-- =============================================================================
-- NEXA LAB — F0-04 — core: produto, variante, preço, composição, claims,
-- benefícios, embalagem, avaliações e ativos tecnológicos
-- SPEC §4.3 core, §4.4, §5.3, G-01..G-06, AC-03, AC-05
-- =============================================================================

-- -----------------------------------------------------------------------------
-- core.product
-- -----------------------------------------------------------------------------
create table core.product (
  id                  uuid primary key default gen_random_uuid(),
  brand_id            uuid not null references core.brand(id),
  canonical_name      text not null,
  url                 text,
  primary_source_id   uuid references ops.source(id),
  dedup_key           text not null unique,
  first_seen_at       timestamptz not null default now(),
  last_seen_at        timestamptz not null default now(),
  consecutive_misses  smallint not null default 0 check (consecutive_misses >= 0),
  created_at          timestamptz not null default now(),
  updated_at          timestamptz not null default now(),
  check (last_seen_at >= first_seen_at)
);
comment on table core.product is 'Produto deduplicado (§4.4). Variantes de volume/tom em core.product_variant. Histórico em core.product_version.';
comment on column core.product.canonical_name is 'Nome canônico normalizado do produto, conforme publicado pela marca.';
comment on column core.product.url is 'URL da página oficial do produto.';
comment on column core.product.dedup_key is 'Normalização de (marca + nome canônico + formato + volume). Similaridade de embedding complementa na Fase 1 (DEC-07).';
comment on column core.product.first_seen_at is 'Primeira coleta em que o produto foi observado. Base do alerta "novo lançamento" (§12).';
comment on column core.product.consecutive_misses is 'Coletas consecutivas sem encontrar o produto. Acima de N → candidato a status discontinued inferido (§4.4).';

select ops.add_traceable_field('core.product', 'category_id', 'uuid references core.category(id)', 'Categoria (taxonomia core.category).');
select ops.add_traceable_field('core.product', 'subcategory_id', 'uuid', 'Subcategoria (taxonomia core.subcategory), coerente com category_id.');
select ops.add_traceable_field('core.product', 'format_id', 'uuid references core.format(id)', 'Formato físico (taxonomia core.format).');
select ops.add_traceable_field('core.product', 'status', 'text check (status in (''launch'', ''permanent'', ''limited'', ''discontinued''))',
  'Ciclo de vida: launch | permanent | limited | discontinued. discontinued por ausência é inferido (§4.4).');
select ops.add_traceable_field('core.product', 'launch_date', 'date', 'Data de lançamento.');
select ops.add_traceable_field('core.product', 'skin_type', 'text[] check (skin_type <@ array[''normal'', ''seca'', ''oleosa'', ''mista'', ''sensivel'', ''acneica'', ''madura'', ''todos_os_tipos''])',
  'Tipos de pele indicados: normal | seca | oleosa | mista | sensivel | acneica | madura | todos_os_tipos.');
select ops.add_traceable_field('core.product', 'body_area', 'text[] check (body_area <@ array[''rosto'', ''area_dos_olhos'', ''labios'', ''pescoco_colo'', ''corpo'', ''maos'', ''pes'', ''couro_cabeludo'', ''cabelo''])',
  'Regiões do corpo: rosto | area_dos_olhos | labios | pescoco_colo | corpo | maos | pes | couro_cabeludo | cabelo.');
select ops.add_traceable_field('core.product', 'use_occasion', 'text', 'Ocasião de uso (ex.: reaplicação ao longo do dia, pós-treino, noturno).');
select ops.add_traceable_field('core.product', 'suggested_frequency', 'text', 'Frequência de uso sugerida pela marca.');
select ops.add_traceable_field('core.product', 'spf_declared', 'smallint check (spf_declared between 1 and 100)', 'FPS declarado. Nunca inferido (G-03).');
select ops.add_traceable_field('core.product', 'target_audience_declared', 'text', 'Público declarado do produto. Nunca inferido; inferência de público fica em análise rotulada (G-08).');

alter table core.product
  add constraint product_subcategory_category_fk
    foreign key (subcategory_id, category_id) references core.subcategory(id, category_id),
  add constraint product_spf_declared_ck check (spf_declared_is_inferred is distinct from true),
  add constraint product_target_audience_declared_ck check (target_audience_declared_is_inferred is distinct from true);

