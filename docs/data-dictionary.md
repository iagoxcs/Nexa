# NEXA LAB — Dicionário de dados

> **Gerado automaticamente** por `scripts/gen_data_dictionary.py` a partir de `supabase/migrations/` e `supabase/seed/taxonomies/`. Não editar à mão: altere a migration/seed e regenere.

Migrations aplicadas:

- `20261016120000_foundation.sql`
- `20261016120100_ops.sql`
- `20261016120200_raw.sql`
- `20261016120300_core_evidence_taxonomies.sql`
- `20261016120400_core_brand.sql`
- `20261016120500_core_product.sql`
- `20261016120600_core_consumer.sql`
- `20261016120700_core_market.sql`
- `20261016120800_security.sql`

## Convenções

### Campo rastreável (SPEC §4.1 + G-01 + G-03)

Colunas marcadas com **[R]** foram criadas por `ops.add_traceable_field()` e possuem quatro colunas auxiliares, omitidas das tabelas abaixo para legibilidade:

| Coluna auxiliar | Tipo | Regra |
|---|---|---|
| `<campo>_is_inferred` | boolean | `true` se o valor não foi declarado pela fonte |
| `<campo>_confidence` | numeric(3,2) | 0.00–1.00 |
| `<campo>_evidence_id` | uuid → `core.evidence` | trecho que sustenta o valor |
| `<campo>_missing_reason` | text | motivo da ausência |

Constraints aplicadas a cada campo rastreável:

- valor preenchido ⇒ `is_inferred`, `confidence` e `evidence_id` obrigatórios (G-01, G-02);
- valor `NULL` ⇔ `missing_reason` preenchido (G-03, G-09);
- `missing_reason` ∈ `not_collected` · `not_published` · `source_blocked` · `parse_error` · `low_confidence` · `ambiguous` · `not_applicable`. `not_collected` (não tentado) é distinto de `not_published` (fonte acessada, informação inexistente).

Atributos multivalorados (ingredientes, claims, benefícios) usam rastreio por linha: `evidence_id NOT NULL` + `confidence` (+ `is_inferred`).

### Versionamento (G-04)

- `brand`, `product`, `product_variant` e `packaging`: SCD tipo 2 por snapshot jsonb em `<entidade>_version`, preenchido pelo trigger `ops.capture_version()`; `DELETE` bloqueado. Colunas de controle de coleta (`updated_at`, `last_seen_at`, `last_collected_at`, `consecutive_misses`) não geram versão. A origem da alteração é gravada a partir de `set local nexa.change_origin = '...'`.
- `product_ingredient`, `claim`, `product_benefit`: SCD2 inline (`valid_from`/`valid_to`); vigente = `valid_to IS NULL`.
- `signal_classification`: reclassificação preenche `superseded_at` e insere nova linha.
- Imutáveis (trigger `ops.forbid_update`): `raw.raw_document` (exceto `last_fetched_at`, `fetch_count`), `core.evidence`, `ops.crawl_log`, `ops.human_review` (exceto `applied_to_rules`, `applied_at`), `core.consumer_signal` (exceto vínculos de marca/produto).

### Segurança

RLS habilitado em todas as tabelas, sem policies: apenas `service_role` acessa (usuários/perfis pendentes — SPEC Q-19). Os schemas `ops`, `raw` e `core` não são expostos pela API REST do Supabase até configuração explícita.

## Schema `ops` — operação

### `ops.cost_ledger`

Custo de tokens, navegador e coleta por execução (A-06, AC-10).

| Coluna | Tipo | Nulo | Default | Descrição |
|---|---|---|---|---|
| `id` | uuid | não | `gen_random_uuid()` | Chave primária (UUID). |
| `run_type` | text | não |  |  |
| `run_id` | uuid | sim |  | ID da execução de origem (crawl_run, sessão do Conselho etc.), interpretado conforme run_type. |
| `provider` | text | sim |  |  |
| `model` | text | sim |  |  |
| `prompt_version` | text | sim |  |  |
| `tokens_in` | integer | sim |  |  |
| `tokens_out` | integer | sim |  |  |
| `browser_seconds` | numeric(10,2) | sim |  |  |
| `cost_original` | numeric(14,6) | sim |  | Custo na moeda cobrada pelo provedor (ex.: USD). |
| `currency_original` | character(3) | sim |  |  |
| `fx_rate_brl` | numeric(12,6) | sim |  | Câmbio usado na conversão para BRL. Fonte do câmbio a definir. |
| `cost_brl` | numeric(14,6) | não |  |  |
| `created_at` | timestamp with time zone | não | `now()` | Data/hora de criação do registro. |

<details><summary>Constraints</summary>

- **CHECK** `cost_ledger_browser_seconds_check`: `CHECK ((browser_seconds >= (0)::numeric))`
- **CHECK** `cost_ledger_run_type_check`: `CHECK ((run_type = ANY (ARRAY['crawl'::text, 'extraction'::text, 'classification'::text, 'embedding'::text, 'council'::text, 'radar'::text, 'other'::text])))`
- **CHECK** `cost_ledger_tokens_in_check`: `CHECK ((tokens_in >= 0))`
- **CHECK** `cost_ledger_tokens_out_check`: `CHECK ((tokens_out >= 0))`
- **PK** `cost_ledger_pkey`: `PRIMARY KEY (id)`

</details>

<details><summary>Índices</summary>

- `cost_ledger_created_idx`: `CREATE INDEX cost_ledger_created_idx ON ops.cost_ledger USING btree (created_at)`
- `cost_ledger_run_idx`: `CREATE INDEX cost_ledger_run_idx ON ops.cost_ledger USING btree (run_type, run_id)`

</details>

### `ops.coverage_report`

Relatório de cobertura: acessadas, bloqueadas, incompletas, indisponíveis (AC-09). "Não coletado" ≠ "não existe" (G-09).

| Coluna | Tipo | Nulo | Default | Descrição |
|---|---|---|---|---|
| `id` | uuid | não | `gen_random_uuid()` | Chave primária (UUID). |
| `period_start` | date | não |  |  |
| `period_end` | date | não |  |  |
| `brands_targeted` | integer | não |  |  |
| `brands_collected` | integer | não |  |  |
| `skus_collected` | integer | não |  |  |
| `pages_accessed` | integer | sim |  |  |
| `pages_blocked` | integer | sim |  |  |
| `records_incomplete` | integer | sim |  |  |
| `records_unavailable` | integer | sim |  |  |
| `fields_completeness` | jsonb | não | `'{}'::jsonb` | Mapa {"schema.tabela.coluna": pct_preenchido} derivado de ops.traceable_field. |
| `blocked_sources` | jsonb | não | `'[]'::jsonb` | Lista de fontes bloqueadas no período com motivo (outcome do crawl_log). |
| `generated_at` | timestamp with time zone | não | `now()` |  |

<details><summary>Constraints</summary>

- **CHECK** `coverage_report_brands_collected_check`: `CHECK ((brands_collected >= 0))`
- **CHECK** `coverage_report_brands_targeted_check`: `CHECK ((brands_targeted >= 0))`
- **CHECK** `coverage_report_check`: `CHECK ((period_end >= period_start))`
- **CHECK** `coverage_report_pages_accessed_check`: `CHECK ((pages_accessed >= 0))`
- **CHECK** `coverage_report_pages_blocked_check`: `CHECK ((pages_blocked >= 0))`
- **CHECK** `coverage_report_records_incomplete_check`: `CHECK ((records_incomplete >= 0))`
- **CHECK** `coverage_report_records_unavailable_check`: `CHECK ((records_unavailable >= 0))`
- **CHECK** `coverage_report_skus_collected_check`: `CHECK ((skus_collected >= 0))`
- **PK** `coverage_report_pkey`: `PRIMARY KEY (id)`

</details>

### `ops.crawl_log`

Log por URL (append-only). Bloqueio/CAPTCHA/login são registrados e a coleta segue, sem contorno (C-02, G-09).

| Coluna | Tipo | Nulo | Default | Descrição |
|---|---|---|---|---|
| `id` | uuid | não | `gen_random_uuid()` | Chave primária (UUID). |
| `crawl_run_id` | uuid | não |  | FK → `ops.crawl_run`. |
| `url` | text | não |  |  |
| `http_status` | smallint | sim |  |  |
| `outcome` | text | não |  | ok \| not_modified (ETag/Last-Modified) \| blocked \| captcha \| login_required \| not_found \| parse_error \| robots_disallowed \| rate_limited \| network_error. |
| `message` | text | sim |  |  |
| `created_at` | timestamp with time zone | não | `now()` | Data/hora de criação do registro. |

<details><summary>Constraints</summary>

- **CHECK** `crawl_log_outcome_check`: `CHECK ((outcome = ANY (ARRAY['ok'::text, 'not_modified'::text, 'blocked'::text, 'captcha'::text, 'login_required'::text, 'not_found'::text, 'parse_error'::text, 'robots_disallowed'::text, 'rate_limited'::text, 'network_error'::text])))`
- **FK** `crawl_log_crawl_run_id_fkey`: `FOREIGN KEY (crawl_run_id) REFERENCES ops.crawl_run(id)`
- **PK** `crawl_log_pkey`: `PRIMARY KEY (id)`

</details>

<details><summary>Índices</summary>

- `crawl_log_outcome_idx`: `CREATE INDEX crawl_log_outcome_idx ON ops.crawl_log USING btree (outcome, created_at DESC) WHERE (outcome <> 'ok'::text)`
- `crawl_log_run_idx`: `CREATE INDEX crawl_log_run_idx ON ops.crawl_log USING btree (crawl_run_id)`

</details>

<details><summary>Triggers</summary>

- `crawl_log_immutable`: `CREATE TRIGGER crawl_log_immutable BEFORE UPDATE ON ops.crawl_log FOR EACH ROW EXECUTE FUNCTION ops.forbid_update()`

</details>

### `ops.crawl_run`

Uma execução de coleta sobre uma fonte.

| Coluna | Tipo | Nulo | Default | Descrição |
|---|---|---|---|---|
| `id` | uuid | não | `gen_random_uuid()` | Chave primária (UUID). |
| `source_id` | uuid | não |  | FK → `ops.source`. |
| `job_id` | uuid | sim |  | FK → `ops.job_queue`. |
| `collector_version` | text | sim |  |  |
| `started_at` | timestamp with time zone | não | `now()` |  |
| `finished_at` | timestamp with time zone | sim |  |  |
| `status` | text | não | `'running'::text` | running \| succeeded \| partial (houve bloqueios/falhas) \| failed \| cancelled. |
| `pages_fetched` | integer | não | `0` |  |
| `pages_blocked` | integer | não | `0` |  |
| `pages_failed` | integer | não | `0` |  |
| `cost_brl` | numeric(12,4) | sim |  | Custo consolidado da execução; detalhamento em ops.cost_ledger (A-06). |

<details><summary>Constraints</summary>

- **CHECK** `crawl_run_check`: `CHECK (((finished_at IS NULL) OR (finished_at >= started_at)))`
- **CHECK** `crawl_run_pages_blocked_check`: `CHECK ((pages_blocked >= 0))`
- **CHECK** `crawl_run_pages_failed_check`: `CHECK ((pages_failed >= 0))`
- **CHECK** `crawl_run_pages_fetched_check`: `CHECK ((pages_fetched >= 0))`
- **CHECK** `crawl_run_status_check`: `CHECK ((status = ANY (ARRAY['running'::text, 'succeeded'::text, 'partial'::text, 'failed'::text, 'cancelled'::text])))`
- **FK** `crawl_run_job_id_fkey`: `FOREIGN KEY (job_id) REFERENCES ops.job_queue(id)`
- **FK** `crawl_run_source_id_fkey`: `FOREIGN KEY (source_id) REFERENCES ops.source(id)`
- **PK** `crawl_run_pkey`: `PRIMARY KEY (id)`

</details>

<details><summary>Índices</summary>

- `crawl_run_source_idx`: `CREATE INDEX crawl_run_source_idx ON ops.crawl_run USING btree (source_id, started_at DESC)`

</details>

### `ops.human_review`

Trilha de correções humanas: quem, quando, valor anterior, novo valor e motivo (G-10, AC-15). Append-only, exceto marcação de retroalimentação.

| Coluna | Tipo | Nulo | Default | Descrição |
|---|---|---|---|---|
| `id` | uuid | não | `gen_random_uuid()` | Chave primária (UUID). |
| `entity_table` | text | não |  | Tabela qualificada da entidade corrigida, ex.: core.product. |
| `entity_id` | uuid | não |  |  |
| `field` | text | não |  |  |
| `old_value` | jsonb | sim |  |  |
| `new_value` | jsonb | sim |  |  |
| `reason` | text | não |  |  |
| `reviewer` | text | não |  |  |
| `reviewer_user_id` | uuid | sim |  | auth.users.id quando a autenticação estiver definida (Q-19). |
| `created_at` | timestamp with time zone | não | `now()` | Data/hora de criação do registro. |
| `applied_to_rules` | boolean | não | `false` | true quando a correção já retroalimentou regras/prompts/golden set. |
| `applied_at` | timestamp with time zone | sim |  |  |

<details><summary>Constraints</summary>

- **CHECK** `human_review_check`: `CHECK (((NOT applied_to_rules) OR (applied_at IS NOT NULL)))`
- **CHECK** `human_review_reason_check`: `CHECK ((length(TRIM(BOTH FROM reason)) > 0))`
- **PK** `human_review_pkey`: `PRIMARY KEY (id)`

</details>

<details><summary>Índices</summary>

- `human_review_entity_idx`: `CREATE INDEX human_review_entity_idx ON ops.human_review USING btree (entity_table, entity_id)`
- `human_review_pending_rules_idx`: `CREATE INDEX human_review_pending_rules_idx ON ops.human_review USING btree (created_at) WHERE (NOT applied_to_rules)`

</details>

<details><summary>Triggers</summary>

- `human_review_append_only`: `CREATE TRIGGER human_review_append_only BEFORE UPDATE ON ops.human_review FOR EACH ROW EXECUTE FUNCTION ops.forbid_update('applied_to_rules', 'applied_at')`

</details>

### `ops.job_queue`

Fila de jobs consumida pelo worker Python (DEC-03). Dequeue com SELECT ... FOR UPDATE SKIP LOCKED.

| Coluna | Tipo | Nulo | Default | Descrição |
|---|---|---|---|---|
| `id` | uuid | não | `gen_random_uuid()` | Chave primária (UUID). |
| `job_type` | text | não |  |  |
| `payload` | jsonb | não | `'{}'::jsonb` |  |
| `priority` | smallint | não | `100` | Menor valor = maior prioridade. |
| `status` | text | não | `'queued'::text` | queued \| running \| succeeded \| failed \| dead (excedeu max_attempts). |
| `attempts` | smallint | não | `0` |  |
| `max_attempts` | smallint | não | `3` |  |
| `scheduled_for` | timestamp with time zone | não | `now()` |  |
| `locked_at` | timestamp with time zone | sim |  |  |
| `locked_by` | text | sim |  | Identificador do worker que reservou o job. |
| `last_error` | text | sim |  |  |
| `finished_at` | timestamp with time zone | sim |  |  |
| `created_at` | timestamp with time zone | não | `now()` | Data/hora de criação do registro. |

<details><summary>Constraints</summary>

- **CHECK** `job_queue_attempts_check`: `CHECK ((attempts >= 0))`
- **CHECK** `job_queue_max_attempts_check`: `CHECK ((max_attempts > 0))`
- **CHECK** `job_queue_status_check`: `CHECK ((status = ANY (ARRAY['queued'::text, 'running'::text, 'succeeded'::text, 'failed'::text, 'dead'::text])))`
- **PK** `job_queue_pkey`: `PRIMARY KEY (id)`

</details>

<details><summary>Índices</summary>

- `job_queue_dequeue_idx`: `CREATE INDEX job_queue_dequeue_idx ON ops.job_queue USING btree (priority, scheduled_for) WHERE (status = 'queued'::text)`

</details>

### `ops.source`

Cadastro de fontes de coleta (camada 1). Uma fonte pode servir a várias marcas (core.brand_source).

