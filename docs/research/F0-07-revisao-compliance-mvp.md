# F0-07 — Revisão de termos de uso e robots.txt das marcas do MVP

> Data: 17/10/2026 · Status: **ferramental pronto; execução bloqueada pela política de rede do ambiente de desenvolvimento.**
> Nenhum resultado de revisão foi registrado. Todas as 101 fontes seguem `access_method = pending_review`, `review_status = pending`, inativas.

---

## 1. Bloqueio atual

O ambiente cloud desta sessão recusa conexões de saída para os domínios das marcas (ex.: `meuollie.com.br`, `sallve.com.br`, `natura.com.br`). Sem acesso, não é possível ler `robots.txt`, identificar a plataforma nem localizar os termos de uso.

**Como liberar (uma das opções):**
- Ajustar *Network access* do ambiente cloud (menu do ambiente na barra de título da sessão → Edit) para um nível mais amplo, ou incluir os 23 domínios da seção 3 em *Allowed domains*. Passo a passo: <https://code.claude.com/docs/en/cloud-environments#network-access>.
- Ou executar `scripts/review_sources.py --mvp-candidates` em máquina local e versionar a saída em `docs/coverage-reports/f0-07/`.

---

## 2. Processo de revisão

| Etapa | Responsável | Ferramenta / artefato | Resultado no banco |
|---|---|---|---|
| 1. Leitura técnica: robots.txt, sitemaps, crawl-delay, plataforma, link dos termos | Automatizada | `scripts/review_sources.py` → `review.json`, `review.csv`, `robots/<domínio>.txt` | `review_status = preliminary`, `robots_allowed`, `sitemap_urls`, `ecommerce_platform`, `rate_limit_rps` |
| 2. Leitura dos termos de uso com o checklist da seção 4 | Iago | `decisions.csv` (uma linha por fonte) | — |
| 3. Geração do registro | Automatizada | `scripts/gen_source_review_sql.py` → `supabase/seed/source_review.sql` | `review_status = approved/rejected`, `access_method`, `tos_url`, `tos_reviewed_at`, `tos_reviewed_by`, `tos_review_notes` |
| 4. Ativação | Iago | `update ops.source set active = true ...` | Constraint exige `approved` + revisão de termos + robots permitido (C-01) |

Garantias do ferramental:
- User-Agent identificável (`NexaLabBot/0.1`, configurável por `NEXA_USER_AGENT`), intervalo mínimo de 3 s por domínio, respeito ao `Crawl-delay` (C-05).
- 401/403/429/CAPTCHA são registrados como resultado, sem nova tentativa (C-02).
- A automação nunca marca `approved`: a decisão sobre os termos é humana (G-10).
- Testes offline: `python3 -m unittest discover -s tests/python` (13 testes).

---

## 3. Candidatos ao MVP (F1-01 — validar com a Thaís)

Critério da SPEC (F1-01): P1-A + P1 nacionais, mesclando plataformas de e-commerce. São 23 candidatos com site brasileiro; a seleção final de **20** sai do resultado da revisão:

1. excluir fontes com `access_method = blocked` (robots ou termos);
2. garantir pelo menos 3 plataformas de e-commerce distintas entre as 20;
3. manter Ollie (P1-A) e marcas com presença relevante em proteção solar facial (categoria piloto DC-19);
4. em empate, priorizar marcas nativas digitais brasileiras (foco NEXA) sobre marcas de grupos multinacionais com site regional.

| # | Marca | Site | Proteção solar facial no portfólio* |
|---|---|---|---|
| 1 | Ollie (P1-A) | meuollie.com.br | A verificar na coleta |
| 2 | AURA Beauty | aurabeautyclub.com.br | A verificar |
| 3 | Olera | olera.com.br | A verificar |
| 4 | ADCOS | lojaadcos.com.br | A verificar |
| 5 | Boca Rosa | bocarosa.com.br | A verificar |
| 6 | Beyoung | beyoung.com.br | A verificar |
| 7 | Sallve | sallve.com.br | A verificar |
| 8 | Creamy | creamy.com.br | A verificar |
| 9 | Principia | principiaskin.com | A verificar |
| 10 | Simple Organic | simpleorganic.com.br | A verificar |
| 11 | Quintal Dermocosméticos | quintaldermocosmeticos.com.br | A verificar |
| 12 | CARE Natural Beauty | carenb.com | A verificar |
| 13 | Pink Cheeks | pinkcheeks.com.br | A verificar |
| 14 | Océane | oceane.com.br | A verificar |
| 15 | Bruna Tavares | linhabrunatavares.com | A verificar |
| 16 | Mantecorp Skincare | mantecorpskincare.com.br | A verificar |
| 17 | Natura | natura.com.br | A verificar |
| 18 | O Boticário | boticario.com.br | A verificar |
| 19 | La Roche-Posay | laroche-posay.com.br | A verificar |
| 20 | SkinCeuticals | skinceuticals.com.br | A verificar |
| 21 | CeraVe | cerave.com.br | A verificar |
| 22 | ISDIN | isdin.com/pt-BR | A verificar |
| 23 | Mustela | mustela.com.br | A verificar |

\* Não preenchido de memória (G-03): será confirmado pela coleta.

---

## 4. Checklist de leitura dos termos de uso (etapa 2)

Registrar em `decisions.csv` → `tos_findings` o trecho relevante e a conclusão.

| # | Pergunta | Se "sim" |
|---|---|---|
| T1 | Os termos proíbem expressamente robôs, scraping, crawlers ou "meios automatizados" de acesso? | `blocked` (ou `manual`, se coleta manual pontual for permitida) |
| T2 | Proíbem reprodução/armazenamento do conteúdo para fins comerciais? | Avaliar: armazenar apenas fatos (preço, INCI, claims) com evidência; se vedado, `blocked` |
| T3 | Exigem autorização prévia para uso de dados? | `blocked` até obter autorização formal |
| T4 | Há API, feed ou programa de parceiros oferecido pela marca/plataforma? | Preferir `api` (SPEC §5.1) |
| T5 | O site depende de JavaScript para exibir preço/produto e o robots/termos não vedam navegador automatizado? | `browser` (Playwright), só se T1 for "não" |
| T6 | Há limite de taxa, horário ou volume declarado? | Ajustar `rate_limit_rps` |
| T7 | Nenhuma vedação aplicável? | `crawler` |

Formato de `decisions.csv`:

```csv
master_list_no,tos_url,tos_findings,access_method,approved_by,approved_at
1,https://.../termos-de-uso,"Sem vedação a meios automatizados; cláusula 5 proíbe uso comercial do conteúdo editorial (não aplicável a fatos de produto)",crawler,Iago,2026-10-20
```

---

## 5. Pendências

| # | Pendência | Responsável |
|---|---|---|
| 1 | Liberar acesso de rede aos 23 domínios (ou rodar o script localmente) | Iago |
| 2 | Executar `review_sources.py --mvp-candidates` e versionar a saída | Claude Code, após item 1 |
| 3 | Leitura dos termos (checklist) e preenchimento de `decisions.csv` | Iago |
| 4 | Validação das 20 marcas do MVP | Thaís |
