# ADR-001: Stack e princípios do MarketPulse AI

**Status:** Aceito
**Data:** 2026-09-23
**Decisores:** Pedro Barbosa
**Relacionado:** [ADR-002](002-duck-typing-para-registro-de-tools.md)

## Contexto

O MarketPulse AI é um assistente em chat que explica dados do mercado financeiro para investidores iniciantes. O projeto tem dois objetivos com o mesmo peso:

- **Aprendizado:** aprofundar Ruby fora do Rails, entender por dentro a arquitetura de agentes com LLM e praticar Docker com vários serviços.
- **Portfólio:** servir de case que une decisões de engenharia (este repositório e seus ADRs) e decisões de UX (case study no Behance).

Por isso, a stack não é escolhida só por produtividade. Ela precisa **expor o funcionamento das peças** em vez de escondê-lo, sem virar um projeto impossível de terminar.

## Decisão

| Camada | Escolha | Por quê |
|---|---|---|
| Linguagem | Ruby 3.3, sem framework no núcleo | Aprender a linguagem sem as convenções do Rails |
| LLM | Claude via API de Messages com tool use | O modelo decide que dados buscar; o código executa |
| Cliente HTTP | `Net::HTTP` da stdlib | Ver o protocolo da API sem a abstração de uma gem |
| Testes | Minitest (stdlib) | Zero dependências; o suficiente para testes de unidade e contrato |
| Execução | Docker e Docker Compose | Ambiente reproduzível e prática de deploy |
| Web (planejado) | Sinatra e frontend em vanilla JS | Servidor HTTP mínimo; foco no backend |
| Banco (planejado) | PostgreSQL com a gem Sequel | Séries de preço, cache, conversas, log de tools e placar de previsões |
| CI | GitHub Actions | Testes e build da imagem a cada push |

### Princípios de arquitetura

1. **O código calcula, o Claude interpreta.** Todo número exibido vem de uma tool determinística. O modelo escolhe quais tools chamar e explica o resultado, mas nunca produz números por conta própria.
2. **Todo dado tem fonte e horário.** As tools retornam `source` e `fetched_at`, e a interface exibe essas informações.
3. **Previsão é experimento, não promessa.** Qualquer modelo de previsão é comparado com baselines, avaliado com backtest walk-forward e tem o histórico de acertos registrado.
4. **Dependências entram quando doem.** Uma gem só é adicionada quando resolver um problema real que a stdlib torna trabalhoso, e a troca é registrada em um ADR.

## Opções consideradas

### Rails (API mode)

**Prós:** produtividade alta, e o autor já tem experiência com o framework.
**Contras:** esconde exatamente o que o projeto quer ensinar (roteamento, persistência, carregamento de código) e traz muito mais do que o necessário para um único endpoint de chat.

### Sinatra ou Roda desde o início

**Prós:** leve e explícito.
**Contras:** na fase 1 não existe HTTP. O loop do agente roda no terminal, e adicionar um servidor antes da hora mistura duas dificuldades.

### Gem oficial `anthropic` em vez de `Net::HTTP`

**Prós:** tipos, retries e streaming prontos.
**Contras:** oculta o formato das mensagens, dos blocos `tool_use` e `tool_result`, e o estado reenviado a cada turno. Será reavaliada quando o streaming entrar na fase web.

## Consequências

### Positivas

- Cada camada é pequena o suficiente para ser lida e entendida por inteiro.
- O projeto roda e é testado sem nenhuma gem, o que simplifica o Docker e o CI.
- As decisões ficam documentadas, e o repositório conta a história da evolução do projeto.

### Negativas e cuidados

- Mais código escrito à mão, como validação de input e parsing de erros HTTP. É intencional, mas precisa de testes.
- Sem as convenções do Rails, a organização de pastas e o carregamento de arquivos são responsabilidade do projeto e precisam de disciplina.
- Algumas escolhas, como `Net::HTTP` e a validação mínima de schema, são provisórias. Os ADRs futuros devem registrar quando e por que forem trocadas.
