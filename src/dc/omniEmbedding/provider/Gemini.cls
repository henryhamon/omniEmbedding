Include %occStatus

/// Gemini provider — Google Generative Language API.
/// Authenticates via query string (`?key=`) on the URL rather than a header,
/// so SetAuth is an explicit no-op.
Class dc.omniEmbedding.provider.Gemini Extends dc.omniEmbedding.provider.Base
{

Parameter DEFAULTTASKTYPE = "RETRIEVAL_DOCUMENT";

ClassMethod GetEmbeddingsUrl(config As %DynamicObject) As %String
{
    Set key = ..ResolveApiKey(config)
    If key = "" {
        $$$ThrowStatus($$$ERROR($$$GeneralError, "dc.omniEmbedding.provider.Gemini.GetEmbeddingsUrl: 'apiKey' resolves to empty value"))
    }
    Return "https://generativelanguage.googleapis.com/v1beta/models/"_config.%Get("modelName")_":embedContent?key="_key
}

/// No-op: Gemini authenticates via ?key= on the URL.
ClassMethod SetAuth(request As %Net.HttpRequest, config As %DynamicObject)
{
    // Intentionally empty — auth is embedded in the URL by GetEmbeddingsUrl
}

ClassMethod BuildPayload(input As %String, config As %DynamicObject) As %DynamicObject
{
    Set taskType = config.%Get("taskType")
    If taskType = "" { Set taskType = ..#DEFAULTTASKTYPE }

    Set part = {}
    Set part.text = input
    Set content = {}
    Set content.parts = [].%Push(part)

    Set payload = {}
    Set payload.content = content
    Set payload.taskType = taskType
    Return payload
}

/// Extracts body.embedding.values -> %Vector.
/// Throws with body content on any missing field.
ClassMethod ParseResponse(body As %DynamicObject) As %Vector
{
    Set embedding = body.%Get("embedding")
    If '$IsObject(embedding) {
        $$$ThrowStatus($$$ERROR($$$GeneralError, "dc.omniEmbedding.provider.Gemini.ParseResponse: 'embedding' field missing. Body: "_body.%ToJSON()))
    }
    Set values = embedding.%Get("values")
    If '$IsObject(values) {
        $$$ThrowStatus($$$ERROR($$$GeneralError, "dc.omniEmbedding.provider.Gemini.ParseResponse: 'embedding.values' field missing. Body: "_body.%ToJSON()))
    }
    Return ..BuildVector(values)
}

ClassMethod ValidateConfig(config As %DynamicObject)
{
    If config.%Get("modelName") = "" {
        $$$ThrowStatus($$$ERROR($$$GeneralError, "dc.omniEmbedding.provider.Gemini.ValidateConfig: 'modelName' is required"))
    }
    If config.%Get("apiKey") = "" {
        $$$ThrowStatus($$$ERROR($$$GeneralError, "dc.omniEmbedding.provider.Gemini.ValidateConfig: 'apiKey' is required"))
    }
}

/// Gemini-specific token estimate: Floor(ByteLen/4) + 2.
ClassMethod EstimateTokenCount(input As %String, config As %DynamicObject) As %Integer
{
    Return ($Length(input) \ 4) + 2
}

}
