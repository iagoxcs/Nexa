# Prompts versionados (A-03)

Todo prompt usado pelo `llm_gateway` vive aqui, um arquivo por prompt, em `prompts/<area>/<nome>.md`.
O gateway resolve o nome `area.nome` para o arquivo e grava `prompt_version` em cada saída.

## Formato

```markdown
---
name: extraction.product_page
version: 0.1.0
task: extraction
description: Uma linha sobre o objetivo do prompt
---
## system
Instruções permanentes.

## user
Conteúdo da requisição, com variáveis {{nome_da_variavel}}.
```

| Campo | Regra |
|---|---|
| `name` | Igual ao caminho: `prompts/extraction/product_page.md` → `extraction.product_page` |
| `version` | SemVer. Toda alteração de texto incrementa a versão |
| `task` | `extraction`, `classification`, `council` ou `critical_review` (define a rota em `config/llm_routing.toml`) |
| Variáveis | `{{nome}}`. Variável ausente na chamada gera `PromptError` |

`prompt_version` gravado = `name@version#<8 primeiros caracteres do sha256 do arquivo>`. Se o arquivo mudar sem incremento de versão, o hash denuncia.

## Regras de conteúdo

- Instruir explicitamente a não inventar valores (G-03): ausência → `null`.
- Exigir trecho literal da fonte para cada valor extraído, quando o schema tiver campo de evidência (G-02).
- Nunca pedir inferência de idade/geração por estética (G-08).
- O schema de saída é um modelo Pydantic no código; o prompt não repete o schema por extenso.

## Pastas

| Pasta | Uso | Fase |
|---|---|---|
| `extraction/` | Extração de atributos de página de produto/marca (F1-04) | 1 |
| `classification/` | Classificação de sinais de consumidor pela taxonomia §6.2 (F1-07) | 1 |
| `council/` | Diretores do Conselho, debate e consolidação (F1-14) | 1–3 |
