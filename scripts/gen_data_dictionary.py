#!/usr/bin/env python3
"""Gera docs/data-dictionary.md a partir das migrations (F0-05).

Aplica migrations + seeds em banco descartável (scripts/validate_migrations.sh,
com DUMP_TO) e lê o catálogo do PostgreSQL: colunas, comentários, constraints,
índices, triggers, funções e conteúdo das taxonomias.

Uso: PGHOST=... PGPORT=... PGUSER=... python3 scripts/gen_data_dictionary.py
"""
from __future__ import annotations

import json
import re
import os
import subprocess
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
OUT = ROOT / "docs" / "data-dictionary.md"
SCHEMAS = ("ops", "raw", "core")
DICT_DB = "nexa_data_dictionary"
TRACE_SUFFIXES = ("_is_inferred", "_confidence", "_evidence_id", "_missing_reason")

CATALOG_SQL = """
with t as (
  select c.oid, n.nspname as schema, c.relname as name, obj_description(c.oid, 'pg_class') as comment
  from pg_class c join pg_namespace n on n.oid = c.relnamespace
  where c.relkind = 'r' and n.nspname = any(%(schemas)s)
)
select json_build_object(
  'tables', (select json_agg(json_build_object(
      'schema', t.schema, 'name', t.name, 'comment', t.comment,
      'columns', (select json_agg(json_build_object(
          'name', a.attname,
          'type', format_type(a.atttypid, a.atttypmod),
          'not_null', a.attnotnull,
          'default', pg_get_expr(d.adbin, d.adrelid),
          'comment', col_description(t.oid, a.attnum)) order by a.attnum)
        from pg_attribute a left join pg_attrdef d on d.adrelid = a.attrelid and d.adnum = a.attnum
        where a.attrelid = t.oid and a.attnum > 0 and not a.attisdropped),
      'constraints', (select json_agg(json_build_object(
          'name', co.conname, 'type', co.contype, 'def', pg_get_constraintdef(co.oid)) order by co.contype, co.conname)
        from pg_constraint co where co.conrelid = t.oid),
      'indexes', (select json_agg(json_build_object('name', i.indexname, 'def', i.indexdef) order by i.indexname)
        from pg_indexes i where i.schemaname = t.schema and i.tablename = t.name
          and i.indexname not in (select conname from pg_constraint where conrelid = t.oid)),
      'triggers', (select json_agg(json_build_object('name', tg.tgname, 'def', pg_get_triggerdef(tg.oid)) order by tg.tgname)
        from pg_trigger tg where tg.tgrelid = t.oid and not tg.tgisinternal),
      'rls', (select relrowsecurity from pg_class where oid = t.oid)
    ) order by t.schema, t.name) from t),
  'traceable', (select json_agg(json_build_object(
      'table', table_schema || '.' || table_name, 'column', column_name, 'type', data_type)
      order by table_schema, table_name, column_name) from ops.traceable_field),
  'functions', (select json_agg(json_build_object(
      'name', n.nspname || '.' || p.proname || '(' || pg_get_function_identity_arguments(p.oid) || ')',
      'comment', obj_description(p.oid, 'pg_proc')) order by n.nspname, p.proname)
    from pg_proc p join pg_namespace n on n.oid = p.pronamespace where n.nspname = any(%(schemas)s)),
  'taxonomies', json_build_object(
    'category', (select json_agg(json_build_object('code', code, 'name', name_pt, 'description', description) order by sort_order) from core.category),
    'subcategory', (select json_agg(json_build_object('category', c.code, 'code', s.code, 'name', s.name_pt, 'description', s.description)
                     order by c.sort_order, s.sort_order) from core.subcategory s join core.category c on c.id = s.category_id),
    'format', (select json_agg(json_build_object('group', format_group, 'code', code, 'name', name_pt, 'description', description) order by sort_order) from core.format),
    'benefit', (select json_agg(json_build_object('group', benefit_group, 'code', code, 'name', name_pt, 'description', description) order by sort_order) from core.benefit),
    'voice_type', (select json_agg(json_build_object('code', code, 'name', name_pt, 'description', description) order by sort_order) from core.voice_type),
    'signal_phrase', (select json_agg(json_build_object('phrase', p.phrase_pattern, 'voice', v.code, 'notes', p.notes) order by p.notes desc, p.phrase_pattern)
                       from core.signal_phrase p left join core.voice_type v on v.id = p.suggested_voice_type_id),
    'trend_class', (select json_agg(json_build_object('code', code, 'name', name_pt, 'description', description) order by sort_order) from core.trend_class)
  )
)
"""

