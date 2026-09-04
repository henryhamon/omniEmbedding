Include %occStatus

/// Abstract provider for the OpenAI-compatible embedding API family.
/// Covers: OpenAI, Azure OpenAI, Ollama (all share {input, model} payload + data[0].embedding response).
/// Subclasses override GetEmbeddingsUrl, SetAuth (if different), and ValidateConfig.
Class dc.omniEmbedding.provider.OpenACompatible Extends dc.omniEmbedding.provider.Base [ Abstract ]
{

/// Validates that modelName is present.
/// Subclasses call ##super() then add their own checks.
ClassMethod ValidateConfig(config As %DynamicObject)
{
    If config.%Get("modelName") = "" {
        $$$ThrowStatus($$$ERROR($$$GeneralError, "dc.omniEmbedding.provider.OpenACompatible.ValidateConfig: 'modelName' is required"))
    }
}

/// Adds Authorization: Bearer header using the resolved API key.
/// Subclasses may override (e.g. AzureOpenAi uses api-key header; Ollama is a no-op).
ClassMethod SetAuth(request As %Net.HttpRequest, config As %DynamicObject)
{
    Set key = ..ResolveApiKey(config)
    If key '= "" {
        Set request.Authorization = "Bearer " _ key
    }
}

/// Builds the OpenAI-compatible payload: {"input": <text>, "model": <modelName>}
ClassMethod BuildPayload(input As %String, config As %DynamicObject) As %DynamicObject
{
    Set payload = {}
    Set payload.input = input
    Set payload.model = config.%Get("modelName")
    Return payload
}

/// Parses the OpenAI-compatible response: extracts data[0].embedding -> %Vector.
/// Throws with response body if field is absent.
ClassMethod ParseResponse(body As %DynamicObject) As %Vector
{
    Set dataArr = body.%Get("data")
    If '$IsObject(dataArr) {
        Set errMsg = "dc.omniEmbedding.provider.OpenACompatible.ParseResponse: 'data' field missing. Body: " _ body.%ToJSON()
        $$$ThrowStatus($$$ERROR($$$GeneralError, errMsg))
    }
    Set first = dataArr.%Get(0)
    If '$IsObject(first) {
        Set errMsg = "dc.omniEmbedding.provider.OpenACompatible.ParseResponse: 'data[0]' missing. Body: " _ body.%ToJSON()
        $$$ThrowStatus($$$ERROR($$$GeneralError, errMsg))
    }
    Set embArr = first.%Get("embedding")
    If '$IsObject(embArr) {
        Set errMsg = "dc.omniEmbedding.provider.OpenACompatible.ParseResponse: 'data[0].embedding' missing. Body: " _ body.%ToJSON()
        $$$ThrowStatus($$$ERROR($$$GeneralError, errMsg))
    }
    Return ..BuildVector(embArr)
}

/// Estimates token count using tiktoken via Embedded Python when available.
/// Falls back to the conservative Base floor (bytes/4 + 1) if Python or tiktoken unavailable.
ClassMethod EstimateTokenCount(input As %String, config As %DynamicObject) As %Integer
{
    Try {
        Return ..EstimateWithTiktoken(input)
    } Catch {
        Return ##super(input, config)
    }
}

/// Tiktoken estimation via Embedded Python — cl100k_base encoding, module-level cache.
/// Declared as a separate method so the Python block is isolated.
ClassMethod EstimateWithTiktoken(input As %String) As %Integer [ Language = python ]
{
    try:
        import tiktoken
        cache = globals().setdefault("_omni_tiktoken_cache", {})
        enc_name = "cl100k_base"
        enc = cache.get(enc_name)
        if enc is None:
            enc = tiktoken.get_encoding(enc_name)
            cache[enc_name] = enc
        return len(enc.encode(input))
    except Exception:
        raise
}

}
