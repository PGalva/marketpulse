# frozen_string_literal: true

require "json"
require_relative "../types"
require_relative "../http"

module MarketPulse
  module LLM
    module Providers
      # Adaptador para a API de Messages da Anthropic (Claude).
      # Toda a "língua da Anthropic" mora aqui: tool_use, tool_result,
      # stop_reason, system como parâmetro separado.
      class Anthropic
        URL = "https://api.anthropic.com/v1/messages"
        DEFAULT_MODEL = "claude-sonnet-5-5"

        attr_reader :model

        def initialize(api_key:, model: DEFAULT_MODEL, url: URL, http: HTTP, max_tokens: 1024)
          @api_key = api_key
          @model = model
          @url = url
          @http = http
          @max_tokens = max_tokens
        end

        def name = "anthropic"

        def chat(messages:, tools:, system:)
          body = request_body(messages: messages, tools: tools, system: system)
          headers = { "x-api-key" => @api_key, "anthropic-version" => "2023-06-01" }
          parse_response(@http.post_json(@url, body: body, headers: headers))
        end

        # Neutro → Anthropic. Público para os testes conferirem a tradução.
        def request_body(messages:, tools:, system:)
          {
            model: @model,
            max_tokens: @max_tokens,
            system: system,
            messages: messages.map { |message| translate(message) },
            tools: tools.map { |t| { name: t.name, description: t.description, input_schema: t.input_schema } }
          }
        end

        # Anthropic → neutro.
        def parse_response(json)
          content = json.fetch("content", [])
          text = content.select { |b| b["type"] == "text" }.map { |b| b["text"] }.join("\n")
          calls = content.select { |b| b["type"] == "tool_use" }
                         .map { |b| ToolCall.new(id: b["id"], name: b["name"], input: b["input"] || {}) }
          Response.new(text: text.empty? ? nil : text, tool_calls: calls)
        end

        private

        def translate(message)
          case message
          in Messages::User(text:)
            { role: "user", content: text }
          in Messages::Assistant(text:, tool_calls:)
            blocks = []
            blocks << { type: "text", text: text } if text && !text.empty?
            tool_calls.each { |c| blocks << { type: "tool_use", id: c.id, name: c.name, input: c.input } }
            { role: "assistant", content: blocks }
          in Messages::ToolResults(results:)
            # Na Anthropic, resultados de tools voltam numa mensagem do "user".
            { role: "user",
              content: results.map do |r|
                { type: "tool_result", tool_use_id: r.tool_call_id, content: r.content, is_error: r.error }
              end }
          end
        end
      end
    end
  end
end
