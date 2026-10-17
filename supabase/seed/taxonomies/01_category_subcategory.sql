-- =============================================================================
-- NEXA LAB — F0-03 — Taxonomia: categoria e subcategoria (v1.0 — validada por Iago em 16/10/2026)
-- Status: validada por Iago em 16/10/2026. Revisões posteriores via ops.human_review.
--
-- Regras de classificação:
--   R1. Categoria = benefício principal declarado. Ex.: protetor labial com FPS →
--       protecao_solar/fps_labial; base com FPS → maquiagem/base (FPS fica em
--       product.spf_declared e em product_benefit secundário).
--   R2. Lábios: com cor/pigmento como apelo principal → maquiagem; cuidado → labios.
--   R3. Formato (stick, bruma, pó...) NÃO define subcategoria: vai em core.format.
--   R4. Kits não são categoria: price_observation.is_kit.
-- =============================================================================

insert into core.category (code, name_pt, description, sort_order) values
  ('skincare_facial',         'Skincare facial',          'Limpeza, tratamento e hidratação do rosto e área dos olhos.', 10),
  ('protecao_solar',          'Proteção solar',           'Produtos cujo benefício principal é fotoproteção, inclusive pós-sol.', 20),
  ('maquiagem',               'Maquiagem',                'Produtos cujo apelo principal é cor, cobertura ou acabamento, com ou sem tratamento.', 30),
  ('labios',                  'Cuidados com os lábios',   'Tratamento labial sem apelo principal de cor.', 40),
  ('corpo',                   'Cuidados corporais',       'Hidratação, limpeza, tratamento e higiene do corpo, mãos e pés.', 50),
  ('cabelos',                 'Cabelos e couro cabeludo', 'Cobertura de adjacência: marcas monitoradas com linhas capilares.', 60),
  ('fragrancias',             'Fragrâncias',              'Perfumes e body splash/mists.', 70),
  ('dispositivos_acessorios', 'Dispositivos e acessórios','Aparelhos de beleza e ferramentas de aplicação.', 80)
on conflict (code) do nothing;

