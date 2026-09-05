# Requirements Document

## Introduction

O `dc.omniEmbedding` é um gateway universal de embeddings para InterSystems IRIS. Ele se integra à infraestrutura nativa de embeddings do IRIS via `%Embedding.Interface`, permitindo que qualquer um dos cinco provedores externos suportados (Ollama, OpenAI, Azure OpenAI, Cohere, Gemini) seja consumido de forma transparente por aplicações que já utilizam `EMBEDDING()` SQL ou a API de classes nativa.

Os requisitos derivados a seguir refletem fielmente as decisões de design documentadas em `design.md`, especialmente os três pilares: HTTP nativo primeiro, polimorfismo por hierarquia de classes e integridade do espaço vetorial como invariante rígida.

---

## Glossary

- **Gateway**: O conjunto de classes `dc.omniEmbedding.*` que implementa o roteamento e a resiliência de chamadas de embedding.
- **Interface**: `dc.omniEmbedding.Interface` — classe-ponte que implementa `%Embedding.Interface` e expõe o gateway ao runtime do IRIS.
- **Engine**: `dc.omniEmbedding.Engine` — responsável pelo despacho ao provedor correto, circuit breaker e lógica de fallback.
- **Provider**: Subclasse concreta de `dc.omniEmbedding.provider.Base` que implementa a integração com um provedor externo específico.
- **Base**: `dc.omniEmbedding.provider.Base` — classe abstrata que define o Template Method `Execute` e os hooks polimórficos.
- **OpenACompatible**: `dc.omniEmbedding.provider.OpenACompatible` — subclasse intermediária para provedores com API compatível com OpenAI.
- **Config**: Objeto JSON armazenado no campo `Configuration` de `%Embedding.Config`, interpretado pelo gateway.
- **Vector_Space**: Par `(modelName, dimensions)` que identifica de forma única o espaço vetorial de um modelo.
- **Circuit_Breaker**: Mecanismo de proteção armazenado em `^omniEmbedding.Breaker` que suspende chamadas a um provedor após falhas consecutivas.
- **ResolveApiKey**: Método de `Base` que lê credenciais de `PasswordCredential` pelo nome; nunca expõe o valor em logs ou exceções.
- **Caller**: Qualquer código ObjectScript ou SQL que invoca `EMBEDDING()` ou chama `Interface.Embedding()` diretamente.

---

## Requirements

### Requisito 1: Integração com o Runtime de Embeddings do IRIS (FR-01)

**User Story:** Como desenvolvedor de aplicações IRIS, quero registrar `dc.omniEmbedding.Interface` como `EmbeddingClass` em `%Embedding.Config`, para que chamadas `EMBEDDING('texto', 'config')` retornem automaticamente um `%Vector` com a dimensão configurada, sem alterar meu código SQL ou ObjectScript existente.

#### Critérios de Aceitação

1. WHEN a `%Embedding.Config` tem `EmbeddingClass = "dc.omniEmbedding.Interface"` e o Caller executa `EMBEDDING(texto, nomeConfig)`, THE Interface SHALL retornar um `%Vector` cuja dimensão seja igual ao campo `dimensions` da Config.
2. WHEN o Caller invoca `##class(dc.omniEmbedding.Interface).Embedding(input, configurationJSON)` com `input` não vazio e `configurationJSON` válido, THE Interface SHALL parsear `configurationJSON` como `%DynamicObject`, delegar ao Engine e retornar um `%Vector` cuja dimensão seja igual ao campo `dimensions` do JSON.
3. IF `configurationJSON` for um JSON sintaticamente inválido, THEN THE Interface SHALL lançar `%Exception.General` cuja mensagem identifique que o erro é de parsing de JSON, sem realizar nenhuma chamada HTTP.
4. IF `configurationJSON` for um JSON válido mas o campo `dimensions` estiver ausente, for zero ou for negativo, THEN THE Interface SHALL lançar exceção identificando o campo inválido.
5. IF `input` for uma string vazia, THEN THE Interface SHALL lançar exceção indicando que o texto de entrada não pode ser vazio, sem realizar nenhuma chamada HTTP.
6. THE Interface SHALL implementar `Embedding()`, `IsValidConfig()` e `EstimateTokenCount()` em conformidade com as assinaturas definidas em `%Embedding.Interface`, de modo que o runtime de IRIS consiga invocar os três métodos através da interface nativa.

---

### Requisito 2: Resolução de Provedor (FR-02)

