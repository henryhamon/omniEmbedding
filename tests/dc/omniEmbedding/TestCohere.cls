Include (%occStatus, %outUnitTest)

/// Unit tests for dc.omniEmbedding.provider.Cohere.
/// Covers BuildPayload shape (with and without inputType), Property 10
/// (ParseResponse rejects malformed bodies with body-in-message), EstimateTokenCount,
/// and ValidateConfig contract.
Class dc.omniEmbedding.tests.TestCohere Extends %UnitTest.TestCase
{

// --- BuildPayload ---

Method TestBuildPayloadDefaultInputType()
{
    Set config = ##class(%DynamicObject).%FromJSON("{""modelName"":""embed-english-v3.0""}")
    Set payload = ##class(dc.omniEmbedding.provider.Cohere).BuildPayload("hello", config)
    Do $$$AssertEquals(payload.model, "embed-english-v3.0", "model")
    Do $$$AssertEquals(payload."input_type", "search_document", "default input_type is search_document")
    Do $$$AssertEquals(payload.texts.%Get(0), "hello", "input wrapped in texts[]")
    Do $$$AssertEquals(payload."embedding_types".%Get(0), "float", "embedding_types is [float]")
}

Method TestBuildPayloadExplicitInputType()
{
    Set config = ##class(%DynamicObject).%FromJSON("{""modelName"":""embed-english-v3.0"",""inputType"":""search_query""}")
    Set payload = ##class(dc.omniEmbedding.provider.Cohere).BuildPayload("q", config)
    Do $$$AssertEquals(payload."input_type", "search_query", "explicit input_type wins")
}

// --- ParseResponse: valid ---

Method TestParseResponseValid()
{
    Set body = ##class(%DynamicObject).%FromJSON("{""embeddings"":{""float"":[[0.1,0.2,0.3]]}}")
    Set vec = ##class(dc.omniEmbedding.provider.Cohere).ParseResponse(body)
    Do $$$AssertTrue(##class(%Library.Vector).IsValid(vec), "returned value is a valid %Vector")
    Set disp = ##class(%Library.Vector).LogicalToDisplay(vec)
    Do $$$AssertEquals($Length(disp, ","), 3, "vector has 3 elements")
}

// --- ParseResponse: property 10 — malformed bodies throw with body in message ---

Method TestParseResponseMissingEmbeddings()
{
    Set body = ##class(%DynamicObject).%FromJSON("{""foo"":""bar""}")
    Do ..AssertParseThrowsWith(body, "embeddings")
}

Method TestParseResponseMissingFloat()
{
    Set body = ##class(%DynamicObject).%FromJSON("{""embeddings"":{""int8"":[[1,2,3]]}}")
    Do ..AssertParseThrowsWith(body, "float")
}

Method TestParseResponseEmptyFloatArray()
{
    Set body = ##class(%DynamicObject).%FromJSON("{""embeddings"":{""float"":[]}}")
    Do ..AssertParseThrowsWith(body, "float[0]")
}

/// Helper: asserts ParseResponse throws and body content is in the message.
Method AssertParseThrowsWith(body As %DynamicObject, fragment As %String) [ Private ]
{
    Set threw = 0, errMsg = ""
    Try { Do ##class(dc.omniEmbedding.provider.Cohere).ParseResponse(body) }
    Catch ex { Set threw = 1, errMsg = ex.DisplayString() }
    Do $$$AssertTrue(threw, "ParseResponse throws for missing "_fragment)
    Do $$$AssertTrue($Find(errMsg, fragment) > 0, "error mentions '"_fragment_"': "_errMsg)
    Do $$$AssertTrue($Find(errMsg, "Body:") > 0, "error includes body dump for diagnosis")
}

// --- EstimateTokenCount: Floor(ByteLen/3.5) + 1 ---

Method TestEstimateTokenCountFormula()
{
    Set config = ##class(%DynamicObject).%FromJSON("{""modelName"":""embed-english-v3.0""}")
    // "hello world" = 11 bytes; floor(11/3.5)+1 = 3+1 = 4
    Set n = ##class(dc.omniEmbedding.provider.Cohere).EstimateTokenCount("hello world", config)
    Do $$$AssertEquals(n, 4, "11 bytes -> 4 tokens (floor(11/3.5)+1)")
    // "" = 0 bytes; floor(0/3.5)+1 = 1
    Set n2 = ##class(dc.omniEmbedding.provider.Cohere).EstimateTokenCount("", config)
    Do $$$AssertEquals(n2, 1, "empty string -> 1 (min token)")
}

Method TestEstimateTokenCountMonotonic()
{
    Set config = ##class(%DynamicObject).%FromJSON("{""modelName"":""embed-english-v3.0""}")
    Set short = ##class(dc.omniEmbedding.provider.Cohere).EstimateTokenCount("hi", config)
    Set long = ##class(dc.omniEmbedding.provider.Cohere).EstimateTokenCount("this is a much longer sentence for estimation", config)
    Do $$$AssertTrue(long > short, "longer text -> higher estimate")
}

// --- ValidateConfig ---

Method TestValidateMissingApiKey()
{
    Set config = ##class(%DynamicObject).%FromJSON("{""modelName"":""embed-english-v3.0""}")
    Set threw = 0, errMsg = ""
    Try { Do ##class(dc.omniEmbedding.provider.Cohere).ValidateConfig(config) }
    Catch ex { Set threw = 1, errMsg = ex.DisplayString() }
    Do $$$AssertTrue(threw, "throws when apiKey missing")
    Do $$$AssertTrue($Find(errMsg, "apiKey") > 0, "error mentions apiKey")
}

Method TestValidateMissingModelName()
{
    Set config = ##class(%DynamicObject).%FromJSON("{""apiKey"":""k""}")
    Set threw = 0, errMsg = ""
    Try { Do ##class(dc.omniEmbedding.provider.Cohere).ValidateConfig(config) }
    Catch ex { Set threw = 1, errMsg = ex.DisplayString() }
    Do $$$AssertTrue(threw, "throws when modelName missing")
    Do $$$AssertTrue($Find(errMsg, "modelName") > 0, "error mentions modelName")
}

// --- SetAuth: Authorization: Bearer ---

Method TestSetAuthUsesBearer()
{
    Set ^||omniEmbeddingCredential("cohere-test") = "ck-live"
    Set request = ##class(%Net.HttpRequest).%New()
    Set config = ##class(%DynamicObject).%FromJSON("{""modelName"":""m"",""apiKey"":""cohere-test""}")
    Do ##class(dc.omniEmbedding.provider.Cohere).SetAuth(request, config)
    Do $$$AssertEquals(request.Authorization, "Bearer ck-live", "Authorization: Bearer <resolved>")
    Kill ^||omniEmbeddingCredential("cohere-test")
}

}
