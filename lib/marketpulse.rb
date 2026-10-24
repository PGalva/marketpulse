# frozen_string_literal: true

require_relative "marketpulse/market_data"
require_relative "marketpulse/forecasting"
require_relative "marketpulse/llm"
require_relative "marketpulse/chat"

# Raiz de composição: o ÚNICO lugar que conhece todos os módulos e decide,
# a partir do ambiente (.env), quais implementações conectar.
# Os módulos em si não sabem uns dos outros além do permitido no ADR-004.
module MarketPulse
  MIGRATIONS = File.expand_path("../db/migrations", __dir__)

  # Repositórios: Postgres quando DATABASE_URL existe, memória caso contrário.
  Storage = Data.define(:prices, :forecasts, :kind) do
    def self.build(env = ENV)
      url = env["DATABASE_URL"].to_s
      return memory if url.empty?

      db = connect(url)
      Storage.new(prices: MarketData::Repositories::PostgresPriceRepository.new(db),
                  forecasts: Forecasting::Repositories::PostgresForecastRepository.new(db),
                  kind: :postgres)
    end

    def self.memory
      Storage.new(prices: MarketData::Repositories::MemoryPriceRepository.new,
                  forecasts: Forecasting::Repositories::MemoryForecastRepository.new,
                  kind: :memory)
    end

    # Carregado sob demanda: sem DATABASE_URL o projeto não precisa de gems.
    def self.connect(url)
      require "sequel"
      require_relative "marketpulse/market_data/repositories/postgres_price_repository"
      require_relative "marketpulse/forecasting/repositories/postgres_forecast_repository"
      Sequel.extension :migration
      db = Sequel.connect(url)
      Sequel::Migrator.run(db, MIGRATIONS) # migrações idempotentes a cada boot
      db
    end

    def memory? = kind == :memory
  end

  def self.market_client(env = ENV) = MarketData.build_client(env)

  def self.tickers(client, env = ENV)
    configured = env["TICKERS"].to_s.split(",").map { |t| t.strip.upcase }.reject(&:empty?)
    return configured unless configured.empty?

    client.respond_to?(:tickers) ? client.tickers : %w[AAPL MSFT]
  end

  def self.daily_job(storage:, client: market_client, env: ENV, logger: $stdout)
    Forecasting::DailyJob.new(client: client, prices: storage.prices, forecasts: storage.forecasts,
                              tickers: tickers(client, env), logger: logger)
  end

  def self.registry(storage:, client: market_client)
    Chat::Tools::Registry.new
                         .register(Chat::Tools::StockQuoteTool.new(market_client: client))
                         .register(Chat::Tools::ForecastPriceTool.new(forecasts: storage.forecasts))
  end
end
