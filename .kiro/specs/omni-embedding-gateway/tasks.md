# Implementation Plan: dc.omniEmbedding — Universal Embedding Gateway

## Overview

Implementação incremental em 8 fases do gateway universal de embeddings para InterSystems IRIS.
Cada fase entrega um conjunto de classes funcionais e testáveis, garantindo que nenhum código fique órfão ou não integrado.
Todas as classes de produção residem em `src/dc/omniEmbedding/`; todas as classes de teste em `tests/dc/omniEmbedding/`.

---

## Tasks

- [ ] 1. Fase 0 — Fundação: Interface, Engine (stub) e Base
  - [x] 1.1 Criar `dc.omniEmbedding.Interface` estendendo `%Embedding.Interface`
    - Criar arquivo `src/dc/omniEmbedding/Interface.cls`
    - Implementar os três métodos da interface: `Embedding()`, `IsValidConfig()` e `EstimateTokenCount()` com assinaturas `[ Final ]` conforme exigido pelo runtime do IRIS
    - Implementar `ParseConfig()` como `[ Private ]` convertendo JSON string em `%DynamicObject`; lançar `%Exception.General` para JSON mal formado
    - `Embedding()` deve validar que `input` não é vazio antes de qualquer chamada HTTP; lançar exceção se `dimensions` ausente, zero ou negativo
    - Delegar ao `Engine.Embed()` após parse (stub por ora); retornar `%Vector`
    - _Requisitos: 1.2, 1.3, 1.4, 1.5, 1.6_

  - [ ]* 1.2 Escrever testes unitários para `dc.omniEmbedding.Interface`
    - Criar arquivo `tests/dc/omniEmbedding/TestInterface.cls` extendendo `%UnitTest.TestCase`
    - Testar parsing de JSON inválido → exceção com mensagem identificável
    - Testar `input` vazio → exceção sem chamada HTTP
    - Testar `dimensions` ausente/zero/negativo → exceção identificando campo
    - Testar `IsValidConfig()` com JSON sintaticamente inválido → retorna `0` com `errorMsg`
    - _Requisitos: 1.3, 1.4, 1.5, 3.4_

  - [x] 1.3 Criar `dc.omniEmbedding.Engine` (stub com despacho e circuit breaker skeleton)
    - Criar arquivo `src/dc/omniEmbedding/Engine.cls`
    - Implementar `Embed()` como ponto de entrada: chama `CheckBreaker`, despacha para `ResolveProvider`, instancia o Provider via `$CLASSMETHOD` e chama `Execute()`
    - Implementar `ResolveProvider()` com mapeamento completo: provider explícito → classe; inferência por prefixo de `modelName` (case-insensitive via `$ZCONVERT`); lançar exceção para valor desconhecido ou modelName não inferível
    - Implementar `ProviderKey()` gerando chave como `provider|modelName|apiBase`
    - Implementar `CheckBreaker()`, `RecordSuccess()` e `RecordFailure()` como stubs que simplesmente leem/escrevem `^omniEmbedding.Breaker` — lógica completa na Fase 5
    - `TryFallback()` como stub que lança "not implemented" por ora
    - _Requisitos: 2.1, 2.2, 2.3, 2.4, 2.5, 2.6, 11.1, 11.6_

  - [ ]* 1.4 Escrever testes unitários para `dc.omniEmbedding.Engine.ResolveProvider`
    - Criar arquivo `tests/dc/omniEmbedding/TestEngine.cls` extendendo `%UnitTest.TestCase`
    - Testar cada valor válido de `config.provider` → nome de classe correto
    - Testar `config.provider` desconhecido → exceção com valor recebido e lista válida
    - Testar inferência por prefixo `"nomic-"` → Ollama; `"text-embedding-"` → OpenAI; `"embed-"` → Cohere; `"embedding-"` → Gemini
    - Testar `provider` e `modelName` ausentes → exceção orientando uso de `provider` explícito
    - Testar `ProviderKey()` com combinações de provider/modelName/apiBase
    - _Requisitos: 2.1, 2.2, 2.3, 2.4, 2.5, 11.6_

  - [x] 1.5 Criar `dc.omniEmbedding.provider.Base` (Abstract)
    - Criar arquivo `src/dc/omniEmbedding/provider/Base.cls` com `[ Abstract ]`
    - Implementar Template Method `Execute()` com `[ Final ]`: ValidateConfig → SetAuth → GetEmbeddingsUrl → BuildPayload → SetBody → RetryWithBackoff → ParseResponse; ao final, `$ASSERT $VECTORLEN(vector) = config.dimensions`
    - Implementar `ValidateConfig()` como `[ Abstract ]` — valida apenas `modelName` não vazio na base; subclasses chamam `##super()`
    - Implementar `EstimateTokenCount()` com fórmula piso: `$FLOOR($LENGTH(text)/4) + 1`
    - Implementar `ResolveApiKey()` como stub que retorna `config.apiKey` diretamente (substituído na Fase 7); lançar exceção se vazio para provedores que exigem chave
    - Declarar métodos abstratos `SetAuth()`, `GetEmbeddingsUrl()`, `BuildPayload()`, `ParseResponse()`
    - Implementar `RetryWithBackoff()` como stub que executa uma única tentativa sem retry (substituído na Fase 5)
    - _Requisitos: 1.1, 9.1, 13.2, 13.5, 15.1, 15.4_

  - [ ]* 1.6 Escrever testes unitários para `dc.omniEmbedding.provider.Base`
    - Criar arquivo `tests/dc/omniEmbedding/TestProviderBase.cls` extendendo `%UnitTest.TestCase`
    - Testar `EstimateTokenCount()` com strings de tamanhos variados; verificar fórmula piso
    - Testar que `Execute()` lança exceção quando `ValidateConfig()` falha (usando subclasse de teste)
    - Testar que `Execute()` propaga exceção de `ParseResponse()` sem substituir por vetor vazio
    - _Requisitos: 9.1, 13.2, 13.5_

  - [x] 1.7 Checkpoint — Fundação funcional
    - Garantir que todas as classes da Fase 0 compilam sem erros no IRIS
    - `Interface.IsValidConfig()` retorna `0` com `errorMsg` para JSON inválido e campos ausentes
    - `Engine.ResolveProvider()` mapeia corretamente todos os 5 provedores
    - Garantir que todos os testes da Fase 0 passam; consultar o usuário se surgirem dúvidas

