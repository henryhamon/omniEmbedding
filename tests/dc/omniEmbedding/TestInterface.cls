Include (%occStatus, %outUnitTest)

/// Tests for dc.omniEmbedding.Interface — Property 2 (invalid config
/// rejection), Property 3 (never returns empty vector on failure),
/// and the Embedding()/IsValidConfig()/EstimateTokenCount() contract.
Class dc.omniEmbedding.tests.TestInterface Extends %UnitTest.TestCase
{

// --- Embedding: input validation (no HTTP) ---

Method TestEmbeddingEmptyInputThrows()
{
    Set threw = 0, errMsg = ""
    Try { Do ##class(dc.omniEmbedding.Interface).Embedding("", "{""provider"":""ollama"",""modelName"":""m"",""dimensions"":768}") }
    Catch ex { Set threw = 1, errMsg = ex.DisplayString() }
    Do $$$AssertTrue(threw, "empty input throws before any HTTP")
    Do $$$AssertTrue($Find(errMsg, "empty") > 0, "message mentions empty: "_errMsg)
}

Method TestEmbeddingMalformedJsonThrows()
{
    Set threw = 0, errMsg = ""
    Try { Do ##class(dc.omniEmbedding.Interface).Embedding("hi", "{not-json") }
    Catch ex { Set threw = 1, errMsg = ex.DisplayString() }
    Do $$$AssertTrue(threw, "malformed JSON throws")
    Do $$$AssertTrue($Find(errMsg, "JSON") > 0, "message identifies JSON parse error: "_errMsg)
}

Method TestEmbeddingMissingDimensionsThrows()
{
    Set threw = 0, errMsg = ""
    Try { Do ##class(dc.omniEmbedding.Interface).Embedding("hi", "{""provider"":""ollama"",""modelName"":""m""}") }
    Catch ex { Set threw = 1, errMsg = ex.DisplayString() }
    Do $$$AssertTrue(threw, "missing dimensions throws")
    Do $$$AssertTrue($Find(errMsg, "dimensions") > 0, "message mentions dimensions")
}

Method TestEmbeddingZeroDimensionsThrows()
{
    Set threw = 0
    Try { Do ##class(dc.omniEmbedding.Interface).Embedding("hi", "{""provider"":""ollama"",""modelName"":""m"",""dimensions"":0}") }
    Catch { Set threw = 1 }
    Do $$$AssertTrue(threw, "zero dimensions throws")
}

Method TestEmbeddingNegativeDimensionsThrows()
{
    Set threw = 0
    Try { Do ##class(dc.omniEmbedding.Interface).Embedding("hi", "{""provider"":""ollama"",""modelName"":""m"",""dimensions"":-3}") }
    Catch { Set threw = 1 }
    Do $$$AssertTrue(threw, "negative dimensions throws")
}

// --- Property 2: IsValidConfig rejects invalid configs ---

Method TestIsValidConfigOllamaMinimalIsValid()
{
    // Ollama needs only modelName — apiKey is optional
    Set config = ##class(%DynamicObject).%FromJSON("{""provider"":""ollama"",""modelName"":""nomic-embed-text""}")
    Set errorMsg = "changed"
    Set ok = ##class(dc.omniEmbedding.Interface).IsValidConfig(config, .errorMsg)
    Do $$$AssertEquals(ok, 1, "Ollama config without apiKey is valid")
    Do $$$AssertEquals(errorMsg, "", "errorMsg cleared on success")
}

Method TestIsValidConfigOpenAiMissingApiKey()
{
    Set config = ##class(%DynamicObject).%FromJSON("{""provider"":""openai"",""modelName"":""text-embedding-3-small""}")
    Set errorMsg = ""
    Set ok = ##class(dc.omniEmbedding.Interface).IsValidConfig(config, .errorMsg)
    Do $$$AssertEquals(ok, 0, "OpenAI without apiKey is invalid")
    Do $$$AssertTrue($Find(errorMsg, "apiKey") > 0, "errorMsg identifies apiKey: "_errorMsg)
}

Method TestIsValidConfigAzureMissingDeployment()
{
    Set config = ##class(%DynamicObject).%FromJSON("{""provider"":""azure"",""modelName"":""m"",""apiBase"":""https://x"",""apiVersion"":""v"",""apiKey"":""k""}")
    Set errorMsg = ""
    Set ok = ##class(dc.omniEmbedding.Interface).IsValidConfig(config, .errorMsg)
    Do $$$AssertEquals(ok, 0, "Azure root-base without deployment is invalid")
    Do $$$AssertTrue($Find(errorMsg, "deployment") > 0, "errorMsg identifies deployment")
}

Method TestIsValidConfigCohereMissingApiKey()
{
    Set config = ##class(%DynamicObject).%FromJSON("{""provider"":""cohere"",""modelName"":""embed-english-v3.0""}")
    Set errorMsg = ""
    Set ok = ##class(dc.omniEmbedding.Interface).IsValidConfig(config, .errorMsg)
    Do $$$AssertEquals(ok, 0, "Cohere without apiKey is invalid")
    Do $$$AssertTrue($Find(errorMsg, "apiKey") > 0, "errorMsg identifies apiKey")
}

Method TestIsValidConfigGeminiMissingModelName()
{
    Set config = ##class(%DynamicObject).%FromJSON("{""provider"":""gemini"",""apiKey"":""k""}")
    Set errorMsg = ""
    Set ok = ##class(dc.omniEmbedding.Interface).IsValidConfig(config, .errorMsg)
    Do $$$AssertEquals(ok, 0, "Gemini without modelName is invalid")
    Do $$$AssertTrue($Find(errorMsg, "modelName") > 0, "errorMsg identifies modelName")
}

Method TestIsValidConfigNoProviderNoModel()
{
    Set config = ##class(%DynamicObject).%FromJSON("{""dimensions"":768}")
    Set errorMsg = ""
    Set ok = ##class(dc.omniEmbedding.Interface).IsValidConfig(config, .errorMsg)
    Do $$$AssertEquals(ok, 0, "missing both provider and modelName is invalid")
    Do $$$AssertTrue(errorMsg '= "", "errorMsg orients the caller")
}

// --- Property 3: never returns empty vector on failure ---

Method TestEmbeddingUnknownProviderThrowsNotEmptyVec()
{
    Set caught = "sentinel"
    Try {
        Set caught = ##class(dc.omniEmbedding.Interface).Embedding("hi", "{""provider"":""madeup"",""modelName"":""m"",""dimensions"":768}")
    } Catch ex {
        Set caught = ex
    }
    Do $$$AssertTrue($IsObject(caught), "unknown provider throws (never returns silently)")
}

Method TestEmbeddingUnreachableHostThrows()
{
    // Guaranteed-unreachable port; must throw, must NOT return an empty vector
    Set json = "{""provider"":""ollama"",""modelName"":""nomic-embed-text"",""apiBase"":""http://127.0.0.1:1"",""dimensions"":768,""retry"":{""maxAttempts"":1}}"
    Set threw = 0
    Try {
        Set vec = ##class(dc.omniEmbedding.Interface).Embedding("hi", json)
    } Catch { Set threw = 1 }
    Do $$$AssertTrue(threw, "unreachable host throws — never returns empty vector")
}

// --- EstimateTokenCount polymorphism ---

Method TestEstimateTokenCountDelegatesByProvider()
{
    // Cohere formula: Floor(11/3.5)+1 = 4
    Set cohereN = ##class(dc.omniEmbedding.Interface).EstimateTokenCount("hello world", "{""provider"":""cohere"",""modelName"":""embed-english-v3.0""}")
    Do $$$AssertEquals(cohereN, 4, "delegates to Cohere estimate (4 for 'hello world')")

    // Gemini formula: Floor(11/4)+2 = 4
    Set geminiN = ##class(dc.omniEmbedding.Interface).EstimateTokenCount("hello world", "{""provider"":""gemini"",""modelName"":""embedding-001""}")
    Do $$$AssertEquals(geminiN, 4, "delegates to Gemini estimate (4 for 'hello world')")
}

Method TestEstimateTokenCountFloorWithoutConfig()
{
    // No config → conservative floor: Floor(11/4)+1 = 3
    Set n = ##class(dc.omniEmbedding.Interface).EstimateTokenCount("hello world", "")
    Do $$$AssertEquals(n, 3, "no config → Floor(ByteLen/4)+1")
}

}
