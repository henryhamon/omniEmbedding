Include (%occStatus, %outUnitTest)

/// Unit tests for dc.omniEmbedding.provider.Jina.
/// Covers URL, ValidateConfig, Property 17 (input ALWAYS as array), passthroughs
/// (task, dimensions, late_chunking, embedding_type), Bearer auth via credential
/// hook, Engine dispatch by explicit name and by jina- prefix, and ParseResponse
/// against an OpenAI-shape Jina response.
Class dc.omniEmbedding.tests.TestJina Extends %UnitTest.TestCase
{

// --- URL ---

Method TestUrlIsJinaCloud()
{
    Set config = ##class(%DynamicObject).%FromJSON("{""modelName"":""jina-embeddings-v3""}")
    Set url = ##class(dc.omniEmbedding.provider.Jina).GetEmbeddingsUrl(config)
    Do $$$AssertEquals(url, "https://api.jina.ai/v1/embeddings", "fixed Jina cloud endpoint")
}

// --- ValidateConfig ---

Method TestValidateMissingApiKey()
{
    Set config = ##class(%DynamicObject).%FromJSON("{""modelName"":""jina-embeddings-v3""}")
    Set threw = 0, errMsg = ""
    Try { Do ##class(dc.omniEmbedding.provider.Jina).ValidateConfig(config) }
    Catch ex { Set threw = 1, errMsg = ex.DisplayString() }
    Do $$$AssertTrue(threw, "throws when apiKey missing")
    Do $$$AssertTrue($Find(errMsg, "apiKey") > 0, "error mentions apiKey")
}

Method TestValidateMissingModelName()
{
    Set config = ##class(%DynamicObject).%FromJSON("{""apiKey"":""k""}")
    Set threw = 0, errMsg = ""
    Try { Do ##class(dc.omniEmbedding.provider.Jina).ValidateConfig(config) }
    Catch ex { Set threw = 1, errMsg = ex.DisplayString() }
    Do $$$AssertTrue(threw, "throws when modelName missing")
    Do $$$AssertTrue($Find(errMsg, "modelName") > 0, "error mentions modelName")
}

// --- Property 17: input ALWAYS as array ---

Method TestBuildPayloadInputAlwaysArray()
{
    Set config = ##class(%DynamicObject).%FromJSON("{""modelName"":""jina-embeddings-v3""}")
    Set payload = ##class(dc.omniEmbedding.provider.Jina).BuildPayload("hello", config)
    Set inputField = payload.%Get("input")
    Do $$$AssertTrue($IsObject(inputField), "input is an object (dynamic array), not a scalar string")
    Do $$$AssertTrue(inputField.%IsA("%Library.DynamicArray"), "input is a %DynamicArray")
    Do $$$AssertEquals(inputField.%Size(), 1, "input array has exactly 1 element")
    Do $$$AssertEquals(inputField.%Get(0), "hello", "input[0] is the original text")
}

Method TestBuildPayloadInputArrayEvenForLongText()
{
    Set config = ##class(%DynamicObject).%FromJSON("{""modelName"":""jina-embeddings-v3""}")
    Set longTxt = "This is a much longer piece of text that spans multiple concepts and would traditionally be split, but Jina supports late_chunking so we send the whole thing."
    Set payload = ##class(dc.omniEmbedding.provider.Jina).BuildPayload(longTxt, config)
    Set inputField = payload.%Get("input")
    Do $$$AssertEquals(inputField.%Size(), 1, "still 1-element array for long text")
    Do $$$AssertEquals(inputField.%Get(0), longTxt, "text preserved verbatim")
}

// --- BuildPayload: minimal shape ---

Method TestBuildPayloadMinimalShape()
{
    Set config = ##class(%DynamicObject).%FromJSON("{""modelName"":""jina-embeddings-v3""}")
    Set payload = ##class(dc.omniEmbedding.provider.Jina).BuildPayload("hi", config)
    Do $$$AssertEquals(payload.%Get("model"), "jina-embeddings-v3", "model set")
    Set count = 0, iter = payload.%GetIterator()
    While iter.%GetNext(.k, .v) { Set count = count + 1 }
    Do $$$AssertEquals(count, 2, "minimal payload has exactly input + model")
}

// --- BuildPayload: passthroughs ---

Method TestBuildPayloadWithTaskRetrievalQuery()
{
    Set config = ##class(%DynamicObject).%FromJSON("{""modelName"":""jina-embeddings-v3"",""task"":""retrieval.query""}")
    Set payload = ##class(dc.omniEmbedding.provider.Jina).BuildPayload("q", config)
    Do $$$AssertEquals(payload.%Get("task"), "retrieval.query", "task forwarded verbatim")
}

Method TestBuildPayloadWithDimensions()
{
    // Jina calls it "dimensions" (not "output_dimension" like Voyage/Mistral) —
    // config normalizes on outputDimension; the provider maps to Jina's native name.
    Set config = ##class(%DynamicObject).%FromJSON("{""modelName"":""jina-embeddings-v3"",""outputDimension"":512}")
    Set payload = ##class(dc.omniEmbedding.provider.Jina).BuildPayload("hi", config)
    Do $$$AssertEquals(payload.%Get("dimensions"), 512, "outputDimension mapped to 'dimensions' at the wire")
    Do $$$AssertEquals(payload.%Get("output_dimension"), "", "no output_dimension (that's Voyage/Mistral's spelling)")
}

Method TestBuildPayloadWithLateChunkingTrue()
{
    Set config = ##class(%DynamicObject).%FromJSON("{""modelName"":""jina-embeddings-v3"",""lateChunking"":true}")
    Set payload = ##class(dc.omniEmbedding.provider.Jina).BuildPayload("long doc", config)
    Do $$$AssertEquals(payload.%Get("late_chunking"), 1, "lateChunking:true forwarded as boolean 1")
}

Method TestBuildPayloadWithLateChunkingFalse()
{
    Set config = ##class(%DynamicObject).%FromJSON("{""modelName"":""jina-embeddings-v3"",""lateChunking"":false}")
    Set payload = ##class(dc.omniEmbedding.provider.Jina).BuildPayload("hi", config)
    Do $$$AssertEquals(payload.%Get("late_chunking"), 0, "lateChunking:false forwarded as boolean 0")
}

Method TestBuildPayloadWithEmbeddingType()
{
    Set config = ##class(%DynamicObject).%FromJSON("{""modelName"":""jina-embeddings-v3"",""outputDtype"":""binary""}")
    Set payload = ##class(dc.omniEmbedding.provider.Jina).BuildPayload("hi", config)
    Do $$$AssertEquals(payload.%Get("embedding_type"), "binary", "outputDtype mapped to 'embedding_type' at the wire")
    Do $$$AssertEquals(payload.%Get("output_dtype"), "", "no output_dtype (that's Voyage/Mistral's spelling)")
}

Method TestBuildPayloadWithAllExtras()
{
    Set config = ##class(%DynamicObject).%FromJSON("{""modelName"":""jina-embeddings-v3"",""task"":""retrieval.passage"",""outputDimension"":768,""lateChunking"":true,""outputDtype"":""float""}")
    Set payload = ##class(dc.omniEmbedding.provider.Jina).BuildPayload("chunk of text", config)
    Do $$$AssertEquals(payload.%Get("task"), "retrieval.passage", "task")
    Do $$$AssertEquals(payload.%Get("dimensions"), 768, "dimensions")
    Do $$$AssertEquals(payload.%Get("late_chunking"), 1, "late_chunking")
    Do $$$AssertEquals(payload.%Get("embedding_type"), "float", "embedding_type")
    // input still an array
    Do $$$AssertEquals(payload.%Get("input").%Size(), 1, "input still 1-element array")
}

// --- Auth ---

Method TestSetAuthUsesBearer()
{
    Set ^||omniEmbeddingCredential("jina-test") = "jina_test_key"
    Set request = ##class(%Net.HttpRequest).%New()
    Set config = ##class(%DynamicObject).%FromJSON("{""modelName"":""jina-embeddings-v3"",""apiKey"":""jina-test""}")
    Do ##class(dc.omniEmbedding.provider.Jina).SetAuth(request, config)
    Do $$$AssertEquals(request.Authorization, "Bearer jina_test_key", "Authorization: Bearer <resolved>")
    Kill ^||omniEmbeddingCredential("jina-test")
}

// --- Engine dispatch ---

Method TestEngineDispatchExplicit()
{
    Set config = ##class(%DynamicObject).%FromJSON("{""provider"":""jina"",""modelName"":""anything""}")
    Do $$$AssertEquals(##class(dc.omniEmbedding.Engine).ResolveProvider(config), "dc.omniEmbedding.provider.Jina", "explicit 'jina' -> Jina class")
}

Method TestEngineDispatchByJinaPrefix()
{
    Set config = ##class(%DynamicObject).%FromJSON("{""modelName"":""jina-embeddings-v3""}")
    Do $$$AssertEquals(##class(dc.omniEmbedding.Engine).ResolveProvider(config), "dc.omniEmbedding.provider.Jina", "jina-embeddings-v3 -> Jina")
}

Method TestEngineDispatchByJinaClipPrefix()
{
    Set config = ##class(%DynamicObject).%FromJSON("{""modelName"":""jina-clip-v1""}")
    Do $$$AssertEquals(##class(dc.omniEmbedding.Engine).ResolveProvider(config), "dc.omniEmbedding.provider.Jina", "jina-clip-v1 also -> Jina (any jina- prefix)")
}

// --- ParseResponse: inherited OpenAI-shape ---

Method TestParseResponseValid()
{
    Set j = "{""object"":""list"",""data"":[{""object"":""embedding"",""embedding"":[0.1,0.2,0.3],""index"":0}],""model"":""jina-embeddings-v3"",""usage"":{""total_tokens"":3,""prompt_tokens"":3}}"
    Set body = ##class(%DynamicObject).%FromJSON(j)
    Set vec = ##class(dc.omniEmbedding.provider.Jina).ParseResponse(body)
    Do $$$AssertTrue(##class(%Library.Vector).IsValid(vec), "valid %Vector")
    Set disp = ##class(%Library.Vector).LogicalToDisplay(vec)
    Do $$$AssertEquals($Length(disp, ","), 3, "vector has 3 elements")
}

// --- Regression: unknown provider must list jina ---

Method TestUnknownProviderListsJina()
{
    Set config = ##class(%DynamicObject).%FromJSON("{""provider"":""bogus"",""modelName"":""m""}")
    Set threw = 0, errMsg = ""
    Try { Do ##class(dc.omniEmbedding.Engine).ResolveProvider(config) }
    Catch ex { Set threw = 1, errMsg = ex.DisplayString() }
    Do $$$AssertTrue(threw, "unknown provider throws")
    Do $$$AssertTrue($Find(errMsg, "jina") > 0, "jina listed among valid: "_errMsg)
}

}