---

- [x] 2. Fase 1 — Ollama CI: OpenACompatible e Ollama
  - [x] 2.1 Criar `dc.omniEmbedding.provider.OpenACompatible` (Abstract)
    - Criar arquivo `src/dc/omniEmbedding/provider/OpenACompatible.cls` com `[ Abstract ]`; estende `Base`
    - Implementar `SetAuth()`: adicionar cabeçalho `Authorization: Bearer {ResolveApiKey(config)}`
    - Implementar `BuildPayload()`: retornar `%DynamicObject` com campos `"input"` e `"model"` (via `config.modelName`)
    - Implementar `ParseResponse()`: extrair `body.data[0].embedding` → `%Vector`; lançar exceção com corpo da resposta se campo ausente
    - Implementar `EstimateTokenCount()`: tentar tiktoken via `$SYSTEM.Python` se disponível com cache por `config.modelName`; cair para `##super()` se Python indisponível, sem lançar exceção
    - _Requisitos: 4.1, 4.2, 4.3, 4.4, 4.5, 9.2, 9.3_

  - [x] 2.2 Criar `dc.omniEmbedding.provider.Ollama`
    - Criar arquivo `src/dc/omniEmbedding/provider/Ollama.cls`; estende `OpenACompatible`
    - Implementar `GetEmbeddingsUrl()`: remover trailing slash de `config.apiBase`; usar `http://localhost:11434` como default se ausente; retornar `{apiBase}/v1/embeddings` sem barras duplicadas
    - Implementar `SetAuth()` como no-op — Ollama não requer autenticação
    - Implementar `ValidateConfig()`: chamar `##super()` (valida `modelName`); NÃO lançar erro por ausência de `apiKey`
    - _Requisitos: 6.1, 6.2, 6.3, 6.4, 6.5_

  - [x]* 2.3 Escrever testes unitários para `dc.omniEmbedding.provider.OpenACompatible`
    - Criar arquivo `tests/dc/omniEmbedding/TestOpenACompatible.cls` extendendo `%UnitTest.TestCase`
    - **Property 9: Payload OpenAI-compatible** — para qualquer par `(input, modelName)`, `BuildPayload()` retorna objeto com exatamente `input` e `model` corretos
    - **Validates: Requisito 4.1**
    - Testar `ParseResponse()` com resposta sem `data[0].embedding` → exceção com corpo
    - Testar `ParseResponse()` com resposta válida → `%Vector` com dimensão correta
    - Testar `EstimateTokenCount()` sem tiktoken → retorna valor piso sem lançar exceção
    - _Requisitos: 4.1, 4.2, 4.3, 9.3_

  - [x]* 2.4 Escrever testes de integração para `dc.omniEmbedding.provider.Ollama` (CI)
    - Criar arquivo `tests/dc/omniEmbedding/TestOllama.cls` extendendo `%UnitTest.TestCase`
    - **Property 7: Construção de URL Ollama** — para qualquer `apiBase` (com ou sem trailing slash), `GetEmbeddingsUrl()` retorna URL sem barras duplicadas; `apiBase` ausente usa default
    - **Validates: Requisitos 6.3, 6.4**
    - **Property 6: Ollama aceita ausência de apiKey** — `ValidateConfig()` não lança erro; `Execute()` não adiciona `Authorization`
    - **Validates: Requisitos 6.1, 6.2**
    - Teste de integração end-to-end: `Interface.Embedding('texto de teste', configJSON_Ollama)` → verificar `$VECTORLEN(vetor) = config.dimensions` (requer Ollama em `localhost:11434`)
    - _Requisitos: 6.1, 6.2, 6.3, 6.4, 6.5, 16.1, 16.2_

  - [x] 2.5 Checkpoint — Ollama CI funcional
    - Fluxo completo `EMBEDDING()` → `%Vector` via Ollama funciona sem credenciais
    - Todos os testes unitários e de propriedade da Fase 1 passam
    - Consultar o usuário se surgirem dúvidas sobre o ambiente CI

