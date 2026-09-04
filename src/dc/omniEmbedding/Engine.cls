Include %occStatus

/// Central dispatch engine for dc.omniEmbedding.
/// Responsibilities: provider resolution, circuit breaker (stub), fallback (stub).
Class dc.omniEmbedding.Engine
{

/// Main entry point. Resolves provider, checks circuit breaker, executes embedding.
/// Throws on any unrecoverable error. Never returns empty/null vector.
ClassMethod Embed(input As %String, config As %DynamicObject) As %Vector
{
    Set providerKey = ..ProviderKey(config)

    If ..CheckBreaker(providerKey) {
        Return ..TryFallback(input, config)
    }

    Set providerClass = ..ResolveProvider(config)

    Try {
        Set vector = $ClassMethod(providerClass, "Execute", input, config)
        Do ..RecordSuccess(providerKey)
        Return vector
    } Catch ex {
        Do ..RecordFailure(providerKey)
        Set fallbacks = config.%Get("fallbacks")
        If $IsObject(fallbacks) && (fallbacks.%Size() > 0) {
            Return ..TryFallback(input, config)
        }
        Throw ex
    }
}

/// Resolves the ObjectScript class name for the provider.
/// Priority: config.provider (explicit) > inference from config.modelName prefix.
/// Throws with actionable message if provider cannot be determined.
ClassMethod ResolveProvider(config As %DynamicObject) As %String
{
    Set provider = $ZConvert(config.%Get("provider"), "L")

    If provider '= "" {
        If provider = "ollama"  { Return "dc.omniEmbedding.provider.Ollama" }
        If provider = "openai"  { Return "dc.omniEmbedding.provider.OpenAi" }
        If provider = "azure"   { Return "dc.omniEmbedding.provider.AzureOpenAi" }
        If provider = "cohere"  { Return "dc.omniEmbedding.provider.Cohere" }
        If provider = "gemini"  { Return "dc.omniEmbedding.provider.Gemini" }
        Set errMsg = "dc.omniEmbedding.Engine.ResolveProvider: unknown provider '" _ config.%Get("provider") _ "'. Valid: ollama, openai, azure, cohere, gemini"
        $$$ThrowStatus($$$ERROR($$$GeneralError, errMsg))
    }

    Set model = $ZConvert(config.%Get("modelName"), "L")

    If model = "" {
        Set errMsg = "dc.omniEmbedding.Engine.ResolveProvider: both 'provider' and 'modelName' are absent. Set 'provider' explicitly: ollama, openai, azure, cohere, gemini"
        $$$ThrowStatus($$$ERROR($$$GeneralError, errMsg))
    }

    If ($Extract(model, 1, 6) = "nomic-") || ($Extract(model, 1, 6) = "mxbai-") || ($Find(model, "llama") '= 0) {
        Return "dc.omniEmbedding.provider.Ollama"
    }
    If $Extract(model, 1, 15) = "text-embedding-" {
        Return "dc.omniEmbedding.provider.OpenAi"
    }
    If $Extract(model, 1, 6) = "embed-" {
        Return "dc.omniEmbedding.provider.Cohere"
    }
    If $Extract(model, 1, 10) = "embedding-" {
        Return "dc.omniEmbedding.provider.Gemini"
    }

    Set errMsg = "dc.omniEmbedding.Engine.ResolveProvider: cannot infer provider from modelName '" _ config.%Get("modelName") _ "'. Set config.provider explicitly."
    $$$ThrowStatus($$$ERROR($$$GeneralError, errMsg))
}

/// Generates the circuit breaker key: "provider|modelName|apiBase"
ClassMethod ProviderKey(config As %DynamicObject) As %String
{
    Return config.%Get("provider") _ "|" _ config.%Get("modelName") _ "|" _ config.%Get("apiBase")
}

/// Checks if the circuit breaker is open for the given provider key.
/// Returns 1 if open (block), 0 if closed (allow).
ClassMethod CheckBreaker(providerKey As %String) As %Boolean [ Private ]
{
    Set data = $Get(^omniEmbedding.Breaker(providerKey))
    If data = "" { Return 0 }
    Set failures = $ListGet(data, 1, 0)
    Set openedAt = $ListGet(data, 2, 0)
    If (failures >= 5) && (openedAt > 0) {
        Set nowSec = ($Piece($Horolog, ",", 1) * 86400) + $Piece($Horolog, ",", 2)
        If (nowSec - openedAt) < 60 { Return 1 }
        Kill ^omniEmbedding.Breaker(providerKey)
    }
    Return 0
}

/// Records a successful provider call: resets circuit breaker state.
ClassMethod RecordSuccess(providerKey As %String) [ Private ]
{
    Kill ^omniEmbedding.Breaker(providerKey)
}

/// Records a failed provider call: increments failure counter.
ClassMethod RecordFailure(providerKey As %String) [ Private ]
{
    Set data = $Get(^omniEmbedding.Breaker(providerKey))
    Set failures = $ListGet(data, 1, 0) + 1
    Set openedAt = $ListGet(data, 2, 0)
    If (failures >= 5) && (openedAt = 0) {
        Set openedAt = ($Piece($Horolog, ",", 1) * 86400) + $Piece($Horolog, ",", 2)
    }
    Set ^omniEmbedding.Breaker(providerKey) = $ListBuild(failures, openedAt)
}

/// Attempts fallback providers from config.fallbacks.
/// STUB — Phase 6 implements full vector-space invariance check.
ClassMethod TryFallback(input As %String, config As %DynamicObject) As %Vector [ Private ]
{
    Set errMsg = "dc.omniEmbedding.Engine.TryFallback: not yet implemented (Phase 6). Provider: " _ config.%Get("provider")
    $$$ThrowStatus($$$ERROR($$$GeneralError, errMsg))
}

}
