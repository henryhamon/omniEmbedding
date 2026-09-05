Include (%occStatus, %outUnitTest)

/// Unit tests for dc.omniEmbedding.provider.OpenACompatible (exercised via Ollama).
/// Covers Property 9 (BuildPayload shape), ParseResponse error paths,
/// EstimateTokenCount floor behaviour, and ValidateConfig contract.
Class dc.omniEmbedding.tests.TestOpenACompatible Extends %UnitTest.TestCase
{

// --- Property 9: BuildPayload returns exactly input+model fields ---

Method TestBuildPayloadBasicShape()
{
    Set j = "{""modelName"":""nomic-embed-text""}"
    Set config = ##class(%DynamicObject).%FromJSON(j)
    Set payload = ##class(dc.omniEmbedding.provider.Ollama).BuildPayload("hello world", config)
    Do $$$AssertEquals(payload.%Get("input"), "hello world", "input field matches")
    Do $$$AssertEquals(payload.%Get("model"), "nomic-embed-text", "model field matches")
}

Method TestBuildPayloadExactlyTwoFields()
{
    Set j = "{""modelName"":""text-embedding-3-small"",""apiKey"":""sk-x"",""dimensions"":1536}"
    Set config = ##class(%DynamicObject).%FromJSON(j)
    Set payload = ##class(dc.omniEmbedding.provider.Ollama).BuildPayload("test input", config)
    Do $$$AssertEquals(payload.%Get("input"), "test input", "input field correct")
    Do $$$AssertEquals(payload.%Get("model"), "text-embedding-3-small", "model field correct")
    Set count = 0
    Set iter = payload.%GetIterator()
    While iter.%GetNext(.k, .v) { Set count = count + 1 }
    Do $$$AssertEquals(count, 2, "payload has exactly 2 fields")
}

// --- ParseResponse: valid response extracts a %Vector ---

Method TestParseResponseValidResponse()
{
    Set j = "{""data"":[{""embedding"":[0.1,0.2,0.3],""index"":0,""object"":""embedding""}],""model"":""nomic-embed-text"",""object"":""list""}"
    Set body = ##class(%DynamicObject).%FromJSON(j)
    Set vec = ##class(dc.omniEmbedding.provider.Ollama).ParseResponse(body)
    Do $$$AssertTrue(##class(%Library.Vector).IsValid(vec), "returned value is a valid %Vector")
    // $vector(v,i,...) read syntax is opaque on IRIS 2026+ — introspect via %Library.Vector
    Set disp = ##class(%Library.Vector).LogicalToDisplay(vec)
    Do $$$AssertEquals($Length(disp, ","), 3, "vector has 3 elements")
    Set v1 = +$Piece(disp, ",", 1)
    Do $$$AssertTrue((v1 > 0.09) && (v1 < 0.11), "first element approximately 0.1")
}

// --- ParseResponse: missing fields throw with body in message ---

Method TestParseResponseMissingData()
{
    Set j = "{""model"":""nomic-embed-text""}"
    Set body = ##class(%DynamicObject).%FromJSON(j)
    Set threw = 0, errMsg = ""
    Try {
        Do ##class(dc.omniEmbedding.provider.Ollama).ParseResponse(body)
    } Catch ex {
        Set threw = 1, errMsg = ex.DisplayString()
    }
    Do $$$AssertTrue(threw, "throws when data field missing")
    Do $$$AssertTrue($Find(errMsg, "data") > 0, "error message mentions data")
}

Method TestParseResponseMissingEmbedding()
{
    Set j = "{""data"":[{""index"":0,""object"":""embedding""}],""model"":""nomic-embed-text""}"
    Set body = ##class(%DynamicObject).%FromJSON(j)
    Set threw = 0, errMsg = ""
    Try {
        Do ##class(dc.omniEmbedding.provider.Ollama).ParseResponse(body)
    } Catch ex {
        Set threw = 1, errMsg = ex.DisplayString()
    }
    Do $$$AssertTrue(threw, "throws when data[0].embedding missing")
    Do $$$AssertTrue($Find(errMsg, "embedding") > 0, "error message mentions embedding")
}

Method TestParseResponseEmptyDataArray()
{
    Set j = "{""data"":[],""model"":""nomic-embed-text""}"
    Set body = ##class(%DynamicObject).%FromJSON(j)
    Set threw = 0
    Try {
        Do ##class(dc.omniEmbedding.provider.Ollama).ParseResponse(body)
    } Catch ex {
        Set threw = 1
    }
    Do $$$AssertTrue(threw, "throws when data array is empty")
}

// --- EstimateTokenCount ---

Method TestEstimateTokenCountPositive()
{
    Set j = "{""modelName"":""nomic-embed-text""}"
    Set config = ##class(%DynamicObject).%FromJSON(j)
    Set count = ##class(dc.omniEmbedding.provider.Ollama).EstimateTokenCount("Hello, this is a test.", config)
    Do $$$AssertTrue(count > 0, "token count is positive")
}

Method TestEstimateTokenCountLongerIsHigher()
{
    Set j = "{""modelName"":""nomic-embed-text""}"
    Set config = ##class(%DynamicObject).%FromJSON(j)
    Set shortCount = ##class(dc.omniEmbedding.provider.Ollama).EstimateTokenCount("Hi", config)
    Set longTxt = "This is a much longer sentence that should produce a higher token count estimate."
    Set longCount = ##class(dc.omniEmbedding.provider.Ollama).EstimateTokenCount(longTxt, config)
    Do $$$AssertTrue(longCount > shortCount, "longer text gets higher token estimate")
}

// --- ValidateConfig ---

Method TestValidateConfigMissingModelName()
{
    Set j = "{""apiKey"":""test""}"
    Set config = ##class(%DynamicObject).%FromJSON(j)
    Set threw = 0
    Try {
        Do ##class(dc.omniEmbedding.provider.Ollama).ValidateConfig(config)
    } Catch ex {
        Set threw = 1
    }
    Do $$$AssertTrue(threw, "throws when modelName absent")
}

/// Property 6: Ollama ValidateConfig does NOT throw for absent apiKey.
Method TestValidateConfigOllamaNoApiKey()
{
    Set j = "{""modelName"":""nomic-embed-text""}"
    Set config = ##class(%DynamicObject).%FromJSON(j)
    Set threw = 0
    Try {
        Do ##class(dc.omniEmbedding.provider.Ollama).ValidateConfig(config)
    } Catch ex {
        Set threw = 1
    }
    Do $$$AssertNotTrue(threw, "Ollama ValidateConfig passes without apiKey")
}

}
