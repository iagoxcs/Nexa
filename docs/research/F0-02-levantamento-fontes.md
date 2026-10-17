# F0-02 — Levantamento: fontes sociais (DEC-08), market share (DEC-09) e hospedagem do worker (DEC-10)

> Data do levantamento: 16/10/2026 · Status: **opções apresentadas, aguardando confirmação de Iago. Nada implementado.**
>
> **Grau de confiança das informações:** termos e preços de plataformas mudam com frequência e vários fornecedores não publicam preço. Cada item indica a qualidade da fonte:
> **[O]** documentação oficial · **[S]** fonte secundária (blog, imprensa, comparativo de concorrente) · **[C]** depende de cotação comercial.
> Antes de contratar ou desenvolver, confirmar os termos vigentes direto com o fornecedor.

---

## 1. DEC-08 — Fontes de voz do consumidor

### 1.1 Viabilidade por plataforma

| Plataforma | Acesso oficial para uso comercial | Cobertura útil para o NEXA | Custo | Compliance (C-01/C-03) | Viabilidade no MVP |
|---|---|---|---|---|---|
| **YouTube** | YouTube Data API v3 [O] | Vídeos de review, rotina e comparativo; comentários públicos | Gratuito dentro da cota padrão de 10.000 unidades/dia; `commentThreads.list` = 1 unidade, `search.list` = 100 unidades [O] | Conforme, via API oficial | **Alta** |
| **Mercado Livre** | API oficial, endpoint `GET /reviews/item/{id}` com nota, texto e data [O] | Avaliações de compradores, nota média e distribuição por estrela | Gratuito (requer app registrado e token) [O]; documentação atualizada em 2023, confirmar campos atuais | Conforme, via API oficial | **Alta** |
| **Avaliações nos sites das marcas / e-commerce** | JSON-LD `Review`/`AggregateRating` já coletado pelo crawler do Módulo A | Avaliações por SKU no site oficial | Sem custo adicional | Conforme, desde que a fonte esteja liberada na F0-07 | **Alta** |
| **Google Trends** | API oficial em **alpha fechada**, por candidatura, sem preço publicado [S]. Biblioteca não oficial `pytrends` arquivada em abr/2025 [S] | Interesse relativo por termo, região e período | Gratuito via exportação manual do site; API sem preço definido | Exportação manual pela interface é conforme; scraping não | **Média** (manual) |
| **Instagram** | Graph API: busca por hashtag limitada a 30 hashtags distintas por 7 dias, só posts recentes, exige conta profissional própria e App Review [O/S]. Não permite ler comentários de posts de terceiros encontrados por hashtag [O] | Volume e tipo de post por hashtag; sem comentários | Gratuito | Conforme dentro dos limites da API | **Baixa** (cobertura insuficiente) |
| **TikTok** | Research API restrita a pesquisa acadêmica/sem fins lucrativos; uso comercial **não elegível** [S]. Não há API comercial de conteúdo de terceiros disponível [S] | — | — | Só via provedor licenciado | **Não viável** sem provedor |
| **Facebook** | Meta Content Library restrita a instituições acadêmicas e sem fins lucrativos [O] | — | — | Só via provedor licenciado | **Não viável** sem provedor |
| **Reddit** | Uso comercial exige contrato com a Reddit; cadastro self-service fechado; aprovação de 2 a 4 semanas [S]. Preços divergentes nas fontes (US$ 0,24 por 1.000 chamadas, com piso entre US$ 12 mil/ano e US$ 12 mil/mês) [S] | Baixa relevância para consumidor brasileiro de dermocosméticos | Alto e incerto [C] | Conforme apenas com contrato | **Baixa** (custo × relevância) |
| **Reclame Aqui** | Sem API pública identificada | Reclamações pós-compra | — | Não coletar sem autorização formal | **Não viável** sem acordo |

### 1.2 Provedores licenciados (TikTok, Instagram, Facebook)

Atendem C-03 **somente se** o provedor tiver acesso licenciado/oficial às plataformas. Nenhum dos levantados publica preço [C].

| Provedor | Observação levantada | Ponto a confirmar na cotação |
|---|---|---|
| Stilingue (Blip) | Foco em português brasileiro; fontes citadas: X, Instagram, Facebook, YouTube, LinkedIn, Threads. TikTok não aparece na lista [S] | Cobertura de TikTok; exportação dos textos brutos com URL e data (G-02) |
| YouScan | Preço sob consulta; um comparativo cita a partir de US$ 299/mês, não confirmado [S] | Licença das fontes; exportação via API |
| Brandwatch | Preço sob consulta [S] | Idem |
| Buzzmonitor, Talkwalker/Hootsuite, Sprinklr, Meltwater | Não levantados em detalhe | Idem |

