# frozen_string_literal: true

require_relative "features"
require_relative "models/logistic_direction"

module MarketPulse
  module Forecasting
    # Previsão de DIREÇÃO (sobe ou não sobe amanhã), inspirada no tutorial
    # "Predict The Stock Market With Machine Learning And Python" (Dataquest).
    # Complementa o OneWeight, que prevê o TAMANHO do retorno (ADR-005).
    #
    # Três ideias do tutorial:
    #   1. Features em vários horizontes (Features.horizon_rows).
    #   2. Só dizer "alta" quando a probabilidade passa de um THRESHOLD (0,6):
    #      o modelo fala menos vezes, mas cada sinal vale mais.
    #   3. Medir com PRECISÃO (dos dias em que disse "alta", quantos subiram?)
    #      contra o baseline "% de dias que sobem": dizer "alta" todo dia já
    #      acerta isso de graça.
    module Direction
      UP = "alta"
      NONE = "sem sinal"

      # Com menos sinais que isso no backtest, nem vale calcular.
      MIN_SIGNALS = 10

      # Mesmo critério do |t| >= 2 do OneWeight: a vantagem sobre o baseline
      # precisa ser maior que 2 erros-padrão para não ser confundida com sorte.
      SIGNIFICANCE = 2.0

      Backtest = Data.define(:precision, :signals, :up_rate, :n_tests) do
        def conclusive? = signals >= MIN_SIGNALS

        # Quantos erros-padrão a precisão está acima do baseline.
        # Se o modelo não soubesse nada, seus sinais acertariam na mesma taxa
        # dos dias de alta (up_rate), com erro-padrão sqrt(p(1-p)/sinais).
        def z
          return nil unless conclusive?

          standard_error = Math.sqrt(up_rate * (1 - up_rate) / signals)
          standard_error.zero? ? 0.0 : (precision - up_rate) / standard_error
        end

        def beats_baseline? = conclusive? && z >= SIGNIFICANCE

        def verdict
          return "inconclusivo (só #{signals} sinais de alta no backtest)" unless conclusive?
          return "superou o baseline (z=#{format('%+.1f', z)})" if beats_baseline?
          return "acima do baseline, mas pode ser sorte (z=#{format('%+.1f', z)})" if precision > up_rate

          "não superou o baseline"
        end
      end

      Result = Data.define(:prob_up, :signal, :threshold, :backtest)

      module_function

      # closes: fechamentos em ordem cronológica. Treina com tudo que tem
      # rótulo, mede com backtest e prevê o próximo pregão a partir de hoje.
      def run(closes, horizons: Features::DEFAULT_HORIZONS, threshold: 0.6, min_train: 120, step: 20,
              model_factory: -> { Models::LogisticDirection.new })
        rows = Features.horizon_rows(closes, horizons: horizons)
        labeled = rows.select(&:labeled?)
        today = rows.last
        raise Error, "Sem a linha de hoje para prever" if today.labeled?

        backtest = walk_forward(labeled, threshold: threshold, min_train: min_train, step: step,
                                         model_factory: model_factory)
        prob = model_factory.call.fit(labeled).predict_proba(today.values)
        Result.new(prob_up: prob, signal: prob >= threshold ? UP : NONE, threshold: threshold, backtest: backtest)
      end

      # Walk-forward como no tutorial: treina com as primeiras `min_train`
      # linhas, prevê as próximas `step`, inclui essas no treino e repete.
      # Re-treinar a cada `step` dias (e não todo dia) deixa o job rápido.
      #
      #   linhas: 0 ........ s | s .. s+step | s+step ..
      #   treino: ██████████ → prevê ░░░░░ → treino cresce → prevê ░░░░░
      def walk_forward(rows, threshold:, min_train:, step:, model_factory:)
        raise Error, "Série curta demais para o backtest de direção (#{rows.size} linhas)" if rows.size <= min_train

        signals = 0
        hits = 0
        ups = 0
        (min_train...rows.size).step(step) do |start|
          model = model_factory.call.fit(rows[0...start]) # só linhas ANTES do bloco de teste
          rows[start, step].each do |row|
            ups += 1 if row.up
            next unless model.predict_proba(row.values) >= threshold

            signals += 1
            hits += 1 if row.up
          end
        end

        n_tests = rows.size - min_train
        Backtest.new(precision: signals.zero? ? nil : hits.to_f / signals, signals: signals,
                     up_rate: ups.to_f / n_tests, n_tests: n_tests)
      end
    end
  end
end