**User Story:** Como operador do sistema, quero que o gateway selecione automaticamente o provedor correto com base no campo `provider` da config ou, na sua ausência, pelo prefixo do `modelName`, para que eu não precise alterar a lógica de despacho ao adicionar ou trocar provedores.

#### Critérios de Aceitação

1. WHEN `config.provider` está presente e é um dos valores `"ollama"`, `"openai"`, `"azure"`, `"cohere"` ou `"gemini"`, THE Engine SHALL instanciar o Provider correspondente sem consultar `config.modelName`.
2. WHEN `config.provider` está ausente, THE Engine SHALL inferir o Provider pelo prefixo de `config.modelName` de acordo com a seguinte tabela de precedência, avaliada na ordem listada: `"nomic-"` → Ollama; `"text-embedding-"` → OpenAI; `"embed-"` → Cohere; `"embedding-"` → Gemini; e SHALL instanciar o primeiro Provider cujo prefixo corresponda ao início de `config.modelName` (comparação case-sensitive).
3. IF `config.provider` contiver um valor não reconhecido, THEN THE Engine SHALL lançar exceção indicando o valor recebido e a lista dos valores válidos (`"ollama"`, `"openai"`, `"azure"`, `"cohere"`, `"gemini"`), sem realizar nenhuma chamada HTTP.
4. IF `config.provider` estiver ausente e `config.modelName` não corresponder a nenhum prefixo conhecido, THEN THE Engine SHALL lançar exceção orientando o Caller a definir `config.provider` explicitamente, sem realizar nenhuma chamada HTTP.
5. IF `config.provider` estiver ausente e `config.modelName` também estiver ausente ou vazio, THEN THE Engine SHALL lançar exceção indicando que ao menos um dos campos `provider` ou `modelName` é obrigatório, sem realizar nenhuma chamada HTTP.
6. THE Engine SHALL suportar exatamente cinco provedores: Ollama, OpenAI, Azure OpenAI, Cohere e Gemini.

---

### Requisito 3: Validação de Configuração (FR-03)

**User Story:** Como desenvolvedor, quero validar uma config antes de usá-la em produção, para que erros de configuração sejam detectados imediatamente com mensagens acionáveis.

#### Critérios de Aceitação

1. WHEN o Caller invoca `Interface.IsValidConfig(configurationJSON, .errorMsg)` com uma config que omite campo obrigatório para o provedor selecionado, THE Interface SHALL retornar `0` e preencher `errorMsg` com o nome de ao menos um campo faltante e o identificador do provedor afetado.
2. WHEN o Caller invoca `Interface.IsValidConfig(configurationJSON, .errorMsg)` com uma config que contém todos os campos obrigatórios para o provedor selecionado com valores não vazios, THE Interface SHALL retornar `1` e deixar `errorMsg` vazia.
3. THE Interface SHALL realizar a validação sem efetuar nenhuma chamada HTTP.
4. IF `configurationJSON` for sintaticamente inválido como JSON, THEN THE Interface SHALL retornar `0` e preencher `errorMsg` com mensagem que permita distinguir um erro de parsing JSON de um erro de campo ausente.
5. WHEN o Caller invoca `Interface.IsValidConfig(configurationJSON, .errorMsg)` com config válida para o provedor `"ollama"` sem o campo `apiKey`, THE Interface SHALL retornar `1` (sem erro) pois `apiKey` não é obrigatório para Ollama.
6. IF `configurationJSON` for JSON válido mas não contiver o campo `provider` nem o campo `modelName`, THEN THE Interface SHALL retornar `0` e preencher `errorMsg` indicando que ao menos um dos dois campos é necessário para determinar o provedor.

---

### Requisito 4: Família OpenAI-Compatible — Payload e Parse (FR-04)

**User Story:** Como integrador, quero que Ollama, OpenAI e Azure OpenAI compartilhem a mesma lógica de construção de payload e parse de resposta, para evitar duplicação de código e garantir comportamento consistente.

#### Critérios de Aceitação

1. WHEN o OpenACompatible Provider envia uma requisição, THE OpenACompatible SHALL construir o payload como `{"input": input, "model": config.modelName}`.
2. WHEN a resposta HTTP retorna um JSON com o campo `data[0].embedding`, THE OpenACompatible SHALL extrair esse array e retornar um `%Vector` correspondente.
3. IF a resposta não contiver o campo `data[0].embedding`, THEN THE OpenACompatible SHALL lançar exceção com o conteúdo do corpo da resposta para diagnóstico.
4. THE OpenACompatible SHALL adicionar o cabeçalho `Authorization: Bearer {apiKey}` em todas as requisições, onde `apiKey` é resolvido via `ResolveApiKey`.
5. THE OpenACompatible.EstimateTokenCount SHALL usar tiktoken via Embedded Python quando disponível, com cache por nome de modelo, e SHALL cair para o piso conservador de `Base` quando tiktoken não estiver disponível.

