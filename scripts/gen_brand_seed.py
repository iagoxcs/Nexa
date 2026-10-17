#!/usr/bin/env python3
"""Gera supabase/seed/brands.sql a partir de supabase/seed/brands.csv (F0-06).

brands.csv é a fonte da verdade da lista-mãe (SPEC §18). O SQL gerado:
- cria uma ops.source (official_site) por source_base_url distinta;
- cria core.brand com os campos rastreáveis vazios e missing_reason = 'not_collected'
  (nenhum atributo é preenchido sem coleta: G-03);
- vincula marca e fonte em core.brand_source (Fenty Beauty e Fenty Skin compartilham fonte).

Uso: python3 scripts/gen_brand_seed.py
"""
from __future__ import annotations

import csv
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
CSV_PATH = ROOT / "supabase" / "seed" / "brands.csv"
SQL_PATH = ROOT / "supabase" / "seed" / "brands.sql"

# Campos rastreáveis de core.brand (ops.traceable_field). Mantidos em sincronia com
# supabase/migrations/20261016120400_core_brand.sql; o teste tests/sql/02_brands.sql
# falha se algum campo rastreável ficar sem missing_reason.
TRACEABLE = [
    "country", "founded_year", "positioning", "competitive_archetype", "declared_audience",
    "inferred_audience", "sales_channels", "price_tier", "founder_influencer",
    "value_proposition", "declared_differentials", "approx_sku_count",
]


def q(value: str) -> str:
    return "'" + value.replace("'", "''") + "'"


def main() -> None:
    with CSV_PATH.open(encoding="utf-8") as f:
        rows = list(csv.DictReader(f))

    sources: dict[str, list[str]] = {}
    for r in rows:
        sources.setdefault(r["source_base_url"], []).append(r["name"])

    out = [
        "-- =============================================================================",
        "-- NEXA LAB — F0-06 — Lista-mãe de marcas (SPEC §18)",
        "-- GERADO por scripts/gen_brand_seed.py a partir de supabase/seed/brands.csv.",
        "-- Não editar à mão. Idempotente.",
        "-- =============================================================================",
        "",
        "set local nexa.change_origin = 'seed:brands.csv';",
        "",
        "insert into ops.source (type, name, base_url, access_method, notes) values",
    ]
    src_values = []
    for base, names in sources.items():
        label = " / ".join(names)
        note = "Fonte compartilhada por: " + label if len(names) > 1 else None
        src_values.append(
            f"  ('official_site', {q('Site oficial — ' + label)}, {q(base)}, 'pending_review', "
            f"{q(note) if note else 'null'})")
    out.append(",\n".join(src_values))
    out.append("on conflict (base_url) do nothing;")
    out.append("")

    mr_cols = ", ".join(f"{c}_missing_reason" for c in TRACEABLE)
    mr_vals = ", ".join("'not_collected'" for _ in TRACEABLE)
    out.append(f"insert into core.brand (master_list_no, name, official_url, site_region, priority_level, nexa_focus, {mr_cols}) values")
    brand_values = []
    for r in rows:
        brand_values.append(
            f"  ({int(r['master_list_no'])}, {q(r['name'])}, {q(r['official_url'])}, {q(r['site_region'])}, "
            f"{q(r['priority_level'])}, {q(r['nexa_focus'])}, {mr_vals})")
    out.append(",\n".join(brand_values))
    out.append("on conflict (name) do nothing;")
    out.append("")

    out.append("insert into core.brand_source (brand_id, source_id, relation)")
    out.append("select b.id, s.id, 'official_site'")
    out.append("from (values")
    out.append(",\n".join(f"  ({q(r['name'])}, {q(r['source_base_url'])})" for r in rows))
    out.append(") as v(brand_name, base_url)")
    out.append("join core.brand b on b.name = v.brand_name")
    out.append("join ops.source s on s.base_url = v.base_url")
    out.append("on conflict (brand_id, source_id, relation) do nothing;")

    SQL_PATH.write_text("\n".join(out) + "\n", encoding="utf-8")
    print(f"escrito: {SQL_PATH.relative_to(ROOT)} ({len(rows)} marcas, {len(sources)} fontes)")


if __name__ == "__main__":
    main()
