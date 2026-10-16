-- =============================================================================
-- NEXA LAB — F0-03 — Taxonomia: formato (PROPOSTA v0.1)
-- Formato = forma física/veículo do produto. Embalagem e mecanismo de
-- dispensação (pump, airless, roll-on, conta-gotas) ficam em core.packaging.
-- Exceção deliberada: stick e bala são forma física (anidro moldado) e também
-- sugerem embalagem; a classificação aqui descreve o produto, não o recipiente.
-- =============================================================================

insert into core.format (code, name_pt, format_group, description, sort_order) values
  -- liquido
  ('liquido_aquoso',   'Líquido aquoso',     'liquido',      'Tônicos, águas micelares, essências, tintas labiais à base de água.', 10),
  ('serum',            'Sérum',              'liquido',      'Líquido de baixa viscosidade concentrado em ativos (aquoso ou emulsionado leve).', 20),
  ('oleo',             'Óleo',               'liquido',      'Veículo oleoso líquido.', 30),
  ('bifasico',         'Bifásico',           'liquido',      'Duas fases que se separam em repouso; agitar antes do uso.', 40),
  ('espuma',           'Espuma/mousse',      'liquido',      'Espuma formada por pump ou válvula. Espuma em lata pressurizada → aerossol.', 50),
  ('spray_nao_aerossol','Spray/bruma',       'liquido',      'Líquido dispensado em névoa por válvula mecânica, sem propelente.', 60),
  -- emulsao
  ('creme',            'Creme',              'emulsao',      'Emulsão de média a alta viscosidade.', 100),
  ('locao',            'Loção/leite',        'emulsao',      'Emulsão fluida espalhável.', 110),
  ('fluido',           'Fluido',             'emulsao',      'Emulsão muito leve, típica de fotoprotetor facial e base.', 120),
  ('gel_creme',        'Gel-creme',          'emulsao',      'Emulsão com polímero gelificante, toque leve.', 130),
  ('pasta',            'Pasta',              'emulsao',      'Dispersão densa de sólidos (argila, óxidos).', 140),
  -- gel
  ('gel',              'Gel',                'gel',          'Gel aquoso transparente ou translúcido.', 200),
  ('jelly',            'Jelly/gelatina',     'gel',          'Gel elástico de alta coesão.', 210),
  ('gel_oleo',         'Gel-óleo',           'gel',          'Óleo gelificado.', 220),
  -- anidro
  ('balm',             'Balm/bálsamo',       'anidro',       'Anidro semissólido de espalhar com os dedos (inclusive balm-to-oil).', 300),
  ('stick',            'Stick/bastão',       'anidro',       'Anidro moldado de aplicação direta na pele, em embalagem giratória ou push-up.', 310),
  ('bala',             'Bala (batom)',       'anidro',       'Anidro moldado em formato de batom clássico.', 320),
  ('lapis',            'Lápis',              'anidro',       'Mina em lápis de madeira ou retrátil.', 330),
  -- solido
  ('barra',            'Barra sólida',       'solido',       'Sabonete, shampoo ou hidratante em barra.', 400),
  ('capsula',          'Cápsula monodose',   'solido',       'Dose única encapsulada (biodegradável ou gelatinosa).', 410),
  -- po
  ('po_compacto',      'Pó compacto',        'po',           'Pó prensado.', 500),
  ('po_solto',         'Pó solto',           'po',           'Pó não prensado, inclusive pó-para-espuma.', 510),
  -- pressurizado
  ('aerossol',         'Aerossol',           'pressurizado', 'Produto com propelente (spray ou espuma em lata).', 600),
  -- suporte
  ('mascara_tecido',   'Máscara de tecido',  'suporte',      'Tecido/biocelulose impregnado.', 700),
  ('patch',            'Patch',              'suporte',      'Adesivo hidrocoloide, hidrogel ou microagulhas.', 710),
  ('lenco',            'Lenço umedecido',    'suporte',      'Lenço impregnado.', 720),
  ('cushion',          'Cushion',            'suporte',      'Esponja impregnada em estojo compacto.', 730),
  -- dispositivo
  ('dispositivo',      'Dispositivo',        'dispositivo',  'Aparelho eletrônico ou ferramenta (sem fórmula).', 800)
on conflict (code) do nothing;
