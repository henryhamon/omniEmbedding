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
