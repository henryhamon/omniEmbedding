Include %occStatus

/// Mistral provider — OpenAI-shaped payload + response, hosted at api.mistral.ai.
/// Covers both text embeddings (mistral-embed, 1024d) and code embeddings
/// (codestral-embed, default 1536d, up to 3072d).
/// Mistral extends the OpenAI-compatible payload with two optional fields:
///   - output_dimension: truncate to a specific dimension (codestral supports this)
///   - output_dtype: "float" | "int8" | "uint8" | "binary" | "ubinary"
/// Both are forwarded only when set on the config.
Class dc.omniEmbedding.provider.Mistral Extends dc.omniEmbedding.provider.OpenACompatible
{

/// Fixed endpoint for Mistral cloud.
ClassMethod GetEmbeddingsUrl(config As %DynamicObject) As %String
{
    Return "https://api.mistral.ai/v1/embeddings"
}

/// Requires modelName (from super) and apiKey.
ClassMethod ValidateConfig(config As %DynamicObject)
{
    Do ##super(config)
    If config.%Get("apiKey") = "" {
        $$$ThrowStatus($$$ERROR($$$GeneralError, "dc.omniEmbedding.provider.Mistral.ValidateConfig: 'apiKey' is required"))
    }
}

/// Extends the OpenAI-shape payload with Mistral's optional output_dimension
/// and output_dtype. Only forwarded when present in the config so the request
/// stays minimal and API-compatible when the caller does not care.
ClassMethod BuildPayload(input As %String, config As %DynamicObject) As %DynamicObject
{
    Set payload = ##super(input, config)

    Set dim = config.%Get("outputDimension")
    If dim '= "" {
        Set payload."output_dimension" = +dim
    }

    Set dtype = config.%Get("outputDtype")
    If dtype '= "" {
        Set payload."output_dtype" = dtype
    }

    Return payload
}

}