create index product_brand_idx on core.product (brand_id);
create index product_category_idx on core.product (category_id, subcategory_id);
create index product_format_idx on core.product (format_id);
create index product_first_seen_idx on core.product (first_seen_at desc);

create trigger product_set_updated_at before update on core.product
  for each row execute function ops.set_updated_at();

create table core.product_version (
  id              uuid primary key default gen_random_uuid(),
  product_id      uuid not null references core.product(id),
  version_no      integer not null check (version_no > 0),
  valid_from      timestamptz not null,
  valid_to        timestamptz,
  snapshot        jsonb not null,
  changed_fields  text[],
  change_origin   text,
  unique (product_id, version_no),
  check (valid_to is null or valid_to >= valid_from)
);
comment on table core.product_version is 'Histórico SCD2 de core.product (ops.capture_version). Versão vigente: valid_to IS NULL.';
create unique index product_version_current_uq on core.product_version (product_id) where valid_to is null;

create trigger product_capture_version after insert or update on core.product
  for each row execute function ops.capture_version('core.product_version', 'product_id');
create trigger product_no_delete before delete on core.product
  for each row execute function ops.forbid_delete();

-- -----------------------------------------------------------------------------
-- core.product_variant
-- -----------------------------------------------------------------------------
create table core.product_variant (
  id                  uuid primary key default gen_random_uuid(),
  product_id          uuid not null references core.product(id),
  variant_name        text,
  shade               text,
  volume_unit         text check (volume_unit in ('ml', 'g', 'un')),
  first_seen_at       timestamptz not null default now(),
  last_seen_at        timestamptz not null default now(),
  consecutive_misses  smallint not null default 0 check (consecutive_misses >= 0),
  created_at          timestamptz not null default now(),
  updated_at          timestamptz not null default now(),
  check (last_seen_at >= first_seen_at)
);
comment on table core.product_variant is 'Variante (SKU) de um produto: volume/peso, tom, GTIN. Histórico em core.product_variant_version.';
comment on column core.product_variant.shade is 'Cor/tom declarado.';
comment on column core.product_variant.volume_unit is 'ml | g | un. Obrigatório quando volume_value está preenchido.';

select ops.add_traceable_field('core.product_variant', 'volume_value', 'numeric(10,3) check (volume_value > 0)',
  'Volume/peso líquido. Preço unitário só é calculado com volume_value_confidence >= 0.90 (G-05).');
select ops.add_traceable_field('core.product_variant', 'gtin', 'text check (gtin ~ ''^[0-9]{8,14}$'')', 'GTIN/EAN quando publicado. Chave forte de deduplicação (§4.4).');

alter table core.product_variant
  add constraint product_variant_volume_unit_ck check (volume_value is null or volume_unit is not null),
  add constraint product_variant_gtin_declared_ck check (gtin_is_inferred is distinct from true);

create unique index product_variant_gtin_uq on core.product_variant (gtin) where gtin is not null;
create index product_variant_product_idx on core.product_variant (product_id);

create trigger product_variant_set_updated_at before update on core.product_variant
  for each row execute function ops.set_updated_at();

create table core.product_variant_version (
  id                  uuid primary key default gen_random_uuid(),
  product_variant_id  uuid not null references core.product_variant(id),
  version_no          integer not null check (version_no > 0),
  valid_from          timestamptz not null,
  valid_to            timestamptz,
  snapshot            jsonb not null,
  changed_fields      text[],
  change_origin       text,
  unique (product_variant_id, version_no),
  check (valid_to is null or valid_to >= valid_from)
);
comment on table core.product_variant_version is 'Histórico SCD2 de core.product_variant (ops.capture_version).';
create unique index product_variant_version_current_uq on core.product_variant_version (product_variant_id) where valid_to is null;

create trigger product_variant_capture_version after insert or update on core.product_variant
  for each row execute function ops.capture_version('core.product_variant_version', 'product_variant_id');
create trigger product_variant_no_delete before delete on core.product_variant
  for each row execute function ops.forbid_delete();

