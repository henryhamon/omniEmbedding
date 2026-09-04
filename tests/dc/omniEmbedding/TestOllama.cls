Include (%occStatus, %outUnitTest)

/// Unit + integration tests for dc.omniEmbedding.provider.Ollama.
/// Covers Property 7 (URL construction) and Property 6 (no auth required).
/// Integration test requires Ollama at http://localhost:11434 with a small embedding model;
/// it is skipped gracefully if Ollama is unreachable.
Class dc.omniEmbedding.tests.TestOllama Extends %UnitTest.TestCase
{

Parameter OLLAMAMODEL = "nomic-embed-text:latest";

Parameter OLLAMADIMENSIONS = 768;

// --- Property 7: URL construction — no duplicate slashes, default base ---

Method TestUrlDefaultBase()
{
    Set config = ##class(%DynamicObject).%FromJSON("{""modelName"":""nomic-embed-text""}")
    Set url = ##class(dc.omniEmbedding.provider.Ollama).GetEmbeddingsUrl(config)
    Do $$$AssertEquals(url, "http://localhost:11434/v1/embeddings", "default base yields canonical url")
}

Method TestUrlExplicitBaseNoSlash()
{
    Set config = ##class(%DynamicObject).%FromJSON("{""modelName"":""m"",""apiBase"":""http://ollama.local:11434""}")
    Set url = ##class(dc.omniEmbedding.provider.Ollama).GetEmbeddingsUrl(config)
    Do $$$AssertEquals(url, "http://ollama.local:11434/v1/embeddings", "explicit base without slash")
}

Method TestUrlExplicitBaseTrailingSlash()
{
    Set config = ##class(%DynamicObject).%FromJSON("{""modelName"":""m"",""apiBase"":""http://ollama.local:11434/""}")
    Set url = ##class(dc.omniEmbedding.provider.Ollama).GetEmbeddingsUrl(config)
    Do $$$AssertEquals(url, "http://ollama.local:11434/v1/embeddings", "single trailing slash stripped")
}

Method TestUrlExplicitBaseMultipleTrailingSlashes()
{
    Set config = ##class(%DynamicObject).%FromJSON("{""modelName"":""m"",""apiBase"":""http://ollama.local:11434///""}")
    Set url = ##class(dc.omniEmbedding.provider.Ollama).GetEmbeddingsUrl(config)
    Do $$$AssertEquals(url, "http://ollama.local:11434/v1/embeddings", "multiple trailing slashes stripped")
}

// --- Property 6: Ollama accepts absence of apiKey; SetAuth is a no-op ---

Method TestSetAuthDoesNotSetAuthorization()
{
    Set request = ##class(%Net.HttpRequest).%New()
    Set config = ##class(%DynamicObject).%FromJSON("{""modelName"":""nomic-embed-text""}")
    Do ##class(dc.omniEmbedding.provider.Ollama).SetAuth(request, config)
    Do $$$AssertEquals(request.Authorization, "", "Authorization header not set by Ollama.SetAuth")
}

Method TestSetAuthIgnoresApiKeyIfPresent()
{
    Set request = ##class(%Net.HttpRequest).%New()
    Set config = ##class(%DynamicObject).%FromJSON("{""modelName"":""m"",""apiKey"":""should-be-ignored""}")
    Do ##class(dc.omniEmbedding.provider.Ollama).SetAuth(request, config)
    Do $$$AssertEquals(request.Authorization, "", "Ollama.SetAuth ignores config.apiKey even when present")
}

// --- Integration: end-to-end via Interface -> Engine -> Ollama ---
// Skipped gracefully when Ollama is unreachable so unit tests still pass in CI without it.

Method TestIntegrationEmbeddingEndToEnd()
{
    Set apiBase = ..DetectOllamaBase()
    If apiBase = "" {
        Do $$$LogMessage("Ollama not reachable (tried localhost and host.docker.internal) — skipping integration test")
        Quit
    }
    Do $$$LogMessage("Using Ollama at "_apiBase)

    Set model = ..#OLLAMAMODEL
    Set dims = ..#OLLAMADIMENSIONS
    Set json = "{""provider"":""ollama"",""modelName"":"""_model_""",""apiBase"":"""_apiBase_""",""dimensions"":"_dims_"}"

    Set threw = 0, errMsg = ""
    Try {
        Set vec = ##class(dc.omniEmbedding.Interface).Embedding("hello world", json)
    } Catch ex {
        Set threw = 1, errMsg = ex.DisplayString()
    }
    Do $$$AssertNotTrue(threw, "Embedding() did not throw: "_errMsg)
    Do $$$AssertNotEquals($Get(vec), "", "vector returned is not empty")
    Set vlen = ..VectorLength(vec)
    Do $$$AssertEquals(vlen, dims, "vector length matches config.dimensions")
}

/// Returns the number of elements in a %Vector.
/// Uses %Library.Vector.LogicalToDisplay because $vector(v,i,...) read syntax is opaque
/// in IRIS 2026+ — the vector is only introspectable through the %Library.Vector API
/// or SQL VECTOR_* functions.
ClassMethod VectorLength(vec As %Vector) As %Integer [ Private ]
{
    If '##class(%Library.Vector).IsValid(vec) { Return 0 }
    Set disp = ##class(%Library.Vector).LogicalToDisplay(vec)
    If disp = "" { Return 0 }
    Return $Length(disp, ",")
}

/// Detects a reachable Ollama endpoint. Tries localhost first, then host.docker.internal
/// (for tests running inside a Docker container against Ollama on the host).
/// Returns "" if none reachable.
ClassMethod DetectOllamaBase() As %String [ Private ]
{
    For host = "localhost", "host.docker.internal" {
        If ..Probe(host) { Return "http://"_host_":11434" }
    }
    Return ""
}

ClassMethod Probe(host As %String) As %Boolean [ Private ]
{
    Set req = ##class(%Net.HttpRequest).%New()
    Set req.Server = host
    Set req.Port = 11434
    Set req.Timeout = 2
    Try {
        Set sc = req.Get("/api/tags")
        If $$$ISERR(sc) { Return 0 }
        Return (req.HttpResponse.StatusCode = 200)
    } Catch {
        Return 0
    }
}

}