**Critérios obrigatórios para qualquer provedor:** (1) declaração de que a coleta usa API oficial ou acordo de dados com a plataforma, e não scraping que contorne bloqueio (C-02/C-03); (2) exportação dos textos com URL, data de publicação e plataforma (G-02); (3) identificador de autor que permita hashing, sem obrigação de armazenar nome (C-04); (4) custo por volume de menções.

**Excluídos por compliance:** serviços de scraping de TikTok, Instagram ou Reddit sem licença da plataforma (ex.: atores de scraping em marketplaces de automação). Violam C-02/C-03 mesmo quando tecnicamente disponíveis.

### 1.3 Opções para decisão

| Opção | Composição | Custo estimado | Cobertura | Risco |
|---|---|---|---|---|
| **A — MVP sem custo de dados** | YouTube Data API + Mercado Livre API + avaliações JSON-LD dos sites oficiais. Google Trends por exportação manual + candidatura à API alpha. | R$ 0 em dados | Reviews e comentários longos; sem TikTok/Instagram | Viés para consumidor de marketplace/YouTube; ausência das redes de maior conversa sobre beleza |
| **B — A + Instagram Graph API** | Opção A + monitoramento de até 30 hashtags por semana | R$ 0 em dados; esforço de App Review | Adiciona volume por hashtag, sem comentários | Limite de 30 hashtags; dados de baixo valor para voz do consumidor |
| **C — A + provedor licenciado** | Opção A + contrato com provedor para TikTok, Instagram e Facebook | Cotação necessária [C] | Cobertura das redes fechadas | Custo recorrente; dependência de exportação do provedor |

**Recomendação:** **Opção A** para o MVP (F1-07 pede 2 a 3 fontes viáveis), com início das cotações da Opção C em paralelo, para decidir na Fase 2 com base no custo por menção. A Opção B não é recomendada: o limite de 30 hashtags e a ausência de comentários não sustentam o requisito TEMA + NECESSIDADE + CONTEXTO (§6.2).

---

## 2. DEC-09 — Fontes de market share e sell-out no Brasil

### 2.1 Bases levantadas

| Fonte | Tipo | Granularidade | Aderência ao NEXA | Custo | Status no banco (G-11) |
|---|---|---|---|---|---|
| **IQVIA** (varejo farmacêutico) | Sell-out em farmácias, licenciado | Empresa, marca, categoria, canal farma; recortes regionais sob contrato | **Muito alta**: dermocosméticos somaram R$ 12,3 bi em 12 meses até jul/2025 (+8,3%), com 83% das vendas em loja física; marcas como Principia e Ollie vendem 88% e 86% em loja física [S, citando IQVIA] | [C] | `observed` |
| **Worldpanel (ex-Kantar Worldpanel)** | Painel de domicílios (sell-out do consumidor) | Categoria, marca, perfil do comprador, canal; painel em expansão de 11.300 para 26.300 lares até o 1º semestre de 2026 [O] | Alta para comportamento de compra e penetração; precisão por marca de nicho a confirmar | [C] | `observed` (amostral; registrar intervalo) |
| **NielsenIQ** | Scanning de varejo (sell-out) | Categoria, marca, canal, região | Alta em varejo alimentar/farma; cobertura de e-commerce e venda direta a confirmar | [C] | `observed` |
| **Euromonitor Passport** | Tamanho de mercado e share anual | Categoria, nacional, anual | Média: bom denominador (`market_size`), pouca granularidade regional. É a base dos números da ABIHPEC (R$ 175 bi em 2025, +6,8%) [S] | [C] | `observed` (nacional) |
| **Nubimetrics** | Inteligência de vendas no Mercado Livre | Produto, vendedor, categoria, só Mercado Livre | Média: canal e-commerce/marketplace; vendas reportadas pela plataforma | [C]; preço não publicado [S] | `estimated` (insumo `platform_sales_rank`) |
| **ABIHPEC** | Associação setorial (agregado público) | Setor total, nacional | Baixa para share; útil como contexto e checagem do denominador | Gratuito | `observed` só para o total do setor |
| **Demonstrações de companhias abertas** (ex.: Natura &Co) | Público, auditado | Empresa/segmento, às vezes por país | Baixa granularidade; útil para triangular | Gratuito | Insumo `company_disclosure` |
| **Comex Stat / IBGE** | Público | NCM (importação) / produção industrial | Baixa; apenas triangulação de oferta | Gratuito | Insumo `public_trade_data` |
| **Close-Up International** | Auditoria farmacêutica | Farma | Possível alternativa à IQVIA; **não verificada** neste levantamento | [C] | — |

### 2.2 Opções para o piloto F1-15

Categoria piloto sugerida: **proteção solar facial no canal farmácia** (a marca P1-A Ollie, o foco em stick FPS e a linha de base financeira estão nessa categoria).

