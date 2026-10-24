# frozen_string_literal: true

require "time"
require_relative "features"
require_relative "backtest"
require_relative "forecast"
require_relative "models/naive"
require_relative "models/one_weight"
require_relative "direction"

module MarketPulse
  module Forecasting
    # O PROCESSO 1 (ADR-004): roda agendado, sem LLM e sem tokens.
    #
    # Para cada ticker:
    #   1. busca o histórico e salva (upsert idempotente)
    #   2. avalia previsões antigas contra o preço real  ← "aprender com o erro"
    #   3. re-treina o modelo com todos os dados disponíveis
    #   4. mede o modelo com backtest walk-forward contra o baseline
    #   5. treina e mede o classificador de direção (ADR-005)
    #   6. gera e salva a previsão do próximo pregão
    class DailyJob
      Z95 = 1.96 # faixa de ~95% supondo erros aproximadamente normais

      def initialize(client:, prices:, forecasts:, tickers:, logger: $stdout,
                     history_days: 500, min_train: 60, model_factory: -> { Models::OneWeight.new },
                     direction: ->(closes) { Direction.run(closes) })
        @client = client
        @prices = prices
        @forecasts = forecasts
        @tickers = tickers
        @logger = logger
        @history_days = history_days
        @min_train = min_train
        @model_factory = model_factory
        @direction = direction
      end

      def run
        @tickers.to_h do |ticker|
          [ticker, run_ticker(ticker)]
        rescue StandardError => e
          # Um ticker com problema não derruba o job inteiro.
          log "✗ #{ticker}: #{e.class}: #{e.message}"
          [ticker, nil]
        end
      end

      private

      def run_ticker(ticker)
        saved = @prices.save_bars(@client.history(ticker, days: @history_days))
        evaluated = evaluate_pending(ticker)

        bars = @prices.history(ticker)
        returns = Features.returns(bars.map(&:close))
        model = @model_factory.call.fit(returns)
        backtest = Backtest.walk_forward(returns, model_factory: @model_factory, min_train: @min_train)
        direction = predict_direction(ticker, bars.map(&:close))

        forecast = build_forecast(ticker, bars.last, returns.last, model, backtest, direction)
        @forecasts.save(forecast)

        log format("✓ %-6s %d pregões, %d previsões avaliadas | peso %+.3f (t=%+.1f, %s) | MAE %.3f%% vs baseline %.3f%%%s",
                   ticker, saved, evaluated, model.weight, model.t_stat, model.pattern,
                   backtest.mae * 100, backtest.baseline_mae * 100, direction_log(direction))
        forecast
      end

      # A direção é um complemento: se a série for curta demais para ela,
      # a previsão de retorno continua sendo salva, com direction_* em nil.
      def predict_direction(ticker, closes)
        return nil unless @direction

        @direction.call(closes)
      rescue Error => e
        log "  #{ticker}: direção ignorada (#{e.message})"
        nil
      end

      def direction_log(d)
        return "" unless d

        b = d.backtest
        precision = b.precision ? format("%.1f%%", b.precision * 100) : "-"
        format(" | P(alta) %.0f%% %s, precisão %s vs %.1f%% de dias de alta (%s)",
               d.prob_up * 100, d.signal, precision, b.up_rate * 100, b.verdict)
      end

      def evaluate_pending(ticker)
        @forecasts.pending_evaluation(ticker).count do |forecast|
          next_bar = @prices.bar_after(ticker, forecast.as_of)
          next false unless next_bar

          @forecasts.record_actual(forecast, next_bar.close)
          true
        end
      end

      def build_forecast(ticker, last_bar, last_return, model, backtest, direction)
        predicted_return = model.predict(last_return)
        spread = Z95 * model.residual_std
        Forecast.new(
          ticker: ticker, as_of: last_bar.date, model: model.name,
          weight: model.weight.round(6), t_stat: model.t_stat.round(3), pattern: model.pattern,
          last_close: last_bar.close,
          predicted_return: predicted_return.round(6),
          predicted_close: (last_bar.close * (1 + predicted_return)).round(2),
          low: (last_bar.close * (1 + predicted_return - spread)).round(2),
          high: (last_bar.close * (1 + predicted_return + spread)).round(2),
          mae: backtest.mae.round(6), baseline_mae: backtest.baseline_mae.round(6),
          hit_rate: backtest.hit_rate.round(4), n_tests: backtest.n_tests,
          **direction_fields(direction),
          actual_close: nil, created_at: Time.now.utc
        )
      end

      def direction_fields(d)
        b = d&.backtest
        {
          prob_up: d&.prob_up&.round(4), direction_signal: d&.signal, direction_threshold: d&.threshold,
          direction_precision: b&.precision&.round(4), direction_signals: b&.signals,
          direction_up_rate: b&.up_rate&.round(4), direction_n_tests: b&.n_tests
        }
      end

      def log(message) = @logger&.puts(message)
    end
  end
end
