extends RefCounted
## Timing in generator tests. A busy machine (other test Godots, a landing running bots) now and then makes ONE call
## slow, and a "worst ms" over thousands of calls then fails a fast generator (Mini Golf's surprises took 42 ms once
## during a landing, 2026-11-11). When a call would be the new worst, run it again a few times, spread out, and keep the fastest:
##   const TestTime := preload("res://tests/test_time.gd")
##   var t1 := Time.get_ticks_usec()
##   var list := Deep.events(es, spec)
##   worst_ms = TestTime.worst(worst_ms, (Time.get_ticks_usec() - t1) / 1000.0, func() -> Variant: return Deep.events(es, spec))
## (dev.debt flags a bare worst_ms = maxf(worst_ms, ...ticks...) in tests: "test-timing-spike".)


## A sustained busy spell (the 03:30 nightly runs at idle priority while a landing's bots and agents' tests use the
## same 4 threads) made all three tries slow at once: Mini Golf's surprises 43 ms, 2026-11-14. So the retries are
## spread out: up to 5 more, 40 ms apart, keeping the fastest; a really slow generator is slow every time.
static func worst(worst_ms: float, ms: float, again: Callable) -> float:
	if ms <= worst_ms:
		return worst_ms
	for i in RETRIES:
		OS.delay_msec(RETRY_GAP_MS)
		var t := Time.get_ticks_usec()
		again.call()
		ms = minf(ms, (Time.get_ticks_usec() - t) / 1000.0)
		if ms <= worst_ms:
			break
	return maxf(worst_ms, ms)


const RETRIES := 5
const RETRY_GAP_MS := 40