---

### Requisito 5: URL Segura para Azure OpenAI (FR-05)

**User Story:** Como operador usando Azure OpenAI, quero que o gateway componha corretamente a URL do endpoint de embeddings independentemente de `apiBase` ser uma raiz ou uma URL completa, para evitar duplicação de segmentos de path.

#### Critérios de Aceitação

1. WHEN `config.apiBase` não contém o segmento `/openai/deployments/`, THE AzureOpenAi Provider SHALL compor a URL como `{apiBase}/openai/deployments/{deployment}/embeddings?api-version={apiVersion}`.
2. WHEN `config.apiBase` já contém o segmento `/openai/deployments/`, THE AzureOpenAi Provider SHALL usar `apiBase` diretamente, adicionando `?api-version={apiVersion}` somente se ausente.
3. THE AzureOpenAi Provider SHALL adicionar o cabeçalho `api-key: {apiKey}` (não `Authorization: Bearer`).
4. IF qualquer um dos campos `apiBase`, `deployment` ou `apiVersion` estiver ausente, THEN THE AzureOpenAi Provider SHALL lançar exceção em `ValidateConfig` antes de qualquer chamada HTTP.
5. THE AzureOpenAi Provider SHALL remover trailing slash de `apiBase` antes de compor a URL.

---

### Requisito 6: Integração com Ollama sem Chave (FR-06)

**User Story:** Como desenvolvedor, quero usar Ollama local em CI sem precisar configurar `apiKey`, para que o pipeline de integração contínua funcione sem segredos.

#### Critérios de Aceitação

1. WHEN `config.provider = "ollama"` e `config.apiKey` está ausente ou vazio, THE Ollama Provider SHALL executar a requisição HTTP sem cabeçalho `Authorization`.
2. THE Ollama.ValidateConfig SHALL NOT lançar erro por ausência de `apiKey`.
3. WHEN `config.apiBase` está ausente, THE Ollama Provider SHALL usar `http://localhost:11434` como valor padrão.
4. THE Ollama Provider SHALL enviar a requisição para `{config.apiBase}/v1/embeddings`.
5. WHEN o Caller usa Ollama com uma config válida em ambiente CI, THE Gateway SHALL completar o fluxo `EMBEDDING('texto', config)` → `%Vector` sem exigir credenciais externas.

---

### Requisito 7: Integração com Cohere (FR-07)

**User Story:** Como integrador usando Cohere, quero que o gateway envie o `input_type` correto e parse o caminho aninhado da resposta, para que os embeddings gerados usem a representação semântica adequada ao caso de uso.

#### Critérios de Aceitação

1. WHEN o Cohere Provider envia uma requisição, THE Cohere Provider SHALL construir o payload como `{"texts": [input], "model": config.modelName, "input_type": config.inputType, "embedding_types": ["float"]}`.
2. WHEN `config.inputType` está ausente, THE Cohere Provider SHALL usar `"search_document"` como valor padrão.
3. WHEN a resposta HTTP retorna JSON com o campo `embeddings.float[0]`, THE Cohere Provider SHALL extrair esse array e retornar um `%Vector` correspondente.
4. IF a resposta não contiver o campo `embeddings.float[0]`, THEN THE Cohere Provider SHALL lançar exceção com o conteúdo do corpo para diagnóstico.
5. THE Cohere Provider SHALL adicionar o cabeçalho `Authorization: Bearer {apiKey}` resolvido via `ResolveApiKey`.
6. THE Cohere.EstimateTokenCount SHALL usar a fórmula `Floor(ByteLen(text)/3.5) + 1`.

---

### Requisito 8: Integração com Gemini (FR-08)

**User Story:** Como integrador usando Gemini, quero que o gateway autentique via query string e parse a estrutura de resposta específica do Gemini, para consumir o modelo de embeddings do Google sem adaptações no meu código.

#### Critérios de Aceitação

