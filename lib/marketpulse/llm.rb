# frozen_string_literal: true

require_relative "llm/types"
require_relative "llm/http"
require_relative "llm/providers/anthropic"
require_relative "llm/providers/openai_compatible"
require_relative "llm/providers/offline"
require_relative "llm/providers/fallback_router"

module MarketPulse
  module LLM
    PROVIDERS = %w[anthropic ollama openai_compatible offline].freeze

    # Factory: a ÚNICA decisão sobre qual IA usar, tomada uma vez, pela
    # configuração. O resto do sistema recebe só o objeto pronto.
    #
    #   LLM_PROVIDER   anthropic | ollama | openai_compatible | offline
    #   LLM_MODEL      modelo do provider (opcional; cada um tem um padrão)
    #   LLM_BASE_URL   URL base para ollama/openai_compatible
    #   LLM_API_KEY    chave para openai_compatible (ANTHROPIC_API_KEY para anthropic)
    #   LLM_FALLBACK   lista separada por vírgula, ex.: "offline"
    def self.build(env = ENV, logger: nil)
      primary = build_one(env.fetch("LLM_PROVIDER", default_provider(env)), env, primary: true)
      fallbacks = env.fetch("LLM_FALLBACK", "").split(",").map(&:strip).reject(&:empty?)
      return primary if fallbacks.empty?

      Providers::FallbackRouter.new(primary, *fallbacks.map { |n| build_one(n, env, primary: false) }, logger: logger)
    end

    # Sem configuração explícita: Claude se houver chave válida, senão offline.
    def self.default_provider(env)
      env.fetch("ANTHROPIC_API_KEY", "").start_with?("sk-ant-") ? "anthropic" : "offline"
    end

    def self.build_one(kind, env, primary:)
      model = (env["LLM_MODEL"] if primary && !env["LLM_MODEL"].to_s.empty?)
      case kind
      when "anthropic"
        Providers::Anthropic.new(api_key: env.fetch("ANTHROPIC_API_KEY") { raise Error, "ANTHROPIC_API_KEY não definida" },
                                 model: model || Providers::Anthropic::DEFAULT_MODEL)
      when "ollama"
        Providers::OpenAICompatible.new(base_url: env.fetch("LLM_BASE_URL", Providers::OpenAICompatible::DEFAULT_BASE_URL),
                                        model: model || Providers::OpenAICompatible::DEFAULT_MODEL,
                                        name: "ollama")
      when "openai_compatible"
        Providers::OpenAICompatible.new(base_url: env.fetch("LLM_BASE_URL") { raise Error, "LLM_BASE_URL não definida" },
                                        model: model || raise(Error, "LLM_MODEL não definido"),
                                        api_key: env["LLM_API_KEY"])
      when "offline"
        Providers::Offline.new
      else
        raise Error, "LLM_PROVIDER desconhecido: #{kind.inspect}. Use: #{PROVIDERS.join(', ')}"
      end
    end
  end
end
