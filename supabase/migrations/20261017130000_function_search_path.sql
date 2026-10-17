-- =============================================================================
-- NEXA LAB — Segurança: search_path fixo nas funções (advisor Supabase 0011)
-- Todas as referências dentro das funções já são qualificadas por schema;
-- pg_catalog continua resolvido implicitamente.
-- =============================================================================

alter function ops.set_updated_at() set search_path = '';
alter function ops.forbid_update() set search_path = '';
alter function ops.forbid_delete() set search_path = '';
alter function ops.capture_version() set search_path = '';
alter function ops.add_traceable_field(regclass, text, text, text) set search_path = '';
alter function core.compute_unit_price() set search_path = '';
