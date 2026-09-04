Include %occStatus

/// Ollama provider — uses the OpenAI-compatible /v1/embeddings endpoint.
/// No authentication required. Default base URL: http://localhost:11434
/// Ref: ADR-003 (OpenACompatible family), ADR-004 (no apiKey requirement).
Class dc.omniEmbedding.provider.Ollama Extends dc.omniEmbedding.provider.OpenACompatible
{

/// Returns the Ollama embeddings endpoint URL.
/// Removes trailing slashes from apiBase; defaults to http://localhost:11434 if absent.
/// Property 7: for any apiBase (with or without trailing slash), returns URL without duplicate slashes.
ClassMethod GetEmbeddingsUrl(config As %DynamicObject) As %String
{
    Set base = config.%Get("apiBase")
    If base = "" {
        Set base = "http://localhost:11434"
    }
    // Strip trailing slashes
    While ($Extract(base, $Length(base)) = "/") {
        Set base = $Extract(base, 1, $Length(base) - 1)
    }
    Return base _ "/v1/embeddings"
}

/// No-op: Ollama does not require authentication.
/// Property 6: Execute() completes without Authorization header.
ClassMethod SetAuth(request As %Net.HttpRequest, config As %DynamicObject)
{
    // Intentionally empty — Ollama requires no auth
}

/// Validates Ollama config. Requires only modelName; apiKey is optional.
/// Property 6: ValidateConfig does NOT throw for absent apiKey.
ClassMethod ValidateConfig(config As %DynamicObject)
{
    Do ##super(config)
    // apiKey deliberately NOT checked — Ollama is keyless
}

}
