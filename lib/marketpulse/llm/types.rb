# frozen_string_literal: true

module MarketPulse
  # Camada de LLM agnóstica de provider (ADR-003).
  #
  # Este arquivo define o FORMATO NEUTRO: a única linguagem que o Agent fala.
  # Cada provider traduz esse formato para a API dele na ida e traduz a
  # resposta de volta na volta. Nenhuma classe aqui sabe o que é "tool_use"
  # (Anthropic) ou "tool_calls" (OpenAI).
  module LLM
    class Error < StandardError; end
    # Falha do provider (rede, HTTP 4xx/5xx, timeout). O FallbackRouter usa
    # esta classe para decidir se tenta o próximo provider da lista.
    class ProviderError < Error; end

    # Um pedido de execução de tool feito pelo modelo.
    ToolCall = Data.define(:id, :name, :input)

    # O resultado de uma tool, devolvido ao modelo no turno seguinte.
    ToolResult = Data.define(:tool_call_id, :content, :error) do
      def initialize(tool_call_id:, content:, error: false) = super
    end

    # A resposta de qualquer provider, sempre neste formato.
    Response = Data.define(:text, :tool_calls) do
      def tool_use? = tool_calls.any?
    end

    # As três mensagens possíveis no histórico da conversa.
    module Messages
      User = Data.define(:text)
      Assistant = Data.define(:text, :tool_calls) do
        def initialize(text: nil, tool_calls: []) = super
      end
      ToolResults = Data.define(:results)
    end

    # Definição neutra de uma tool, igual ao contrato do ADR-002.
    ToolDefinition = Data.define(:name, :description, :input_schema)
  end
end
