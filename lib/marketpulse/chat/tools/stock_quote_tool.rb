# frozen_string_literal: true

module MarketPulse
  module Chat
    module Tools
      # PORO: não herda de nada, só cumpre o contrato (ADR-002).
      class StockQuoteTool
        def initialize(market_client:)
          @market_client = market_client
        end

        def name = "get_stock_quote"

        def description
          "Retorna o preço atual, a variação percentual do dia e o volume de uma ação. " \
            "Use quando o usuário perguntar sobre cotação, preço ou desempenho diário de um ativo."
        end

        def input_schema
          {
            type: "object",
            properties: { ticker: { type: "string", description: "Ticker em maiúsculas, ex.: AAPL, PETR4" } },
            required: ["ticker"]
          }
        end

        def execute(input)
          @market_client.quote(input.fetch("ticker").strip.upcase)
        end
      end
    end
  end
end