-- -----------------------------------------------------------------------------
-- core.price_observation — histórico de preço (G-05, AC-05)
-- -----------------------------------------------------------------------------
create table core.price_observation (
  id                         uuid primary key default gen_random_uuid(),
  variant_id                 uuid not null references core.product_variant(id),
  source_id                  uuid not null references ops.source(id),
  crawl_run_id               uuid references ops.crawl_run(id),
  observed_at                timestamptz not null,
  list_price                 numeric(12,2) check (list_price >= 0),
  promo_price                numeric(12,2) check (promo_price >= 0),
  price_missing_reason       text check (price_missing_reason in ('not_published', 'out_of_stock_no_price', 'source_blocked', 'parse_error')),
  currency                   char(3) not null default 'BRL',
  unit_price_per_ml_g        numeric(12,4),
  unit_promo_price_per_ml_g  numeric(12,4),
  unit_basis_volume          numeric(10,3),
  unit_basis_unit            text check (unit_basis_unit in ('ml', 'g')),
  is_kit                     boolean not null default false,
  availability               text not null default 'unknown' check (availability in ('in_stock', 'out_of_stock', 'unknown')),
  seller_name                text,
  extraction_method          text not null check (extraction_method in ('api', 'json_ld', 'parser', 'llm', 'manual')),
  extraction_confidence      numeric(3,2) not null check (extraction_confidence between 0 and 1),
  prompt_version             text,
  evidence_id                uuid not null references core.evidence(id),
  created_at                 timestamptz not null default now(),
  check (list_price is not null or promo_price is not null or price_missing_reason is not null),
  check (extraction_method <> 'llm' or prompt_version is not null)
);
comment on table core.price_observation is 'Observação de preço por variante, fonte e data. Append-only por natureza: cada coleta gera nova linha (G-04).';
comment on column core.price_observation.list_price is 'Preço cheio (de/por: "de"). Nunca confundido com promocional (G-05).';
comment on column core.price_observation.promo_price is 'Preço promocional vigente na coleta.';
comment on column core.price_observation.price_missing_reason is 'Motivo quando nenhum preço foi capturado (G-03).';
comment on column core.price_observation.unit_price_per_ml_g is 'list_price ÷ volume. Calculado por trigger apenas se volume em ml/g com confiança >= 0.90 e não for kit (G-05); caso contrário NULL.';
comment on column core.price_observation.unit_promo_price_per_ml_g is 'promo_price ÷ volume, mesmas regras de unit_price_per_ml_g.';
comment on column core.price_observation.unit_basis_volume is 'Volume da variante usado no cálculo, congelado na observação.';
comment on column core.price_observation.is_kit is 'Observação refere-se a kit/combo; preço unitário não é calculado.';
comment on column core.price_observation.seller_name is 'Vendedor em marketplace (pessoa jurídica). Não armazenar pessoa física (C-04).';
comment on column core.price_observation.extraction_method is 'api | json_ld | parser | llm | manual.';

create index price_observation_variant_idx on core.price_observation (variant_id, observed_at desc);
create index price_observation_source_idx on core.price_observation (source_id, observed_at desc);

create or replace function core.compute_unit_price()
returns trigger
language plpgsql
as $$
declare
  v_volume numeric;
  v_unit   text;
  v_conf   numeric;
begin
  select volume_value, volume_unit, volume_value_confidence
    into v_volume, v_unit, v_conf
    from core.product_variant
   where id = new.variant_id;

  if not new.is_kit and v_unit in ('ml', 'g') and v_conf >= 0.90 and v_volume > 0 then
    new.unit_basis_volume         := v_volume;
    new.unit_basis_unit           := v_unit;
    new.unit_price_per_ml_g       := round(new.list_price / v_volume, 4);
    new.unit_promo_price_per_ml_g := round(new.promo_price / v_volume, 4);
  else
    new.unit_basis_volume         := null;
    new.unit_basis_unit           := null;
    new.unit_price_per_ml_g       := null;
    new.unit_promo_price_per_ml_g := null;
  end if;
  return new;
end;
$$;
comment on function core.compute_unit_price() is 'Trigger BEFORE INSERT/UPDATE em price_observation: calcula preço por ml/g somente quando G-05 é atendido.';

