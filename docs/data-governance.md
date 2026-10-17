# NEXA LAB — Política de retenção, backup e acesso

> **F0-09** · Versão 0.1 (proposta) · 17/10/2026 · Responsável técnico: Iago
> Status: **proposta para aprovação**. Itens marcados como **[DECIDIR]** dependem de definição de Iago antes da implementação.
> Base normativa: SPEC §0 (G-02, G-04, G-09, G-10, C-04, A-06, A-07), `docs/architecture.md` (DC-13, DC-14, DEC-10).
> Fora de escopo: titularidade de dados, código e credenciais entre as partes (SPEC §2, nota de governança).

---

## 1. Princípios

| # | Princípio | Origem |
|---|---|---|
| P1 | Toda evidência referenciada por um dado do `core` permanece abrível enquanto o dado existir. | G-02 |
| P2 | Histórico não é sobrescrito nem apagado; correção gera nova versão ou registro em `ops.human_review`. | G-04, G-10 |
| P3 | Retenção mínima necessária para dados de consumidor: só texto público, autor como hash, sem perfil individual. | C-04, SPEC §1 |
| P4 | Termos de uso de cada fonte prevalecem sobre a retenção padrão desta política. | C-01 |
| P5 | Logs operacionais têm retenção limitada; o que precisa durar vira agregado (`ops.coverage_report`, `ops.cost_ledger`). | G-09, A-06 |
| P6 | Acesso por menor privilégio; `service_role` nunca sai de ambiente servidor. | DC-13 |

---

## 2. Classificação dos dados

| Classe | Conteúdo | Tabelas / locais | Sensibilidade |
|---|---|---|---|
| C1 — Público coletado | Páginas de produto, preços, INCI, claims, JSON-LD | `raw.raw_document`, Storage `raw/`, `core.evidence`, `core.product*`, `core.price_observation` | Baixa (dado público), mas sujeita aos termos da fonte |
| C2 — Voz do consumidor | Comentários e avaliações públicas, autor em hash | `core.consumer_signal`, `core.signal_classification` | Média: pode conter dado pessoal no texto livre |
| C3 — Inteligência derivada | Classificações, índices, pareceres do Conselho, fichas | `core.*` inferido, `analytics`, `council` | Confidencial (ativo do projeto) |
| C4 — Financeiro | Planilha-base, premissas, cenários | `finance`, Storage `finance/` | Confidencial |
| C5 — Operacional | Fila, logs de coleta, custos, revisões humanas | `ops.*` | Interna |
| C6 — Segredos | Chaves de API, `service_role`, `AUTHOR_HASH_SECRET` | Gerenciador de segredos (nunca no repositório) | Restrita |

---

## 3. Retenção

### 3.1 Tabela de retenção (padrão, quando a fonte não impõe regra mais restritiva)

| Dado | Retenção proposta | Ação ao vencer | Justificativa |
|---|---|---|---|
| `raw.raw_document` (metadados) | Indefinida | — | Base de auditoria; linha pequena |
| Arquivo bruto no Storage **referenciado** por `core.evidence` | Enquanto houver evidência ativa | — | P1 (G-02) |
| Arquivo bruto **não referenciado** e já substituído por versão mais nova da mesma URL | 12 meses **[DECIDIR]** | Excluir o arquivo do Storage; manter a linha com `storage_path` marcado como expurgado | Custo de armazenamento sem perda de rastreabilidade |
| `core.evidence` | Indefinida | — | P1 |
| Entidades e versões (`brand*`, `product*`, `packaging*`, `price_observation`) | Indefinida | — | P2 (G-04); série histórica é o ativo |
| `core.consumer_signal` / `signal_classification` | Ver §3.2 (depende da fonte) | Expurgo ou anonimização | P3, P4 |
| `core.trend_series` | Indefinida | — | Série relativa, sem dado pessoal |
| `ops.crawl_log` | 18 meses | Excluir após consolidar em `ops.coverage_report` | P5 |
| `ops.job_queue` (concluídos/mortos) | 90 dias | Excluir | P5 |
| `ops.crawl_run`, `ops.coverage_report` | Indefinida | — | Cobertura histórica (AC-09) |
| `ops.cost_ledger` | Indefinida | — | Custo por execução (A-06, AC-10) |
| `ops.human_review` | Indefinida | — | Trilha de auditoria (G-10, AC-15) |
| `council.*`, `finance.*` | Indefinida | — | Decisões versionadas (AC-11, AC-13) |

