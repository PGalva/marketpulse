# frozen_string_literal: true

module MarketPulse
  module Forecasting
    module Models
      # Baseline "amanhã = hoje": prevê retorno zero (o preço não muda).
      # Todo modelo precisa vencer este para valer alguma coisa.
      class Naive
        def name = "naive"
        def fit(_returns) = self
        def predict(_last_return) = 0.0
      end
    end
  end
end
