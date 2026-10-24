# frozen_string_literal: true

# Séries de preço (OHLCV). Uma linha por ticker por pregão.
Sequel.migration do
  up do
    create_table?(:price_bars) do
      String :ticker, null: false
      Date :date, null: false
      BigDecimal :open, size: [14, 4], null: false
      BigDecimal :high, size: [14, 4], null: false
      BigDecimal :low, size: [14, 4], null: false
      BigDecimal :close, size: [14, 4], null: false
      Bignum :volume, null: false
      primary_key %i[ticker date] # garante a idempotência do upsert
    end
  end

  down do
    drop_table?(:price_bars)
  end
end
