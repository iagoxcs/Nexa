-- =============================================================================
-- NEXA LAB — F0-04 — Fundação: extensões, schemas, permissões e funções utilitárias
-- SPEC §4.1, §4.2, G-01, G-03, G-04, G-10, A-07
-- =============================================================================

-- DEC-01: Supabase (PostgreSQL + pgvector + pg_cron).
-- pgvector é habilitado, mas nenhuma coluna de embedding é criada: a dimensão
-- depende do modelo a ser definido por benchmark (DEC-07, Fase 1).
create extension if not exists vector with schema extensions;
create extension if not exists pg_cron;

-- -----------------------------------------------------------------------------
-- Schemas (§4.2). analytics, finance e council ficam para migrations posteriores.
-- -----------------------------------------------------------------------------
create schema if not exists ops;
create schema if not exists raw;
create schema if not exists core;

comment on schema ops  is 'Operação: fontes, jobs, logs de coleta, custos, cobertura e revisões humanas (SPEC §4.3 ops).';
comment on schema raw  is 'Documentos brutos imutáveis: HTML/JSON/respostas de API, com hash e caminho no Storage (SPEC §4.3 raw).';
comment on schema core is 'Entidades normalizadas, rastreáveis e versionadas (SPEC §4.3 core).';

-- Single-tenant (A-07). Usuários além de Iago/Thaís não definidos (Q-19):
-- apenas service_role acessa os schemas. anon/authenticated recebem acesso
-- somente após definição de RLS por perfil.
grant usage on schema ops, raw, core to service_role;
alter default privileges in schema ops  grant all on tables    to service_role;
alter default privileges in schema raw  grant all on tables    to service_role;
alter default privileges in schema core grant all on tables    to service_role;
alter default privileges in schema ops  grant all on sequences to service_role;
alter default privileges in schema raw  grant all on sequences to service_role;
alter default privileges in schema core grant all on sequences to service_role;
alter default privileges in schema ops  grant execute on functions to service_role;

-- -----------------------------------------------------------------------------
-- Funções de trigger genéricas
-- -----------------------------------------------------------------------------

create or replace function ops.set_updated_at()
returns trigger
language plpgsql
as $$
begin
  new.updated_at := now();
  return new;
end;
$$;
comment on function ops.set_updated_at() is 'Trigger BEFORE UPDATE: mantém updated_at.';

-- Bloqueia UPDATE em tabelas append-only/imutáveis. Argumentos do trigger
-- (TG_ARGV) listam as únicas colunas que podem mudar.
create or replace function ops.forbid_update()
returns trigger
language plpgsql
as $$
declare
  v_allowed text[] := coalesce(tg_argv::text[], '{}');
begin
  if (to_jsonb(new) - v_allowed) is distinct from (to_jsonb(old) - v_allowed) then
    raise exception '%.% é imutável (append-only). Colunas alteráveis: %',
      tg_table_schema, tg_table_name, v_allowed
      using errcode = 'restrict_violation';
  end if;
  return new;
end;
$$;
comment on function ops.forbid_update() is
  'Trigger BEFORE UPDATE: rejeita alteração em tabela imutável, exceto colunas passadas como argumento (G-02, G-10).';

create or replace function ops.forbid_delete()
returns trigger
language plpgsql
as $$
begin
  raise exception 'DELETE proibido em %.% (G-04: histórico nunca é apagado; use status/valid_to)',
    tg_table_schema, tg_table_name
    using errcode = 'restrict_violation';
end;
$$;
comment on function ops.forbid_delete() is 'Trigger BEFORE DELETE: impede exclusão física de entidades versionadas (G-04).';

-- Versionamento SCD tipo 2 por snapshot (G-04, §4.4).
-- TG_ARGV[0] = tabela de versão (schema.tabela); TG_ARGV[1] = coluna FK na tabela de versão.
-- Colunas de controle de coleta (updated_at, last_seen_at, last_collected_at,
-- consecutive_misses) não geram nova versão.
-- A origem da alteração é lida de current_setting('nexa.change_origin'),
-- ex.: 'crawl_run:<uuid>', 'human_review:<uuid>', 'seed'.
create or replace function ops.capture_version()
returns trigger
language plpgsql
as $$
declare
  v_table   text := tg_argv[0];
  v_fk      text := tg_argv[1];
  v_ignore  text[] := array['updated_at', 'last_seen_at', 'last_collected_at', 'consecutive_misses'];
  v_new     jsonb := to_jsonb(new);
  v_old     jsonb;
  v_changed text[];
  v_now     timestamptz := clock_timestamp();
