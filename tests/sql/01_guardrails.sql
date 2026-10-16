-- Testes de constraints dos guardrails (SPEC §0). Executado por scripts/validate_migrations.sh
-- dentro de uma transação; nada é persistido.

-- Insere linha a partir de jsonb, preenchendo missing_reason = 'not_collected'
-- para campos rastreáveis não informados.
create function pg_temp.ins(p_table text, p_data jsonb) returns uuid language plpgsql as $$
declare
  v_data jsonb := p_data;
  r record;
  v_cols text;
  v_id uuid;
begin
  for r in select column_name from ops.traceable_field
            where table_schema || '.' || table_name = p_table loop
    if not v_data ? r.column_name then
      v_data := v_data || jsonb_build_object(r.column_name || '_missing_reason', 'not_collected');
    end if;
  end loop;
  select string_agg(quote_ident(k), ', ') into v_cols from jsonb_object_keys(v_data) k;
  execute format('insert into %s (%s) select %s from jsonb_populate_record(null::%s, $1) returning id',
                 p_table, v_cols, v_cols, p_table) into v_id using v_data;
  return v_id;
end $$;

create function pg_temp.expect_error(p_sql text, p_label text) returns void language plpgsql as $$
begin
  begin
    execute p_sql;
  exception when others then
    raise notice 'ok   (rejeitado) %: %', p_label, sqlerrm;
    return;
  end;
  raise exception 'FALHA: % deveria ter sido rejeitado', p_label;
end $$;

create function pg_temp.assert(p_cond boolean, p_label text) returns void language plpgsql as $$
begin
  if p_cond is not true then raise exception 'FALHA: %', p_label; end if;
  raise notice 'ok   %', p_label;
end $$;

do $$
declare
  v_src uuid; v_doc uuid; v_ev uuid; v_brand uuid; v_prod uuid; v_var_lo uuid; v_var_hi uuid;
  v_po uuid; v_hr uuid; v_cat uuid; v_sub_other uuid;