| Coluna | Tipo | Nulo | Default | Descrição |
|---|---|---|---|---|
| `id` | uuid | não | `gen_random_uuid()` | Chave primária (UUID). |
| `type` | text | não |  | official_site \| ecommerce \| marketplace \| social_api \| forum \| trends \| scientific \| regulatory \| market_data. |
| `name` | text | não |  |  |
| `base_url` | text | não |  |  |
| `access_method` | text | não | `'manual'::text` | api \| licensed \| crawler \| browser \| manual \| blocked. "blocked" registra fonte inviável após revisão F0-07 (SPEC §18). |
| `ecommerce_platform` | text | sim |  | Plataforma identificada por fingerprint (VTEX, Shopify, Nuvemshop, Magento...) para reaproveitar parsers (§5.2). |
| `tos_reviewed_at` | timestamp with time zone | sim |  | Data da revisão de termos de uso/robots.txt (F0-07). NULL = não revisada; fonte não pode ser ativada. |
| `tos_review_notes` | text | sim |  |  |
| `robots_allowed` | boolean | sim |  | Resultado da revisão do robots.txt. NULL = não revisado. |
| `rate_limit_rps` | numeric(6,3) | sim |  | Limite de requisições por segundo para o domínio (C-05). Padrão global em config/rate_limits.yaml. |
| `active` | boolean | não | `false` | Fonte habilitada para coleta. Exige revisão de compliance (constraint source_active_compliance_ck). |
| `notes` | text | sim |  |  |
| `created_at` | timestamp with time zone | não | `now()` | Data/hora de criação do registro. |
| `updated_at` | timestamp with time zone | não | `now()` | Data/hora da última alteração (trigger ops.set_updated_at). |

<details><summary>Constraints</summary>

- **CHECK** `source_access_method_check`: `CHECK ((access_method = ANY (ARRAY['api'::text, 'licensed'::text, 'crawler'::text, 'browser'::text, 'manual'::text, 'blocked'::text])))`
- **CHECK** `source_active_compliance_ck`: `CHECK (((NOT active) OR ((tos_reviewed_at IS NOT NULL) AND (access_method <> 'blocked'::text) AND ((access_method <> ALL (ARRAY['crawler'::text, 'browser'::text])) OR (robots_allowed IS TRUE)))))`
- **CHECK** `source_rate_limit_rps_check`: `CHECK ((rate_limit_rps > (0)::numeric))`
- **CHECK** `source_social_method_ck`: `CHECK (((type <> 'social_api'::text) OR (access_method = ANY (ARRAY['api'::text, 'licensed'::text, 'manual'::text, 'blocked'::text]))))`
- **CHECK** `source_type_check`: `CHECK ((type = ANY (ARRAY['official_site'::text, 'ecommerce'::text, 'marketplace'::text, 'social_api'::text, 'forum'::text, 'trends'::text, 'scientific'::text, 'regulatory'::text, 'market_data'::text])))`
- **PK** `source_pkey`: `PRIMARY KEY (id)`
- **UNIQUE** `source_base_url_key`: `UNIQUE (base_url)`

</details>

<details><summary>Triggers</summary>

- `source_set_updated_at`: `CREATE TRIGGER source_set_updated_at BEFORE UPDATE ON ops.source FOR EACH ROW EXECUTE FUNCTION ops.set_updated_at()`

</details>

### `ops.traceable_field`

Registro dos atributos criados com ops.add_traceable_field(). Base para relatório de completude por campo (AC-01, AC-09).

| Coluna | Tipo | Nulo | Default | Descrição |
|---|---|---|---|---|
| `table_schema` | text | não |  |  |
| `table_name` | text | não |  |  |
| `column_name` | text | não |  |  |
| `data_type` | text | não |  |  |
| `description` | text | sim |  |  |
| `created_at` | timestamp with time zone | não | `now()` | Data/hora de criação do registro. |

<details><summary>Constraints</summary>

- **PK** `traceable_field_pkey`: `PRIMARY KEY (table_schema, table_name, column_name)`

</details>

## Schema `raw` — documentos brutos

### `raw.raw_document`

Documento bruto imutável. Mesmo URL com novo content_hash = nova linha encadeada por previous_document_id (§4.4).

| Coluna | Tipo | Nulo | Default | Descrição |
|---|---|---|---|---|
| `id` | uuid | não | `gen_random_uuid()` | Chave primária (UUID). |
| `source_id` | uuid | não |  | FK → `ops.source`. |
| `crawl_run_id` | uuid | sim |  | FK → `ops.crawl_run`. |
| `url` | text | não |  | URL solicitada. |
| `final_url` | text | sim |  | URL após redirecionamentos. |
| `fetched_at` | timestamp with time zone | não |  | Primeira coleta deste conteúdo (hash). |
| `last_fetched_at` | timestamp with time zone | não |  | Última coleta em que o mesmo hash foi observado. Única coluna atualizável junto com fetch_count. |
| `fetch_count` | integer | não | `1` |  |
| `http_status` | smallint | sim |  |  |
| `content_hash` | character(64) | não |  | SHA-256 hexadecimal do conteúdo bruto. |
| `content_type` | text | sim |  |  |
| `content_length` | bigint | sim |  |  |
| `storage_path` | text | não |  | Caminho do arquivo bruto no Supabase Storage. |
| `structured_data` | jsonb | sim |  | JSON-LD/schema.org/microdata extraído (extruct), sem interpretação. |
| `http_headers` | jsonb | sim |  | Cabeçalhos de resposta. Não armazenar Set-Cookie nem cabeçalhos com dados pessoais (C-04). |
| `etag` | text | sim |  |  |
| `last_modified` | timestamp with time zone | sim |  |  |
| `previous_document_id` | uuid | sim |  | FK → `raw.raw_document`. Versão anterior do mesmo URL, para diff de conteúdo. |
| `created_at` | timestamp with time zone | não | `now()` | Data/hora de criação do registro. |

<details><summary>Constraints</summary>

- **CHECK** `raw_document_check`: `CHECK ((last_fetched_at >= fetched_at))`
- **CHECK** `raw_document_content_hash_check`: `CHECK ((content_hash ~ '^[0-9a-f]{64}$'::text))`
- **CHECK** `raw_document_content_length_check`: `CHECK ((content_length >= 0))`
- **CHECK** `raw_document_fetch_count_check`: `CHECK ((fetch_count >= 1))`
- **FK** `raw_document_crawl_run_id_fkey`: `FOREIGN KEY (crawl_run_id) REFERENCES ops.crawl_run(id)`
- **FK** `raw_document_previous_document_id_fkey`: `FOREIGN KEY (previous_document_id) REFERENCES raw.raw_document(id)`
- **FK** `raw_document_source_id_fkey`: `FOREIGN KEY (source_id) REFERENCES ops.source(id)`
- **PK** `raw_document_pkey`: `PRIMARY KEY (id)`
- **UNIQUE** `raw_document_url_content_hash_key`: `UNIQUE (url, content_hash)`

</details>

<details><summary>Índices</summary>

- `raw_document_run_idx`: `CREATE INDEX raw_document_run_idx ON raw.raw_document USING btree (crawl_run_id)`
- `raw_document_source_idx`: `CREATE INDEX raw_document_source_idx ON raw.raw_document USING btree (source_id, fetched_at DESC)`
- `raw_document_url_idx`: `CREATE INDEX raw_document_url_idx ON raw.raw_document USING btree (url, fetched_at DESC)`

</details>

<details><summary>Triggers</summary>

- `raw_document_immutable`: `CREATE TRIGGER raw_document_immutable BEFORE UPDATE ON raw.raw_document FOR EACH ROW EXECUTE FUNCTION ops.forbid_update('last_fetched_at', 'fetch_count')`

</details>

## Schema `core` — entidades normalizadas

### `core.benefit`

Taxonomia de benefício normalizado. O texto literal da alegação fica em core.claim (claim_text_exact).

| Coluna | Tipo | Nulo | Default | Descrição |
|---|---|---|---|---|
| `id` | uuid | não | `gen_random_uuid()` | Chave primária (UUID). |
| `code` | text | não |  | Código estável (slug) usado em seeds, filtros e integrações. |
| `name_pt` | text | não |  | Nome de exibição em pt-BR. |
| `benefit_group` | text | não |  |  |
| `description` | text | sim |  |  |
| `sort_order` | integer | não | `0` | Ordem de exibição. |
| `active` | boolean | não | `true` | Item ativo para uso. |
| `created_at` | timestamp with time zone | não | `now()` | Data/hora de criação do registro. |
| `updated_at` | timestamp with time zone | não | `now()` | Data/hora da última alteração (trigger ops.set_updated_at). |

<details><summary>Constraints</summary>

- **CHECK** `benefit_benefit_group_check`: `CHECK ((benefit_group = ANY (ARRAY['hidratacao_barreira'::text, 'protecao'::text, 'tratamento'::text, 'limpeza'::text, 'maquiagem_acabamento'::text, 'sensorial_bem_estar'::text, 'capilar'::text])))`
- **CHECK** `benefit_code_check`: `CHECK ((code ~ '^[a-z0-9_]+$'::text))`
- **PK** `benefit_pkey`: `PRIMARY KEY (id)`
- **UNIQUE** `benefit_code_key`: `UNIQUE (code)`

</details>

<details><summary>Triggers</summary>

- `benefit_set_updated_at`: `CREATE TRIGGER benefit_set_updated_at BEFORE UPDATE ON core.benefit FOR EACH ROW EXECUTE FUNCTION ops.set_updated_at()`

</details>

### `core.brand`

Marca monitorada. Atributos extraídos/inferidos seguem o padrão rastreável (§4.1). Histórico em core.brand_version.

| Coluna | Tipo | Nulo | Default | Descrição |
|---|---|---|---|---|
| `id` | uuid | não | `gen_random_uuid()` | Chave primária (UUID). |
| `name` | text | não |  | Nome da marca conforme lista-mãe (§18). |
| `official_url` | text | sim |  |  |
| `site_region` | text | sim |  | Região do site oficial pelo domínio (BR \| INTL), conforme coluna "Origem" da lista-mãe. Não é nacionalidade da empresa (ver country). |
| `priority_level` | text | não |  | Nível de prioridade: P1-A \| P1 \| P2 (§18). |
| `nexa_focus` | text | sim |  | Motivo do monitoramento definido pelo NEXA (coluna "Foco NEXA" da lista-mãe). Não é atributo da marca. |
| `marketplace_presence` | jsonb | não | `'[]'::jsonb` | Lista [{source_id, store_url, observed_at, evidence_id}] de presença observada em marketplaces. |
| `social_handles` | jsonb | não | `'[]'::jsonb` | Lista [{platform, handle, url, observed_at, evidence_id}] de perfis oficiais. Sem métricas de seguidores como proxy de mercado (G-07). |
| `last_collected_at` | timestamp with time zone | sim |  | Data da última coleta bem-sucedida de qualquer fonte da marca. |
| `created_at` | timestamp with time zone | não | `now()` | Data/hora de criação do registro. |
| `updated_at` | timestamp with time zone | não | `now()` | Data/hora da última alteração (trigger ops.set_updated_at). |
| `country` **[R]** | character(2) | sim |  | País de origem da marca (ISO 3166-1 alfa-2). Coletado, nunca deduzido do domínio (§18, G-03). |
| `founded_year` **[R]** | smallint | sim |  | Ano de fundação. |
| `positioning` **[R]** | text | sim |  | Posicionamento da marca (síntese). |
| `competitive_archetype` **[R]** | text | sim |  | Arquétipo competitivo. Taxonomia ainda não definida na SPEC. |
| `declared_audience` **[R]** | text | sim |  | Público declarado pela marca. Sempre is_inferred = false. |
| `inferred_audience` **[R]** | text | sim |  | Público inferido. Sempre is_inferred = true; geração/idade não inferida por estética (G-08). |
| `sales_channels` **[R]** | text[] | sim |  | Canais de venda observados (site próprio, marketplace, farmácia, varejo, venda direta...). |
| `price_tier` **[R]** | text | sim |  | Faixa de preço da marca. Critério de corte ainda não definido na SPEC. |
| `founder_influencer` **[R]** | text | sim |  | Fundador(a) ou influenciador(a) associado(a) publicamente à marca. |
| `value_proposition` **[R]** | text | sim |  | Proposta de valor declarada. |
| `declared_differentials` **[R]** | text[] | sim |  | Diferenciais declarados pela marca (texto da fonte). |
| `approx_sku_count` **[R]** | integer | sim |  | Quantidade aproximada de SKUs observados no site oficial. |

<details><summary>Constraints</summary>

- **CHECK** `brand_approx_sku_count_check`: `CHECK ((approx_sku_count >= 0))`
- **CHECK** `brand_declared_audience_declared_ck`: `CHECK ((declared_audience_is_inferred IS DISTINCT FROM true))`
- **CHECK** `brand_founded_year_check`: `CHECK (((founded_year >= 1800) AND (founded_year <= 2100)))`
- **CHECK** `brand_inferred_audience_inferred_ck`: `CHECK ((inferred_audience_is_inferred IS DISTINCT FROM false))`
- **CHECK** `brand_priority_level_check`: `CHECK ((priority_level = ANY (ARRAY['P1-A'::text, 'P1'::text, 'P2'::text])))`
- **CHECK** `brand_site_region_check`: `CHECK ((site_region = ANY (ARRAY['BR'::text, 'INTL'::text])))`
- **PK** `brand_pkey`: `PRIMARY KEY (id)`
- **UNIQUE** `brand_name_key`: `UNIQUE (name)`

</details>

<details><summary>Triggers</summary>

- `brand_capture_version`: `CREATE TRIGGER brand_capture_version AFTER INSERT OR UPDATE ON core.brand FOR EACH ROW EXECUTE FUNCTION ops.capture_version('core.brand_version', 'brand_id')`
- `brand_no_delete`: `CREATE TRIGGER brand_no_delete BEFORE DELETE ON core.brand FOR EACH ROW EXECUTE FUNCTION ops.forbid_delete()`
- `brand_set_updated_at`: `CREATE TRIGGER brand_set_updated_at BEFORE UPDATE ON core.brand FOR EACH ROW EXECUTE FUNCTION ops.set_updated_at()`

</details>

### `core.brand_source`

Vínculo N:N entre marca e fonte. Resolve fontes compartilhadas (ex.: Fenty Beauty e Fenty Skin em fentybeauty.com, §18).

| Coluna | Tipo | Nulo | Default | Descrição |
|---|---|---|---|---|
| `id` | uuid | não | `gen_random_uuid()` | Chave primária (UUID). |
| `brand_id` | uuid | não |  | FK → `core.brand`. |
| `source_id` | uuid | não |  | FK → `ops.source`. |
| `relation` | text | não |  | official_site \| official_store \| marketplace_store \| social_profile \| other. |
| `created_at` | timestamp with time zone | não | `now()` | Data/hora de criação do registro. |

<details><summary>Constraints</summary>

- **CHECK** `brand_source_relation_check`: `CHECK ((relation = ANY (ARRAY['official_site'::text, 'official_store'::text, 'marketplace_store'::text, 'social_profile'::text, 'other'::text])))`
- **FK** `brand_source_brand_id_fkey`: `FOREIGN KEY (brand_id) REFERENCES core.brand(id)`
- **FK** `brand_source_source_id_fkey`: `FOREIGN KEY (source_id) REFERENCES ops.source(id)`
- **PK** `brand_source_pkey`: `PRIMARY KEY (id)`
- **UNIQUE** `brand_source_brand_id_source_id_relation_key`: `UNIQUE (brand_id, source_id, relation)`

</details>

<details><summary>Índices</summary>

- `brand_source_source_idx`: `CREATE INDEX brand_source_source_idx ON core.brand_source USING btree (source_id)`

</details>

### `core.brand_version`

Histórico SCD2 de core.brand, preenchido por trigger (ops.capture_version). Versão vigente: valid_to IS NULL.

| Coluna | Tipo | Nulo | Default | Descrição |
|---|---|---|---|---|
| `id` | uuid | não | `gen_random_uuid()` | Chave primária (UUID). |
| `brand_id` | uuid | não |  | FK → `core.brand`. |
| `version_no` | integer | não |  | Número sequencial da versão. |
| `valid_from` | timestamp with time zone | não |  | Início de vigência (SCD2). |
| `valid_to` | timestamp with time zone | sim |  | Fim de vigência (SCD2). NULL = vigente. |
| `snapshot` | jsonb | não |  | Linha completa de core.brand no momento da versão. |
| `changed_fields` | text[] | sim |  | Colunas alteradas em relação à versão anterior (NULL na primeira versão). |
| `change_origin` | text | sim |  | Origem da alteração (setting nexa.change_origin), ex.: crawl_run:<uuid>, human_review:<uuid>, seed. |

<details><summary>Constraints</summary>

