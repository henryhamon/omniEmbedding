Include (%occStatus, %outUnitTest)

/// Unit tests for dc.omniEmbedding.provider.Gemini.
/// Covers URL construction (auth in query string), SetAuth no-op contract,
/// BuildPayload structure, Property 10 (ParseResponse rejects malformed bodies),
/// EstimateTokenCount formula, and ValidateConfig contract.
Class dc.omniEmbedding.tests.TestGemini Extends %UnitTest.TestCase
{

// --- GetEmbeddingsUrl: auth in query string ---

Method TestUrlIncludesModelAndKey()
{
    Set config = ##class(%DynamicObject).%FromJSON("{""modelName"":""embedding-001"",""apiKey"":""gk-abc""}")
    Set url = ##class(dc.omniEmbedding.provider.Gemini).GetEmbeddingsUrl(config)
    Do $$$AssertEquals(url, "https://generativelanguage.googleapis.com/v1beta/models/embedding-001:embedContent?key=gk-abc", "url embeds model and apiKey")
}

Method TestUrlThrowsOnEmptyKey()
{
    Set config = ##class(%DynamicObject).%FromJSON("{""modelName"":""embedding-001""}")
    Set threw = 0
    Try { Do ##class(dc.omniEmbedding.provider.Gemini).GetEmbeddingsUrl(config) }
    Catch { Set threw = 1 }
    Do $$$AssertTrue(threw, "throws when apiKey resolves to empty")
}

// --- SetAuth: no headers set ---

Method TestSetAuthIsNoOp()
{
    Set request = ##class(%Net.HttpRequest).%New()
    Set config = ##class(%DynamicObject).%FromJSON("{""modelName"":""embedding-001"",""apiKey"":""gk""}")
    Do ##class(dc.omniEmbedding.provider.Gemini).SetAuth(request, config)
    Do $$$AssertEquals(request.Authorization, "", "no Authorization header")
    Do $$$AssertEquals(request.GetHeader("api-key"), "", "no api-key header")
    Do $$$AssertEquals(request.GetHeader("x-goog-api-key"), "", "no x-goog-api-key header")
}

// --- BuildPayload structure ---

Method TestBuildPayloadDefaultTaskType()
{
    Set config = ##class(%DynamicObject).%FromJSON("{""modelName"":""embedding-001""}")
    Set payload = ##class(dc.omniEmbedding.provider.Gemini).BuildPayload("hello", config)
    Do $$$AssertEquals(payload.taskType, "RETRIEVAL_DOCUMENT", "default taskType")
    Do $$$AssertEquals(payload.content.parts.%Get(0).text, "hello", "text nested in content.parts[0].text")
}

Method TestBuildPayloadExplicitTaskType()
{
    Set config = ##class(%DynamicObject).%FromJSON("{""modelName"":""embedding-001"",""taskType"":""RETRIEVAL_QUERY""}")
    Set payload = ##class(dc.omniEmbedding.provider.Gemini).BuildPayload("q", config)
    Do $$$AssertEquals(payload.taskType, "RETRIEVAL_QUERY", "explicit taskType wins")
}

// --- ParseResponse: valid ---

Method TestParseResponseValid()
{
    Set body = ##class(%DynamicObject).%FromJSON("{""embedding"":{""values"":[0.1,0.2,0.3,0.4]}}")
    Set vec = ##class(dc.omniEmbedding.provider.Gemini).ParseResponse(body)
    Do $$$AssertTrue(##class(%Library.Vector).IsValid(vec), "returned value is a valid %Vector")
    Set disp = ##class(%Library.Vector).LogicalToDisplay(vec)
    Do $$$AssertEquals($Length(disp, ","), 4, "vector has 4 elements")
}

// --- ParseResponse: property 10 ---

Method TestParseResponseMissingEmbedding()
{
    Set body = ##class(%DynamicObject).%FromJSON("{""foo"":""bar""}")
    Do ..AssertParseThrowsWith(body, "embedding")
}

Method TestParseResponseMissingValues()
{
    Set body = ##class(%DynamicObject).%FromJSON("{""embedding"":{""statistics"":{}}}")
    Do ..AssertParseThrowsWith(body, "values")
}

/// Helper: asserts ParseResponse throws and body dump is in the message.
Method AssertParseThrowsWith(body As %DynamicObject, fragment As %String) [ Private ]
{
    Set threw = 0, errMsg = ""
    Try { Do ##class(dc.omniEmbedding.provider.Gemini).ParseResponse(body) }
    Catch ex { Set threw = 1, errMsg = ex.DisplayString() }
    Do $$$AssertTrue(threw, "ParseResponse throws for missing "_fragment)
    Do $$$AssertTrue($Find(errMsg, fragment) > 0, "error mentions '"_fragment_"': "_errMsg)
    Do $$$AssertTrue($Find(errMsg, "Body:") > 0, "error includes body dump for diagnosis")
}

// --- EstimateTokenCount: Floor(ByteLen/4) + 2 ---

Method TestEstimateTokenCountFormula()
{
    Set config = ##class(%DynamicObject).%FromJSON("{""modelName"":""embedding-001""}")
    // "hello world" = 11 bytes; floor(11/4)+2 = 2+2 = 4
    Set n = ##class(dc.omniEmbedding.provider.Gemini).EstimateTokenCount("hello world", config)
    Do $$$AssertEquals(n, 4, "11 bytes -> 4 tokens (floor(11/4)+2)")
    // empty
    Set n2 = ##class(dc.omniEmbedding.provider.Gemini).EstimateTokenCount("", config)
    Do $$$AssertEquals(n2, 2, "empty string -> 2 (min tokens)")
}

// --- ValidateConfig ---

Method TestValidateMissingApiKey()
{
    Set config = ##class(%DynamicObject).%FromJSON("{""modelName"":""embedding-001""}")
    Set threw = 0, errMsg = ""
    Try { Do ##class(dc.omniEmbedding.provider.Gemini).ValidateConfig(config) }
    Catch ex { Set threw = 1, errMsg = ex.DisplayString() }
    Do $$$AssertTrue(threw, "throws when apiKey missing")
    Do $$$AssertTrue($Find(errMsg, "apiKey") > 0, "error mentions apiKey")
}

Method TestValidateMissingModelName()
{
    Set config = ##class(%DynamicObject).%FromJSON("{""apiKey"":""gk""}")
    Set threw = 0, errMsg = ""
    Try { Do ##class(dc.omniEmbedding.provider.Gemini).ValidateConfig(config) }
    Catch ex { Set threw = 1, errMsg = ex.DisplayString() }
    Do $$$AssertTrue(threw, "throws when modelName missing")
    Do $$$AssertTrue($Find(errMsg, "modelName") > 0, "error mentions modelName")
}

}
