# frozen_string_literal: true

require_relative "../forecast"

module MarketPulse
  module Forecasting
    module Repositories
      # Mesmo contrato do MemoryForecastRepository, no PostgreSQL.
      class PostgresForecastRepository
        COLUMNS = Forecast.members

        def initialize(db)
          @table = db[:forecasts]
        end

        def save(forecast)
          row = forecast.to_h
          @table.insert_conflict(target: %i[ticker as_of model],
                                 update: (COLUMNS - %i[ticker as_of model]).to_h { |c| [c, Sequel[:excluded][c]] })
                .insert(row)
          forecast
        end

        def latest(ticker)
          row = @table.where(ticker: ticker).order(Sequel.desc(:as_of)).first
          row && to_forecast(row)
        end

        def pending_evaluation(ticker)
          @table.where(ticker: ticker, actual_close: nil).all.map { |r| to_forecast(r) }
        end

        def record_actual(forecast, actual_close)
          @table.where(ticker: forecast.ticker, as_of: forecast.as_of, model: forecast.model)
                .update(actual_close: actual_close)
        end

        def evaluated(ticker, limit: 30)
          @table.where(ticker: ticker).exclude(actual_close: nil)
                .order(Sequel.desc(:as_of)).limit(limit).all.reverse.map { |r| to_forecast(r) }
        end

        private

        FLOATS = %i[weight t_stat last_close predicted_return predicted_close low high mae baseline_mae hit_rate].freeze

        def to_forecast(row)
          attrs = COLUMNS.to_h { |c| [c, row[c]] }
          FLOATS.each { |c| attrs[c] = attrs[c].to_f }
          attrs[:actual_close] = attrs[:actual_close]&.to_f
          Forecast.new(**attrs)
        end
      end
    end
  end
end