1. THE Gemini Provider SHALL construir a URL como `https://generativelanguage.googleapis.com/v1beta/models/{config.modelName}:embedContent?key={apiKey}`, onde `apiKey` é resolvido via `ResolveApiKey`.
2. THE Gemini.SetAuth SHALL ser um no-op, pois a autenticação já está embutida na URL construída por `GetEmbeddingsUrl`.
3. WHEN o Gemini Provider envia uma requisição, THE Gemini Provider SHALL construir o payload como `{"content": {"parts": [{"text": input}]}, "taskType": "RETRIEVAL_DOCUMENT"}`.
4. WHEN a resposta HTTP retorna JSON com o campo `embedding.values`, THE Gemini Provider SHALL extrair esse array e retornar um `%Vector` correspondente.
5. IF a resposta não contiver o campo `embedding.values`, THEN THE Gemini Provider SHALL lançar exceção com o conteúdo do corpo para diagnóstico.
6. THE Gemini.EstimateTokenCount SHALL usar a fórmula `Floor(ByteLen(text)/4) + 2`.

---

### Requisito 9: Estimativa de Contagem de Tokens (FR-09)

**User Story:** Como desenvolvedor, quero estimar o número de tokens de um texto antes de enviá-lo, para evitar erros de limite de contexto e controlar custos.

#### Critérios de Aceitação

1. THE Base.EstimateTokenCount SHALL retornar `Floor(ByteLen(text)/4) + 1` como piso conservador para qualquer Provider.
2. WHEN tiktoken está disponível via Embedded Python, THE OpenACompatible.EstimateTokenCount SHALL usar tiktoken com cache por nome de modelo e retornar a contagem precisa de tokens.
3. WHEN tiktoken não está disponível, THE OpenACompatible.EstimateTokenCount SHALL cair para o piso da Base sem lançar exceção.
4. THE Interface.EstimateTokenCount SHALL delegar ao Provider resolvido pela config.
5. THE EstimateTokenCount de cada Provider concreto SHALL nunca instanciar um novo cliente ou encoder por chamada — recursos caros devem ser cacheados.

---

### Requisito 10: Retry com Backoff Exponencial (FR-10)

**User Story:** Como operador, quero que o gateway tente novamente automaticamente em caso de erros transitórios, para aumentar a resiliência sem intervenção manual.

#### Critérios de Aceitação

1. WHEN a resposta HTTP retorna status `429` ou qualquer status `5xx`, THE Base.RetryWithBackoff SHALL aguardar e retentar a requisição.
2. WHEN `config.retry.honorRetryAfter = true` e a resposta `429` contém o cabeçalho `Retry-After: N`, THE Base.RetryWithBackoff SHALL aguardar pelo menos `N * 1000` milissegundos antes de retentar.
3. WHEN `config.retry.honorRetryAfter` é false ou o cabeçalho `Retry-After` está ausente, THE Base.RetryWithBackoff SHALL calcular o delay como `MIN(baseDelayMs * 2^(attempt-1) + jitter, maxDelayMs)`, onde `jitter` é um valor aleatório no intervalo `[0, baseDelayMs)`.
4. WHEN a resposta HTTP retorna um status `4xx` diferente de `429`, THE Base.RetryWithBackoff SHALL lançar exceção imediata (fast-fail) sem retentar.
5. IF todas as tentativas forem esgotadas, THEN THE Base.RetryWithBackoff SHALL lançar exceção contendo o status HTTP do último erro e a URL chamada.
6. THE Base.RetryWithBackoff SHALL respeitar `config.retry.maxAttempts` (padrão: `3`), `config.retry.baseDelayMs` (padrão: `500`) e `config.retry.maxDelayMs` (padrão: `8000`).

---

### Requisito 11: Circuit Breaker (FR-11)

**User Story:** Como operador, quero que o gateway suspenda automaticamente chamadas a um provedor instável após falhas consecutivas, para proteger o sistema e permitir recuperação sem intervenção manual.

#### Critérios de Aceitação

1. THE Engine SHALL manter o estado do Circuit_Breaker em `^omniEmbedding.Breaker(providerKey)` como `$ListBuild(consecutiveFailures, openedAtSeconds)`.
2. WHEN o número de falhas consecutivas de um Provider atinge o limiar de `5`, THE Engine.RecordFailure SHALL abrir o circuito registrando o timestamp atual em `openedAtSeconds`.
3. WHILE o circuito de um Provider estiver aberto e o cooldown de `60` segundos não tiver expirado, THE Engine.CheckBreaker SHALL retornar `1` (aberto) e THE Engine SHALL tentar o fallback sem chamar o Provider primário.
4. WHEN o cooldown de `60` segundos expira, THE Engine.CheckBreaker SHALL retornar `0` (half-open), permitindo uma tentativa de chamada ao Provider.
5. WHEN uma chamada ao Provider tem sucesso, THE Engine.RecordSuccess SHALL zerar `consecutiveFailures` e fechar o circuito (setar `openedAtSeconds = 0`).
6. THE Engine.ProviderKey SHALL gerar a chave como `provider + "|" + modelName + "|" + apiBase`.

