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
            "Use quando o usuário perguntar sobre previsão, tendência ou o que pode acontecer com o preço. " \
            "Sempre mencione a incerteza e se o modelo superou o baseline."
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
            scoreboard: scoreboard(ticker),
            source: "modelo estatístico local (#{forecast.model})",
            disclaimer: DISCLAIMER
          }
        end

        private

        def scoreboard(ticker)
          past = @forecasts.evaluated(ticker)
          hits = past.map(&:direction_hit?).compact
          {
            evaluated: past.size,
            direction_hits: hits.count(true),
            inside_range: past.count(&:inside_range?)
          }
        end
      end
    end
  end
end