- **CHECK** `brand_version_check`: `CHECK (((valid_to IS NULL) OR (valid_to >= valid_from)))`
- **CHECK** `brand_version_version_no_check`: `CHECK ((version_no > 0))`
- **FK** `brand_version_brand_id_fkey`: `FOREIGN KEY (brand_id) REFERENCES core.brand(id)`
- **PK** `brand_version_pkey`: `PRIMARY KEY (id)`
- **UNIQUE** `brand_version_brand_id_version_no_key`: `UNIQUE (brand_id, version_no)`

</details>

<details><summary>Índices</summary>

- `brand_version_current_uq`: `CREATE UNIQUE INDEX brand_version_current_uq ON core.brand_version USING btree (brand_id) WHERE (valid_to IS NULL)`

</details>

### `core.category`

Taxonomia de categoria de produto (F0-03). Critério de classificação: benefício principal declarado do produto.

| Coluna | Tipo | Nulo | Default | Descrição |
|---|---|---|---|---|
| `id` | uuid | não | `gen_random_uuid()` | Chave primária (UUID). |
| `code` | text | não |  | Código estável (slug) usado em seeds, filtros e integrações. |
| `name_pt` | text | não |  | Nome de exibição em pt-BR. |
| `description` | text | sim |  |  |
| `sort_order` | integer | não | `0` | Ordem de exibição. |
| `active` | boolean | não | `true` | Item ativo para uso. |
| `created_at` | timestamp with time zone | não | `now()` | Data/hora de criação do registro. |
| `updated_at` | timestamp with time zone | não | `now()` | Data/hora da última alteração (trigger ops.set_updated_at). |

<details><summary>Constraints</summary>

- **CHECK** `category_code_check`: `CHECK ((code ~ '^[a-z0-9_]+$'::text))`
- **PK** `category_pkey`: `PRIMARY KEY (id)`
- **UNIQUE** `category_code_key`: `UNIQUE (code)`

</details>

<details><summary>Triggers</summary>

- `category_set_updated_at`: `CREATE TRIGGER category_set_updated_at BEFORE UPDATE ON core.category FOR EACH ROW EXECUTE FUNCTION ops.set_updated_at()`

</details>

### `core.claim`

Alegação literal do produto. Texto nunca parafraseado; evidence_id obrigatório (AC-03). Alegação ≠ evidência científica (G-06).

| Coluna | Tipo | Nulo | Default | Descrição |
|---|---|---|---|---|
| `id` | uuid | não | `gen_random_uuid()` | Chave primária (UUID). |
| `product_id` | uuid | não |  | FK → `core.product`. |
| `claim_text_exact` | text | não |  | Texto exato da alegação na fonte. |
| `metric_value` | numeric | sim |  | Valor numérico declarado na alegação (ex.: 47 em "reduz 47% das manchas"). |
| `metric_unit` | text | sim |  |  |
| `metric_context` | text | sim |  | Condições declaradas (prazo, amostra, método), quando publicadas. |
| `extraction_confidence` | numeric(3,2) | não |  |  |
| `evidence_id` | uuid | não |  | FK → `core.evidence`. |
| `valid_from` | timestamp with time zone | não | `now()` | Início de vigência (SCD2). |
| `valid_to` | timestamp with time zone | sim |  | Fim de vigência (SCD2). NULL = vigente. |
| `created_at` | timestamp with time zone | não | `now()` | Data/hora de criação do registro. |
| `claim_type` **[R]** | text | sim |  | Tipo de alegação: benefit \| efficacy \| metric \| safety \| sustainability (classificação). |

<details><summary>Constraints</summary>

- **CHECK** `claim_check`: `CHECK (((valid_to IS NULL) OR (valid_to >= valid_from)))`
- **CHECK** `claim_claim_text_exact_check`: `CHECK ((length(claim_text_exact) > 0))`
- **CHECK** `claim_claim_type_check`: `CHECK ((claim_type = ANY (ARRAY['benefit'::text, 'efficacy'::text, 'metric'::text, 'safety'::text, 'sustainability'::text])))`
- **CHECK** `claim_extraction_confidence_check`: `CHECK (((extraction_confidence >= (0)::numeric) AND (extraction_confidence <= (1)::numeric)))`
- **FK** `claim_evidence_id_fkey`: `FOREIGN KEY (evidence_id) REFERENCES core.evidence(id)`
- **FK** `claim_product_id_fkey`: `FOREIGN KEY (product_id) REFERENCES core.product(id)`
- **PK** `claim_pkey`: `PRIMARY KEY (id)`

</details>

<details><summary>Índices</summary>

- `claim_current_uq`: `CREATE UNIQUE INDEX claim_current_uq ON core.claim USING btree (product_id, md5(claim_text_exact)) WHERE (valid_to IS NULL)`

</details>

### `core.consumer_signal`

Sinal público de consumidor (comentário, avaliação, post). Apenas fontes permitidas (C-03). Sem dados pessoais (C-04).

| Coluna | Tipo | Nulo | Default | Descrição |
|---|---|---|---|---|
| `id` | uuid | não | `gen_random_uuid()` | Chave primária (UUID). |
| `source_id` | uuid | não |  | FK → `ops.source`. |
| `raw_document_id` | uuid | sim |  | FK → `raw.raw_document`. |
| `platform` | text | não |  | youtube \| reddit \| tiktok \| instagram \| facebook \| marketplace \| ecommerce \| forum \| search \| other. |
| `signal_kind` | text | não |  |  |
| `external_public_id` | text | sim |  | ID público do conteúdo na plataforma, apenas quando os termos permitem armazená-lo. |
| `url` | text | não |  |  |
| `original_text` | text | não |  | Texto original, sem edição. Base de evidência das classificações. |
| `text_hash` | character(64) | não |  | SHA-256 do texto normalizado, para deduplicação. |
| `language` | text | sim |  |  |
| `published_at` | timestamp with time zone | sim |  |  |
| `collected_at` | timestamp with time zone | não |  |  |
| `author_hash` | character(64) | sim |  | HMAC-SHA256 do identificador do autor com segredo do ambiente. Nome/handle nunca armazenados; anonimizado no BI (C-04). |
| `rating_value` | numeric(4,2) | sim |  | Nota atribuída pelo consumidor, quando o sinal é uma avaliação. |
| `rating_scale_max` | numeric(4,1) | sim |  |  |
| `engagement` | jsonb | não | `'{}'::jsonb` | Métricas públicas (curtidas, respostas, visualizações). Não são proxy de mercado ou vendas (G-07). |
| `created_at` | timestamp with time zone | não | `now()` | Data/hora de criação do registro. |
| `related_brand_id` **[R]** | uuid | sim |  | FK → `core.brand`. Marca à qual o sinal se refere. |
| `related_product_id` **[R]** | uuid | sim |  | FK → `core.product`. Produto ao qual o sinal se refere. |

<details><summary>Constraints</summary>

- **CHECK** `consumer_signal_author_hash_check`: `CHECK ((author_hash ~ '^[0-9a-f]{64}$'::text))`
- **CHECK** `consumer_signal_check`: `CHECK (((rating_value IS NULL) OR ((rating_scale_max IS NOT NULL) AND ((rating_value >= (0)::numeric) AND (rating_value <= rating_scale_max)))))`
- **CHECK** `consumer_signal_original_text_check`: `CHECK ((length(original_text) > 0))`
- **CHECK** `consumer_signal_platform_check`: `CHECK ((platform = ANY (ARRAY['youtube'::text, 'reddit'::text, 'tiktok'::text, 'instagram'::text, 'facebook'::text, 'marketplace'::text, 'ecommerce'::text, 'forum'::text, 'search'::text, 'other'::text])))`
- **CHECK** `consumer_signal_signal_kind_check`: `CHECK ((signal_kind = ANY (ARRAY['comment'::text, 'review'::text, 'post'::text, 'video'::text, 'question'::text, 'answer'::text])))`
- **CHECK** `consumer_signal_text_hash_check`: `CHECK ((text_hash ~ '^[0-9a-f]{64}$'::text))`
- **FK** `consumer_signal_raw_document_id_fkey`: `FOREIGN KEY (raw_document_id) REFERENCES raw.raw_document(id)`
- **FK** `consumer_signal_related_brand_id_fkey`: `FOREIGN KEY (related_brand_id) REFERENCES core.brand(id)`
- **FK** `consumer_signal_related_product_id_fkey`: `FOREIGN KEY (related_product_id) REFERENCES core.product(id)`
- **FK** `consumer_signal_source_id_fkey`: `FOREIGN KEY (source_id) REFERENCES ops.source(id)`
- **PK** `consumer_signal_pkey`: `PRIMARY KEY (id)`

</details>

<details><summary>Índices</summary>

- `consumer_signal_brand_idx`: `CREATE INDEX consumer_signal_brand_idx ON core.consumer_signal USING btree (related_brand_id)`
- `consumer_signal_external_uq`: `CREATE UNIQUE INDEX consumer_signal_external_uq ON core.consumer_signal USING btree (platform, external_public_id) WHERE (external_public_id IS NOT NULL)`
- `consumer_signal_product_idx`: `CREATE INDEX consumer_signal_product_idx ON core.consumer_signal USING btree (related_product_id)`
- `consumer_signal_published_idx`: `CREATE INDEX consumer_signal_published_idx ON core.consumer_signal USING btree (published_at DESC)`
- `consumer_signal_text_uq`: `CREATE UNIQUE INDEX consumer_signal_text_uq ON core.consumer_signal USING btree (platform, url, text_hash)`

</details>

<details><summary>Triggers</summary>

- `consumer_signal_immutable`: `CREATE TRIGGER consumer_signal_immutable BEFORE UPDATE ON core.consumer_signal FOR EACH ROW EXECUTE FUNCTION ops.forbid_update('related_brand_id', 'related_brand_id_is_inferred', 'related_brand_id_confidence', 'related_brand_id_evidence_id', 'related_brand_id_missing_reason', 'related_product_id', 'related_product_id_is_inferred', 'related_product_id_confidence', 'related_product_id_evidence_id', 'related_product_id_missing_reason')`

</details>

### `core.evidence`

Evidência textual abrível no BI (excerpt + URL + data). Imutável. Referenciada por todo campo rastreável (§4.1, G-02).

| Coluna | Tipo | Nulo | Default | Descrição |
|---|---|---|---|---|
| `id` | uuid | não | `gen_random_uuid()` | Chave primária (UUID). |
| `evidence_type` | text | não | `'document'::text` | document (página coletada) \| api_response \| manual (inserção humana, exige created_by). |
| `raw_document_id` | uuid | sim |  | FK → `raw.raw_document`. |
| `url` | text | não |  |  |
| `excerpt` | text | não |  | Trecho literal da fonte que sustenta o valor. |
| `selector_or_offset` | text | sim |  | Seletor CSS/XPath, caminho JSON ou offset de caracteres no documento bruto. |
| `captured_at` | timestamp with time zone | não |  | Data/hora da coleta da fonte (não da gravação). |
| `created_by` | text | sim |  |  |
| `created_at` | timestamp with time zone | não | `now()` | Data/hora de criação do registro. |

<details><summary>Constraints</summary>

- **CHECK** `evidence_check`: `CHECK (((evidence_type = 'manual'::text) OR (raw_document_id IS NOT NULL)))`
- **CHECK** `evidence_check1`: `CHECK (((evidence_type <> 'manual'::text) OR (created_by IS NOT NULL)))`
- **CHECK** `evidence_evidence_type_check`: `CHECK ((evidence_type = ANY (ARRAY['document'::text, 'api_response'::text, 'manual'::text])))`
- **CHECK** `evidence_excerpt_check`: `CHECK ((length(excerpt) > 0))`
- **FK** `evidence_raw_document_id_fkey`: `FOREIGN KEY (raw_document_id) REFERENCES raw.raw_document(id)`
- **PK** `evidence_pkey`: `PRIMARY KEY (id)`

</details>

<details><summary>Índices</summary>

- `evidence_raw_document_idx`: `CREATE INDEX evidence_raw_document_idx ON core.evidence USING btree (raw_document_id)`

</details>

<details><summary>Triggers</summary>

- `evidence_immutable`: `CREATE TRIGGER evidence_immutable BEFORE UPDATE ON core.evidence FOR EACH ROW EXECUTE FUNCTION ops.forbid_update()`

</details>

### `core.format`

Taxonomia de formato = forma física do produto (textura/veículo). Embalagem e mecanismo de dispensação ficam em core.packaging.

| Coluna | Tipo | Nulo | Default | Descrição |
|---|---|---|---|---|
| `id` | uuid | não | `gen_random_uuid()` | Chave primária (UUID). |
| `code` | text | não |  | Código estável (slug) usado em seeds, filtros e integrações. |
| `name_pt` | text | não |  | Nome de exibição em pt-BR. |
| `format_group` | text | não |  | liquido \| emulsao \| gel \| anidro \| solido \| po \| pressurizado \| suporte (tecido, patch) \| dispositivo. |
| `description` | text | sim |  |  |
| `sort_order` | integer | não | `0` | Ordem de exibição. |
| `active` | boolean | não | `true` | Item ativo para uso. |
| `created_at` | timestamp with time zone | não | `now()` | Data/hora de criação do registro. |
| `updated_at` | timestamp with time zone | não | `now()` | Data/hora da última alteração (trigger ops.set_updated_at). |

<details><summary>Constraints</summary>

- **CHECK** `format_code_check`: `CHECK ((code ~ '^[a-z0-9_]+$'::text))`
- **CHECK** `format_format_group_check`: `CHECK ((format_group = ANY (ARRAY['liquido'::text, 'emulsao'::text, 'gel'::text, 'anidro'::text, 'solido'::text, 'po'::text, 'pressurizado'::text, 'suporte'::text, 'dispositivo'::text])))`
- **PK** `format_pkey`: `PRIMARY KEY (id)`
- **UNIQUE** `format_code_key`: `UNIQUE (code)`

</details>

<details><summary>Triggers</summary>

- `format_set_updated_at`: `CREATE TRIGGER format_set_updated_at BEFORE UPDATE ON core.format FOR EACH ROW EXECUTE FUNCTION ops.set_updated_at()`

</details>

### `core.ingredient`

Ingrediente pela nomenclatura INCI normalizada.

| Coluna | Tipo | Nulo | Default | Descrição |
|---|---|---|---|---|
| `id` | uuid | não | `gen_random_uuid()` | Chave primária (UUID). |
| `inci_name` | text | não |  | Nome INCI normalizado (maiúsculas, sem espaços nas pontas). |
| `common_name` | text | sim |  |  |
| `function_class` | text | sim |  | Classe funcional (umectante, filtro UV, emoliente...). Vocabulário a definir. |
| `notes` | text | sim |  |  |
| `created_at` | timestamp with time zone | não | `now()` | Data/hora de criação do registro. |
| `updated_at` | timestamp with time zone | não | `now()` | Data/hora da última alteração (trigger ops.set_updated_at). |

<details><summary>Constraints</summary>

- **CHECK** `ingredient_inci_name_check`: `CHECK ((inci_name = upper(TRIM(BOTH FROM inci_name))))`
- **PK** `ingredient_pkey`: `PRIMARY KEY (id)`
- **UNIQUE** `ingredient_inci_name_key`: `UNIQUE (inci_name)`

</details>

<details><summary>Triggers</summary>

- `ingredient_set_updated_at`: `CREATE TRIGGER ingredient_set_updated_at BEFORE UPDATE ON core.ingredient FOR EACH ROW EXECUTE FUNCTION ops.set_updated_at()`

</details>

### `core.market_share_estimate`

Share de marca/produto por recorte. Estimativa nunca rotulada como share confirmado (G-11). Sinais digitais não são vendas (G-07).