insert into core.subcategory (category_id, code, name_pt, description, sort_order)
select c.id, v.code, v.name_pt, v.description, v.sort_order
from (values
  -- skincare_facial
  ('skincare_facial', 'limpeza_facial',         'Limpeza facial',               'Sabonetes, géis, espumas e óleos de limpeza.', 10),
  ('skincare_facial', 'demaquilante',           'Demaquilante',                 'Água micelar, bifásico, balm de limpeza.', 20),
  ('skincare_facial', 'esfoliacao_facial',      'Esfoliação facial',            'Esfoliantes físicos, químicos (AHA/BHA/PHA) e enzimáticos.', 30),
  ('skincare_facial', 'tonico_essencia',        'Tônico e essência',            'Tônicos, essências e loções preparadoras.', 40),
  ('skincare_facial', 'serum_tratamento',       'Sérum e concentrado',          'Séruns, ampolas e concentrados de ativos.', 50),
  ('skincare_facial', 'hidratante_facial',      'Hidratante facial',            'Cremes, géis e emulsões hidratantes de uso diário.', 60),
  ('skincare_facial', 'area_dos_olhos',         'Área dos olhos',               'Tratamentos para olheiras, bolsas e linhas perioculares.', 70),
  ('skincare_facial', 'mascara_facial',         'Máscara facial',               'Máscaras de tecido, argila, gel e overnight.', 80),
  ('skincare_facial', 'oleo_facial',            'Óleo facial',                  'Óleos de tratamento facial (não de limpeza).', 90),
  ('skincare_facial', 'bruma_facial',           'Bruma facial',                 'Brumas e águas termais sem FPS como benefício principal.', 100),
  ('skincare_facial', 'tratamento_localizado',  'Tratamento localizado',        'Secativos, patches de acne, tratamento pontual de manchas.', 110),
  -- protecao_solar
  ('protecao_solar',  'fps_facial',             'Protetor solar facial',        'Fotoprotetor facial sem cor.', 10),
  ('protecao_solar',  'fps_facial_com_cor',     'Protetor solar facial com cor','Fotoprotetor facial com pigmento/tonalidade, apelo principal proteção.', 20),
  ('protecao_solar',  'fps_corporal',           'Protetor solar corporal',      'Fotoprotetor para corpo.', 30),
  ('protecao_solar',  'fps_labial',             'Protetor solar labial',        'Fotoprotetor para lábios.', 40),
  ('protecao_solar',  'fps_infantil',           'Protetor solar infantil',      'Fotoprotetor declarado para uso infantil.', 50),
  ('protecao_solar',  'pos_sol',                'Pós-sol',                      'Produtos de alívio e reparação após exposição solar.', 60),
  -- maquiagem
  ('maquiagem',       'base',                   'Base',                         'Bases de cobertura média a alta.', 10),
  ('maquiagem',       'pele_tratamento_cor',    'Skin tint, BB e CC',           'Coberturas leves com apelo de tratamento.', 20),
  ('maquiagem',       'corretivo',              'Corretivo',                    'Corretivos e neutralizadores.', 30),
  ('maquiagem',       'po_facial',              'Pó facial',                    'Pós compactos e soltos de acabamento.', 40),
  ('maquiagem',       'primer',                 'Primer',                       'Preparadores de pele para maquiagem.', 50),
  ('maquiagem',       'fixador_maquiagem',      'Fixador de maquiagem',         'Sprays e brumas fixadoras.', 60),
  ('maquiagem',       'blush',                  'Blush',                        'Blushes em pó, creme, líquido ou stick.', 70),
  ('maquiagem',       'bronzer_contorno',       'Bronzer e contorno',           'Bronzers e produtos de contorno.', 80),
  ('maquiagem',       'iluminador',             'Iluminador',                   'Iluminadores faciais.', 90),
  ('maquiagem',       'multifuncional_rosto',   'Multifuncional',               'Produto declarado para mais de uma área (bochechas, lábios, olhos).', 100),
  ('maquiagem',       'sombra',                 'Sombra',                       'Sombras e paletas.', 110),
  ('maquiagem',       'delineador',             'Delineador',                   'Delineadores e lápis de olho.', 120),
  ('maquiagem',       'mascara_cilios',         'Máscara de cílios',            'Máscaras para cílios.', 130),
  ('maquiagem',       'sobrancelha',            'Sobrancelha',                  'Géis, lápis, pomadas e pós para sobrancelha.', 140),
  ('maquiagem',       'batom',                  'Batom',                        'Batons cremosos, matte e líquidos.', 150),
  ('maquiagem',       'gloss',                  'Gloss',                        'Gloss e óleos labiais com cor.', 160),
  ('maquiagem',       'lip_tint',               'Lip tint',                     'Tintas labiais e balms com cor.', 170),
  ('maquiagem',       'lapis_labial',           'Lápis labial',                 'Contornos e lápis labiais.', 180),
  -- labios
  ('labios',          'balm_labial',            'Balm labial',                  'Balms e hidratantes labiais sem cor como apelo principal.', 10),
  ('labios',          'mascara_labial',         'Máscara labial',               'Máscaras labiais (inclusive overnight).', 20),
  ('labios',          'esfoliante_labial',      'Esfoliante labial',            'Esfoliantes para lábios.', 30),
  ('labios',          'tratamento_labial',      'Tratamento labial',            'Volumizadores, óleos e séruns labiais de tratamento.', 40),
  -- corpo
  ('corpo',           'hidratante_corporal',    'Hidratante corporal',          'Loções, cremes, manteigas e géis corporais.', 10),
  ('corpo',           'oleo_corporal',          'Óleo corporal',                'Óleos corporais.', 20),
  ('corpo',           'sabonete_corporal',      'Sabonete corporal',            'Sabonetes líquidos, em barra e óleos de banho.', 30),
  ('corpo',           'esfoliante_corporal',    'Esfoliante corporal',          'Esfoliantes físicos e químicos para corpo.', 40),
  ('corpo',           'tratamento_corporal',    'Tratamento corporal',          'Firmeza, celulite, estrias, manchas e acne corporais.', 50),
  ('corpo',           'maos_pes',               'Mãos e pés',                   'Cremes e tratamentos para mãos, pés e cutículas.', 60),
  ('corpo',           'desodorante',            'Desodorante e antitranspirante','Desodorantes e antitranspirantes.', 70),
  ('corpo',           'autobronzeador',         'Autobronzeador',               'Autobronzeadores e bronzeamento sem sol.', 80),
  ('corpo',           'iluminador_corporal',    'Iluminador corporal',          'Óleos/géis com brilho e maquiagem corporal.', 90),
  -- cabelos
  ('cabelos',         'shampoo',                'Shampoo',                      'Shampoos líquidos e sólidos.', 10),
  ('cabelos',         'condicionador',          'Condicionador',                'Condicionadores e co-wash.', 20),
  ('cabelos',         'mascara_capilar',        'Máscara capilar',              'Máscaras e tratamentos de enxágue.', 30),
  ('cabelos',         'leave_in_finalizador',   'Leave-in e finalizador',       'Leave-ins, cremes de pentear, finalizadores.', 40),
  ('cabelos',         'oleo_capilar',           'Óleo capilar',                 'Óleos e séruns capilares.', 50),
  ('cabelos',         'couro_cabeludo',         'Couro cabeludo',               'Tônicos e tratamentos de couro cabeludo.', 60),
  -- fragrancias
  ('fragrancias',     'perfume',                'Perfume',                      'Extrait, EDP, EDT e colônias.', 10),
  ('fragrancias',     'body_splash_mist',       'Body splash e mist',           'Body splash, body mist e hair mist.', 20),
  -- dispositivos_acessorios
  ('dispositivos_acessorios', 'dispositivo_eletronico', 'Dispositivo eletrônico', 'LED, microcorrente, radiofrequência, limpeza sônica.', 10),
  ('dispositivos_acessorios', 'ferramenta_aplicacao',   'Ferramenta de aplicação','Esponjas, pincéis, gua sha, rolos.', 20)
) as v(category_code, code, name_pt, description, sort_order)
join core.category c on c.code = v.category_code
on conflict (code) do nothing;
