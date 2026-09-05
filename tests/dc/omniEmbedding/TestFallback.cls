Include (%occStatus, %outUnitTest)

/// Tests for TryFallback with vector-space invariance.
/// Property 4: fallback with different modelName OR dimensions is REJECTED
///   with a fatal exception BEFORE any HTTP call (never mix vector spaces).
/// Property 5: fallback in the same vector space is executed.
/// Also covers: empty/missing fallbacks propagates primary failure; all
/// exhausted lists every attempt.
Class dc.omniEmbedding.tests.TestFallback Extends %UnitTest.TestCase
{

// --- AssertVectorSpaceCompatible: the pure invariant check ---

Method TestSameSpaceAccepted()
{
    Set p = ##class(%DynamicObject).%FromJSON("{""modelName"":""nomic-embed-text"",""dimensions"":768}")
    Set f = ##class(%DynamicObject).%FromJSON("{""modelName"":""nomic-embed-text"",""dimensions"":768}")
    Set threw = 0
    Try { Do ##class(dc.omniEmbedding.Engine).AssertVectorSpaceCompatible(p, f, "fb") }
    Catch { Set threw = 1 }
    Do $$$AssertNotTrue(threw, "same modelName + dimensions is accepted")
}

Method TestDifferentModelRejected()
{
    Set p = ##class(%DynamicObject).%FromJSON("{""modelName"":""nomic-embed-text"",""dimensions"":768}")
    Set f = ##class(%DynamicObject).%FromJSON("{""modelName"":""text-embedding-3-small"",""dimensions"":768}")
    Do ..AssertRejects(p, f, "fbA", "nomic-embed-text")
    Do ..AssertRejects(p, f, "fbA", "text-embedding-3-small")
}

Method TestDifferentDimensionsRejected()
{
    Set p = ##class(%DynamicObject).%FromJSON("{""modelName"":""nomic-embed-text"",""dimensions"":768}")
    Set f = ##class(%DynamicObject).%FromJSON("{""modelName"":""nomic-embed-text"",""dimensions"":1024}")
    Do ..AssertRejects(p, f, "fbA", "dimensions")
}

Method TestBothDifferentRejected()
{
    Set p = ##class(%DynamicObject).%FromJSON("{""modelName"":""m1"",""dimensions"":768}")
    Set f = ##class(%DynamicObject).%FromJSON("{""modelName"":""m2"",""dimensions"":1536}")
    Do ..AssertRejects(p, f, "fbA", "m1")
    Do ..AssertRejects(p, f, "fbA", "m2")
}

Method TestDimensionsCoercedToInt()
{
    // string "768" and int 768 should be treated as equal
    Set p = ##class(%DynamicObject).%FromJSON("{""modelName"":""m"",""dimensions"":768}")
    Set f = ##class(%DynamicObject).%FromJSON("{""modelName"":""m"",""dimensions"":""768""}")
    Set threw = 0
    Try { Do ##class(dc.omniEmbedding.Engine).AssertVectorSpaceCompatible(p, f, "fb") }
    Catch { Set threw = 1 }
    Do $$$AssertNotTrue(threw, "numeric coercion: '768' equals 768")
}

// --- TryFallback: empty/missing fallbacks ---

Method TestEmptyFallbacksThrowsWithPrimaryReason()
{
    Set config = ##class(%DynamicObject).%FromJSON("{""provider"":""ollama"",""modelName"":""m"",""dimensions"":768,""fallbacks"":[]}")
    Set threw = 0, errMsg = ""
    Try { Do ##class(dc.omniEmbedding.Engine).TryFallback("hi", config, "primary boom") }
    Catch ex { Set threw = 1, errMsg = ex.DisplayString() }
    Do $$$AssertTrue(threw, "empty fallbacks throws")
    Do $$$AssertTrue($Find(errMsg, "primary boom") > 0, "error carries primary failure reason: "_errMsg)
}

Method TestMissingFallbacksThrows()
{
    Set config = ##class(%DynamicObject).%FromJSON("{""provider"":""ollama"",""modelName"":""m"",""dimensions"":768}")
    Set threw = 0
    Try { Do ##class(dc.omniEmbedding.Engine).TryFallback("hi", config, "boom") }
    Catch { Set threw = 1 }
    Do $$$AssertTrue(threw, "missing fallbacks throws")
}

// --- TryFallback: invariance is fatal — thrown BEFORE any HTTP call ---

// Uses TestEngine below (subclass of Engine that overrides LoadFallbackConfig

// so tests don't need a real %Embedding.Config), and asserts we never enter

// Embed for an incompatible fallback (no counter increment).

Method TestIncompatibleFallbackIsFatal()
{
    Do ##class(dc.omniEmbedding.tests.FakeEngine).Reset()
    Do ##class(dc.omniEmbedding.tests.FakeEngine).Register("bad-dims", ##class(%DynamicObject).%FromJSON("{""provider"":""ollama"",""modelName"":""m"",""dimensions"":1536}"))

    Set config = ##class(%DynamicObject).%FromJSON("{""provider"":""ollama"",""modelName"":""m"",""dimensions"":768,""fallbacks"":[""bad-dims""]}")
    Set threw = 0, errMsg = ""
    Try { Do ##class(dc.omniEmbedding.tests.FakeEngine).TryFallback("hi", config, "primary boom") }
    Catch ex { Set threw = 1, errMsg = ex.DisplayString() }
    Do $$$AssertTrue(threw, "incompatible fallback is fatal")
    Do $$$AssertTrue($Find(errMsg, "vector-space mismatch") > 0, "message identifies the mismatch: "_errMsg)
    Do $$$AssertEquals(##class(dc.omniEmbedding.tests.FakeEngine).EmbedCalls(), 0, "no HTTP call was made")
}

// --- TryFallback: all compatible fallbacks exhausted ---

Method TestAllFallbacksExhausted()
{
    Do ##class(dc.omniEmbedding.tests.FakeEngine).Reset()
    Do ##class(dc.omniEmbedding.tests.FakeEngine).Register("fbA", ##class(%DynamicObject).%FromJSON("{""provider"":""ollama"",""modelName"":""m"",""dimensions"":768}"))
    Do ##class(dc.omniEmbedding.tests.FakeEngine).Register("fbB", ##class(%DynamicObject).%FromJSON("{""provider"":""ollama"",""modelName"":""m"",""dimensions"":768}"))
    Do ##class(dc.omniEmbedding.tests.FakeEngine).SetEmbedFails(1)

    Set config = ##class(%DynamicObject).%FromJSON("{""provider"":""ollama"",""modelName"":""m"",""dimensions"":768,""fallbacks"":[""fbA"",""fbB""]}")
    Set threw = 0, errMsg = ""
    Try { Do ##class(dc.omniEmbedding.tests.FakeEngine).TryFallback("hi", config, "primary boom") }
    Catch ex { Set threw = 1, errMsg = ex.DisplayString() }
    Do $$$AssertTrue(threw, "all fallbacks exhausted throws")
    Do $$$AssertTrue($Find(errMsg, "fbA") > 0, "message lists fbA: "_errMsg)
    Do $$$AssertTrue($Find(errMsg, "fbB") > 0, "message lists fbB: "_errMsg)
    Do $$$AssertTrue($Find(errMsg, "primary boom") > 0, "message carries primary reason")
    Do $$$AssertEquals(##class(dc.omniEmbedding.tests.FakeEngine).EmbedCalls(), 2, "both compatible fallbacks were tried")
}

// --- Helpers ---

/// Asserts AssertVectorSpaceCompatible rejects and the message mentions the fragment.
Method AssertRejects(p As %DynamicObject, f As %DynamicObject, fbName As %String, fragment As %String) [ Private ]
{
    Set threw = 0, errMsg = ""
    Try { Do ##class(dc.omniEmbedding.Engine).AssertVectorSpaceCompatible(p, f, fbName) }
    Catch ex { Set threw = 1, errMsg = ex.DisplayString() }
    Do $$$AssertTrue(threw, "rejects: message must mention '"_fragment_"'")
    Do $$$AssertTrue($Find(errMsg, fragment) > 0, "error mentions '"_fragment_"': "_errMsg)
}

}
