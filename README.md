[![Gitter](https://img.shields.io/badge/Available%20on-Intersystems%20Open%20Exchange-00b2a9.svg)](https://openexchange.intersystems.com/)
[![License: MIT](https://img.shields.io/badge/License-MIT-blue.svg?style=flat&logo=AdGuard)](LICENSE)
[![InterSystems IRIS](https://img.shields.io/badge/InterSystems-IRIS%202026%2B-blue.svg)](https://www.intersystems.com/)
[![ObjectScript](https://img.shields.io/badge/ObjectScript-native-informational.svg)](https://docs.intersystems.com/)

![OmniEmbedding Logo](./assets/omni-logo.png)

# 🧠 dc.omniEmbedding

**The Universal Embedding Gateway for InterSystems IRIS**

> *One `EMBEDDING()` call. Any provider. Same vector space.*

---

## 🌌 Motivation

InterSystems IRIS 2026 ships a native embeddings runtime — `%Embedding.Interface` + `EMBEDDING()` SQL — but each embedding provider has its own quirks:

- **Ollama** speaks OpenAI-compatible JSON but needs no auth
- **OpenAI** uses `Authorization: Bearer`
- **Azure OpenAI** wants `api-key` (not `Bearer`) and a deployment-scoped URL
- **Cohere** returns embeddings under `embeddings.float[0]`
- **Gemini** authenticates via `?key=` on the URL itself
- **Mistral** is OpenAI-shaped but adds `output_dimension` / `output_dtype` for Codestral truncation
- **Voyage AI** adds `input_type` (`query` vs `document`), truncation and int8/binary quantization
- **Jina AI** requires `input` as an array (even for one text) and exposes `task` + `late_chunking` for coherent long-doc chunks
- **AWS Bedrock** speaks SigV4 (not Bearer) and switches payload/response shape per family (`amazon.titan-embed-*` vs `cohere.embed-*` hosted on Bedrock)
- **Google Vertex AI** needs region + project in the URL and an OAuth 2.0 access token in the header — the same `text-embedding-*` family name as OpenAI lives here too

Swapping providers usually means rewriting glue code, and mixing them in fallback flows silently mixes vector spaces — a data-integrity disaster that only surfaces months later, when your similarity searches start returning nonsense.

**`dc.omniEmbedding` changes that.**

Plug it in once as your `EmbeddingClass` and every `EMBEDDING('text', 'config')` call — from SQL, from ObjectScript, from Interoperability — routes to the right provider, retries transient errors, opens a circuit breaker on failing providers, and **refuses** to fall back to a config whose vector space differs from the primary.

- ✅ **Ten providers, one interface:** Ollama · OpenAI · Azure OpenAI · Cohere · Gemini · Mistral (text + code) · Voyage (text + code + domain) · Jina (with `late_chunking`) · AWS Bedrock (SigV4, Titan + Cohere via Bedrock) · Google Vertex AI (text-embedding + gemini-embedding)
- ✅ **Native HTTP:** `%Net.HttpRequest` — no Python required on the hot path
- ✅ **Resilient:** exponential backoff, `Retry-After` honored, circuit breaker per provider
- ✅ **Safe fallback:** vector-space invariance is enforced *before* any HTTP call
- ✅ **Secure by default:** `apiKey` is a **credential name**, never the raw secret
- ✅ **CI-friendly:** the whole happy path runs against local Ollama, no cloud keys

---

## 🛠️ How It Works

`dc.omniEmbedding` sits between IRIS's native embedding runtime and any of the ten supported external providers, applying three architectural pillars:

1. **HTTP native first** — the happy path uses `%Net.HttpRequest` end-to-end; Embedded Python is opt-in only (for accurate `tiktoken` token counts).
2. **Polymorphism by class hierarchy** — a Template Method in `provider.Base` fixes the sequence `ValidateConfig → SetAuth → GetEmbeddingsUrl → BuildPayload → RetryWithBackoff → ParseResponse`; each provider overrides only what differs.
3. **Vector-space integrity as a hard invariant** — a fallback with a different `modelName` or `dimensions` is *fatal*, never a silent downgrade.

### **Core Components**

| Class | Role |
|---|---|
| `dc.omniEmbedding.Interface` | Bridge to `%Embedding.Interface` — the class you register in `%Embedding.Config` |
| `dc.omniEmbedding.Engine` | Provider resolution, circuit breaker, fallback with vector-space check |
| `dc.omniEmbedding.provider.Base` | Abstract Template Method; retry/backoff; credential resolution |
| `dc.omniEmbedding.provider.OpenACompatible` | Shared payload/parse for the OpenAI-shaped family |
| `dc.omniEmbedding.provider.Ollama` | Local Ollama, keyless, `/v1/embeddings` |
| `dc.omniEmbedding.provider.OpenAi` | `api.openai.com`, `Bearer` auth |
| `dc.omniEmbedding.provider.AzureOpenAi` | Deployment-scoped URL, `api-key` header |
| `dc.omniEmbedding.provider.Cohere` | `v2/embed`, nested `embeddings.float[0]` |
| `dc.omniEmbedding.provider.Gemini` | Auth via `?key=`, `content.parts[].text` payload |
| `dc.omniEmbedding.provider.Mistral` | `api.mistral.ai/v1/embeddings`, text (`mistral-embed`) + code (`codestral-embed`), optional `output_dimension` / `output_dtype` |
| `dc.omniEmbedding.provider.Voyage` | `api.voyageai.com/v1/embeddings`, text (`voyage-3*`) + code (`voyage-code-3`) + domain (`voyage-finance-2`, `voyage-law-2`, `voyage-multilingual-2`); `input_type` (`query`/`document`), `truncation`, `output_dimension`, `output_dtype` |
| `dc.omniEmbedding.provider.Jina` | `api.jina.ai/v1/embeddings`, `jina-embeddings-v3` and `jina-*` variants; `input` wrapped as array; `task`, `dimensions`, `late_chunking`, `embedding_type` |
| `dc.omniEmbedding.provider.Bedrock` | `bedrock-runtime.{region}.amazonaws.com/model/{modelId}/invoke`; **SigV4** auth via `util.SigV4`; families `amazon.titan-embed-*` (`inputText`/`normalize`, response `.embedding`) and `cohere.embed-*` on Bedrock (`texts[]`/`input_type`, response `.embeddings[0]`); optional `sessionTokenCredential` for STS/AssumeRole |
| `dc.omniEmbedding.util.SigV4` | AWS Signature V4 signer, isolated + testable; key derivation matches AWS's official test vector byte-for-byte |
| `dc.omniEmbedding.provider.VertexAi` | `{region}-aiplatform.googleapis.com/.../models/{model}:predict`; `Bearer` OAuth 2.0 token; payload `instances[{content, task_type?, title?}]` + optional `parameters{outputDimensionality, autoTruncate}`; response `predictions[0].embeddings.values` |

### **Architecture Overview**

```

┌─────────────────────────────────────────────────────────────┐
│                Any caller — SQL, ObjectScript,              │
│                Interoperability, Embedded Python            │
│                    EMBEDDING('text', 'config')              │
└─────────────────────────┬───────────────────────────────────┘
                          │
                          ▼
┌─────────────────────────────────────────────────────────────┐
│              %Embedding.Interface (IRIS runtime)            │
│  Reads EmbeddingClass from %Embedding.Config, dispatches:   │
└─────────────────────────┬───────────────────────────────────┘
                          │
                          ▼
┌─────────────────────────────────────────────────────────────┐
│            dc.omniEmbedding.Interface (bridge)              │
│  ParseConfig · validate input · Engine.Embed()              │
└─────────────────────────┬───────────────────────────────────┘
                          │
                          ▼
┌─────────────────────────────────────────────────────────────┐
│                 dc.omniEmbedding.Engine                     │
│  ResolveProvider · CheckBreaker · RecordSuccess/Failure     │
│  TryFallback (vector-space invariant — fatal on mismatch)   │
└─────────────────────────┬───────────────────────────────────┘
                          │
                          ▼
┌─────────────────────────────────────────────────────────────┐
│       provider.Base.Execute() — Template Method             │
│  ValidateConfig → SetAuth → GetEmbeddingsUrl →              │
│  BuildPayload → RetryWithBackoff → ParseResponse            │
└─────────────────────────┬───────────────────────────────────┘
                          │
                          ▼
┌─────────────────────────────────────────────────────────────┐
│   %Net.HttpRequest → { Ollama | OpenAI | Azure | Cohere |   │
│                        Gemini | Mistral | Voyage | Jina |   │
│                        Bedrock (SigV4) | VertexAI (OAuth) } │
└─────────────────────────────────────────────────────────────┘

```

### **Resilience Model**

- **Retry:** 429 and 5xx are retried with `MIN(baseDelayMs * 2^(attempt-1) + jitter, maxDelayMs)` — `Retry-After` is honored verbatim when present. 4xx (except 429) fast-fail.
- **Circuit breaker:** per `provider|modelName|apiBase` key stored in `^omniEmbedding.Breaker`. Opens after **5** consecutive failures; **60 s** cooldown; half-open lets one probe through.
- **Fallback:** iterates `config.fallbacks` in order. Each candidate is *refused* before any HTTP call if `modelName` or `dimensions` differ from the primary — vectors from different spaces never mix.

---

## 📋 Prerequisites

- **InterSystems IRIS 2026.2+** (native `%Embedding.Interface` and `%Library.Vector` are required)
- **Docker** and **Docker Compose** (if you use the bundled dev container)
- Optional: **Ollama** at `http://localhost:11434` for zero-cost end-to-end integration tests
- Optional: **Embedded Python** with `tiktoken` for exact OpenAI token counts (a conservative floor is used when unavailable)

---

## 🛠️ Installation

### 1. **Clone the Repository**

```sh
git clone https://github.com/henryhamon/dc.omniEmbedding.git
cd dc.omniEmbedding
```

### 2. **Build and Run the Dev Container**

```sh
docker-compose up -d --build
```

The IPM module `dc-omni-embedding` is loaded automatically into the `IRISAPP` namespace.

### 3. **Or Install as an IPM Package**

```objectscript
zpm "install dc-omni-embedding"
```

### 4. **Wire it into `%Embedding.Config`**

Register `dc.omniEmbedding.Interface` as your `EmbeddingClass`, then store a JSON configuration:

```sql
INSERT INTO %Embedding.Config (Name, Configuration, EmbeddingClass, VectorLength, Description)
VALUES (
    'ollama-nomic',
    '{"provider":"ollama","modelName":"nomic-embed-text:latest","apiBase":"http://host.docker.internal:11434","dimensions":768}',
    'dc.omniEmbedding.Interface',
    768,
    'Local Ollama (nomic-embed-text)'
)
```

### 5. **Use It**

From SQL:

```sql
SELECT EMBEDDING('the quick brown fox', 'ollama-nomic')
```

From ObjectScript:

```objectscript
Set vec = ##class(dc.omniEmbedding.Interface).Embedding(
    "the quick brown fox",
    "{""provider"":""ollama"",""modelName"":""nomic-embed-text:latest"",""dimensions"":768}"
)
```

---

## 💡 Configuration Reference

Every field is a top-level key on the JSON stored in `%Embedding.Config.Configuration`.

### **Common fields (all providers)**

| Field | Required | Description |
|---|---|---|
| `provider` | one of: `ollama`, `openai`, `azure`, `cohere`, `gemini`, `mistral`, `voyage`, `jina`, `bedrock`, `vertex` (aliases: `vertexai`) — or infer from `modelName`. **Bedrock and Vertex do NOT infer** (their model prefixes collide with OpenAI / Cohere / Gemini) | Explicit provider selection |
| `modelName` | yes | Model identifier for the target provider |
| `dimensions` | yes | Expected vector length — enforced when checking fallbacks |
| `apiKey` | provider-dependent | **Credential name** (not the value) — resolved via `Ens.Config.Credentials` |
| `apiBase` | provider-dependent | Override default endpoint (Ollama, Azure) |
| `sslConfig` | no | Name of a `%SSL.Config` for TLS |
| `httpTimeout` | no (default `30`s) | HTTP timeout in seconds |
| `retry.maxAttempts` | no (default `3`) | Max attempts including the first |
| `retry.baseDelayMs` | no (default `500`) | Base backoff delay |
| `retry.maxDelayMs` | no (default `8000`) | Backoff cap |
| `retry.honorRetryAfter` | no (default `true`) | Use the `Retry-After` header when present |
| `fallbacks` | no | Array of `%Embedding.Config` names — each must share the primary's vector space |

### **Provider-specific extras**

- **Azure OpenAI:** `deployment`, `apiVersion` (`deployment` is optional when `apiBase` is already deployment-scoped)
- **Cohere:** `inputType` (default `search_document`)
- **Gemini:** `taskType` (default `RETRIEVAL_DOCUMENT`)
- **Mistral:** `outputDimension` (truncate — Codestral supports up to 3072), `outputDtype` (`float` · `int8` · `uint8` · `binary` · `ubinary`)
- **Voyage:** `inputType` (`query` · `document`), `truncation` (bool), `outputDimension`, `outputDtype`
- **Jina:** `task` (e.g. `retrieval.query` · `retrieval.passage` · `text-matching` · `classification`), `outputDimension` (mapped to Jina's `dimensions`), `lateChunking` (bool — coherent long-doc chunks), `outputDtype` (mapped to Jina's `embedding_type`)
- **AWS Bedrock:** `region` (required, e.g. `us-east-1`), `sessionTokenCredential` (optional, name of a second credential holding an STS token); `inputType` for Cohere-on-Bedrock family (default `search_document`); `dimensions` for Titan family
- **Google Vertex AI:** `region` (e.g. `us-central1`) + `project` required; `apiKey` names a credential whose value is a valid OAuth 2.0 access token (rotation is external — service-account JWT auto-refresh is future work); optional `taskType` (`RETRIEVAL_QUERY` · `RETRIEVAL_DOCUMENT` · `SEMANTIC_SIMILARITY` · `CLASSIFICATION` · `CLUSTERING` · `CODE_RETRIEVAL_QUERY`), `title` (only meaningful with `RETRIEVAL_DOCUMENT`), `outputDimension` (mapped to `outputDimensionality`), `autoTruncate` (bool)

### **Example — Ollama with an OpenAI fallback**

```json
{
    "provider": "ollama",
    "modelName": "nomic-embed-text:latest",
    "apiBase": "http://host.docker.internal:11434",
    "dimensions": 768,
    "fallbacks": ["ollama-backup"]
}
```

An OpenAI config with `text-embedding-3-small` (1536 dims) as a fallback would be **rejected before any HTTP call** — different vector space.

### **Example — AWS Bedrock Titan v2 with a session token**

Register two credentials — the AWS access key/secret pair, and the STS session token — then reference both by name:

```objectscript
Set cred = ##class(Ens.Config.Credentials).%New()
Set cred.SystemName = "aws-prod"
Set cred.Username = "aws"
Set cred.Password = "AKIA...prod:wJalrXUtnFEMI/K7MDENG..."   ; accessKeyId:secretAccessKey
Do cred.%Save()

Set tok = ##class(Ens.Config.Credentials).%New()
Set tok.SystemName = "aws-prod-session"
Set tok.Username = "sts"
Set tok.Password = "FQoDYXdz...session-token..."
Do tok.%Save()
```

```json
{
    "provider": "bedrock",
    "modelName": "amazon.titan-embed-text-v2:0",
    "region": "us-east-1",
    "apiKey": "aws-prod",
    "sessionTokenCredential": "aws-prod-session",
    "dimensions": 1024
}
```

Bedrock **requires** `provider: "bedrock"` explicit — the gateway will NOT infer it from `cohere.embed-*` or `amazon.titan-embed-*` prefixes to avoid collision with the direct Cohere provider.

### **Example — Mistral Codestral for code retrieval, truncated to 1024 dims**

```json
{
    "provider": "mistral",
    "modelName": "codestral-embed",
    "apiKey": "mistral-prod",
    "outputDimension": 1024,
    "outputDtype": "float",
    "dimensions": 1024
}
```

`outputDimension` tells Mistral to truncate the vector server-side (Codestral supports up to 3072); `dimensions` is what the gateway enforces on fallbacks and what IRIS stores.

---

## 🔐 Credentials

`config.apiKey` is always a **credential name**, never the raw secret. The gateway resolves the name via `Ens.Config.Credentials.%OpenId(name).Password`. Register one from the IRIS terminal:

```objectscript
Set cred = ##class(Ens.Config.Credentials).%New()
Set cred.SystemName = "openai-prod"
Set cred.Username = "apikey"
Set cred.Password = "sk-...your-real-key..."
Do cred.%Save()
```

Then reference it as `"apiKey": "openai-prod"` in your config. Exceptions raised for a missing credential carry only the *name* — never the value. See `TestSecurity` (Property 15).

---

## 🗂️ Project Structure

```
dc.omniEmbedding/
├── src/dc/omniEmbedding/
│   ├── Interface.cls              # Bridge to %Embedding.Interface
│   ├── Engine.cls                 # Dispatch · breaker · fallback
│   └── provider/
│       ├── Base.cls               # Template Method · retry · ResolveApiKey
│       ├── OpenACompatible.cls    # Shared payload/parse for OpenAI-family
│       ├── Ollama.cls
│       ├── OpenAi.cls
│       ├── AzureOpenAi.cls
│       ├── Cohere.cls
│       ├── Gemini.cls
│       ├── Mistral.cls              # mistral-embed (text) + codestral-embed (code)
│       ├── Voyage.cls               # voyage-3, voyage-code-3, voyage-finance-2, ...
│       ├── Jina.cls                 # jina-embeddings-v3, with late_chunking
│       ├── Bedrock.cls              # Titan + Cohere-via-Bedrock; overrides Execute for SigV4 ordering
│       └── VertexAi.cls             # text-embedding-* + gemini-embedding-*, OAuth 2.0 Bearer
├── src/dc/omniEmbedding/util/
│   └── SigV4.cls                    # AWS Signature V4 signer (isolated, testable)
├── tests/dc/omniEmbedding/
│   ├── TestOpenACompatible.cls    # Payload shape, parse errors, tiktoken floor
│   ├── TestOllama.cls             # URL construction + end-to-end via Ollama
│   ├── TestAzureUrl.cls           # Property 8 — URL composition invariants
│   ├── TestCohere.cls             # Property 10 — nested response parse
│   ├── TestGemini.cls             # Property 10 — auth-in-URL, no-op SetAuth
│   ├── TestMistral.cls            # URL, dispatch, output_dimension/dtype passthrough
│   ├── TestVoyage.cls             # URL, dispatch, inputType enum, all passthroughs
│   ├── TestJina.cls               # Property 17 — input always array; late_chunking; camelCase→wire mapping
│   ├── TestSigV4.cls              # Property 18 — key derivation matches AWS official vector byte-for-byte
│   ├── TestBedrock.cls            # URL, families, ParseResponse per family, credential formats, Property 19 (SigV4 applied), dispatch rules
│   ├── TestVertexAi.cls           # URL, ValidateConfig, Property 20 (parameters block only when needed), dispatch regression (no prefix inference)
│   ├── TestResilience.cls         # Properties 11-14 — backoff & breaker
│   ├── TestFallback.cls           # Properties 4-5 — vector-space invariance
│   ├── TestSecurity.cls           # Property 15 — credentials never leak
│   ├── TestInterface.cls          # Properties 2-3 — validation & no empty vec
│   └── FakeEngine.cls             # Test double for fallback tests
├── module.xml                     # IPM manifest
├── docker-compose.yml
└── README.md
```

---

## 🧪 Testing

Run every suite from the IRIS terminal:

```objectscript
Set ^UnitTestRoot = "/tmp/ut"
Do ##class(%UnitTest.Manager).RunTest(":dc.omniEmbedding.tests.TestOllama", "/nodelete/noload")
```

Or via IPM:

```objectscript
zpm "test dc-omni-embedding"
```

The end-to-end integration test in `TestOllama` auto-probes `localhost:11434` then `host.docker.internal:11434` and skips gracefully if Ollama is unavailable — CI stays green without any cloud key.

---

## 📊 Roadmap

### ✅ **v1.0 — Complete**

* [x] `%Embedding.Interface` bridge & runtime integration
* [x] Provider resolution by explicit name or model-prefix inference
* [x] Ten providers: Ollama, OpenAI, Azure OpenAI, Cohere, Gemini, Mistral (text + code), Voyage (text + code + domain), Jina (with `late_chunking`), AWS Bedrock (SigV4, Titan + Cohere-on-Bedrock), Google Vertex AI (text-embedding + gemini-embedding)
* [x] Retry with exponential backoff + `Retry-After` honoring
* [x] Circuit breaker (5 failures / 60 s cooldown / half-open probe)
* [x] Fallback with vector-space invariance (fatal on mismatch)
* [x] Credentials via `Ens.Config.Credentials` (secret never leaks)
* [x] Polymorphic `EstimateTokenCount` (tiktoken · Cohere · Gemini formulas)
* [x] Property-based test suite covering every correctness invariant

### 🔮 **Future**

* [ ] Batching support (multiple inputs per request)
* [ ] Vertex AI: automatic OAuth 2.0 access-token refresh via service-account JWT-bearer flow (currently the token is supplied externally through `Ens.Config.Credentials`)
* [ ] Optional in-process embedding cache with TTL

---

## 🎖️ Credits

`dc.omniEmbedding` is designed and developed with 💜 by:

- [**Henry Pereira**](https://community.intersystems.com/user/henry-pereira) — architecture, implementation, testing

---

## 📄 License

This project is licensed under the [MIT License](LICENSE).