### 3.2 Voz do consumidor — regras por fonte (DEC-08)

| Fonte | Regra de retenção | Status |
|---|---|---|
| **YouTube Data API** | As políticas de desenvolvedor do YouTube exigem que dados obtidos pela API sejam atualizados ou excluídos em até 30 dias, com exceções descritas de forma divergente pelas fontes consultadas. Isso conflita com manter texto de comentário como evidência histórica. | **[DECIDIR] antes do F1-07** — ver §3.3 |
| **Mercado Livre API** | Termos de retenção não levantados. | **[DECIDIR]** após leitura dos termos da API |
| **Avaliações JSON-LD em sites oficiais** | Seguem os termos de cada site (revisão F0-07). | Pendente F0-07 |
| **Google Trends (exportação manual)** | Sem dado pessoal; série relativa. | Retenção indefinida |

### 3.3 Opções para o conflito do YouTube

| Opção | Como funciona | Efeito no NEXA |
|---|---|---|
| A — Ciclo de atualização | Job recoleta, em até 30 dias, cada comentário armazenado; comentários removidos na origem são excluídos do banco | Evidência fica abrível enquanto existir na origem; custo de cota da API proporcional ao volume armazenado |
| B — Retenção curta + agregado | Texto e IDs excluídos após 30 dias; permanecem apenas contagens agregadas por tema/necessidade, sem texto | Perde-se a citação literal de sinais antigos (G-02 fica limitado ao período de 30 dias) |
| C — Confirmação formal | Consultar os termos vigentes e, se necessário, o suporte de API do YouTube para confirmar o que pode ser mantido além de 30 dias | Decisão definitiva antes de coletar em escala |

Recomendação: **C antes do F1-07**, operando em **A** no MVP até a confirmação.

### 3.4 Pedido de exclusão de dado pessoal (LGPD)

Comentários públicos podem conter nome, @ ou outro dado de terceiro no texto livre.

1. Pedido recebido (titular ou plataforma) → registro em `ops.human_review` com `field = 'original_text'` e motivo.
2. Redação do texto em `core.consumer_signal` para `[removido a pedido]`, mantendo o hash e a classificação agregada.
3. Arquivo bruto correspondente no Storage excluído.

`core.consumer_signal` é imutável por trigger; a redação exige uma função privilegiada dedicada (`ops.redact_consumer_signal`), a criar em migration na Fase 1 **[DECIDIR] prazo de atendimento: proposta de 15 dias**.

---

## 4. Backup e recuperação

### 4.1 Cobertura

| Ativo | Mecanismo | Observação |
|---|---|---|
| Banco Postgres (Supabase) | Backup diário gerenciado do Supabase. Pro: últimos 7 dias; Team: 14 dias; Enterprise: até 30 dias | Plano do projeto **[DECIDIR]** (depende de Q-18) |
| Banco — recuperação a um ponto no tempo (PITR) | Add-on pago do Supabase; ao ativar, substitui os backups diários | Recomendado a partir da Fase 2 (coleta agendada); preço a confirmar no painel |
| Storage (HTML/JSON bruto, planilhas) | **Não** incluído no backup do banco. Exportação semanal para bucket em outro provedor (ex.: Cloud Storage do projeto GCP do worker, DEC-10) | Sem isso, arquivo excluído no Storage é irrecuperável e a evidência perde o original |
| Código, migrations, seeds, prompts, configuração | Repositório Git (GitHub) | Já versionado |
| Dump lógico mensal (`pg_dump`) | Job agendado para o mesmo bucket externo | Independe do provedor do banco; retenção de 12 dumps **[DECIDIR]** |
| Segredos | Gerenciador de segredos do provedor do worker | Não entram em backup de dados; reemissão documentada em runbook |

### 4.2 Metas propostas

| Indicador | Meta MVP (Fase 1) | Meta Fase 2+ |
|---|---|---|
| RPO (perda máxima de dados) | 24 h | ≤ 15 min (com PITR) |
| RTO (tempo para restabelecer) | 8 h | 4 h |
| Teste de restauração | 1 por fase, em projeto Supabase separado | Trimestral |