| Coluna | Tipo | Nulo | Default | Descrição |
|---|---|---|---|---|
| `id` | uuid | não | `gen_random_uuid()` | Chave primária (UUID). |
| `brand_id` | uuid | não |  | FK → `core.brand`. |
| `product_id` | uuid | sim |  | FK → `core.product`. |
| `market_size_id` | uuid | sim |  | FK → `core.market_size`. Registro de core.market_size usado como denominador, quando aplicável. |
| `category_id` | uuid | sim |  | FK → `core.category`. |
| `subcategory_id` | uuid | sim |  |  |
| `channel` | text | sim |  |  |
| `uf` | character(2) | sim |  |  |
| `municipality_or_region` | text | sim |  |  |
| `period_start` | date | não |  |  |
| `period_end` | date | não |  |  |
| `universe_definition` | text | não |  |  |
| `revenue_value` | numeric(18,2) | sim |  |  |
| `units_value` | numeric(18,0) | sim |  |  |
| `share_value_pct` | numeric(6,3) | sim |  | Receita da marca no recorte ÷ receita total do mesmo recorte × 100 (§7.1). |
| `share_volume_pct` | numeric(6,3) | sim |  | Unidades da marca no recorte ÷ unidades totais do mesmo recorte × 100 (§7.1). |
| `status` | text | não |  |  |
| `sell_type` | text | sim |  |  |
| `method` | text | sim |  |  |
| `inputs` | text[] | não | `'{}'::text[]` | Insumos da estimativa (§7.3): company_disclosure \| association_report \| licensed_report \| retailer_data \| platform_sales_rank \| published_revenue_range \| retail_distribution \| public_trade_data \| panel_sample \| public_demand_indicator. Seguidores, avaliações, buscas e tráfego são bloqueados (G-07). |
| `assumptions` | text | sim |  |  |
| `bias_notes` | text | sim |  |  |
| `coverage_notes` | text | sim |  |  |
| `range_min` | numeric(6,3) | sim |  | Limite inferior do intervalo de share (%), obrigatório se estimated. |
| `range_max` | numeric(6,3) | sim |  | Limite superior do intervalo de share (%), obrigatório se estimated. |
| `confidence` | numeric(3,2) | sim |  |  |
| `comparability_restrictions` | text | sim |  |  |
| `source` | text | sim |  |  |
| `source_id` | uuid | sim |  | FK → `ops.source`. |
| `base_year` | smallint | sim |  |  |
| `evidence_ids` | uuid[] | não | `'{}'::uuid[]` |  |
| `data_acquisition_plan` | text | sim |  | Plano de aquisição quando status = unavailable (§7.5). |
| `created_at` | timestamp with time zone | não | `now()` | Data/hora de criação do registro. |

<details><summary>Constraints</summary>

- **CHECK** `market_share_available_ck`: `CHECK (((status = 'unavailable'::text) OR (((share_value_pct IS NOT NULL) OR (share_volume_pct IS NOT NULL)) AND (source IS NOT NULL) AND (sell_type IS NOT NULL))))`
- **CHECK** `market_share_estimate_base_year_check`: `CHECK (((base_year >= 1990) AND (base_year <= 2100)))`
- **CHECK** `market_share_estimate_check`: `CHECK ((period_end >= period_start))`
- **CHECK** `market_share_estimate_check1`: `CHECK (((range_min IS NULL) OR (range_max IS NULL) OR (range_min <= range_max)))`
- **CHECK** `market_share_estimate_confidence_check`: `CHECK (((confidence >= (0)::numeric) AND (confidence <= (1)::numeric)))`
- **CHECK** `market_share_estimate_range_max_check`: `CHECK (((range_max >= (0)::numeric) AND (range_max <= (100)::numeric)))`
- **CHECK** `market_share_estimate_range_min_check`: `CHECK (((range_min >= (0)::numeric) AND (range_min <= (100)::numeric)))`
- **CHECK** `market_share_estimate_revenue_value_check`: `CHECK ((revenue_value >= (0)::numeric))`
- **CHECK** `market_share_estimate_sell_type_check`: `CHECK ((sell_type = ANY (ARRAY['sell_in'::text, 'sell_out'::text])))`
- **CHECK** `market_share_estimate_share_value_pct_check`: `CHECK (((share_value_pct >= (0)::numeric) AND (share_value_pct <= (100)::numeric)))`
- **CHECK** `market_share_estimate_share_volume_pct_check`: `CHECK (((share_volume_pct >= (0)::numeric) AND (share_volume_pct <= (100)::numeric)))`
- **CHECK** `market_share_estimate_status_check`: `CHECK ((status = ANY (ARRAY['observed'::text, 'estimated'::text, 'unavailable'::text])))`
- **CHECK** `market_share_estimate_uf_check`: `CHECK ((uf = ANY (ARRAY['AC'::bpchar, 'AL'::bpchar, 'AP'::bpchar, 'AM'::bpchar, 'BA'::bpchar, 'CE'::bpchar, 'DF'::bpchar, 'ES'::bpchar, 'GO'::bpchar, 'MA'::bpchar, 'MT'::bpchar, 'MS'::bpchar, 'MG'::bpchar, 'PA'::bpchar, 'PB'::bpchar, 'PR'::bpchar, 'PE'::bpchar, 'PI'::bpchar, 'RJ'::bpchar, 'RN'::bpchar, 'RS'::bpchar, 'RO'::bpchar, 'RR'::bpchar, 'SC'::bpchar, 'SP'::bpchar, 'SE'::bpchar, 'TO'::bpchar])))`
- **CHECK** `market_share_estimate_units_value_check`: `CHECK ((units_value >= (0)::numeric))`
- **CHECK** `market_share_estimated_ck`: `CHECK (((status <> 'estimated'::text) OR ((method IS NOT NULL) AND (cardinality(inputs) > 0) AND (assumptions IS NOT NULL) AND (bias_notes IS NOT NULL) AND (coverage_notes IS NOT NULL) AND (range_min IS NOT NULL) AND (range_max IS NOT NULL) AND (confidence IS NOT NULL))))`
- **CHECK** `market_share_inputs_ck`: `CHECK ((inputs <@ ARRAY['company_disclosure'::text, 'association_report'::text, 'licensed_report'::text, 'retailer_data'::text, 'platform_sales_rank'::text, 'published_revenue_range'::text, 'retail_distribution'::text, 'public_trade_data'::text, 'panel_sample'::text, 'public_demand_indicator'::text]))`
- **CHECK** `market_share_unavailable_ck`: `CHECK (((status <> 'unavailable'::text) OR ((share_value_pct IS NULL) AND (share_volume_pct IS NULL) AND (revenue_value IS NULL) AND (units_value IS NULL) AND (data_acquisition_plan IS NOT NULL))))`
- **FK** `market_share_estimate_brand_id_fkey`: `FOREIGN KEY (brand_id) REFERENCES core.brand(id)`
- **FK** `market_share_estimate_category_id_fkey`: `FOREIGN KEY (category_id) REFERENCES core.category(id)`
- **FK** `market_share_estimate_market_size_id_fkey`: `FOREIGN KEY (market_size_id) REFERENCES core.market_size(id)`
- **FK** `market_share_estimate_product_id_fkey`: `FOREIGN KEY (product_id) REFERENCES core.product(id)`
- **FK** `market_share_estimate_source_id_fkey`: `FOREIGN KEY (source_id) REFERENCES ops.source(id)`
- **FK** `market_share_subcategory_category_fk`: `FOREIGN KEY (subcategory_id, category_id) REFERENCES core.subcategory(id, category_id)`
- **PK** `market_share_estimate_pkey`: `PRIMARY KEY (id)`

</details>

<details><summary>Índices</summary>

- `market_share_brand_idx`: `CREATE INDEX market_share_brand_idx ON core.market_share_estimate USING btree (brand_id, period_start)`
- `market_share_cut_idx`: `CREATE INDEX market_share_cut_idx ON core.market_share_estimate USING btree (category_id, subcategory_id, uf, channel, period_start)`

</details>

### `core.market_size`

Tamanho de mercado por recorte (categoria, território, canal, período, universo). Denominador do share (§7.1).

| Coluna | Tipo | Nulo | Default | Descrição |
|---|---|---|---|---|
| `id` | uuid | não | `gen_random_uuid()` | Chave primária (UUID). |
| `category_id` | uuid | sim |  | FK → `core.category`. |
| `subcategory_id` | uuid | sim |  |  |
| `channel` | text | sim |  | Canal do recorte. Vocabulário de canais ainda não definido na SPEC. |
| `uf` | character(2) | sim |  | UF (sigla). NULL = Brasil. |
| `municipality_or_region` | text | sim |  |  |
| `period_start` | date | não |  |  |
| `period_end` | date | não |  |  |
| `revenue` | numeric(18,2) | sim |  |  |
| `units` | numeric(18,0) | sim |  |  |
| `currency` | character(3) | não | `'BRL'::bpchar` |  |
| `universe_definition` | text | não |  | Definição explícita do universo medido (obrigatória, §7.1). |
| `scope` | text | sim |  |  |
| `sell_type` | text | sim |  |  |
| `status` | text | não |  | observed \| estimated \| unavailable — estados distintos (G-11). |
| `method` | text | sim |  |  |
| `assumptions` | text | sim |  |  |
| `range_min` | numeric(18,2) | sim |  |  |
| `range_max` | numeric(18,2) | sim |  |  |
| `confidence` | numeric(3,2) | sim |  |  |
| `source` | text | sim |  |  |
| `source_id` | uuid | sim |  | FK → `ops.source`. |
| `base_year` | smallint | sim |  |  |
| `evidence_ids` | uuid[] | não | `'{}'::uuid[]` | Evidências (core.evidence) que sustentam o registro. |
| `data_acquisition_plan` | text | sim |  | Plano de aquisição de dados quando status = unavailable (§7.5 "DADOS INSUFICIENTES"). |
| `created_at` | timestamp with time zone | não | `now()` | Data/hora de criação do registro. |

<details><summary>Constraints</summary>

- **CHECK** `market_size_available_ck`: `CHECK (((status = 'unavailable'::text) OR (((revenue IS NOT NULL) OR (units IS NOT NULL)) AND (source IS NOT NULL) AND (sell_type IS NOT NULL))))`
- **CHECK** `market_size_base_year_check`: `CHECK (((base_year >= 1990) AND (base_year <= 2100)))`
- **CHECK** `market_size_check`: `CHECK ((period_end >= period_start))`
- **CHECK** `market_size_check1`: `CHECK (((range_min IS NULL) OR (range_max IS NULL) OR (range_min <= range_max)))`
- **CHECK** `market_size_confidence_check`: `CHECK (((confidence >= (0)::numeric) AND (confidence <= (1)::numeric)))`
- **CHECK** `market_size_estimated_ck`: `CHECK (((status <> 'estimated'::text) OR ((method IS NOT NULL) AND (assumptions IS NOT NULL) AND (range_min IS NOT NULL) AND (range_max IS NOT NULL) AND (confidence IS NOT NULL))))`
- **CHECK** `market_size_revenue_check`: `CHECK ((revenue >= (0)::numeric))`
- **CHECK** `market_size_sell_type_check`: `CHECK ((sell_type = ANY (ARRAY['sell_in'::text, 'sell_out'::text])))`
- **CHECK** `market_size_status_check`: `CHECK ((status = ANY (ARRAY['observed'::text, 'estimated'::text, 'unavailable'::text])))`
- **CHECK** `market_size_uf_check`: `CHECK ((uf = ANY (ARRAY['AC'::bpchar, 'AL'::bpchar, 'AP'::bpchar, 'AM'::bpchar, 'BA'::bpchar, 'CE'::bpchar, 'DF'::bpchar, 'ES'::bpchar, 'GO'::bpchar, 'MA'::bpchar, 'MT'::bpchar, 'MS'::bpchar, 'MG'::bpchar, 'PA'::bpchar, 'PB'::bpchar, 'PR'::bpchar, 'PE'::bpchar, 'PI'::bpchar, 'RJ'::bpchar, 'RN'::bpchar, 'RS'::bpchar, 'RO'::bpchar, 'RR'::bpchar, 'SC'::bpchar, 'SP'::bpchar, 'SE'::bpchar, 'TO'::bpchar])))`
- **CHECK** `market_size_unavailable_ck`: `CHECK (((status <> 'unavailable'::text) OR ((revenue IS NULL) AND (units IS NULL) AND (data_acquisition_plan IS NOT NULL))))`
- **CHECK** `market_size_units_check`: `CHECK ((units >= (0)::numeric))`
- **FK** `market_size_category_id_fkey`: `FOREIGN KEY (category_id) REFERENCES core.category(id)`
- **FK** `market_size_source_id_fkey`: `FOREIGN KEY (source_id) REFERENCES ops.source(id)`
- **FK** `market_size_subcategory_category_fk`: `FOREIGN KEY (subcategory_id, category_id) REFERENCES core.subcategory(id, category_id)`
- **PK** `market_size_pkey`: `PRIMARY KEY (id)`

</details>

### `core.packaging`

Embalagem do produto (ou de uma variante específica). Vocabulários de tipo/material/mecanismo ainda não definidos na SPEC.

| Coluna | Tipo | Nulo | Default | Descrição |
|---|---|---|---|---|
| `id` | uuid | não | `gen_random_uuid()` | Chave primária (UUID). |
| `product_id` | uuid | não |  | FK → `core.product`. |
| `variant_id` | uuid | sim |  | FK → `core.product_variant`. Preenchido quando a embalagem difere entre variantes. |
| `created_at` | timestamp with time zone | não | `now()` | Data/hora de criação do registro. |
| `updated_at` | timestamp with time zone | não | `now()` | Data/hora da última alteração (trigger ops.set_updated_at). |
| `type` **[R]** | text | sim |  | Tipo de embalagem primária (bisnaga, frasco, stick, pote, sachê...). |
| `material` **[R]** | text | sim |  | Material declarado. |
| `dispensing_mechanism` **[R]** | text | sim |  | Mecanismo de dispensação (pump, airless, giro, conta-gotas, spray, roll-on...). |
| `portability` **[R]** | text | sim |  | Portabilidade (tamanho de bolsa/viagem, à prova de vazamento...). |
| `refill_available` **[R]** | boolean | sim |  | Existe refil comercializado. |
| `visual_notes` **[R]** | text | sim |  | Percepção visual. Tipicamente inferida (is_inferred = true). |

<details><summary>Constraints</summary>

- **FK** `packaging_product_id_fkey`: `FOREIGN KEY (product_id) REFERENCES core.product(id)`
- **FK** `packaging_variant_id_fkey`: `FOREIGN KEY (variant_id) REFERENCES core.product_variant(id)`
- **PK** `packaging_pkey`: `PRIMARY KEY (id)`

</details>

<details><summary>Índices</summary>

- `packaging_product_idx`: `CREATE INDEX packaging_product_idx ON core.packaging USING btree (product_id)`
- `packaging_product_variant_uq`: `CREATE UNIQUE INDEX packaging_product_variant_uq ON core.packaging USING btree (product_id, COALESCE(variant_id, '00000000-0000-0000-0000-000000000000'::uuid))`

</details>

<details><summary>Triggers</summary>

- `packaging_capture_version`: `CREATE TRIGGER packaging_capture_version AFTER INSERT OR UPDATE ON core.packaging FOR EACH ROW EXECUTE FUNCTION ops.capture_version('core.packaging_version', 'packaging_id')`
- `packaging_no_delete`: `CREATE TRIGGER packaging_no_delete BEFORE DELETE ON core.packaging FOR EACH ROW EXECUTE FUNCTION ops.forbid_delete()`
- `packaging_set_updated_at`: `CREATE TRIGGER packaging_set_updated_at BEFORE UPDATE ON core.packaging FOR EACH ROW EXECUTE FUNCTION ops.set_updated_at()`

</details>

### `core.packaging_version`

Histórico SCD2 de core.packaging (ops.capture_version).

| Coluna | Tipo | Nulo | Default | Descrição |
|---|---|---|---|---|
| `id` | uuid | não | `gen_random_uuid()` | Chave primária (UUID). |
| `packaging_id` | uuid | não |  | FK → `core.packaging`. |
| `version_no` | integer | não |  | Número sequencial da versão. |
| `valid_from` | timestamp with time zone | não |  | Início de vigência (SCD2). |
| `valid_to` | timestamp with time zone | sim |  | Fim de vigência (SCD2). NULL = vigente. |
| `snapshot` | jsonb | não |  |  |
| `changed_fields` | text[] | sim |  |  |
| `change_origin` | text | sim |  |  |

<details><summary>Constraints</summary>

- **CHECK** `packaging_version_check`: `CHECK (((valid_to IS NULL) OR (valid_to >= valid_from)))`
- **CHECK** `packaging_version_version_no_check`: `CHECK ((version_no > 0))`
- **FK** `packaging_version_packaging_id_fkey`: `FOREIGN KEY (packaging_id) REFERENCES core.packaging(id)`
- **PK** `packaging_version_pkey`: `PRIMARY KEY (id)`
- **UNIQUE** `packaging_version_packaging_id_version_no_key`: `UNIQUE (packaging_id, version_no)`

</details>

<details><summary>Índices</summary>

- `packaging_version_current_uq`: `CREATE UNIQUE INDEX packaging_version_current_uq ON core.packaging_version USING btree (packaging_id) WHERE (valid_to IS NULL)`

</details>

### `core.price_observation`

Observação de preço por variante, fonte e data. Append-only por natureza: cada coleta gera nova linha (G-04).

