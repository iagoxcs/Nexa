-- =============================================================================
-- NEXA LAB — F0-03 — Classificação de tendência (SPEC §8)
-- Critérios qualitativos. Limiares numéricos dependem dos pesos/normalização do
-- Índice de Tendência, a calibrar na Fase 1 com a Thaís (SPEC §8, Q-17).
-- =============================================================================

insert into core.trend_class (code, name_pt, description, sort_order) values
  ('sinal_fraco',      'Sinal fraco',
   'Menções esparsas, em poucas fontes, sem persistência demonstrada. Ação: monitorar e buscar confirmação cruzada.', 10),
  ('moda_passageira',  'Moda passageira',
   'Pico rápido concentrado em uma plataforma/creator, baixa diversidade de fontes e queda após o pico. Viralização sem persistência.', 20),
  ('em_formacao',      'Em formação',
   'Crescimento sustentado por múltiplos períodos e em 2 ou mais fontes independentes, ainda sem reflexo amplo na oferta.', 30),
  ('consolidada',      'Consolidada',
   'Interesse persistente em patamar estável e presença recorrente na oferta (lançamentos, claims) e na conversa do consumidor.', 40),
  ('macrotendencia',   'Macrotendência',
   'Movimento estrutural plurianual, multicategoria, sustentado por mudança de comportamento, tecnologia ou regulação.', 50)
on conflict (code) do nothing;
