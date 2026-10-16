-- =============================================================================
-- NEXA LAB — F0-04 — core: voz do consumidor e tendências
-- SPEC §4.3 core (voz do consumidor), §6, G-01, G-07, G-08, C-03, C-04
-- =============================================================================

-- -----------------------------------------------------------------------------
-- core.consumer_signal — dado (nunca alterado por reclassificação, §6.1)
-- -----------------------------------------------------------------------------
create table core.consumer_signal (
  id                  uuid primary key default gen_random_uuid(),
  source_id           uuid not null references ops.source(id),
  raw_document_id     uuid references raw.raw_document(id),
  platform            text not null check (platform in (
                        'youtube', 'reddit', 'tiktok', 'instagram', 'facebook', 'marketplace', 'ecommerce', 'forum', 'search', 'other')),
  signal_kind         text not null check (signal_kind in ('comment', 'review', 'post', 'video', 'question', 'answer')),
  external_public_id  text,
  url                 text not null,
  original_text       text not null check (length(original_text) > 0),
  text_hash           char(64) not null check (text_hash ~ '^[0-9a-f]{64}$'),
  language            text,
  published_at        timestamptz,
  collected_at        timestamptz not null,
  author_hash         char(64) check (author_hash ~ '^[0-9a-f]{64}$'),
  rating_value        numeric(4,2),
  rating_scale_max    numeric(4,1),
  engagement          jsonb not null default '{}'::jsonb,
  created_at          timestamptz not null default now(),
  check (rating_value is null or (rating_scale_max is not null and rating_value between 0 and rating_scale_max))
);
comment on table core.consumer_signal is 'Sinal público de consumidor (comentário, avaliação, post). Apenas fontes permitidas (C-03). Sem dados pessoais (C-04).';
comment on column core.consumer_signal.platform is 'youtube | reddit | tiktok | instagram | facebook | marketplace | ecommerce | forum | search | other.';
comment on column core.consumer_signal.external_public_id is 'ID público do conteúdo na plataforma, apenas quando os termos permitem armazená-lo.';
comment on column core.consumer_signal.original_text is 'Texto original, sem edição. Base de evidência das classificações.';
comment on column core.consumer_signal.text_hash is 'SHA-256 do texto normalizado, para deduplicação.';
comment on column core.consumer_signal.author_hash is 'HMAC-SHA256 do identificador do autor com segredo do ambiente. Nome/handle nunca armazenados; anonimizado no BI (C-04).';
comment on column core.consumer_signal.rating_value is 'Nota atribuída pelo consumidor, quando o sinal é uma avaliação.';
comment on column core.consumer_signal.engagement is 'Métricas públicas (curtidas, respostas, visualizações). Não são proxy de mercado ou vendas (G-07).';

select ops.add_traceable_field('core.consumer_signal', 'related_brand_id', 'uuid references core.brand(id)', 'Marca à qual o sinal se refere.');
select ops.add_traceable_field('core.consumer_signal', 'related_product_id', 'uuid references core.product(id)', 'Produto ao qual o sinal se refere.');

create unique index consumer_signal_external_uq on core.consumer_signal (platform, external_public_id) where external_public_id is not null;
create unique index consumer_signal_text_uq on core.consumer_signal (platform, url, text_hash);
create index consumer_signal_brand_idx on core.consumer_signal (related_brand_id);
create index consumer_signal_product_idx on core.consumer_signal (related_product_id);
create index consumer_signal_published_idx on core.consumer_signal (published_at desc);

create trigger consumer_signal_immutable before update on core.consumer_signal
  for each row execute function ops.forbid_update(
    'related_brand_id', 'related_brand_id_is_inferred', 'related_brand_id_confidence', 'related_brand_id_evidence_id', 'related_brand_id_missing_reason',
    'related_product_id', 'related_product_id_is_inferred', 'related_product_id_confidence', 'related_product_id_evidence_id', 'related_product_id_missing_reason');