---

### Requisito 12: Fallback com Invariância de Espaço Vetorial (FR-12)

**User Story:** Como arquiteto de dados, quero que o gateway nunca misture vetores de espaços vetoriais distintos em uma operação de fallback, para preservar a integridade semântica dos dados armazenados.

#### Critérios de Aceitação

1. WHEN o Provider primário falha e `config.fallbacks` contém nomes de configs, THE Engine.TryFallback SHALL tentar cada config de fallback na ordem listada.
2. WHEN uma config de fallback tem `modelName` diferente do Provider primário OU `dimensions` diferente, THE Engine.TryFallback SHALL lançar exceção identificando o nome da config incompatível, os valores de `modelName` e `dimensions` de ambas, e SHALL NOT executar a chamada HTTP para esse fallback.
3. WHEN uma config de fallback tem o mesmo `Vector_Space` que o Provider primário (mesmo `modelName` E mesmo `dimensions`), THE Engine.TryFallback SHALL executar a chamada ao fallback Provider.
4. IF todas as configs de fallback forem esgotadas sem sucesso, THEN THE Engine.TryFallback SHALL lançar exceção listando todos os fallbacks tentados.
5. IF `config.fallbacks` estiver ausente ou vazio e o Provider primário falhar, THEN THE Engine SHALL propagar a exceção original do Provider primário ao Caller.

---

### Requisito 13: Tratamento de Erros — Exceção com Contexto (FR-13)

**User Story:** Como desenvolvedor, quero que qualquer falha do gateway resulte em uma exceção com contexto suficiente para diagnóstico, para não receber vetores silenciosamente incorretos nem mensagens de erro genéricas.

#### Critérios de Aceitação

1. IF qualquer Provider falhar por erro HTTP, THEN THE Provider SHALL lançar exceção contendo o status HTTP, a URL chamada e um trecho do corpo da resposta.
2. THE Gateway SHALL NUNCA retornar um `%Vector` de dimensão zero ou nulo em casos de falha.
3. IF `ParseResponse` não encontrar o campo de embedding esperado na resposta, THEN THE Provider SHALL lançar exceção com o conteúdo do corpo recebido para facilitar o diagnóstico.
4. IF `ResolveApiKey` não conseguir resolver a credencial, THEN THE Base SHALL lançar exceção identificando o nome da credencial não encontrada, sem expor valores de segredos.
5. THE Engine SHALL propagar toda exceção não recuperável ao Caller sem suprimí-la nem substituí-la por vetor vazio.

---

### Requisito 14: Segurança de Credenciais (NFR-01, NFR-07)

**User Story:** Como administrador de segurança, quero que chaves de API nunca sejam armazenadas em texto plano na configuração e nunca apareçam em logs ou mensagens de erro, para estar em conformidade com as políticas de segurança da organização.

#### Critérios de Aceitação

1. THE Base.ResolveApiKey SHALL ler o valor da credencial a partir de `PasswordCredential` usando o nome armazenado em `config.apiKey`, nunca tratando `config.apiKey` como o valor direto da chave.
2. THE Base.ResolveApiKey SHALL NUNCA incluir o valor da credencial resolvida em mensagens de log, exceções ou traces de erro.
3. IF `config.apiKey` referenciar uma credencial inexistente, THEN THE Base.ResolveApiKey SHALL lançar exceção contendo apenas o nome da credencial, sem nenhum valor.
4. THE Provider classes SHALL usar as macros `$$$ThrowStatus`, `$$$ERROR` e `$$$GeneralError` via `%occInclude` para geração de erros, mantendo consistência com o padrão ObjectScript IRIS.

---

### Requisito 15: Transporte HTTP Nativo e SSL (NFR-03, NFR-04)

**User Story:** Como arquiteto, quero que o gateway use exclusivamente `%Net.HttpRequest` como transporte e respeite a configuração SSL, para não introduzir dependências externas no caminho principal e garantir comunicação segura com APIs na nuvem.

#### Critérios de Aceitação

