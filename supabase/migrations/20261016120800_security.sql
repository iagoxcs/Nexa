-- =============================================================================
-- NEXA LAB — F0-04 — Segurança: RLS e permissões
-- Usuários e perfis não definidos (SPEC Q-19). Política adotada até a definição:
-- RLS habilitado em todas as tabelas, sem policies → anon/authenticated sem acesso;
-- service_role (worker, ETL, backend Next.js) ignora RLS.
-- =============================================================================

grant all on all tables    in schema ops, raw, core to service_role;
grant all on all sequences in schema ops, raw, core to service_role;
grant execute on all functions in schema ops, core to service_role;

revoke all on all tables in schema ops, raw, core from anon, authenticated;
revoke execute on all functions in schema ops, core from public;

do $$
declare
  r record;
begin
  for r in
    select schemaname, tablename
      from pg_tables
     where schemaname in ('ops', 'raw', 'core')
  loop
    execute format('alter table %I.%I enable row level security', r.schemaname, r.tablename);
  end loop;
end;
$$;