| Coluna | Tipo | Nulo | Default | Descrição |
|---|---|---|---|---|
| `id` | uuid | não | `gen_random_uuid()` | Chave primária (UUID). |
| `variant_id` | uuid | não |  | FK → `core.product_variant`. |
| `source_id` | uuid | não |  | FK → `ops.source`. |
| `crawl_run_id` | uuid | sim |  | FK → `ops.crawl_run`. |
| `observed_at` | timestamp with time zone | não |  |  |
| `list_price` | numeric(12,2) | sim |  | Preço cheio (de/por: "de"). Nunca confundido com promocional (G-05). |
| `promo_price` | numeric(12,2) | sim |  | Preço promocional vigente na coleta. |
| `price_missing_reason` | text | sim |  | Motivo quando nenhum preço foi capturado (G-03). |
| `currency` | character(3) | não | `'BRL'::bpchar` |  |
| `unit_price_per_ml_g` | numeric(12,4) | sim |  | list_price ÷ volume. Calculado por trigger apenas se volume em ml/g com confiança >= 0.90 e não for kit (G-05); caso contrário NULL. |
| `unit_promo_price_per_ml_g` | numeric(12,4) | sim |  | promo_price ÷ volume, mesmas regras de unit_price_per_ml_g. |
| `unit_basis_volume` | numeric(10,3) | sim |  | Volume da variante usado no cálculo, congelado na observação. |
| `unit_basis_unit` | text | sim |  |  |
| `is_kit` | boolean | não | `false` | Observação refere-se a kit/combo; preço unitário não é calculado. |
| `availability` | text | não | `'unknown'::text` |  |
| `seller_name` | text | sim |  | Vendedor em marketplace (pessoa jurídica). Não armazenar pessoa física (C-04). |
| `extraction_method` | text | não |  | api \| json_ld \| parser \| llm \| manual. |
| `extraction_confidence` | numeric(3,2) | não |  |  |
| `prompt_version` | text | sim |  |  |
| `evidence_id` | uuid | não |  | FK → `core.evidence`. |
| `created_at` | timestamp with time zone | não | `now()` | Data/hora de criação do registro. |

<details><summary>Constraints</summary>

- **CHECK** `price_observation_availability_check`: `CHECK ((availability = ANY (ARRAY['in_stock'::text, 'out_of_stock'::text, 'unknown'::text])))`
- **CHECK** `price_observation_check`: `CHECK (((list_price IS NOT NULL) OR (promo_price IS NOT NULL) OR (price_missing_reason IS NOT NULL)))`
- **CHECK** `price_observation_check1`: `CHECK (((extraction_method <> 'llm'::text) OR (prompt_version IS NOT NULL)))`
- **CHECK** `price_observation_extraction_confidence_check`: `CHECK (((extraction_confidence >= (0)::numeric) AND (extraction_confidence <= (1)::numeric)))`
- **CHECK** `price_observation_extraction_method_check`: `CHECK ((extraction_method = ANY (ARRAY['api'::text, 'json_ld'::text, 'parser'::text, 'llm'::text, 'manual'::text])))`
- **CHECK** `price_observation_list_price_check`: `CHECK ((list_price >= (0)::numeric))`
- **CHECK** `price_observation_price_missing_reason_check`: `CHECK ((price_missing_reason = ANY (ARRAY['not_published'::text, 'out_of_stock_no_price'::text, 'source_blocked'::text, 'parse_error'::text])))`
- **CHECK** `price_observation_promo_price_check`: `CHECK ((promo_price >= (0)::numeric))`
- **CHECK** `price_observation_unit_basis_unit_check`: `CHECK ((unit_basis_unit = ANY (ARRAY['ml'::text, 'g'::text])))`
- **FK** `price_observation_crawl_run_id_fkey`: `FOREIGN KEY (crawl_run_id) REFERENCES ops.crawl_run(id)`
- **FK** `price_observation_evidence_id_fkey`: `FOREIGN KEY (evidence_id) REFERENCES core.evidence(id)`
- **FK** `price_observation_source_id_fkey`: `FOREIGN KEY (source_id) REFERENCES ops.source(id)`
- **FK** `price_observation_variant_id_fkey`: `FOREIGN KEY (variant_id) REFERENCES core.product_variant(id)`
- **PK** `price_observation_pkey`: `PRIMARY KEY (id)`

</details>

<details><summary>Índices</summary>

- `price_observation_source_idx`: `CREATE INDEX price_observation_source_idx ON core.price_observation USING btree (source_id, observed_at DESC)`
- `price_observation_variant_idx`: `CREATE INDEX price_observation_variant_idx ON core.price_observation USING btree (variant_id, observed_at DESC)`

</details>

<details><summary>Triggers</summary>

- `price_observation_unit_price`: `CREATE TRIGGER price_observation_unit_price BEFORE INSERT OR UPDATE OF list_price, promo_price, variant_id, is_kit ON core.price_observation FOR EACH ROW EXECUTE FUNCTION core.compute_unit_price()`

</details>

### `core.product`

Produto deduplicado (§4.4). Variantes de volume/tom em core.product_variant. Histórico em core.product_version.

| Coluna | Tipo | Nulo | Default | Descrição |
|---|---|---|---|---|
| `id` | uuid | não | `gen_random_uuid()` | Chave primária (UUID). |
| `brand_id` | uuid | não |  | FK → `core.brand`. |
| `canonical_name` | text | não |  | Nome canônico normalizado do produto, conforme publicado pela marca. |
| `url` | text | sim |  | URL da página oficial do produto. |
| `primary_source_id` | uuid | sim |  | FK → `ops.source`. |
| `dedup_key` | text | não |  | Normalização de (marca + nome canônico + formato + volume). Similaridade de embedding complementa na Fase 1 (DEC-07). |
| `first_seen_at` | timestamp with time zone | não | `now()` | Primeira coleta em que o produto foi observado. Base do alerta "novo lançamento" (§12). |
| `last_seen_at` | timestamp with time zone | não | `now()` |  |
| `consecutive_misses` | smallint | não | `0` | Coletas consecutivas sem encontrar o produto. Acima de N → candidato a status discontinued inferido (§4.4). |
| `created_at` | timestamp with time zone | não | `now()` | Data/hora de criação do registro. |
| `updated_at` | timestamp with time zone | não | `now()` | Data/hora da última alteração (trigger ops.set_updated_at). |
| `category_id` **[R]** | uuid | sim |  | FK → `core.category`. Categoria (taxonomia core.category). |
| `subcategory_id` **[R]** | uuid | sim |  | Subcategoria (taxonomia core.subcategory), coerente com category_id. |
| `format_id` **[R]** | uuid | sim |  | FK → `core.format`. Formato físico (taxonomia core.format). |
| `status` **[R]** | text | sim |  | Ciclo de vida: launch \| permanent \| limited \| discontinued. discontinued por ausência é inferido (§4.4). |
| `launch_date` **[R]** | date | sim |  | Data de lançamento. |
| `skin_type` **[R]** | text[] | sim |  | Tipos de pele indicados: normal \| seca \| oleosa \| mista \| sensivel \| acneica \| madura \| todos_os_tipos. |
| `body_area` **[R]** | text[] | sim |  | Regiões do corpo: rosto \| area_dos_olhos \| labios \| pescoco_colo \| corpo \| maos \| pes \| couro_cabeludo \| cabelo. |
| `use_occasion` **[R]** | text | sim |  | Ocasião de uso (ex.: reaplicação ao longo do dia, pós-treino, noturno). |
| `suggested_frequency` **[R]** | text | sim |  | Frequência de uso sugerida pela marca. |
| `spf_declared` **[R]** | smallint | sim |  | FPS declarado. Nunca inferido (G-03). |
| `target_audience_declared` **[R]** | text | sim |  | Público declarado do produto. Nunca inferido; inferência de público fica em análise rotulada (G-08). |

<details><summary>Constraints</summary>

- **CHECK** `product_body_area_check`: `CHECK ((body_area <@ ARRAY['rosto'::text, 'area_dos_olhos'::text, 'labios'::text, 'pescoco_colo'::text, 'corpo'::text, 'maos'::text, 'pes'::text, 'couro_cabeludo'::text, 'cabelo'::text]))`
- **CHECK** `product_check`: `CHECK ((last_seen_at >= first_seen_at))`
- **CHECK** `product_consecutive_misses_check`: `CHECK ((consecutive_misses >= 0))`
- **CHECK** `product_skin_type_check`: `CHECK ((skin_type <@ ARRAY['normal'::text, 'seca'::text, 'oleosa'::text, 'mista'::text, 'sensivel'::text, 'acneica'::text, 'madura'::text, 'todos_os_tipos'::text]))`
- **CHECK** `product_spf_declared_check`: `CHECK (((spf_declared >= 1) AND (spf_declared <= 100)))`
- **CHECK** `product_spf_declared_ck`: `CHECK ((spf_declared_is_inferred IS DISTINCT FROM true))`
- **CHECK** `product_status_check`: `CHECK ((status = ANY (ARRAY['launch'::text, 'permanent'::text, 'limited'::text, 'discontinued'::text])))`
- **CHECK** `product_target_audience_declared_ck`: `CHECK ((target_audience_declared_is_inferred IS DISTINCT FROM true))`
- **FK** `product_brand_id_fkey`: `FOREIGN KEY (brand_id) REFERENCES core.brand(id)`
- **FK** `product_category_id_fkey`: `FOREIGN KEY (category_id) REFERENCES core.category(id)`
- **FK** `product_format_id_fkey`: `FOREIGN KEY (format_id) REFERENCES core.format(id)`
- **FK** `product_primary_source_id_fkey`: `FOREIGN KEY (primary_source_id) REFERENCES ops.source(id)`
- **FK** `product_subcategory_category_fk`: `FOREIGN KEY (subcategory_id, category_id) REFERENCES core.subcategory(id, category_id)`
- **PK** `product_pkey`: `PRIMARY KEY (id)`
- **UNIQUE** `product_dedup_key_key`: `UNIQUE (dedup_key)`

</details>

<details><summary>Índices</summary>

- `product_brand_idx`: `CREATE INDEX product_brand_idx ON core.product USING btree (brand_id)`
- `product_category_idx`: `CREATE INDEX product_category_idx ON core.product USING btree (category_id, subcategory_id)`
- `product_first_seen_idx`: `CREATE INDEX product_first_seen_idx ON core.product USING btree (first_seen_at DESC)`
- `product_format_idx`: `CREATE INDEX product_format_idx ON core.product USING btree (format_id)`

</details>

<details><summary>Triggers</summary>

- `product_capture_version`: `CREATE TRIGGER product_capture_version AFTER INSERT OR UPDATE ON core.product FOR EACH ROW EXECUTE FUNCTION ops.capture_version('core.product_version', 'product_id')`
- `product_no_delete`: `CREATE TRIGGER product_no_delete BEFORE DELETE ON core.product FOR EACH ROW EXECUTE FUNCTION ops.forbid_delete()`
- `product_set_updated_at`: `CREATE TRIGGER product_set_updated_at BEFORE UPDATE ON core.product FOR EACH ROW EXECUTE FUNCTION ops.set_updated_at()`

</details>

### `core.product_benefit`

Associação produto × benefício normalizado (principal/secundário), com rastreio por linha (§4.1). SCD2 inline.

| Coluna | Tipo | Nulo | Default | Descrição |
|---|---|---|---|---|
| `id` | uuid | não | `gen_random_uuid()` | Chave primária (UUID). |
| `product_id` | uuid | não |  | FK → `core.product`. |
| `benefit_id` | uuid | não |  | FK → `core.benefit`. |
| `is_primary` | boolean | não | `false` | Benefício principal. No máximo um vigente por produto. |
| `is_inferred` | boolean | não |  |  |
| `confidence` | numeric(3,2) | não |  |  |
| `evidence_id` | uuid | não |  | FK → `core.evidence`. |
| `model` | text | sim |  |  |
| `prompt_version` | text | sim |  |  |
| `valid_from` | timestamp with time zone | não | `now()` | Início de vigência (SCD2). |
| `valid_to` | timestamp with time zone | sim |  | Fim de vigência (SCD2). NULL = vigente. |
| `created_at` | timestamp with time zone | não | `now()` | Data/hora de criação do registro. |

<details><summary>Constraints</summary>

- **CHECK** `product_benefit_check`: `CHECK (((NOT is_inferred) OR (prompt_version IS NOT NULL)))`
- **CHECK** `product_benefit_check1`: `CHECK (((valid_to IS NULL) OR (valid_to >= valid_from)))`
- **CHECK** `product_benefit_confidence_check`: `CHECK (((confidence >= (0)::numeric) AND (confidence <= (1)::numeric)))`
- **FK** `product_benefit_benefit_id_fkey`: `FOREIGN KEY (benefit_id) REFERENCES core.benefit(id)`
- **FK** `product_benefit_evidence_id_fkey`: `FOREIGN KEY (evidence_id) REFERENCES core.evidence(id)`
- **FK** `product_benefit_product_id_fkey`: `FOREIGN KEY (product_id) REFERENCES core.product(id)`
- **PK** `product_benefit_pkey`: `PRIMARY KEY (id)`

</details>

<details><summary>Índices</summary>

- `product_benefit_benefit_idx`: `CREATE INDEX product_benefit_benefit_idx ON core.product_benefit USING btree (benefit_id) WHERE (valid_to IS NULL)`
- `product_benefit_current_uq`: `CREATE UNIQUE INDEX product_benefit_current_uq ON core.product_benefit USING btree (product_id, benefit_id) WHERE (valid_to IS NULL)`
- `product_benefit_primary_uq`: `CREATE UNIQUE INDEX product_benefit_primary_uq ON core.product_benefit USING btree (product_id) WHERE (is_primary AND (valid_to IS NULL))`

</details>

### `core.product_ingredient`

Composição INCI do produto. Presença de ingrediente nunca é inferida (G-03); evidence_id obrigatório (AC-03). SCD2 inline: alteração fecha valid_to e insere nova linha.

| Coluna | Tipo | Nulo | Default | Descrição |
|---|---|---|---|---|
| `id` | uuid | não | `gen_random_uuid()` | Chave primária (UUID). |
| `product_id` | uuid | não |  | FK → `core.product`. |
| `ingredient_id` | uuid | não |  | FK → `core.ingredient`. |
| `inci_text_as_published` | text | não |  | Grafia exatamente como publicada na fonte. |
| `position_in_inci` | smallint | sim |  | Posição na lista INCI publicada (1 = maior concentração). |
| `is_highlighted_active` | boolean | não | `false` | Ativo destacado pela marca na comunicação do produto. |
| `highlight_evidence_id` | uuid | sim |  | FK → `core.evidence`. |
| `concentration_unit` | text | sim |  |  |
| `is_inferred` | boolean | não | `false` | Sempre false: presença de ingrediente só por declaração (G-03). |
| `confidence` | numeric(3,2) | não |  |  |
| `evidence_id` | uuid | não |  | FK → `core.evidence`. |
| `valid_from` | timestamp with time zone | não | `now()` | Início de vigência (SCD2). |
| `valid_to` | timestamp with time zone | sim |  | Fim de vigência (fórmula alterada ou ingrediente removido). NULL = vigente. |
| `created_at` | timestamp with time zone | não | `now()` | Data/hora de criação do registro. |
| `declared_concentration` **[R]** | numeric(9,4) | sim |  | Concentração declarada pela marca. Nunca inferida (G-03). |

<details><summary>Constraints</summary>

- **CHECK** `product_ingredient_check`: `CHECK (((NOT is_highlighted_active) OR (highlight_evidence_id IS NOT NULL)))`
- **CHECK** `product_ingredient_check1`: `CHECK (((valid_to IS NULL) OR (valid_to >= valid_from)))`
- **CHECK** `product_ingredient_concentration_declared_ck`: `CHECK ((declared_concentration_is_inferred IS DISTINCT FROM true))`
- **CHECK** `product_ingredient_concentration_unit_check`: `CHECK ((concentration_unit = ANY (ARRAY['%'::text, 'mg/g'::text, 'mg/ml'::text, 'ppm'::text, 'UI/g'::text])))`
- **CHECK** `product_ingredient_concentration_unit_ck`: `CHECK (((declared_concentration IS NULL) OR (concentration_unit IS NOT NULL)))`
- **CHECK** `product_ingredient_confidence_check`: `CHECK (((confidence >= (0)::numeric) AND (confidence <= (1)::numeric)))`
- **CHECK** `product_ingredient_declared_concentration_check`: `CHECK ((declared_concentration > (0)::numeric))`
- **CHECK** `product_ingredient_not_inferred_ck`: `CHECK ((is_inferred = false))`
- **CHECK** `product_ingredient_position_in_inci_check`: `CHECK ((position_in_inci > 0))`
- **FK** `product_ingredient_evidence_id_fkey`: `FOREIGN KEY (evidence_id) REFERENCES core.evidence(id)`
- **FK** `product_ingredient_highlight_evidence_id_fkey`: `FOREIGN KEY (highlight_evidence_id) REFERENCES core.evidence(id)`
- **FK** `product_ingredient_ingredient_id_fkey`: `FOREIGN KEY (ingredient_id) REFERENCES core.ingredient(id)`
- **FK** `product_ingredient_product_id_fkey`: `FOREIGN KEY (product_id) REFERENCES core.product(id)`
- **PK** `product_ingredient_pkey`: `PRIMARY KEY (id)`