---

- [x] 3. Fase 2 — OpenAI e Azure OpenAI
  - [x] 3.1 Criar `dc.omniEmbedding.provider.OpenAi`
    - Criar arquivo `src/dc/omniEmbedding/provider/OpenAi.cls`; estende `OpenACompatible`
    - Implementar `GetEmbeddingsUrl()`: retornar `"https://api.openai.com/v1/embeddings"` (constante)
    - Implementar `ValidateConfig()`: chamar `##super()` + assert `modelName` e `apiKey` não vazios; lançar exceção identificando o campo ausente
    - _Requisitos: 4.1, 4.4, 3.1, 3.2_

  - [x] 3.2 Criar `dc.omniEmbedding.provider.AzureOpenAi`
    - Criar arquivo `src/dc/omniEmbedding/provider/AzureOpenAi.cls`; estende `OpenACompatible`
    - Implementar `GetEmbeddingsUrl()`: remover trailing slash de `apiBase`; se `apiBase` já contém `/openai/deployments/`, usar diretamente adicionando `?api-version={apiVersion}` apenas se ausente; caso contrário, compor `{apiBase}/openai/deployments/{deployment}/embeddings?api-version={apiVersion}`
    - Implementar `SetAuth()`: adicionar cabeçalho `api-key: {ResolveApiKey(config)}` (não `Authorization: Bearer`)
    - Implementar `ValidateConfig()`: chamar `##super()` + assert `apiBase`, `deployment`, `apiVersion` e `apiKey` não vazios
    - _Requisitos: 5.1, 5.2, 5.3, 5.4, 5.5_

  - [x]* 3.3 Escrever testes unitários para `dc.omniEmbedding.provider.AzureOpenAi`
    - Criar arquivo `tests/dc/omniEmbedding/TestAzureUrl.cls` extendendo `%UnitTest.TestCase`
    - **Property 8: Construção de URL Azure sem duplicação** — para qualquer combinação de `(apiBase, deployment, apiVersion)`, incluindo apiBase com trailing slash, URL completa e URL raiz, `GetEmbeddingsUrl()` retorna URL com exatamente uma ocorrência de `/openai/deployments/` terminando em `?api-version={apiVersion}`
    - **Validates: Requisitos 5.1, 5.2, 5.5**
    - Testar que cabeçalho `api-key` é usado (não `Authorization: Bearer`)
    - Testar `ValidateConfig()` para cada campo obrigatório ausente → exceção identificando o campo
    - _Requisitos: 5.1, 5.2, 5.3, 5.4, 5.5_

---

