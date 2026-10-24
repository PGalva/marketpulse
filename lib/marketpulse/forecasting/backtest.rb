# frozen_string_literal: true

module MarketPulse
  module Forecasting
    # Backtest WALK-FORWARD: treina só com o passado, prevê o próximo dia,
    # avança um dia e repete. Nunca usa dado do futuro no treino
    # (o erro clássico chamado look-ahead bias).
    #
    #   dia:    0 1 2 ... i | i+1
    #   treino: ███████████ | → prevê i+1 → compara com o real → avança
    module Backtest
      Result = Data.define(:mae, :baseline_mae, :hit_rate, :n_tests) do
        def beats_baseline = mae < baseline_mae

        def to_h
          { mae_pct: (mae * 100).round(4), baseline_mae_pct: (baseline_mae * 100).round(4),
            hit_rate_pct: (hit_rate * 100).round(1), n_tests: n_tests, beats_baseline: beats_baseline }
        end
      end

      module_function

      # model_factory: algo que responde a `call` e devolve um modelo novo.
      def walk_forward(returns, model_factory:, min_train: 60, baseline: Models::Naive.new)
        raise Error, "Série curta demais para backtest (#{returns.size} retornos)" if returns.size <= min_train + 1

        errors = []
        baseline_errors = []
        hits = 0
        directional = 0

        (min_train...(returns.size - 1)).each do |i|
          train = returns[0..i]
          actual = returns[i + 1]
          predicted = model_factory.call.fit(train).predict(returns[i])

          errors << (predicted - actual).abs
          baseline_errors << (baseline.predict(returns[i]) - actual).abs
          next if predicted.zero? || actual.zero?

          directional += 1
          hits += 1 if (predicted.positive? == actual.positive?)
        end

        Result.new(mae: errors.sum / errors.size,
                   baseline_mae: baseline_errors.sum / baseline_errors.size,
                   hit_rate: directional.zero? ? 0.0 : hits.to_f / directional,
                   n_tests: errors.size)
      end
    end
  end
end