begin
  -- C-01: fonte não pode ser ativada sem revisão de termos
  perform pg_temp.expect_error(
    $q$insert into ops.source (type, name, base_url, access_method, active) values ('official_site', 'X', 'https://x.test', 'crawler', true)$q$,
    'C-01 fonte ativa sem tos_reviewed_at');
  perform pg_temp.expect_error(
    $q$insert into ops.source (type, name, base_url, access_method, tos_reviewed_at, robots_allowed, active)
       values ('social_api', 'TikTok', 'https://tiktok.test', 'crawler', now(), true, true)$q$,
    'C-03 fonte social via crawler');

  insert into ops.source (type, name, base_url, access_method, tos_reviewed_at, robots_allowed, active)
  values ('official_site', 'Marca Teste', 'https://marca.test', 'crawler', now(), true, true)
  returning id into v_src;

  insert into raw.raw_document (source_id, url, fetched_at, last_fetched_at, content_hash, storage_path)
  values (v_src, 'https://marca.test/p/1', now(), now(), repeat('a', 64), 'raw/marca/1.html')
  returning id into v_doc;

  -- raw imutável
  perform pg_temp.expect_error(
    format($q$update raw.raw_document set content_hash = repeat('b', 64) where id = %L$q$, v_doc),
    'raw_document imutável');
  update raw.raw_document set last_fetched_at = now() + interval '1 day', fetch_count = 2 where id = v_doc;
  perform pg_temp.assert(true, 'raw_document aceita atualizar last_fetched_at/fetch_count');

  insert into core.evidence (raw_document_id, url, excerpt, captured_at)
  values (v_doc, 'https://marca.test/p/1', 'Protetor solar FPS 50, 30 g', now())
  returning id into v_ev;

  -- G-01/G-03: valor sem rastreio e ausência sem motivo
  perform pg_temp.expect_error(
    $q$select pg_temp.ins('core.brand', '{"name":"B1","priority_level":"P1","country":"BR"}')$q$,
    'G-01 valor sem evidence/confidence');
  perform pg_temp.expect_error(
    $q$insert into core.brand (name, priority_level) values ('B2', 'P1')$q$,
    'G-03 campo NULL sem missing_reason');
  perform pg_temp.expect_error(
    format($q$select pg_temp.ins('core.brand', '{"name":"B3","priority_level":"P1","declared_audience":"x",
      "declared_audience_is_inferred":true,"declared_audience_confidence":0.5,"declared_audience_evidence_id":"%s"}')$q$, v_ev),
    'público declarado marcado como inferido');

  v_brand := pg_temp.ins('core.brand', jsonb_build_object(
    'name', 'Marca Teste', 'priority_level', 'P1', 'country', 'BR',
    'country_is_inferred', false, 'country_confidence', 0.95, 'country_evidence_id', v_ev));

  -- G-04: versionamento
  perform pg_temp.assert((select count(*) = 1 from core.brand_version where brand_id = v_brand), 'G-04 versão 1 criada no insert');
  update core.brand set last_collected_at = now() where id = v_brand;
  perform pg_temp.assert((select count(*) = 1 from core.brand_version where brand_id = v_brand), 'G-04 controle de coleta não gera versão');
  update core.brand set positioning = 'Ciência acessível', positioning_is_inferred = true, positioning_confidence = 0.7,
                        positioning_evidence_id = v_ev, positioning_missing_reason = null
   where id = v_brand;
  perform pg_temp.assert((select count(*) = 2 and count(*) filter (where valid_to is null) = 1
                            from core.brand_version where brand_id = v_brand), 'G-04 alteração gera versão 2 e fecha a 1');
  perform pg_temp.assert((select 'positioning' = any(changed_fields) from core.brand_version
                           where brand_id = v_brand and version_no = 2), 'G-04 changed_fields registra a coluna');
  perform pg_temp.expect_error(format($q$delete from core.brand where id = %L$q$, v_brand), 'G-04 delete proibido');

  -- Coerência categoria × subcategoria
  select id into v_cat from core.category where code = 'protecao_solar';
  select id into v_sub_other from core.subcategory where code = 'batom';
  perform pg_temp.expect_error(
    format($q$select pg_temp.ins('core.product', '{"brand_id":"%s","canonical_name":"P","dedup_key":"k0",
      "category_id":"%s","category_id_is_inferred":false,"category_id_confidence":0.9,"category_id_evidence_id":"%s",
      "subcategory_id":"%s","subcategory_id_is_inferred":false,"subcategory_id_confidence":0.9,"subcategory_id_evidence_id":"%s"}')$q$,
      v_brand, v_cat, v_ev, v_sub_other, v_ev),
    'subcategoria de outra categoria');

  v_prod := pg_temp.ins('core.product', jsonb_build_object('brand_id', v_brand, 'canonical_name', 'Stick FPS 50', 'dedup_key', 'marca-teste|stick-fps-50'));

  -- G-05: preço unitário só com volume confidence >= 0.90
  v_var_lo := pg_temp.ins('core.product_variant', jsonb_build_object('product_id', v_prod, 'volume_unit', 'g',
    'volume_value', 30, 'volume_value_is_inferred', true, 'volume_value_confidence', 0.85, 'volume_value_evidence_id', v_ev));
  v_var_hi := pg_temp.ins('core.product_variant', jsonb_build_object('product_id', v_prod, 'volume_unit', 'g',
    'volume_value', 30, 'volume_value_is_inferred', false, 'volume_value_confidence', 0.95, 'volume_value_evidence_id', v_ev));

  insert into core.price_observation (variant_id, source_id, observed_at, list_price, promo_price, extraction_method, extraction_confidence, evidence_id)
  values (v_var_lo, v_src, now(), 109.99, 99.99, 'json_ld', 1, v_ev) returning id into v_po;
  perform pg_temp.assert((select unit_price_per_ml_g is null from core.price_observation where id = v_po), 'G-05 sem preço unitário com confiança 0.85');

  insert into core.price_observation (variant_id, source_id, observed_at, list_price, promo_price, extraction_method, extraction_confidence, evidence_id)
  values (v_var_hi, v_src, now(), 109.99, 99.99, 'json_ld', 1, v_ev) returning id into v_po;
  perform pg_temp.assert((select unit_price_per_ml_g = 3.6663 and unit_promo_price_per_ml_g = 3.3330
                            from core.price_observation where id = v_po), 'G-05 preço unitário calculado com confiança 0.95');

  insert into core.price_observation (variant_id, source_id, observed_at, list_price, is_kit, extraction_method, extraction_confidence, evidence_id)
  values (v_var_hi, v_src, now(), 199.90, true, 'json_ld', 1, v_ev) returning id into v_po;
  perform pg_temp.assert((select unit_price_per_ml_g is null from core.price_observation where id = v_po), 'G-05 kit sem preço unitário');

  -- G-03 / AC-03: INCI nunca inferido; claim exige evidência
  insert into core.ingredient (inci_name) values ('ECTOIN');
  perform pg_temp.expect_error(
    format($q$insert into core.product_ingredient (product_id, ingredient_id, inci_text_as_published, is_inferred, confidence, evidence_id,
               declared_concentration_missing_reason)
              select %L, id, 'Ectoin', true, 0.6, %L, 'not_published' from core.ingredient where inci_name = 'ECTOIN'$q$, v_prod, v_ev),
    'G-03 ingrediente inferido');
  perform pg_temp.expect_error(
    format($q$insert into core.claim (product_id, claim_text_exact, extraction_confidence, claim_type_missing_reason)
              values (%L, 'Resistente à água', 0.9, 'not_collected')$q$, v_prod),
    'AC-03 claim sem evidence_id');

  -- G-11 / G-07: market share
  perform pg_temp.expect_error(
    format($q$insert into core.market_share_estimate (brand_id, period_start, period_end, universe_definition, share_value_pct, status, sell_type,
               method, inputs, assumptions, bias_notes, coverage_notes, confidence, source)
              values (%L, '2026-01-01', '2026-06-30', 'Fotoproteção facial, e-commerce BR', 2.5, 'estimated', 'sell_out',
                      'm', '{published_revenue_range}', 'a', 'b', 'c', 0.4, 's')$q$, v_brand),
    'G-11 estimativa sem intervalo');
  perform pg_temp.expect_error(
    format($q$insert into core.market_share_estimate (brand_id, period_start, period_end, universe_definition, share_value_pct, status, sell_type,
               method, inputs, assumptions, bias_notes, coverage_notes, range_min, range_max, confidence, source)
              values (%L, '2026-01-01', '2026-06-30', 'u', 2.5, 'estimated', 'sell_out',
                      'm', '{followers}', 'a', 'b', 'c', 1, 4, 0.4, 's')$q$, v_brand),
    'G-07 seguidores como insumo de share');
  perform pg_temp.expect_error(
    format($q$insert into core.market_share_estimate (brand_id, period_start, period_end, universe_definition, share_value_pct, status)
              values (%L, '2026-01-01', '2026-06-30', 'u', 2.5, 'unavailable')$q$, v_brand),
    'G-11 indisponível com valor');

  -- G-10: trilha de revisão append-only
  insert into ops.human_review (entity_table, entity_id, field, old_value, new_value, reason, reviewer)
  values ('core.brand', v_brand, 'positioning', '"Ciência acessível"', '"Ciência + preço"', 'Ajuste de síntese', 'thais')
  returning id into v_hr;
  perform pg_temp.expect_error(format($q$update ops.human_review set reason = 'x' where id = %L$q$, v_hr), 'G-10 revisão imutável');
  update ops.human_review set applied_to_rules = true, applied_at = now() where id = v_hr;
  perform pg_temp.assert(true, 'G-10 marcação applied_to_rules permitida');

  -- Integridade das taxonomias semeadas
  perform pg_temp.assert((select count(*) = 20 from core.voice_type), 'voz do consumidor: 20 tipos (§6.2)');
  perform pg_temp.assert((select count(*) = 5 from core.trend_class), 'tendência: 5 classes (§8)');
  perform pg_temp.assert((select count(*) >= 7 from core.signal_phrase where notes = 'SPEC §6.2'), 'frases-sinal da SPEC');
  perform pg_temp.assert((select count(*) = 0 from core.category c where not exists
                           (select 1 from core.subcategory s where s.category_id = c.id)), 'toda categoria tem subcategoria');
end $$;
