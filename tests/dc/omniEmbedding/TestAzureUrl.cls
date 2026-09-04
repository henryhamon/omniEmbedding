Include (%occStatus, %outUnitTest)

/// Unit tests for dc.omniEmbedding.provider.AzureOpenAi.
/// Covers Property 8 (URL composition: exactly one /openai/deployments/ segment
/// and one ?api-version, regardless of apiBase shape or trailing slashes)
/// and ValidateConfig / SetAuth contract.
Class dc.omniEmbedding.tests.TestAzureUrl Extends %UnitTest.TestCase
{

// --- Property 8: URL composition ---

Method TestUrlFromRootBase()
{
    Set config = ##class(%DynamicObject).%FromJSON("{""modelName"":""m"",""apiBase"":""https://foo.openai.azure.com"",""deployment"":""ada"",""apiVersion"":""2024-02-01""}")
    Set url = ##class(dc.omniEmbedding.provider.AzureOpenAi).GetEmbeddingsUrl(config)
    Do $$$AssertEquals(url, "https://foo.openai.azure.com/openai/deployments/ada/embeddings?api-version=2024-02-01", "root base composes canonical url")
}

Method TestUrlFromRootBaseTrailingSlash()
{
    Set config = ##class(%DynamicObject).%FromJSON("{""modelName"":""m"",""apiBase"":""https://foo.openai.azure.com/"",""deployment"":""ada"",""apiVersion"":""2024-02-01""}")
    Set url = ##class(dc.omniEmbedding.provider.AzureOpenAi).GetEmbeddingsUrl(config)
    Do $$$AssertEquals(url, "https://foo.openai.azure.com/openai/deployments/ada/embeddings?api-version=2024-02-01", "trailing slash stripped from root base")
}

Method TestUrlFromRootBaseMultipleSlashes()
{
    Set config = ##class(%DynamicObject).%FromJSON("{""modelName"":""m"",""apiBase"":""https://foo.openai.azure.com///"",""deployment"":""ada"",""apiVersion"":""2024-02-01""}")
    Set url = ##class(dc.omniEmbedding.provider.AzureOpenAi).GetEmbeddingsUrl(config)
    Do $$$AssertEquals(url, "https://foo.openai.azure.com/openai/deployments/ada/embeddings?api-version=2024-02-01", "multiple trailing slashes stripped")
}

Method TestUrlFromFullBase()
{
    Set config = ##class(%DynamicObject).%FromJSON("{""modelName"":""m"",""apiBase"":""https://foo.openai.azure.com/openai/deployments/ada/embeddings"",""apiVersion"":""2024-02-01""}")
    Set url = ##class(dc.omniEmbedding.provider.AzureOpenAi).GetEmbeddingsUrl(config)
    Do $$$AssertEquals(url, "https://foo.openai.azure.com/openai/deployments/ada/embeddings?api-version=2024-02-01", "full deployment url used directly")
}

Method TestUrlFromFullBaseWithApiVersion()
{
    Set config = ##class(%DynamicObject).%FromJSON("{""modelName"":""m"",""apiBase"":""https://foo.openai.azure.com/openai/deployments/ada/embeddings?api-version=2024-02-01"",""apiVersion"":""2024-02-01""}")
    Set url = ##class(dc.omniEmbedding.provider.AzureOpenAi).GetEmbeddingsUrl(config)
    Do $$$AssertEquals(url, "https://foo.openai.azure.com/openai/deployments/ada/embeddings?api-version=2024-02-01", "no duplicate api-version when already present")
}

Method TestUrlHasExactlyOneDeploymentsSegment()
{
    Set config = ##class(%DynamicObject).%FromJSON("{""modelName"":""m"",""apiBase"":""https://foo.openai.azure.com/"",""deployment"":""ada"",""apiVersion"":""2024-02-01""}")
    Set url = ##class(dc.omniEmbedding.provider.AzureOpenAi).GetEmbeddingsUrl(config)
    Do $$$AssertEquals($Length(url, "/openai/deployments/"), 2, "exactly one /openai/deployments/ segment")
    Do $$$AssertEquals($Length(url, "?api-version="), 2, "exactly one ?api-version= query")
}

// --- SetAuth uses api-key header, not Authorization ---

Method TestSetAuthUsesApiKeyHeader()
{
    Set request = ##class(%Net.HttpRequest).%New()
    Set config = ##class(%DynamicObject).%FromJSON("{""modelName"":""m"",""apiKey"":""secret-value""}")
    Do ##class(dc.omniEmbedding.provider.AzureOpenAi).SetAuth(request, config)
    Do $$$AssertEquals(request.GetHeader("api-key"), "secret-value", "api-key header set")
    Do $$$AssertEquals(request.Authorization, "", "Authorization header NOT set")
}

Method TestSetAuthRejectsEmptyKey()
{
    Set request = ##class(%Net.HttpRequest).%New()
    Set config = ##class(%DynamicObject).%FromJSON("{""modelName"":""m""}")
    Set threw = 0
    Try { Do ##class(dc.omniEmbedding.provider.AzureOpenAi).SetAuth(request, config) }
    Catch { Set threw = 1 }
    Do $$$AssertTrue(threw, "throws when apiKey resolves to empty")
}

// --- ValidateConfig: each required field ---

Method TestValidateMissingApiBase()
{
    Set config = ##class(%DynamicObject).%FromJSON("{""modelName"":""m"",""deployment"":""d"",""apiVersion"":""v"",""apiKey"":""k""}")
    Do ..AssertValidateThrows(config, "apiBase")
}

Method TestValidateMissingApiVersion()
{
    Set config = ##class(%DynamicObject).%FromJSON("{""modelName"":""m"",""apiBase"":""https://x"",""deployment"":""d"",""apiKey"":""k""}")
    Do ..AssertValidateThrows(config, "apiVersion")
}

Method TestValidateMissingDeploymentOnRootBase()
{
    Set config = ##class(%DynamicObject).%FromJSON("{""modelName"":""m"",""apiBase"":""https://x"",""apiVersion"":""v"",""apiKey"":""k""}")
    Do ..AssertValidateThrows(config, "deployment")
}

Method TestValidateDeploymentOptionalOnFullBase()
{
    Set config = ##class(%DynamicObject).%FromJSON("{""modelName"":""m"",""apiBase"":""https://x/openai/deployments/d/embeddings"",""apiVersion"":""v"",""apiKey"":""k""}")
    Set threw = 0
    Try { Do ##class(dc.omniEmbedding.provider.AzureOpenAi).ValidateConfig(config) }
    Catch { Set threw = 1 }
    Do $$$AssertNotTrue(threw, "deployment not required when apiBase already contains it")
}

Method TestValidateMissingApiKey()
{
    Set config = ##class(%DynamicObject).%FromJSON("{""modelName"":""m"",""apiBase"":""https://x"",""deployment"":""d"",""apiVersion"":""v""}")
    Do ..AssertValidateThrows(config, "apiKey")
}

Method TestValidateMissingModelName()
{
    Set config = ##class(%DynamicObject).%FromJSON("{""apiBase"":""https://x"",""deployment"":""d"",""apiVersion"":""v"",""apiKey"":""k""}")
    Do ..AssertValidateThrows(config, "modelName")
}

/// Helper: asserts ValidateConfig throws and the message mentions the given field.
Method AssertValidateThrows(config As %DynamicObject, expectedField As %String) [ Private ]
{
    Set threw = 0, errMsg = ""
    Try { Do ##class(dc.omniEmbedding.provider.AzureOpenAi).ValidateConfig(config) }
    Catch ex { Set threw = 1, errMsg = ex.DisplayString() }
    Do $$$AssertTrue(threw, "ValidateConfig throws for missing "_expectedField)
    Do $$$AssertTrue($Find(errMsg, expectedField) > 0, "error mentions '"_expectedField_"': "_errMsg)
}

}
