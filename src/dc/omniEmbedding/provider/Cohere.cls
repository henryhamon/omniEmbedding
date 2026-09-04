Include %occStatus

/// Cohere provider — Cohere v2 embed API.
/// Distinct payload shape (`texts` array, `input_type`, `embedding_types`) and
/// nested response (`embeddings.float[0]`) — does NOT inherit from OpenACompatible.
Class dc.omniEmbedding.provider.Cohere Extends dc.omniEmbedding.provider.Base
{

Parameter DEFAULTINPUTTYPE = "search_document";

ClassMethod GetEmbeddingsUrl(config As %DynamicObject) As %String
{
    Return "https://api.cohere.com/v2/embed"
}

ClassMethod SetAuth(request As %Net.HttpRequest, config As %DynamicObject)
{
    Set key = ..ResolveApiKey(config)
    If key = "" {
        $$$ThrowStatus($$$ERROR($$$GeneralError, "dc.omniEmbedding.provider.Cohere.SetAuth: 'apiKey' resolves to empty value"))
    }
    Set request.Authorization = "Bearer "_key
}

ClassMethod BuildPayload(input As %String, config As %DynamicObject) As %DynamicObject
{
    Set inputType = config.%Get("inputType")
    If inputType = "" { Set inputType = ..#DEFAULTINPUTTYPE }

    Set payload = {}
    Set payload.texts = [].%Push(input)
    Set payload.model = config.%Get("modelName")
    Set payload."input_type" = inputType
    Set payload."embedding_types" = [].%Push("float")
    Return payload
}

/// Extracts body.embeddings.float[0] -> %Vector.
/// Throws with body content on any missing field.
ClassMethod ParseResponse(body As %DynamicObject) As %Vector
{
    Set embeddings = body.%Get("embeddings")
    If '$IsObject(embeddings) {
        $$$ThrowStatus($$$ERROR($$$GeneralError, "dc.omniEmbedding.provider.Cohere.ParseResponse: 'embeddings' field missing. Body: "_body.%ToJSON()))
    }
    Set floatArr = embeddings.%Get("float")
    If '$IsObject(floatArr) {
        $$$ThrowStatus($$$ERROR($$$GeneralError, "dc.omniEmbedding.provider.Cohere.ParseResponse: 'embeddings.float' field missing. Body: "_body.%ToJSON()))
    }
    Set first = floatArr.%Get(0)
    If '$IsObject(first) {
        $$$ThrowStatus($$$ERROR($$$GeneralError, "dc.omniEmbedding.provider.Cohere.ParseResponse: 'embeddings.float[0]' missing. Body: "_body.%ToJSON()))
    }
    Return ..BuildVector(first)
}

ClassMethod ValidateConfig(config As %DynamicObject)
{
    If config.%Get("modelName") = "" {
        $$$ThrowStatus($$$ERROR($$$GeneralError, "dc.omniEmbedding.provider.Cohere.ValidateConfig: 'modelName' is required"))
    }
    If config.%Get("apiKey") = "" {
        $$$ThrowStatus($$$ERROR($$$GeneralError, "dc.omniEmbedding.provider.Cohere.ValidateConfig: 'apiKey' is required"))
    }
}

/// Cohere-specific token estimate: Floor(ByteLen/3.5) + 1.
ClassMethod EstimateTokenCount(input As %String, config As %DynamicObject) As %Integer
{
    Return $Piece($Length(input) / 3.5, ".", 1) + 1
}

}
