Include (%occStatus, %outUnitTest)

/// Unit tests for dc.omniEmbedding.provider.Mistral.
/// Covers URL, ValidateConfig, BuildPayload (minimal + with Mistral-specific
/// optionals output_dimension / output_dtype), Bearer auth via test-hook
/// credential resolution, and Engine dispatch by explicit name and by
/// modelName prefix (mistral- / codestral-).
Class dc.omniEmbedding.tests.TestMistral Extends %UnitTest.TestCase
{

// --- URL is fixed ---

Method TestUrlIsMistralCloud()
{
    Set config = ##class(%DynamicObject).%FromJSON("{""modelName"":""mistral-embed""}")
    Set url = ##class(dc.omniEmbedding.provider.Mistral).GetEmbeddingsUrl(config)
    Do $$$AssertEquals(url, "https://api.mistral.ai/v1/embeddings", "fixed Mistral cloud endpoint")
}

// --- ValidateConfig ---

Method TestValidateMissingApiKey()
{
    Set config = ##class(%DynamicObject).%FromJSON("{""modelName"":""mistral-embed""}")
    Set threw = 0, errMsg = ""
    Try { Do ##class(dc.omniEmbedding.provider.Mistral).ValidateConfig(config) }
    Catch ex { Set threw = 1, errMsg = ex.DisplayString() }
    Do $$$AssertTrue(threw, "throws when apiKey missing")
    Do $$$AssertTrue($Find(errMsg, "apiKey") > 0, "error mentions apiKey")
}

Method TestValidateMissingModelName()
{
    Set config = ##class(%DynamicObject).%FromJSON("{""apiKey"":""k""}")
    Set threw = 0, errMsg = ""
    Try { Do ##class(dc.omniEmbedding.provider.Mistral).ValidateConfig(config) }
    Catch ex { Set threw = 1, errMsg = ex.DisplayString() }
    Do $$$AssertTrue(threw, "throws when modelName missing")
    Do $$$AssertTrue($Find(errMsg, "modelName") > 0, "error mentions modelName")
}

// --- BuildPayload: minimal (OpenAI-compatible) ---

Method TestBuildPayloadMinimal()
{
    Set config = ##class(%DynamicObject).%FromJSON("{""modelName"":""mistral-embed""}")
    Set payload = ##class(dc.omniEmbedding.provider.Mistral).BuildPayload("hello", config)
    Do $$$AssertEquals(payload.%Get("input"), "hello", "input")
    Do $$$AssertEquals(payload.%Get("model"), "mistral-embed", "model")
    // Optional fields must be absent when not configured
    Do $$$AssertEquals(payload.%Get("output_dimension"), "", "no output_dimension when omitted")
    Do $$$AssertEquals(payload.%Get("output_dtype"), "", "no output_dtype when omitted")
    Set count = 0, iter = payload.%GetIterator()
    While iter.%GetNext(.k, .v) { Set count = count + 1 }
    Do $$$AssertEquals(count, 2, "minimal payload has exactly input + model")
}

// --- BuildPayload: Codestral with output_dimension truncation ---

Method TestBuildPayloadCodestralWithOutputDimension()
{
    Set config = ##class(%DynamicObject).%FromJSON("{""modelName"":""codestral-embed"",""outputDimension"":1024}")
    Set payload = ##class(dc.omniEmbedding.provider.Mistral).BuildPayload("def foo():\n    pass", config)
    Do $$$AssertEquals(payload.%Get("model"), "codestral-embed", "codestral model")
    Do $$$AssertEquals(payload.%Get("output_dimension"), 1024, "output_dimension forwarded as int")
}

// --- BuildPayload: output_dtype passthrough ---

Method TestBuildPayloadWithOutputDtype()
{
    Set config = ##class(%DynamicObject).%FromJSON("{""modelName"":""mistral-embed"",""outputDtype"":""int8""}")
    Set payload = ##class(dc.omniEmbedding.provider.Mistral).BuildPayload("hi", config)
    Do $$$AssertEquals(payload.%Get("output_dtype"), "int8", "output_dtype forwarded")
}

Method TestBuildPayloadWithBothExtras()
{
    Set config = ##class(%DynamicObject).%FromJSON("{""modelName"":""codestral-embed"",""outputDimension"":3072,""outputDtype"":""binary""}")
    Set payload = ##class(dc.omniEmbedding.provider.Mistral).BuildPayload("code", config)
    Do $$$AssertEquals(payload.%Get("output_dimension"), 3072, "output_dimension")
    Do $$$AssertEquals(payload.%Get("output_dtype"), "binary", "output_dtype")
}

// --- Auth: Bearer via credential lookup (inherited from OpenACompatible) ---

Method TestSetAuthUsesBearer()
{
    Set ^||omniEmbeddingCredential("mistral-test") = "mst-live-key"
    Set request = ##class(%Net.HttpRequest).%New()
    Set config = ##class(%DynamicObject).%FromJSON("{""modelName"":""mistral-embed"",""apiKey"":""mistral-test""}")
    Do ##class(dc.omniEmbedding.provider.Mistral).SetAuth(request, config)
    Do $$$AssertEquals(request.Authorization, "Bearer mst-live-key", "Authorization: Bearer <resolved>")
    Kill ^||omniEmbeddingCredential("mistral-test")
}

// --- Engine dispatch by explicit provider name ---

Method TestEngineDispatchExplicit()
{
    Set config = ##class(%DynamicObject).%FromJSON("{""provider"":""mistral"",""modelName"":""anything""}")
    Do $$$AssertEquals(##class(dc.omniEmbedding.Engine).ResolveProvider(config), "dc.omniEmbedding.provider.Mistral", "explicit 'mistral' -> Mistral class")
}

// --- Engine dispatch by modelName prefix ---

Method TestEngineDispatchByMistralPrefix()
{
    Set config = ##class(%DynamicObject).%FromJSON("{""modelName"":""mistral-embed""}")
    Do $$$AssertEquals(##class(dc.omniEmbedding.Engine).ResolveProvider(config), "dc.omniEmbedding.provider.Mistral", "mistral- prefix -> Mistral")
}

Method TestEngineDispatchByCodestralPrefix()
{
    Set config = ##class(%DynamicObject).%FromJSON("{""modelName"":""codestral-embed""}")
    Do $$$AssertEquals(##class(dc.omniEmbedding.Engine).ResolveProvider(config), "dc.omniEmbedding.provider.Mistral", "codestral- prefix -> Mistral")
}

// --- ParseResponse: inherited from OpenACompatible works on Mistral shape ---

Method TestParseResponseValid()
{
    Set j = "{""object"":""list"",""data"":[{""object"":""embedding"",""embedding"":[0.1,0.2,0.3,0.4],""index"":0}],""model"":""mistral-embed"",""usage"":{""prompt_tokens"":5,""total_tokens"":5}}"
    Set body = ##class(%DynamicObject).%FromJSON(j)
    Set vec = ##class(dc.omniEmbedding.provider.Mistral).ParseResponse(body)
    Do $$$AssertTrue(##class(%Library.Vector).IsValid(vec), "valid %Vector returned")
    Set disp = ##class(%Library.Vector).LogicalToDisplay(vec)
    Do $$$AssertEquals($Length(disp, ","), 4, "vector has 4 elements")
}

// --- Error path: unknown provider must not accidentally resolve to Mistral ---

Method TestUnknownProviderStillRejected()
{
    Set config = ##class(%DynamicObject).%FromJSON("{""provider"":""bogus"",""modelName"":""m""}")
    Set threw = 0, errMsg = ""
    Try { Do ##class(dc.omniEmbedding.Engine).ResolveProvider(config) }
    Catch ex { Set threw = 1, errMsg = ex.DisplayString() }
    Do $$$AssertTrue(threw, "unknown provider throws")
    Do $$$AssertTrue($Find(errMsg, "mistral") > 0, "error lists mistral among valid providers: "_errMsg)
}

}
