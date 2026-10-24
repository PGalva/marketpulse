# frozen_string_literal: true

require_relative "../test_helper"

LLM = MarketPulse::LLM
M = LLM::Messages

module ProviderFixtures
  def tools
    [LLM::ToolDefinition.new(name: "get_stock_quote", description: "Cotação de uma ação",
                             input_schema: { type: "object", properties: { ticker: { type: "string" } }, required: ["ticker"] })]
  end

  def conversation
    [
      M::User.new(text: "Como está a AAPL?"),
      M::Assistant.new(text: nil, tool_calls: [LLM::ToolCall.new(id: "c1", name: "get_stock_quote", input: { "ticker" => "AAPL" })]),
      M::ToolResults.new(results: [LLM::ToolResult.new(tool_call_id: "c1", content: '{"price":1}')])
    ]
  end
end

class AnthropicProviderTest < Minitest::Test
  include TestHelpers
  include ProviderFixtures
  include ProviderContract

  def provider = LLM::Providers::Anthropic.new(api_key: "x")

  def test_traduz_o_historico_neutro_para_o_formato_da_anthropic
    body = provider.request_body(messages: conversation, tools: tools, system: "sys")

    assert_equal "sys", body[:system]
    assert_equal "tool_use", body[:messages][1][:content].first[:type]
    result = body[:messages][2]
    assert_equal "user", result[:role]
    assert_equal "tool_result", result[:content].first[:type]
    assert_equal "c1", result[:content].first[:tool_use_id]
    assert_equal "get_stock_quote", body[:tools].first[:name]
  end

  def test_traduz_a_resposta_real_para_o_formato_neutro
    response = provider.parse_response(fixture("anthropic_tool_use.json"))

    assert response.tool_use?
    assert_equal "Vou buscar a cotação.", response.text
    assert_equal LLM::ToolCall.new(id: "toolu_01", name: "get_stock_quote", input: { "ticker" => "AAPL" }),
                 response.tool_calls.first
  end

  def test_envia_a_chave_no_header
    http = FakeHTTP.new(fixture("anthropic_tool_use.json"))
    LLM::Providers::Anthropic.new(api_key: "sk-ant-teste", http: http).chat(messages: conversation, tools: tools, system: "s")

    assert_equal "sk-ant-teste", http.requests.first[:headers]["x-api-key"]
  end
end

class OpenAICompatibleProviderTest < Minitest::Test
  include TestHelpers
  include ProviderFixtures
  include ProviderContract

  def provider = LLM::Providers::OpenAICompatible.new

  def test_system_vira_mensagem_e_tools_viram_functions
    body = provider.request_body(messages: conversation, tools: tools, system: "sys")

    assert_equal({ role: "system", content: "sys" }, body[:messages].first)
    assert_equal "function", body[:tools].first[:type]
    assert_equal tools.first.input_schema, body[:tools].first[:function][:parameters]
  end

  def test_arguments_sao_serializados_como_string_e_resultados_viram_role_tool
    body = provider.request_body(messages: conversation, tools: tools, system: "sys")

    assistant = body[:messages][2]
    assert_equal '{"ticker":"AAPL"}', assistant[:tool_calls].first[:function][:arguments]
    assert_equal({ role: "tool", tool_call_id: "c1", content: '{"price":1}' }, body[:messages][3])
  end

  def test_parse_trata_arguments_string_json_invalido_e_id_vazio
    response = provider.parse_response(fixture("openai_tool_calls.json"))

    first, broken = response.tool_calls
    assert_nil response.text
    assert_equal({ "ticker" => "AAPL" }, first.input)
    assert_equal({}, broken.input, "JSON quebrado vira input vazio; o Registry recusa depois")
    refute_empty broken.id, "id vazio é gerado"
  end

  def test_monta_a_url_de_chat_completions_sem_chave
    http = FakeHTTP.new(fixture("openai_tool_calls.json"))
    LLM::Providers::OpenAICompatible.new(base_url: "http://ollama:11434/v1/", http: http)
                                    .chat(messages: conversation, tools: tools, system: "s")

    assert_equal "http://ollama:11434/v1/chat/completions", http.requests.first[:url]
    assert_empty http.requests.first[:headers]
  end
end

class OfflineProviderTest < Minitest::Test
  include TestHelpers
  include ProviderFixtures
  include ProviderContract

  def provider = LLM::Providers::Offline.new

  def forecast_tool = LLM::ToolDefinition.new(name: "forecast_price", description: "x", input_schema: {})

  def test_pede_cotacao_para_tickers_em_maiusculas
    response = provider.chat(messages: [M::User.new(text: "Como está a AAPL hoje?")], tools: tools, system: "")
    assert_equal ["AAPL"], response.tool_calls.map { |c| c.input["ticker"] }
  end

  def test_pede_previsao_quando_a_pergunta_fala_em_previsao
    response = provider.chat(messages: [M::User.new(text: "Qual a previsão da MSFT?")],
                             tools: tools + [forecast_tool], system: "")
    assert_equal "forecast_price", response.tool_calls.first.name
  end
end

class FallbackRouterTest < Minitest::Test
  include TestHelpers

  def test_usa_o_proximo_provider_quando_o_primeiro_falha
    broken = ScriptedProvider.new(LLM::ProviderError.new("timeout"))
    backup = ScriptedProvider.new(final("ok do backup"))
    router = LLM::Providers::FallbackRouter.new(broken, backup)

    assert_equal "ok do backup", router.chat(messages: [], tools: [], system: "").text
  end

  def test_erro_quando_nenhum_responde
    router = LLM::Providers::FallbackRouter.new(ScriptedProvider.new(LLM::ProviderError.new("a")))
    assert_raises(LLM::ProviderError) { router.chat(messages: [], tools: [], system: "") }
  end
end

class FactoryTest < Minitest::Test
  def test_sem_chave_valida_usa_offline
    assert_equal "offline", LLM.build({ "ANTHROPIC_API_KEY" => "cole-sua-chave-aqui" }).name
  end

  def test_ollama_com_fallback_offline_vira_router
    provider = LLM.build({ "LLM_PROVIDER" => "ollama", "LLM_FALLBACK" => "offline" })
    assert_equal "fallback(ollama → offline)", provider.name
  end

  def test_provider_desconhecido_explica_as_opcoes
    error = assert_raises(LLM::Error) { LLM.build({ "LLM_PROVIDER" => "gpt" }) }
    assert_match(/anthropic, ollama/, error.message)
  end
end