1. THE Base.Execute SHALL usar `%Net.HttpRequest` como único mecanismo de transporte HTTP, sem dependências Python no caminho principal (feliz).
2. WHEN `config.sslConfig` está presente e não vazio, THE Base.Execute SHALL atribuir `request.SSLConfiguration = config.sslConfig` antes de enviar a requisição.
3. WHEN `config.sslConfig` está ausente, THE Base.Execute SHALL usar o valor padrão do `%Net.HttpRequest` sem lançar exceção.
4. THE Base.Execute SHALL atribuir `request.Timeout = config.httpTimeout` quando `config.httpTimeout` estiver presente, usando `30` segundos como padrão.
5. THE Gateway SHALL NOT instanciar clientes HTTP, encoders tiktoken ou qualquer outro recurso caro por chamada — tais recursos devem ser cacheados no nível de classe ou processo.

---

### Requisito 16: Exercitabilidade em CI via Ollama (NFR-08)

**User Story:** Como engenheiro de DevOps, quero que o caminho completo do gateway seja exercitável em CI usando Ollama local sem chave, para garantir cobertura de integração contínua sem depender de APIs externas pagas.

#### Critérios de Aceitação

1. WHEN o ambiente CI tem Ollama disponível em `http://localhost:11434`, THE Gateway SHALL completar o fluxo end-to-end `EMBEDDING('texto', config)` → `%Vector` para uma config Ollama válida sem nenhuma chave de API.
2. THE Gateway SHALL verificar a dimensão do `%Vector` retornado contra `config.dimensions` e lançar exceção se houver divergência.
3. WHEN duas configs Ollama com o mesmo `Vector_Space` estão configuradas como primária e fallback, THE Gateway SHALL executar o fallback com sucesso quando o Provider primário falha (simulado por config inválida).
4. WHEN N falhas consecutivas são simuladas para um Provider Ollama, THE Circuit_Breaker SHALL abrir e fechar conforme os parâmetros de `FAILURE_THRESHOLD = 5` e `COOLDOWN_SECONDS = 60`.

---

## Expansão de Providers (v1.1+)

Os requisitos abaixo foram adicionados após a entrega da v1.0. Eles ampliam a lista de provedores suportados sem alterar contratos existentes (Interface, Engine, Base) — apenas adicionam novas subclasses de Provider e novos ramos de despacho em `Engine.ResolveProvider`.

**Prefixo de inferência atualizado**: `mistral-` / `codestral-` → Mistral; `voyage-` → Voyage; `jina-` / `jina-embeddings-` → Jina; para Bedrock, prefixo derivado do `modelId` (`amazon.titan-embed-`, `cohere.embed-` via Bedrock) só é seguro quando `provider = "bedrock"` está explícito, pois `cohere.embed-` colide com o Cohere direto.

---

### Requisito 17: Integração com Mistral (FR-14) — implementado

**User Story:** Como integrador, quero usar Mistral (texto via `mistral-embed`, código via `codestral-embed`) através da mesma interface, para consolidar embeddings de conteúdo natural e código-fonte sob um único gateway.

#### Critérios de Aceitação

1. WHEN `config.provider = "mistral"` OU `config.modelName` começa com `"mistral-"` ou `"codestral-"`, THE Engine SHALL instanciar `dc.omniEmbedding.provider.Mistral`.
2. THE Mistral Provider SHALL construir a URL como `https://api.mistral.ai/v1/embeddings` (constante).
3. THE Mistral Provider SHALL herdar `BuildPayload` e `ParseResponse` de `OpenACompatible` (payload `{input, model}`, resposta `data[0].embedding`).
4. WHEN `config.outputDimension` está presente, THE Mistral Provider SHALL adicionar o campo `output_dimension` ao payload (truncação server-side, útil para Codestral que suporta até 3072).
5. WHEN `config.outputDtype` está presente, THE Mistral Provider SHALL adicionar o campo `output_dtype` ao payload (valores válidos: `float`, `int8`, `uint8`, `binary`, `ubinary`).
6. THE Mistral Provider SHALL adicionar o cabeçalho `Authorization: Bearer {apiKey}` resolvido via `ResolveApiKey`.
7. THE Mistral.ValidateConfig SHALL exigir `modelName` e `apiKey` não vazios.

---

### Requisito 18: Integração com Voyage AI (FR-15)

**User Story:** Como integrador que já usa Voyage em pipelines de RAG, quero consumir `voyage-3`, `voyage-3-large`, `voyage-code-3` e famílias domain-specific (`voyage-finance-2`, `voyage-law-2`, `voyage-multilingual-2`) através do gateway, para unificar o código de retrieval independentemente do provedor.

#### Critérios de Aceitação

