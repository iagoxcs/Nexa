-- =============================================================================
-- NEXA LAB — F0-04 — Schema ops
-- SPEC §4.3 ops, G-09, G-10, C-01, C-02, C-05, A-06, DEC-03
-- =============================================================================

-- -----------------------------------------------------------------------------
-- ops.source — cadastro de fontes
-- -----------------------------------------------------------------------------
create table ops.source (
  id                  uuid primary key default gen_random_uuid(),
  type                text not null check (type in (
                        'official_site', 'ecommerce', 'marketplace', 'social_api', 'forum',
                        'trends', 'scientific', 'regulatory', 'market_data')),
  name                text not null,
  base_url            text not null unique,
  access_method       text not null default 'manual' check (access_method in (
                        'api', 'licensed', 'crawler', 'browser', 'manual', 'blocked')),
  ecommerce_platform  text,
  tos_reviewed_at     timestamptz,
  tos_review_notes    text,
  robots_allowed      boolean,
  rate_limit_rps      numeric(6,3) check (rate_limit_rps > 0),
  active              boolean not null default false,
  notes               text,
  created_at          timestamptz not null default now(),
  updated_at          timestamptz not null default now(),
  -- C-01/C-02: fonte só fica ativa após revisão de termos; crawler/browser exigem robots permitido.
  constraint source_active_compliance_ck check (
    not active
    or (
      tos_reviewed_at is not null
      and access_method <> 'blocked'
      and (access_method not in ('crawler', 'browser') or robots_allowed is true)
    )
  ),
  -- C-03: plataformas sociais fechadas apenas por API oficial, licença ou exportação manual autorizada.
  constraint source_social_method_ck check (
    type <> 'social_api' or access_method in ('api', 'licensed', 'manual', 'blocked')
  )
);
comment on table ops.source is 'Cadastro de fontes de coleta (camada 1). Uma fonte pode servir a várias marcas (core.brand_source).';
comment on column ops.source.type is 'official_site | ecommerce | marketplace | social_api | forum | trends | scientific | regulatory | market_data.';
comment on column ops.source.access_method is 'api | licensed | crawler | browser | manual | blocked. "blocked" registra fonte inviável após revisão F0-07 (SPEC §18).';
comment on column ops.source.ecommerce_platform is 'Plataforma identificada por fingerprint (VTEX, Shopify, Nuvemshop, Magento...) para reaproveitar parsers (§5.2).';
comment on column ops.source.tos_reviewed_at is 'Data da revisão de termos de uso/robots.txt (F0-07). NULL = não revisada; fonte não pode ser ativada.';
comment on column ops.source.robots_allowed is 'Resultado da revisão do robots.txt. NULL = não revisado.';
comment on column ops.source.rate_limit_rps is 'Limite de requisições por segundo para o domínio (C-05). Padrão global em config/rate_limits.yaml.';
comment on column ops.source.active is 'Fonte habilitada para coleta. Exige revisão de compliance (constraint source_active_compliance_ck).';

create trigger source_set_updated_at before update on ops.source
  for each row execute function ops.set_updated_at();

-- -----------------------------------------------------------------------------
-- ops.job_queue — fila de jobs em Postgres (DEC-03)
-- -----------------------------------------------------------------------------
create table ops.job_queue (
  id             uuid primary key default gen_random_uuid(),
  job_type       text not null,
  payload        jsonb not null default '{}'::jsonb,
  priority       smallint not null default 100,
  status         text not null default 'queued' check (status in ('queued', 'running', 'succeeded', 'failed', 'dead')),
  attempts       smallint not null default 0 check (attempts >= 0),
  max_attempts   smallint not null default 3 check (max_attempts > 0),
  scheduled_for  timestamptz not null default now(),
  locked_at      timestamptz,
  locked_by      text,
  last_error     text,
  finished_at    timestamptz,
  created_at     timestamptz not null default now()
);
comment on table ops.job_queue is 'Fila de jobs consumida pelo worker Python (DEC-03). Dequeue com SELECT ... FOR UPDATE SKIP LOCKED.';
comment on column ops.job_queue.priority is 'Menor valor = maior prioridade.';
comment on column ops.job_queue.status is 'queued | running | succeeded | failed | dead (excedeu max_attempts).';
comment on column ops.job_queue.locked_by is 'Identificador do worker que reservou o job.';

create index job_queue_dequeue_idx on ops.job_queue (priority, scheduled_for) where status = 'queued';

-- -----------------------------------------------------------------------------
-- ops.crawl_run / ops.crawl_log — execução e log de coleta (G-09, C-02)
-- -----------------------------------------------------------------------------
create table ops.crawl_run (
  id                 uuid primary key default gen_random_uuid(),
  source_id          uuid not null references ops.source(id),
  job_id             uuid references ops.job_queue(id),
  collector_version  text,
  started_at         timestamptz not null default now(),
  finished_at        timestamptz,
  status             text not null default 'running' check (status in ('running', 'succeeded', 'partial', 'failed', 'cancelled')),
  pages_fetched      integer not null default 0 check (pages_fetched >= 0),
  pages_blocked      integer not null default 0 check (pages_blocked >= 0),
  pages_failed       integer not null default 0 check (pages_failed >= 0),
  cost_brl           numeric(12,4),
  check (finished_at is null or finished_at >= started_at)
);
comment on table ops.crawl_run is 'Uma execução de coleta sobre uma fonte.';
comment on column ops.crawl_run.status is 'running | succeeded | partial (houve bloqueios/falhas) | failed | cancelled.';
comment on column ops.crawl_run.cost_brl is 'Custo consolidado da execução; detalhamento em ops.cost_ledger (A-06).';

