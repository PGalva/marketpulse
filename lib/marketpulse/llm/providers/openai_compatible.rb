# frozen_string_literal: true

require "json"
require "securerandom"
require_relative "../types"
require_relative "../http"

module MarketPulse
  module LLM
    module Providers
      # Adaptador para qualquer API no formato de chat completions da OpenAI.
      # Cobre o Ollama (local, gratuito) e a maioria dos provedores na nuvem:
      # muda só o base_url, o modelo e, se houver, a chave.
      class OpenAICompatible
        DEFAULT_BASE_URL = "http://ollama:11434/v1"
        DEFAULT_MODEL = "qwen2.5:3b"

        attr_reader :model

        # read_timeout alto: um modelo local rodando só na CPU pode levar
        # mais de um minuto para responder.
        def initialize(base_url: DEFAULT_BASE_URL, model: DEFAULT_MODEL, api_key: nil,
                       http: HTTP, read_timeout: 300, name: "openai_compatible")
          @url = "#{base_url.chomp('/')}/chat/completions"
          @model = model
          @api_key = api_key
          @http = http
          @read_timeout = read_timeout
          @name = name
        end

        attr_reader :name

        def chat(messages:, tools:, system:)
          headers = @api_key ? { "authorization" => "Bearer #{@api_key}" } : {}
          json = @http.post_json(@url, body: request_body(messages: messages, tools: tools, system: system),
                                       headers: headers, read_timeout: @read_timeout)
          parse_response(json)
        end

        def request_body(messages:, tools:, system:)
          body = {
            model: @model,
            # Aqui o system prompt é uma mensagem, não um parâmetro separado.
            messages: [{ role: "system", content: system }] + messages.flat_map { |m| translate(m) }
          }
          unless tools.empty?
            body[:tools] = tools.map do |t|
              { type: "function", function: { name: t.name, description: t.description, parameters: t.input_schema } }
            end
          end
          body
        end

        def parse_response(json)
          message = json.dig("choices", 0, "message") or
            raise ProviderError, "Resposta sem choices[0].message: #{json.to_s[0, 200]}"

          calls = Array(message["tool_calls"]).map do |call|
            fn = call["function"] || {}
            # Armadilha nº 1: arguments chega como STRING JSON, não objeto.
            ToolCall.new(id: call["id"].to_s.empty? ? "call_#{SecureRandom.hex(4)}" : call["id"],
                         name: fn["name"].to_s,
                         input: parse_arguments(fn["arguments"]))
          end
          text = message["content"].to_s.strip
          Response.new(text: text.empty? ? nil : text, tool_calls: calls)
        end

        private

        def translate(message)
          case message
          in Messages::User(text:)
            [{ role: "user", content: text }]
          in Messages::Assistant(text:, tool_calls:)
            out = { role: "assistant", content: text }
            unless tool_calls.empty?
              out[:tool_calls] = tool_calls.map do |c|
                { id: c.id, type: "function", function: { name: c.name, arguments: JSON.generate(c.input) } }
              end
            end
            [out]
          in Messages::ToolResults(results:)
            # Aqui cada resultado vira uma mensagem própria com role "tool".
            results.map do |r|
              { role: "tool", tool_call_id: r.tool_call_id, content: r.error ? "ERRO: #{r.content}" : r.content }
            end
          end
        end

        # Modelos pequenos às vezes mandam JSON quebrado. Em vez de derrubar
        # o loop, entregamos um input vazio: a validação do Registry recusa,
        # e o erro volta ao modelo como tool_result com error: true.
        def parse_arguments(raw)
          return raw if raw.is_a?(Hash)

          parsed = JSON.parse(raw.to_s)
          parsed.is_a?(Hash) ? parsed : {}
        rescue JSON::ParserError
          {}
        end
      end
    end
  end
end
