[![Gitter](https://img.shields.io/badge/Available%20on-Intersystems%20Open%20Exchange-00b2a9.svg)](https://openexchange.intersystems.com/)
[![License: MIT](https://img.shields.io/badge/License-MIT-blue.svg?style=flat&logo=AdGuard)](LICENSE)
[![InterSystems IRIS](https://img.shields.io/badge/InterSystems-IRIS%202026%2B-blue.svg)](https://www.intersystems.com/)
[![ObjectScript](https://img.shields.io/badge/ObjectScript-native-informational.svg)](https://docs.intersystems.com/)
[![Embedded Python](https://img.shields.io/badge/Embedded%20Python-optional-yellow.svg)](https://docs.intersystems.com/)

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

Swapping providers usually means rewriting glue code, and mixing them in fallback flows silently mixes vector spaces — a data-integrity disaster that only surfaces months later, when your similarity searches start returning nonsense.

**`dc.omniEmbedding` changes that.**

Plug it in once as your `EmbeddingClass` and every `EMBEDDING('text', 'config')` call — from SQL, from ObjectScript, from Interoperability — routes to the right provider, retries transient errors, opens a circuit breaker on failing providers, and **refuses** to fall back to a config whose vector space differs from the primary.

- ✅ **Five providers, one interface:** Ollama · OpenAI · Azure OpenAI · Cohere · Gemini
- ✅ **Native HTTP:** `%Net.HttpRequest` — no Python required on the hot path
- ✅ **Resilient:** exponential backoff, `Retry-After` honored, circuit breaker per provider
- ✅ **Safe fallback:** vector-space invariance is enforced *before* any HTTP call
- ✅ **Secure by default:** `apiKey` is a **credential name**, never the raw secret
- ✅ **CI-friendly:** the whole happy path runs against local Ollama, no cloud keys

---

## 🛠️ How It Works

`dc.omniEmbedding` sits between IRIS's native embedding runtime and any of the five supported external providers, applying three architectural pillars:

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
│   %Net.HttpRequest → { Ollama | OpenAI | Azure |            │
│                        Cohere | Gemini }                    │
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
| `provider` | one of: `ollama`, `openai`, `azure`, `cohere`, `gemini` (or infer from `modelName`) | Explicit provider selection |
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
│       └── Gemini.cls
├── tests/dc/omniEmbedding/
│   ├── TestOpenACompatible.cls    # Payload shape, parse errors, tiktoken floor
│   ├── TestOllama.cls             # URL construction + end-to-end via Ollama
│   ├── TestAzureUrl.cls           # Property 8 — URL composition invariants
│   ├── TestCohere.cls             # Property 10 — nested response parse
│   ├── TestGemini.cls             # Property 10 — auth-in-URL, no-op SetAuth
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
* [x] Five providers: Ollama, OpenAI, Azure OpenAI, Cohere, Gemini
* [x] Retry with exponential backoff + `Retry-After` honoring
* [x] Circuit breaker (5 failures / 60 s cooldown / half-open probe)
* [x] Fallback with vector-space invariance (fatal on mismatch)
* [x] Credentials via `Ens.Config.Credentials` (secret never leaks)
* [x] Polymorphic `EstimateTokenCount` (tiktoken · Cohere · Gemini formulas)
* [x] Property-based test suite covering every correctness invariant

### 🔮 **Future**

* [ ] Batching support (multiple inputs per request)
* [ ] Native support for AWS Bedrock and Vertex AI

---

## 🎖️ Credits

`dc.omniEmbedding` is designed and developed with 💜 by:

- [**Henry Pereira**](https://community.intersystems.com/user/henry-pereira) — architecture, implementation, testing

---

## 📄 License

This project is licensed under the [MIT License](LICENSE).