- [x] 4. Fase 3 — Cohere
  - [x] 4.1 Criar `dc.omniEmbedding.provider.Cohere`
    - Criar arquivo `src/dc/omniEmbedding/provider/Cohere.cls`; estende `Base`
    - Implementar `GetEmbeddingsUrl()`: retornar `"https://api.cohere.com/v2/embed"`
    - Implementar `SetAuth()`: adicionar cabeçalho `Authorization: Bearer {ResolveApiKey(config)}`
    - Implementar `BuildPayload()`: construir `{"texts": [input], "model": config.modelName, "input_type": config.inputType ?? "search_document", "embedding_types": ["float"]}`
    - Implementar `ParseResponse()`: extrair `body.embeddings.float[0]` (parse aninhado duplo) → `%Vector`; lançar exceção com corpo se campo ausente
    - Implementar `ValidateConfig()`: chamar `##super()` + assert `apiKey` não vazio
    - Implementar `EstimateTokenCount()`: `$FLOOR($LENGTH(text)/3.5) + 1`
    - _Requisitos: 7.1, 7.2, 7.3, 7.4, 7.5, 7.6_

  - [x]* 4.2 Escrever testes unitários para `dc.omniEmbedding.provider.Cohere`
    - Criar arquivo `tests/dc/omniEmbedding/TestCohere.cls` extendendo `%UnitTest.TestCase`
    - Testar `BuildPayload()` com `inputType` explícito e com `inputType` ausente (deve usar `"search_document"`)
    - **Property 10 (Cohere): Parse de resposta — rejeição de formato inesperado** — JSON sem `embeddings.float[0]` → exceção com corpo
    - **Validates: Requisito 7.4**
    - Testar `ParseResponse()` com resposta válida → `%Vector` correto
    - Testar `EstimateTokenCount()` com strings de tamanhos variados; verificar fórmula `Floor(ByteLen/3.5)+1`
    - _Requisitos: 7.1, 7.2, 7.3, 7.4, 7.6_

---

- [x] 5. Fase 4 — Gemini
  - [x] 5.1 Criar `dc.omniEmbedding.provider.Gemini`
    - Criar arquivo `src/dc/omniEmbedding/provider/Gemini.cls`; estende `Base`
    - Implementar `GetEmbeddingsUrl()`: retornar `"https://generativelanguage.googleapis.com/v1beta/models/" _ config.modelName _ ":embedContent?key=" _ ResolveApiKey(config)`
    - Implementar `SetAuth()` como no-op explícito (autenticação já na URL)
    - Implementar `BuildPayload()`: construir `{"content": {"parts": [{"text": input}]}, "taskType": "RETRIEVAL_DOCUMENT"}`
    - Implementar `ParseResponse()`: extrair `body.embedding.values` → `%Vector`; lançar exceção com corpo se campo ausente
    - Implementar `ValidateConfig()`: chamar `##super()` + assert `apiKey` não vazio
    - Implementar `EstimateTokenCount()`: `$FLOOR($LENGTH(text)/4) + 2`
    - _Requisitos: 8.1, 8.2, 8.3, 8.4, 8.5, 8.6_

  - [x]* 5.2 Escrever testes unitários para `dc.omniEmbedding.provider.Gemini`
    - Criar arquivo `tests/dc/omniEmbedding/TestGemini.cls` extendendo `%UnitTest.TestCase`
    - Testar `GetEmbeddingsUrl()` inclui `?key=` na URL e o `apiKey` resolvido
    - Testar `SetAuth()` não adiciona nenhum cabeçalho HTTP
    - Testar `BuildPayload()` inclui `taskType: "RETRIEVAL_DOCUMENT"` e estrutura `content.parts[0].text`
    - **Property 10 (Gemini): Parse de resposta — rejeição de formato inesperado** — JSON sem `embedding.values` → exceção com corpo
    - **Validates: Requisito 8.5**
    - Testar `EstimateTokenCount()` com fórmula `Floor(ByteLen/4)+2`
    - _Requisitos: 8.1, 8.2, 8.3, 8.4, 8.5, 8.6_

---

