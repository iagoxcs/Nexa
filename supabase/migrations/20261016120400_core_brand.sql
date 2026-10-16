-- =============================================================================
-- NEXA LAB — F0-04 — core: marca
-- SPEC §4.3 core (brand, brand_version), §5.3, §18, G-01, G-04, G-08
-- =============================================================================

create table core.brand (
  id                    uuid primary key default gen_random_uuid(),
  name                  text not null unique,
  official_url          text,
  site_region           text check (site_region in ('BR', 'INTL')),
  priority_level        text not null check (priority_level in ('P1-A', 'P1', 'P2')),
  nexa_focus            text,
  marketplace_presence  jsonb not null default '[]'::jsonb,
  social_handles        jsonb not null default '[]'::jsonb,
  last_collected_at     timestamptz,
  created_at            timestamptz not null default now(),
  updated_at            timestamptz not null default now()
);
comment on table core.brand is 'Marca monitorada. Atributos extraídos/inferidos seguem o padrão rastreável (§4.1). Histórico em core.brand_version.';
comment on column core.brand.name is 'Nome da marca conforme lista-mãe (§18).';
comment on column core.brand.site_region is 'Região do site oficial pelo domínio (BR | INTL), conforme coluna "Origem" da lista-mãe. Não é nacionalidade da empresa (ver country).';
comment on column core.brand.priority_level is 'Nível de prioridade: P1-A | P1 | P2 (§18).';
comment on column core.brand.nexa_focus is 'Motivo do monitoramento definido pelo NEXA (coluna "Foco NEXA" da lista-mãe). Não é atributo da marca.';
comment on column core.brand.marketplace_presence is 'Lista [{source_id, store_url, observed_at, evidence_id}] de presença observada em marketplaces.';
comment on column core.brand.social_handles is 'Lista [{platform, handle, url, observed_at, evidence_id}] de perfis oficiais. Sem métricas de seguidores como proxy de mercado (G-07).';
comment on column core.brand.last_collected_at is 'Data da última coleta bem-sucedida de qualquer fonte da marca.';

select ops.add_traceable_field('core.brand', 'country', 'char(2)', 'País de origem da marca (ISO 3166-1 alfa-2). Coletado, nunca deduzido do domínio (§18, G-03).');
select ops.add_traceable_field('core.brand', 'founded_year', 'smallint check (founded_year between 1800 and 2100)', 'Ano de fundação.');
select ops.add_traceable_field('core.brand', 'positioning', 'text', 'Posicionamento da marca (síntese).');
select ops.add_traceable_field('core.brand', 'competitive_archetype', 'text', 'Arquétipo competitivo. Taxonomia ainda não definida na SPEC.');
select ops.add_traceable_field('core.brand', 'declared_audience', 'text', 'Público declarado pela marca. Sempre is_inferred = false.');
select ops.add_traceable_field('core.brand', 'inferred_audience', 'text', 'Público inferido. Sempre is_inferred = true; geração/idade não inferida por estética (G-08).');
select ops.add_traceable_field('core.brand', 'sales_channels', 'text[]', 'Canais de venda observados (site próprio, marketplace, farmácia, varejo, venda direta...).');
select ops.add_traceable_field('core.brand', 'price_tier', 'text', 'Faixa de preço da marca. Critério de corte ainda não definido na SPEC.');
select ops.add_traceable_field('core.brand', 'founder_influencer', 'text', 'Fundador(a) ou influenciador(a) associado(a) publicamente à marca.');
select ops.add_traceable_field('core.brand', 'value_proposition', 'text', 'Proposta de valor declarada.');
select ops.add_traceable_field('core.brand', 'declared_differentials', 'text[]', 'Diferenciais declarados pela marca (texto da fonte).');
select ops.add_traceable_field('core.brand', 'approx_sku_count', 'integer check (approx_sku_count >= 0)', 'Quantidade aproximada de SKUs observados no site oficial.');

alter table core.brand
  add constraint brand_declared_audience_declared_ck check (declared_audience_is_inferred is distinct from true),
  add constraint brand_inferred_audience_inferred_ck check (inferred_audience_is_inferred is distinct from false);

create trigger brand_set_updated_at before update on core.brand
  for each row execute function ops.set_updated_at();

-- -----------------------------------------------------------------------------
-- core.brand_version — SCD tipo 2 (G-04)
-- -----------------------------------------------------------------------------
create table core.brand_version (
  id              uuid primary key default gen_random_uuid(),
  brand_id        uuid not null references core.brand(id),
  version_no      integer not null check (version_no > 0),
  valid_from      timestamptz not null,
  valid_to        timestamptz,
  snapshot        jsonb not null,
  changed_fields  text[],
  change_origin   text,
  unique (brand_id, version_no),
  check (valid_to is null or valid_to >= valid_from)
);
comment on table core.brand_version is 'Histórico SCD2 de core.brand, preenchido por trigger (ops.capture_version). Versão vigente: valid_to IS NULL.';
comment on column core.brand_version.snapshot is 'Linha completa de core.brand no momento da versão.';
comment on column core.brand_version.changed_fields is 'Colunas alteradas em relação à versão anterior (NULL na primeira versão).';
comment on column core.brand_version.change_origin is 'Origem da alteração (setting nexa.change_origin), ex.: crawl_run:<uuid>, human_review:<uuid>, seed.';

create unique index brand_version_current_uq on core.brand_version (brand_id) where valid_to is null;

create trigger brand_capture_version after insert or update on core.brand
  for each row execute function ops.capture_version('core.brand_version', 'brand_id');
create trigger brand_no_delete before delete on core.brand
  for each row execute function ops.forbid_delete();

-- -----------------------------------------------------------------------------
-- core.brand_source — vínculo marca × fonte (N:N)
-- -----------------------------------------------------------------------------
create table core.brand_source (
  id          uuid primary key default gen_random_uuid(),
  brand_id    uuid not null references core.brand(id),
  source_id   uuid not null references ops.source(id),
  relation    text not null check (relation in ('official_site', 'official_store', 'marketplace_store', 'social_profile', 'other')),
  created_at  timestamptz not null default now(),
  unique (brand_id, source_id, relation)
);
comment on table core.brand_source is 'Vínculo N:N entre marca e fonte. Resolve fontes compartilhadas (ex.: Fenty Beauty e Fenty Skin em fentybeauty.com, §18).';
comment on column core.brand_source.relation is 'official_site | official_store | marketplace_store | social_profile | other.';

create index brand_source_source_idx on core.brand_source (source_id);
