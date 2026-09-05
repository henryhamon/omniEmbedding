Include (%occStatus, %outUnitTest)

/// Resilience tests: Property 11 (Retry-After honored + delay cap),
/// Property 12 (fast-fail on 4xx != 429), Property 13 (circuit breaker
/// opens after threshold, closes after cooldown), Property 14 (RecordSuccess
/// resets to $LISTBUILD(0,0)).
Class dc.omniEmbedding.tests.TestResilience Extends %UnitTest.TestCase
{

Parameter BREAKERKEY = "test|resilience|http://x";

Method OnBeforeOneTest(testname As %String) As %Status
{
    Kill ^omniEmbedding.Breaker(..#BREAKERKEY)
    Return $$$OK
}

Method OnAfterOneTest(testname As %String) As %Status
{
    Kill ^omniEmbedding.Breaker(..#BREAKERKEY)
    Return $$$OK
}

// --- Property 12: fast-fail on 4xx (except 429) ---

Method TestFastFail4xxSet()
{
    For status = 400, 401, 403, 404, 422 {
        Do $$$AssertTrue(##class(dc.omniEmbedding.provider.Base).IsFastFailStatus(status), "status "_status_" is fast-fail")
    }
}

Method TestNotFastFail429()
{
    Do $$$AssertNotTrue(##class(dc.omniEmbedding.provider.Base).IsFastFailStatus(429), "429 is retryable, not fast-fail")
}

Method TestNotFastFail5xx()
{
    For status = 500, 502, 503, 504 {
        Do $$$AssertNotTrue(##class(dc.omniEmbedding.provider.Base).IsFastFailStatus(status), "status "_status_" is retryable")
    }
}

Method TestNotFastFail2xx()
{
    Do $$$AssertNotTrue(##class(dc.omniEmbedding.provider.Base).IsFastFailStatus(200), "200 is not fast-fail")
}

// --- Property 11: Retry-After honored ---

Method TestRetryAfterHonored()
{
    Set config = ##class(%DynamicObject).%FromJSON("{}")
    Set delay = ##class(dc.omniEmbedding.provider.Base).ComputeBackoffDelay(1, "3", config)
    Do $$$AssertEquals(delay, 3000, "Retry-After: 3 -> 3000 ms")

    Set delay2 = ##class(dc.omniEmbedding.provider.Base).ComputeBackoffDelay(1, "10", config)
    Do $$$AssertEquals(delay2, 10000, "Retry-After: 10 -> 10000 ms (NOT capped by maxDelayMs when server dictates)")
}

Method TestRetryAfterNonNumericFallsBackToBackoff()
{
    Set config = ##class(%DynamicObject).%FromJSON("{""retry"":{""baseDelayMs"":500,""maxDelayMs"":8000}}")
    // Non-numeric (HTTP-date form) — falls back to backoff formula
    Set delay = ##class(dc.omniEmbedding.provider.Base).ComputeBackoffDelay(1, "Wed, 21 Oct 2015 07:28:00 GMT", config)
    Do $$$AssertTrue(delay <= 8000, "non-numeric Retry-After -> capped backoff")
    Do $$$AssertTrue(delay >= 500, "non-numeric Retry-After -> at least baseDelayMs")
}

// --- Property 11 (continued): backoff obeys maxDelayMs cap ---

Method TestBackoffCappedByMaxDelay()
{
    Set config = ##class(%DynamicObject).%FromJSON("{""retry"":{""baseDelayMs"":500,""maxDelayMs"":8000}}")
    // On attempt 10, exp = 500 * 2^9 = 256000 — must be capped
    For attempt = 5, 10, 20 {
        Set delay = ##class(dc.omniEmbedding.provider.Base).ComputeBackoffDelay(attempt, "", config)
        Do $$$AssertTrue(delay <= 8000, "attempt "_attempt_" delay ("_delay_") capped at maxDelayMs")
    }
}

Method TestBackoffMonotonicUntilCap()
{
    Set config = ##class(%DynamicObject).%FromJSON("{""retry"":{""baseDelayMs"":100,""maxDelayMs"":100000}}")
    Set d1 = ##class(dc.omniEmbedding.provider.Base).ComputeBackoffDelay(1, "", config)
    Set d3 = ##class(dc.omniEmbedding.provider.Base).ComputeBackoffDelay(3, "", config)
    Do $$$AssertTrue(d3 > d1, "attempt 3 delay ("_d3_") > attempt 1 delay ("_d1_") before cap")
}

Method TestBackoffUsesDefaults()
{
    // No retry config at all → default baseDelayMs=500, maxDelayMs=8000
    Set config = ##class(%DynamicObject).%FromJSON("{}")
    Set delay = ##class(dc.omniEmbedding.provider.Base).ComputeBackoffDelay(1, "", config)
    // exp = 500 * 1 = 500; jitter 0..499 → 500..999
    Do $$$AssertTrue((delay >= 500) && (delay < 1000), "attempt 1 default backoff in [500,1000): "_delay)
}

// --- Property 13: circuit breaker opens after 5 failures, closes after 60s ---

Method TestBreakerClosedBelowThreshold()
{
    For i = 1:1:4 { Do ##class(dc.omniEmbedding.Engine).RecordFailure(..#BREAKERKEY) }
    Do $$$AssertNotTrue(##class(dc.omniEmbedding.Engine).CheckBreaker(..#BREAKERKEY), "4 failures: still closed")
    Set data = $Get(^omniEmbedding.Breaker(..#BREAKERKEY))
    Do $$$AssertEquals($ListGet(data, 1), 4, "failures counter = 4")
    Do $$$AssertEquals($ListGet(data, 2), 0, "openedAt still 0 (not tripped)")
}

Method TestBreakerOpensAtThreshold()
{
    For i = 1:1:5 { Do ##class(dc.omniEmbedding.Engine).RecordFailure(..#BREAKERKEY) }
    Do $$$AssertTrue(##class(dc.omniEmbedding.Engine).CheckBreaker(..#BREAKERKEY), "5 failures: open")
    Set data = $Get(^omniEmbedding.Breaker(..#BREAKERKEY))
    Do $$$AssertEquals($ListGet(data, 1), 5, "failures counter = 5")
    Do $$$AssertTrue($ListGet(data, 2) > 0, "openedAt set to now")
}

Method TestBreakerHalfOpenAfterCooldown()
{
    For i = 1:1:5 { Do ##class(dc.omniEmbedding.Engine).RecordFailure(..#BREAKERKEY) }
    // Rewrite state so openedAt is 61 seconds in the past — cooldown expired
    Set past = ##class(dc.omniEmbedding.Engine).NowSeconds() - 61
    Set ^omniEmbedding.Breaker(..#BREAKERKEY) = $ListBuild(5, past)
    Do $$$AssertNotTrue(##class(dc.omniEmbedding.Engine).CheckBreaker(..#BREAKERKEY), "after 60s cooldown: half-open (returns 0)")
}

Method TestBreakerStillOpenWithinCooldown()
{
    For i = 1:1:5 { Do ##class(dc.omniEmbedding.Engine).RecordFailure(..#BREAKERKEY) }
    // 30 seconds in the past — still within cooldown
    Set recent = ##class(dc.omniEmbedding.Engine).NowSeconds() - 30
    Set ^omniEmbedding.Breaker(..#BREAKERKEY) = $ListBuild(5, recent)
    Do $$$AssertTrue(##class(dc.omniEmbedding.Engine).CheckBreaker(..#BREAKERKEY), "within cooldown: still open")
}

// --- Enriched error messages: StatusHint / TransportHint ---

Method TestStatusHint401MentionsCredentialName()
{
    Set config = ##class(%DynamicObject).%FromJSON("{""apiKey"":""azure-openai""}")
    Set hint = ##class(dc.omniEmbedding.provider.Base).StatusHint(401, config)
    Do $$$AssertTrue($Find(hint, "azure-openai") > 0, "401 hint names the credential: "_hint)
    Do $$$AssertTrue($Find(hint, "Ens.Config.Credentials") > 0, "401 hint tells caller where to check")
    Do $$$AssertTrue($Find(hint, "regenerate") > 0, "401 hint suggests regeneration")
}

Method TestStatusHint403MentionsPermission()
{
    Set config = ##class(%DynamicObject).%FromJSON("{""apiKey"":""prod-key""}")
    Set hint = ##class(dc.omniEmbedding.provider.Base).StatusHint(403, config)
    Do $$$AssertTrue($Find(hint, "prod-key") > 0, "403 hint names the credential")
    Do $$$AssertTrue($Find(hint, "permission") > 0, "403 hint mentions permission")
}

Method TestStatusHint404MentionsModelAndDeployment()
{
    Set hint = ##class(dc.omniEmbedding.provider.Base).StatusHint(404, ##class(%DynamicObject).%FromJSON("{}"))
    Do $$$AssertTrue($Find(hint, "modelName") > 0, "404 hint mentions modelName")
    Do $$$AssertTrue($Find(hint, "deployment") > 0, "404 hint mentions Azure deployment concept")
}

Method TestStatusHint429MentionsRetryAfter()
{
    Set hint = ##class(dc.omniEmbedding.provider.Base).StatusHint(429, ##class(%DynamicObject).%FromJSON("{}"))
    Do $$$AssertTrue($Find(hint, "Retry-After") > 0, "429 hint mentions Retry-After")
    Do $$$AssertTrue($Find(hint, "maxAttempts") > 0, "429 hint mentions retry config")
}

Method TestStatusHint5xxMentionsUpstream()
{
    For status = 500, 502, 503, 504 {
        Set hint = ##class(dc.omniEmbedding.provider.Base).StatusHint(status, ##class(%DynamicObject).%FromJSON("{}"))
        Do $$$AssertTrue($Find(hint, "upstream") > 0, "5xx hint for "_status_" mentions upstream")
    }
}

Method TestStatusHintUnknownStatusIsEmpty()
{
    Set hint = ##class(dc.omniEmbedding.provider.Base).StatusHint(418, ##class(%DynamicObject).%FromJSON("{}"))
    Do $$$AssertEquals(hint, "", "unknown status yields empty hint (no misleading advice)")
}

Method TestStatusHintDoesNotLeakCredentialValue()
{
    // Register a credential, ensure the hint never contains the VALUE — only the NAME
    Set ^||omniEmbeddingCredential("secret-name") = "SUPER-SECRET-VALUE-XYZ"
    Set config = ##class(%DynamicObject).%FromJSON("{""apiKey"":""secret-name""}")
    Set hint = ##class(dc.omniEmbedding.provider.Base).StatusHint(401, config)
    Do $$$AssertTrue($Find(hint, "secret-name") > 0, "hint names the credential")
    Do $$$AssertEquals($Find(hint, "SUPER-SECRET-VALUE-XYZ"), 0, "hint MUST NOT contain the credential value")
    Kill ^||omniEmbeddingCredential("secret-name")
}

Method TestTransportHintOnHttpsMentionsSslConfig()
{
    Set hint = ##class(dc.omniEmbedding.provider.Base).TransportHint("https://api.example.com/v1/x", "SSL error")
    Do $$$AssertTrue($Find(hint, "sslConfig") > 0, "HTTPS transport hint suggests 'sslConfig' field")
    Do $$$AssertTrue($Find(hint, "Security.SSLConfigs") > 0, "hint mentions the IRIS class to create SSL config")
}

Method TestTransportHintOnHttpMentionsNetwork()
{
    Set hint = ##class(dc.omniEmbedding.provider.Base).TransportHint("http://localhost:11434/x", "connect failed")
    Do $$$AssertTrue($Find(hint, "network") > 0, "HTTP transport hint mentions network reachability")
    Do $$$AssertEquals($Find(hint, "sslConfig"), 0, "no misleading SSL suggestion on plain HTTP URL")
}

// --- Property 14: RecordSuccess resets to $LISTBUILD(0, 0) ---

Method TestRecordSuccessResetsState()
{
    For i = 1:1:5 { Do ##class(dc.omniEmbedding.Engine).RecordFailure(..#BREAKERKEY) }
    Do ##class(dc.omniEmbedding.Engine).RecordSuccess(..#BREAKERKEY)
    Do $$$AssertNotTrue(##class(dc.omniEmbedding.Engine).CheckBreaker(..#BREAKERKEY), "after success: closed")
    Set data = $Get(^omniEmbedding.Breaker(..#BREAKERKEY))
    Do $$$AssertEquals(data, $ListBuild(0, 0), "state is exactly $LISTBUILD(0, 0)")
}

}