</details>

<details><summary>Índices</summary>

- `product_ingredient_current_uq`: `CREATE UNIQUE INDEX product_ingredient_current_uq ON core.product_ingredient USING btree (product_id, ingredient_id) WHERE (valid_to IS NULL)`
- `product_ingredient_ingredient_idx`: `CREATE INDEX product_ingredient_ingredient_idx ON core.product_ingredient USING btree (ingredient_id) WHERE (valid_to IS NULL)`

</details>

### `core.product_variant`

Variante (SKU) de um produto: volume/peso, tom, GTIN. Histórico em core.product_variant_version.

| Coluna | Tipo | Nulo | Default | Descrição |
|---|---|---|---|---|
| `id` | uuid | não | `gen_random_uuid()` | Chave primária (UUID). |
| `product_id` | uuid | não |  | FK → `core.product`. |
| `variant_name` | text | sim |  |  |
| `shade` | text | sim |  | Cor/tom declarado. |
| `volume_unit` | text | sim |  | ml \| g \| un. Obrigatório quando volume_value está preenchido. |
| `first_seen_at` | timestamp with time zone | não | `now()` |  |
| `last_seen_at` | timestamp with time zone | não | `now()` |  |
| `consecutive_misses` | smallint | não | `0` |  |
| `created_at` | timestamp with time zone | não | `now()` | Data/hora de criação do registro. |
| `updated_at` | timestamp with time zone | não | `now()` | Data/hora da última alteração (trigger ops.set_updated_at). |
| `volume_value` **[R]** | numeric(10,3) | sim |  | Volume/peso líquido. Preço unitário só é calculado com volume_value_confidence >= 0.90 (G-05). |
| `gtin` **[R]** | text | sim |  | GTIN/EAN quando publicado. Chave forte de deduplicação (§4.4). |

<details><summary>Constraints</summary>

- **CHECK** `product_variant_check`: `CHECK ((last_seen_at >= first_seen_at))`
- **CHECK** `product_variant_consecutive_misses_check`: `CHECK ((consecutive_misses >= 0))`
- **CHECK** `product_variant_gtin_check`: `CHECK ((gtin ~ '^[0-9]{8,14}$'::text))`
- **CHECK** `product_variant_gtin_declared_ck`: `CHECK ((gtin_is_inferred IS DISTINCT FROM true))`
- **CHECK** `product_variant_volume_unit_check`: `CHECK ((volume_unit = ANY (ARRAY['ml'::text, 'g'::text, 'un'::text])))`
- **CHECK** `product_variant_volume_unit_ck`: `CHECK (((volume_value IS NULL) OR (volume_unit IS NOT NULL)))`
- **CHECK** `product_variant_volume_value_check`: `CHECK ((volume_value > (0)::numeric))`
- **FK** `product_variant_product_id_fkey`: `FOREIGN KEY (product_id) REFERENCES core.product(id)`
- **PK** `product_variant_pkey`: `PRIMARY KEY (id)`

</details>

<details><summary>Índices</summary>

- `product_variant_gtin_uq`: `CREATE UNIQUE INDEX product_variant_gtin_uq ON core.product_variant USING btree (gtin) WHERE (gtin IS NOT NULL)`
- `product_variant_product_idx`: `CREATE INDEX product_variant_product_idx ON core.product_variant USING btree (product_id)`

</details>

<details><summary>Triggers</summary>

- `product_variant_capture_version`: `CREATE TRIGGER product_variant_capture_version AFTER INSERT OR UPDATE ON core.product_variant FOR EACH ROW EXECUTE FUNCTION ops.capture_version('core.product_variant_version', 'product_variant_id')`
- `product_variant_no_delete`: `CREATE TRIGGER product_variant_no_delete BEFORE DELETE ON core.product_variant FOR EACH ROW EXECUTE FUNCTION ops.forbid_delete()`
- `product_variant_set_updated_at`: `CREATE TRIGGER product_variant_set_updated_at BEFORE UPDATE ON core.product_variant FOR EACH ROW EXECUTE FUNCTION ops.set_updated_at()`

</details>

### `core.product_variant_version`

Histórico SCD2 de core.product_variant (ops.capture_version).

| Coluna | Tipo | Nulo | Default | Descrição |
|---|---|---|---|---|
| `id` | uuid | não | `gen_random_uuid()` | Chave primária (UUID). |
| `product_variant_id` | uuid | não |  | FK → `core.product_variant`. |
| `version_no` | integer | não |  | Número sequencial da versão. |
| `valid_from` | timestamp with time zone | não |  | Início de vigência (SCD2). |
| `valid_to` | timestamp with time zone | sim |  | Fim de vigência (SCD2). NULL = vigente. |
| `snapshot` | jsonb | não |  |  |
| `changed_fields` | text[] | sim |  |  |
| `change_origin` | text | sim |  |  |

<details><summary>Constraints</summary>

- **CHECK** `product_variant_version_check`: `CHECK (((valid_to IS NULL) OR (valid_to >= valid_from)))`
- **CHECK** `product_variant_version_version_no_check`: `CHECK ((version_no > 0))`
- **FK** `product_variant_version_product_variant_id_fkey`: `FOREIGN KEY (product_variant_id) REFERENCES core.product_variant(id)`
- **PK** `product_variant_version_pkey`: `PRIMARY KEY (id)`
- **UNIQUE** `product_variant_version_product_variant_id_version_no_key`: `UNIQUE (product_variant_id, version_no)`

</details>

<details><summary>Índices</summary>

- `product_variant_version_current_uq`: `CREATE UNIQUE INDEX product_variant_version_current_uq ON core.product_variant_version USING btree (product_variant_id) WHERE (valid_to IS NULL)`

</details>

### `core.product_version`

Histórico SCD2 de core.product (ops.capture_version). Versão vigente: valid_to IS NULL.

| Coluna | Tipo | Nulo | Default | Descrição |
|---|---|---|---|---|
| `id` | uuid | não | `gen_random_uuid()` | Chave primária (UUID). |
| `product_id` | uuid | não |  | FK → `core.product`. |
| `version_no` | integer | não |  | Número sequencial da versão. |
| `valid_from` | timestamp with time zone | não |  | Início de vigência (SCD2). |
| `valid_to` | timestamp with time zone | sim |  | Fim de vigência (SCD2). NULL = vigente. |
| `snapshot` | jsonb | não |  |  |
| `changed_fields` | text[] | sim |  |  |
| `change_origin` | text | sim |  |  |

<details><summary>Constraints</summary>

- **CHECK** `product_version_check`: `CHECK (((valid_to IS NULL) OR (valid_to >= valid_from)))`
- **CHECK** `product_version_version_no_check`: `CHECK ((version_no > 0))`
- **FK** `product_version_product_id_fkey`: `FOREIGN KEY (product_id) REFERENCES core.product(id)`
- **PK** `product_version_pkey`: `PRIMARY KEY (id)`
- **UNIQUE** `product_version_product_id_version_no_key`: `UNIQUE (product_id, version_no)`

</details>

<details><summary>Índices</summary>

- `product_version_current_uq`: `CREATE UNIQUE INDEX product_version_current_uq ON core.product_version USING btree (product_id) WHERE (valid_to IS NULL)`

</details>

### `core.review_aggregate`

Agregado de avaliações de consumidor por fonte e data. Avaliação ≠ evidência científica (G-06). Não é proxy de vendas (G-07).

| Coluna | Tipo | Nulo | Default | Descrição |
|---|---|---|---|---|
| `id` | uuid | não | `gen_random_uuid()` | Chave primária (UUID). |
| `product_id` | uuid | sim |  | FK → `core.product`. Preenchido quando a fonte agrega avaliações no nível do produto. |
| `variant_id` | uuid | sim |  | FK → `core.product_variant`. Preenchido quando a fonte agrega avaliações no nível da variante. |
| `source_id` | uuid | não |  | FK → `ops.source`. |
| `observed_at` | timestamp with time zone | não |  |  |
| `avg_rating` | numeric(4,2) | sim |  |  |
| `rating_scale_max` | numeric(4,1) | não | `5` |  |
| `review_count` | integer | sim |  |  |
| `positive_themes` | jsonb | sim |  | Temas positivos inferidos: [{theme, count, example_signal_ids}]. Rastreio em themes_*. |
| `negative_themes` | jsonb | sim |  | Temas negativos/reclamações recorrentes inferidos, mesma estrutura. |
| `themes_model` | text | sim |  |  |
| `themes_prompt_version` | text | sim |  |  |
| `themes_confidence` | numeric(3,2) | sim |  |  |
| `evidence_id` | uuid | não |  | FK → `core.evidence`. |
| `created_at` | timestamp with time zone | não | `now()` | Data/hora de criação do registro. |

<details><summary>Constraints</summary>

- **CHECK** `review_aggregate_check`: `CHECK (((product_id IS NOT NULL) OR (variant_id IS NOT NULL)))`
- **CHECK** `review_aggregate_check1`: `CHECK (((avg_rating IS NULL) OR ((avg_rating >= (0)::numeric) AND (avg_rating <= rating_scale_max))))`
- **CHECK** `review_aggregate_check2`: `CHECK ((((positive_themes IS NULL) AND (negative_themes IS NULL)) OR (themes_prompt_version IS NOT NULL)))`
- **CHECK** `review_aggregate_review_count_check`: `CHECK ((review_count >= 0))`
- **CHECK** `review_aggregate_themes_confidence_check`: `CHECK (((themes_confidence >= (0)::numeric) AND (themes_confidence <= (1)::numeric)))`
- **FK** `review_aggregate_evidence_id_fkey`: `FOREIGN KEY (evidence_id) REFERENCES core.evidence(id)`
- **FK** `review_aggregate_product_id_fkey`: `FOREIGN KEY (product_id) REFERENCES core.product(id)`
- **FK** `review_aggregate_source_id_fkey`: `FOREIGN KEY (source_id) REFERENCES ops.source(id)`
- **FK** `review_aggregate_variant_id_fkey`: `FOREIGN KEY (variant_id) REFERENCES core.product_variant(id)`
- **PK** `review_aggregate_pkey`: `PRIMARY KEY (id)`

</details>

<details><summary>Índices</summary>

- `review_aggregate_product_idx`: `CREATE INDEX review_aggregate_product_idx ON core.review_aggregate USING btree (product_id, observed_at DESC)`
- `review_aggregate_variant_idx`: `CREATE INDEX review_aggregate_variant_idx ON core.review_aggregate USING btree (variant_id, observed_at DESC)`

</details>

### `core.signal_classification`

Classificação de um sinal pela taxonomia §6.2. Sempre inferência (is_inferred implícito = true). Reclassificação marca superseded_at e insere nova linha; o sinal original não muda.

| Coluna | Tipo | Nulo | Default | Descrição |
|---|---|---|---|---|
| `id` | uuid | não | `gen_random_uuid()` | Chave primária (UUID). |
| `signal_id` | uuid | não |  | FK → `core.consumer_signal`. |
| `voice_type_id` | uuid | não |  | FK → `core.voice_type`. |
| `theme` | text | não |  | TEMA (saída obrigatória §6.2). |
| `need` | text | não |  | NECESSIDADE (saída obrigatória §6.2). |
| `context` | text | não |  | CONTEXTO de uso/ocasião (saída obrigatória §6.2). |
| `intensity` | smallint | não |  | INTENSIDADE 1–5. FREQUÊNCIA é calculada na agregação (analytics). |
| `signal_phrase_match` | text | sim |  | Trecho do texto que casou com uma frase-sinal. |
| `signal_phrase_id` | uuid | sim |  | FK → `core.signal_phrase`. |
| `sentiment` | text | sim |  |  |
| `confidence` | numeric(3,2) | não |  |  |
| `model` | text | não |  |  |
| `prompt_version` | text | não |  |  |
| `classified_at` | timestamp with time zone | não | `now()` |  |
| `reviewed` | boolean | não | `false` | true após validação humana; correções em ops.human_review (G-10). |
| `reviewed_by` | text | sim |  |  |
| `reviewed_at` | timestamp with time zone | sim |  |  |
| `superseded_at` | timestamp with time zone | sim |  | Preenchido quando a classificação é substituída. NULL = vigente. |

<details><summary>Constraints</summary>

- **CHECK** `signal_classification_check`: `CHECK (((NOT reviewed) OR ((reviewed_by IS NOT NULL) AND (reviewed_at IS NOT NULL))))`
- **CHECK** `signal_classification_confidence_check`: `CHECK (((confidence >= (0)::numeric) AND (confidence <= (1)::numeric)))`
- **CHECK** `signal_classification_intensity_check`: `CHECK (((intensity >= 1) AND (intensity <= 5)))`
- **CHECK** `signal_classification_sentiment_check`: `CHECK ((sentiment = ANY (ARRAY['positive'::text, 'neutral'::text, 'negative'::text, 'mixed'::text])))`
- **FK** `signal_classification_signal_id_fkey`: `FOREIGN KEY (signal_id) REFERENCES core.consumer_signal(id)`
- **FK** `signal_classification_signal_phrase_id_fkey`: `FOREIGN KEY (signal_phrase_id) REFERENCES core.signal_phrase(id)`
- **FK** `signal_classification_voice_type_id_fkey`: `FOREIGN KEY (voice_type_id) REFERENCES core.voice_type(id)`
- **PK** `signal_classification_pkey`: `PRIMARY KEY (id)`

</details>

<details><summary>Índices</summary>

- `signal_classification_current_uq`: `CREATE UNIQUE INDEX signal_classification_current_uq ON core.signal_classification USING btree (signal_id, voice_type_id) WHERE (superseded_at IS NULL)`
- `signal_classification_voice_idx`: `CREATE INDEX signal_classification_voice_idx ON core.signal_classification USING btree (voice_type_id) WHERE (superseded_at IS NULL)`

</details>

### `core.signal_phrase`

Frases-sinal para pré-filtro/realce de sinais (SPEC §6.2). Expandida por revisão humana (origin = human_review).

| Coluna | Tipo | Nulo | Default | Descrição |
|---|---|---|---|---|
| `id` | uuid | não | `gen_random_uuid()` | Chave primária (UUID). |
| `phrase_pattern` | text | não |  | Padrão em minúsculas. A comparação é feita no código após normalização (lower + unaccent) do texto e do padrão. Para regex, expressão POSIX. |
| `match_type` | text | não | `'prefix'::text` |  |
| `language` | text | não | `'pt-BR'::text` |  |
| `suggested_voice_type_id` | uuid | sim |  | FK → `core.voice_type`. Sugestão de tipo de voz. Heurística de pré-classificação, não substitui a classificação validada. |
| `origin` | text | não | `'seed'::text` |  |
| `notes` | text | sim |  |  |
| `active` | boolean | não | `true` | Item ativo para uso. |
| `created_at` | timestamp with time zone | não | `now()` | Data/hora de criação do registro. |
| `updated_at` | timestamp with time zone | não | `now()` | Data/hora da última alteração (trigger ops.set_updated_at). |

<details><summary>Constraints</summary>

- **CHECK** `signal_phrase_match_type_check`: `CHECK ((match_type = ANY (ARRAY['prefix'::text, 'contains'::text, 'regex'::text])))`
- **CHECK** `signal_phrase_origin_check`: `CHECK ((origin = ANY (ARRAY['seed'::text, 'human_review'::text])))`
- **FK** `signal_phrase_suggested_voice_type_id_fkey`: `FOREIGN KEY (suggested_voice_type_id) REFERENCES core.voice_type(id)`
- **PK** `signal_phrase_pkey`: `PRIMARY KEY (id)`
- **UNIQUE** `signal_phrase_phrase_pattern_language_key`: `UNIQUE (phrase_pattern, language)`

</details>

<details><summary>Triggers</summary>

- `signal_phrase_set_updated_at`: `CREATE TRIGGER signal_phrase_set_updated_at BEFORE UPDATE ON core.signal_phrase FOR EACH ROW EXECUTE FUNCTION ops.set_updated_at()`

</details>

### `core.subcategory`

