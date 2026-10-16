-- =============================================================================
-- NEXA LAB — F0-04 — Schema raw
-- SPEC §4.3 raw, §5.2, G-02, C-04
-- =============================================================================

create table raw.raw_document (
  id                    uuid primary key default gen_random_uuid(),
  source_id             uuid not null references ops.source(id),
  crawl_run_id          uuid references ops.crawl_run(id),
  url                   text not null,
  final_url             text,
  fetched_at            timestamptz not null,
  last_fetched_at       timestamptz not null,
  fetch_count           integer not null default 1 check (fetch_count >= 1),
  http_status           smallint,
  content_hash          char(64) not null check (content_hash ~ '^[0-9a-f]{64}$'),
  content_type          text,
  content_length        bigint check (content_length >= 0),
  storage_path          text not null,
  structured_data       jsonb,
  http_headers          jsonb,
  etag                  text,
  last_modified         timestamptz,
  previous_document_id  uuid references raw.raw_document(id),
  created_at            timestamptz not null default now(),
  unique (url, content_hash),
  check (last_fetched_at >= fetched_at)
);
comment on table raw.raw_document is 'Documento bruto imutável. Mesmo URL com novo content_hash = nova linha encadeada por previous_document_id (§4.4).';
comment on column raw.raw_document.url is 'URL solicitada.';
comment on column raw.raw_document.final_url is 'URL após redirecionamentos.';
comment on column raw.raw_document.fetched_at is 'Primeira coleta deste conteúdo (hash).';
comment on column raw.raw_document.last_fetched_at is 'Última coleta em que o mesmo hash foi observado. Única coluna atualizável junto com fetch_count.';
comment on column raw.raw_document.content_hash is 'SHA-256 hexadecimal do conteúdo bruto.';
comment on column raw.raw_document.storage_path is 'Caminho do arquivo bruto no Supabase Storage.';
comment on column raw.raw_document.structured_data is 'JSON-LD/schema.org/microdata extraído (extruct), sem interpretação.';
comment on column raw.raw_document.http_headers is 'Cabeçalhos de resposta. Não armazenar Set-Cookie nem cabeçalhos com dados pessoais (C-04).';
comment on column raw.raw_document.previous_document_id is 'Versão anterior do mesmo URL, para diff de conteúdo.';

create index raw_document_source_idx on raw.raw_document (source_id, fetched_at desc);
create index raw_document_url_idx on raw.raw_document (url, fetched_at desc);
create index raw_document_run_idx on raw.raw_document (crawl_run_id);

create trigger raw_document_immutable before update on raw.raw_document
  for each row execute function ops.forbid_update('last_fetched_at', 'fetch_count');