begin
  if tg_op = 'UPDATE' then
    v_old := to_jsonb(old);
    if (v_new - v_ignore) = (v_old - v_ignore) then
      return new;
    end if;
    select array_agg(n.key order by n.key)
      into v_changed
      from jsonb_each(v_new - v_ignore) n
     where n.value is distinct from v_old -> n.key;
  end if;

  execute format('update %s set valid_to = $1 where %I = $2 and valid_to is null', v_table, v_fk)
    using v_now, new.id;

  execute format(
    'insert into %1$s (%2$I, version_no, valid_from, snapshot, changed_fields, change_origin)
     select $1, coalesce(max(version_no), 0) + 1, $2, $3, $4, $5 from %1$s where %2$I = $1',
    v_table, v_fk)
    using new.id, v_now, v_new, v_changed, nullif(current_setting('nexa.change_origin', true), '');

  return new;
end;
$$;
comment on function ops.capture_version() is
  'Trigger AFTER INSERT OR UPDATE: grava snapshot jsonb da linha na tabela de versão (SCD2), fecha a versão anterior e registra campos alterados (G-04).';

-- -----------------------------------------------------------------------------
-- Padrão de campo rastreável (§4.1 + G-01 + G-03)
-- -----------------------------------------------------------------------------

create table ops.traceable_field (
  table_schema text not null,
  table_name   text not null,
  column_name  text not null,
  data_type    text not null,
  description  text,
  created_at   timestamptz not null default now(),
  primary key (table_schema, table_name, column_name)
);
comment on table ops.traceable_field is
  'Registro dos atributos criados com ops.add_traceable_field(). Base para relatório de completude por campo (AC-01, AC-09).';

-- Cria, para um atributo <c>, as colunas:
--   <c>                 valor
--   <c>_is_inferred     true se não declarado pela fonte (G-01)
--   <c>_confidence      0.00–1.00
--   <c>_evidence_id     FK core.evidence (G-02)
--   <c>_missing_reason  motivo da ausência quando <c> é NULL (G-03, G-09)
-- e as constraints:
--   valor presente  ⇒ is_inferred, confidence e evidence_id obrigatórios
--   valor ausente   ⇔ missing_reason preenchido
create or replace function ops.add_traceable_field(
  p_table   regclass,
  p_column  text,
  p_type    text,
  p_comment text default null
)
returns void
language plpgsql
as $$
declare
  v_schema text;
  v_name   text;
begin
  select n.nspname, c.relname into v_schema, v_name
    from pg_class c join pg_namespace n on n.oid = c.relnamespace
   where c.oid = p_table;

  execute format(
    'alter table %1$s
       add column %2$I %3$s,
       add column %4$I boolean,
       add column %5$I numeric(3,2),
       add column %6$I uuid references core.evidence(id),
       add column %7$I text',
    p_table, p_column, p_type,
    p_column || '_is_inferred', p_column || '_confidence',
    p_column || '_evidence_id', p_column || '_missing_reason');

  execute format('alter table %s add constraint %I check (%I between 0 and 1)',
    p_table, v_name || '_' || p_column || '_conf_ck', p_column || '_confidence');

  execute format(
    'alter table %s add constraint %I check (%I is null or (%I is not null and %I is not null and %I is not null))',
    p_table, v_name || '_' || p_column || '_trace_ck',
    p_column, p_column || '_is_inferred', p_column || '_confidence', p_column || '_evidence_id');

  execute format(
    'alter table %s add constraint %I check ((%I is null) = (%I is not null))',
    p_table, v_name || '_' || p_column || '_missing_ck', p_column, p_column || '_missing_reason');

  execute format(
    'alter table %s add constraint %I check (%I in (''not_collected'', ''not_published'', ''source_blocked'', ''parse_error'', ''low_confidence'', ''ambiguous'', ''not_applicable''))',
    p_table, v_name || '_' || p_column || '_mr_ck', p_column || '_missing_reason');

  execute format('comment on column %s.%I is %L', p_table, p_column, coalesce(p_comment, 'Atributo rastreável (§4.1).'));
  execute format('comment on column %s.%I is %L', p_table, p_column || '_is_inferred',
    'Rastreio de ' || p_column || ': true se o valor não foi declarado pela fonte (G-01).');
  execute format('comment on column %s.%I is %L', p_table, p_column || '_confidence',
    'Rastreio de ' || p_column || ': confiança 0.00–1.00 da extração/inferência.');
  execute format('comment on column %s.%I is %L', p_table, p_column || '_evidence_id',
    'Rastreio de ' || p_column || ': FK core.evidence com o trecho que sustenta o valor (G-02).');
  execute format('comment on column %s.%I is %L', p_table, p_column || '_missing_reason',
    'Rastreio de ' || p_column || ': motivo da ausência (not_collected | not_published | source_blocked | parse_error | low_confidence | ambiguous | not_applicable). Obrigatório quando o valor é NULL (G-03, G-09).');

  insert into ops.traceable_field (table_schema, table_name, column_name, data_type, description)
  values (v_schema, v_name, p_column, p_type, p_comment);
end;
$$;
comment on function ops.add_traceable_field(regclass, text, text, text) is
  'Aplica o padrão de campo rastreável (§4.1) + missing_reason (G-03) a uma coluna e registra em ops.traceable_field.';