Taxonomia de subcategoria, filha de core.category. (id, category_id) único para FK composta que garante coerência categoria × subcategoria.

| Coluna | Tipo | Nulo | Default | Descrição |
|---|---|---|---|---|
| `id` | uuid | não | `gen_random_uuid()` | Chave primária (UUID). |
| `category_id` | uuid | não |  | FK → `core.category`. |
| `code` | text | não |  | Código estável (slug) usado em seeds, filtros e integrações. |
| `name_pt` | text | não |  | Nome de exibição em pt-BR. |
| `description` | text | sim |  |  |
| `sort_order` | integer | não | `0` | Ordem de exibição. |
| `active` | boolean | não | `true` | Item ativo para uso. |
| `created_at` | timestamp with time zone | não | `now()` | Data/hora de criação do registro. |
| `updated_at` | timestamp with time zone | não | `now()` | Data/hora da última alteração (trigger ops.set_updated_at). |

<details><summary>Constraints</summary>

- **CHECK** `subcategory_code_check`: `CHECK ((code ~ '^[a-z0-9_]+$'::text))`
- **FK** `subcategory_category_id_fkey`: `FOREIGN KEY (category_id) REFERENCES core.category(id)`
- **PK** `subcategory_pkey`: `PRIMARY KEY (id)`
- **UNIQUE** `subcategory_code_key`: `UNIQUE (code)`
- **UNIQUE** `subcategory_id_category_id_key`: `UNIQUE (id, category_id)`

</details>

<details><summary>Triggers</summary>

- `subcategory_set_updated_at`: `CREATE TRIGGER subcategory_set_updated_at BEFORE UPDATE ON core.subcategory FOR EACH ROW EXECUTE FUNCTION ops.set_updated_at()`

</details>

### `core.technology_asset`

Patentes, marcas registradas, ativos proprietários e tecnologias. Patente/fornecedor nunca inventados (G-03).

| Coluna | Tipo | Nulo | Default | Descrição |
|---|---|---|---|---|
| `id` | uuid | não | `gen_random_uuid()` | Chave primária (UUID). |
| `brand_id` | uuid | não |  | FK → `core.brand`. |
| `product_id` | uuid | sim |  | FK → `core.product`. |
| `name` | text | não |  |  |
| `type` | text | não |  |  |
| `verification_status` | text | não | `'declared'::text` | confirmed (verificado em registro oficial) \| declared (afirmado pela marca) \| unverified. |
| `registry_number` | text | sim |  | Número de registro (INPI, USPTO, WIPO...). Obrigatório para patente/marca confirmada. |
| `jurisdiction` | text | sim |  |  |
| `verified_at` | timestamp with time zone | sim |  |  |
| `evidence_id` | uuid | não |  | FK → `core.evidence`. |
| `notes` | text | sim |  |  |
| `created_at` | timestamp with time zone | não | `now()` | Data/hora de criação do registro. |
| `updated_at` | timestamp with time zone | não | `now()` | Data/hora da última alteração (trigger ops.set_updated_at). |

<details><summary>Constraints</summary>

- **CHECK** `technology_asset_check`: `CHECK (((verification_status <> 'confirmed'::text) OR (verified_at IS NOT NULL)))`
- **CHECK** `technology_asset_check1`: `CHECK (((verification_status <> 'confirmed'::text) OR (type <> ALL (ARRAY['patent'::text, 'trademark'::text])) OR (registry_number IS NOT NULL)))`
- **CHECK** `technology_asset_type_check`: `CHECK ((type = ANY (ARRAY['patent'::text, 'trademark'::text, 'proprietary_active'::text, 'technology'::text])))`
- **CHECK** `technology_asset_verification_status_check`: `CHECK ((verification_status = ANY (ARRAY['confirmed'::text, 'declared'::text, 'unverified'::text])))`
- **FK** `technology_asset_brand_id_fkey`: `FOREIGN KEY (brand_id) REFERENCES core.brand(id)`
- **FK** `technology_asset_evidence_id_fkey`: `FOREIGN KEY (evidence_id) REFERENCES core.evidence(id)`
- **FK** `technology_asset_product_id_fkey`: `FOREIGN KEY (product_id) REFERENCES core.product(id)`
- **PK** `technology_asset_pkey`: `PRIMARY KEY (id)`

</details>

<details><summary>Índices</summary>

- `technology_asset_brand_idx`: `CREATE INDEX technology_asset_brand_idx ON core.technology_asset USING btree (brand_id)`

</details>

<details><summary>Triggers</summary>

- `technology_asset_set_updated_at`: `CREATE TRIGGER technology_asset_set_updated_at BEFORE UPDATE ON core.technology_asset FOR EACH ROW EXECUTE FUNCTION ops.set_updated_at()`

</details>

### `core.trend_class`

Classificação de tendência (SPEC §8). Limiares quantitativos dependem dos pesos do Índice de Tendência (Q-17).

| Coluna | Tipo | Nulo | Default | Descrição |
|---|---|---|---|---|
| `id` | uuid | não | `gen_random_uuid()` | Chave primária (UUID). |
| `code` | text | não |  | Código estável (slug) usado em seeds, filtros e integrações. |
| `name_pt` | text | não |  | Nome de exibição em pt-BR. |
| `description` | text | não |  |  |
| `sort_order` | integer | não | `0` | Ordem de exibição. |
| `active` | boolean | não | `true` | Item ativo para uso. |
| `created_at` | timestamp with time zone | não | `now()` | Data/hora de criação do registro. |
| `updated_at` | timestamp with time zone | não | `now()` | Data/hora da última alteração (trigger ops.set_updated_at). |

<details><summary>Constraints</summary>

- **CHECK** `trend_class_code_check`: `CHECK ((code ~ '^[a-z0-9_]+$'::text))`
- **PK** `trend_class_pkey`: `PRIMARY KEY (id)`
- **UNIQUE** `trend_class_code_key`: `UNIQUE (code)`

</details>

<details><summary>Triggers</summary>

- `trend_class_set_updated_at`: `CREATE TRIGGER trend_class_set_updated_at BEFORE UPDATE ON core.trend_class FOR EACH ROW EXECUTE FUNCTION ops.set_updated_at()`

</details>

### `core.trend_series`

Série de interesse relativo. Valores comparáveis apenas dentro do mesmo query_batch_id. Nunca tratar como tamanho de mercado (G-07, §6.1).

| Coluna | Tipo | Nulo | Default | Descrição |
|---|---|---|---|---|
| `id` | uuid | não | `gen_random_uuid()` | Chave primária (UUID). |
| `term` | text | não |  |  |
| `source` | text | não |  |  |
| `source_id` | uuid | sim |  | FK → `ops.source`. |
| `region` | text | não |  | Código ISO 3166 (BR, BR-SP...) ou "GLOBAL". |
| `period_start` | date | não |  |  |
| `period_end` | date | não |  |  |
| `relative_interest` | numeric(6,2) | não |  | Google Trends: 0–100 relativo ao pico do lote. internal_signals: contagem/índice interno documentado. |
| `query_batch_id` | uuid | não |  | Identifica a consulta conjunta; o Google Trends renormaliza a cada consulta. |
| `note` | text | não | `'relative_not_absolute'::text` | Fixo em relative_not_absolute (rótulo obrigatório). |
| `raw_document_id` | uuid | sim |  | FK → `raw.raw_document`. |
| `collected_at` | timestamp with time zone | não |  |  |
| `created_at` | timestamp with time zone | não | `now()` | Data/hora de criação do registro. |

<details><summary>Constraints</summary>

- **CHECK** `trend_series_check`: `CHECK ((period_end >= period_start))`
- **CHECK** `trend_series_check1`: `CHECK (((source <> 'google_trends'::text) OR (relative_interest <= (100)::numeric)))`
- **CHECK** `trend_series_note_check`: `CHECK ((note = 'relative_not_absolute'::text))`
- **CHECK** `trend_series_relative_interest_check`: `CHECK ((relative_interest >= (0)::numeric))`
- **CHECK** `trend_series_source_check`: `CHECK ((source = ANY (ARRAY['google_trends'::text, 'internal_signals'::text])))`
- **FK** `trend_series_raw_document_id_fkey`: `FOREIGN KEY (raw_document_id) REFERENCES raw.raw_document(id)`
- **FK** `trend_series_source_id_fkey`: `FOREIGN KEY (source_id) REFERENCES ops.source(id)`
- **PK** `trend_series_pkey`: `PRIMARY KEY (id)`
- **UNIQUE** `trend_series_term_source_region_period_start_period_end_que_key`: `UNIQUE (term, source, region, period_start, period_end, query_batch_id)`

</details>

<details><summary>Índices</summary>

- `trend_series_term_idx`: `CREATE INDEX trend_series_term_idx ON core.trend_series USING btree (term, region, period_start)`

</details>

### `core.voice_type`

Taxonomia de voz do consumidor (SPEC §6.2).

| Coluna | Tipo | Nulo | Default | Descrição |
|---|---|---|---|---|
| `id` | uuid | não | `gen_random_uuid()` | Chave primária (UUID). |
| `code` | text | não |  | Código estável (slug) usado em seeds, filtros e integrações. |
| `name_pt` | text | não |  | Nome de exibição em pt-BR. |
| `description` | text | não |  |  |
| `sort_order` | integer | não | `0` | Ordem de exibição. |
| `active` | boolean | não | `true` | Item ativo para uso. |
| `created_at` | timestamp with time zone | não | `now()` | Data/hora de criação do registro. |
| `updated_at` | timestamp with time zone | não | `now()` | Data/hora da última alteração (trigger ops.set_updated_at). |

<details><summary>Constraints</summary>

- **CHECK** `voice_type_code_check`: `CHECK ((code ~ '^[a-z0-9_]+$'::text))`
- **PK** `voice_type_pkey`: `PRIMARY KEY (id)`
- **UNIQUE** `voice_type_code_key`: `UNIQUE (code)`

</details>

<details><summary>Triggers</summary>

- `voice_type_set_updated_at`: `CREATE TRIGGER voice_type_set_updated_at BEFORE UPDATE ON core.voice_type FOR EACH ROW EXECUTE FUNCTION ops.set_updated_at()`

</details>

## Funções

| Função | Descrição |
|---|---|
| `core.compute_unit_price()` | Trigger BEFORE INSERT/UPDATE em price_observation: calcula preço por ml/g somente quando G-05 é atendido. |
| `ops.add_traceable_field(p_table regclass, p_column text, p_type text, p_comment text)` | Aplica o padrão de campo rastreável (§4.1) + missing_reason (G-03) a uma coluna e registra em ops.traceable_field. |
| `ops.capture_version()` | Trigger AFTER INSERT OR UPDATE: grava snapshot jsonb da linha na tabela de versão (SCD2), fecha a versão anterior e registra campos alterados (G-04). |
| `ops.forbid_delete()` | Trigger BEFORE DELETE: impede exclusão física de entidades versionadas (G-04). |
| `ops.forbid_update()` | Trigger BEFORE UPDATE: rejeita alteração em tabela imutável, exceto colunas passadas como argumento (G-02, G-10). |
| `ops.set_updated_at()` | Trigger BEFORE UPDATE: mantém updated_at. |

## Campos rastreáveis registrados (`ops.traceable_field`)

| Tabela | Coluna | Tipo |
|---|---|---|
| `core.brand` | `approx_sku_count` | integer check (approx_sku_count >= 0) |
| `core.brand` | `competitive_archetype` | text |
| `core.brand` | `country` | char(2) |
| `core.brand` | `declared_audience` | text |
| `core.brand` | `declared_differentials` | text[] |
| `core.brand` | `founded_year` | smallint check (founded_year between 1800 and 2100) |
| `core.brand` | `founder_influencer` | text |
| `core.brand` | `inferred_audience` | text |
| `core.brand` | `positioning` | text |
| `core.brand` | `price_tier` | text |
| `core.brand` | `sales_channels` | text[] |
| `core.brand` | `value_proposition` | text |
| `core.claim` | `claim_type` | text check (claim_type in ('benefit', 'efficacy', 'metric', 'safety', 'sustainability')) |
| `core.consumer_signal` | `related_brand_id` | uuid references core.brand(id) |
| `core.consumer_signal` | `related_product_id` | uuid references core.product(id) |
| `core.packaging` | `dispensing_mechanism` | text |
| `core.packaging` | `material` | text |
| `core.packaging` | `portability` | text |
| `core.packaging` | `refill_available` | boolean |
| `core.packaging` | `type` | text |
| `core.packaging` | `visual_notes` | text |
| `core.product` | `body_area` | text[] check (body_area <@ array['rosto', 'area_dos_olhos', 'labios', 'pescoco_colo', 'corpo', 'maos', 'pes', 'couro_cabeludo', 'cabelo']) |
| `core.product` | `category_id` | uuid references core.category(id) |
| `core.product` | `format_id` | uuid references core.format(id) |
| `core.product` | `launch_date` | date |
| `core.product` | `skin_type` | text[] check (skin_type <@ array['normal', 'seca', 'oleosa', 'mista', 'sensivel', 'acneica', 'madura', 'todos_os_tipos']) |
| `core.product` | `spf_declared` | smallint check (spf_declared between 1 and 100) |
| `core.product` | `status` | text check (status in ('launch', 'permanent', 'limited', 'discontinued')) |
| `core.product` | `subcategory_id` | uuid |
| `core.product` | `suggested_frequency` | text |
| `core.product` | `target_audience_declared` | text |
| `core.product` | `use_occasion` | text |
| `core.product_ingredient` | `declared_concentration` | numeric(9,4) check (declared_concentration > 0) |
| `core.product_variant` | `gtin` | text check (gtin ~ '^[0-9]{8,14}$') |
| `core.product_variant` | `volume_value` | numeric(10,3) check (volume_value > 0) |

## Anexo — Taxonomias semeadas (F0-03, proposta v0.1)

### Categoria e subcategoria

