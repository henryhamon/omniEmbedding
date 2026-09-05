Include %occStatus

/// Jina AI provider — jina-embeddings-v3 and related models at api.jina.ai.
/// Response is OpenAI-shaped (data[0].embedding) — inherited from OpenACompatible.
/// Payload differs on one important point (Property 17): Jina ALWAYS requires
/// `input` as an array, even for a single text. BuildPayload is overridden
/// (not super-delegated) to enforce that.
/// Optional passthroughs (camelCase in config → snake_case at the wire):
///   - task: retrieval.query | retrieval.passage | text-matching | classification | separation
///   - dimensions (config.outputDimension): server-side truncation
///   - late_chunking (config.lateChunking): boolean, for long-doc coherent chunks
///   - embedding_type (config.outputDtype): float | base64 | binary | ubinary
Class dc.omniEmbedding.provider.Jina Extends dc.omniEmbedding.provider.OpenACompatible
{

/// Fixed endpoint for Jina cloud.
ClassMethod GetEmbeddingsUrl(config As %DynamicObject) As %String
{
    Return "https://api.jina.ai/v1/embeddings"
}

/// Requires modelName (from super) and apiKey.
ClassMethod ValidateConfig(config As %DynamicObject)
{
    Do ##super(config)
    If config.%Get("apiKey") = "" {
        $$$ThrowStatus($$$ERROR($$$GeneralError, "dc.omniEmbedding.provider.Jina.ValidateConfig: 'apiKey' is required"))
    }
}

/// Property 17: Jina requires `input` as an array, so we do NOT delegate to
/// the OpenACompatible super — we build the payload from scratch and wrap the
/// single input string in a one-element array.
ClassMethod BuildPayload(input As %String, config As %DynamicObject) As %DynamicObject
{
    Set payload = {}
    Set payload.input = [].%Push(input)
    Set payload.model = config.%Get("modelName")

    Set task = config.%Get("task")
    If task '= "" {
        Set payload.task = task
    }

    Set dim = config.%Get("outputDimension")
    If dim '= "" {
        Set payload.dimensions = +dim
    }

    Set lateChunking = config.%Get("lateChunking")
    If lateChunking '= "" {
        Set payload."late_chunking" = ''lateChunking
    }

    Set dtype = config.%Get("outputDtype")
    If dtype '= "" {
        Set payload."embedding_type" = dtype
    }

    Return payload
}

}
