# frozen_string_literal: true

require_relative "test_helper"
require_relative "market_data/market_data_test"

# Roda só quando há banco (DATABASE_URL): no CI e no Docker.
# Os repositórios Postgres precisam provar O MESMO comportamento dos de
# memória, por isso incluem os mesmos módulos de contrato.
if ENV["DATABASE_URL"].to_s.empty?
  warn "[postgres_test] DATABASE_URL ausente: testes de Postgres pulados."
else
  module PostgresTestSetup
    def setup
      @storage = MarketPulse::Storage.build
      @db = Sequel::DATABASES.last
      @db[:forecasts].delete
      @db[:price_bars].delete
    end
  end

  class PostgresPriceRepositoryTest < Minitest::Test
    include PostgresTestSetup
    include PriceRepositoryContract

    def repo = @storage.prices
  end

  class PostgresForecastRepositoryTest < Minitest::Test
    include PostgresTestSetup

    def job_on(day)
      client = MarketPulse::MarketData::FakeClient.new(today: day, days: 300)
      MarketPulse::Forecasting::DailyJob.new(client: client, prices: @storage.prices, forecasts: @storage.forecasts,
                                             tickers: %w[AAPL], logger: nil)
    end

    def test_job_idempotente_e_placar_no_banco
      2.times { job_on(Date.new(2026, 10, 21)).run }
      assert_equal 1, @db[:forecasts].count

      job_on(Date.new(2026, 10, 22)).run
      evaluated = @storage.forecasts.evaluated("AAPL")

      assert_equal 1, evaluated.size
      assert_kind_of Float, evaluated.first.actual_close
      assert_equal Date.new(2026, 10, 22), @storage.forecasts.latest("AAPL").as_of
    end
  end
end
