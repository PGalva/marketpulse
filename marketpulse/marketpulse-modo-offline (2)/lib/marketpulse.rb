# frozen_string_literal: true

require "fake_market_client"
require "tools/registry"
require "tools/stock_quote_tool"

# Ponto único que monta as peças do projeto.
# bin/chat e bin/tool usam o mesmo registry, então testar uma tool
# manualmente é testar exatamente o que o agente vai usar.
module MarketPulse
  def self.registry
    Tools::Registry.new
      .register(Tools::StockQuoteTool.new(market_client: FakeMarketClient.new))
  end
end
