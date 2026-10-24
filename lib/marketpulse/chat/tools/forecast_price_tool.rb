# frozen_string_literal: true

module MarketPulse
  module Chat
    module Tools
      # O PROCESSO 2 lendo o que o PROCESSO 1 deixou pronto (ADR-004).
      # Esta tool não treina nem calcula nada: só lê a última previsão salva
      # pelo job e o placar de acertos, e entrega ao modelo para explicar.
      class ForecastPriceTool
        class NoForecastError < StandardError; end

        DISCLAIMER = "Exercício educacional. Não é recomendação de investimento."

        def initialize(forecasts:)
          @forecasts = forecasts
        end

        def name = "forecast_price"

        def description
          "Retorna a previsão estatística do próximo pregão de uma ação: retorno previsto, faixa de " \
            "preço provável, o padrão encontrado nos dados (momentum, reversão à média ou nenhum), " \
            "o resultado do backtest contra o baseline e o placar de previsões passadas. " \
            "Inclui também a probabilidade de o próximo pregão fechar em alta, com a precisão desse sinal " \
            "no backtest comparada à porcentagem de dias que simplesmente sobem. " \
            "Use quando o usuário perguntar sobre previsão, tendência, se vai subir ou o que pode acontecer com o preço. " \
            "Sempre mencione a incerteza e se cada modelo superou o seu baseline."
        end

        def input_schema
          {
            type: "object",
            properties: { ticker: { type: "string", description: "Ticker em maiúsculas, ex.: AAPL" } },
            required: ["ticker"]
          }
        end

        def execute(input)
          ticker = input.fetch("ticker").strip.upcase
          forecast = @forecasts.latest(ticker) or
            raise NoForecastError, "Ainda não há previsão para #{ticker}. Rode o job: bin/forecast_job"

          {
            ticker: ticker,
            as_of: forecast.as_of.to_s,
            model: forecast.model,
            last_close: forecast.last_close,
            predicted_return_pct: (forecast.predicted_return * 100).round(3),
            predicted_close: forecast.predicted_close,
            range: { low: forecast.low, high: forecast.high, confidence: "~95%" },
            pattern: forecast.pattern,
            weight: forecast.weight,
            t_stat: forecast.t_stat,
            backtest: {
              mae_pct: (forecast.mae * 100).round(4),
              baseline_mae_pct: (forecast.baseline_mae * 100).round(4),
              beats_baseline: forecast.mae < forecast.baseline_mae,
              direction_hit_rate_pct: (forecast.hit_rate * 100).round(1),
              n_tests: forecast.n_tests
            },
            direction: direction(forecast),
            scoreboard: scoreboard(ticker),
            source: "modelo estatístico local (#{forecast.model})",
            disclaimer: DISCLAIMER
          }
        end

        private

        # Classificador de direção (ADR-005). nil quando a série foi curta demais.
        def direction(forecast)
          return nil unless forecast.direction?

          b = forecast.direction_backtest
          {
            prob_up_pct: (forecast.prob_up * 100).round(1),
            signal: forecast.direction_signal,
            threshold_pct: (forecast.direction_threshold * 100).round(1),
            backtest: {
              precision_pct: b.precision && (b.precision * 100).round(1),
              up_signals: b.signals,
              baseline_up_days_pct: (b.up_rate * 100).round(1),
              conclusive: b.conclusive?,
              z: b.z&.round(2),
              beats_baseline: b.beats_baseline?,
              verdict: b.verdict,
              n_tests: b.n_tests
            },
            how_to_read: "Só é \"alta\" quando a probabilidade passa do threshold. A precisão diz, dos dias em que " \
                         "o modelo disse alta no backtest, quantos subiram; o baseline é a porcentagem de dias " \
                         "que subiram de qualquer forma. Só conta como vitória com z >= 2 (vantagem maior que " \
                         "dois erros-padrão). Se beats_baseline for false, o sinal não merece confiança."
          }
        end

        def scoreboard(ticker)
          past = @forecasts.evaluated(ticker)
          hits = past.map(&:direction_hit?).compact
          up_signals = past.map(&:up_signal_hit?).compact
          {
            evaluated: past.size,
            direction_hits: hits.count(true),
            inside_range: past.count(&:inside_range?),
            up_signals: up_signals.size,
            up_signal_hits: up_signals.count(true)
          }
        end
      end
    end
  end
end
