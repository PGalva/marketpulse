# frozen_string_literal: true

$LOAD_PATH.unshift File.expand_path("../lib", __dir__)

require "minitest/autorun"
require "marketpulse"
require "agent"
require "offline_claude"

class OfflineClaudeTest < Minitest::Test
  def agent
    Agent.new(claude: OfflineClaude.new, registry: MarketPulse.registry, logger: nil)
  end

  def test_busca_a_cotacao_e_resume
    answer = agent.ask("Como está a AAPL hoje?")
    assert_match(/AAPL: USD 228.4/, answer)
    refute_match(/Erro/, answer) # "Como" e "hoje" não podem virar ticker
  end

  def test_busca_varios_tickers
    answer = agent.ask("Compare MSFT e PETR4")
    assert_match(/MSFT/, answer)
    assert_match(/PETR4/, answer)
  end

  def test_ticker_inexistente_vira_erro_explicado
    assert_match(/Erro: Ticker XPTO não encontrado/, agent.ask("E a XPTO?"))
  end

  def test_sem_ticker
    assert_match(/Não encontrei um ticker/, agent.ask("oi"))
  end
end