| Opção | Composição | Resultado esperado no AC-16 | Custo |
|---|---|---|---|
| **A — Recorte licenciado IQVIA** | Compra de um recorte: proteção solar facial × farmácia × Brasil + UFs prioritárias, últimos 12–24 meses | Share `observed` por marca/UF com fonte auditável | [C] |
| **B — Estimativa documentada com dados públicos** | Euromonitor/ABIHPEC (denominador nacional) + números IQVIA citados em imprensa + `company_disclosure` + presença em varejo | Share `estimated` com intervalo largo e confiança baixa, ou relatório de impossibilidade + plano de aquisição | R$ 0 |
| **C — Canal e-commerce via Nubimetrics** | Assinatura Nubimetrics restrita a Mercado Livre | Share `estimated` do canal marketplace (não representa o mercado total) | [C] |

**Recomendação:** iniciar pela **Opção B** (cumpre AC-16 pela via "estimativa documentada ou demonstração de impossibilidade" sem custo) e solicitar em paralelo a cotação da **Opção A**, que é a única que entrega share observado para o canal dominante de dermocosméticos. A decisão de compra depende do orçamento (Q-18).

**Restrição permanente:** seguidores, avaliações, buscas e tráfego não entram como insumo (G-07); a constraint `market_share_inputs_ck` já bloqueia isso no banco.

---

## 3. DEC-10 — Hospedagem do worker

### 3.1 Perfil da carga

- Worker Python 3.12 com Chromium (Playwright) para páginas JS; 1 a 2 GB de RAM por processo de navegador.
- Carga em lotes: MVP com 20 marcas e 300 a 500 SKUs, cadência semanal/quinzenal (§13); Fase 2 com 100 a 150 marcas.
- Consome `ops.job_queue` até esvaziar; não precisa ficar ligado 24 h no MVP.
- Latência relevante entre worker e Supabase: preferir mesma região (São Paulo).

### 3.2 Opções

| Opção | Modelo de cobrança | Prós | Contras | Custo indicativo |
|---|---|---|---|---|
| **A — VPS** (Hetzner, DigitalOcean, Magalu Cloud) | Mensal fixo | Controle total; Playwright sem restrição; custo previsível | Manutenção de SO, segurança e deploy por conta própria. Hetzner: reajuste de ~33–43% em abr/2026 e indisponibilidade da linha de menor custo desde jun/2026 [S]; sem região no Brasil | Hetzner CPX 4 GB ≈ € 20/mês [S]; demais [C] |
| **B — Google Cloud Run Jobs** (região `southamerica-east1`) | Por vCPU-segundo e GiB-segundo; escala a zero | Paga só durante o lote; região São Paulo; container com Chromium; disparo por Cloud Scheduler ou HTTP | Limite de duração por tarefa a confirmar para lotes longos; exige conta GCP | Jobs: US$ 0,000018 por vCPU-s após franquia gratuita (tabela base; preço de São Paulo a confirmar) [O] |
| **C — Fly.io Machines** (região GRU) | Por segundo de máquina | Região São Paulo; liga/desliga máquinas sob demanda | Sem franquia gratuita para contas novas [S]; egress pago | shared-cpu-1x 256 MB ≈ US$ 2/mês ligado 24 h [S]; 2 GB para Chromium [C] |
| **D — Railway / Render** | Uso (Railway) ou instância fixa (Render) | Deploy simples a partir do repositório | Render reestruturou preços em 2026 [S]; sem região no Brasil | Railway Hobby a partir de US$ 5/mês + uso [S] |
| **Descartado — GitHub Actions como worker** | — | — | Os termos do GitHub Actions restringem o uso a atividades ligadas ao desenvolvimento do próprio software; rodar coleta de produção ali cria risco de violação de termos (contrário ao espírito de C-01). IPs compartilhados também aumentam bloqueios. Pode ser usado só para CI e para disparar jobs | — |

### 3.3 Recomendação

**Opção B — Cloud Run Jobs em São Paulo** para o MVP e a Fase 2: a carga é em lotes, o custo acompanha o uso, fica na mesma região do Supabase recomendado (`sa-east-1`) e o container com Chromium roda sem ajuste especial. O `pg_cron` enfileira em `ops.job_queue` e aciona a execução do job; o job consome a fila e encerra.

**Alternativa:** Opção A (VPS) se a preferência for custo fixo e controle total, aceitando a manutenção do servidor.

---

## 4. Decisões solicitadas

