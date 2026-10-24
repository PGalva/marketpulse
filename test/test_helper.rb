# frozen_string_literal: true

$LOAD_PATH.unshift File.expand_path("../lib", __dir__)

require "minitest/autorun"
require "json"
require "marketpulse"

module TestHelpers
  FIXTURES = File.expand_path("fixtures", __dir__)

  def fixture(name) = JSON.parse(File.read(File.join(FIXTURES, name)))

  # HTTP falso: devolve respostas roteirizadas e guarda o que foi enviado.
  class FakeHTTP
    attr_reader :requests

    def initialize(*responses)
      @responses = responses
      @requests = []
    end

    def post_json(url, body:, headers: {}, read_timeout: nil)
      @requests << { url: url, body: body, headers: headers }
      response = @responses.shift
      raise response if response.is_a?(Exception)

      response
    end
  end

  # Provider roteirizado, no formato neutro, para testar o Agent sem rede.
  class ScriptedProvider
    attr_reader :calls

    def initialize(*responses)
      @responses = responses
      @calls = []
    end

    def name = "scripted"
    def model = "scripted"

    def chat(messages:, tools:, system:)
      @calls << messages.dup
      response = @responses.shift
      raise response if response.is_a?(Exception)

      response
    end
  end

  def tool_use(id, name, input)
    MarketPulse::LLM::Response.new(text: nil, tool_calls: [MarketPulse::LLM::ToolCall.new(id: id, name: name, input: input)])
  end

  def final(text) = MarketPulse::LLM::Response.new(text: text, tool_calls: [])
end

# Contrato que TODO provider precisa cumprir (mesma ideia do ToolContract).
module ProviderContract
  def test_cumpre_o_contrato_de_provider
    %i[name model chat].each { |m| assert_respond_to provider, m }
    assert_equal %i[messages system tools].sort,
                 provider.method(:chat).parameters.select { |type, _| type == :keyreq || type == :key }.map(&:last).sort
  end
end

# Contrato que TODA tool precisa cumprir (ADR-002).
module ToolContract
  def test_cumpre_o_contrato_de_tool
    MarketPulse::Chat::Tools::Registry::REQUIRED_METHODS.each { |m| assert_respond_to tool, m }
    assert_match(/\A[a-z0-9_]{1,64}\z/, tool.name)
    assert_operator tool.description.strip.length, :>, 20
    assert_equal "object", tool.input_schema[:type]
    assert_equal 1, tool.method(:execute).arity
  end
end
