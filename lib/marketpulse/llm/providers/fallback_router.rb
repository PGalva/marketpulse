# frozen_string_literal: true

require_relative "../types"

module MarketPulse
  module LLM
    module Providers
      # Padrão Composite: um provider feito de providers.
      # Tenta cada um na ordem; se um falhar com ProviderError, tenta o próximo.
      # O Agent não sabe que existe um router: ele só vê o método `chat`.
      class FallbackRouter
        attr_reader :providers

        def initialize(*providers, logger: nil)
          raise ArgumentError, "FallbackRouter precisa de ao menos um provider" if providers.empty?

          @providers = providers
          @logger = logger
        end

        def name = "fallback(#{@providers.map(&:name).join(' → ')})"
        def model = @providers.first.model

        def chat(**request)
          errors = []
          @providers.each do |provider|
            return provider.chat(**request)
          rescue ProviderError => e
            errors << "#{provider.name}: #{e.message}"
            @logger&.puts("  ⚠ #{provider.name} falhou, tentando o próximo (#{e.message})")
          end
          raise ProviderError, "Nenhum provider respondeu. #{errors.join(' | ')}"
        end
      end
    end
  end
end
