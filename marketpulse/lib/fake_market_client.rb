# frozen_string_literal: true

require "time"

# Dados fixos para a fase 1: permite testar o loop sem depender de API externa.
# Como a tool recebe o cliente por injeção, trocar por um cliente real depois
# não exige mudar nada na tool nem no agente (duck typing de novo).
class FakeMarketClient
  class TickerNotFound < StandardError; end

  QUOTES = {
    "AAPL"  => { price: 228.40, change_pct: 1.25,  volume: 52_300_000, currency: "USD" },
    "MSFT"  => { price: 431.10, change_pct: -0.48, volume: 18_900_000, currency: "USD" },
    "PETR4" => { price: 38.52,  change_pct: -1.12, volume: 41_200_000, currency: "BRL" }
  }.freeze

  def quote(ticker)
    data = QUOTES.fetch(ticker) { raise TickerNotFound, "Ticker #{ticker} não encontrado" }
    { ticker: ticker, **data, source: "fake", fetched_at: Time.now.utc.iso8601 }
  end
end
