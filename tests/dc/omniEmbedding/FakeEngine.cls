Include %occStatus

/// Test double for dc.omniEmbedding.Engine. Overrides LoadFallbackConfig to
/// serve configs from an in-memory registry (no %Embedding.Config needed) and
/// Embed to record call counts and optionally fail — so fallback tests can
/// verify HTTP was or was NOT called without any real network.
Class dc.omniEmbedding.tests.FakeEngine Extends dc.omniEmbedding.Engine
{

/// Register a fake config under the given fallback name.
ClassMethod Register(name As %String, config As %DynamicObject)
{
    Set ^||FakeEngine("configs", name) = config.%ToJSON()
}

/// Reset counters and registry between tests.
ClassMethod Reset()
{
    Kill ^||FakeEngine
}

ClassMethod SetEmbedFails(fails As %Boolean)
{
    Set ^||FakeEngine("fails") = fails
}

ClassMethod EmbedCalls() As %Integer
{
    Return +$Get(^||FakeEngine("calls"), 0)
}

/// Override: serve from the in-memory registry instead of %Embedding.Config.
ClassMethod LoadFallbackConfig(name As %String) As %DynamicObject [ Internal ]
{
    Set json = $Get(^||FakeEngine("configs", name))
    If json = "" {
        $$$ThrowStatus($$$ERROR($$$GeneralError, "FakeEngine.LoadFallbackConfig: no config registered for '"_name_"'"))
    }
    Return {}.%FromJSON(json)
}

/// Override: count calls, and either throw (default) or return a dummy vector.
ClassMethod Embed(input As %String, config As %DynamicObject) As %Vector
{
    Set ^||FakeEngine("calls") = +$Get(^||FakeEngine("calls"), 0) + 1
    If +$Get(^||FakeEngine("fails"), 0) {
        $$$ThrowStatus($$$ERROR($$$GeneralError, "FakeEngine.Embed: simulated failure"))
    }
    Return ""
}

}
