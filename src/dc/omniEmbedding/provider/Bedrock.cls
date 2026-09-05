Include %occStatus

/// AWS Bedrock provider — hosts embedding models under two payload families:
///   - amazon.titan-embed-*  : payload {inputText, dimensions, normalize}, response .embedding
///   - cohere.embed-*        : payload {texts:[...], input_type}, response .embeddings[0]
/// 
/// URL is composed per region + modelId. Authentication is AWS SigV4 (delegated
/// to dc.omniEmbedding.util.SigV4), so this provider extends Base directly (NOT
/// OpenACompatible — the payload and response shapes are unrelated to OpenAI).
/// 
/// Credential (resolved from Ens.Config.Credentials by name in config.apiKey)
/// carries BOTH accessKeyId and secretAccessKey, encoded as either:
///   - "accessKeyId:secretAccessKey"      (colon-separated), OR
///   - JSON: {"accessKeyId":"...", "secretAccessKey":"..."}
/// A temporary session token (STS/AssumeRole) can be supplied by naming a
/// separate credential in `config.sessionTokenCredential`; its resolved value
/// is the session token itself.
Class dc.omniEmbedding.provider.Bedrock Extends dc.omniEmbedding.provider.Base
{

Parameter SERVICE = "bedrock";

ClassMethod GetEmbeddingsUrl(config As %DynamicObject) As %String
{
    Set region = config.%Get("region")
    Set modelId = config.%Get("modelName")
    Return "https://bedrock-runtime."_region_".amazonaws.com/model/"_modelId_"/invoke"
}

/// Signs the request with SigV4 using credentials resolved via ResolveApiKey.
/// SetAuth is called AFTER BuildPayload writes to request.EntityBody, but the
/// signature depends on the payload — so we read the body back here to compute
/// the SHA-256. Base.Execute's Template Method already writes the payload
/// before calling SetAuth is NOT true — actually SetAuth runs FIRST in the
/// template. We work around this by re-signing the payload contents lazily
/// through util.SigV4 which recomputes the hash from `payload` we pass in.
/// 
/// Because of the ordering constraint, Bedrock overrides Execute() to move
/// SetAuth AFTER BuildPayload/SetBody — see below.
ClassMethod SetAuth(request As %Net.HttpRequest, config As %DynamicObject)
{
    // Intentionally empty here — real signing happens in Execute() below
    // once the payload is written to the request.
}

/// Executes the Bedrock request with SigV4 signing applied AFTER the payload
/// is built (SigV4 must sign the actual body bytes). This is the only provider
/// that overrides Base.Execute — all others MUST use the base Template Method.
ClassMethod Execute(input As %String, config As %DynamicObject) As %Vector
{
    Do ..ValidateConfig(config)

    Set request = ##class(%Net.HttpRequest).%New()
    Set request.ContentType = "application/json"
    Set timeout = config.%Get("httpTimeout")
    Set request.Timeout = $Select(+timeout > 0: +timeout, 1: 30)
    Set sslConfig = config.%Get("sslConfig")
    If sslConfig '= "" {
        Set request.SSLConfiguration = sslConfig
    }

    Set url = ..GetEmbeddingsUrl(config)
    Set payload = ..BuildPayload(input, config)
    Set payloadJson = payload.%ToJSON()
    Do request.EntityBody.Write(payloadJson)

    // Sign AFTER the payload is on the wire — SigV4 hashes the body.
    Do ..SignBedrockRequest(request, url, payloadJson, config)

    Set response = ..RetryWithBackoff(request, url, config)

    Set body = {}.%FromJSON(response.Data)
    Return ..ParseResponse(body, config)
}

/// Resolves credentials and calls util.SigV4 to attach the signature headers.
ClassMethod SignBedrockRequest(request As %Net.HttpRequest, url As %String, payload As %String, config As %DynamicObject) [ Private ]
{
    Set region = config.%Get("region")
    Set combined = ..ResolveApiKey(config)
    Set access = ..ParseAwsCredential(combined, "accessKeyId")
    Set secret = ..ParseAwsCredential(combined, "secretAccessKey")

    // Optional session token via a second named credential
    Set sessionToken = ""
    Set stName = config.%Get("sessionTokenCredential")
    If stName '= "" {
        // Reuse the same resolver by swapping apiKey temporarily
        Set stCfg = {}
        Set stCfg.apiKey = stName
        Set sessionToken = ..ResolveApiKey(stCfg)
    }

    Do ##class(dc.omniEmbedding.util.SigV4).Sign(request, "POST", url, region, ..#SERVICE, access, secret, sessionToken, payload)
}

