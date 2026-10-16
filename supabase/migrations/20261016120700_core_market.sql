-- =============================================================================
-- NEXA LAB — F0-04 — core: market share (Módulo C)
-- SPEC §4.3 core (market share), §7, G-07, G-11
-- =============================================================================

create table core.market_size (
  id                     uuid primary key default gen_random_uuid(),
  category_id            uuid references core.category(id),
  subcategory_id         uuid,
  channel                text,
  uf                     char(2),
  municipality_or_region text,
  period_start           date not null,
  period_end             date not null,
  revenue                numeric(18,2) check (revenue >= 0),
  units                  numeric(18,0) check (units >= 0),
  currency               char(3) not null default 'BRL',
  universe_definition    text not null,
  scope                  text,
  sell_type              text check (sell_type in ('sell_in', 'sell_out')),
  status                 text not null check (status in ('observed', 'estimated', 'unavailable')),
  method                 text,
  assumptions            text,
  range_min              numeric(18,2),
  range_max              numeric(18,2),
  confidence             numeric(3,2) check (confidence between 0 and 1),
  source                 text,
  source_id              uuid references ops.source(id),
  base_year              smallint check (base_year between 1990 and 2100),
  evidence_ids           uuid[] not null default '{}',
  data_acquisition_plan  text,
  created_at             timestamptz not null default now(),
  constraint market_size_subcategory_category_fk
    foreign key (subcategory_id, category_id) references core.subcategory(id, category_id),
  check (period_end >= period_start),
  check (uf in ('AC','AL','AP','AM','BA','CE','DF','ES','GO','MA','MT','MS','MG','PA','PB','PR','PE','PI','RJ','RN','RS','RO','RR','SC','SP','SE','TO')),
  check (range_min is null or range_max is null or range_min <= range_max),
  -- G-11: estados distintos e coerentes
  constraint market_size_unavailable_ck check (
    status <> 'unavailable' or (revenue is null and units is null and data_acquisition_plan is not null)),
  constraint market_size_available_ck check (
    status = 'unavailable' or ((revenue is not null or units is not null) and source is not null and sell_type is not null)),
  constraint market_size_estimated_ck check (
    status <> 'estimated' or (method is not null and assumptions is not null and range_min is not null and range_max is not null and confidence is not null))
);
comment on table core.market_size is 'Tamanho de mercado por recorte (categoria, território, canal, período, universo). Denominador do share (§7.1).';
comment on column core.market_size.uf is 'UF (sigla). NULL = Brasil.';
comment on column core.market_size.channel is 'Canal do recorte. Vocabulário de canais ainda não definido na SPEC.';
comment on column core.market_size.universe_definition is 'Definição explícita do universo medido (obrigatória, §7.1).';
comment on column core.market_size.status is 'observed | estimated | unavailable — estados distintos (G-11).';
comment on column core.market_size.data_acquisition_plan is 'Plano de aquisição de dados quando status = unavailable (§7.5 "DADOS INSUFICIENTES").';
comment on column core.market_size.evidence_ids is 'Evidências (core.evidence) que sustentam o registro.';

create table core.market_share_estimate (
  id                         uuid primary key default gen_random_uuid(),
  brand_id                   uuid not null references core.brand(id),
  product_id                 uuid references core.product(id),
  market_size_id             uuid references core.market_size(id),
  category_id                uuid references core.category(id),
  subcategory_id             uuid,
  channel                    text,
  uf                         char(2),
  municipality_or_region     text,
  period_start               date not null,
  period_end                 date not null,
  universe_definition        text not null,
  revenue_value              numeric(18,2) check (revenue_value >= 0),
  units_value                numeric(18,0) check (units_value >= 0),
  share_value_pct            numeric(6,3) check (share_value_pct between 0 and 100),
  share_volume_pct           numeric(6,3) check (share_volume_pct between 0 and 100),
  status                     text not null check (status in ('observed', 'estimated', 'unavailable')),
  sell_type                  text check (sell_type in ('sell_in', 'sell_out')),
  method                     text,
  inputs                     text[] not null default '{}',
  assumptions                text,
  bias_notes                 text,
  coverage_notes             text,
  range_min                  numeric(6,3) check (range_min between 0 and 100),
  range_max                  numeric(6,3) check (range_max between 0 and 100),
  confidence                 numeric(3,2) check (confidence between 0 and 1),
  comparability_restrictions text,
  source                     text,
  source_id                  uuid references ops.source(id),
  base_year                  smallint check (base_year between 1990 and 2100),
  evidence_ids               uuid[] not null default '{}',
  data_acquisition_plan      text,
  created_at                 timestamptz not null default now(),
  constraint market_share_subcategory_category_fk
    foreign key (subcategory_id, category_id) references core.subcategory(id, category_id),
  check (period_end >= period_start),
  check (uf in ('AC','AL','AP','AM','BA','CE','DF','ES','GO','MA','MT','MS','MG','PA','PB','PR','PE','PI','RJ','RN','RS','RO','RR','SC','SP','SE','TO')),
  check (range_min is null or range_max is null or range_min <= range_max),
  -- G-07: seguidores, curtidas, buscas e tráfego não são insumos válidos de estimativa.
  constraint market_share_inputs_ck check (inputs <@ array[
    'company_disclosure', 'association_report', 'licensed_report', 'retailer_data', 'platform_sales_rank',
    'published_revenue_range', 'retail_distribution', 'public_trade_data', 'panel_sample', 'public_demand_indicator']),
  -- G-11: estados distintos e coerentes
  constraint market_share_unavailable_ck check (
    status <> 'unavailable' or (share_value_pct is null and share_volume_pct is null
                                and revenue_value is null and units_value is null and data_acquisition_plan is not null)),
  constraint market_share_available_ck check (
    status = 'unavailable' or ((share_value_pct is not null or share_volume_pct is not null) and source is not null and sell_type is not null)),
  constraint market_share_estimated_ck check (
    status <> 'estimated' or (method is not null and cardinality(inputs) > 0 and assumptions is not null and bias_notes is not null
                              and coverage_notes is not null and range_min is not null and range_max is not null and confidence is not null))
);
comment on table core.market_share_estimate is 'Share de marca/produto por recorte. Estimativa nunca rotulada como share confirmado (G-11). Sinais digitais não são vendas (G-07).';
comment on column core.market_share_estimate.market_size_id is 'Registro de core.market_size usado como denominador, quando aplicável.';
comment on column core.market_share_estimate.share_value_pct is 'Receita da marca no recorte ÷ receita total do mesmo recorte × 100 (§7.1).';
comment on column core.market_share_estimate.share_volume_pct is 'Unidades da marca no recorte ÷ unidades totais do mesmo recorte × 100 (§7.1).';
comment on column core.market_share_estimate.inputs is
  'Insumos da estimativa (§7.3): company_disclosure | association_report | licensed_report | retailer_data | platform_sales_rank | published_revenue_range | retail_distribution | public_trade_data | panel_sample | public_demand_indicator. Seguidores, avaliações, buscas e tráfego são bloqueados (G-07).';
comment on column core.market_share_estimate.range_min is 'Limite inferior do intervalo de share (%), obrigatório se estimated.';
comment on column core.market_share_estimate.range_max is 'Limite superior do intervalo de share (%), obrigatório se estimated.';
comment on column core.market_share_estimate.data_acquisition_plan is 'Plano de aquisição quando status = unavailable (§7.5).';

create index market_share_brand_idx on core.market_share_estimate (brand_id, period_start);
create index market_share_cut_idx on core.market_share_estimate (category_id, subcategory_id, uf, channel, period_start);
