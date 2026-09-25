# frozen_string_literal: true

require "net/http"
require "json"

# Cliente HTTP mínimo para a API de Messages do Claude.
# Usamos só a stdlib (Net::HTTP + JSON) para enxergar o protocolo "cru":
# é exatamente isso que uma gem faria por baixo dos panos.
class ClaudeClient
  class Error < StandardError; end

  URL = URI("https://api.anthropic.com/v1/messages")

  def initialize(api_key: ENV.fetch("ANTHROPIC_API_KEY"),
                 model: ENV.fetch("CLAUDE_MODEL", "claude-sonnet-5"))
    @api_key = api_key
    @model = model
  end

  # Envia a conversa inteira + a lista de tools e devolve o JSON da resposta.
  # A API não guarda estado: a cada chamada mandamos o histórico completo.
  def create(messages:, tools:, system:)
    request = Net::HTTP::Post.new(URL)
    request["x-api-key"] = @api_key
    request["anthropic-version"] = "2023-06-01"
    request["content-type"] = "application/json"
    request.body = JSON.generate(
      model: @model,
      max_tokens: 1024,
      system: system,
      messages: messages,
      tools: tools
    )

    response = Net::HTTP.start(URL.host, URL.port, use_ssl: true) { |http| http.request(request) }
    body = JSON.parse(response.body)

    unless response.is_a?(Net::HTTPSuccess)
      raise Error, "#{response.code}: #{body.dig('error', 'message')}"
    end

    body
  end
end
