-- =============================================================================
-- NEXA LAB — F0-03 — Taxonomia: benefício (PROPOSTA v0.1)
-- Benefício normalizado para filtro/agregação. A alegação literal fica em
-- core.claim; métricas (FPS, % de redução) ficam em product.spf_declared e
-- claim.metric_value. Um produto tem 1 benefício principal e N secundários.
-- =============================================================================

insert into core.benefit (code, name_pt, benefit_group, description, sort_order) values
  -- hidratacao_barreira
  ('hidratacao',              'Hidratação',                    'hidratacao_barreira',  'Aumento ou manutenção do conteúdo de água da pele/lábios/cabelo.', 10),
  ('nutricao',                'Nutrição/emoliência',           'hidratacao_barreira',  'Reposição lipídica, maciez, conforto de pele seca.', 20),
  ('reparacao_barreira',      'Reparação da barreira',         'hidratacao_barreira',  'Fortalecimento/restauração da barreira cutânea.', 30),
  ('calmante',                'Calmante/antivermelhidão',      'hidratacao_barreira',  'Alívio de sensibilidade, ardor, vermelhidão.', 40),
  -- protecao
  ('protecao_uvb',            'Proteção UVB (FPS)',            'protecao',             'Proteção contra UVB; valor em product.spf_declared.', 100),
  ('protecao_uva',            'Proteção UVA',                  'protecao',             'Proteção UVA declarada (PPD, FPUVA, selo UVA).', 110),
  ('protecao_luz_visivel',    'Proteção luz visível',          'protecao',             'Proteção contra luz visível/azul declarada.', 120),
  ('resistencia_agua_suor',   'Resistência à água/suor',       'protecao',             'Resistência à água ou ao suor declarada.', 130),
  ('antipoluicao',            'Antipoluição',                  'protecao',             'Proteção contra poluição/partículas declarada.', 140),
  ('antioxidante',            'Antioxidante',                  'protecao',             'Neutralização de radicais livres declarada.', 150),
  -- tratamento
  ('controle_oleosidade',     'Controle de oleosidade',        'tratamento',           'Redução de sebo/brilho.', 200),
  ('antiacne',                'Antiacne',                      'tratamento',           'Prevenção/tratamento de acne e cravos.', 210),
  ('uniformizacao_manchas',   'Uniformização/manchas',         'tratamento',           'Clareamento de manchas, melasma, tom irregular.', 220),
  ('antissinais',             'Antissinais',                   'tratamento',           'Rugas, linhas finas, sinais de envelhecimento.', 230),
  ('firmeza',                 'Firmeza/elasticidade',          'tratamento',           'Firmeza e elasticidade de rosto ou corpo.', 240),
  ('renovacao_celular',       'Renovação/esfoliação',          'tratamento',           'Renovação celular, esfoliação química ou física.', 250),
  ('reducao_poros',           'Redução de poros',              'tratamento',           'Aparência de poros.', 260),
  ('luminosidade',            'Luminosidade/viço',             'tratamento',           'Pele luminosa como resultado de tratamento (não pigmento).', 270),
  ('olheiras_bolsas',         'Olheiras/bolsas',               'tratamento',           'Olheiras, bolsas e linhas perioculares.', 280),
  ('celulite_estrias',        'Celulite/estrias',              'tratamento',           'Aparência de celulite e estrias.', 290),
  ('volume_labial',           'Volume labial',                 'tratamento',           'Efeito volumizador labial.', 300),
  ('desodorante',             'Desodorante/antitranspirante',  'tratamento',           'Controle de odor e/ou transpiração.', 310),
  -- limpeza
  ('limpeza',                 'Limpeza',                       'limpeza',              'Remoção de sujidades e oleosidade.', 400),
  ('demaquilagem',            'Demaquilagem',                  'limpeza',              'Remoção de maquiagem/fotoprotetor.', 410),
  -- maquiagem_acabamento
  ('cobertura',               'Cobertura/uniformização imediata','maquiagem_acabamento','Cobertura de imperfeições por pigmento.', 500),
  ('cor',                     'Cor',                           'maquiagem_acabamento', 'Pigmentação de lábios, bochechas, olhos.', 510),
  ('acabamento_matte',        'Acabamento matte',              'maquiagem_acabamento', 'Acabamento sem brilho declarado.', 520),
  ('acabamento_luminoso',     'Acabamento luminoso',           'maquiagem_acabamento', 'Brilho/glow por pigmento ou partículas.', 530),
  ('longa_duracao',           'Longa duração',                 'maquiagem_acabamento', 'Fixação/duração declarada.', 540),
  ('efeito_imediato',         'Efeito imediato',               'maquiagem_acabamento', 'Blur, lifting ou alisamento óptico imediato.', 550),
  ('bronzeado_sem_sol',       'Bronzeado sem sol',             'maquiagem_acabamento', 'Cor de bronzeado por DHA/pigmento.', 560),
  ('multifuncionalidade',     'Multifuncionalidade',           'maquiagem_acabamento', 'Uso declarado em várias áreas ou funções no mesmo produto.', 570),
  -- sensorial_bem_estar
  ('perfumacao',              'Perfumação',                    'sensorial_bem_estar',  'Fragrância como benefício declarado.', 600),
  ('sensorial_textura',       'Sensorial/textura',             'sensorial_bem_estar',  'Toque seco, não pegajoso, absorção rápida, textura declarada.', 610),
  ('refrescancia',            'Refrescância',                  'sensorial_bem_estar',  'Sensação de frescor/resfriamento.', 620),
  ('reaplicacao_pratica',     'Reaplicação prática',           'sensorial_bem_estar',  'Aplicação/reaplicação sem mãos, sobre maquiagem ou fora de casa.', 630),
  -- capilar
  ('reparacao_capilar',       'Reparação capilar',             'capilar',              'Reconstrução de fios danificados.', 700),
  ('antifrizz_definicao',     'Antifrizz/definição',           'capilar',              'Controle de frizz e definição de cachos.', 710),
  ('anticaspa',               'Anticaspa',                     'capilar',              'Controle de caspa/descamação do couro cabeludo.', 720),
  ('antiqueda_fortalecimento','Antiqueda/fortalecimento',      'capilar',              'Fortalecimento e redução de queda.', 730)
on conflict (code) do nothing;