-- -----------------------------------------------------------------------------
-- core.signal_classification — interpretação (sempre inferida)
-- -----------------------------------------------------------------------------
create table core.signal_classification (
  id                   uuid primary key default gen_random_uuid(),
  signal_id            uuid not null references core.consumer_signal(id),
  voice_type_id        uuid not null references core.voice_type(id),
  theme                text not null,
  need                 text not null,
  context              text not null,
  intensity            smallint not null check (intensity between 1 and 5),
  signal_phrase_match  text,
  signal_phrase_id     uuid references core.signal_phrase(id),
  sentiment            text check (sentiment in ('positive', 'neutral', 'negative', 'mixed')),
  confidence           numeric(3,2) not null check (confidence between 0 and 1),
  model                text not null,
  prompt_version       text not null,
  classified_at        timestamptz not null default now(),
  reviewed             boolean not null default false,
  reviewed_by          text,
  reviewed_at          timestamptz,
  superseded_at        timestamptz,
  check (not reviewed or (reviewed_by is not null and reviewed_at is not null))
);
comment on table core.signal_classification is 'Classificação de um sinal pela taxonomia §6.2. Sempre inferência (is_inferred implícito = true). Reclassificação marca superseded_at e insere nova linha; o sinal original não muda.';
comment on column core.signal_classification.theme is 'TEMA (saída obrigatória §6.2).';
comment on column core.signal_classification.need is 'NECESSIDADE (saída obrigatória §6.2).';
comment on column core.signal_classification.context is 'CONTEXTO de uso/ocasião (saída obrigatória §6.2).';
comment on column core.signal_classification.intensity is 'INTENSIDADE 1–5. FREQUÊNCIA é calculada na agregação (analytics).';
comment on column core.signal_classification.signal_phrase_match is 'Trecho do texto que casou com uma frase-sinal.';
comment on column core.signal_classification.reviewed is 'true após validação humana; correções em ops.human_review (G-10).';
comment on column core.signal_classification.superseded_at is 'Preenchido quando a classificação é substituída. NULL = vigente.';

create unique index signal_classification_current_uq on core.signal_classification (signal_id, voice_type_id) where superseded_at is null;
create index signal_classification_voice_idx on core.signal_classification (voice_type_id) where superseded_at is null;

-- -----------------------------------------------------------------------------
-- core.trend_series — interesse relativo (nunca tamanho de mercado)
-- -----------------------------------------------------------------------------
create table core.trend_series (
  id                 uuid primary key default gen_random_uuid(),
  term               text not null,
  source             text not null check (source in ('google_trends', 'internal_signals')),
  source_id          uuid references ops.source(id),
  region             text not null,
  period_start       date not null,
  period_end         date not null,
  relative_interest  numeric(6,2) not null check (relative_interest >= 0),
  query_batch_id     uuid not null,
  note               text not null default 'relative_not_absolute' check (note = 'relative_not_absolute'),
  raw_document_id    uuid references raw.raw_document(id),
  collected_at       timestamptz not null,
  created_at         timestamptz not null default now(),
  check (period_end >= period_start),
  check (source <> 'google_trends' or relative_interest <= 100),
  unique (term, source, region, period_start, period_end, query_batch_id)
);
comment on table core.trend_series is 'Série de interesse relativo. Valores comparáveis apenas dentro do mesmo query_batch_id. Nunca tratar como tamanho de mercado (G-07, §6.1).';
comment on column core.trend_series.region is 'Código ISO 3166 (BR, BR-SP...) ou "GLOBAL".';
comment on column core.trend_series.relative_interest is 'Google Trends: 0–100 relativo ao pico do lote. internal_signals: contagem/índice interno documentado.';
comment on column core.trend_series.query_batch_id is 'Identifica a consulta conjunta; o Google Trends renormaliza a cada consulta.';
comment on column core.trend_series.note is 'Fixo em relative_not_absolute (rótulo obrigatório).';

create index trend_series_term_idx on core.trend_series (term, region, period_start);
