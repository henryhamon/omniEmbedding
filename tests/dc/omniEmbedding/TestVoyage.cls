Include (%occStatus, %outUnitTest)

/// Unit tests for dc.omniEmbedding.provider.Voyage.
/// Covers URL, ValidateConfig (Property 16: inputType enum), BuildPayload
/// (minimal + each optional passthrough + all together), Bearer auth via
/// credential hook, Engine dispatch by explicit name and by voyage- prefix,
/// and ParseResponse against a real Voyage response.
Class dc.omniEmbedding.tests.TestVoyage Extends %UnitTest.TestCase
{

// --- URL ---

Method TestUrlIsVoyageCloud()
{
    Set config = ##class(%DynamicObject).%FromJSON("{""modelName"":""voyage-3""}")
    Set url = ##class(dc.omniEmbedding.provider.Voyage).GetEmbeddingsUrl(config)
    Do $$$AssertEquals(url, "https://api.voyageai.com/v1/embeddings", "fixed Voyage cloud endpoint")
}

// --- ValidateConfig ---

Method TestValidateMissingApiKey()
{
    Set config = ##class(%DynamicObject).%FromJSON("{""modelName"":""voyage-3""}")
    Set threw = 0, errMsg = ""
    Try { Do ##class(dc.omniEmbedding.provider.Voyage).ValidateConfig(config) }
    Catch ex { Set threw = 1, errMsg = ex.DisplayString() }
    Do $$$AssertTrue(threw, "throws when apiKey missing")
    Do $$$AssertTrue($Find(errMsg, "apiKey") > 0, "error mentions apiKey")
}

Method TestValidateMissingModelName()
{
    Set config = ##class(%DynamicObject).%FromJSON("{""apiKey"":""k""}")
    Set threw = 0, errMsg = ""
    Try { Do ##class(dc.omniEmbedding.provider.Voyage).ValidateConfig(config) }
    Catch ex { Set threw = 1, errMsg = ex.DisplayString() }
    Do $$$AssertTrue(threw, "throws when modelName missing")
    Do $$$AssertTrue($Find(errMsg, "modelName") > 0, "error mentions modelName")
}

Method TestValidateAcceptsQueryInputType()
{
    Set config = ##class(%DynamicObject).%FromJSON("{""modelName"":""voyage-3"",""apiKey"":""k"",""inputType"":""query""}")
    Set threw = 0
    Try { Do ##class(dc.omniEmbedding.provider.Voyage).ValidateConfig(config) }
    Catch { Set threw = 1 }
    Do $$$AssertNotTrue(threw, "'query' accepted")
}

Method TestValidateAcceptsDocumentInputType()
{
    Set config = ##class(%DynamicObject).%FromJSON("{""modelName"":""voyage-3"",""apiKey"":""k"",""inputType"":""document""}")
    Set threw = 0
    Try { Do ##class(dc.omniEmbedding.provider.Voyage).ValidateConfig(config) }
    Catch { Set threw = 1 }
    Do $$$AssertNotTrue(threw, "'document' accepted")
}

// --- Property 16: inputType enum ---

Method TestValidateRejectsUnknownInputType()
{
    Set config = ##class(%DynamicObject).%FromJSON("{""modelName"":""voyage-3"",""apiKey"":""k"",""inputType"":""passage""}")
    Set threw = 0, errMsg = ""
    Try { Do ##class(dc.omniEmbedding.provider.Voyage).ValidateConfig(config) }
    Catch ex { Set threw = 1, errMsg = ex.DisplayString() }
    Do $$$AssertTrue(threw, "rejects 'passage' — Voyage only accepts query/document")
    Do $$$AssertTrue($Find(errMsg, "inputType") > 0, "error mentions inputType")
    Do $$$AssertTrue($Find(errMsg, "query") > 0, "error lists 'query' as valid")
    Do $$$AssertTrue($Find(errMsg, "document") > 0, "error lists 'document' as valid")
}

Method TestValidateRejectsEmptyStringExplicit()
{
    // Empty inputType is treated as absent (no validation) — this documents that
    Set config = ##class(%DynamicObject).%FromJSON("{""modelName"":""voyage-3"",""apiKey"":""k"",""inputType"":""""}")
    Set threw = 0
    Try { Do ##class(dc.omniEmbedding.provider.Voyage).ValidateConfig(config) }
    Catch { Set threw = 1 }
    Do $$$AssertNotTrue(threw, "empty inputType is treated as absent, not invalid")
}

// --- BuildPayload: minimal ---

Method TestBuildPayloadMinimal()
{
    Set config = ##class(%DynamicObject).%FromJSON("{""modelName"":""voyage-3""}")
    Set payload = ##class(dc.omniEmbedding.provider.Voyage).BuildPayload("hello", config)
    Do $$$AssertEquals(payload.%Get("input"), "hello", "input")
    Do $$$AssertEquals(payload.%Get("model"), "voyage-3", "model")
    Set count = 0, iter = payload.%GetIterator()
    While iter.%GetNext(.k, .v) { Set count = count + 1 }
    Do $$$AssertEquals(count, 2, "minimal payload has exactly input + model")
}

// --- BuildPayload: each passthrough ---

Method TestBuildPayloadWithInputType()
{
    Set config = ##class(%DynamicObject).%FromJSON("{""modelName"":""voyage-3"",""inputType"":""query""}")
    Set payload = ##class(dc.omniEmbedding.provider.Voyage).BuildPayload("q", config)
    Do $$$AssertEquals(payload.%Get("input_type"), "query", "input_type forwarded")
}

Method TestBuildPayloadWithTruncationTrue()
{
    Set config = ##class(%DynamicObject).%FromJSON("{""modelName"":""voyage-3"",""truncation"":true}")
    Set payload = ##class(dc.omniEmbedding.provider.Voyage).BuildPayload("hi", config)
    Do $$$AssertEquals(payload.truncation, 1, "truncation:true forwarded as boolean 1")
}

Method TestBuildPayloadWithTruncationFalse()
{
    Set config = ##class(%DynamicObject).%FromJSON("{""modelName"":""voyage-3"",""truncation"":false}")
    Set payload = ##class(dc.omniEmbedding.provider.Voyage).BuildPayload("hi", config)
    Do $$$AssertEquals(payload.truncation, 0, "truncation:false forwarded as boolean 0")
}

Method TestBuildPayloadWithOutputDimension()
{
    Set config = ##class(%DynamicObject).%FromJSON("{""modelName"":""voyage-3-large"",""outputDimension"":1024}")
    Set payload = ##class(dc.omniEmbedding.provider.Voyage).BuildPayload("hi", config)
    Do $$$AssertEquals(payload.%Get("output_dimension"), 1024, "output_dimension forwarded as int")
}

Method TestBuildPayloadWithOutputDtype()
{
    Set config = ##class(%DynamicObject).%FromJSON("{""modelName"":""voyage-3"",""outputDtype"":""int8""}")
    Set payload = ##class(dc.omniEmbedding.provider.Voyage).BuildPayload("hi", config)
    Do $$$AssertEquals(payload.%Get("output_dtype"), "int8", "output_dtype forwarded")
}

Method TestBuildPayloadWithAllExtras()
{
    Set config = ##class(%DynamicObject).%FromJSON("{""modelName"":""voyage-code-3"",""inputType"":""document"",""truncation"":true,""outputDimension"":512,""outputDtype"":""binary""}")
    Set payload = ##class(dc.omniEmbedding.provider.Voyage).BuildPayload("def foo(): pass", config)
    Do $$$AssertEquals(payload.%Get("input_type"), "document", "input_type")
    Do $$$AssertEquals(payload.truncation, 1, "truncation")
    Do $$$AssertEquals(payload.%Get("output_dimension"), 512, "output_dimension")
    Do $$$AssertEquals(payload.%Get("output_dtype"), "binary", "output_dtype")
    Do $$$AssertEquals(payload.%Get("model"), "voyage-code-3", "code model preserved")
}

// --- Auth: Bearer via credential lookup ---

Method TestSetAuthUsesBearer()
{
    Set ^||omniEmbeddingCredential("voyage-test") = "pa-live-key"
    Set request = ##class(%Net.HttpRequest).%New()
    Set config = ##class(%DynamicObject).%FromJSON("{""modelName"":""voyage-3"",""apiKey"":""voyage-test""}")
    Do ##class(dc.omniEmbedding.provider.Voyage).SetAuth(request, config)
    Do $$$AssertEquals(request.Authorization, "Bearer pa-live-key", "Authorization: Bearer <resolved>")
    Kill ^||omniEmbeddingCredential("voyage-test")
}

// --- Engine dispatch ---

Method TestEngineDispatchExplicit()
{
    Set config = ##class(%DynamicObject).%FromJSON("{""provider"":""voyage"",""modelName"":""anything""}")
    Do $$$AssertEquals(##class(dc.omniEmbedding.Engine).ResolveProvider(config), "dc.omniEmbedding.provider.Voyage", "explicit 'voyage' -> Voyage class")
}

Method TestEngineDispatchByVoyagePrefix()
{
    Set config = ##class(%DynamicObject).%FromJSON("{""modelName"":""voyage-3""}")
    Do $$$AssertEquals(##class(dc.omniEmbedding.Engine).ResolveProvider(config), "dc.omniEmbedding.provider.Voyage", "voyage- prefix -> Voyage")
}

Method TestEngineDispatchByVoyageCodePrefix()
{
    Set config = ##class(%DynamicObject).%FromJSON("{""modelName"":""voyage-code-3""}")
    Do $$$AssertEquals(##class(dc.omniEmbedding.Engine).ResolveProvider(config), "dc.omniEmbedding.provider.Voyage", "voyage-code-3 also -> Voyage")
}

Method TestEngineDispatchByVoyageFinancePrefix()
{
    Set config = ##class(%DynamicObject).%FromJSON("{""modelName"":""voyage-finance-2""}")
    Do $$$AssertEquals(##class(dc.omniEmbedding.Engine).ResolveProvider(config), "dc.omniEmbedding.provider.Voyage", "voyage-finance-2 also -> Voyage")
}

// --- ParseResponse: OpenAI-shape, inherited ---

Method TestParseResponseValid()
{
    Set j = "{""object"":""list"",""data"":[{""object"":""embedding"",""embedding"":[0.11,0.22,0.33,0.44,0.55],""index"":0}],""model"":""voyage-3"",""usage"":{""total_tokens"":5}}"
    Set body = ##class(%DynamicObject).%FromJSON(j)
    Set vec = ##class(dc.omniEmbedding.provider.Voyage).ParseResponse(body)
    Do $$$AssertTrue(##class(%Library.Vector).IsValid(vec), "valid %Vector")
    Set disp = ##class(%Library.Vector).LogicalToDisplay(vec)
    Do $$$AssertEquals($Length(disp, ","), 5, "vector has 5 elements")
}

// --- Regression: unknown provider must list voyage ---

Method TestUnknownProviderListsVoyage()
{
    Set config = ##class(%DynamicObject).%FromJSON("{""provider"":""bogus"",""modelName"":""m""}")
    Set threw = 0, errMsg = ""
    Try { Do ##class(dc.omniEmbedding.Engine).ResolveProvider(config) }
    Catch ex { Set threw = 1, errMsg = ex.DisplayString() }
    Do $$$AssertTrue(threw, "unknown provider throws")
    Do $$$AssertTrue($Find(errMsg, "voyage") > 0, "voyage listed among valid: "_errMsg)
}

}
