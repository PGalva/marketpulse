# frozen_string_literal: true

module MarketPulse
  module Forecasting
    # Uma previsão salva. `actual_close` começa nil e é preenchido pelo job
    # no pregão seguinte: é assim que nasce o placar de acertos e erros.
    Forecast = Data.define(
      :ticker, :as_of, :model, :weight, :t_stat, :pattern,
      :last_close, :predicted_return, :predicted_close, :low, :high,
      :mae, :baseline_mae, :hit_rate, :n_tests,
      :actual_close, :created_at
    ) do
      def evaluated? = !actual_close.nil?

      def actual_return = evaluated? ? (actual_close / last_close) - 1 : nil

      def direction_hit?
        return nil unless evaluated? && !predicted_return.zero?

        predicted_return.positive? == actual_return.positive?
      end

      def inside_range? = evaluated? ? actual_close.between?(low, high) : nil
    end
  end
end