- [x] 6. Fase 5 — Resiliência: RetryWithBackoff e Circuit Breaker completos
  - [x] 6.1 Implementar `RetryWithBackoff()` completo em `dc.omniEmbedding.provider.Base`
    - Modificar arquivo `src/dc/omniEmbedding/provider/Base.cls`
    - Substituir o stub de `RetryWithBackoff()` pela implementação completa com loop `WHILE attempt < maxAttempts`
    - Ler parâmetros de retry de `config.retry`: `maxAttempts` (default 3), `baseDelayMs` (default 500), `maxDelayMs` (default 8000), `honorRetryAfter` (default 1)
    - Em status 2xx: retornar resposta imediatamente
    - Em status 429 ou 5xx: calcular delay; se `honorRetryAfter` e cabeçalho `Retry-After` presente, usar `Retry-After * 1000`; caso contrário, `MIN(baseDelayMs * 2^(attempt-1) + RAND(baseDelayMs), maxDelayMs)`; aguardar e retentar
    - Em status 4xx (exceto 429): lançar exceção imediata com status, URL e trecho do corpo (fast-fail, sem retry)
    - Após esgotar tentativas: lançar exceção com último status HTTP e URL
    - Usar `$ZSleep` ou `HANG` para aguardar; garantir que `delayMs ≤ maxDelayMs` em todo ponto
    - _Requisitos: 10.1, 10.2, 10.3, 10.4, 10.5, 10.6, 15.1_

  - [x] 6.2 Implementar Circuit Breaker completo em `dc.omniEmbedding.Engine`
    - Modificar arquivo `src/dc/omniEmbedding/Engine.cls`
    - Substituir stubs de `CheckBreaker()`, `RecordFailure()`, `RecordSuccess()` pela implementação completa baseada nos algoritmos do design
    - `CheckBreaker()`: ler `^omniEmbedding.Breaker(providerKey)`; se `failures < 5`, retornar 0; se `$ZTS - openedAt >= 60`, retornar 0 (half-open); caso contrário, retornar 1 (aberto)
    - `RecordFailure()`: incrementar `failures`; se `failures >= 5`, setar `openedAt = $ZTS`; escrever `$LISTBUILD(failures, openedAt)`
    - `RecordSuccess()`: escrever `$LISTBUILD(0, 0)` (zera contador e fecha circuito)
    - Atualizar `Embed()` para: após sucesso chamar `RecordSuccess`; após falha por esgotamento de tentativas chamar `RecordFailure` e então `TryFallback`
    - _Requisitos: 11.1, 11.2, 11.3, 11.4, 11.5, 11.6_

  - [x]* 6.3 Escrever testes para `RetryWithBackoff` e Circuit Breaker
    - Criar arquivo `tests/dc/omniEmbedding/TestResilience.cls` extendendo `%UnitTest.TestCase`
    - **Property 11: Retry honra Retry-After e limites de backoff** — com `honorRetryAfter=true` e cabeçalho `Retry-After: N`, delay ≥ N×1000ms; sem `Retry-After`, delay ≤ `maxDelayMs`
    - **Validates: Requisitos 10.2, 10.3**
    - **Property 12: Fast-fail em erros 4xx (exceto 429)** — para qualquer status 4xx ≠ 429, `RetryWithBackoff` lança exceção na primeira tentativa sem nenhuma retentativa
    - **Validates: Requisito 10.4**
    - **Property 13: Circuit breaker — abertura por limiar de falhas** — após exatamente 5 `RecordFailure`, `CheckBreaker` retorna 1 dentro de 60s e 0 após 60s
    - **Validates: Requisitos 11.2, 11.3, 11.4**
    - **Property 14: Circuit breaker — reset por sucesso** — após `RecordSuccess`, `CheckBreaker` retorna 0 e global é `$LISTBUILD(0,0)`
    - **Validates: Requisito 11.5**
    - Testar que `Embed()` chama `RecordSuccess` após resposta 2xx
    - Testar que `Embed()` chama `RecordFailure` após esgotar tentativas
    - _Requisitos: 10.1, 10.2, 10.3, 10.4, 10.5, 10.6, 11.1, 11.2, 11.3, 11.4, 11.5_

  - [x] 6.4 Checkpoint — Resiliência funcional
    - `RetryWithBackoff` retenta corretamente em 429/5xx e faz fast-fail em 4xx
    - Circuit breaker abre após 5 falhas e fecha após 60s ou sucesso
    - Todos os testes da Fase 5 passam; consultar o usuário se surgirem dúvidas

---

