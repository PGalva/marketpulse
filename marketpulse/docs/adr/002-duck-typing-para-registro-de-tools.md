# ADR-002: Duck Typing em vez de Herança Clássica para o registro de Tools

**Status:** Aceito
**Data:** 2026-09-22
**Relacionado:** [ADR-001](001-stack-e-principios.md)
**Decisores:** Pedro Barbosa

## Contexto

O MarketPulse AI usa a API de Messages do Claude com *tool use*. Nesse modelo, a aplicação envia ao Claude uma lista de ferramentas. Cada ferramenta tem `name`, `description` e um `input_schema` em JSON Schema. Quando o modelo decide usar uma ferramenta, ele devolve um bloco `tool_use`. A aplicação então executa a ferramenta correspondente localmente e responde com um `tool_result`.

A primeira implementação usava herança clássica a partir de uma classe base abstrata:

```ruby
class BaseTool
  def name         = raise(NotImplementedError)
  def description  = raise(NotImplementedError)
  def input_schema = raise(NotImplementedError)
  def execute(_input) = raise(NotImplementedError)

  # Comportamento compartilhado foi se acumulando aqui:
  # logging, cache, retry, formatação de erro, rate limit...
end

class StockQuoteTool < BaseTool
  # ...
end
```

Com o crescimento do número de ferramentas (cotação, indicadores fundamentalistas, comparação setorial, notícias), surgiram estes problemas:

- **A classe base virou um "god object".** Comportamentos que só algumas tools precisam, como cache ou retry de API externa, foram parar em `BaseTool` e passaram a ser herdados por todas.
- **O acoplamento é hierárquico.** Qualquer mudança em `BaseTool` afeta todas as subclasses, e cada nova ferramenta precisa conhecer e respeitar os detalhes internos da classe pai.
- **Ruby tem herança simples.** Uma tool que já precisa herdar de outra classe, como um cliente de API existente ou um `Struct`, não consegue herdar também de `BaseTool`.
- **Os testes ficam pesados.** Testar uma tool exige carregar a hierarquia inteira e seus efeitos colaterais, como logging e cache.
- **A herança não garante o contrato.** Os métodos abstratos com `NotImplementedError` só falham em tempo de execução, no momento da chamada. Na prática, a herança oferece a mesma garantia que o duck typing, só que com mais acoplamento.

## Decisão

Uma **Tool** é qualquer objeto que responda a quatro métodos. Não existe classe base obrigatória. O `Tools::Registry` verifica o contrato **no momento do registro** usando `respond_to?`, sem olhar para a ancestralidade da classe.

### Interface comum

| Método | Retorno | Responsabilidade |
|---|---|---|
| `name` | `String` | Identificador único, em `snake_case`, enviado ao Claude. |
| `description` | `String` | Descrição em linguagem natural. O modelo usa esse texto para decidir quando chamar a tool. |
| `input_schema` | `Hash` | JSON Schema (`type: "object"`) dos parâmetros aceitos. |
| `execute(input)` | `String` ou `Hash` | Executa a ação com o `input` já validado e retorna o conteúdo do `tool_result`. |

### Registry

```ruby
module Tools
  class InvalidToolError < ArgumentError; end
  class UnknownToolError < StandardError; end

  class Registry
    REQUIRED_METHODS = %i[name description input_schema execute].freeze

    def initialize
      @tools = {}
    end

    def register(tool)
      missing = REQUIRED_METHODS.reject { |m| tool.respond_to?(m) }
      if missing.any?
        raise InvalidToolError,
              "#{tool.class} não implementa: #{missing.join(', ')}"
      end

      if @tools.key?(tool.name)
        raise InvalidToolError, "Tool '#{tool.name}' já registrada"
      end

      @tools[tool.name] = tool
      self
    end

    # Payload do parâmetro `tools` na chamada à API do Claude
    def definitions
      @tools.values.map do |tool|
        {
          name: tool.name,
          description: tool.description,
          input_schema: tool.input_schema
        }
      end
    end

    def call(name, input)
      tool = @tools.fetch(name) { raise UnknownToolError, "Tool desconhecida: #{name}" }
      tool.execute(input)
    end
  end
end
```

### Exemplo de Tool

A tool é um objeto Ruby comum, e suas dependências entram pelo construtor:

```ruby
class StockQuoteTool
  def initialize(market_client:)
    @market_client = market_client
  end

  def name = "get_stock_quote"

  def description
    "Retorna preço atual, variação diária e volume de um ativo a partir do ticker."
  end

  def input_schema
    {
      type: "object",
      properties: {
        ticker: { type: "string", description: "Ticker do ativo, ex.: PETR4, AAPL" }
      },
      required: ["ticker"]
    }
  end

  def execute(input)
    quote = @market_client.quote(input.fetch("ticker"))
    { price: quote.price, change_pct: quote.change_pct, volume: quote.volume }
  end
end
```

Comportamentos transversais, como cache, logging e retry, são aplicados por **composição**. A forma recomendada é um decorator que também respeita o contrato:

