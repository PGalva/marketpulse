# ADR-003: Camada de LLM agnóstica de provider

**Status:** Aceito
**Data:** 2026-10-23
**Decisores:** Pedro Barbosa
**Relacionado:** [ADR-002](002-duck-typing-para-registro-de-tools.md), [ADR-004](004-modulos-e-dois-processos.md)

## Contexto

Até o marco 0, o `Agent` falava diretamente o formato da API da Anthropic: lia `stop_reason`, montava blocos `tool_use` e `tool_result`, e recebia um parâmetro chamado `claude:`. Na prática, o Claude era o centro do sistema.

Isso trazia três problemas:

- **Custo para estudar.** Cada teste manual com IA de verdade gastava tokens pagos.
- **Acoplamento.** Usar outro modelo, como um modelo aberto rodando localmente no Ollama, exigiria reescrever o `Agent`.
- **Ponto único de falha.** Se a API caísse ou a chave expirasse, o chat parava.

As APIs diferem em detalhes que parecem pequenos, mas quebram o loop do agente:

| | Anthropic | Compatível com OpenAI (Ollama e outros) |
|---|---|---|
| System prompt | parâmetro `system` separado | mensagem com `role: "system"` |
| Definição da tool | `input_schema` | `{type: "function", function: {parameters}}` |
| Pedido de tool | bloco `tool_use` em `content` | `message.tool_calls` |
| Argumentos | `input` já é um objeto | `arguments` é uma **string JSON** |
| Resultado | bloco `tool_result` numa mensagem `user` | uma mensagem `role: "tool"` por resultado |

## Decisão

O sistema fala um **formato neutro, próprio**, definido em `lib/marketpulse/llm/types.rb` com objetos de valor imutáveis (`Data.define`):

```ruby
ToolCall   = Data.define(:id, :name, :input)
ToolResult = Data.define(:tool_call_id, :content, :error)
Response   = Data.define(:text, :tool_calls)        # tool_use? => tool_calls.any?
Messages::User, Messages::Assistant, Messages::ToolResults
```

Todo **provider** é um objeto com esta interface (duck typing, como no ADR-002):

```ruby
provider.name   # => "ollama"
provider.model  # => "qwen2.5:3b"
provider.chat(messages:, tools:, system:)  # => LLM::Response
```

Cada provider traduz o formato neutro para a sua API na ida e de volta na volta. Toda a "língua" de cada API mora só dentro do seu adaptador:

| Provider | Para onde vai | Custo |
|---|---|---|
| `Providers::Anthropic` | API do Claude | por token |
| `Providers::OpenAICompatible` | Ollama local ou qualquer API no formato OpenAI | zero no Ollama |
| `Providers::Offline` | lugar nenhum: regras locais | zero |
| `Providers::FallbackRouter` | o primeiro da lista que responder | depende |

A escolha é feita **uma vez, por configuração**, na factory `MarketPulse::LLM.build`, a partir do `.env`:

```
LLM_PROVIDER=ollama
LLM_MODEL=qwen2.5:3b
LLM_FALLBACK=offline
```

Só o provider escolhido é instanciado. Com `LLM_PROVIDER=ollama`, nenhuma requisição vai para a Anthropic: a classe existe no projeto, mas fica sem uso.

O `FallbackRouter` aplica o padrão **Composite**: ele é um provider feito de providers, com a mesma interface `chat`. O `Agent` não sabe que ele existe.

## Opções consideradas

### Opção A: Manter o formato da Anthropic como formato interno

| Dimensão | Avaliação |
|---|---|
| Complexidade | Baixa no início |
| Custo | Alto para estudar (tokens) |
| Flexibilidade | Baixa: outros providers precisariam imitar a Anthropic |

**Prós:** nenhuma refatoração.
**Contras:** o formato de um fornecedor vira a língua do sistema inteiro; o adaptador OpenAI teria que traduzir de Anthropic para OpenAI, o que é mais confuso.

### Opção B: Gem multi-provider pronta

| Dimensão | Avaliação |
|---|---|
| Complexidade | Baixa |
| Aprendizado | Baixo: esconde exatamente as diferenças que o projeto quer estudar |
| Dependência | Uma gem grande no núcleo |

**Prós:** muitos providers prontos, streaming e retries.
**Contras:** contraria o ADR-001 (dependências entram quando doem) e o objetivo de aprendizado.

### Opção C: Formato neutro próprio com adaptadores (escolhida)

| Dimensão | Avaliação |
|---|---|
| Complexidade | Média |
| Custo | Zero com Ollama ou offline |
| Aprendizado | Alto: cada diferença entre APIs vira código explícito e testado |
| Flexibilidade | Alta: provider novo = uma classe nova |

## Consequências

### Positivas

- **Estudar sem pagar.** O projeto roda completo com `offline` ou com um modelo local no Ollama.
- **O `Agent` ficou menor e independente de fornecedor.** Ele só conhece `Response#tool_use?` e os três tipos de mensagem.
- **Testes sem rede.** Cada adaptador é testado com fixtures que reproduzem respostas reais (`test/fixtures/*.json`), e todos incluem o mesmo `ProviderContract`.
- **Resiliência.** Com `LLM_FALLBACK=offline`, uma falha do provider principal não derruba o chat.

### Negativas e cuidados

- **O formato neutro é o denominador comum.** Recursos específicos de um provider (prompt caching da Anthropic, por exemplo) não cabem nele sem estendê-lo. Quando forem necessários, devem entrar como opções do adaptador, nunca como vazamento para o `Agent`.
- **Modelos locais pequenos erram mais:** inventam tools, mandam JSON quebrado ou ignoram tools. Mitigações implementadas: `arguments` inválido vira input vazio, a validação do `Registry` recusa e o erro volta ao modelo como `ToolResult` com `error: true`; ids vazios são gerados.
- **Timeouts maiores.** Um modelo local na CPU pode passar de um minuto por resposta; o adaptador usa `read_timeout` de 300 s.
- **Mudança de caminhos.** O código do ADR-002 mudou de lugar: o `Registry` agora está em `lib/marketpulse/chat/tools/`. O contrato das tools não mudou.

## Action Items

1. [x] Definir o formato neutro e migrar o `Agent` para ele.
2. [x] Adaptadores Anthropic, OpenAI-compatível e Offline, com fixtures e `ProviderContract`.
3. [x] `FallbackRouter` e factory por `.env`.
4. [x] Ollama como serviço opcional no Compose (`--profile ollama`).
5. [ ] Comparar modelos: rodar as mesmas perguntas em dois providers e registrar quem escolhe a tool certa.
6. [ ] Avaliar streaming de respostas quando o chat for para a web.
