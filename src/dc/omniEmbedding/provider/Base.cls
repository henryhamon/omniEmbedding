Include %occStatus

/// Abstract base class for all omniEmbedding providers.
/// Implements the Template Method pattern via Execute() [Final].
/// Subclasses override: SetAuth, GetEmbeddingsUrl, BuildPayload, ParseResponse, ValidateConfig.
/// ValidateConfig subclasses MUST call ##super() first.
Class dc.omniEmbedding.provider.Base [ Abstract ]
{

/// Template Method — final, not to be overridden.
/// Sequence: ValidateConfig → SetAuth → GetEmbeddingsUrl → BuildPayload
///           → RetryWithBackoff → ParseResponse
ClassMethod Execute(input As %String, config As %DynamicObject) As %Vector [ Final ]
{
    Do ..ValidateConfig(config)

    Set request = ##class(%Net.HttpRequest).%New()
    Set request.ContentType = "application/json"
    Set timeout = config.%Get("httpTimeout")
    Set request.Timeout = $Select(+timeout > 0: +timeout, 1: 30)
    Set sslConfig = config.%Get("sslConfig")
    If sslConfig '= "" {
        Set request.SSLConfiguration = sslConfig
    }

    Do ..SetAuth(request, config)

    Set url = ..GetEmbeddingsUrl(config)
    Set payload = ..BuildPayload(input, config)
    Do request.EntityBody.Write(payload.%ToJSON())

    Set response = ..RetryWithBackoff(request, url, config)

    Set body = {}.%FromJSON(response.Data)
    Set vector = ..ParseResponse(body)

    Return vector
}

/// Validates provider-specific configuration fields.
/// Base validates only that modelName is present.
/// Subclasses MUST call ##super() then add their own checks.
ClassMethod ValidateConfig(config As %DynamicObject) [ Abstract ]
{
}

/// Conservative floor estimate: (byteLen / 4) + 1.
/// Always available offline, no dependencies.
/// Subclasses may override with more accurate strategies.
ClassMethod EstimateTokenCount(input As %String, config As %DynamicObject) As %Integer
{
    Quit ($Length(input) \ 4) + 1
}

/// Sets authentication headers on the HTTP request.
ClassMethod SetAuth(request As %Net.HttpRequest, config As %DynamicObject) [ Abstract ]
{
}

/// Returns the full URL for the embeddings endpoint.
ClassMethod GetEmbeddingsUrl(config As %DynamicObject) As %String [ Abstract ]
{
}

/// Builds the JSON request body as a %DynamicObject.
ClassMethod BuildPayload(input As %String, config As %DynamicObject) As %DynamicObject [ Abstract ]
{
}

/// Parses the HTTP response body and returns a %Vector.
/// MUST throw — never return empty/null vector on failure.
ClassMethod ParseResponse(body As %DynamicObject) As %Vector [ Abstract ]
{
}

/// Executes the HTTP POST with a single attempt.
/// STUB — Phase 5 adds full retry/backoff logic.
/// Throws on transport error or non-2xx status.
ClassMethod RetryWithBackoff(request As %Net.HttpRequest, url As %String, config As %DynamicObject) As %Net.HttpResponse [ Private ]
{
    Set sc = request.Post(url)
    If $$$ISERR(sc) {
        Set errMsg = "dc.omniEmbedding.provider.Base: HTTP transport error for URL: " _ url
        $$$ThrowStatus($$$ERROR($$$GeneralError, errMsg))
    }
    Set status = request.HttpResponse.StatusCode
    If (status < 200) || (status >= 300) {
        Set bodySnip = ""
        Try { Set bodySnip = request.HttpResponse.Data.Read(300) } Catch {}
        Set errMsg = "dc.omniEmbedding.provider.Base: HTTP " _ status _ " from '" _ url _ "': " _ bodySnip
        $$$ThrowStatus($$$ERROR($$$GeneralError, errMsg))
    }
    Return request.HttpResponse
}

/// Resolves the API key.
/// STUB — Phase 7 replaces with PasswordCredential lookup.
/// Returns config.apiKey as-is.
ClassMethod ResolveApiKey(config As %DynamicObject) As %String
{
    Return config.%Get("apiKey")
}

/// Shared utility: builds a %Vector from a %DynamicArray of floats.
/// Used by ParseResponse implementations.
/// Pattern matches shipped %Embedding.OpenAI: the produced %Library.Vector is opaque
/// in ObjectScript ($vector(v,i,...) read syntax raises <VECTOR> on IRIS 2026+);
/// introspect only via %Library.Vector.LogicalToDisplay/IsValid or SQL VECTOR_* functions.
ClassMethod BuildVector(embeddingArray As %DynamicArray) As %Vector [ Internal ]
{
    If '$IsObject(embeddingArray) {
        $$$ThrowStatus($$$ERROR($$$GeneralError, "dc.omniEmbedding.provider.Base.BuildVector: embedding array is null"))
    }
    Set v = "", i = 0
    Set iter = embeddingArray.%GetIterator()
    While iter.%GetNext(.key, .val) {
        Set $vector(v, $increment(i), "xf32") = val
    }
    If i = 0 {
        $$$ThrowStatus($$$ERROR($$$GeneralError, "dc.omniEmbedding.provider.Base.BuildVector: embedding array is empty"))
    }
    Return v
}

}