| # | Decisão | Opções | Recomendação |
|---|---|---|---|
| 1 | DEC-08 — fontes sociais do MVP | A · B · C | **A**, com cotação da C em paralelo |
| 2 | DEC-09 — market share do piloto F1-15 | A · B · C | **B**, com cotação da A em paralelo |
| 3 | DEC-10 — worker | A · B · C · D | **B** (Cloud Run Jobs, São Paulo) |
| 4 | Categoria piloto do F1-15 | Proteção solar facial × farmácia (sugerida) ou outra | Proteção solar facial × farmácia |
| 5 | Orçamento mensal (Q-18) | Teto em R$ para dados, infraestrutura e modelos | Necessário para decidir as cotações |

---

## 5. Fontes consultadas

**DEC-08**
- [YouTube Data API — Quota Calculator (Google)](https://developers.google.com/youtube/v3/determine_quota_cost)
- [Mercado Livre — Opiniões sobre um produto (documentação oficial)](https://developers.mercadolivre.com.br/pt-br/opinioes-sobre-um-produto)
- [Meta — Instagram Hashtag Search (documentação oficial)](https://developers.facebook.com/documentation/instagram-platform/instagram-api-with-facebook-login/hashtag-search)
- [Supermetrics — Good to know about Instagram public data](https://docs.supermetrics.com/docs/good-to-know-about-instagram-public-data.md)
- [Meta Content Library — Get access (documentação oficial)](https://developers.secure.facebook.com/docs/content-library-api/get-access)
- [Meta Transparency — Meta Content Library](https://transparency.meta.com/pt-br/researchtools/meta-content-library)
- [Datashake — TikTok Data Coverage in 2026](https://www.datashake.com/blog/tiktok-data-coverage-in-2026-what-social-intelligence-teams-need-to-know)
- [Xpoz — TikTok Research API limits, access and alternatives](https://www.xpoz.ai/blog/guides/tiktok-research-api-limits-access-and-alternatives/)
- [Techloy — Reddit API pricing in 2026](https://www.techloy.com/reddit-api-pricing-in-2026-complete-guide-for-developers-and-businesses/)
- [Octolens — Reddit API pricing](https://octolens.com/blog/reddit-api-pricing)
- [PPC Land — Google opens alpha testing for new Trends API](https://ppc.land/google-opens-alpha-testing-for-new-trends-api-targeting-developers-and-journalists/)
- [Konabayev — Google Trends API Landscape 2026](https://konabayev.com/blog/google-trends-api-landscape-2026/)
- [The SI Lab — Stilingue (take.blip)](https://www.thesilab.com/vendor-directory/stilingue-take-blip)
- [Influencer Marketing Hub — Ferramentas de monitoramento de mídia social](https://influencermarketinghub.com/br/ferramentas-monitoramento-social/)
- [Capterra — Brandwatch](https://www.capterra.com.br/software/157048/brandwatch)

**DEC-09**
- [Giro News — Mercado de dermocosméticos cresce 8,3% (dados IQVIA)](https://gironews.com/farma-cosmeticos/mercado-de-dermocosmeticos-cresce-83-nos-ultimos-12-meses/)
- [Revista Panpharma ed. 95](https://www.panpharma.com.br/uploads/2024/06/Revista_Panpharma_Ed95_Interativa.pdf)
- [Worldpanel Brasil — expansão do painel](https://www.kantar.com/brazil/campaigns/wp/2025/mosaico)
- [Grandes Nomes da Propaganda — estudo Kantar sobre gerações e beleza](https://grandesnomesdapropaganda.com.br/mercado/estudo-da-kantar-aponta-como-diferentes-geracoes-consomem-produtos-de-beleza/)
- [O Hoje — Brasil bate R$ 175 bilhões no mercado de beleza](https://ohoje.com/2026/08/10/brasil-bate-r-175-bilhoes-no-mercado-de-beleza-e-setor-mira-novas-tendencias/)
- [Economic News Brasil — mercado de beleza R$ 200 bilhões](https://economicnewsbrasil.com.br/2026/09/15/elf-no-brasil-mercado-beleza-200-bilhoes/)
- [Academia Nubimetrics — Beleza](https://academia.nubimetrics.com/br/beleza)
- [Jaguar Sheet — Nubimetrics vs Real Trends](https://jaguarsheet.com/pt/comparar/nubimetrics-vs-real-trends)

**DEC-10**
- [Google Cloud — Cloud Run pricing](https://cloud.google.com/run/pricing/?hl=pt-br)
- [Findstack — Railway vs Render vs Fly.io](https://findstack.com/resources/railway-vs-render-vs-fly-io)
- [Techplained — Render vs Railway vs Fly.io (2026)](https://www.techplained.com/render-vs-railway-vs-flyio)
- [Findstack — Hetzner price increase 2026](https://findstack.com/resources/hetzner-price-increase-2026)
- [Vincent Schmalbach — Hetzner cheap cloud unavailable](https://www.vincentschmalbach.com/hetzner-cheap-cloud-unavailable-price-increases/)
