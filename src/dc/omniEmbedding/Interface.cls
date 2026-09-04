Include %occStatus

/// Bridge class: adapts %Embedding.Interface to the omniEmbedding engine.
/// Aligned with IRIS 2026 contract:
///   - Embedding(input, configuration As %String) — configuration is raw JSON string
///   - IsValidConfig(config As %DynamicObject, ByRef errorMsg) — config is already parsed by %Embedding.Config trigger
Class dc.omniEmbedding.Interface Extends %Embedding.Interface
{

/// Returns a %Vector for the given input text.
/// configuration is a raw JSON string (as stored in %Embedding.Config.Configuration).
/// Throws on any error. Never returns an empty/null vector.
ClassMethod Embedding(input As %String, configuration As %String) As %Vector
{
    If input = "" {
        $$$ThrowStatus($$$ERROR($$$GeneralError, "dc.omniEmbedding.Interface.Embedding: input cannot be empty"))
    }

    Set config = ..ParseConfig(configuration)

    Set dims = config.%Get("dimensions")
    If (dims = "") || (+dims <= 0) {
        Set errMsg = "dc.omniEmbedding.Interface.Embedding: 'dimensions' must be a positive integer, got: " _ dims
        $$$ThrowStatus($$$ERROR($$$GeneralError, errMsg))
    }

    Return ##class(dc.omniEmbedding.Engine).Embed(input, config)
}

/// Validates the configuration without making any HTTP call.
/// config is a %DynamicObject (already parsed by the %Embedding.Config INSERT/UPDATE trigger).
/// Returns 1 if valid, 0 + errorMsg if invalid.
ClassMethod IsValidConfig(config As %DynamicObject, ByRef errorMsg As %String) As %Boolean
{
    Set errorMsg = ""
    Try {
        Set providerClass = ##class(dc.omniEmbedding.Engine).ResolveProvider(config)
        Do $ClassMethod(providerClass, "ValidateConfig", config)
        Return 1
    } Catch ex {
        Set errorMsg = ex.DisplayString()
        Return 0
    }
}

/// Estimates token count for the given text.
/// Falls back to conservative floor estimate (bytes/4 + 1) if no config or provider unavailable.
ClassMethod EstimateTokenCount(input As %String, configuration As %String = "") As %Integer
{
    If configuration = "" {
        Return ($Length(input) \ 4) + 1
    }
    Try {
        Set config = ..ParseConfig(configuration)
        Set providerClass = ##class(dc.omniEmbedding.Engine).ResolveProvider(config)
        Return $ClassMethod(providerClass, "EstimateTokenCount", input, config)
    } Catch {
        Return ($Length(input) \ 4) + 1
    }
}

/// Parses a JSON string into a %DynamicObject.
/// Throws with a clear message if the JSON is malformed.
ClassMethod ParseConfig(json As %String) As %DynamicObject [ Private ]
{
    Try {
        Set config = {}.%FromJSON(json)
        Return config
    } Catch ex {
        Set errMsg = "dc.omniEmbedding.Interface.ParseConfig: JSON parse error: " _ ex.DisplayString()
        $$$ThrowStatus($$$ERROR($$$GeneralError, errMsg))
    }
}

}
