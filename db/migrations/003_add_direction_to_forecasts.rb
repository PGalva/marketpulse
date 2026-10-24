# frozen_string_literal: true

# Previsão de direção (ADR-005). Colunas opcionais: previsões antigas e
# séries curtas demais para o classificador ficam com NULL.
Sequel.migration do
  up do
    alter_table(:forecasts) do
      add_column :prob_up, Float
      add_column :direction_signal, String
      add_column :direction_threshold, Float
      add_column :direction_precision, Float
      add_column :direction_signals, Integer
      add_column :direction_up_rate, Float
      add_column :direction_n_tests, Integer
    end
  end

  down do
    alter_table(:forecasts) do
      %i[prob_up direction_signal direction_threshold direction_precision
         direction_signals direction_up_rate direction_n_tests].each { |c| drop_column c }
    end
  end
end
