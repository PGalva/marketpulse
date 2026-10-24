# frozen_string_literal: true

require_relative "../bar"

module MarketPulse
  module MarketData
    module Repositories
      # Mesmo contrato do MemoryPriceRepository, guardando no PostgreSQL.
      # Todo o SQL de preços mora aqui e em nenhum outro lugar.
      class PostgresPriceRepository
        def initialize(db)
          @db = db
          @table = db[:price_bars]
        end

        # Upsert: ON CONFLICT (ticker, date) DO UPDATE. Rodar o job duas
        # vezes no mesmo dia deixa o banco igual (idempotência).
        def save_bars(bars)
          rows = bars.map(&:to_h)
          return 0 if rows.empty?

          @table.insert_conflict(target: %i[ticker date],
                                 update: { open: Sequel[:excluded][:open], high: Sequel[:excluded][:high],
                                           low: Sequel[:excluded][:low], close: Sequel[:excluded][:close],
                                           volume: Sequel[:excluded][:volume] })
                .multi_insert(rows)
          rows.size
        end

        def history(ticker, limit: nil)
          query = @table.where(ticker: ticker).order(Sequel.desc(:date))
          query = query.limit(limit) if limit
          query.all.reverse.map { |row| to_bar(row) }
        end

        def bar_after(ticker, date)
          row = @table.where(ticker: ticker).where(Sequel[:date] > date).order(:date).first
          row && to_bar(row)
        end

        def tickers = @table.distinct.select_map(:ticker).sort

        private

        def to_bar(row)
          Bar.new(ticker: row[:ticker], date: row[:date], open: row[:open].to_f, high: row[:high].to_f,
                  low: row[:low].to_f, close: row[:close].to_f, volume: row[:volume].to_i)
        end
      end
    end
  end
end