| Categoria | Código subcategoria | Nome | Descrição |
|---|---|---|---|
| `skincare_facial` | `limpeza_facial` | Limpeza facial | Sabonetes, géis, espumas e óleos de limpeza. |
| `skincare_facial` | `demaquilante` | Demaquilante | Água micelar, bifásico, balm de limpeza. |
| `skincare_facial` | `esfoliacao_facial` | Esfoliação facial | Esfoliantes físicos, químicos (AHA/BHA/PHA) e enzimáticos. |
| `skincare_facial` | `tonico_essencia` | Tônico e essência | Tônicos, essências e loções preparadoras. |
| `skincare_facial` | `serum_tratamento` | Sérum e concentrado | Séruns, ampolas e concentrados de ativos. |
| `skincare_facial` | `hidratante_facial` | Hidratante facial | Cremes, géis e emulsões hidratantes de uso diário. |
| `skincare_facial` | `area_dos_olhos` | Área dos olhos | Tratamentos para olheiras, bolsas e linhas perioculares. |
| `skincare_facial` | `mascara_facial` | Máscara facial | Máscaras de tecido, argila, gel e overnight. |
| `skincare_facial` | `oleo_facial` | Óleo facial | Óleos de tratamento facial (não de limpeza). |
| `skincare_facial` | `bruma_facial` | Bruma facial | Brumas e águas termais sem FPS como benefício principal. |
| `skincare_facial` | `tratamento_localizado` | Tratamento localizado | Secativos, patches de acne, tratamento pontual de manchas. |
| `protecao_solar` | `fps_facial` | Protetor solar facial | Fotoprotetor facial sem cor. |
| `protecao_solar` | `fps_facial_com_cor` | Protetor solar facial com cor | Fotoprotetor facial com pigmento/tonalidade, apelo principal proteção. |
| `protecao_solar` | `fps_corporal` | Protetor solar corporal | Fotoprotetor para corpo. |
| `protecao_solar` | `fps_labial` | Protetor solar labial | Fotoprotetor para lábios. |
| `protecao_solar` | `fps_infantil` | Protetor solar infantil | Fotoprotetor declarado para uso infantil. |
| `protecao_solar` | `pos_sol` | Pós-sol | Produtos de alívio e reparação após exposição solar. |
| `maquiagem` | `base` | Base | Bases de cobertura média a alta. |
| `maquiagem` | `pele_tratamento_cor` | Skin tint, BB e CC | Coberturas leves com apelo de tratamento. |
| `maquiagem` | `corretivo` | Corretivo | Corretivos e neutralizadores. |
| `maquiagem` | `po_facial` | Pó facial | Pós compactos e soltos de acabamento. |
| `maquiagem` | `primer` | Primer | Preparadores de pele para maquiagem. |
| `maquiagem` | `fixador_maquiagem` | Fixador de maquiagem | Sprays e brumas fixadoras. |
| `maquiagem` | `blush` | Blush | Blushes em pó, creme, líquido ou stick. |
| `maquiagem` | `bronzer_contorno` | Bronzer e contorno | Bronzers e produtos de contorno. |
| `maquiagem` | `iluminador` | Iluminador | Iluminadores faciais. |
| `maquiagem` | `multifuncional_rosto` | Multifuncional | Produto declarado para mais de uma área (bochechas, lábios, olhos). |
| `maquiagem` | `sombra` | Sombra | Sombras e paletas. |
| `maquiagem` | `delineador` | Delineador | Delineadores e lápis de olho. |
| `maquiagem` | `mascara_cilios` | Máscara de cílios | Máscaras para cílios. |
| `maquiagem` | `sobrancelha` | Sobrancelha | Géis, lápis, pomadas e pós para sobrancelha. |
| `maquiagem` | `batom` | Batom | Batons cremosos, matte e líquidos. |
| `maquiagem` | `gloss` | Gloss | Gloss e óleos labiais com cor. |
| `maquiagem` | `lip_tint` | Lip tint | Tintas labiais e balms com cor. |
| `maquiagem` | `lapis_labial` | Lápis labial | Contornos e lápis labiais. |
| `labios` | `balm_labial` | Balm labial | Balms e hidratantes labiais sem cor como apelo principal. |
| `labios` | `mascara_labial` | Máscara labial | Máscaras labiais (inclusive overnight). |
| `labios` | `esfoliante_labial` | Esfoliante labial | Esfoliantes para lábios. |
| `labios` | `tratamento_labial` | Tratamento labial | Volumizadores, óleos e séruns labiais de tratamento. |
| `corpo` | `hidratante_corporal` | Hidratante corporal | Loções, cremes, manteigas e géis corporais. |
| `corpo` | `oleo_corporal` | Óleo corporal | Óleos corporais. |
| `corpo` | `sabonete_corporal` | Sabonete corporal | Sabonetes líquidos, em barra e óleos de banho. |
| `corpo` | `esfoliante_corporal` | Esfoliante corporal | Esfoliantes físicos e químicos para corpo. |
| `corpo` | `tratamento_corporal` | Tratamento corporal | Firmeza, celulite, estrias, manchas e acne corporais. |
| `corpo` | `maos_pes` | Mãos e pés | Cremes e tratamentos para mãos, pés e cutículas. |
| `corpo` | `desodorante` | Desodorante e antitranspirante | Desodorantes e antitranspirantes. |
| `corpo` | `autobronzeador` | Autobronzeador | Autobronzeadores e bronzeamento sem sol. |
| `corpo` | `iluminador_corporal` | Iluminador corporal | Óleos/géis com brilho e maquiagem corporal. |
| `cabelos` | `shampoo` | Shampoo | Shampoos líquidos e sólidos. |
| `cabelos` | `condicionador` | Condicionador | Condicionadores e co-wash. |
| `cabelos` | `mascara_capilar` | Máscara capilar | Máscaras e tratamentos de enxágue. |
| `cabelos` | `leave_in_finalizador` | Leave-in e finalizador | Leave-ins, cremes de pentear, finalizadores. |
| `cabelos` | `oleo_capilar` | Óleo capilar | Óleos e séruns capilares. |
| `cabelos` | `couro_cabeludo` | Couro cabeludo | Tônicos e tratamentos de couro cabeludo. |
| `fragrancias` | `perfume` | Perfume | Extrait, EDP, EDT e colônias. |
| `fragrancias` | `body_splash_mist` | Body splash e mist | Body splash, body mist e hair mist. |
| `dispositivos_acessorios` | `dispositivo_eletronico` | Dispositivo eletrônico | LED, microcorrente, radiofrequência, limpeza sônica. |
| `dispositivos_acessorios` | `ferramenta_aplicacao` | Ferramenta de aplicação | Esponjas, pincéis, gua sha, rolos. |

### Formato

| Grupo | Código | Nome | Descrição |
|---|---|---|---|
| liquido | `liquido_aquoso` | Líquido aquoso | Tônicos, águas micelares, essências, tintas labiais à base de água. |
| liquido | `serum` | Sérum | Líquido de baixa viscosidade concentrado em ativos (aquoso ou emulsionado leve). |
| liquido | `oleo` | Óleo | Veículo oleoso líquido. |
| liquido | `bifasico` | Bifásico | Duas fases que se separam em repouso; agitar antes do uso. |
| liquido | `espuma` | Espuma/mousse | Espuma formada por pump ou válvula. Espuma em lata pressurizada → aerossol. |
| liquido | `spray_nao_aerossol` | Spray/bruma | Líquido dispensado em névoa por válvula mecânica, sem propelente. |
| emulsao | `creme` | Creme | Emulsão de média a alta viscosidade. |
| emulsao | `locao` | Loção/leite | Emulsão fluida espalhável. |
| emulsao | `fluido` | Fluido | Emulsão muito leve, típica de fotoprotetor facial e base. |
| emulsao | `gel_creme` | Gel-creme | Emulsão com polímero gelificante, toque leve. |
| emulsao | `pasta` | Pasta | Dispersão densa de sólidos (argila, óxidos). |
| gel | `gel` | Gel | Gel aquoso transparente ou translúcido. |
| gel | `jelly` | Jelly/gelatina | Gel elástico de alta coesão. |
| gel | `gel_oleo` | Gel-óleo | Óleo gelificado. |
| anidro | `balm` | Balm/bálsamo | Anidro semissólido de espalhar com os dedos (inclusive balm-to-oil). |
| anidro | `stick` | Stick/bastão | Anidro moldado de aplicação direta na pele, em embalagem giratória ou push-up. |
| anidro | `bala` | Bala (batom) | Anidro moldado em formato de batom clássico. |
| anidro | `lapis` | Lápis | Mina em lápis de madeira ou retrátil. |
| solido | `barra` | Barra sólida | Sabonete, shampoo ou hidratante em barra. |
| solido | `capsula` | Cápsula monodose | Dose única encapsulada (biodegradável ou gelatinosa). |
| po | `po_compacto` | Pó compacto | Pó prensado. |
| po | `po_solto` | Pó solto | Pó não prensado, inclusive pó-para-espuma. |
| pressurizado | `aerossol` | Aerossol | Produto com propelente (spray ou espuma em lata). |
| suporte | `mascara_tecido` | Máscara de tecido | Tecido/biocelulose impregnado. |
| suporte | `patch` | Patch | Adesivo hidrocoloide, hidrogel ou microagulhas. |
| suporte | `lenco` | Lenço umedecido | Lenço impregnado. |
| suporte | `cushion` | Cushion | Esponja impregnada em estojo compacto. |
| dispositivo | `dispositivo` | Dispositivo | Aparelho eletrônico ou ferramenta (sem fórmula). |

### Benefício

| Grupo | Código | Nome | Descrição |
|---|---|---|---|
| hidratacao_barreira | `hidratacao` | Hidratação | Aumento ou manutenção do conteúdo de água da pele/lábios/cabelo. |
| hidratacao_barreira | `nutricao` | Nutrição/emoliência | Reposição lipídica, maciez, conforto de pele seca. |
| hidratacao_barreira | `reparacao_barreira` | Reparação da barreira | Fortalecimento/restauração da barreira cutânea. |
| hidratacao_barreira | `calmante` | Calmante/antivermelhidão | Alívio de sensibilidade, ardor, vermelhidão. |
| protecao | `protecao_uvb` | Proteção UVB (FPS) | Proteção contra UVB; valor em product.spf_declared. |
| protecao | `protecao_uva` | Proteção UVA | Proteção UVA declarada (PPD, FPUVA, selo UVA). |
| protecao | `protecao_luz_visivel` | Proteção luz visível | Proteção contra luz visível/azul declarada. |
| protecao | `resistencia_agua_suor` | Resistência à água/suor | Resistência à água ou ao suor declarada. |
| protecao | `antipoluicao` | Antipoluição | Proteção contra poluição/partículas declarada. |
| protecao | `antioxidante` | Antioxidante | Neutralização de radicais livres declarada. |
| tratamento | `controle_oleosidade` | Controle de oleosidade | Redução de sebo/brilho. |
| tratamento | `antiacne` | Antiacne | Prevenção/tratamento de acne e cravos. |
| tratamento | `uniformizacao_manchas` | Uniformização/manchas | Clareamento de manchas, melasma, tom irregular. |
| tratamento | `antissinais` | Antissinais | Rugas, linhas finas, sinais de envelhecimento. |
| tratamento | `firmeza` | Firmeza/elasticidade | Firmeza e elasticidade de rosto ou corpo. |
| tratamento | `renovacao_celular` | Renovação/esfoliação | Renovação celular, esfoliação química ou física. |
| tratamento | `reducao_poros` | Redução de poros | Aparência de poros. |
| tratamento | `luminosidade` | Luminosidade/viço | Pele luminosa como resultado de tratamento (não pigmento). |
| tratamento | `olheiras_bolsas` | Olheiras/bolsas | Olheiras, bolsas e linhas perioculares. |
| tratamento | `celulite_estrias` | Celulite/estrias | Aparência de celulite e estrias. |
| tratamento | `volume_labial` | Volume labial | Efeito volumizador labial. |
| tratamento | `desodorante` | Desodorante/antitranspirante | Controle de odor e/ou transpiração. |
| limpeza | `limpeza` | Limpeza | Remoção de sujidades e oleosidade. |
| limpeza | `demaquilagem` | Demaquilagem | Remoção de maquiagem/fotoprotetor. |
| maquiagem_acabamento | `cobertura` | Cobertura/uniformização imediata | Cobertura de imperfeições por pigmento. |
| maquiagem_acabamento | `cor` | Cor | Pigmentação de lábios, bochechas, olhos. |
| maquiagem_acabamento | `acabamento_matte` | Acabamento matte | Acabamento sem brilho declarado. |
| maquiagem_acabamento | `acabamento_luminoso` | Acabamento luminoso | Brilho/glow por pigmento ou partículas. |
| maquiagem_acabamento | `longa_duracao` | Longa duração | Fixação/duração declarada. |
| maquiagem_acabamento | `efeito_imediato` | Efeito imediato | Blur, lifting ou alisamento óptico imediato. |
| maquiagem_acabamento | `bronzeado_sem_sol` | Bronzeado sem sol | Cor de bronzeado por DHA/pigmento. |
| maquiagem_acabamento | `multifuncionalidade` | Multifuncionalidade | Uso declarado em várias áreas ou funções no mesmo produto. |
| sensorial_bem_estar | `perfumacao` | Perfumação | Fragrância como benefício declarado. |
| sensorial_bem_estar | `sensorial_textura` | Sensorial/textura | Toque seco, não pegajoso, absorção rápida, textura declarada. |
| sensorial_bem_estar | `refrescancia` | Refrescância | Sensação de frescor/resfriamento. |
| sensorial_bem_estar | `reaplicacao_pratica` | Reaplicação prática | Aplicação/reaplicação sem mãos, sobre maquiagem ou fora de casa. |
| capilar | `reparacao_capilar` | Reparação capilar | Reconstrução de fios danificados. |
| capilar | `antifrizz_definicao` | Antifrizz/definição | Controle de frizz e definição de cachos. |
| capilar | `anticaspa` | Anticaspa | Controle de caspa/descamação do couro cabeludo. |
| capilar | `antiqueda_fortalecimento` | Antiqueda/fortalecimento | Fortalecimento e redução de queda. |

### Voz do consumidor (§6.2)

| Código | Nome | Descrição |
|---|---|---|
| `necessidade_dor` | Necessidade/dor | Problema ou necessidade não resolvida relatada pelo consumidor ("minha pele fica oleosa às 11h"). |
| `desejo` | Desejo | Algo que o consumidor gostaria de ter ou sentir, sem problema explícito ("eu queria um protetor que..."). |
| `objecao` | Objeção | Motivo declarado para não comprar ou não experimentar (preço, ingrediente, desconfiança). |
| `frustracao` | Frustração | Experiência negativa com produto já usado, sem decisão explícita de abandono. |
| `elogio` | Elogio | Avaliação positiva explícita do produto/marca. |
| `abandono` | Abandono | Relato de que deixou de usar ou não recompraria, com ou sem motivo. |
| `recompra` | Recompra | Relato de recompra, uso contínuo ou fidelidade ("já é meu terceiro"). |
| `pedido_explicito` | Pedido explícito | Solicitação direta de produto, versão, tom, tamanho ou formato inexistente. |
| `solucao_improvisada` | Solução improvisada | Gambiarra/combinação criada pelo consumidor para resolver uma necessidade (sinal de white space). |
| `comparacao` | Comparação | Comparação entre produtos/marcas, inclusive "dupe". |
| `medo_risco` | Medo/risco | Receio de reação, efeito colateral, segurança ou ingrediente. |
| `sensorial` | Sensorial | Comentário sobre textura, cheiro, toque, acabamento, absorção. |
| `embalagem` | Embalagem | Comentário sobre embalagem, dispensação, vazamento, portabilidade. |
| `preco_valor` | Preço/valor | Percepção de preço, custo-benefício, rendimento. |
| `eficacia_percebida` | Eficácia percebida | Resultado percebido pelo consumidor (funciona/não funciona). Não é evidência científica (G-06). |
| `confianca` | Confiança | Credibilidade da marca, transparência, autoridade, recomendação profissional. |
| `sustentabilidade` | Sustentabilidade | Refil, ingredientes, embalagem, impacto ambiental, testes em animais. |
| `praticidade` | Praticidade | Facilidade, tempo, reaplicação, rotina simplificada ou trabalhosa. |
| `inclusao` | Inclusão | Tons de pele, tipos de pele/cabelo, acessibilidade, representatividade. |
| `estetica_desejo` | Estética/desejo | Apelo visual do produto/embalagem, "instagramável", colecionável. |

### Classificação de tendência (§8)

| Código | Nome | Descrição |
|---|---|---|
| `sinal_fraco` | Sinal fraco | Menções esparsas, em poucas fontes, sem persistência demonstrada. Ação: monitorar e buscar confirmação cruzada. |
| `moda_passageira` | Moda passageira | Pico rápido concentrado em uma plataforma/creator, baixa diversidade de fontes e queda após o pico. Viralização sem persistência. |
| `em_formacao` | Em formação | Crescimento sustentado por múltiplos períodos e em 2 ou mais fontes independentes, ainda sem reflexo amplo na oferta. |
| `consolidada` | Consolidada | Interesse persistente em patamar estável e presença recorrente na oferta (lançamentos, claims) e na conversa do consumidor. |
| `macrotendencia` | Macrotendência | Movimento estrutural plurianual, multicategoria, sustentado por mudança de comportamento, tecnologia ou regulação. |

### Frases-sinal

| Padrão | Tipo de voz sugerido | Origem |
|---|---|---|
| "abandonei porque…" | `abandono` | SPEC §6.2 |
| "eu queria que…" | `desejo` | SPEC §6.2 |
| "não consigo usar…" | `necessidade_dor` | SPEC §6.2 |
| "não funciona em mim…" | `eficacia_percebida` | SPEC §6.2 |
| "odeio quando…" | `frustracao` | SPEC §6.2 |
| "seria perfeito se…" | `pedido_explicito` | SPEC §6.2 |
| "é trabalhoso…" | `praticidade` | SPEC §6.2 |
| "caro demais…" | `preco_valor` | Proposta NEXA v0.1 |
| "comprei de novo…" | `recompra` | Proposta NEXA v0.1 |
| "dei um jeito…" | `solucao_improvisada` | Proposta NEXA v0.1 |
| "dupe…" | `comparacao` | Proposta NEXA v0.1 |
| "já é o meu terceiro…" | `recompra` | Proposta NEXA v0.1 |
| "me deu alergia…" | `medo_risco` | Proposta NEXA v0.1 |
| "melhor que o…" | `comparacao` | Proposta NEXA v0.1 |
| "misturo com…" | `solucao_improvisada` | Proposta NEXA v0.1 |
| "não existe um…" | `pedido_explicito` | Proposta NEXA v0.1 |
| "não tem meu tom…" | `inclusao` | Proposta NEXA v0.1 |
| "parei de usar…" | `abandono` | Proposta NEXA v0.1 |
| "queria muito um…" | `pedido_explicito` | Proposta NEXA v0.1 |
| "tenho medo de…" | `medo_risco` | Proposta NEXA v0.1 |
| "vale cada centavo…" | `preco_valor` | Proposta NEXA v0.1 |
| "vazou na bolsa…" | `embalagem` | Proposta NEXA v0.1 |

