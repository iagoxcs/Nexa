-- =============================================================================
-- NEXA LAB — F0-03 — Taxonomia: voz do consumidor (SPEC §6.2)
-- Códigos definidos na SPEC; descrições e critérios propostos para validação.
-- Um sinal pode receber mais de um tipo (uma linha por tipo em signal_classification).
-- =============================================================================

insert into core.voice_type (code, name_pt, description, sort_order) values
  ('necessidade_dor',     'Necessidade/dor',        'Problema ou necessidade não resolvida relatada pelo consumidor ("minha pele fica oleosa às 11h").', 10),
  ('desejo',              'Desejo',                 'Algo que o consumidor gostaria de ter ou sentir, sem problema explícito ("eu queria um protetor que...").', 20),
  ('objecao',             'Objeção',                'Motivo declarado para não comprar ou não experimentar (preço, ingrediente, desconfiança).', 30),
  ('frustracao',          'Frustração',             'Experiência negativa com produto já usado, sem decisão explícita de abandono.', 40),
  ('elogio',              'Elogio',                 'Avaliação positiva explícita do produto/marca.', 50),
  ('abandono',            'Abandono',               'Relato de que deixou de usar ou não recompraria, com ou sem motivo.', 60),
  ('recompra',            'Recompra',               'Relato de recompra, uso contínuo ou fidelidade ("já é meu terceiro").', 70),
  ('pedido_explicito',    'Pedido explícito',       'Solicitação direta de produto, versão, tom, tamanho ou formato inexistente.', 80),
  ('solucao_improvisada', 'Solução improvisada',    'Gambiarra/combinação criada pelo consumidor para resolver uma necessidade (sinal de white space).', 90),
  ('comparacao',          'Comparação',             'Comparação entre produtos/marcas, inclusive "dupe".', 100),
  ('medo_risco',          'Medo/risco',             'Receio de reação, efeito colateral, segurança ou ingrediente.', 110),
  ('sensorial',           'Sensorial',              'Comentário sobre textura, cheiro, toque, acabamento, absorção.', 120),
  ('embalagem',           'Embalagem',              'Comentário sobre embalagem, dispensação, vazamento, portabilidade.', 130),
  ('preco_valor',         'Preço/valor',            'Percepção de preço, custo-benefício, rendimento.', 140),
  ('eficacia_percebida',  'Eficácia percebida',     'Resultado percebido pelo consumidor (funciona/não funciona). Não é evidência científica (G-06).', 150),
  ('confianca',           'Confiança',              'Credibilidade da marca, transparência, autoridade, recomendação profissional.', 160),
  ('sustentabilidade',    'Sustentabilidade',       'Refil, ingredientes, embalagem, impacto ambiental, testes em animais.', 170),
  ('praticidade',         'Praticidade',            'Facilidade, tempo, reaplicação, rotina simplificada ou trabalhosa.', 180),
  ('inclusao',            'Inclusão',               'Tons de pele, tipos de pele/cabelo, acessibilidade, representatividade.', 190),
  ('estetica_desejo',     'Estética/desejo',        'Apelo visual do produto/embalagem, "instagramável", colecionável.', 200)
on conflict (code) do nothing;
