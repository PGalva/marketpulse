# frozen_string_literal: true

require_relative "../forecast"

module MarketPulse
  module Forecasting
    module Repositories
      # Leitura e escrita de previsões. O job ESCREVE; a tool do chat só LÊ
      # (separação entre escrita e leitura, ADR-004).
      class MemoryForecastRepository
        def initialize
          @rows = {}
        end

        # Idempotente: a chave é (ticker, as_of, model).
        def save(forecast)
          @rows[key(forecast)] = forecast
        end

        def latest(ticker)
          for_ticker(ticker).max_by(&:as_of)
        end

        def pending_evaluation(ticker)
          for_ticker(ticker).reject(&:evaluated?)
        end

        def record_actual(forecast, actual_close)
          @rows[key(forecast)] = forecast.with(actual_close: actual_close)
        end

        def evaluated(ticker, limit: 30)
          for_ticker(ticker).select(&:evaluated?).sort_by(&:as_of).last(limit)
        end

        private

        def key(f) = [f.ticker, f.as_of, f.model]
        def for_ticker(ticker) = @rows.values.select { |f| f.ticker == ticker }
      end
    end
  end
end
