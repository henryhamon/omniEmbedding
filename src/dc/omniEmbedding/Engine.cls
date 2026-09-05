Include %occStatus

/// Central dispatch engine for dc.omniEmbedding.
/// Responsibilities: provider resolution, circuit breaker, fallback with
/// vector-space invariance.
Class dc.omniEmbedding.Engine
{

/// Main entry point. Resolves provider, checks circuit breaker, executes embedding.
/// On failure and when config.fallbacks is present, delegates to TryFallback
/// under a strict vector-space invariance (same modelName AND dimensions).
/// Throws on any unrecoverable error. Never returns empty/null vector.
ClassMethod Embed(input As %String, config As %DynamicObject) As %Vector
{
    Set providerKey = ..ProviderKey(config)

    If ..CheckBreaker(providerKey) {
        Return ..TryFallback(input, config, "circuit breaker open for '"_providerKey_"'")
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
            Return ..TryFallback(input, config, ex.DisplayString())
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
        If provider = "mistral" { Return "dc.omniEmbedding.provider.Mistral" }
        If provider = "voyage"  { Return "dc.omniEmbedding.provider.Voyage" }
        If provider = "jina"    { Return "dc.omniEmbedding.provider.Jina" }
        Set errMsg = "dc.omniEmbedding.Engine.ResolveProvider: unknown provider '" _ config.%Get("provider") _ "'. Valid: ollama, openai, azure, cohere, gemini, mistral, voyage, jina"
        $$$ThrowStatus($$$ERROR($$$GeneralError, errMsg))
    }

    Set model = $ZConvert(config.%Get("modelName"), "L")

    If model = "" {
        Set errMsg = "dc.omniEmbedding.Engine.ResolveProvider: both 'provider' and 'modelName' are absent. Set 'provider' explicitly: ollama, openai, azure, cohere, gemini, mistral, voyage, jina"
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
    // Mistral prefixes cover both text (mistral-embed) and code (codestral-embed).
    If ($Extract(model, 1, 8) = "mistral-") || ($Extract(model, 1, 10) = "codestral-") {
        Return "dc.omniEmbedding.provider.Mistral"
    }
    // Voyage prefixes cover text (voyage-3), code (voyage-code-3) and domain models.
    If $Extract(model, 1, 7) = "voyage-" {
        Return "dc.omniEmbedding.provider.Voyage"
    }
    // Jina prefixes cover jina-embeddings-* and other jina-* embed variants.
    If $Extract(model, 1, 5) = "jina-" {
        Return "dc.omniEmbedding.provider.Jina"
    }

    Set errMsg = "dc.omniEmbedding.Engine.ResolveProvider: cannot infer provider from modelName '" _ config.%Get("modelName") _ "'. Set config.provider explicitly."
    $$$ThrowStatus($$$ERROR($$$GeneralError, errMsg))
}

/// Generates the circuit breaker key: "provider|modelName|apiBase"
ClassMethod ProviderKey(config As %DynamicObject) As %String
{
    Return config.%Get("provider") _ "|" _ config.%Get("modelName") _ "|" _ config.%Get("apiBase")
}

Parameter FAILURETHRESHOLD = 5;

Parameter COOLDOWNSECONDS = 60;

/// Checks if the circuit breaker is open for the given provider key.
/// Returns 1 if open (block), 0 if closed OR half-open (allow one attempt).
ClassMethod CheckBreaker(providerKey As %String) As %Boolean [ Internal ]
{
    Set data = $Get(^omniEmbedding.Breaker(providerKey))
    If data = "" { Return 0 }
    Set failures = $ListGet(data, 1, 0)
    Set openedAt = $ListGet(data, 2, 0)
    If (failures < ..#FAILURETHRESHOLD) || (openedAt = 0) { Return 0 }
    Set nowSec = ..NowSeconds()
    If (nowSec - openedAt) >= ..#COOLDOWNSECONDS { Return 0 }
    Return 1
}

/// Records a successful provider call: resets circuit breaker to (0, 0).
/// Property 14: global explicitly becomes $LISTBUILD(0, 0) after success.
ClassMethod RecordSuccess(providerKey As %String) [ Internal ]
{
    Set ^omniEmbedding.Breaker(providerKey) = $ListBuild(0, 0)
}

/// Records a failed provider call: increments failure counter, opens circuit
/// once the failure threshold is reached.
ClassMethod RecordFailure(providerKey As %String) [ Internal ]
{
    Set data = $Get(^omniEmbedding.Breaker(providerKey))
    Set failures = $ListGet(data, 1, 0) + 1
    Set openedAt = $ListGet(data, 2, 0)
    If (failures >= ..#FAILURETHRESHOLD) && (openedAt = 0) {
        Set openedAt = ..NowSeconds()
    }
    Set ^omniEmbedding.Breaker(providerKey) = $ListBuild(failures, openedAt)
}

/// Wall-clock seconds since epoch (from $Horolog). Extracted so tests can
/// verify the cooldown math without waiting 60 real seconds.
ClassMethod NowSeconds() As %Integer [ Internal ]
{
    Return ($Piece($Horolog, ",", 1) * 86400) + $Piece($Horolog, ",", 2)
}

/// Attempts fallback configs from config.fallbacks in order.
/// Enforces the vector-space invariant BEFORE any HTTP call: a fallback with
/// a different modelName or different dimensions is rejected with a fatal
/// exception (never mix vectors from different spaces).
/// If config.fallbacks is absent/empty, throws with the primary failure reason.
/// If every compatible fallback fails, throws listing every attempt.
ClassMethod TryFallback(input As %String, config As %DynamicObject, primaryFailureReason As %String = "") As %Vector [ Internal ]
{
    Set fallbacks = config.%Get("fallbacks")
    If '$IsObject(fallbacks) || (fallbacks.%Size() = 0) {
        $$$ThrowStatus($$$ERROR($$$GeneralError, "dc.omniEmbedding.Engine.TryFallback: no fallbacks configured. Primary failure: "_primaryFailureReason))
    }

    Set attempts = ""
    Set iter = fallbacks.%GetIterator()
    While iter.%GetNext(.k, .fbName) {
        Set fbConfig = ..LoadFallbackConfig(fbName)

        // Vector-space invariance is fatal — never fall through, never HTTP.
        Do ..AssertVectorSpaceCompatible(config, fbConfig, fbName)

        Set attempts = attempts _ $Select(attempts = "": "", 1: ", ") _ fbName
        Try {
            Return ..Embed(input, fbConfig)
        } Catch fbEx {
            // Compatible but failed — try the next one
        }
    }

    $$$ThrowStatus($$$ERROR($$$GeneralError, "dc.omniEmbedding.Engine.TryFallback: all fallbacks exhausted. Primary: "_primaryFailureReason_". Attempted: "_attempts))
}

/// Rejects any fallback whose vector space (modelName + dimensions) differs
/// from the primary. Throws before any HTTP call — Property 4.
ClassMethod AssertVectorSpaceCompatible(primary As %DynamicObject, fallback As %DynamicObject, fallbackName As %String) [ Internal ]
{
    Set pModel = primary.%Get("modelName")
    Set pDims = primary.%Get("dimensions")
    Set fModel = fallback.%Get("modelName")
    Set fDims = fallback.%Get("dimensions")
    If (pModel = fModel) && (+pDims = +fDims) { Return }

    Set errMsg = "dc.omniEmbedding.Engine.TryFallback: vector-space mismatch on fallback '"_fallbackName_"'. Primary=(modelName='"_pModel_"', dimensions="_pDims_"); Fallback=(modelName='"_fModel_"', dimensions="_fDims_"). Fallbacks MUST share the primary's vector space."
    $$$ThrowStatus($$$ERROR($$$GeneralError, errMsg))
}

/// Loads a named %Embedding.Config and returns its Configuration JSON parsed.
/// Overridable via subclass in tests that need to inject configs without
/// touching persistent storage.
ClassMethod LoadFallbackConfig(name As %String) As %DynamicObject [ Internal ]
{
    Set cfg = ##class(%Embedding.Config).%OpenId(name)
    If '$IsObject(cfg) {
        $$$ThrowStatus($$$ERROR($$$GeneralError, "dc.omniEmbedding.Engine.LoadFallbackConfig: %Embedding.Config '"_name_"' not found"))
    }
    Return {}.%FromJSON(cfg.Configuration)
}

}
