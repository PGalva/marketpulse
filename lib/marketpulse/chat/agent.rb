# frozen_string_literal: true

require "json"
require_relative "../llm/types"

module MarketPulse
  module Chat
    # O loop ReAct, agora falando SÓ o formato neutro.
    # O Agent não sabe se do outro lado está o Claude, o Ollama, o modo
    # offline ou um FallbackRouter: ele só conhece o método `chat`.
    class Agent
      MAX_TURNS = 5

      SYSTEM_PROMPT = <<~PROMPT
        Você é o MarketPulse, um assistente que explica dados do mercado financeiro
        para investidores iniciantes. Use as tools para obter dados; nunca invente números.
        Quando falar de previsões, diga sempre a faixa de incerteza e se o modelo superou o baseline.
        Explique em linguagem simples, em português, e não faça recomendações de compra ou venda.
      PROMPT

      attr_reader :history

      def initialize(provider:, registry:, logger: $stdout, system_prompt: SYSTEM_PROMPT)
        @provider = provider
        @registry = registry
        @logger = logger
        @system_prompt = system_prompt
        @history = []
      end

      # Mantém o histórico entre perguntas: a conversa tem memória.
      def ask(question)
        @history << LLM::Messages::User.new(text: question)

        MAX_TURNS.times do |turn|
          log "↻ Turno #{turn + 1} via #{@provider.name} (#{@history.size} mensagens)"
          response = @provider.chat(messages: @history, tools: @registry.definitions, system: @system_prompt)
          @history << LLM::Messages::Assistant.new(text: response.text, tool_calls: response.tool_calls)

          return response.text.to_s unless response.tool_use?

          results = response.tool_calls.map { |call| run_tool(call) }
          @history << LLM::Messages::ToolResults.new(results: results)
        end

        "Não consegui chegar a uma resposta em #{MAX_TURNS} turnos."
      end

      def reset! = @history.clear

      private

      def run_tool(call)
        log "  → #{call.name}(#{call.input.to_json})"
        output = @registry.call(call.name, call.input)
        log "  ← #{output.to_json[0, 160]}"
        LLM::ToolResult.new(tool_call_id: call.id, content: JSON.generate(output))
      rescue StandardError => e
        # Erro de tool vira resultado com error: true; o modelo explica.
        log "  ✗ #{e.message}"
        LLM::ToolResult.new(tool_call_id: call.id, content: e.message, error: true)
      end

      def log(message) = @logger&.puts(message)
    end
  end
end
