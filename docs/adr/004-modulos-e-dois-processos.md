# ADR-004: Módulos com dependências em uma direção e previsão em processo separado

**Status:** Aceito
**Data:** 2026-10-23
**Decisores:** Pedro Barbosa
**Relacionado:** [ADR-001](001-stack-e-principios.md), [ADR-003](003-camada-de-llm-agnostica.md)

## Contexto

O projeto passou a ter previsão de retorno de ações. Uma intuição comum, e errada, é que o LLM "aprende" com os dados enviados a ele. Não aprende: durante a conversa (inferência) os pesos do modelo estão congelados. Dados enviados no contexto são só uma folha de consulta, e mandar dados ao LLM o dia inteiro só gastaria tokens.

O aprendizado com o histórico precisa acontecer em outro lugar: um **modelo estatístico próprio**, treinado no código e re-treinado quando chegam dados novos. Isso levanta duas perguntas de arquitetura:

1. **Quem roda o treino e quando?** Ele não pode depender de alguém abrir o chat.
2. **Como organizar o código** para que treino, IA e chat não se contaminem?

## Decisão

### 1. Dois processos independentes

```
PROCESSO 1 · agendado (bin/scheduler → bin/forecast_job) · SEM LLM, SEM TOKENS
  fonte de dados → Postgres → avalia previsões antigas → re-treina → backtest → salva previsão

PROCESSO 2 · sob demanda (bin/chat)
  usuário → LLM → tool forecast_price → LÊ a previsão salva → LLM explica
```

É uma forma simples de **separação entre escrita e leitura** (CQRS): o job escreve, o chat só lê. A tool `forecast_price` não calcula nada.

O job é **idempotente**: rodar duas vezes no mesmo dia deixa o banco igual (upsert por `(ticker, date)` e por `(ticker, as_of, model)`).

### 2. Quatro módulos, dependências em uma só direção

```
chat ──────► llm
  ├────────► forecasting ──────► market_data
  └────────► market_data
```

| Módulo | Responsabilidade | Pode depender de |
|---|---|---|
| `market_data` | buscar e guardar preços (`Bar`, clientes, `PriceRepository`) | nada |
| `llm` | formato neutro e providers (ADR-003) | nada |
| `forecasting` | features, modelos, backtest, `ForecastRepository`, `DailyJob` | `market_data` |
| `chat` | `Agent`, `Registry`, tools | `llm`, `forecasting`, `market_data` |

A regra: **cada módulo depende só do que precisa para fazer o próprio trabalho**. Quanto mais um módulo é usado pelos outros, mais estável e independente ele precisa ser, então `market_data` fica na base, sem depender de ninguém.

A regra é **verificada por teste** (`test/architecture_test.rb`), que lê os `require` de cada módulo e também carrega o `forecasting` num processo isolado para provar que `llm` e `chat` não vazam.

Um único lugar conhece todos os módulos: a **raiz de composição** em `lib/marketpulse.rb`, que decide pelo `.env` quais implementações conectar (Postgres ou memória, Stooq ou dados simulados, qual provider de IA).

### 3. Previsão como experimento

- Modelo inicial: **um peso**, `retorno_amanhã = peso × retorno_hoje`, treinado por mínimos quadrados (`peso = Σ(hoje × amanhã) / Σ(hoje²)`). O sinal do peso revela momentum (positivo) ou reversão à média (negativo); a estatística t diz se o padrão é distinguível de ruído.
- **Baseline obrigatório:** "amanhã = hoje" (retorno zero).
- **Backtest walk-forward:** treina só com o passado, prevê o próximo dia, avança. Um teste garante que nenhum dado futuro entra no treino.
- **Placar:** cada previsão guarda `actual_close`, preenchido pelo job no pregão seguinte.
- A saída é sempre **uma faixa** (~95%), nunca um número único.

## Opções consideradas

### Opção A: O LLM faz a previsão lendo os dados

**Prós:** simples de montar.
**Contras:** o LLM não aprende com os erros, gera números sem garantia estatística e gasta tokens a cada pergunta. Contraria o princípio "o código calcula, o Claude interpreta" (ADR-001).

### Opção B: Treinar na hora em que o usuário pergunta

**Prós:** sem agendador.
**Contras:** respostas lentas, o placar só avança quando alguém pergunta, e o chat passa a depender de fonte de dados e treino funcionando no momento da conversa.

### Opção C: Job agendado separado, chat só lê (escolhida)

**Prós:** custo zero de tokens para manter o modelo, falhas isoladas (a IA fora do ar não impede o re-treino, e vice-versa), placar contínuo.
**Contras:** mais um processo para operar (o serviço `scheduler`) e dados com até um dia de atraso, o que é suficiente para previsão do pregão seguinte.

## Consequências

### Positivas

- O treino roda sem IA, sem chave e sem tokens.
- Cada módulo pode ser testado isolado; repositórios em memória e em Postgres cumprem o mesmo contrato de testes.
- Trocar a fonte de dados (fake → Stooq) ou a IA (offline → Ollama → Claude) não toca na previsão.

### Negativas e cuidados

- Mais arquivos e pastas do que um script único. É o preço de a regra de dependência ser verificável.
- Sem banco (`DATABASE_URL`), os dados vivem em memória: o `bin/chat` roda o job ao iniciar para ter o que ler, e nada persiste.
- O modelo de um peso é deliberadamente simples. Em dados reais, espere vencer o baseline por pouco ou não vencer, e isso também é um resultado válido.

## Action Items

1. [x] Separar `market_data`, `forecasting`, `llm` e `chat`, com teste de arquitetura.
2. [x] Modelo de um peso, baseline, backtest walk-forward e placar.
3. [x] `DailyJob` idempotente, `bin/forecast_job` e `bin/scheduler`.
4. [x] Repositórios em memória e PostgreSQL (Sequel, migrações).
5. [ ] Prever volatilidade (faixa) com um modelo próprio, em vez do desvio dos resíduos.
6. [ ] Notícias e sentimento como feature, classificadas por um modelo barato e guardadas no banco.
