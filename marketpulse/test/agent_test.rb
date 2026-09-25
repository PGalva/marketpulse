# frozen_string_literal: true

# Testa o loop inteiro SEM chamar a API: um Claude falso que roteiriza respostas.
# Rode com: ruby test/agent_test.rb
$LOAD_PATH.unshift File.expand_path("../lib", __dir__)

require "minitest/autorun"
require "agent"
require "fake_market_client"
require "tools/registry"
require "tools/stock_quote_tool"

class ScriptedClaude
  attr_reader :calls

  def initialize(*responses)
    @responses = responses
    @calls = []
  end

  def create(messages:, tools:, system:)
    @calls << messages.map(&:dup)
    @responses.shift
  end
end

class AgentTest < Minitest::Test
  def setup
    @registry = Tools::Registry.new
    @registry.register(Tools::StockQuoteTool.new(market_client: FakeMarketClient.new))
  end

  def tool_use(id, ticker)
    { "stop_reason" => "tool_use",
      "content" => [{ "type" => "tool_use", "id" => id, "name" => "get_stock_quote",
                      "input" => { "ticker" => ticker } }] }
  end

  def final(text)
    { "stop_reason" => "end_turn", "content" => [{ "type" => "text", "text" => text }] }
  end

  def test_executa_a_tool_e_devolve_a_resposta_final
    claude = ScriptedClaude.new(tool_use("t1", "AAPL"), final("A AAPL subiu 1,25% hoje."))
    answer = Agent.new(claude: claude, registry: @registry, logger: nil).ask("Como está a AAPL?")

    assert_equal "A AAPL subiu 1,25% hoje.", answer
    result = claude.calls.last.last[:content].first
    assert_equal "t1", result[:tool_use_id]
    assert_includes result[:content], "228.4"
  end

  def test_erro_da_tool_vira_tool_result_com_is_error
    claude = ScriptedClaude.new(tool_use("t1", "XPTO"), final("Não encontrei esse ticker."))
    Agent.new(claude: claude, registry: @registry, logger: nil).ask("E a XPTO?")

    result = claude.calls.last.last[:content].first
    assert result[:is_error]
    assert_match(/não encontrado/, result[:content])
  end

  def test_para_depois_do_limite_de_turnos
    claude = ScriptedClaude.new(*Array.new(Agent::MAX_TURNS) { |i| tool_use("t#{i}", "AAPL") })
    answer = Agent.new(claude: claude, registry: @registry, logger: nil).ask("loop")

    assert_match(/Não consegui/, answer)
  end

  def test_registry_rejeita_objeto_sem_o_contrato
    assert_raises(Tools::InvalidToolError) { @registry.register(Object.new) }
  end
end
