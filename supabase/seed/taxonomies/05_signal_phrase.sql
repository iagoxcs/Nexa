-- =============================================================================
-- NEXA LAB — F0-03 — Frases-sinal (SPEC §6.2)
-- Bloco 1: frases da SPEC. Bloco 2: frases NEXA v1.0 (validadas em 16/10/2026).
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
  -- Bloco 2 — NEXA v1.0, validado por Iago em 16/10/2026
  ('queria muito um',      'pedido_explicito',    'NEXA v1.0 (validada 16/10/2026)'),
  ('não existe um',        'pedido_explicito',    'NEXA v1.0 (validada 16/10/2026)'),
  ('parei de usar',        'abandono',            'NEXA v1.0 (validada 16/10/2026)'),
  ('já é o meu terceiro',  'recompra',            'NEXA v1.0 (validada 16/10/2026)'),
  ('comprei de novo',      'recompra',            'NEXA v1.0 (validada 16/10/2026)'),
  ('tenho medo de',        'medo_risco',          'NEXA v1.0 (validada 16/10/2026)'),
  ('me deu alergia',       'medo_risco',          'NEXA v1.0 (validada 16/10/2026)'),
  ('misturo com',          'solucao_improvisada', 'NEXA v1.0 (validada 16/10/2026)'),
  ('dei um jeito',         'solucao_improvisada', 'NEXA v1.0 (validada 16/10/2026)'),
  ('melhor que o',         'comparacao',          'NEXA v1.0 (validada 16/10/2026)'),
  ('dupe',                 'comparacao',          'NEXA v1.0 (validada 16/10/2026)'),
  ('caro demais',          'preco_valor',         'NEXA v1.0 (validada 16/10/2026)'),
  ('vale cada centavo',    'preco_valor',         'NEXA v1.0 (validada 16/10/2026)'),
  ('vazou na bolsa',       'embalagem',           'NEXA v1.0 (validada 16/10/2026)'),
  ('não tem meu tom',      'inclusao',            'NEXA v1.0 (validada 16/10/2026)')
) as v(phrase, voice_code, notes)
join core.voice_type vt on vt.code = v.voice_code
on conflict (phrase_pattern, language) do nothing;
