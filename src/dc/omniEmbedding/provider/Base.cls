Include %occStatus

/// Abstract base class for all omniEmbedding providers.
/// Implements the Template Method pattern via Execute() [Final].
/// Subclasses override: SetAuth, GetEmbeddingsUrl, BuildPayload, ParseResponse, ValidateConfig.
/// ValidateConfig subclasses MUST call ##super() first.
Class dc.omniEmbedding.provider.Base [ Abstract ]
{

/// Template Method — NOT declared Final. Overrides are reserved for providers
/// with a legitimate ordering constraint that this sequence cannot express
/// (currently only Bedrock, which must apply SigV4 AFTER the payload is written
/// so the signature covers the actual body bytes). All other providers MUST use
/// this template unchanged.
/// Sequence: ValidateConfig → SetAuth → GetEmbeddingsUrl → BuildPayload
///           → RetryWithBackoff → ParseResponse
ClassMethod Execute(input As %String, config As %DynamicObject) As %Vector
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

/// Executes the HTTP POST with retry / exponential backoff.
/// Retries on 429 and 5xx. Fast-fails on other 4xx. Honors Retry-After when
/// config.retry.honorRetryAfter is true (default) and the header is present.
/// Retry parameters (all under config.retry, with defaults):
///   maxAttempts (3), baseDelayMs (500), maxDelayMs (8000), honorRetryAfter (1)
/// Throws with the last HTTP status and URL after attempts are exhausted.
ClassMethod RetryWithBackoff(request As %Net.HttpRequest, url As %String, config As %DynamicObject) As %Net.HttpResponse [ Internal ]
{
    Set retry = config.%Get("retry")
    Set maxAttempts = ..RetryParam(retry, "maxAttempts", 3)
    Set honorRetryAfter = ..RetryParam(retry, "honorRetryAfter", 1)

    Set attempt = 0, lastStatus = 0, lastBody = ""
    While attempt < maxAttempts {
        Set attempt = attempt + 1

        Set sc = request.Post(url)
        If $$$ISERR(sc) {
            Set transportErr = $System.Status.GetErrorText(sc)
            Set hint = ..TransportHint(url, transportErr)
            $$$ThrowStatus($$$ERROR($$$GeneralError, "dc.omniEmbedding: HTTP transport error on POST '"_url_"'. Cause: "_transportErr_hint))
        }

        Set lastStatus = request.HttpResponse.StatusCode

        // Success: 2xx
        If (lastStatus >= 200) && (lastStatus < 300) {
            Return request.HttpResponse
        }

        Set lastBody = ""
        Try { Set lastBody = request.HttpResponse.Data.Read(300) } Catch {}

        // Fast-fail on 4xx that are NOT 429
        If ..IsFastFailStatus(lastStatus) {
            Set hint = ..StatusHint(lastStatus, config)
            $$$ThrowStatus($$$ERROR($$$GeneralError, "dc.omniEmbedding: HTTP "_lastStatus_" from '"_url_"' (fast-fail, no retry). "_hint_" Body: "_lastBody))
        }

        // Last attempt: don't sleep, fall through to throw
        If attempt >= maxAttempts { Quit }

        // 429 or 5xx: compute delay and sleep before next attempt
        Set retryAfter = ""
        If honorRetryAfter {
            Set retryAfter = request.HttpResponse.GetHeader("Retry-After")
        }
        Set delayMs = ..ComputeBackoffDelay(attempt, retryAfter, config)
        If delayMs > 0 { Hang delayMs / 1000 }
    }

    Set hint = ..StatusHint(lastStatus, config)
    $$$ThrowStatus($$$ERROR($$$GeneralError, "dc.omniEmbedding: HTTP "_lastStatus_" from '"_url_"' (exhausted "_maxAttempts_" attempts). "_hint_" Body: "_lastBody))
}

/// Returns an actionable hint for common HTTP failure codes.
/// Never leaks the resolved credential value — only the credential NAME
/// (which is public metadata already visible in %Embedding.Config).
ClassMethod StatusHint(status As %Integer, config As %DynamicObject) As %String [ Internal ]
{
    Set credName = config.%Get("apiKey")
    If status = 401 {
        Return "Hint: authentication failed — check that Ens.Config.Credentials '"_credName_"' holds a valid, non-expired key for the provider; regenerate the key in the provider portal if unsure."
    }
    If status = 403 {
        Return "Hint: forbidden — the credential '"_credName_"' resolves, but lacks permission for this endpoint/model/region (check IAM/subscription/quotas on the provider side)."
    }
    If status = 404 {
        Return "Hint: not found — verify config.modelName (or Azure deployment name / Bedrock modelId / GCP project+region) matches something that actually exists at the URL above."
    }
    If status = 413 {
        Return "Hint: payload too large — reduce input length or split into chunks before calling EMBEDDING()."
    }
    If status = 422 {
        Return "Hint: invalid request — check that provider-specific fields (input_type, taskType, outputDimension, etc.) match the model's supported values."
    }
    If status = 429 {
        Return "Hint: rate limited — the gateway honors Retry-After; if persistent, increase config.retry.maxAttempts, back off caller concurrency, or ask the provider for a higher quota."
    }
    If (status >= 500) && (status < 600) {
        Return "Hint: upstream provider error — usually transient; the gateway already retried up to config.retry.maxAttempts (default 3)."
    }
    Return ""
}

/// Returns an actionable hint for transport-level failures (raised BEFORE any
/// HTTP response arrived — DNS failure, TCP refused, TLS handshake, etc.).
ClassMethod TransportHint(url As %String, errText As %String) As %String [ Internal ]
{
    If $Extract(url, 1, 8) = "https://" {
        // Most common cause on IRIS: no SSLConfiguration set on the request.
        // The %Net error text usually mentions "SSL" or "TLS" when that's it,
        // but even for generic transport errors on HTTPS, missing SSL config
        // is the highest-probability first thing to check.
        Return " Hint: HTTPS calls require an SSL configuration — set 'sslConfig' in your %Embedding.Config JSON to the name of a Security.SSLConfigs entry (create one via Management Portal → System Administration → Security → SSL/TLS Configurations, or ##class(Security.SSLConfigs).Create(""OmniHTTPS"") in %SYS)."
    }
    Return " Hint: verify network reachability (DNS, firewall, proxy) between IRIS and the URL above."
}

/// Returns 1 for statuses that must NOT be retried: any 4xx other than 429.
ClassMethod IsFastFailStatus(status As %Integer) As %Boolean
{
    Return ((status >= 400) && (status < 500) && (status '= 429))
}

/// Computes the backoff delay in milliseconds for a given attempt.
/// When retryAfter is non-empty and numeric, returns retryAfter * 1000 clamped to at least that value.
/// Otherwise returns MIN(baseDelayMs * 2^(attempt-1) + rand(baseDelayMs), maxDelayMs).
ClassMethod ComputeBackoffDelay(attempt As %Integer, retryAfter As %String, config As %DynamicObject) As %Integer
{
    Set retry = config.%Get("retry")
    Set baseDelayMs = ..RetryParam(retry, "baseDelayMs", 500)
    Set maxDelayMs = ..RetryParam(retry, "maxDelayMs", 8000)

    If (retryAfter '= "") && ($Match(retryAfter, "^[0-9]+$")) {
        Return +retryAfter * 1000
    }

    Set exp = baseDelayMs * ($ZPower(2, attempt - 1))
    Set jitter = $Random(baseDelayMs)
    Set delay = exp + jitter
    If delay > maxDelayMs { Set delay = maxDelayMs }
    Return delay
}

/// Reads a numeric retry parameter from config.retry with a default fallback.
ClassMethod RetryParam(retry As %DynamicObject, name As %String, default As %Integer) As %Integer [ Private ]
{
    If '$IsObject(retry) { Return default }
    Set v = retry.%Get(name)
    If (v = "") { Return default }
    Return +v
}

/// Resolves the API key.
/// config.apiKey is a CREDENTIAL NAME (SystemName), never the value itself.
/// Looks it up in the namespace's Ens.Config.Credentials store and returns
/// the Password (the resolved secret).
/// SECURITY (Property 15): exceptions and traces NEVER include the resolved
/// value — only the credential name. Callers MUST treat the return value as
/// secret and never log it.
/// Returns "" when config.apiKey is absent — providers that require a key
/// (all except Ollama) enforce non-empty via ValidateConfig / SetAuth.
ClassMethod ResolveApiKey(config As %DynamicObject) As %String
{
    Set name = config.%Get("apiKey")
    If name = "" { Return "" }

    // Test hook: process-private override wins over persistent store.
    // Used by unit tests to inject credentials without touching Ens.Config.Credentials.
    Set testValue = $Get(^||omniEmbeddingCredential(name))
    If testValue '= "" { Return testValue }

    If '$$$comClassDefined("Ens.Config.Credentials") {
        $$$ThrowStatus($$$ERROR($$$GeneralError, "dc.omniEmbedding.provider.Base.ResolveApiKey: credential store 'Ens.Config.Credentials' not available in this namespace; cannot resolve credential '"_name_"'"))
    }

    Set cred = ##class(Ens.Config.Credentials).%OpenId(name, , .sc)
    If '$IsObject(cred) {
        $$$ThrowStatus($$$ERROR($$$GeneralError, "dc.omniEmbedding.provider.Base.ResolveApiKey: credential '"_name_"' not found"))
    }
    Return cred.Password
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
