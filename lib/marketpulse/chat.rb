# frozen_string_literal: true

# chat é o topo da pirâmide: pode depender de llm, forecasting e market_data.
require_relative "llm"
require_relative "chat/tools/registry"
require_relative "chat/tools/stock_quote_tool"
require_relative "chat/tools/forecast_price_tool"
require_relative "chat/agent"
