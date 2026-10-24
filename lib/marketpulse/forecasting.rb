# frozen_string_literal: true

# Regra de arquitetura (ADR-004): forecasting depende só de market_data.
# Um teste em test/architecture_test.rb garante que nenhum arquivo daqui
# carregue llm ou chat.
require_relative "market_data"
require_relative "forecasting/features"
require_relative "forecasting/models/naive"
require_relative "forecasting/models/one_weight"
require_relative "forecasting/models/logistic_direction"
require_relative "forecasting/backtest"
require_relative "forecasting/direction"
require_relative "forecasting/forecast"
require_relative "forecasting/repositories/memory_forecast_repository"
require_relative "forecasting/daily_job"
