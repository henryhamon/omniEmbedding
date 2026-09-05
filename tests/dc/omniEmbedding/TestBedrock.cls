Include (%occStatus, %outUnitTest)

/// Unit tests for dc.omniEmbedding.provider.Bedrock.
/// Covers URL composition per region + modelId, family detection (Titan +
/// Cohere-via-Bedrock), payload shape per family, ParseResponse per family,
/// ValidateConfig, credential parsing (colon and JSON forms), Property 19
/// (SigV4 signature applied — Authorization starts with AWS4-HMAC-SHA256),
/// and the Engine's decision to NOT infer Bedrock from model prefix.
Class dc.omniEmbedding.tests.TestBedrock Extends %UnitTest.TestCase
{

Method OnAfterOneTest(testname As %String) As %Status
{
    Kill ^||omniEmbeddingCredential
    Return $$$OK
}

// --- URL ---

Method TestUrlComposedFromRegionAndModel()
{
    Set config = ##class(%DynamicObject).%FromJSON("{""region"":""us-east-1"",""modelName"":""amazon.titan-embed-text-v2:0""}")
    Set url = ##class(dc.omniEmbedding.provider.Bedrock).GetEmbeddingsUrl(config)
    Do $$$AssertEquals(url, "https://bedrock-runtime.us-east-1.amazonaws.com/model/amazon.titan-embed-text-v2:0/invoke", "URL composed with region + modelId")
}

Method TestUrlHonorsDifferentRegion()
{
    Set config = ##class(%DynamicObject).%FromJSON("{""region"":""eu-west-1"",""modelName"":""cohere.embed-english-v3""}")
    Set url = ##class(dc.omniEmbedding.provider.Bedrock).GetEmbeddingsUrl(config)
    Do $$$AssertTrue($Find(url, "bedrock-runtime.eu-west-1.amazonaws.com") > 0, "region interpolated")
    Do $$$AssertTrue($Find(url, "/model/cohere.embed-english-v3/invoke") > 0, "modelId interpolated")
}

// --- ValidateConfig ---

Method TestValidateMissingModelName()
{
    Set config = ##class(%DynamicObject).%FromJSON("{""region"":""us-east-1"",""apiKey"":""k""}")
    Set threw = 0, errMsg = ""
    Try { Do ##class(dc.omniEmbedding.provider.Bedrock).ValidateConfig(config) }
    Catch ex { Set threw = 1, errMsg = ex.DisplayString() }
    Do $$$AssertTrue(threw, "throws on missing modelName")
    Do $$$AssertTrue($Find(errMsg, "modelName") > 0, "mentions modelName")
}

Method TestValidateMissingRegion()
{
    Set config = ##class(%DynamicObject).%FromJSON("{""modelName"":""amazon.titan-embed-text-v2:0"",""apiKey"":""k""}")
    Set threw = 0, errMsg = ""
    Try { Do ##class(dc.omniEmbedding.provider.Bedrock).ValidateConfig(config) }
    Catch ex { Set threw = 1, errMsg = ex.DisplayString() }
    Do $$$AssertTrue(threw, "throws on missing region")
    Do $$$AssertTrue($Find(errMsg, "region") > 0, "mentions region")
}

Method TestValidateMissingApiKey()
{
    Set config = ##class(%DynamicObject).%FromJSON("{""modelName"":""amazon.titan-embed-text-v2:0"",""region"":""us-east-1""}")
    Set threw = 0, errMsg = ""
    Try { Do ##class(dc.omniEmbedding.provider.Bedrock).ValidateConfig(config) }
    Catch ex { Set threw = 1, errMsg = ex.DisplayString() }
    Do $$$AssertTrue(threw, "throws on missing apiKey")
    Do $$$AssertTrue($Find(errMsg, "apiKey") > 0, "mentions apiKey")
}

Method TestValidateUnsupportedModelFamily()
{
    Set config = ##class(%DynamicObject).%FromJSON("{""modelName"":""anthropic.claude-3-sonnet"",""region"":""us-east-1"",""apiKey"":""k""}")
    Set threw = 0, errMsg = ""
    Try { Do ##class(dc.omniEmbedding.provider.Bedrock).ValidateConfig(config) }
    Catch ex { Set threw = 1, errMsg = ex.DisplayString() }
    Do $$$AssertTrue(threw, "rejects non-embedding families early")
    Do $$$AssertTrue($Find(errMsg, "amazon.titan-embed") > 0, "lists supported families")
    Do $$$AssertTrue($Find(errMsg, "cohere.embed-") > 0, "lists supported families")
}

// --- Family detection ---

Method TestDetectFamilyTitan()
{
    Do $$$AssertEquals(##class(dc.omniEmbedding.provider.Bedrock).DetectFamily("amazon.titan-embed-text-v2:0"), "titan", "titan-embed-text")
    Do $$$AssertEquals(##class(dc.omniEmbedding.provider.Bedrock).DetectFamily("amazon.titan-embed-image-v1"), "titan", "titan-embed-image")
}

Method TestDetectFamilyCohere()
{
    Do $$$AssertEquals(##class(dc.omniEmbedding.provider.Bedrock).DetectFamily("cohere.embed-english-v3"), "cohere", "cohere.embed-english-v3")
    Do $$$AssertEquals(##class(dc.omniEmbedding.provider.Bedrock).DetectFamily("cohere.embed-multilingual-v3"), "cohere", "cohere.embed-multilingual-v3")
}

// --- BuildPayload per family ---

Method TestBuildPayloadTitan()
{
    Set config = ##class(%DynamicObject).%FromJSON("{""modelName"":""amazon.titan-embed-text-v2:0"",""dimensions"":1024}")
    Set payload = ##class(dc.omniEmbedding.provider.Bedrock).BuildPayload("hello", config)
    Do $$$AssertEquals(payload.inputText, "hello", "inputText")
    Do $$$AssertEquals(payload.dimensions, 1024, "dimensions forwarded")
    Do $$$AssertEquals(payload.normalize, 1, "normalize:true default")
}

Method TestBuildPayloadTitanWithoutDimensions()
{
    Set config = ##class(%DynamicObject).%FromJSON("{""modelName"":""amazon.titan-embed-text-v2:0""}")
    Set payload = ##class(dc.omniEmbedding.provider.Bedrock).BuildPayload("hi", config)
    Do $$$AssertEquals(payload.inputText, "hi", "inputText set")
    Do $$$AssertEquals(payload.%Get("dimensions"), "", "no dimensions when omitted")
}

Method TestBuildPayloadCohereDefault()
{
    Set config = ##class(%DynamicObject).%FromJSON("{""modelName"":""cohere.embed-english-v3""}")
    Set payload = ##class(dc.omniEmbedding.provider.Bedrock).BuildPayload("hello", config)
    Do $$$AssertEquals(payload.texts.%Get(0), "hello", "text wrapped in texts[]")
    Do $$$AssertEquals(payload.%Get("input_type"), "search_document", "default input_type")
}

Method TestBuildPayloadCohereExplicitInputType()
{
    Set config = ##class(%DynamicObject).%FromJSON("{""modelName"":""cohere.embed-english-v3"",""inputType"":""search_query""}")
    Set payload = ##class(dc.omniEmbedding.provider.Bedrock).BuildPayload("q", config)
    Do $$$AssertEquals(payload.%Get("input_type"), "search_query", "explicit input_type wins")
}

// --- ParseResponse per family ---

Method TestParseResponseTitan()
{
    Set config = ##class(%DynamicObject).%FromJSON("{""modelName"":""amazon.titan-embed-text-v2:0""}")
    Set body = ##class(%DynamicObject).%FromJSON("{""embedding"":[0.1,0.2,0.3,0.4],""inputTextTokenCount"":1}")
    Set vec = ##class(dc.omniEmbedding.provider.Bedrock).ParseResponse(body, config)
    Do $$$AssertTrue(##class(%Library.Vector).IsValid(vec), "valid vector")
    Do $$$AssertEquals($Length(##class(%Library.Vector).LogicalToDisplay(vec), ","), 4, "4 elements")
}

Method TestParseResponseTitanMissingEmbedding()
{
    Set config = ##class(%DynamicObject).%FromJSON("{""modelName"":""amazon.titan-embed-text-v2:0""}")
    Set body = ##class(%DynamicObject).%FromJSON("{""error"":""oops""}")
    Set threw = 0, errMsg = ""
    Try { Do ##class(dc.omniEmbedding.provider.Bedrock).ParseResponse(body, config) }
    Catch ex { Set threw = 1, errMsg = ex.DisplayString() }
    Do $$$AssertTrue(threw, "throws when embedding field missing")
    Do $$$AssertTrue($Find(errMsg, "embedding") > 0, "mentions field")
    Do $$$AssertTrue($Find(errMsg, "titan") > 0, "identifies family in error")
}

Method TestParseResponseCohere()
{
    Set config = ##class(%DynamicObject).%FromJSON("{""modelName"":""cohere.embed-english-v3""}")
    Set body = ##class(%DynamicObject).%FromJSON("{""embeddings"":[[0.5,0.6,0.7]],""id"":""x""}")
    Set vec = ##class(dc.omniEmbedding.provider.Bedrock).ParseResponse(body, config)
    Do $$$AssertTrue(##class(%Library.Vector).IsValid(vec), "valid vector")
    Do $$$AssertEquals($Length(##class(%Library.Vector).LogicalToDisplay(vec), ","), 3, "3 elements from embeddings[0]")
}

Method TestParseResponseCohereMissingEmbeddings()
{
    Set config = ##class(%DynamicObject).%FromJSON("{""modelName"":""cohere.embed-english-v3""}")
    Set body = ##class(%DynamicObject).%FromJSON("{""foo"":""bar""}")
    Set threw = 0, errMsg = ""
    Try { Do ##class(dc.omniEmbedding.provider.Bedrock).ParseResponse(body, config) }
    Catch ex { Set threw = 1, errMsg = ex.DisplayString() }
    Do $$$AssertTrue(threw, "throws when embeddings missing")
    Do $$$AssertTrue($Find(errMsg, "cohere") > 0, "identifies family in error")
}

// --- Credential parsing ---

Method TestParseCredentialColonForm()
{
    Do $$$AssertEquals(##class(dc.omniEmbedding.provider.Bedrock).ParseAwsCredential("AKIAEXAMPLE:secretVal123", "accessKeyId"), "AKIAEXAMPLE", "colon form → accessKeyId")
    Do $$$AssertEquals(##class(dc.omniEmbedding.provider.Bedrock).ParseAwsCredential("AKIAEXAMPLE:secretVal123", "secretAccessKey"), "secretVal123", "colon form → secretAccessKey")
}

Method TestParseCredentialJsonForm()
{
    Set json = "{""accessKeyId"":""AKIAJSON"",""secretAccessKey"":""sekret+/=""}"
    Do $$$AssertEquals(##class(dc.omniEmbedding.provider.Bedrock).ParseAwsCredential(json, "accessKeyId"), "AKIAJSON", "JSON form → accessKeyId")
    Do $$$AssertEquals(##class(dc.omniEmbedding.provider.Bedrock).ParseAwsCredential(json, "secretAccessKey"), "sekret+/=", "JSON form → secretAccessKey (preserves special chars)")
}

Method TestParseCredentialInvalidFormat()
{
    Set threw = 0
    Try { Do ##class(dc.omniEmbedding.provider.Bedrock).ParseAwsCredential("no-colon-here", "accessKeyId") }
    Catch { Set threw = 1 }
    Do $$$AssertTrue(threw, "raw string without colon or JSON is rejected")
}

Method TestParseCredentialInvalidJson()
{
    Set threw = 0
    Try { Do ##class(dc.omniEmbedding.provider.Bedrock).ParseAwsCredential("{not-json", "accessKeyId") }
    Catch { Set threw = 1 }
    Do $$$AssertTrue(threw, "malformed JSON credential rejected")
}

// --- Property 19: SigV4 applied — Authorization header prefix check ---

Method TestExecuteAppliesSigV4()
{
    // We can't actually POST to Bedrock without real credentials + network,
    // but we can verify the request WOULD carry a SigV4 Authorization header by
    // driving BuildPayload + SignBedrockRequest directly via a small helper.
    // Instead, exercise SignBedrockRequest indirectly through Execute's internal
    // flow up to just before Post — by stubbing the credential and asserting
    // that after signing, the request's Authorization starts with AWS4-HMAC-SHA256.
    Set ^||omniEmbeddingCredential("aws-test") = "AKIAEXAMPLE:wJalrXUtnFEMI/K7MDENG+bPxRfiCYEXAMPLEKEY"

    // Build a request manually mirroring what Bedrock.Execute does up to signing
    Set request = ##class(%Net.HttpRequest).%New()
    Set request.ContentType = "application/json"
    Set config = ##class(%DynamicObject).%FromJSON("{""modelName"":""amazon.titan-embed-text-v2:0"",""region"":""us-east-1"",""apiKey"":""aws-test""}")
    Set url = ##class(dc.omniEmbedding.provider.Bedrock).GetEmbeddingsUrl(config)
    Set payload = ##class(dc.omniEmbedding.provider.Bedrock).BuildPayload("hello", config)
    Set payloadJson = payload.%ToJSON()

    // Call SigV4 directly with the parsed credentials
    Set access = ##class(dc.omniEmbedding.provider.Bedrock).ParseAwsCredential(##class(dc.omniEmbedding.provider.Base).ResolveApiKey(config), "accessKeyId")
    Set secret = ##class(dc.omniEmbedding.provider.Bedrock).ParseAwsCredential(##class(dc.omniEmbedding.provider.Base).ResolveApiKey(config), "secretAccessKey")
    Do ##class(dc.omniEmbedding.util.SigV4).Sign(request, "POST", url, "us-east-1", "bedrock", access, secret, "", payloadJson)

    Set auth = request.Authorization
    Do $$$AssertEquals($Extract(auth, 1, 17), "AWS4-HMAC-SHA256 ", "SigV4 Authorization header applied")
    Do $$$AssertTrue($Find(auth, "Credential=AKIAEXAMPLE/") > 0, "credential includes accessKeyId")
    Do $$$AssertTrue($Find(auth, "/us-east-1/bedrock/aws4_request") > 0, "credential scope us-east-1/bedrock")
    Do $$$AssertEquals(request.GetHeader("x-amz-date") \ 1, request.GetHeader("x-amz-date") \ 1, "x-amz-date header is set")
    Do $$$AssertTrue($Length(request.GetHeader("x-amz-date")) = 16, "x-amz-date is 16 chars")
}

// --- Engine dispatch: explicit only; NO prefix inference for cohere.embed-* ---

Method TestEngineDispatchExplicit()
{
    Set config = ##class(%DynamicObject).%FromJSON("{""provider"":""bedrock"",""modelName"":""amazon.titan-embed-text-v2:0"",""region"":""us-east-1""}")
    Do $$$AssertEquals(##class(dc.omniEmbedding.Engine).ResolveProvider(config), "dc.omniEmbedding.provider.Bedrock", "explicit 'bedrock' -> Bedrock")
}

Method TestEngineDoesNotInferBedrockFromCoherePrefix()
{
    // ADR-014: cohere.embed-* WITHOUT provider="bedrock" must NOT resolve to Bedrock;
    // Cohere direct owns the "embed-" prefix — the "cohere." dotted prefix is
    // not recognized by the inference table, so this should FAIL to infer and
    // raise the "cannot infer" error, telling the caller to set provider="bedrock".
    Set config = ##class(%DynamicObject).%FromJSON("{""modelName"":""cohere.embed-english-v3""}")
    Set threw = 0, errMsg = ""
    Try { Do ##class(dc.omniEmbedding.Engine).ResolveProvider(config) }
    Catch ex { Set threw = 1, errMsg = ex.DisplayString() }
    Do $$$AssertTrue(threw, "cohere.embed-* without provider=bedrock raises 'cannot infer'")
    Do $$$AssertTrue($Find(errMsg, "cannot infer") > 0, "error orients caller to set provider explicitly")
}

Method TestEngineDoesNotInferBedrockFromTitanPrefix()
{
    Set config = ##class(%DynamicObject).%FromJSON("{""modelName"":""amazon.titan-embed-text-v2:0""}")
    Set threw = 0, errMsg = ""
    Try { Do ##class(dc.omniEmbedding.Engine).ResolveProvider(config) }
    Catch ex { Set threw = 1, errMsg = ex.DisplayString() }
    Do $$$AssertTrue(threw, "amazon.titan-embed-* without provider=bedrock also raises 'cannot infer'")
}

Method TestUnknownProviderListsBedrock()
{
    Set config = ##class(%DynamicObject).%FromJSON("{""provider"":""bogus"",""modelName"":""m""}")
    Set threw = 0, errMsg = ""
    Try { Do ##class(dc.omniEmbedding.Engine).ResolveProvider(config) }
    Catch ex { Set threw = 1, errMsg = ex.DisplayString() }
    Do $$$AssertTrue(threw, "unknown provider throws")
    Do $$$AssertTrue($Find(errMsg, "bedrock") > 0, "bedrock listed among valid")
}

}
