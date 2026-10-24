# frozen_string_literal: true

require "date"

module MarketPulse
  # Camada base do sistema: busca e guarda dados de mercado.
  # Não depende de nenhum outro módulo do MarketPulse (ADR-004).
  module MarketData
    class Error < StandardError; end
    class TickerNotFound < Error; end

    # Um pregão (candle diário): abertura, máxima, mínima, fechamento, volume.
    Bar = Data.define(:ticker, :date, :open, :high, :low, :close, :volume)
  end
end
