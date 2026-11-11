extends RefCounted
## Timing in generator tests. A busy machine (other test Godots, a landing running bots) now and then makes ONE call
## slow, and a "worst ms" over thousands of calls then fails a fast generator (Mini Golf's surprises took 42 ms once
## during a landing, 2026-11-11). When a call would be the new worst, run it twice more and keep the fastest:
##   const TestTime := preload("res://tests/test_time.gd")
##   var t1 := Time.get_ticks_usec()
##   var list := Deep.events(es, spec)
##   worst_ms = TestTime.worst(worst_ms, (Time.get_ticks_usec() - t1) / 1000.0, func() -> Variant: return Deep.events(es, spec))
## (dev.debt flags a bare worst_ms = maxf(worst_ms, ...ticks...) in tests: "test-timing-spike".)


static func worst(worst_ms: float, ms: float, again: Callable) -> float:
	if ms <= worst_ms:
		return worst_ms
	for i in 2:
		var t := Time.get_ticks_usec()
		again.call()
		ms = minf(ms, (Time.get_ticks_usec() - t) / 1000.0)
	return maxf(worst_ms, ms)
