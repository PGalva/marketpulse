# frozen_string_literal: true

require "net/http"
require "csv"
require "time"
require_relative "bar"

module MarketPulse
  module MarketData
    # Histórico diário real e gratuito, sem chave, via CSV do Stooq.
    # Uso educacional. Ações dos EUA usam o sufixo ".us" (aapl.us).
    #
    # Mesmo contrato do FakeClient (duck typing): name, history, quote.
    # Trocar de fonte de dados é trocar o objeto, não o código que o usa.
    class StooqClient
      URL = "https://stooq.com/q/d/l/"

      def initialize(suffix: ".us", fetcher: method(:fetch_csv))
        @suffix = suffix
        @fetcher = fetcher
      end

      def name = "stooq"

      def history(ticker, days: 500)
        csv = @fetcher.call(symbol(ticker))
        bars = parse(ticker, csv)
        raise TickerNotFound, "Sem dados para #{ticker} no Stooq" if bars.empty?

        bars.last(days)
      end

      def quote(ticker)
        last, previous = history(ticker, days: 2).reverse
        {
          ticker: ticker, price: last.close,
          change_pct: previous ? (((last.close / previous.close) - 1) * 100).round(2) : 0.0,
          volume: last.volume, currency: "USD", source: name,
          as_of: last.date.iso8601, fetched_at: Time.now.utc.iso8601
        }
      end

      # Público para ser testado com um CSV de fixture, sem rede.
      def parse(ticker, csv)
        CSV.parse(csv.to_s, headers: true).filter_map do |row|
          next unless row["Close"] && row["Date"]

          Bar.new(ticker: ticker, date: Date.parse(row["Date"]),
                  open: row["Open"].to_f, high: row["High"].to_f, low: row["Low"].to_f,
                  close: row["Close"].to_f, volume: row["Volume"].to_i)
        end
      rescue CSV::MalformedCSVError, Date::Error
        []
      end

      private

      def symbol(ticker) = "#{ticker.downcase}#{@suffix}"

      def fetch_csv(symbol)
        uri = URI(URL)
        uri.query = URI.encode_www_form(s: symbol, i: "d")
        response = Net::HTTP.get_response(uri)
        raise Error, "Stooq respondeu HTTP #{response.code}" unless response.is_a?(Net::HTTPSuccess)

        response.body
      rescue SocketError, SystemCallError, Net::OpenTimeout, Net::ReadTimeout => e
        raise Error, "Falha de rede no Stooq: #{e.message}"
      end
    end
  end
end
