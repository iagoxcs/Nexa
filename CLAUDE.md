# CLAUDE.md — NEXA LAB

Especificação completa: `docs/SPEC.md`. Ler integralmente antes de qualquer tarefa.

Dicionário de dados: `docs/data-dictionary.md` (gerado por `scripts/gen_data_dictionary.py`; não editar à mão).

## 0. Regras permanentes para o Claude Code

Estas regras valem para **todo** código, prompt, migração e tela gerados neste repositório. Nenhuma tarefa justifica violá-las.

### 0.1 Regras de dados (guardrails)

| ID | Regra |
|---|---|
| G-01 | **Nunca apresentar inferência como fato.** Todo campo inferido carrega `is_inferred = true` + `confidence` (0–1) + `evidence_id`. |
| G-02 | Todo dado relevante preserva **fonte, URL, data/hora de coleta e evidência textual**. A evidência deve ser abrível a partir do BI. |
| G-03 | **Proibido inventar** INCI, concentração, preço, avaliação, público, patente, fornecedor ou alegação. Ausência = `NULL` + motivo em `missing_reason`. |
| G-04 | Deduplicar produtos e variantes; alterações geram nova versão (histórico), nunca sobrescrita. |
| G-05 | Preço cheio ≠ preço promocional. Preço unitário (por ml/g) só é calculado quando volume/peso tiverem `confidence ≥ 0.9`. |
| G-06 | Avaliação de consumidor ≠ evidência científica. Tabelas e telas separadas. |
| G-07 | Seguidores, curtidas, buscas e tráfego **não** são proxy de tamanho de mercado nem de vendas. |
| G-08 | Não inferir geração/idade por estética. Apenas dado declarado, audiência disponível ou hipótese rotulada. |
| G-09 | Logs obrigatórios: erros, sites bloqueados, campos ausentes, cobertura real. **"Não coletado" ≠ "não existe".** |
| G-10 | Toda correção humana é registrada (quem, quando, valor anterior, motivo) e retroalimenta regras/prompts. |
| G-11 | Market share **observado**, **estimado** e **indisponível** são estados distintos. Estimativa nunca é rotulada como market share confirmado. |
| G-12 | Projeções financeiras são calculadas por **código determinístico**, nunca por texto livre do LLM. |

### 0.2 Regras de compliance

| ID | Regra |
|---|---|
| C-01 | Respeitar termos de uso, `robots.txt`, rate limits e políticas de cada plataforma. |
| C-02 | **Não burlar** CAPTCHA, login, paywall, bloqueio técnico ou anti-bot. Bloqueio = registrar em `crawl_log` com status `blocked` e seguir. |
| C-03 | Plataformas fechadas (TikTok, Instagram, Facebook): somente API oficial, exportação autorizada ou provedor licenciado. |
| C-04 | Não armazenar dados pessoais desnecessários. Identificadores de consumidores são hasheados (`author_hash`) e anonimizados no BI. |
| C-05 | User-agent identificável, backoff exponencial, limite de requisições por domínio configurável. |

### 0.3 Regras de arquitetura

| ID | Regra |
|---|---|
| A-01 | **Banco, coletores, ETL e BI são independentes do modelo de IA.** LLM é camada de interpretação, nunca o banco. |
| A-02 | Toda chamada a LLM passa pela camada `llm_gateway` (adapter por provedor: OpenAI, Anthropic, Google). Proibido importar SDK de provedor fora dela. |
| A-03 | Prompts versionados em arquivo (`/prompts/*.md`), com `prompt_version` gravado em cada saída gerada. |
| A-04 | Saídas de LLM para extração/classificação usam **JSON com schema validado** (Pydantic/Zod). Saída inválida = retry limitado + log, nunca gravação parcial. |
| A-05 | Toda resposta do Conselho cita os `record_id`/`evidence_id` que a sustentam. Resposta sem citação é rejeitada pela validação. |
| A-06 | Custos de tokens, navegador e coleta são registrados por execução (`cost_ledger`). |
| A-07 | Single-tenant. Sem lógica multi-tenant. |

---

## Convenções do repositório

- Migrations em `supabase/migrations/`, nomeadas `YYYYMMDDHHMMSS_<descricao>.sql`. Nunca editar migration já aplicada; criar nova.
- Atributos sujeitos a extração/inferência são criados com `ops.add_traceable_field(...)` (padrão §4.1 + `missing_reason` de G-03). Não criar essas colunas manualmente.
- Taxonomias em `supabase/seed/taxonomies/*.sql`, idempotentes (`on conflict do nothing`). Alterar código (`code`) de taxonomia exige migration de remapeamento.
- Após alterar migrations: `scripts/validate_migrations.sh` e `python3 scripts/gen_data_dictionary.py`.