1. WHEN `config.provider = "voyage"` OU `config.modelName` começa com `"voyage-"`, THE Engine SHALL instanciar `dc.omniEmbedding.provider.Voyage`.
2. THE Voyage Provider SHALL construir a URL como `https://api.voyageai.com/v1/embeddings` (constante).
3. THE Voyage Provider SHALL herdar `ParseResponse` de `OpenACompatible` (resposta `data[0].embedding`).
4. THE Voyage.BuildPayload SHALL construir `{"input": input, "model": modelName}` e adicionar passthrough opcional para os campos:
   - `input_type` (valores esperados pela Voyage: `"query"` ou `"document"`) quando `config.inputType` presente
   - `truncation` (booleano) quando `config.truncation` presente
   - `output_dimension` (inteiro) quando `config.outputDimension` presente
   - `output_dtype` (`float`|`int8`|`uint8`|`binary`|`ubinary`) quando `config.outputDtype` presente
5. THE Voyage Provider SHALL adicionar o cabeçalho `Authorization: Bearer {apiKey}` resolvido via `ResolveApiKey`.
6. THE Voyage.ValidateConfig SHALL exigir `modelName` e `apiKey` não vazios.
7. IF `config.inputType` estiver presente com valor diferente de `"query"` ou `"document"`, THEN THE Voyage.ValidateConfig SHALL lançar exceção identificando o campo e os valores válidos.

---

### Requisito 19: Integração com Jina AI (FR-16)

**User Story:** Como desenvolvedor, quero consumir os modelos de embedding da Jina (`jina-embeddings-v3` e derivados) através do gateway, aproveitando features como `late_chunking` para documentos longos sem alterar meu código de retrieval.

#### Critérios de Aceitação

1. WHEN `config.provider = "jina"` OU `config.modelName` começa com `"jina-"` ou `"jina-embeddings-"`, THE Engine SHALL instanciar `dc.omniEmbedding.provider.Jina`.
2. THE Jina Provider SHALL construir a URL como `https://api.jina.ai/v1/embeddings` (constante).
3. THE Jina Provider SHALL herdar `ParseResponse` de `OpenACompatible` (resposta `data[0].embedding`).
4. THE Jina.BuildPayload SHALL construir `{"input": [input], "model": modelName}` (Jina exige `input` como array mesmo para um único texto) e adicionar passthrough opcional para os campos:
   - `task` (ex.: `"retrieval.query"`, `"retrieval.passage"`, `"text-matching"`, `"classification"`) quando `config.task` presente
   - `dimensions` (inteiro — truncação server-side) quando `config.outputDimension` presente
   - `late_chunking` (booleano) quando `config.lateChunking` presente
   - `embedding_type` (`float`|`base64`|`binary`|`ubinary`) quando `config.outputDtype` presente
5. THE Jina Provider SHALL adicionar o cabeçalho `Authorization: Bearer {apiKey}` resolvido via `ResolveApiKey`.
6. THE Jina.ValidateConfig SHALL exigir `modelName` e `apiKey` não vazios.

---

### Requisito 20: Integração com AWS Bedrock (FR-17)

**User Story:** Como arquiteto em uma organização que padroniza modelos via AWS Bedrock, quero consumir os embeddings hospedados na Bedrock (Titan v2, Cohere via Bedrock) através do mesmo gateway, mantendo autenticação por credenciais IAM e roteamento por `region` sem depender de SDKs externos.

#### Critérios de Aceitação

1. WHEN `config.provider = "bedrock"`, THE Engine SHALL instanciar `dc.omniEmbedding.provider.Bedrock`.
2. THE Bedrock Provider SHALL construir a URL como `https://bedrock-runtime.{region}.amazonaws.com/model/{modelId}/invoke`, onde `region` vem de `config.region` e `modelId` vem de `config.modelName`.
3. THE Bedrock Provider SHALL autenticar cada requisição via **AWS Signature Version 4** (SigV4) sobre o serviço `bedrock`, usando `accessKeyId`, `secretAccessKey` (via `ResolveApiKey` — o nome da credencial é `config.apiKey`; o segredo resolvido é interpretado como `{accessKeyId}:{secretAccessKey}` ou como JSON `{"accessKeyId":"...","secretAccessKey":"..."}`) e opcionalmente `sessionToken` (via `config.sessionTokenCredential` — outro nome de credencial resolvido separadamente).
4. THE Bedrock Provider SHALL despachar o payload e parse conforme o `modelId`:
   - IF `modelId` começa com `"amazon.titan-embed-"`, THEN payload = `{"inputText": input, "dimensions": config.dimensions, "normalize": true}` e resposta parseada em `.embedding`.
   - IF `modelId` começa com `"cohere.embed-"` (via Bedrock), THEN payload = `{"texts": [input], "input_type": config.inputType ?? "search_document"}` e resposta parseada em `.embeddings[0]`.
