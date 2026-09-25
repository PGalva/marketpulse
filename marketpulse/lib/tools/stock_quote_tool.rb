# frozen_string_literal: true

module Tools
  # Um objeto Ruby comum (PORO). Não herda de nada: basta cumprir o contrato.
  class StockQuoteTool
    def initialize(market_client:)
      @market_client = market_client
    end

    def name = "get_stock_quote"

    # O Claude lê esta descrição para decidir QUANDO chamar a tool.
    # Descrições claras = escolhas melhores do modelo.
    def description
      "Retorna o preço atual, a variação percentual do dia e o volume de uma ação. " \
        "Use sempre que o usuário perguntar sobre cotação, preço ou desempenho diário de um ativo."
    end

    def input_schema
      {
        type: "object",
        properties: {
          ticker: { type: "string", description: "Ticker do ativo em maiúsculas, ex.: AAPL, PETR4" }
        },
        required: ["ticker"]
      }
    end

    # O input chega do modelo com chaves String (vem de JSON).
    def execute(input)
      @market_client.quote(input.fetch("ticker").upcase)
    end
  end
end
