# frozen_string_literal: true

require "json"

# O coração do projeto: o loop ReAct.
# 1. Manda a conversa + tools para o Claude.
# 2. Se ele responder com tool_use, executa as tools e devolve os resultados.
# 3. Repete até ele responder só com texto (stop_reason != "tool_use").
class Agent
  MAX_TURNS = 5 # proteção contra loop infinito (e contra gastar tokens à toa)

  SYSTEM_PROMPT = <<~PROMPT
    Você é o MarketPulse, um assistente que explica dados do mercado financeiro
    para investidores iniciantes. Use as tools para obter dados; nunca invente números.
    Explique em linguagem simples e não faça recomendações de compra ou venda.
  PROMPT

  def initialize(claude:, registry:, logger: $stdout)
    @claude = claude
    @registry = registry
    @logger = logger
  end

  def ask(question)
    messages = [{ role: "user", content: question }]

    MAX_TURNS.times do |turn|
      log "↻ Turno #{turn + 1}: enviando #{messages.size} mensagem(ns) ao Claude"
      response = @claude.create(messages: messages, tools: @registry.definitions, system: SYSTEM_PROMPT)

      # A resposta do assistente entra no histórico exatamente como veio,
      # incluindo os blocos tool_use (a API exige isso no próximo turno).
      messages << { role: "assistant", content: response["content"] }

      return final_text(response) unless response["stop_reason"] == "tool_use"

      tool_results = response["content"]
                     .select { |block| block["type"] == "tool_use" }
                     .map { |block| run_tool(block) }

      # Os resultados voltam como mensagem do "user", ligados pelo tool_use_id.
      messages << { role: "user", content: tool_results }
    end

    "Não consegui chegar a uma resposta em #{MAX_TURNS} turnos."
  end

  private

  def run_tool(block)
    log "  → Claude pediu #{block['name']}(#{block['input'].to_json})"
    output = @registry.call(block["name"], block["input"])
    log "  ← Resultado: #{output.to_json}"
    { type: "tool_result", tool_use_id: block["id"], content: JSON.generate(output) }
  rescue StandardError => e
    # Erro não derruba o loop: vira um tool_result com is_error,
    # e o Claude decide como explicar isso ao usuário.
    log "  ✗ Erro: #{e.message}"
    { type: "tool_result", tool_use_id: block["id"], content: e.message, is_error: true }
  end

  def final_text(response)
    response["content"].select { |b| b["type"] == "text" }.map { |b| b["text"] }.join("\n")
  end

  def log(message)
    @logger&.puts(message)
  end
end
