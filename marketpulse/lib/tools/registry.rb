# frozen_string_literal: true

module Tools
  class InvalidToolError < ArgumentError; end
  class UnknownToolError < StandardError; end
  class InvalidInputError < StandardError; end

  # Registro de tools por duck typing (ADR-002): qualquer objeto que responda
  # a name, description, input_schema e execute pode ser registrado.
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

    # Formato que a API espera no parâmetro `tools`.
    def definitions
      @tools.values.map do |tool|
        { name: tool.name, description: tool.description, input_schema: tool.input_schema }
      end
    end

    def call(name, input)
      tool = @tools.fetch(name) { raise UnknownToolError, "Tool desconhecida: #{name}" }
      validate!(tool, input)
      tool.execute(input)
    end

    private

    # Validação mínima, sem gems: só confere os campos obrigatórios.
    # Na fase 3 dá para trocar por json_schemer e validar o schema completo.
    def validate!(tool, input)
      required = tool.input_schema.fetch(:required, [])
      missing = required.reject { |key| input.key?(key) }
      raise InvalidInputError, "Campos obrigatórios ausentes: #{missing.join(', ')}" if missing.any?
    end
  end
end
