# frozen_string_literal: true

require_relative "../features"

module MarketPulse
  module Forecasting
    module Models
      # Classificador de DIREÇÃO: qual a probabilidade de o próximo pregão
      # fechar em alta? (ADR-005)
      #
      # É uma regressão logística, o classificador linear mais simples:
      #
      #   z     = viés + Σ(peso_k × feature_k)
      #   P(up) = 1 / (1 + e^-z)          ← a sigmoide espreme z entre 0 e 1
      #
      # TREINAR = ajustar os pesos para que P(up) fique perto de 1 nos dias que
      # subiram e perto de 0 nos que caíram. Não há fórmula fechada como no
      # OneWeight, então descemos o gradiente da perda (log loss) aos poucos.
      #
      # O tutorial usa Random Forest (scikit-learn). Aqui fica a logística em
      # Ruby puro: cabe em uma tela, é determinística e os pesos são legíveis.
      # O contrato (fit/predict_proba) permite trocar o modelo depois.
      class LogisticDirection
        attr_reader :weights, :bias, :n

        def initialize(iterations: 150, learning_rate: 0.3, l2: 0.01)
          @iterations = iterations
          @learning_rate = learning_rate
          @l2 = l2 # penaliza pesos grandes: com pouco sinal, prefere pesos ~0
        end

        def name = "logistic_direction"

        # rows: Features::Row rotuladas (up não nil)
        def fit(rows)
          raise Error, "Poucos dados para treinar a direção (#{rows.size} linhas)" if rows.size < 30

          x = rows.map(&:values)
          y = rows.map { |r| r.up ? 1.0 : 0.0 }
          standardize_fit(x)
          xs = x.map { |v| standardize(v) }

          k = xs.first.size
          @weights = Array.new(k, 0.0)
          @bias = 0.0
          m = xs.size.to_f

          # Laços com `while` em vez de each/map: este é o trecho mais quente do
          # job (centenas de iterações × centenas de linhas por re-treino).
          @iterations.times do
            grad_w = Array.new(k, 0.0)
            grad_b = 0.0
            i = 0
            while i < xs.size
              v = xs[i]
              error = sigmoid(dot(v)) - y[i] # derivada da log loss em relação a z
              j = 0
              while j < k
                grad_w[j] += error * v[j]
                j += 1
              end
              grad_b += error
              i += 1
            end
            k.times { |j| @weights[j] -= @learning_rate * ((grad_w[j] / m) + (@l2 * @weights[j])) }
            @bias -= @learning_rate * grad_b / m
          end
          @n = rows.size
          self
        end

        def predict_proba(values)
          raise Error, "Modelo não treinado: chame fit antes" unless @weights

          sigmoid(dot(standardize(values)))
        end

        private

        # Cada feature vira (valor - média) / desvio, com média e desvio do
        # TREINO. Assim todas ficam na mesma escala e o gradiente converge.
        def standardize_fit(x)
          columns = x.transpose
          @means = columns.map { |c| c.sum / c.size }
          @stds = columns.map { |c| s = Features.stddev(c); s.zero? ? 1.0 : s }
        end

        def standardize(values) = values.each_with_index.map { |v, j| (v - @means[j]) / @stds[j] }

        def dot(v)
          z = @bias
          j = 0
          while j < v.size
            z += v[j] * @weights[j]
            j += 1
          end
          z
        end

        def sigmoid(z) = 1.0 / (1.0 + Math.exp(-z.clamp(-30, 30)))
      end
    end
  end
end