5. IF `config.region` estiver ausente, THEN THE Bedrock.ValidateConfig SHALL lançar exceção identificando o campo.
6. IF `modelId` não corresponder a nenhuma família suportada (Titan, Cohere via Bedrock), THEN THE Bedrock Provider SHALL lançar exceção listando as famílias suportadas.
7. THE Bedrock.SigV4 SHALL derivar a chave de assinatura via `HMAC-SHA256("aws4_request", HMAC-SHA256("bedrock", HMAC-SHA256(region, HMAC-SHA256(date, "AWS4"+secretAccessKey))))` conforme especificação AWS.
8. THE Bedrock.SigV4 SHALL montar o cabeçalho `Authorization: AWS4-HMAC-SHA256 Credential={accessKeyId}/{date}/{region}/bedrock/aws4_request, SignedHeaders={headers}, Signature={hex}`.
9. THE Bedrock Provider SHALL adicionar os cabeçalhos `x-amz-date` (ISO8601 UTC compact) e, se `sessionToken` presente, `x-amz-security-token`.
10. THE Bedrock Provider SHALL NUNCA logar `secretAccessKey`, `sessionToken` nem a `Signature` — apenas o `accessKeyId` (identificador público) e o `Credential Scope` podem aparecer em mensagens de erro/diagnóstico.

---

### Requisito 21: Integração com Google Vertex AI (FR-18)

**User Story:** Como arquiteto em uma organização padronizada em Google Cloud, quero consumir os modelos de embedding do Vertex AI (`text-embedding-004`, `text-embedding-005`, `gemini-embedding-001`) — que ficam sob endpoints regionais autenticados por OAuth 2.0 — através do mesmo gateway, mantendo isolamento de credencial e roteamento por projeto/região sem depender de SDKs externos.

#### Critérios de Aceitação

1. WHEN `config.provider = "vertex"` OU `config.provider = "vertexai"` (alias comum), THE Engine SHALL instanciar `dc.omniEmbedding.provider.VertexAi`.
2. THE Engine SHALL NOT inferir Vertex a partir de prefixo de `modelName` — `text-embedding-*` colide com OpenAI e `embedding-*` colide com Gemini direto. Vertex exige `provider` explícito.
3. THE VertexAi Provider SHALL construir a URL como `https://{region}-aiplatform.googleapis.com/v1/projects/{project}/locations/{region}/publishers/google/models/{modelName}:predict`.
4. THE VertexAi Provider SHALL adicionar o cabeçalho `Authorization: Bearer {accessToken}`, onde `accessToken` é o valor resolvido via `ResolveApiKey` (o nome da credencial vem de `config.apiKey` e o segredo armazenado é o próprio token OAuth 2.0 válido).
5. THE VertexAi.BuildPayload SHALL construir `{"instances":[{"content": input}]}` e adicionar campos opcionais no nível da instância:
   - `task_type` (valores como `RETRIEVAL_QUERY`, `RETRIEVAL_DOCUMENT`, `SEMANTIC_SIMILARITY`, `CLASSIFICATION`, `CLUSTERING`, `CODE_RETRIEVAL_QUERY`) quando `config.taskType` presente
   - `title` (metadados úteis apenas com `RETRIEVAL_DOCUMENT`) quando `config.title` presente
6. THE VertexAi.BuildPayload SHALL emitir o bloco `parameters` APENAS quando pelo menos um de `config.outputDimension` OU `config.autoTruncate` estiver presente, mapeando:
   - `outputDimension` → `outputDimensionality` (inteiro)
   - `autoTruncate` → `autoTruncate` (booleano)
7. THE VertexAi.ParseResponse SHALL extrair `body.predictions[0].embeddings.values` → `%Vector`; lançar exceção com o corpo da resposta se qualquer campo do caminho estiver ausente.
8. THE VertexAi.ValidateConfig SHALL exigir `modelName`, `region`, `project` e `apiKey` não vazios; a ausência de qualquer um lança exceção identificando o campo.
9. THE VertexAi Provider SHALL delegar refresh do access token OAuth 2.0 ao chamador — o gateway não implementa fluxo de service account JWT-bearer nem uso de metadata server em v1.1. Documentar como escopo futuro se for necessário auto-refresh.