SCHEMA_TITLES = {
    "ops": "Schema `ops` — operação",
    "raw": "Schema `raw` — documentos brutos",
    "core": "Schema `core` — entidades normalizadas",
}
CONTYPE = {"p": "PK", "f": "FK", "u": "UNIQUE", "c": "CHECK", "x": "EXCLUDE"}
STANDARD_COMMENTS = {
    "id": "Chave primária (UUID).",
    "created_at": "Data/hora de criação do registro.",
    "updated_at": "Data/hora da última alteração (trigger ops.set_updated_at).",
    "valid_from": "Início de vigência (SCD2).",
    "valid_to": "Fim de vigência (SCD2). NULL = vigente.",
    "version_no": "Número sequencial da versão.",
    "code": "Código estável (slug) usado em seeds, filtros e integrações.",
    "name_pt": "Nome de exibição em pt-BR.",
    "sort_order": "Ordem de exibição.",
    "active": "Item ativo para uso.",
}
FK_RE = re.compile(r"^FOREIGN KEY \((\w+)\) REFERENCES ([\w.]+)\(")


def psql(db: str, sql: str) -> str:
    return subprocess.run(
        ["psql", "-d", db, "-AtqX", "-v", "ON_ERROR_STOP=1", "-c", sql],
        check=True, capture_output=True, text=True,
    ).stdout


def esc(text: str | None) -> str:
    return (text or "").replace("|", "\\|").replace("\n", " ")


