# frozen_string_literal: true

require "json"
require_relative "../types"

module MarketPulse
  module LLM
    module Providers
      # Um "modelo" sem rede, sem chave e sem custo, guiado por regras.
      # Serve para rodar e testar o sistema inteiro offline e como último
      # recurso no FallbackRouter. Fala o formato neutro como os outros.
      #
      # Regras:
      # - Último item é ToolResults → resume os resultados em texto.
      # - Pergunta com ticker em MAIÚSCULAS (AAPL, PETR4):
      #     * fala em previsão/prever/forecast → forecast_price
      #     * caso contrário                    → get_stock_quote
      # - Sem ticker → pede um ticker.
      class Offline
        TICKER = /\b[A-Z]{3,5}\d{0,2}\b/
        FORECAST_WORDS = /previs|prever|forecast|amanh/i

        def name = "offline"
        def model = "regras-locais"

        def chat(messages:, tools:, system: nil)
          last = messages.last
          return Response.new(text: summarize(last.results), tool_calls: []) if last.is_a?(Messages::ToolResults)

          text = last.respond_to?(:text) ? last.text.to_s : ""
          tickers = text.scan(TICKER).uniq
          return Response.new(text: "[offline] Não encontrei um ticker. Tente: Como está a AAPL?", tool_calls: []) if tickers.empty?

          tool = pick_tool(text, tools.map(&:name))
          return Response.new(text: "[offline] Nenhuma tool disponível para isso.", tool_calls: []) unless tool

          calls = tickers.each_with_index.map do |ticker, i|
            ToolCall.new(id: "offline_#{i}", name: tool, input: { "ticker" => ticker })
          end
          Response.new(text: nil, tool_calls: calls)
        end

        private

        def pick_tool(text, available)
          wanted = text.match?(FORECAST_WORDS) ? "forecast_price" : "get_stock_quote"
          available.include?(wanted) ? wanted : available.first
        end

        def summarize(results)
          lines = results.map do |r|
            next "- Erro: #{r.content}" if r.error

            data = JSON.parse(r.content)
            data["predicted_return_pct"] ? forecast_line(data) : quote_line(data)
          rescue JSON::ParserError
            "- #{r.content}"
          end
          "[offline] Resultado das tools:\n#{lines.join("\n")}"
        end

        def quote_line(d)
          "- #{d['ticker']}: #{d['currency']} #{d['price']} (#{format('%+.2f', d['change_pct'].to_f)}% no dia)"
        end

        def forecast_line(d)
          "- #{d['ticker']}: previsão #{format('%+.2f', d['predicted_return_pct'])}% para o próximo pregão " \
            "(faixa #{d['range']['low']}–#{d['range']['high']}); padrão: #{d['pattern']}; " \
            "o modelo #{d.dig('backtest', 'beats_baseline') ? 'superou' : 'NÃO superou'} o baseline."
        end
      end
    end
  end
end
