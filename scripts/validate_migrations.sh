#!/usr/bin/env bash
# Aplica migrations + seeds em um banco PostgreSQL descartável e executa testes de constraint.
# Uso: PGHOST=localhost PGPORT=5432 PGUSER=postgres scripts/validate_migrations.sh
# (variáveis padrão do libpq; o script cria e remove um banco temporário)
#
# Em Postgres local sem pgvector/pg_cron, as linhas de extensão são ignoradas
# (no Supabase as duas extensões estão disponíveis).
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
DB="nexa_validate_$$"
ADMIN_URL="${PGDATABASE:-postgres}"
TARGET_URL="$DB"

psql -d "$ADMIN_URL" -qX -v ON_ERROR_STOP=1 -c "create database $DB"
trap 'psql -d "$ADMIN_URL" -qX -c "drop database if exists $DB" >/dev/null' EXIT

psql -d "$TARGET_URL" -qX -v ON_ERROR_STOP=1 <<'SQL'
create schema if not exists extensions;
do $$
begin
  if not exists (select 1 from pg_roles where rolname = 'anon') then create role anon nologin; end if;
  if not exists (select 1 from pg_roles where rolname = 'authenticated') then create role authenticated nologin; end if;
  if not exists (select 1 from pg_roles where rolname = 'service_role') then create role service_role nologin bypassrls; end if;
end $$;
SQL

has_ext() { psql -d "$TARGET_URL" -AtqX -c "select count(*) from pg_available_extensions where name = '$1'"; }

for f in "$ROOT"/supabase/migrations/*.sql; do
  echo "migration: $(basename "$f")"
  sql="$(cat "$f")"
  [[ "$(has_ext vector)" == "0" ]] && sql="$(sed -E '/create extension if not exists vector/d' <<<"$sql")"
  [[ "$(has_ext pg_cron)" == "0" ]] && sql="$(sed -E '/create extension if not exists pg_cron/d' <<<"$sql")"
  psql -d "$TARGET_URL" -qX -v ON_ERROR_STOP=1 -1 -o /dev/null <<<"$sql"
done

for f in "$ROOT"/supabase/seed/taxonomies/*.sql; do
  echo "seed: $(basename "$f")"
  psql -d "$TARGET_URL" -qX -v ON_ERROR_STOP=1 -1 -f "$f"
done

if [[ "${DUMP_TO:-}" != "" ]]; then
  # Cópia do banco com schema + seeds (antes dos testes) para gerar o dicionário de dados.
  psql -d "$ADMIN_URL" -qX -c "drop database if exists $DUMP_TO" -c "create database $DUMP_TO template $DB"
fi

echo "testes: tests/sql/*.sql"
for f in "$ROOT"/tests/sql/*.sql; do
  echo "  $(basename "$f")"
  psql -d "$TARGET_URL" -qX -v ON_ERROR_STOP=1 -1 -f "$f"
done

echo "OK"