create index crawl_run_source_idx on ops.crawl_run (source_id, started_at desc);

create table ops.crawl_log (
  id            uuid primary key default gen_random_uuid(),
  crawl_run_id  uuid not null references ops.crawl_run(id),
  url           text not null,
  http_status   smallint,
  outcome       text not null check (outcome in (
                  'ok', 'not_modified', 'blocked', 'captcha', 'login_required', 'not_found',
                  'parse_error', 'robots_disallowed', 'rate_limited', 'network_error')),
  message       text,
  created_at    timestamptz not null default now()
);
comment on table ops.crawl_log is 'Log por URL (append-only). Bloqueio/CAPTCHA/login são registrados e a coleta segue, sem contorno (C-02, G-09).';
comment on column ops.crawl_log.outcome is
  'ok | not_modified (ETag/Last-Modified) | blocked | captcha | login_required | not_found | parse_error | robots_disallowed | rate_limited | network_error.';

create index crawl_log_run_idx on ops.crawl_log (crawl_run_id);
create index crawl_log_outcome_idx on ops.crawl_log (outcome, created_at desc) where outcome <> 'ok';

create trigger crawl_log_immutable before update on ops.crawl_log
  for each row execute function ops.forbid_update();

-- -----------------------------------------------------------------------------
-- ops.cost_ledger — custos por execução (A-06)
-- -----------------------------------------------------------------------------
create table ops.cost_ledger (
  id                uuid primary key default gen_random_uuid(),
  run_type          text not null check (run_type in (
                      'crawl', 'extraction', 'classification', 'embedding', 'council', 'radar', 'other')),
  run_id            uuid,
  provider          text,
  model             text,
  prompt_version    text,
  tokens_in         integer check (tokens_in >= 0),
  tokens_out        integer check (tokens_out >= 0),
  browser_seconds   numeric(10,2) check (browser_seconds >= 0),
  cost_original     numeric(14,6),
  currency_original char(3),
  fx_rate_brl       numeric(12,6),
  cost_brl          numeric(14,6) not null,
  created_at        timestamptz not null default now()
);
comment on table ops.cost_ledger is 'Custo de tokens, navegador e coleta por execução (A-06, AC-10).';
comment on column ops.cost_ledger.run_id is 'ID da execução de origem (crawl_run, sessão do Conselho etc.), interpretado conforme run_type.';
comment on column ops.cost_ledger.cost_original is 'Custo na moeda cobrada pelo provedor (ex.: USD).';
comment on column ops.cost_ledger.fx_rate_brl is 'Câmbio usado na conversão para BRL. Fonte do câmbio a definir.';

create index cost_ledger_run_idx on ops.cost_ledger (run_type, run_id);
create index cost_ledger_created_idx on ops.cost_ledger (created_at);

-- -----------------------------------------------------------------------------
-- ops.human_review — correções humanas (G-10)
-- -----------------------------------------------------------------------------
create table ops.human_review (
  id                uuid primary key default gen_random_uuid(),
  entity_table      text not null,
  entity_id         uuid not null,
  field             text not null,
  old_value         jsonb,
  new_value         jsonb,
  reason            text not null check (length(trim(reason)) > 0),
  reviewer          text not null,
  reviewer_user_id  uuid,
  created_at        timestamptz not null default now(),
  applied_to_rules  boolean not null default false,
  applied_at        timestamptz,
  check (not applied_to_rules or applied_at is not null)
);
comment on table ops.human_review is 'Trilha de correções humanas: quem, quando, valor anterior, novo valor e motivo (G-10, AC-15). Append-only, exceto marcação de retroalimentação.';
comment on column ops.human_review.entity_table is 'Tabela qualificada da entidade corrigida, ex.: core.product.';
comment on column ops.human_review.reviewer_user_id is 'auth.users.id quando a autenticação estiver definida (Q-19).';
comment on column ops.human_review.applied_to_rules is 'true quando a correção já retroalimentou regras/prompts/golden set.';

create index human_review_entity_idx on ops.human_review (entity_table, entity_id);
create index human_review_pending_rules_idx on ops.human_review (created_at) where not applied_to_rules;

create trigger human_review_append_only before update on ops.human_review
  for each row execute function ops.forbid_update('applied_to_rules', 'applied_at');

-- -----------------------------------------------------------------------------
-- ops.coverage_report — cobertura real (G-09, AC-09)
-- -----------------------------------------------------------------------------
create table ops.coverage_report (
  id                   uuid primary key default gen_random_uuid(),
  period_start         date not null,
  period_end           date not null,
  brands_targeted      integer not null check (brands_targeted >= 0),
  brands_collected     integer not null check (brands_collected >= 0),
  skus_collected       integer not null check (skus_collected >= 0),
  pages_accessed       integer check (pages_accessed >= 0),
  pages_blocked        integer check (pages_blocked >= 0),
  records_incomplete   integer check (records_incomplete >= 0),
  records_unavailable  integer check (records_unavailable >= 0),
  fields_completeness  jsonb not null default '{}'::jsonb,
  blocked_sources      jsonb not null default '[]'::jsonb,
  generated_at         timestamptz not null default now(),
  check (period_end >= period_start)
);
comment on table ops.coverage_report is 'Relatório de cobertura: acessadas, bloqueadas, incompletas, indisponíveis (AC-09). "Não coletado" ≠ "não existe" (G-09).';
comment on column ops.coverage_report.fields_completeness is 'Mapa {"schema.tabela.coluna": pct_preenchido} derivado de ops.traceable_field.';
comment on column ops.coverage_report.blocked_sources is 'Lista de fontes bloqueadas no período com motivo (outcome do crawl_log).';
