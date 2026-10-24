# frozen_string_literal: true

require_relative "../../llm/types"

module MarketPulse
  module Chat
    module Tools
      class InvalidToolError < ArgumentError; end
      class UnknownToolError < StandardError; end
      class InvalidInputError < StandardError; end

      # Registro de tools por duck typing (ADR-002): qualquer objeto que
      # responda a name, description, input_schema e execute serve.
      class Registry
        REQUIRED_METHODS = %i[name description input_schema execute].freeze

        def initialize
          @tools = {}
        end

        def register(tool)
          missing = REQUIRED_METHODS.reject { |m| tool.respond_to?(m) }
          raise InvalidToolError, "#{tool.class} não implementa: #{missing.join(', ')}" if missing.any?
          raise InvalidToolError, "Tool '#{tool.name}' já registrada" if @tools.key?(tool.name)

          @tools[tool.name] = tool
          self
        end

        def names = @tools.keys

        # Definições no formato NEUTRO; cada provider traduz para a sua API.
        def definitions
          @tools.values.map do |t|
            LLM::ToolDefinition.new(name: t.name, description: t.description, input_schema: t.input_schema)
          end
        end

        def call(name, input)
          tool = @tools.fetch(name) { raise UnknownToolError, "Tool desconhecida: #{name}" }
          validate!(tool, input)
          tool.execute(input)
        end

        private

        # Validação mínima: campos obrigatórios e tipo string.
        # O input vem do modelo e não é confiável (modelos locais pequenos
        # erram com frequência).
        def validate!(tool, input)
          raise InvalidInputError, "Input deve ser um objeto JSON" unless input.is_a?(Hash)

          schema = tool.input_schema
          missing = schema.fetch(:required, []).reject { |key| input.key?(key) }
          raise InvalidInputError, "Campos obrigatórios ausentes: #{missing.join(', ')}" if missing.any?

          schema.fetch(:properties, {}).each do |key, spec|
            value = input[key.to_s]
            next if value.nil? || spec[:type] != "string" || value.is_a?(String)

            raise InvalidInputError, "Campo '#{key}' deve ser string"
          end
        end
      end
    end
  end
end
