# frozen_string_literal: true

require_relative "market_data/bar"
require_relative "market_data/fake_client"
require_relative "market_data/stooq_client"
require_relative "market_data/repositories/memory_price_repository"
# O repositório Postgres é carregado sob demanda (MarketPulse::Storage),
# para o projeto rodar sem gems quando não há banco.

module MarketPulse
  module MarketData
    # MARKET_DATA_SOURCE: fake (padrão) | stooq
    def self.build_client(env = ENV)
      case env.fetch("MARKET_DATA_SOURCE", "fake")
      when "fake" then FakeClient.new
      when "stooq" then StooqClient.new
      else raise Error, "MARKET_DATA_SOURCE desconhecido: #{env['MARKET_DATA_SOURCE']}. Use fake ou stooq"
      end
    end
  end
end