O teste de restauração valida: contagem de linhas por tabela, abertura de 10 evidências aleatórias (excerpt + arquivo no Storage) e reprodução do relatório de cobertura.

---

## 5. Controle de acesso

### 5.1 Papéis

| Papel | Quem | Acesso | Status |
|---|---|---|---|
| `service_role` | Worker (Cloud Run Jobs), backend do Next.js (somente servidor), scripts de migração | Total; ignora RLS | Implementado (DC-13) |
| Administrador | Iago | Painéis Supabase, GCP, GitHub, provedores LLM; aprovação de fontes (F0-07) | A configurar |
| Product owner | Thaís | Leitura de todo o BI; correção de classificação via `ops.human_review` (writeback); sem acesso a `finance` **[DECIDIR]** e a segredos | A configurar (policies RLS) |
| Outros usuários | — | — | **Q-19 em aberto** |
| `anon` | Navegador sem login | Nenhum | Implementado (revoke + RLS) |

### 5.2 Regras

| # | Regra |
|---|---|
| R1 | Todas as tabelas com RLS habilitado; acesso de usuário só por policy explícita por papel. |
| R2 | `SUPABASE_SERVICE_ROLE_KEY` apenas em variáveis de servidor (worker e rotas server-side do Next.js); proibido em código cliente ou no repositório. |
| R3 | MFA obrigatório nas contas Supabase, GitHub, GCP e provedores de LLM. |
| R4 | Rotação de chaves de API a cada 90 dias e imediatamente após saída de pessoa com acesso. |
| R5 | `AUTHOR_HASH_SECRET` não é rotacionado em operação normal (rotacionar quebra a deduplicação de autores); rotação só em incidente, com reprocessamento dos hashes. |
| R6 | Repositório privado; GitHub Actions apenas para CI, sem segredos de produção de coleta (DC-17). |
| R7 | Revisão semestral de acessos: lista de usuários, papéis e chaves ativas. |
| R8 | Exportações do BI (CSV/XLSX) não incluem `author_hash` nem texto integral de sinais; citações aparecem truncadas com link para a evidência. |

---

## 6. Implementação (backlog técnico)

| ID | Item | Fase | Depende de |
|---|---|---|---|
| GOV-01 | Job de expurgo: `ops.job_queue` (90 d) e `ops.crawl_log` (18 m, após consolidação) | 1 | Aprovação desta política |
| GOV-02 | Coluna e job de expurgo de arquivos brutos não referenciados no Storage | 2 | §3.1 [DECIDIR] |
| GOV-03 | Função `ops.redact_consumer_signal` + procedimento LGPD | 1 | §3.4 |
| GOV-04 | Ciclo de atualização de 30 dias para dados do YouTube | 1 (antes do F1-07) | §3.3 |
| GOV-05 | Exportação semanal do Storage e `pg_dump` mensal para bucket externo | 1 | DEC-10 (GCP) |
| GOV-06 | Policies RLS para administrador e product owner | 1 (F1-09/F1-10) | Q-19 |
| GOV-07 | Runbook de restauração e primeiro teste | 1 | GOV-05 |

---

## 7. Decisões solicitadas

| # | Decisão | Proposta |
|---|---|---|
| D1 | Retenção de arquivos brutos não referenciados | 12 meses |
| D2 | Tratamento dos dados do YouTube | Opção C (confirmar termos) operando em A no MVP |
| D3 | Prazo de atendimento a pedido de exclusão | 15 dias |
| D4 | Plano Supabase e PITR | Pro no MVP; PITR a partir da Fase 2 (depende de Q-18) |
| D5 | Retenção de dumps mensais | 12 dumps |
| D6 | Acesso da Thaís ao schema `finance` | A definir por Iago |

---

## 8. Fontes consultadas

- [Supabase — Database Backups](https://supabase.com/docs/guides/platform/backups)
- [Supabase — Pricing](https://supabase.com/pricing)
- [YouTube API Services — Developer Policies](https://developers.google.com/youtube/terms/developer-policies)
- [YouTube — Complying with YouTube's Developer Policies](https://developers.google.com/youtube/terms/developer-policies-guide)