def render(cat: dict, migrations: list[str]) -> str:
    traceable = {(t["table"], t["column"]) for t in cat["traceable"] or []}
    out: list[str] = []
    w = out.append

    w("# NEXA LAB — Dicionário de dados\n")
    w("> **Gerado automaticamente** por `scripts/gen_data_dictionary.py` a partir de `supabase/migrations/` "
      "e `supabase/seed/taxonomies/`. Não editar à mão: altere a migration/seed e regenere.\n")
    w("Migrations aplicadas:\n")
    for m in migrations:
        w(f"- `{m}`")
    w("")

    w("## Convenções\n")
    w("### Campo rastreável (SPEC §4.1 + G-01 + G-03)\n")
    w("Colunas marcadas com **[R]** foram criadas por `ops.add_traceable_field()` e possuem quatro colunas auxiliares, "
      "omitidas das tabelas abaixo para legibilidade:\n")
    w("| Coluna auxiliar | Tipo | Regra |")
    w("|---|---|---|")
    w("| `<campo>_is_inferred` | boolean | `true` se o valor não foi declarado pela fonte |")
    w("| `<campo>_confidence` | numeric(3,2) | 0.00–1.00 |")
    w("| `<campo>_evidence_id` | uuid → `core.evidence` | trecho que sustenta o valor |")
    w("| `<campo>_missing_reason` | text | motivo da ausência |")
    w("")
    w("Constraints aplicadas a cada campo rastreável:\n")
    w("- valor preenchido ⇒ `is_inferred`, `confidence` e `evidence_id` obrigatórios (G-01, G-02);")
    w("- valor `NULL` ⇔ `missing_reason` preenchido (G-03, G-09);")
    w("- `missing_reason` ∈ `not_collected` · `not_published` · `source_blocked` · `parse_error` · `low_confidence` · `ambiguous` · `not_applicable`. "
      "`not_collected` (não tentado) é distinto de `not_published` (fonte acessada, informação inexistente).\n")
    w("Atributos multivalorados (ingredientes, claims, benefícios) usam rastreio por linha: `evidence_id NOT NULL` + `confidence` (+ `is_inferred`).\n")
    w("### Versionamento (G-04)\n")
    w("- `brand`, `product`, `product_variant` e `packaging`: SCD tipo 2 por snapshot jsonb em `<entidade>_version`, "
      "preenchido pelo trigger `ops.capture_version()`; `DELETE` bloqueado. Colunas de controle de coleta "
      "(`updated_at`, `last_seen_at`, `last_collected_at`, `consecutive_misses`) não geram versão. "
      "A origem da alteração é gravada a partir de `set local nexa.change_origin = '...'`.")
    w("- `product_ingredient`, `claim`, `product_benefit`: SCD2 inline (`valid_from`/`valid_to`); vigente = `valid_to IS NULL`.")
    w("- `signal_classification`: reclassificação preenche `superseded_at` e insere nova linha.")
    w("- Imutáveis (trigger `ops.forbid_update`): `raw.raw_document` (exceto `last_fetched_at`, `fetch_count`), `core.evidence`, "
      "`ops.crawl_log`, `ops.human_review` (exceto `applied_to_rules`, `applied_at`), `core.consumer_signal` (exceto vínculos de marca/produto).\n")
    w("### Segurança\n")
    w("RLS habilitado em todas as tabelas, sem policies: apenas `service_role` acessa (usuários/perfis pendentes — SPEC Q-19). "
      "Os schemas `ops`, `raw` e `core` não são expostos pela API REST do Supabase até configuração explícita.\n")

    tables = cat["tables"] or []
    for schema in SCHEMAS:
        w(f"## {SCHEMA_TITLES[schema]}\n")
        for t in [t for t in tables if t["schema"] == schema]:
            fq = f"{t['schema']}.{t['name']}"
            w(f"### `{fq}`\n")
            if t["comment"]:
                w(f"{t['comment']}\n")
            base_cols = {c["name"] for c in t["columns"]}
            fks = {m.group(1): m.group(2) for c in (t["constraints"] or []) if c["type"] == "f"
                   for m in [FK_RE.match(c["def"])] if m}
            w("| Coluna | Tipo | Nulo | Default | Descrição |")
            w("|---|---|---|---|---|")
            for c in t["columns"]:
                name = c["name"]
                if any(name.endswith(s) and name[: -len(s)] in base_cols and (fq, name[: -len(s)]) in traceable
                       for s in TRACE_SUFFIXES):
                    continue
                mark = " **[R]**" if (fq, name) in traceable else ""
                comment = c["comment"] or STANDARD_COMMENTS.get(name) or (f"FK → `{fks[name]}`." if name in fks else "")
                if c["comment"] and name in fks:
                    comment = f"FK → `{fks[name]}`. {comment}"
                w(f"| `{name}`{mark} | {esc(c['type'])} | {'não' if c['not_null'] else 'sim'} | "
                  f"{esc(c['default']) and '`' + esc(c['default']) + '`'} | {esc(comment)} |")
            w("")
            cons = [c for c in (t["constraints"] or [])
                    if not any(c["name"].endswith(s) for s in ("_conf_ck", "_trace_ck", "_missing_ck", "_mr_ck"))
                    and not (c["type"] == "f" and c["name"].endswith("_evidence_id_fkey")
                             and (fq, c["name"][len(t["name"]) + 1: -len("_evidence_id_fkey")]) in traceable)]
            if cons:
                w("<details><summary>Constraints</summary>\n")
                for c in cons:
                    w(f"- **{CONTYPE.get(c['type'], c['type'])}** `{c['name']}`: `{esc(c['def'])}`")
                w("\n</details>\n")
            extras = [("Índices", t["indexes"]), ("Triggers", t["triggers"])]
            for label, items in extras:
                if items:
                    w(f"<details><summary>{label}</summary>\n")
                    for i in items:
                        w(f"- `{i['name']}`: `{esc(i['def'])}`")
                    w("\n</details>\n")

    w("## Funções\n")
    w("| Função | Descrição |")
    w("|---|---|")
    for f in cat["functions"] or []:
        w(f"| `{esc(f['name'])}` | {esc(f['comment'])} |")
    w("")

    w("## Campos rastreáveis registrados (`ops.traceable_field`)\n")
    w("| Tabela | Coluna | Tipo |")
    w("|---|---|---|")
    for tr in cat["traceable"] or []:
        w(f"| `{tr['table']}` | `{tr['column']}` | {esc(tr['type'])} |")
    w("")

    tax = cat["taxonomies"]
    w("## Anexo — Taxonomias semeadas (F0-03, v1.0 validada em 16/10/2026)\n")
    w("### Categoria e subcategoria\n")
    w("| Categoria | Código subcategoria | Nome | Descrição |")
    w("|---|---|---|---|")
    for s in tax["subcategory"] or []:
        w(f"| `{s['category']}` | `{s['code']}` | {esc(s['name'])} | {esc(s['description'])} |")
    w("")
    for key, title, has_group in (("format", "Formato", True), ("benefit", "Benefício", True),
                                  ("voice_type", "Voz do consumidor (§6.2)", False),
                                  ("trend_class", "Classificação de tendência (§8)", False)):
        w(f"### {title}\n")
        w(("| Grupo " if has_group else "") + "| Código | Nome | Descrição |")
        w(("|---" if has_group else "") + "|---|---|---|")
        for r in tax[key] or []:
            w((f"| {r['group']} " if has_group else "") + f"| `{r['code']}` | {esc(r['name'])} | {esc(r['description'])} |")
        w("")
    w("### Frases-sinal\n")
    w("| Padrão | Tipo de voz sugerido | Origem |")
    w("|---|---|---|")
    for r in tax["signal_phrase"] or []:
        w(f"| \"{esc(r['phrase'])}…\" | `{r['voice']}` | {esc(r['notes'])} |")
    w("")
    return "\n".join(out)


def main() -> int:
    env = dict(os.environ, DUMP_TO=DICT_DB)
    subprocess.run([str(ROOT / "scripts" / "validate_migrations.sh")], check=True, env=env,
                   stdout=subprocess.DEVNULL)
    try:
        sql = CATALOG_SQL.replace("%(schemas)s", "array[" + ",".join(f"'{s}'" for s in SCHEMAS) + "]")
        cat = json.loads(psql(DICT_DB, sql))
    finally:
        psql(os.environ.get("PGDATABASE", "postgres"), f"drop database if exists {DICT_DB}")
    migrations = sorted(p.name for p in (ROOT / "supabase" / "migrations").glob("*.sql"))
    OUT.write_text(render(cat, migrations) + "\n", encoding="utf-8")
    print(f"escrito: {OUT.relative_to(ROOT)}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
