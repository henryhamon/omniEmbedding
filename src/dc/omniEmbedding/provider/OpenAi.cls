Include %occStatus

/// OpenAI provider — uses the OpenAI /v1/embeddings endpoint at api.openai.com.
/// Inherits payload shape and response parsing from OpenACompatible.
Class dc.omniEmbedding.provider.OpenAi Extends dc.omniEmbedding.provider.OpenACompatible
{

/// Fixed endpoint for OpenAI cloud.
ClassMethod GetEmbeddingsUrl(config As %DynamicObject) As %String
{
    Return "https://api.openai.com/v1/embeddings"
}

/// Requires modelName (from super) and apiKey.
ClassMethod ValidateConfig(config As %DynamicObject)
{
    Do ##super(config)
    If config.%Get("apiKey") = "" {
        $$$ThrowStatus($$$ERROR($$$GeneralError, "dc.omniEmbedding.provider.OpenAi.ValidateConfig: 'apiKey' is required"))
    }
}

}