create trigger price_observation_unit_price before insert or update of list_price, promo_price, variant_id, is_kit
  on core.price_observation
  for each row execute function core.compute_unit_price();

-- -----------------------------------------------------------------------------
-- core.ingredient / core.product_ingredient (AC-03)
-- -----------------------------------------------------------------------------
create table core.ingredient (
  id              uuid primary key default gen_random_uuid(),
  inci_name       text not null unique check (inci_name = upper(trim(inci_name))),
  common_name     text,
  function_class  text,
  notes           text,
  created_at      timestamptz not null default now(),
  updated_at      timestamptz not null default now()
);
comment on table core.ingredient is 'Ingrediente pela nomenclatura INCI normalizada.';
comment on column core.ingredient.inci_name is 'Nome INCI normalizado (maiúsculas, sem espaços nas pontas).';
comment on column core.ingredient.function_class is 'Classe funcional (umectante, filtro UV, emoliente...). Vocabulário a definir.';

create trigger ingredient_set_updated_at before update on core.ingredient
  for each row execute function ops.set_updated_at();

create table core.product_ingredient (
  id                         uuid primary key default gen_random_uuid(),
  product_id                 uuid not null references core.product(id),
  ingredient_id              uuid not null references core.ingredient(id),
  inci_text_as_published     text not null,
  position_in_inci           smallint check (position_in_inci > 0),
  is_highlighted_active      boolean not null default false,
  highlight_evidence_id      uuid references core.evidence(id),
  concentration_unit         text check (concentration_unit in ('%', 'mg/g', 'mg/ml', 'ppm', 'UI/g')),
  is_inferred                boolean not null default false,
  confidence                 numeric(3,2) not null check (confidence between 0 and 1),
  evidence_id                uuid not null references core.evidence(id),
  valid_from                 timestamptz not null default now(),
  valid_to                   timestamptz,
  created_at                 timestamptz not null default now(),
  constraint product_ingredient_not_inferred_ck check (is_inferred = false),
  check (not is_highlighted_active or highlight_evidence_id is not null),
  check (valid_to is null or valid_to >= valid_from)
);

select ops.add_traceable_field('core.product_ingredient', 'declared_concentration', 'numeric(9,4) check (declared_concentration > 0)',
  'Concentração declarada pela marca. Nunca inferida (G-03).');

alter table core.product_ingredient
  add constraint product_ingredient_concentration_unit_ck check (declared_concentration is null or concentration_unit is not null),
  add constraint product_ingredient_concentration_declared_ck check (declared_concentration_is_inferred is distinct from true);

comment on table core.product_ingredient is 'Composição INCI do produto. Presença de ingrediente nunca é inferida (G-03); evidence_id obrigatório (AC-03). SCD2 inline: alteração fecha valid_to e insere nova linha.';
comment on column core.product_ingredient.inci_text_as_published is 'Grafia exatamente como publicada na fonte.';
comment on column core.product_ingredient.position_in_inci is 'Posição na lista INCI publicada (1 = maior concentração).';
comment on column core.product_ingredient.is_highlighted_active is 'Ativo destacado pela marca na comunicação do produto.';
comment on column core.product_ingredient.is_inferred is 'Sempre false: presença de ingrediente só por declaração (G-03).';
comment on column core.product_ingredient.valid_to is 'Fim de vigência (fórmula alterada ou ingrediente removido). NULL = vigente.';

create unique index product_ingredient_current_uq on core.product_ingredient (product_id, ingredient_id) where valid_to is null;
create index product_ingredient_ingredient_idx on core.product_ingredient (ingredient_id) where valid_to is null;

-- -----------------------------------------------------------------------------
-- core.claim (AC-03)
-- -----------------------------------------------------------------------------
create table core.claim (
  id                     uuid primary key default gen_random_uuid(),
  product_id             uuid not null references core.product(id),
  claim_text_exact       text not null check (length(claim_text_exact) > 0),
  metric_value           numeric,
  metric_unit            text,
  metric_context         text,
  extraction_confidence  numeric(3,2) not null check (extraction_confidence between 0 and 1),
  evidence_id            uuid not null references core.evidence(id),
  valid_from             timestamptz not null default now(),
  valid_to               timestamptz,
  created_at             timestamptz not null default now(),
  check (valid_to is null or valid_to >= valid_from)
);