/// Parses the Bedrock credential value into its component field.
/// Accepts two formats:
///   - "accessKeyId:secretAccessKey"
///   - JSON: {"accessKeyId":"...","secretAccessKey":"..."}
/// Never echoes the values in exceptions.
ClassMethod ParseAwsCredential(raw As %String, field As %String) As %String [ Internal ]
{
    // JSON form
    If $Extract(raw, 1) = "{" {
        Set obj = ""
        Try { Set obj = {}.%FromJSON(raw) } Catch {}
        If '$IsObject(obj) {
            $$$ThrowStatus($$$ERROR($$$GeneralError, "dc.omniEmbedding.provider.Bedrock.ParseAwsCredential: credential value is not valid JSON"))
        }
        Set val = obj.%Get(field)
        If val = "" {
            $$$ThrowStatus($$$ERROR($$$GeneralError, "dc.omniEmbedding.provider.Bedrock.ParseAwsCredential: credential JSON is missing '"_field_"'"))
        }
        Return val
    }
    // Colon form
    If $Length(raw, ":") '= 2 {
        $$$ThrowStatus($$$ERROR($$$GeneralError, "dc.omniEmbedding.provider.Bedrock.ParseAwsCredential: credential must be 'accessKeyId:secretAccessKey' or JSON object"))
    }
    If field = "accessKeyId" { Return $Piece(raw, ":", 1) }
    Return $Piece(raw, ":", 2)
}

/// Builds the payload by dispatching on the modelName family.
ClassMethod BuildPayload(input As %String, config As %DynamicObject) As %DynamicObject
{
    Set family = ..DetectFamily(config.%Get("modelName"))
    If family = "titan" {
        Set p = {}
        Set p.inputText = input
        Set dim = config.%Get("dimensions")
        If dim '= "" { Set p.dimensions = +dim }
        Set p.normalize = 1
        Return p
    }
    If family = "cohere" {
        Set p = {}
        Set inputType = config.%Get("inputType")
        If inputType = "" { Set inputType = "search_document" }
        Set p.texts = [].%Push(input)
        Set p."input_type" = inputType
        Return p
    }
    // Unreachable — DetectFamily throws for unknown families
    $$$ThrowStatus($$$ERROR($$$GeneralError, "dc.omniEmbedding.provider.Bedrock.BuildPayload: unreachable"))
}

/// Parses the response body by dispatching on the modelName family.
ClassMethod ParseResponse(body As %DynamicObject, config As %DynamicObject = "") As %Vector
{
    // ParseResponse is normally called with (body) only from Base.Execute — but
    // Bedrock overrides Execute() and passes config as a second argument, so
    // we can re-derive the family without process-private state.
    If '$IsObject(config) {
        $$$ThrowStatus($$$ERROR($$$GeneralError, "dc.omniEmbedding.provider.Bedrock.ParseResponse: config is required (call via Execute)"))
    }
    Set family = ..DetectFamily(config.%Get("modelName"))
    If family = "titan" {
        Set arr = body.%Get("embedding")
        If '$IsObject(arr) {
            $$$ThrowStatus($$$ERROR($$$GeneralError, "dc.omniEmbedding.provider.Bedrock.ParseResponse (titan): 'embedding' missing. Body: "_body.%ToJSON()))
        }
        Return ..BuildVector(arr)
    }
    If family = "cohere" {
        Set outer = body.%Get("embeddings")
        If '$IsObject(outer) {
            $$$ThrowStatus($$$ERROR($$$GeneralError, "dc.omniEmbedding.provider.Bedrock.ParseResponse (cohere): 'embeddings' missing. Body: "_body.%ToJSON()))
        }
        Set first = outer.%Get(0)
        If '$IsObject(first) {
            $$$ThrowStatus($$$ERROR($$$GeneralError, "dc.omniEmbedding.provider.Bedrock.ParseResponse (cohere): 'embeddings[0]' missing. Body: "_body.%ToJSON()))
        }
        Return ..BuildVector(first)
    }
    $$$ThrowStatus($$$ERROR($$$GeneralError, "dc.omniEmbedding.provider.Bedrock.ParseResponse: unreachable"))
}

/// Detects the payload family from the Bedrock modelId.
/// Returns "titan" or "cohere". Throws for anything else.
ClassMethod DetectFamily(modelId As %String) As %String [ Internal ]
{
    If $Extract(modelId, 1, 18) = "amazon.titan-embed" { Return "titan" }
    If $Extract(modelId, 1, 13) = "cohere.embed-" { Return "cohere" }
    $$$ThrowStatus($$$ERROR($$$GeneralError, "dc.omniEmbedding.provider.Bedrock.DetectFamily: unsupported modelId '"_modelId_"'. Supported families: amazon.titan-embed-*, cohere.embed-*"))
}

ClassMethod ValidateConfig(config As %DynamicObject)
{
    If config.%Get("modelName") = "" {
        $$$ThrowStatus($$$ERROR($$$GeneralError, "dc.omniEmbedding.provider.Bedrock.ValidateConfig: 'modelName' is required"))
    }
    If config.%Get("region") = "" {
        $$$ThrowStatus($$$ERROR($$$GeneralError, "dc.omniEmbedding.provider.Bedrock.ValidateConfig: 'region' is required"))
    }
    If config.%Get("apiKey") = "" {
        $$$ThrowStatus($$$ERROR($$$GeneralError, "dc.omniEmbedding.provider.Bedrock.ValidateConfig: 'apiKey' (credential name) is required"))
    }
    // Family check — surfaces early instead of at BuildPayload time
    Do ..DetectFamily(config.%Get("modelName"))
}

}
