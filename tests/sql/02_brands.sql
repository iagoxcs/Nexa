-- Testes do seed da lista-mãe (F0-06, SPEC §18).
do $$
declare
  v_missing int;
begin
  if (select count(*) from core.brand where master_list_no is not null) <> 102 then
    raise exception 'FALHA: lista-mãe deve ter 102 marcas';
  end if;
  if (select count(distinct bs.source_id) from core.brand_source bs join core.brand b on b.id = bs.brand_id
       where b.master_list_no is not null) <> 101 then
    raise exception 'FALHA: 101 fontes oficiais esperadas (Fenty Beauty e Fenty Skin compartilham fentybeauty.com)';
  end if;
  if (select count(distinct bs.source_id) from core.brand_source bs join core.brand b on b.id = bs.brand_id
       where b.name in ('Fenty Beauty', 'Fenty Skin')) <> 1 then
    raise exception 'FALHA: Fenty Beauty e Fenty Skin devem apontar para a mesma fonte';
  end if;
  if exists (select 1 from core.brand b where b.master_list_no is not null and not exists (select 1 from core.brand_source bs where bs.brand_id = b.id)) then
    raise exception 'FALHA: marca sem fonte vinculada';
  end if;
  if exists (select 1 from ops.source s join core.brand_source bs on bs.source_id = s.id join core.brand b on b.id = bs.brand_id
             where b.master_list_no is not null and (s.active or s.access_method <> 'pending_review' or s.tos_reviewed_at is not null)) then
    raise exception 'FALHA: fontes do seed devem iniciar inativas e pendentes de revisão (F0-07)';
  end if;
  if (select count(*) from core.brand_version v join core.brand b on b.id = v.brand_id where b.master_list_no is not null) <> 102 then
    raise exception 'FALHA: seed deve gerar a versão 1 de cada marca (G-04)';
  end if;
  if exists (select 1 from core.brand_version where change_origin is distinct from 'seed:brands.csv' and version_no = 1
             and (snapshot->>'master_list_no') is not null) then
    raise exception 'FALHA: change_origin da carga deve ser seed:brands.csv';
  end if;
  if (select count(*) from core.brand where master_list_no is not null and priority_level = 'P1-A') <> 1
     or (select count(*) from core.brand where master_list_no is not null and priority_level = 'P1') <> 45
     or (select count(*) from core.brand where master_list_no is not null and priority_level = 'P2') <> 56 then
    raise exception 'FALHA: distribuição de prioridade diverge da lista-mãe (1 / 45 / 56)';
  end if;
  raise notice 'ok   lista-mãe: 102 marcas, 101 fontes, Fenty com fonte compartilhada, versões criadas';
end $$;
