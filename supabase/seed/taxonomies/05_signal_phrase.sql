-- =============================================================================
-- NEXA LAB — F0-03 — Frases-sinal (SPEC §6.2)
-- Bloco 1: frases da SPEC. Bloco 2: proposta NEXA para validação (notes).
-- suggested_voice_type é heurística de pré-classificação; a classificação final
-- é feita pelo classificador com schema validado e revisão humana.
-- =============================================================================

insert into core.signal_phrase (phrase_pattern, match_type, suggested_voice_type_id, origin, notes)
select v.phrase, 'contains', vt.id, 'seed', v.notes
from (values
  -- Bloco 1 — SPEC §6.2
  ('eu queria que',        'desejo',              'SPEC §6.2'),
  ('odeio quando',         'frustracao',          'SPEC §6.2'),
  ('não consigo usar',     'necessidade_dor',     'SPEC §6.2'),
  ('seria perfeito se',    'pedido_explicito',    'SPEC §6.2'),
  ('abandonei porque',     'abandono',            'SPEC §6.2'),
  ('é trabalhoso',         'praticidade',         'SPEC §6.2'),
  ('não funciona em mim',  'eficacia_percebida',  'SPEC §6.2'),
  -- Bloco 2 — proposta NEXA (validar)
  ('queria muito um',      'pedido_explicito',    'Proposta NEXA v0.1'),
  ('não existe um',        'pedido_explicito',    'Proposta NEXA v0.1'),
  ('parei de usar',        'abandono',            'Proposta NEXA v0.1'),
  ('já é o meu terceiro',  'recompra',            'Proposta NEXA v0.1'),
  ('comprei de novo',      'recompra',            'Proposta NEXA v0.1'),
  ('tenho medo de',        'medo_risco',          'Proposta NEXA v0.1'),
  ('me deu alergia',       'medo_risco',          'Proposta NEXA v0.1'),
  ('misturo com',          'solucao_improvisada', 'Proposta NEXA v0.1'),
  ('dei um jeito',         'solucao_improvisada', 'Proposta NEXA v0.1'),
  ('melhor que o',         'comparacao',          'Proposta NEXA v0.1'),
  ('dupe',                 'comparacao',          'Proposta NEXA v0.1'),
  ('caro demais',          'preco_valor',         'Proposta NEXA v0.1'),
  ('vale cada centavo',    'preco_valor',         'Proposta NEXA v0.1'),
  ('vazou na bolsa',       'embalagem',           'Proposta NEXA v0.1'),
  ('não tem meu tom',      'inclusao',            'Proposta NEXA v0.1')
) as v(phrase, voice_code, notes)
join core.voice_type vt on vt.code = v.voice_code
on conflict (phrase_pattern, language) do nothing;
