Include %occStatus

/// Google Cloud Vertex AI provider — text-embedding-004, text-embedding-005,
/// gemini-embedding-001 and related models. Distinct from the direct Gemini
/// provider (`generativelanguage.googleapis.com`) — Vertex AI is GCP's managed
/// endpoint that requires an OAuth 2.0 Bearer access token, not a query-string
/// API key, and speaks a different payload shape (`instances[]` / `parameters`).
/// 
/// Auth model: `config.apiKey` names an `Ens.Config.Credentials` entry whose
/// Password field is a valid OAuth 2.0 access token (e.g. from
/// `gcloud auth print-access-token` or a service-account JWT flow rotated
/// externally). Tokens expire in ~1 hour; refreshing them is currently out of
/// the gateway's scope — that responsibility belongs to whichever component
/// writes the credential.
Class dc.omniEmbedding.provider.VertexAi Extends dc.omniEmbedding.provider.Base
{

/// Composes the Vertex AI predict URL from region + project + modelName.
ClassMethod GetEmbeddingsUrl(config As %DynamicObject) As %String
{
    Set region = config.%Get("region")
    Set project = config.%Get("project")
    Set model = config.%Get("modelName")
    Return "https://"_region_"-aiplatform.googleapis.com/v1/projects/"_project_"/locations/"_region_"/publishers/google/models/"_model_":predict"
}

/// Authorization: Bearer <resolved access token>.
ClassMethod SetAuth(request As %Net.HttpRequest, config As %DynamicObject)
{
    Set token = ..ResolveApiKey(config)
    If token = "" {
        $$$ThrowStatus($$$ERROR($$$GeneralError, "dc.omniEmbedding.provider.VertexAi.SetAuth: 'apiKey' resolves to empty access token"))
    }
    Set request.Authorization = "Bearer "_token
}

/// Builds the Vertex AI payload: {instances:[{content, [task_type], [title]}], [parameters:{outputDimensionality, autoTruncate}]}
ClassMethod BuildPayload(input As %String, config As %DynamicObject) As %DynamicObject
{
    Set instance = {}
    Set instance.content = input

    Set taskType = config.%Get("taskType")
    If taskType '= "" {
        Set instance."task_type" = taskType
    }

    Set title = config.%Get("title")
    If title '= "" {
        Set instance.title = title
    }

    Set payload = {}
    Set payload.instances = [].%Push(instance)

    // Parameters block is only emitted when at least one parameter is present
    Set dim = config.%Get("outputDimension")
    Set autoTrunc = config.%Get("autoTruncate")
    If (dim '= "") || (autoTrunc '= "") {
        Set params = {}
        If dim '= "" {
            Set params.outputDimensionality = +dim
        }
        If autoTrunc '= "" {
            Set params.autoTruncate = ''autoTrunc
        }
        Set payload.parameters = params
    }

    Return payload
}

/// Extracts predictions[0].embeddings.values -> %Vector.
/// Throws with body content on any missing field.
ClassMethod ParseResponse(body As %DynamicObject) As %Vector
{
    Set predictions = body.%Get("predictions")
    If '$IsObject(predictions) {
        $$$ThrowStatus($$$ERROR($$$GeneralError, "dc.omniEmbedding.provider.VertexAi.ParseResponse: 'predictions' field missing. Body: "_body.%ToJSON()))
    }
    Set first = predictions.%Get(0)
    If '$IsObject(first) {
        $$$ThrowStatus($$$ERROR($$$GeneralError, "dc.omniEmbedding.provider.VertexAi.ParseResponse: 'predictions[0]' missing. Body: "_body.%ToJSON()))
    }
    Set embeddings = first.%Get("embeddings")
    If '$IsObject(embeddings) {
        $$$ThrowStatus($$$ERROR($$$GeneralError, "dc.omniEmbedding.provider.VertexAi.ParseResponse: 'predictions[0].embeddings' missing. Body: "_body.%ToJSON()))
    }
    Set values = embeddings.%Get("values")
    If '$IsObject(values) {
        $$$ThrowStatus($$$ERROR($$$GeneralError, "dc.omniEmbedding.provider.VertexAi.ParseResponse: 'predictions[0].embeddings.values' missing. Body: "_body.%ToJSON()))
    }
    Return ..BuildVector(values)
}

ClassMethod ValidateConfig(config As %DynamicObject)
{
    If config.%Get("modelName") = "" {
        $$$ThrowStatus($$$ERROR($$$GeneralError, "dc.omniEmbedding.provider.VertexAi.ValidateConfig: 'modelName' is required"))
    }
    If config.%Get("region") = "" {
        $$$ThrowStatus($$$ERROR($$$GeneralError, "dc.omniEmbedding.provider.VertexAi.ValidateConfig: 'region' is required"))
    }
    If config.%Get("project") = "" {
        $$$ThrowStatus($$$ERROR($$$GeneralError, "dc.omniEmbedding.provider.VertexAi.ValidateConfig: 'project' is required"))
    }
    If config.%Get("apiKey") = "" {
        $$$ThrowStatus($$$ERROR($$$GeneralError, "dc.omniEmbedding.provider.VertexAi.ValidateConfig: 'apiKey' (credential name holding a Vertex OAuth access token) is required"))
    }
}

}
