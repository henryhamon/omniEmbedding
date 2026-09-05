Include %occStatus

/// Voyage AI provider — OpenAI-shaped payload + response, hosted at api.voyageai.com.
/// Covers text (voyage-3, voyage-3-large), code (voyage-code-3), and domain-tuned
/// models (voyage-finance-2, voyage-law-2, voyage-multilingual-2).
/// Voyage extends the OpenAI-compatible payload with four optional fields:
///   - input_type: "query" | "document" (drives retrieval-side vs corpus-side embedding)
///   - truncation: boolean — server-side truncation to model max
///   - output_dimension: integer — truncate vector server-side
///   - output_dtype: "float" | "int8" | "uint8" | "binary" | "ubinary"
/// All forwarded only when set on the config.
Class dc.omniEmbedding.provider.Voyage Extends dc.omniEmbedding.provider.OpenACompatible
{

/// Fixed endpoint for Voyage cloud.
ClassMethod GetEmbeddingsUrl(config As %DynamicObject) As %String
{
    Return "https://api.voyageai.com/v1/embeddings"
}

/// Requires modelName (from super) and apiKey. When inputType is present, it MUST
/// be exactly "query" or "document" — any other value is rejected before any HTTP call.
ClassMethod ValidateConfig(config As %DynamicObject)
{
    Do ##super(config)
    If config.%Get("apiKey") = "" {
        $$$ThrowStatus($$$ERROR($$$GeneralError, "dc.omniEmbedding.provider.Voyage.ValidateConfig: 'apiKey' is required"))
    }
    Set inputType = config.%Get("inputType")
    If (inputType '= "") && (inputType '= "query") && (inputType '= "document") {
        $$$ThrowStatus($$$ERROR($$$GeneralError, "dc.omniEmbedding.provider.Voyage.ValidateConfig: 'inputType' must be 'query' or 'document', got: "_inputType))
    }
}

/// Extends the OpenAI-shape payload with Voyage's four optional passthroughs.
/// Only forwarded when present in the config.
ClassMethod BuildPayload(input As %String, config As %DynamicObject) As %DynamicObject
{
    Set payload = ##super(input, config)

    Set inputType = config.%Get("inputType")
    If inputType '= "" {
        Set payload."input_type" = inputType
    }

    Set truncation = config.%Get("truncation")
    If truncation '= "" {
        Set payload.truncation = ''truncation
    }

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
