# ADR-005: Previsão de direção com classificador, threshold e precisão

**Status:** Aceito
**Data:** 2026-10-23
**Decisores:** Pedro Barbosa
**Relacionado:** [ADR-001](001-stack-e-principios.md), [ADR-004](004-modulos-e-dois-processos.md)

## Contexto

O tutorial [*Predict The Stock Market With Machine Learning And Python*](https://youtu.be/1O_BenficgE) (Dataquest) prevê o S&P 500 de um jeito diferente do nosso modelo de um peso (ADR-004):

| | MarketPulse até aqui | Tutorial |
|---|---|---|
| Pergunta | *quanto* vai variar amanhã? (regressão) | *vai subir* amanhã? (classificação) |
| Features | só o retorno de hoje | razão preço/média móvel e tendência em vários horizontes (2, 5, 60, 250 e 1000 dias) |
| Modelo | `peso × retorno_hoje` | Random Forest (scikit-learn) |
| Quando fala | todo dia | só quando a probabilidade passa de **0,6** |
| Métrica | MAE contra "amanhã = hoje" | **precisão** contra a % de dias que sobem |

A arquitetura do projeto já seguia boa parte do que o tutorial ensina: walk-forward sem dado do futuro, baseline obrigatório, previsão calculada pelo código e não pelo LLM. O que faltava era responder a pergunta que um investidor iniciante realmente faz ("vai subir?") com uma métrica que ele consegue entender ("das vezes em que o modelo disse que ia subir, quantas subiu?").

## Decisão

Adicionar ao módulo `forecasting` um **classificador de direção** que roda no mesmo `DailyJob`, ao lado do `OneWeight`, e é salvo na mesma linha da tabela `forecasts`.

### 1. Features em vários horizontes (`Features.horizon_rows`)

Para cada horizonte `h`:

- `ratio_h = fechamento_hoje / média dos últimos h fechamentos - 1`
- `trend_h = fração de dias de alta entre os últimos h pregões`

O alvo `up` (o próximo fechamento foi maior?) nunca entra nas features. Um teste altera todos os preços a partir de um dia e verifica que as features dos dias anteriores não mudam.

Os horizontes padrão são **2, 5, 20 e 60**, e não os 250 e 1000 do tutorial: aqui temos cerca de 500 pregões, e um horizonte de 1000 dias exigiria quatro anos de histórico só para calcular a primeira linha. Eles são configuráveis por `DIRECTION_HORIZONS`.

### 2. Regressão logística em Ruby puro (`Models::LogisticDirection`)

`P(alta) = sigmoide(viés + Σ peso × feature)`, treinada por descida de gradiente com regularização L2 e features padronizadas pela média e pelo desvio do **treino**.

Fica a logística, e não a Random Forest, por coerência com o ADR-001: são cerca de 70 linhas com a stdlib, o resultado é determinístico, os pesos são legíveis e não entra um segundo runtime (Python) só para um modelo. O contrato `fit(rows)` / `predict_proba(values)` permite trocar o modelo depois.

### 3. Threshold e precisão (`Direction`)

- O sinal é `"alta"` só quando `P(alta) >= 0,6` (`DIRECTION_THRESHOLD`). Abaixo disso, é `"sem sinal"`: o modelo fala menos vezes, mas cada sinal vale mais.
- O backtest é walk-forward em blocos: treina com as primeiras 120 linhas, prevê as 20 seguintes, inclui essas no treino e repete. Re-treinar a cada 20 dias, e não todo dia, mantém o job em pouco mais de 1 segundo por ticker com 500 pregões.
- **Precisão** = dos dias em que o modelo disse alta, quantos subiram.
- **Baseline** = a porcentagem de dias de alta no mesmo período. Dizer "alta" todo dia já acerta isso sem modelo nenhum.

### 4. Vitória só com significância (z ≥ 2)

O primeiro critério testado foi "precisão maior que o baseline, com pelo menos 10 sinais". O experimento abaixo mostrou que ele declarava vitória na MSFT, que nos dados simulados é um passeio aleatório puro. Por isso o critério adotado é o mesmo do `|t| >= 2` do `OneWeight`:

```
z = (precisão - baseline) / sqrt(baseline × (1 - baseline) / sinais)
```

O resultado vira um de quatro vereditos: *superou o baseline*, *acima do baseline, mas pode ser sorte*, *não superou* ou *inconclusivo* (menos de 10 sinais).

### Experimento de referência

Dados simulados, 500 pregões, threshold 0,6. A AAPL tem momentum, a PETR4 tem reversão à média e a MSFT é ruído (ver `FakeClient`).

| Horizontes | AAPL (momentum) | PETR4 (reversão) | MSFT (ruído) |
|---|---|---|---|
| `2` | 55,9% vs 53,1%, z=+0,5, pode ser sorte | **67,5% vs 56,5%, z=+2,4** | 57,1% vs 48,8%, z=+0,9, pode ser sorte |
| `2,5` | 50,0% vs 52,9%, não superou | **66,4% vs 56,7%, z=+2,1** | 48,0% vs 48,7%, não superou |
| `2,5,20,60` (padrão) | 45,5% vs 52,7%, não superou | **66,9% vs 57,1%, z=+2,2** | 41,9% vs 48,6%, não superou |

Leituras:

- **A reversão da PETR4 é encontrada em todas as configurações.** O padrão mais forte sobrevive.
- **Mais features pioram a AAPL.** Com cerca de 300 linhas de treino, os horizontes longos geram pesos espúrios (overfitting). Regularização L2 mais forte foi testada (0,1 e 0,3) e não resolveu: o problema é feature demais para pouco histórico, não o tamanho dos pesos.
- **Sem o teste de significância, a MSFT "venceria"** com só o horizonte de 2 dias. É o exemplo mais claro de por que precisão sem tamanho de amostra engana.

## Opções consideradas

### Opção A: Serviço Python com scikit-learn (Random Forest, fiel ao tutorial)

**Prós:** modelo não linear, ecossistema de ML completo, prática com mais um container.
**Contras:** um segundo runtime e uma API HTTP interna só para um modelo, exceção ao ADR-001 e ao teste de arquitetura. Fica como evolução se a logística se mostrar limitada em dados reais.

### Opção B: Usar o sinal do `OneWeight` como direção

**Prós:** nada novo para manter.
**Contras:** sem features de horizonte, sem probabilidade e sem threshold. Não testa a ideia do tutorial.

### Opção C: Classificador logístico em Ruby, no mesmo job (escolhida)

**Prós:** sem dependência nova, determinístico, testável com a stdlib, e o resultado mora na mesma linha da previsão de retorno (um placar só).
**Contras:** modelo linear; Ruby puro é lento para treinos grandes (mitigado com re-treino em blocos e laços `while` no trecho quente).

## Consequências

### Positivas

- O chat responde "vai subir?" com uma probabilidade, um sinal e a precisão histórica desse sinal comparada a uma régua que qualquer pessoa entende.
- O placar ganha `up_signals` e `up_signal_hits`: quantas vezes o modelo disse alta e quantas acertou, com dados reais, pregão a pregão.
- A tool entrega o veredito pronto, e o LLM só o explica (princípio do ADR-001).
- Tudo é desligável e configurável pelo `.env` (`DIRECTION=off`, `DIRECTION_HORIZONS`, `DIRECTION_THRESHOLD`).

### Negativas e cuidados

- **A suíte de testes ficou mais lenta** (de ~0,6 s para ~8 s), porque cada teste do `DailyJob` agora treina o classificador. Se incomodar, os testes que não tratam de direção podem injetar `direction: nil`.
- **Séries curtas** (menos de ~180 pregões com os horizontes padrão) ficam sem direção. A previsão de retorno continua sendo salva com `direction_*` nulo, e a tool omite o bloco.
- **Duas previsões podem discordar** (o `OneWeight` vê momentum na AAPL, e a direção não supera o baseline). Isso é informação, não bug: a tool mostra os dois vereditos.
- **Um sinal de "alta" pode aparecer mesmo quando o modelo não supera o baseline.** A tool instrui o LLM a dizer que, nesse caso, o sinal não merece confiança.
- Migração `003` com colunas anuláveis: previsões antigas continuam legíveis.

## Action Items

1. [x] Features multi-horizonte com teste anti-vazamento.
2. [x] `LogisticDirection`, `Direction.run` e backtest em blocos com precisão e z.
3. [x] Integração no `DailyJob`, migração `003`, tool `forecast_price` e modo offline.
4. [ ] Rodar com `MARKET_DATA_SOURCE=stooq` por algumas semanas e registrar a precisão real versus o backtest.
5. [ ] Selecionar horizontes por backtest (validação), em vez de fixar no `.env`.
6. [ ] Reavaliar a Opção A (Random Forest) se a logística não superar o baseline em dados reais.
