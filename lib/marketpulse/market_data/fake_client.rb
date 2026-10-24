# frozen_string_literal: true

require "time"
require_relative "bar"

module MarketPulse
  module MarketData
    # Dados simulados e DETERMINÍSTICOS (mesma semente, mesma série).
    #
    # Cada ticker tem uma "personalidade" escondida no coeficiente `phi`,
    # para que o exercício de previsão tenha algo a descobrir:
    #   retorno_amanhã = phi × retorno_hoje + ruído
    #   AAPL  phi > 0  → momentum
    #   PETR4 phi < 0  → reversão à média
    #   MSFT  phi = 0  → passeio aleatório (nada a prever)
    # O treino do modelo de um peso deve "redescobrir" esses valores.
    class FakeClient
      PROFILES = {
        "AAPL" => { start: 180.0, phi: 0.25, vol: 0.015, currency: "USD", seed: 11 },
        "MSFT" => { start: 400.0, phi: 0.0, vol: 0.012, currency: "USD", seed: 22 },
        "PETR4" => { start: 36.0, phi: -0.30, vol: 0.020, currency: "BRL", seed: 33 }
      }.freeze

      def initialize(today: Date.today, days: 500)
        @today = today
        @days = days
      end

      def name = "fake"

      def tickers = PROFILES.keys

      def history(ticker, days: @days)
        bars = series(ticker)
        bars.last(days)
      end

      def quote(ticker)
        last, previous = series(ticker).last(2).reverse
        {
          ticker: ticker,
          price: last.close,
          change_pct: (((last.close / previous.close) - 1) * 100).round(2),
          volume: last.volume,
          currency: profile(ticker)[:currency],
          source: name,
          as_of: last.date.iso8601,
          fetched_at: Time.now.utc.iso8601
        }
      end

      private

      def profile(ticker)
        PROFILES.fetch(ticker) { raise TickerNotFound, "Ticker #{ticker} não encontrado" }
      end

      def series(ticker)
        @cache ||= {}
        @cache[ticker] ||= generate(ticker, profile(ticker))
      end

      def generate(ticker, p)
        rng = Random.new(p[:seed])
        dates = trading_days
        price = p[:start]
        last_return = 0.0
        dates.map do |date|
          shock = gaussian(rng) * p[:vol]
          ret = (p[:phi] * last_return) + shock
          open = price
          price = (price * (1 + ret)).round(2)
          last_return = ret
          high = [open, price].max * (1 + (rng.rand * 0.005))
          low = [open, price].min * (1 - (rng.rand * 0.005))
          Bar.new(ticker: ticker, date: date, open: open.round(2), high: high.round(2), low: low.round(2),
                  close: price, volume: (rng.rand(20_000_000..60_000_000)))
        end
      end

      # Dias úteis (segunda a sexta) terminando em @today.
      def trading_days
        days = []
        date = @today
        while days.size < @days
          days.unshift(date) unless date.saturday? || date.sunday?
          date -= 1
        end
        days
      end

      # Normal padrão via Box-Muller.
      def gaussian(rng)
        Math.sqrt(-2 * Math.log(1 - rng.rand)) * Math.cos(2 * Math::PI * rng.rand)
      end
    end
  end
end
