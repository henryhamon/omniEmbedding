Include (%occStatus, %outUnitTest)

/// Unit tests for dc.omniEmbedding.provider.VertexAi.
/// Covers URL composition (region + project + model), ValidateConfig for each
/// required field, BuildPayload (minimal + optional taskType/title/parameters),
/// ParseResponse (valid + each missing-field path), Bearer auth via credential
/// hook, and Engine dispatch (explicit "vertex" and "vertexai"; NO prefix
/// inference — text-embedding-* and gemini-embedding-* would collide with
/// OpenAI/Gemini direct).
Class dc.omniEmbedding.tests.TestVertexAi Extends %UnitTest.TestCase
{

Method OnAfterOneTest(testname As %String) As %Status
{
    Kill ^||omniEmbeddingCredential
    Return $$$OK
}

// --- URL ---

Method TestUrlComposedFromRegionProjectModel()
{
    Set config = ##class(%DynamicObject).%FromJSON("{""region"":""us-central1"",""project"":""my-project"",""modelName"":""text-embedding-005""}")
    Set url = ##class(dc.omniEmbedding.provider.VertexAi).GetEmbeddingsUrl(config)
    Do $$$AssertEquals(url, "https://us-central1-aiplatform.googleapis.com/v1/projects/my-project/locations/us-central1/publishers/google/models/text-embedding-005:predict", "URL composed correctly")
}

Method TestUrlDifferentRegionAndModel()
{
    Set config = ##class(%DynamicObject).%FromJSON("{""region"":""europe-west4"",""project"":""p123"",""modelName"":""gemini-embedding-001""}")
    Set url = ##class(dc.omniEmbedding.provider.VertexAi).GetEmbeddingsUrl(config)
    Do $$$AssertTrue($Find(url, "europe-west4-aiplatform.googleapis.com") > 0, "region interpolated")
    Do $$$AssertTrue($Find(url, "/projects/p123/locations/europe-west4/") > 0, "project + region interpolated")
    Do $$$AssertTrue($Find(url, "/models/gemini-embedding-001:predict") > 0, "model + :predict suffix")
}

// --- ValidateConfig ---

Method TestValidateMissingModelName()
{
    Set config = ##class(%DynamicObject).%FromJSON("{""region"":""us-central1"",""project"":""p"",""apiKey"":""k""}")
    Do ..AssertValidateThrows(config, "modelName")
}

Method TestValidateMissingRegion()
{
    Set config = ##class(%DynamicObject).%FromJSON("{""modelName"":""text-embedding-005"",""project"":""p"",""apiKey"":""k""}")
    Do ..AssertValidateThrows(config, "region")
}

Method TestValidateMissingProject()
{
    Set config = ##class(%DynamicObject).%FromJSON("{""modelName"":""text-embedding-005"",""region"":""us-central1"",""apiKey"":""k""}")
    Do ..AssertValidateThrows(config, "project")
}

Method TestValidateMissingApiKey()
{
    Set config = ##class(%DynamicObject).%FromJSON("{""modelName"":""text-embedding-005"",""region"":""us-central1"",""project"":""p""}")
    Do ..AssertValidateThrows(config, "apiKey")
}

Method AssertValidateThrows(config As %DynamicObject, field As %String) [ Private ]
{
    Set threw = 0, errMsg = ""
    Try { Do ##class(dc.omniEmbedding.provider.VertexAi).ValidateConfig(config) }
    Catch ex { Set threw = 1, errMsg = ex.DisplayString() }
    Do $$$AssertTrue(threw, "ValidateConfig throws for missing "_field)
    Do $$$AssertTrue($Find(errMsg, field) > 0, "error mentions '"_field_"': "_errMsg)
}

// --- BuildPayload: minimal ---

Method TestBuildPayloadMinimal()
{
    Set config = ##class(%DynamicObject).%FromJSON("{""modelName"":""text-embedding-005""}")
    Set payload = ##class(dc.omniEmbedding.provider.VertexAi).BuildPayload("hello", config)
    // instances[0].content = "hello"
    Set inst = payload.instances.%Get(0)
    Do $$$AssertEquals(inst.content, "hello", "content set")
    Do $$$AssertEquals(inst.%Get("task_type"), "", "no task_type when omitted")
    Do $$$AssertEquals(inst.%Get("title"), "", "no title when omitted")
    // Parameters block absent when no optional param present
    Do $$$AssertEquals(payload.%Get("parameters"), "", "no parameters block when all optionals omitted")
}

// --- BuildPayload: task_type / title ---

Method TestBuildPayloadWithTaskType()
{
    Set config = ##class(%DynamicObject).%FromJSON("{""modelName"":""text-embedding-005"",""taskType"":""RETRIEVAL_QUERY""}")
    Set payload = ##class(dc.omniEmbedding.provider.VertexAi).BuildPayload("q", config)
    Do $$$AssertEquals(payload.instances.%Get(0).%Get("task_type"), "RETRIEVAL_QUERY", "task_type at instance level (snake_case at wire)")
}

Method TestBuildPayloadWithTitle()
{
    Set config = ##class(%DynamicObject).%FromJSON("{""modelName"":""text-embedding-005"",""taskType"":""RETRIEVAL_DOCUMENT"",""title"":""Alice in Wonderland""}")
    Set payload = ##class(dc.omniEmbedding.provider.VertexAi).BuildPayload("chapter 1...", config)
    Set inst = payload.instances.%Get(0)
    Do $$$AssertEquals(inst.title, "Alice in Wonderland", "title forwarded (only meaningful for RETRIEVAL_DOCUMENT)")
    Do $$$AssertEquals(inst.%Get("task_type"), "RETRIEVAL_DOCUMENT", "task_type companion set")
}

// --- BuildPayload: parameters block emitted only when needed ---

Method TestBuildPayloadWithOutputDimension()
{
    Set config = ##class(%DynamicObject).%FromJSON("{""modelName"":""text-embedding-005"",""outputDimension"":256}")
    Set payload = ##class(dc.omniEmbedding.provider.VertexAi).BuildPayload("hi", config)
    Do $$$AssertTrue($IsObject(payload.parameters), "parameters block present")
    Do $$$AssertEquals(payload.parameters.outputDimensionality, 256, "outputDimension mapped to outputDimensionality (camelCase preserved)")
}

Method TestBuildPayloadWithAutoTruncateTrue()
{
    Set config = ##class(%DynamicObject).%FromJSON("{""modelName"":""text-embedding-005"",""autoTruncate"":true}")
    Set payload = ##class(dc.omniEmbedding.provider.VertexAi).BuildPayload("very long text", config)
    Do $$$AssertEquals(payload.parameters.autoTruncate, 1, "autoTruncate:true forwarded as 1")
}

Method TestBuildPayloadWithAutoTruncateFalse()
{
    Set config = ##class(%DynamicObject).%FromJSON("{""modelName"":""text-embedding-005"",""autoTruncate"":false}")
    Set payload = ##class(dc.omniEmbedding.provider.VertexAi).BuildPayload("hi", config)
    Do $$$AssertEquals(payload.parameters.autoTruncate, 0, "autoTruncate:false forwarded as 0")
}

Method TestBuildPayloadWithAllExtras()
{
    Set config = ##class(%DynamicObject).%FromJSON("{""modelName"":""text-embedding-005"",""taskType"":""SEMANTIC_SIMILARITY"",""outputDimension"":768,""autoTruncate"":true}")
    Set payload = ##class(dc.omniEmbedding.provider.VertexAi).BuildPayload("compare me", config)
    Do $$$AssertEquals(payload.instances.%Get(0).%Get("task_type"), "SEMANTIC_SIMILARITY", "task_type")
    Do $$$AssertEquals(payload.parameters.outputDimensionality, 768, "outputDimensionality")
    Do $$$AssertEquals(payload.parameters.autoTruncate, 1, "autoTruncate")
}

// --- ParseResponse: valid ---

Method TestParseResponseValid()
{
    Set j = "{""predictions"":[{""embeddings"":{""values"":[0.1,0.2,0.3,0.4,0.5,0.6],""statistics"":{""truncated"":false,""token_count"":5}}}]}"
    Set body = ##class(%DynamicObject).%FromJSON(j)
    Set vec = ##class(dc.omniEmbedding.provider.VertexAi).ParseResponse(body)
    Do $$$AssertTrue(##class(%Library.Vector).IsValid(vec), "valid %Vector")
    Do $$$AssertEquals($Length(##class(%Library.Vector).LogicalToDisplay(vec), ","), 6, "6 elements")
}

// --- ParseResponse: each missing-field path ---

Method TestParseResponseMissingPredictions()
{
    Set body = ##class(%DynamicObject).%FromJSON("{""foo"":""bar""}")
    Do ..AssertParseThrowsWith(body, "predictions")
}

Method TestParseResponseMissingFirstPrediction()
{
    Set body = ##class(%DynamicObject).%FromJSON("{""predictions"":[]}")
    Do ..AssertParseThrowsWith(body, "predictions[0]")
}

Method TestParseResponseMissingEmbeddings()
{
    Set body = ##class(%DynamicObject).%FromJSON("{""predictions"":[{""foo"":""bar""}]}")
    Do ..AssertParseThrowsWith(body, "embeddings")
}

Method TestParseResponseMissingValues()
{
    Set body = ##class(%DynamicObject).%FromJSON("{""predictions"":[{""embeddings"":{""statistics"":{}}}]}")
    Do ..AssertParseThrowsWith(body, "values")
}

Method AssertParseThrowsWith(body As %DynamicObject, fragment As %String) [ Private ]
{
    Set threw = 0, errMsg = ""
    Try { Do ##class(dc.omniEmbedding.provider.VertexAi).ParseResponse(body) }
    Catch ex { Set threw = 1, errMsg = ex.DisplayString() }
    Do $$$AssertTrue(threw, "ParseResponse throws for missing "_fragment)
    Do $$$AssertTrue($Find(errMsg, fragment) > 0, "error mentions '"_fragment_"': "_errMsg)
    Do $$$AssertTrue($Find(errMsg, "Body:") > 0, "error includes body dump")
}

// --- Auth ---

Method TestSetAuthUsesBearerToken()
{
    Set ^||omniEmbeddingCredential("gcp-token") = "ya29.a0AfB_byC-fake-access-token-value"
    Set request = ##class(%Net.HttpRequest).%New()
    Set config = ##class(%DynamicObject).%FromJSON("{""apiKey"":""gcp-token""}")
    Do ##class(dc.omniEmbedding.provider.VertexAi).SetAuth(request, config)
    Do $$$AssertEquals(request.Authorization, "Bearer ya29.a0AfB_byC-fake-access-token-value", "Authorization: Bearer <resolved token>")
    Kill ^||omniEmbeddingCredential("gcp-token")
}

Method TestSetAuthRejectsEmptyToken()
{
    Set request = ##class(%Net.HttpRequest).%New()
    Set config = ##class(%DynamicObject).%FromJSON("{""modelName"":""text-embedding-005""}")
    Set threw = 0
    Try { Do ##class(dc.omniEmbedding.provider.VertexAi).SetAuth(request, config) }
    Catch { Set threw = 1 }
    Do $$$AssertTrue(threw, "throws when access token resolves to empty")
}

// --- Engine dispatch ---

Method TestEngineDispatchExplicitVertex()
{
    Set config = ##class(%DynamicObject).%FromJSON("{""provider"":""vertex"",""modelName"":""text-embedding-005"",""region"":""us-central1"",""project"":""p""}")
    Do $$$AssertEquals(##class(dc.omniEmbedding.Engine).ResolveProvider(config), "dc.omniEmbedding.provider.VertexAi", "explicit 'vertex' -> VertexAi")
}

Method TestEngineDispatchExplicitVertexai()
{
    Set config = ##class(%DynamicObject).%FromJSON("{""provider"":""vertexai"",""modelName"":""text-embedding-005""}")
    Do $$$AssertEquals(##class(dc.omniEmbedding.Engine).ResolveProvider(config), "dc.omniEmbedding.provider.VertexAi", "'vertexai' alias also works")
}

Method TestEngineDoesNotInferVertexFromTextEmbeddingPrefix()
{
    // text-embedding-005 without provider="vertex" MUST resolve to OpenAI
    // (that prefix belongs to OpenAI's text-embedding-3-*, and Vertex only
    // gets dispatched via explicit provider). This guards against the
    // regression where Vertex would silently steal OpenAI traffic.
    Set config = ##class(%DynamicObject).%FromJSON("{""modelName"":""text-embedding-005""}")
    Do $$$AssertEquals(##class(dc.omniEmbedding.Engine).ResolveProvider(config), "dc.omniEmbedding.provider.OpenAi", "text-embedding-005 without provider=vertex → OpenAi")
}

Method TestEngineDoesNotInferVertexFromGeminiEmbeddingPrefix()
{
    // gemini-embedding-001 without provider="vertex" MUST resolve to direct
    // Gemini (embedding- prefix). Vertex-hosted Gemini needs explicit provider.
    Set config = ##class(%DynamicObject).%FromJSON("{""modelName"":""embedding-001""}")
    Do $$$AssertEquals(##class(dc.omniEmbedding.Engine).ResolveProvider(config), "dc.omniEmbedding.provider.Gemini", "embedding-001 → Gemini direct (not Vertex)")
}

Method TestUnknownProviderListsVertex()
{
    Set config = ##class(%DynamicObject).%FromJSON("{""provider"":""bogus"",""modelName"":""m""}")
    Set threw = 0, errMsg = ""
    Try { Do ##class(dc.omniEmbedding.Engine).ResolveProvider(config) }
    Catch ex { Set threw = 1, errMsg = ex.DisplayString() }
    Do $$$AssertTrue(threw, "unknown provider throws")
    Do $$$AssertTrue($Find(errMsg, "vertex") > 0, "vertex listed among valid: "_errMsg)
}

}
