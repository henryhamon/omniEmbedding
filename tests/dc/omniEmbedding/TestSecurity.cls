Include (%occStatus, %outUnitTest)

/// Security tests for dc.omniEmbedding.provider.Base.ResolveApiKey.
/// Property 15: an exception raised for a missing credential MUST contain the
/// credential name and MUST NOT contain the (would-be) value. Callers must
/// treat the resolved value as secret — never log it, never leak it.
Class dc.omniEmbedding.tests.TestSecurity Extends %UnitTest.TestCase
{

Parameter GOODNAME = "omni-test-good";

Parameter MISSING = "omni-test-missing";

Parameter SECRET = "sk-test-DO-NOT-LEAK-9f2a3b1c";

Method OnBeforeOneTest(testname As %String) As %Status
{
    // Test hook: seed one credential, ensure the other is truly absent
    Set ^||omniEmbeddingCredential(..#GOODNAME) = ..#SECRET
    Kill ^||omniEmbeddingCredential(..#MISSING)
    Return $$$OK
}

Method OnAfterOneTest(testname As %String) As %Status
{
    Kill ^||omniEmbeddingCredential
    Return $$$OK
}

// --- Happy path: credential is resolved ---

Method TestResolveReturnsRegisteredValue()
{
    Set config = ##class(%DynamicObject).%FromJSON("{""apiKey"":"""_..#GOODNAME_"""}")
    Set value = ##class(dc.omniEmbedding.provider.Base).ResolveApiKey(config)
    Do $$$AssertEquals(value, ..#SECRET, "resolves to the registered secret value")
}

Method TestResolveEmptyNameReturnsEmpty()
{
    // Ollama-style config with no apiKey — must return "" without throwing
    Set config = ##class(%DynamicObject).%FromJSON("{""modelName"":""nomic-embed-text""}")
    Set value = ##class(dc.omniEmbedding.provider.Base).ResolveApiKey(config)
    Do $$$AssertEquals(value, "", "empty apiKey returns empty (not thrown)")
}

// --- Property 15: exception carries the NAME, never the value ---

Method TestMissingCredentialThrowsWithName()
{
    Set config = ##class(%DynamicObject).%FromJSON("{""apiKey"":"""_..#MISSING_"""}")
    Set threw = 0, errMsg = ""
    Try { Do ##class(dc.omniEmbedding.provider.Base).ResolveApiKey(config) }
    Catch ex { Set threw = 1, errMsg = ex.DisplayString() }
    Do $$$AssertTrue(threw, "throws when credential absent")
    Do $$$AssertTrue($Find(errMsg, ..#MISSING) > 0, "error MUST mention credential name")
}

Method TestExceptionDoesNotLeakSecret()
{
    // Register a value under GOODNAME, then ASK for MISSING — the exception
    // must not accidentally contain SECRET (defensive against future refactors)
    Set config = ##class(%DynamicObject).%FromJSON("{""apiKey"":"""_..#MISSING_"""}")
    Set threw = 0, errMsg = ""
    Try { Do ##class(dc.omniEmbedding.provider.Base).ResolveApiKey(config) }
    Catch ex { Set threw = 1, errMsg = ex.DisplayString() }
    Do $$$AssertTrue(threw, "throws")
    Do $$$AssertEquals($Find(errMsg, ..#SECRET), 0, "error MUST NOT contain the secret value")
}

// --- config.apiKey is a NAME, never treated as the value directly ---

Method TestApiKeyIsNameNotValue()
{
    // Register SECRET under GOODNAME. Resolve GOODNAME → get SECRET.
    // Now put SECRET itself as apiKey — it should fail (no cred named SECRET),
    // proving apiKey is never used as the raw value.
    Set config = ##class(%DynamicObject).%FromJSON("{""apiKey"":"""_..#SECRET_"""}")
    Set threw = 0
    Try { Do ##class(dc.omniEmbedding.provider.Base).ResolveApiKey(config) }
    Catch { Set threw = 1 }
    Do $$$AssertTrue(threw, "raw value in apiKey does NOT bypass credential lookup")
}

}
