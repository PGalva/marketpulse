# frozen_string_literal: true

require_relative "../test_helper"

class AgentTest < Minitest::Test
  include TestHelpers

  def setup
    @storage = MarketPulse::Storage.memory
    @client = MarketPulse::MarketData::FakeClient.new(today: Date.new(2026, 10, 23), days: 300)
    @registry = MarketPulse.registry(storage: @storage, client: @client)
  end

  def agent(provider) = MarketPulse::Chat::Agent.new(provider: provider, registry: @registry, logger: nil)

  def test_executa_a_tool_e_devolve_a_resposta_final
    provider = ScriptedProvider.new(tool_use("t1", "get_stock_quote", { "ticker" => "AAPL" }), final("Subiu."))

    assert_equal "Subiu.", agent(provider).ask("Como está a AAPL?")
    result = provider.calls.last.last.results.first
    assert_equal "t1", result.tool_call_id
    refute result.error
  end

  def test_erro_de_tool_e_input_invalido_viram_resultado_com_erro
    provider = ScriptedProvider.new(tool_use("t1", "get_stock_quote", {}), final("ok"))
    agent(provider).ask("?")

    result = provider.calls.last.last.results.first
    assert result.error
    assert_match(/obrigatórios ausentes: ticker/, result.content)
  end

  def test_historico_persiste_entre_perguntas
    provider = ScriptedProvider.new(final("um"), final("dois"))
    a = agent(provider)
    a.ask("primeira")
    a.ask("segunda")

    assert_equal 4, a.history.size
  end

  def test_para_depois_do_limite_de_turnos
    responses = Array.new(MarketPulse::Chat::Agent::MAX_TURNS) { |i| tool_use("t#{i}", "get_stock_quote", { "ticker" => "AAPL" }) }
    assert_match(/Não consegui/, agent(ScriptedProvider.new(*responses)).ask("loop"))
  end

  def test_fluxo_completo_offline_com_previsao
    MarketPulse.daily_job(storage: @storage, client: @client, logger: nil).run
    answer = agent(MarketPulse::LLM::Providers::Offline.new).ask("Qual a previsão da PETR4?")

    assert_match(/PETR4: previsão/, answer)
    assert_match(/reversão à média/, answer)
  end
end

class StockQuoteToolTest < Minitest::Test
  include ToolContract

  def tool = MarketPulse::Chat::Tools::StockQuoteTool.new(market_client: MarketPulse::MarketData::FakeClient.new)
end

class ForecastPriceToolTest < Minitest::Test
  include ToolContract

  def tool = @tool ||= MarketPulse::Chat::Tools::ForecastPriceTool.new(forecasts: @storage.forecasts)

  def setup
    @storage = MarketPulse::Storage.memory
  end

  def test_sem_previsao_explica_como_gerar
    error = assert_raises(MarketPulse::Chat::Tools::ForecastPriceTool::NoForecastError) { tool.execute("ticker" => "AAPL") }
    assert_match(/bin\/forecast_job/, error.message)
  end

  def test_retorna_previsao_backtest_placar_e_aviso
    client = MarketPulse::MarketData::FakeClient.new(today: Date.new(2026, 10, 23), days: 300)
    MarketPulse.daily_job(storage: @storage, client: client, logger: nil).run
    out = tool.execute("ticker" => "aapl")

    assert_equal "AAPL", out[:ticker]
    assert_includes out[:backtest].keys, :beats_baseline
    assert_equal 0, out[:scoreboard][:evaluated]
    assert_match(/Não é recomendação/, out[:disclaimer])
  end
end

class RegistryTest < Minitest::Test
  def test_rejeita_objeto_sem_o_contrato
    assert_raises(MarketPulse::Chat::Tools::InvalidToolError) { MarketPulse::Chat::Tools::Registry.new.register(Object.new) }
  end
end
