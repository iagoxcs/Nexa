-- =============================================================================
-- NEXA LAB — F0-06/F0-07 — Lista-mãe e revisão de compliance das fontes
-- SPEC §18, F0-06, F0-07, C-01, G-02
-- =============================================================================

-- access_method "pending_review": fonte cadastrada, revisão F0-07 ainda não feita.
alter table ops.source
  drop constraint source_access_method_check,
  add constraint source_access_method_check check (access_method in (
    'api', 'licensed', 'crawler', 'browser', 'manual', 'blocked', 'pending_review')),
  alter column access_method set default 'pending_review';

alter table ops.source
  add column tos_url                 text,
  add column tos_reviewed_by         text,
  add column robots_checked_at       timestamptz,
  add column robots_raw_document_id  uuid references raw.raw_document(id),
  add column sitemap_urls            text[] not null default '{}',
  add column review_status           text not null default 'pending'
    check (review_status in ('pending', 'preliminary', 'approved', 'rejected')),
  add constraint source_tos_review_ck check (tos_reviewed_at is null or tos_reviewed_by is not null);

alter table ops.source
  drop constraint source_active_compliance_ck,
  add constraint source_active_compliance_ck check (
    not active
    or (
      tos_reviewed_at is not null
      and review_status = 'approved'
      and access_method not in ('blocked', 'pending_review')
      and (access_method not in ('crawler', 'browser') or robots_allowed is true)
    )
  );

comment on column ops.source.access_method is
  'api | licensed | crawler | browser | manual | blocked | pending_review. pending_review = cadastrada sem revisão F0-07.';
comment on column ops.source.tos_url is 'URL dos termos de uso analisados na revisão F0-07.';
comment on column ops.source.tos_reviewed_by is 'Responsável pela revisão de termos (obrigatório quando tos_reviewed_at preenchido).';
comment on column ops.source.robots_checked_at is 'Data da última leitura do robots.txt na revisão.';
comment on column ops.source.robots_raw_document_id is 'Cópia do robots.txt lido na revisão (raw.raw_document), para auditoria (G-02).';
comment on column ops.source.sitemap_urls is 'Sitemaps declarados no robots.txt ou localizados na revisão (§5.2).';
comment on column ops.source.review_status is
  'pending | preliminary (análise automatizada, sem aprovação) | approved (aprovada por Iago) | rejected. Ativação exige approved.';

-- Rastreio até a lista-mãe (§18)
alter table core.brand
  add column master_list_no smallint unique check (master_list_no > 0);
comment on column core.brand.master_list_no is 'Número da marca na lista-mãe (SPEC §18). NULL para marcas incluídas depois.';