- [x] 7. Fase 6 — Fallback com Invariância de Espaço Vetorial
  - [x] 7.1 Implementar `TryFallback()` completo em `dc.omniEmbedding.Engine`
    - Modificar arquivo `src/dc/omniEmbedding/Engine.cls`
    - Substituir stub de `TryFallback()` pela implementação completa do algoritmo de validação de fallback
    - Iterar sobre `config.fallbacks` (array de nomes de `%Embedding.Config`); para cada nome, carregar a config via `##class(%Embedding.Config).%OpenId()` e parsear
    - Antes de executar qualquer chamada HTTP, verificar invariante de espaço vetorial: se `fbParsed.modelName ≠ config.modelName` OU `fbParsed.dimensions ≠ config.dimensions`, lançar exceção com nome do fallback incompatível, valores de ambos os lados
    - Se espaço vetorial compatível, chamar `Embed(input, fbParsed)` em `TRY/CATCH`; em caso de falha, continuar para o próximo fallback
    - Se todos os fallbacks esgotados, lançar exceção listando todos os tentados
    - Se `config.fallbacks` ausente/vazio e Provider primário falha, propagar exceção original
    - Atualizar `Embed()` para chamar `TryFallback` quando breaker aberto ou quando Provider falha após retries
    - _Requisitos: 12.1, 12.2, 12.3, 12.4, 12.5_

  - [x]* 7.2 Escrever testes para `TryFallback`
    - Criar arquivo `tests/dc/omniEmbedding/TestFallback.cls` extendendo `%UnitTest.TestCase`
    - **Property 4: Invariância de espaço vetorial no fallback** — para qualquer par (configPrimária, configFallback) com `modelName` ou `dimensions` distintos, `TryFallback` lança exceção identificando incompatibilidade sem executar chamada HTTP
    - **Validates: Requisito 12.2**
    - **Property 5: Fallback compatível é executado** — para par com mesmo `modelName` e `dimensions`, quando Provider primário falha, `TryFallback` executa o Provider do fallback
    - **Validates: Requisito 12.3**
    - Testar que `config.fallbacks` vazio propaga exceção original
    - Testar que todos os fallbacks esgotados lança exceção listando tentativas
    - Testar fallback CI com duas configs Ollama do mesmo espaço vetorial (requer Ollama)
    - _Requisitos: 12.1, 12.2, 12.3, 12.4, 12.5, 16.3_

---

