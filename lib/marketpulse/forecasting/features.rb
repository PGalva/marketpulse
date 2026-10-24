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

      # Uma linha da tabela de treino do modelo de direção (ADR-005).
      # `up` é o alvo: o fechamento do pregão SEGUINTE foi maior que o de hoje?
      # Na última linha (hoje) ainda não sabemos: `up` é nil, e é ela que o
      # modelo usa para prever amanhã.
      Row = Data.define(:index, :values, :up) do
        def labeled? = !up.nil?
      end

      DEFAULT_HORIZONS = [2, 5, 20, 60].freeze

      # Features em vários horizontes, como no tutorial do Dataquest:
      #
      #   ratio_h = fechamento_hoje / média dos últimos h fechamentos - 1
      #             (acima da média recente? quanto?)
      #   trend_h = fração de dias de alta entre os últimos h pregões
      #             (quantos dos últimos h dias subiram?)
      #
      # Tudo usa só fechamentos ATÉ hoje (índices <= i). O único dado do
      # futuro é o alvo `up`, que nunca entra em `values`.
      # A linha i só existe quando há passado suficiente para o maior horizonte.
      def horizon_rows(closes, horizons: DEFAULT_HORIZONS)
        longest = horizons.max
        raise Error, "Série curta demais para horizonte de #{longest} dias (#{closes.size} fechamentos)" if closes.size <= longest + 1

        ups = closes.each_cons(2).map { |previous, current| current > previous ? 1.0 : 0.0 } # ups[k]: dia k+1 subiu
        (longest...closes.size).map do |i|
          values = horizons.flat_map do |h|
            window = closes[(i - h + 1)..i]
            ratio = (closes[i] / (window.sum / h)) - 1
            trend = ups[(i - h)...i].sum / h # altas dos dias i-h+1..i
            [ratio, trend]
          end
          up = i + 1 < closes.size ? closes[i + 1] > closes[i] : nil
          Row.new(index: i, values: values, up: up)
        end
      end

      def feature_names(horizons: DEFAULT_HORIZONS)
        horizons.flat_map { |h| ["ratio_#{h}", "trend_#{h}"] }
      end
    end
  end
end