```ruby
class CachedTool < SimpleDelegator
  def initialize(tool, cache:, ttl:)
    super(tool)
    @cache, @ttl = cache, ttl
  end

  def execute(input)
    @cache.fetch([name, input], expires_in: @ttl) { __getobj__.execute(input) }
  end
end

registry.register(CachedTool.new(StockQuoteTool.new(market_client:), cache:, ttl: 60))
```

## Opções consideradas

### Opção A: Herança clássica (`BaseTool`)

| Dimensão | Avaliação |
|---|---|
| Complexidade | Média, e cresce com a classe base |
| Acoplamento | Alto |
| Testabilidade | Média |
| Familiaridade | Alta |

**Prós:** o padrão é conhecido e o ponto central permite compartilhar comportamento.
**Contras:** gera um god object, herança simples, fragilidade da classe base, e o contrato continua sendo verificado só em runtime.

### Opção B: Mixin (`include Tools::Contract`)

| Dimensão | Avaliação |
|---|---|
| Complexidade | Baixa |
| Acoplamento | Médio |
| Testabilidade | Boa |
| Familiaridade | Alta |

**Prós:** não consome a herança da classe e deixa explícito que a classe "é uma tool".
**Contras:** tende a repetir o problema da Opção A, com comportamento acumulando no módulo, e ainda obriga cada tool a conhecer um módulo do framework.

### Opção C: Duck Typing com validação no registro (escolhida)

| Dimensão | Avaliação |
|---|---|
| Complexidade | Baixa |
| Acoplamento | Mínimo |
| Testabilidade | Alta |
| Familiaridade | Alta (é Ruby idiomático) |

**Prós:** o contrato é explícito e pequeno, a verificação acontece cedo (no boot) e qualquer objeto pode ser uma tool.
**Contras:** não há tipagem estática, então a conformidade da assinatura e do retorno depende de testes e de validação manual.

## Consequências

### Positivas

- **Desacoplamento.** As tools não dependem de nenhuma classe do framework, apenas do contrato. Adicionar uma ferramenta nova não exige mexer em código existente (Open/Closed).
- **Testes unitários simples.** Cada tool é um PORO com dependências injetadas, então dá para testar sem carregar hierarquia nem infraestrutura:

  ```ruby
  class StockQuoteToolTest < Minitest::Test
    def test_retorna_a_cotacao_do_ticker
      client = Minitest::Mock.new
      client.expect(:quote, { price: 38.5 }, ["PETR4"])

      result = Tools::StockQuoteTool.new(market_client: client).execute("ticker" => "PETR4")

      assert_equal 38.5, result[:price]
      client.verify
    end
  end
  ```

- **Fakes triviais.** Nos testes do Registry e do loop de conversa com o Claude, qualquer `Struct` ou `Data` serve como tool falsa.
- **Composição no lugar de hierarquia.** Cache, logging e retry viram decorators opcionais, aplicados só onde fazem sentido.
- **Falha antecipada.** Uma tool incompleta quebra no `register`, durante o boot, e não no meio de uma conversa com o usuário.

### Negativas e cuidados

- **Não há tipagem estática.** `respond_to?` confirma que o método existe, mas não valida a aridade de `execute` nem os tipos retornados. Mitigações:
  - **Contract test compartilhado** que toda tool deve incluir:

    ```ruby
    module ToolContract
      def test_cumpre_o_contrato
        Tools::Registry::REQUIRED_METHODS.each { |m| assert_respond_to tool, m }
        assert_match(/\A[a-z0-9_]{1,64}\z/, tool.name)
        assert_operator tool.description.strip.length, :>, 20
        assert_equal "object", tool.input_schema[:type]
        assert_equal 1, tool.method(:execute).arity
      end
    end

    class StockQuoteToolTest < Minitest::Test
      include ToolContract

      def tool = Tools::StockQuoteTool.new(market_client: FakeMarketClient.new)
    end
    ```

  - Opcionalmente, adicionar assinaturas **RBS** (`interface _Tool`) e checagem com Steep no CI, se o número de tools crescer.
- **O input vem do modelo e não é confiável.** O Claude pode enviar parâmetros ausentes ou malformados. O Registry deve **validar o `input` contra o `input_schema`** antes de chamar `execute`, por exemplo com a gem `json_schemer`, e devolver um `tool_result` com `is_error: true` em vez de levantar exceção.
- **O contrato fica implícito no código.** Sem uma classe base, a interface só existe neste ADR, no Registry (`REQUIRED_METHODS`) e no contract test. Esses três precisam ser mantidos sincronizados.
- **As chaves do input são strings.** O `input` do bloco `tool_use` chega com chaves `String`. As tools devem usar `input.fetch("ticker")`, ou o Registry deve normalizar as chaves em um único lugar.

## Action Items

1. [x] Remover `BaseTool` e migrar as tools existentes para POROs.
2. [x] Implementar `Tools::Registry` com validação do contrato no registro.
3. [ ] Adicionar validação de `input` por JSON Schema no `Registry#call` (hoje só os campos `required` são verificados).
4. [ ] Criar o módulo `ToolContract` (Minitest) e incluí-lo no teste de todas as tools.
5. [ ] Extrair cache e logging para decorators (`CachedTool`, `LoggedTool`).
6. [ ] Reavaliar RBS/Steep quando houver mais de 10 tools registradas.
