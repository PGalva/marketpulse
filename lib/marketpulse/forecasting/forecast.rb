# frozen_string_literal: true

require_relative "direction"

module MarketPulse
  module Forecasting
    # Uma previsão salva. `actual_close` começa nil e é preenchido pelo job
    # no pregão seguinte: é assim que nasce o placar de acertos e erros.
    #
    # Duas previsões convivem na mesma linha:
    # - TAMANHO do retorno (OneWeight): predicted_return, faixa low..high
    # - DIREÇÃO (LogisticDirection, ADR-005): prob_up e direction_signal.
    #   Os campos direction_* ficam nil quando a série é curta demais.
    Forecast = Data.define(
      :ticker, :as_of, :model, :weight, :t_stat, :pattern,
      :last_close, :predicted_return, :predicted_close, :low, :high,
      :mae, :baseline_mae, :hit_rate, :n_tests,
      :prob_up, :direction_signal, :direction_threshold,
      :direction_precision, :direction_signals, :direction_up_rate, :direction_n_tests,
      :actual_close, :created_at
    ) do
      def evaluated? = !actual_close.nil?

      def actual_return = evaluated? ? (actual_close / last_close) - 1 : nil

      def direction_hit?
        return nil unless evaluated? && !predicted_return.zero?

        predicted_return.positive? == actual_return.positive?
      end

      def inside_range? = evaluated? ? actual_close.between?(low, high) : nil

      def direction? = !prob_up.nil?

      # Reconstrói o backtest de direção a partir das colunas salvas, para que
      # job e tool usem o MESMO critério de vitória sobre o baseline.
      def direction_backtest
        return nil unless direction?

        Direction::Backtest.new(precision: direction_precision, signals: direction_signals,
                                up_rate: direction_up_rate, n_tests: direction_n_tests)
      end

      # Placar da DIREÇÃO: só conta os dias em que o modelo disse "alta".
      # nil quando não houve sinal ou a previsão ainda não foi avaliada.
      def up_signal_hit?
        return nil unless evaluated? && direction_signal == Direction::UP

        actual_close > last_close
      end
    end
  end
end
