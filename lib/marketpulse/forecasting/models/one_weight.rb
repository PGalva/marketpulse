# frozen_string_literal: true

require_relative "../features"

module MarketPulse
  module Forecasting
    module Models
      # O modelo de um peso:  retorno_amanhã = peso × retorno_hoje
      #
      # TREINAR = achar o peso que faz o modelo errar menos no passado.
      # Por mínimos quadrados há uma fórmula fechada:
      #
      #   peso = Σ(hoje × amanhã) / Σ(hoje²)
      #
      # peso > 0 → momentum (subiu, tende a continuar subindo)
      # peso < 0 → reversão à média (subiu, tende a devolver)
      # peso ≈ 0 → passeio aleatório (o passado não ajuda)
      class OneWeight
        # |t| acima disso: o peso é estatisticamente diferente de zero
        # (aprox. 95% de confiança). Abaixo, pode ser só ruído.
        SIGNIFICANCE = 2.0

        attr_reader :weight, :residual_std, :t_stat, :n

        def name = "one_weight"

        def fit(returns)
          pairs = returns.each_cons(2).to_a
          raise Error, "Poucos dados para treinar (#{pairs.size} pares)" if pairs.size < 10

          sum_xy = pairs.sum { |today, tomorrow| today * tomorrow }
          sum_xx = pairs.sum { |today, _| today**2 }
          @weight = sum_xx.zero? ? 0.0 : sum_xy / sum_xx

          residuals = pairs.map { |today, tomorrow| tomorrow - (@weight * today) }
          @residual_std = Features.stddev(residuals)
          standard_error = sum_xx.zero? ? Float::INFINITY : @residual_std / Math.sqrt(sum_xx)
          @t_stat = standard_error.zero? ? 0.0 : @weight / standard_error
          @n = pairs.size
          self
        end

        def predict(last_return)
          raise Error, "Modelo não treinado: chame fit antes" unless @weight

          @weight * last_return
        end

        def pattern
          return "sem padrão significativo (passeio aleatório)" if @t_stat.abs < SIGNIFICANCE

          @weight.positive? ? "momentum" : "reversão à média"
        end
      end
    end
  end
end
