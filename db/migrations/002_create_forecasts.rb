# frozen_string_literal: true

# Previsões e o placar. actual_close é preenchido no pregão seguinte.
Sequel.migration do
  up do
    create_table?(:forecasts) do
      String :ticker, null: false
      Date :as_of, null: false
      String :model, null: false
      Float :weight, null: false
      Float :t_stat, null: false
      String :pattern, null: false
      Float :last_close, null: false
      Float :predicted_return, null: false
      Float :predicted_close, null: false
      Float :low, null: false
      Float :high, null: false
      Float :mae, null: false
      Float :baseline_mae, null: false
      Float :hit_rate, null: false
      Integer :n_tests, null: false
      Float :actual_close
      Time :created_at, null: false
      primary_key %i[ticker as_of model]
      index %i[ticker actual_close]
    end
  end

  down do
    drop_table?(:forecasts)
  end
end
