Include %occStatus

/// Azure OpenAI provider — composes deployment-scoped URLs and uses the
/// `api-key` header instead of `Authorization: Bearer`.
/// Inherits payload shape and response parsing from OpenACompatible.
Class dc.omniEmbedding.provider.AzureOpenAi Extends dc.omniEmbedding.provider.OpenACompatible
{

/// Composes the Azure embeddings URL from apiBase / deployment / apiVersion.
/// Property 8: exactly one `/openai/deployments/` segment and one `?api-version=` query
/// regardless of whether apiBase is a root or already the full deployment URL,
/// and independent of trailing slashes on apiBase.
ClassMethod GetEmbeddingsUrl(config As %DynamicObject) As %String
{
    Set base = ..StripTrailingSlashes(config.%Get("apiBase"))
    Set apiVersion = config.%Get("apiVersion")

    If $Find(base, "/openai/deployments/") > 0 {
        If $Find(base, "?api-version=") > 0 { Return base }
        Set sep = $Select($Find(base, "?") > 0: "&", 1: "?")
        Return base_sep_"api-version="_apiVersion
    }

    Set deployment = config.%Get("deployment")
    Return base_"/openai/deployments/"_deployment_"/embeddings?api-version="_apiVersion
}

/// Azure uses the `api-key` header, NOT `Authorization: Bearer`.
ClassMethod SetAuth(request As %Net.HttpRequest, config As %DynamicObject)
{
    Set key = ..ResolveApiKey(config)
    If key = "" {
        $$$ThrowStatus($$$ERROR($$$GeneralError, "dc.omniEmbedding.provider.AzureOpenAi.SetAuth: 'apiKey' resolves to empty value"))
    }
    Do request.SetHeader("api-key", key)
}

/// Requires modelName (super), apiBase, apiVersion, apiKey.
/// `deployment` is required only when apiBase does not already contain the
/// full `/openai/deployments/<name>` path.
ClassMethod ValidateConfig(config As %DynamicObject)
{
    Do ##super(config)
    Set base = config.%Get("apiBase")
    If base = "" {
        $$$ThrowStatus($$$ERROR($$$GeneralError, "dc.omniEmbedding.provider.AzureOpenAi.ValidateConfig: 'apiBase' is required"))
    }
    If config.%Get("apiVersion") = "" {
        $$$ThrowStatus($$$ERROR($$$GeneralError, "dc.omniEmbedding.provider.AzureOpenAi.ValidateConfig: 'apiVersion' is required"))
    }
    If ($Find(base, "/openai/deployments/") = 0) && (config.%Get("deployment") = "") {
        $$$ThrowStatus($$$ERROR($$$GeneralError, "dc.omniEmbedding.provider.AzureOpenAi.ValidateConfig: 'deployment' is required when apiBase is a root URL"))
    }
    If config.%Get("apiKey") = "" {
        $$$ThrowStatus($$$ERROR($$$GeneralError, "dc.omniEmbedding.provider.AzureOpenAi.ValidateConfig: 'apiKey' is required"))
    }
}

ClassMethod StripTrailingSlashes(url As %String) As %String [ Private ]
{
    While ($Length(url) > 0) && ($Extract(url, $Length(url)) = "/") {
        Set url = $Extract(url, 1, $Length(url) - 1)
    }
    Return url
}

}
