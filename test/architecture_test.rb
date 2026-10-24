# frozen_string_literal: true

require_relative "test_helper"

# Testa a ARQUITETURA, não o comportamento: garante a direção das
# dependências do ADR-004 lendo os requires de cada módulo.
#
#   chat ──► llm
#     ├────► forecasting ──► market_data
#     └────► market_data
#
# Se alguém fizer forecasting depender de llm, este teste quebra no CI.
class ArchitectureTest < Minitest::Test
  LIB = File.expand_path("../lib/marketpulse", __dir__)

  ALLOWED = {
    "market_data" => [],
    "llm" => [],
    "forecasting" => %w[market_data],
    "chat" => %w[llm forecasting market_data]
  }.freeze

  ALLOWED.each do |mod, allowed|
    define_method("test_#{mod}_so_depende_do_permitido") do
      forbidden = ALLOWED.keys - [mod] - allowed
      files = Dir[File.join(LIB, "#{mod}.rb"), File.join(LIB, mod, "**/*.rb")]
      refute_empty files

      violations = files.flat_map do |file|
        File.readlines(file, encoding: "UTF-8").grep(/require/).filter_map do |line|
          hit = forbidden.find { |other| line.match?(%r{["'/]#{other}(["'/]|\.rb)}) }
          "#{File.basename(file)} → #{hit}: #{line.strip}" if hit
        end
      end
      assert_empty violations, "#{mod} não pode depender de #{forbidden.join(', ')}"
    end
  end

  def test_forecasting_carrega_sem_llm_nem_chat
    # Processo isolado: carregar o forecasting não pode puxar llm nem chat.
    script = <<~RUBY
      $LOAD_PATH.unshift "#{File.expand_path('../lib', __dir__)}"
      require "marketpulse/forecasting"
      abort "vazou LLM" if defined?(MarketPulse::LLM)
      abort "vazou Chat" if defined?(MarketPulse::Chat)
    RUBY
    assert system(RbConfig.ruby, "-e", script), "forecasting carregou módulos proibidos"
  end
end
