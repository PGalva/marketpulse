# frozen_string_literal: true

require "json"

# Um "Claude" falso, sem rede e sem chave, para rodar o chat localmente.
# Ele responde no MESMO formato JSON da API real, então o Agent nem percebe
# a diferença. É duck typing de novo: basta ter o método `create`.
#
# Regras simples:
# - Mensagem do usuário com um ticker em MAIÚSCULAS (AAPL, PETR4) → pede get_stock_quote.
#   (Sem isso, palavras como "COMO" virariam ticker.)
# - Chegou um tool_result → resume o resultado em texto.
# - Sem ticker → responde que não sabe o que buscar.
class OfflineClaude
  TICKER = /\b[A-Z]{3,5}\d{0,2}\b/

  def create(messages:, tools:, system:)
    last = messages.last

    if tool_results?(last)
      text_response(summarize(last[:content]))
    elsif (tickers = last[:content].to_s.scan(TICKER).uniq).any?
      tool_use_response(tickers)
    else
      text_response("[offline] Não encontrei um ticker na pergunta. Tente algo como: Como está a AAPL?")
    end
  end

  private

  def tool_results?(message)
    message[:content].is_a?(Array) && message[:content].all? { |b| b[:type] == "tool_result" }
  end

  def tool_use_response(tickers)
    blocks = tickers.each_with_index.map do |ticker, i|
      { "type" => "tool_use", "id" => "offline_#{i}", "name" => "get_stock_quote",
        "input" => { "ticker" => ticker } }
    end
    { "stop_reason" => "tool_use", "content" => blocks }
  end

  def summarize(results)
    lines = results.map do |result|
      next "- Erro: #{result[:content]}" if result[:is_error]

      data = JSON.parse(result[:content])
      "- #{data['ticker']}: #{data['currency']} #{data['price']} (#{format('%+.2f', data['change_pct'])}% no dia)"
    end
    "[offline] Resultado das tools:\n#{lines.join("\n")}"
  end

  def text_response(text)
    { "stop_reason" => "end_turn", "content" => [{ "type" => "text", "text" => text }] }
  end
end