select ops.add_traceable_field('core.claim', 'claim_type',
  'text check (claim_type in (''benefit'', ''efficacy'', ''metric'', ''safety'', ''sustainability''))',
  'Tipo de alegação: benefit | efficacy | metric | safety | sustainability (classificação).');

comment on table core.claim is 'Alegação literal do produto. Texto nunca parafraseado; evidence_id obrigatório (AC-03). Alegação ≠ evidência científica (G-06).';
comment on column core.claim.claim_text_exact is 'Texto exato da alegação na fonte.';
comment on column core.claim.metric_value is 'Valor numérico declarado na alegação (ex.: 47 em "reduz 47% das manchas").';
comment on column core.claim.metric_context is 'Condições declaradas (prazo, amostra, método), quando publicadas.';

create unique index claim_current_uq on core.claim (product_id, md5(claim_text_exact)) where valid_to is null;

-- -----------------------------------------------------------------------------
-- core.product_benefit
-- -----------------------------------------------------------------------------
create table core.product_benefit (
  id              uuid primary key default gen_random_uuid(),
  product_id      uuid not null references core.product(id),
  benefit_id      uuid not null references core.benefit(id),
  is_primary      boolean not null default false,
  is_inferred     boolean not null,
  confidence      numeric(3,2) not null check (confidence between 0 and 1),
  evidence_id     uuid not null references core.evidence(id),
  model           text,
  prompt_version  text,
  valid_from      timestamptz not null default now(),
  valid_to        timestamptz,
  created_at      timestamptz not null default now(),
  check (not is_inferred or prompt_version is not null),
  check (valid_to is null or valid_to >= valid_from)
);
comment on table core.product_benefit is 'Associação produto × benefício normalizado (principal/secundário), com rastreio por linha (§4.1). SCD2 inline.';
comment on column core.product_benefit.is_primary is 'Benefício principal. No máximo um vigente por produto.';

create unique index product_benefit_current_uq on core.product_benefit (product_id, benefit_id) where valid_to is null;
create unique index product_benefit_primary_uq on core.product_benefit (product_id) where is_primary and valid_to is null;
create index product_benefit_benefit_idx on core.product_benefit (benefit_id) where valid_to is null;

-- -----------------------------------------------------------------------------
-- core.packaging
-- -----------------------------------------------------------------------------
create table core.packaging (
  id          uuid primary key default gen_random_uuid(),
  product_id  uuid not null references core.product(id),
  variant_id  uuid references core.product_variant(id),
  created_at  timestamptz not null default now(),
  updated_at  timestamptz not null default now()
);
comment on table core.packaging is 'Embalagem do produto (ou de uma variante específica). Vocabulários de tipo/material/mecanismo ainda não definidos na SPEC.';
comment on column core.packaging.variant_id is 'Preenchido quando a embalagem difere entre variantes.';

select ops.add_traceable_field('core.packaging', 'type', 'text', 'Tipo de embalagem primária (bisnaga, frasco, stick, pote, sachê...).');
select ops.add_traceable_field('core.packaging', 'material', 'text', 'Material declarado.');
select ops.add_traceable_field('core.packaging', 'dispensing_mechanism', 'text', 'Mecanismo de dispensação (pump, airless, giro, conta-gotas, spray, roll-on...).');
select ops.add_traceable_field('core.packaging', 'portability', 'text', 'Portabilidade (tamanho de bolsa/viagem, à prova de vazamento...).');
select ops.add_traceable_field('core.packaging', 'refill_available', 'boolean', 'Existe refil comercializado.');
select ops.add_traceable_field('core.packaging', 'visual_notes', 'text', 'Percepção visual. Tipicamente inferida (is_inferred = true).');

create index packaging_product_idx on core.packaging (product_id);
create unique index packaging_product_variant_uq on core.packaging (product_id, coalesce(variant_id, '00000000-0000-0000-0000-000000000000'::uuid));

create trigger packaging_set_updated_at before update on core.packaging
  for each row execute function ops.set_updated_at();