- [x] 8. Fase 7 — Hardening: credenciais reais, token count polimórfico, IsValidConfig completo
  - [x] 8.1 Implementar `ResolveApiKey()` real em `dc.omniEmbedding.provider.Base`
    - Modificar arquivo `src/dc/omniEmbedding/provider/Base.cls`
    - Substituir stub por leitura via `##class(SYS.Database.PasswordCredential).%OpenId(config.apiKey)` (ou API equivalente do IRIS); usar o nome em `config.apiKey` como referência, nunca como valor
    - Lançar exceção com nome da credencial se não encontrada; NUNCA incluir o valor em mensagens de erro, logs ou traces
    - Usar macros `$$$ThrowStatus`, `$$$ERROR` ou `$$$GeneralError` conforme padrão ObjectScript IRIS
    - _Requisitos: 14.1, 14.2, 14.3, 14.4_

  - [x]* 8.2 Escrever testes de segurança para `ResolveApiKey`
    - Adicionar casos de teste em `tests/dc/omniEmbedding/TestProviderBase.cls`
    - **Property 15: Segurança de credencial — ausência de valor em exceções** — para credencial inexistente, exceção contém nome mas NÃO contém valor
    - **Validates: Requisitos 13.4, 14.3**
    - Testar que credencial encontrada retorna valor sem lançar exceção
    - Testar que `config.apiKey` ausente/vazio lança exceção para provedores que exigem chave
    - _Requisitos: 14.1, 14.2, 14.3_

  - [x] 8.3 Completar `IsValidConfig()` em `dc.omniEmbedding.Interface`
    - Modificar arquivo `src/dc/omniEmbedding/Interface.cls`
    - Implementar validação completa sem chamada HTTP: parsear JSON; chamar `Engine.ResolveProvider()` para determinar provedor; instanciar o Provider e chamar `ValidateConfig()` em bloco TRY/CATCH
    - Se `ValidateConfig()` lançar exceção, capturar e preencher `errorMsg` com a mensagem; retornar `0`
    - Se JSON sintaticamente inválido, preencher `errorMsg` com mensagem que permita distinguir de campo ausente; retornar `0`
    - Se `provider` e `modelName` ausentes, retornar `0` com `errorMsg` orientativo
    - Se config Ollama sem `apiKey`, retornar `1` (válida)
    - _Requisitos: 3.1, 3.2, 3.3, 3.4, 3.5, 3.6_

  - [x]* 8.4 Escrever testes completos para `IsValidConfig`
    - Adicionar casos de teste em `tests/dc/omniEmbedding/TestInterface.cls`
    - **Property 2: Rejeição de configuração inválida** — para qualquer provedor e qualquer campo obrigatório ausente, `IsValidConfig()` retorna `0` com `errorMsg` não vazio identificando o campo
    - **Validates: Requisitos 3.1, 3.2, 3.5**
    - Testar config Ollama válida sem `apiKey` → retorna `1`
    - Testar JSON inválido → retorna `0` com `errorMsg` distinguível de campo ausente
    - Testar `provider` e `modelName` ausentes → retorna `0`
    - _Requisitos: 3.1, 3.2, 3.3, 3.4, 3.5, 3.6_

  - [x] 8.5 Verificar e completar polimorfismo de `EstimateTokenCount`
    - Modificar `src/dc/omniEmbedding/Interface.cls`
    - Garantir que `Interface.EstimateTokenCount()` chama `Engine.ResolveProvider()`, instancia o Provider e delega para o `EstimateTokenCount()` correto do provedor
    - Verificar que `OpenACompatible.EstimateTokenCount()` usa cache por `config.modelName` para instância do tiktoken (não instancia por chamada)
    - Verificar que `Cohere.EstimateTokenCount()` usa fórmula `Floor(ByteLen/3.5)+1` e `Gemini.EstimateTokenCount()` usa `Floor(ByteLen/4)+2`
    - _Requisitos: 9.2, 9.3, 9.4, 9.5, 15.5_

  - [x]* 8.6 Escrever testes de propriedade end-to-end
    - Adicionar casos de teste nos arquivos de teste existentes
    - **Property 1: Dimensão correta do vetor retornado** — para qualquer `input` não vazio e config válida com `dimensions = D`, `Embedding()` retorna `%Vector` com `$VECTORLEN(resultado) = D` (via Ollama)
    - **Validates: Requisitos 1.1, 16.2**
    - **Property 3: Sem vetor vazio em falha** — para qualquer cenário de falha (rede, HTTP error, JSON malformado, credencial ausente), gateway lança exceção e NUNCA retorna `%Vector` de dimensão zero ou nulo
    - **Validates: Requisitos 13.2, 13.5**
    - Testar circuit breaker com N falhas simuladas via Ollama com URL inválida (opens após 5 falhas, fecha após 60s)
    - _Requisitos: 1.1, 13.2, 13.5, 16.2, 16.4_

  - [x] 8.7 Checkpoint final — Hardening completo
    - Todas as 8 fases implementadas e integradas
    - Todos os testes de todas as fases passam
    - `Interface`, `Engine` e todos os 5 Providers compilam sem erros no IRIS
    - Fluxo end-to-end `EMBEDDING('texto', 'config')` → `%Vector` funciona para Ollama em CI
    - Consultar o usuário antes de fechar a implementação se surgirem dúvidas

---

## Notes

- Tasks marcadas com `*` são opcionais e podem ser puladas para um MVP mais rápido
- Cada task referencia requisitos específicos para rastreabilidade
- Os checkpoints garantem validação incremental antes de avançar de fase
- Os testes de propriedade validam as invariantes universais do sistema (seção "Correctness Properties" do design)
- Os testes unitários validam exemplos específicos e casos de borda
- O fluxo CI via Ollama (sem chave) cobre o caminho feliz completo sem APIs pagas
- Todas as classes de produção seguem o padrão ObjectScript IRIS com `%occInclude` para macros de erro

## Task Dependency Graph

```json
{
  "waves": [
    { "id": 0, "tasks": ["1.1", "1.3", "1.5"] },
    { "id": 1, "tasks": ["1.2", "1.4", "1.6"] },
    { "id": 2, "tasks": ["2.1", "2.2"] },
    { "id": 3, "tasks": ["2.3", "2.4", "3.1", "3.2"] },
    { "id": 4, "tasks": ["3.3", "4.1", "5.1"] },
    { "id": 5, "tasks": ["4.2", "5.2", "6.1", "6.2"] },
    { "id": 6, "tasks": ["6.3", "7.1"] },
    { "id": 7, "tasks": ["7.2", "8.1", "8.3", "8.5"] },
    { "id": 8, "tasks": ["8.2", "8.4", "8.6"] }
  ]
}
```
