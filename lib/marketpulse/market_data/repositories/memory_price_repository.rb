# frozen_string_literal: true

require_relative "../bar"

module MarketPulse
  module MarketData
    module Repositories
      # Padrão Repository: o resto do código pede "o histórico da AAPL" e não
      # sabe onde os dados moram. Esta versão guarda em memória (testes e
      # modo sem banco). A versão Postgres tem exatamente os mesmos métodos.
      class MemoryPriceRepository
        def initialize
          @bars = Hash.new { |h, k| h[k] = {} }
        end

        # Idempotente: salvar o mesmo pregão duas vezes não duplica nada.
        def save_bars(bars)
          bars.each { |bar| @bars[bar.ticker][bar.date] = bar }
          bars.size
        end

        def history(ticker, limit: nil)
          sorted = @bars[ticker].values.sort_by(&:date)
          limit ? sorted.last(limit) : sorted
        end

        def bar_after(ticker, date)
          history(ticker).find { |bar| bar.date > date }
        end

        def tickers = @bars.keys.sort
      end
    end
  end
end
