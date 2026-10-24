# frozen_string_literal: true

module MarketPulse
  # Previsão de retorno como EXPERIMENTO mensurável (ADR-004).
  # Depende só de market_data. Não conhece LLM nem chat: o job que treina
  # os modelos roda sem nenhuma IA e sem gastar tokens.
  module Forecasting
    class Error < StandardError; end

    module Features
      module_function

      # Retornos diários simples: (P_t / P_{t-1}) - 1.
      # Prevemos retornos, não preços: retornos são comparáveis entre ações
      # de R$ 36 e US$ 400, e oscilam em torno de zero.
      def returns(closes)
        closes.each_cons(2).map { |previous, current| (current / previous) - 1 }
      end

      def stddev(values)
        return 0.0 if values.size < 2

        mean = values.sum / values.size
        Math.sqrt(values.sum { |v| (v - mean)**2 } / (values.size - 1))
      end
    end
  end
end
