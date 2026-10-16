-- =============================================================================
-- NEXA LAB — F0-03/F0-04 — core: evidência e tabelas de taxonomia
-- SPEC §4.3 core, §6.2, §8, G-02. Conteúdo inicial em supabase/seed/taxonomies/.
-- =============================================================================

-- -----------------------------------------------------------------------------
-- core.evidence — trecho que sustenta um valor (G-02)
-- -----------------------------------------------------------------------------
create table core.evidence (
  id                  uuid primary key default gen_random_uuid(),
  evidence_type       text not null default 'document' check (evidence_type in ('document', 'api_response', 'manual')),
  raw_document_id     uuid references raw.raw_document(id),
  url                 text not null,
  excerpt             text not null check (length(excerpt) > 0),
  selector_or_offset  text,
  captured_at         timestamptz not null,
  created_by          text,
  created_at          timestamptz not null default now(),
  check (evidence_type = 'manual' or raw_document_id is not null),
  check (evidence_type <> 'manual' or created_by is not null)
);
comment on table core.evidence is 'Evidência textual abrível no BI (excerpt + URL + data). Imutável. Referenciada por todo campo rastreável (§4.1, G-02).';
comment on column core.evidence.evidence_type is 'document (página coletada) | api_response | manual (inserção humana, exige created_by).';
comment on column core.evidence.excerpt is 'Trecho literal da fonte que sustenta o valor.';
comment on column core.evidence.selector_or_offset is 'Seletor CSS/XPath, caminho JSON ou offset de caracteres no documento bruto.';
comment on column core.evidence.captured_at is 'Data/hora da coleta da fonte (não da gravação).';

create index evidence_raw_document_idx on core.evidence (raw_document_id);

create trigger evidence_immutable before update on core.evidence
  for each row execute function ops.forbid_update();

-- -----------------------------------------------------------------------------
-- Taxonomias. Estrutura comum: code estável (slug), nome em pt-BR, ativo.
-- -----------------------------------------------------------------------------
create table core.category (
  id           uuid primary key default gen_random_uuid(),
  code         text not null unique check (code ~ '^[a-z0-9_]+$'),
  name_pt      text not null,
  description  text,
  sort_order   integer not null default 0,
  active       boolean not null default true,
  created_at   timestamptz not null default now(),
  updated_at   timestamptz not null default now()
);
comment on table core.category is 'Taxonomia de categoria de produto (F0-03). Critério de classificação: benefício principal declarado do produto.';

create table core.subcategory (
  id           uuid primary key default gen_random_uuid(),
  category_id  uuid not null references core.category(id),
  code         text not null unique check (code ~ '^[a-z0-9_]+$'),
  name_pt      text not null,
  description  text,
  sort_order   integer not null default 0,
  active       boolean not null default true,
  created_at   timestamptz not null default now(),
  updated_at   timestamptz not null default now(),
  unique (id, category_id)
);
comment on table core.subcategory is 'Taxonomia de subcategoria, filha de core.category. (id, category_id) único para FK composta que garante coerência categoria × subcategoria.';

create table core.format (
  id            uuid primary key default gen_random_uuid(),
  code          text not null unique check (code ~ '^[a-z0-9_]+$'),
  name_pt       text not null,
  format_group  text not null check (format_group in ('liquido', 'emulsao', 'gel', 'anidro', 'solido', 'po', 'pressurizado', 'suporte', 'dispositivo')),
  description   text,
  sort_order    integer not null default 0,
  active        boolean not null default true,
  created_at    timestamptz not null default now(),
  updated_at    timestamptz not null default now()
);
comment on table core.format is 'Taxonomia de formato = forma física do produto (textura/veículo). Embalagem e mecanismo de dispensação ficam em core.packaging.';
comment on column core.format.format_group is 'liquido | emulsao | gel | anidro | solido | po | pressurizado | suporte (tecido, patch) | dispositivo.';

create table core.benefit (
  id             uuid primary key default gen_random_uuid(),
  code           text not null unique check (code ~ '^[a-z0-9_]+$'),
  name_pt        text not null,
  benefit_group  text not null check (benefit_group in (
                   'hidratacao_barreira', 'protecao', 'tratamento', 'limpeza', 'maquiagem_acabamento', 'sensorial_bem_estar', 'capilar')),
  description    text,
  sort_order     integer not null default 0,
  active         boolean not null default true,
  created_at     timestamptz not null default now(),
  updated_at     timestamptz not null default now()
);
comment on table core.benefit is 'Taxonomia de benefício normalizado. O texto literal da alegação fica em core.claim (claim_text_exact).';

create table core.voice_type (
  id           uuid primary key default gen_random_uuid(),
  code         text not null unique check (code ~ '^[a-z0-9_]+$'),
  name_pt      text not null,
  description  text not null,
  sort_order   integer not null default 0,
  active       boolean not null default true,
  created_at   timestamptz not null default now(),
  updated_at   timestamptz not null default now()
);
comment on table core.voice_type is 'Taxonomia de voz do consumidor (SPEC §6.2).';

create table core.signal_phrase (
  id                       uuid primary key default gen_random_uuid(),
  phrase_pattern           text not null,
  match_type               text not null default 'prefix' check (match_type in ('prefix', 'contains', 'regex')),
  language                 text not null default 'pt-BR',
  suggested_voice_type_id  uuid references core.voice_type(id),
  origin                   text not null default 'seed' check (origin in ('seed', 'human_review')),
  notes                    text,
  active                   boolean not null default true,
  created_at               timestamptz not null default now(),
  updated_at               timestamptz not null default now(),
  unique (phrase_pattern, language)
);
comment on table core.signal_phrase is 'Frases-sinal para pré-filtro/realce de sinais (SPEC §6.2). Expandida por revisão humana (origin = human_review).';
comment on column core.signal_phrase.phrase_pattern is 'Padrão em minúsculas. A comparação é feita no código após normalização (lower + unaccent) do texto e do padrão. Para regex, expressão POSIX.';
comment on column core.signal_phrase.suggested_voice_type_id is 'Sugestão de tipo de voz. Heurística de pré-classificação, não substitui a classificação validada.';

create table core.trend_class (
  id           uuid primary key default gen_random_uuid(),
  code         text not null unique check (code ~ '^[a-z0-9_]+$'),
  name_pt      text not null,
  description  text not null,
  sort_order   integer not null default 0,
  active       boolean not null default true,
  created_at   timestamptz not null default now(),
  updated_at   timestamptz not null default now()
);
comment on table core.trend_class is 'Classificação de tendência (SPEC §8). Limiares quantitativos dependem dos pesos do Índice de Tendência (Q-17).';

create trigger category_set_updated_at      before update on core.category      for each row execute function ops.set_updated_at();
create trigger subcategory_set_updated_at   before update on core.subcategory   for each row execute function ops.set_updated_at();
create trigger format_set_updated_at        before update on core.format        for each row execute function ops.set_updated_at();
create trigger benefit_set_updated_at       before update on core.benefit       for each row execute function ops.set_updated_at();
create trigger voice_type_set_updated_at    before update on core.voice_type    for each row execute function ops.set_updated_at();
create trigger signal_phrase_set_updated_at before update on core.signal_phrase for each row execute function ops.set_updated_at();
create trigger trend_class_set_updated_at   before update on core.trend_class   for each row execute function ops.set_updated_at();