create table core.packaging_version (
  id              uuid primary key default gen_random_uuid(),
  packaging_id    uuid not null references core.packaging(id),
  version_no      integer not null check (version_no > 0),
  valid_from      timestamptz not null,
  valid_to        timestamptz,
  snapshot        jsonb not null,
  changed_fields  text[],
  change_origin   text,
  unique (packaging_id, version_no),
  check (valid_to is null or valid_to >= valid_from)
);
comment on table core.packaging_version is 'Histórico SCD2 de core.packaging (ops.capture_version).';
create unique index packaging_version_current_uq on core.packaging_version (packaging_id) where valid_to is null;

create trigger packaging_capture_version after insert or update on core.packaging
  for each row execute function ops.capture_version('core.packaging_version', 'packaging_id');
create trigger packaging_no_delete before delete on core.packaging
  for each row execute function ops.forbid_delete();

-- -----------------------------------------------------------------------------
-- core.review_aggregate (G-06)
-- -----------------------------------------------------------------------------
create table core.review_aggregate (
  id                     uuid primary key default gen_random_uuid(),
  product_id             uuid references core.product(id),
  variant_id             uuid references core.product_variant(id),
  source_id              uuid not null references ops.source(id),
  observed_at            timestamptz not null,
  avg_rating             numeric(4,2),
  rating_scale_max       numeric(4,1) not null default 5,
  review_count           integer check (review_count >= 0),
  positive_themes        jsonb,
  negative_themes        jsonb,
  themes_model           text,
  themes_prompt_version  text,
  themes_confidence      numeric(3,2) check (themes_confidence between 0 and 1),
  evidence_id            uuid not null references core.evidence(id),
  created_at             timestamptz not null default now(),
  check (product_id is not null or variant_id is not null),
  check (avg_rating is null or avg_rating between 0 and rating_scale_max),
  check ((positive_themes is null and negative_themes is null) or themes_prompt_version is not null)
);
comment on table core.review_aggregate is 'Agregado de avaliações de consumidor por fonte e data. Avaliação ≠ evidência científica (G-06). Não é proxy de vendas (G-07).';
comment on column core.review_aggregate.product_id is 'Preenchido quando a fonte agrega avaliações no nível do produto.';
comment on column core.review_aggregate.variant_id is 'Preenchido quando a fonte agrega avaliações no nível da variante.';
comment on column core.review_aggregate.positive_themes is 'Temas positivos inferidos: [{theme, count, example_signal_ids}]. Rastreio em themes_*.';
comment on column core.review_aggregate.negative_themes is 'Temas negativos/reclamações recorrentes inferidos, mesma estrutura.';

create index review_aggregate_product_idx on core.review_aggregate (product_id, observed_at desc);
create index review_aggregate_variant_idx on core.review_aggregate (variant_id, observed_at desc);

-- -----------------------------------------------------------------------------
-- core.technology_asset
-- -----------------------------------------------------------------------------
create table core.technology_asset (
  id                   uuid primary key default gen_random_uuid(),
  brand_id             uuid not null references core.brand(id),
  product_id           uuid references core.product(id),
  name                 text not null,
  type                 text not null check (type in ('patent', 'trademark', 'proprietary_active', 'technology')),
  verification_status  text not null default 'declared' check (verification_status in ('confirmed', 'declared', 'unverified')),
  registry_number      text,
  jurisdiction         text,
  verified_at          timestamptz,
  evidence_id          uuid not null references core.evidence(id),
  notes                text,
  created_at           timestamptz not null default now(),
  updated_at           timestamptz not null default now(),
  check (verification_status <> 'confirmed' or verified_at is not null),
  check (verification_status <> 'confirmed' or type not in ('patent', 'trademark') or registry_number is not null)
);
comment on table core.technology_asset is 'Patentes, marcas registradas, ativos proprietários e tecnologias. Patente/fornecedor nunca inventados (G-03).';
comment on column core.technology_asset.verification_status is 'confirmed (verificado em registro oficial) | declared (afirmado pela marca) | unverified.';
comment on column core.technology_asset.registry_number is 'Número de registro (INPI, USPTO, WIPO...). Obrigatório para patente/marca confirmada.';

create index technology_asset_brand_idx on core.technology_asset (brand_id);

create trigger technology_asset_set_updated_at before update on core.technology_asset
  for each row execute function ops.set_updated_at();
