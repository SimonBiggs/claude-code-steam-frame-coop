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
	# Tiny calls never matter for a 5-100 ms budget, and re-timing them made a would-be worst that never settles (the
	# caller's wall clock vs the retries' on-CPU time): Cannon Cove's 0.1 ms waves took 92 s instead of 4 (2026-11-20).
	if ms < MIN_RETRY_MS:
		return ms
	# First re-time at once (on-CPU time x the machine's current slowness, cached for 0.5 s): the caller's wall-clock
	# reading is often just the busy machine, and the spread-out retries (40 ms gaps) are only for what still looks slow.
	# (Waiting before every check made Whack-a-Mole's quick run 34 s instead of 14.)
	var scale := _scale_cached(false)
	for i in RETRIES + 1:
		if i > 0:
			OS.delay_msec(RETRY_GAP_MS)
			if i == 1:
				scale = _scale_cached(true)
		var t := cpu_usec()
		again.call()
		ms = minf(ms, (cpu_usec() - t) / 1000.0 * scale)
		if ms <= worst_ms:
			break
	return maxf(worst_ms, ms)


static var _scale := 1.0
static var _scale_at := -1000000


static func _scale_cached(fresh: bool) -> float:
	if fresh or Time.get_ticks_msec() - _scale_at > 500:
		_scale = load_scale()
		_scale_at = Time.get_ticks_msec()
	return _scale


## On-CPU time alone still read 47 ms under load: busy sibling hyperthreads and shared caches slow the work itself.
## So a would-be new worst is scaled by how much slower a FIXED reference loop runs right now than on a quiet Steam
## Machine (REF_QUIET_US, measured 2026-11-20). Never scales up; at most 4x down.
static func load_scale() -> float:
	var now := INF
	for i in 3:
		var t := cpu_usec()
		var acc := 0
		for j in REF_LOOPS:
			acc = (acc * 31 + j) % 1000003
		now = minf(now, cpu_usec() - t)
		if acc < 0:
			print(acc)
	var s := clampf(REF_QUIET_US / maxf(now, 1.0), 0.25, 1.0)
	return 1.0 if s > 0.8 else s  # a quiet machine's jitter must not shrink the worst (more re-times, slower tests)


## 2026-11-20: still not enough: the nightly failed Mini Golf at 40.3 ms (18-27 ms on a quiet machine) and under
## steady load every retry was slow too (41-51 ms). So the retries time the call in THIS THREAD's on-CPU time
## (/proc/thread-self/schedstat, ns), which waiting for a busy CPU doesn't add to; wall clock where that's missing.
static func cpu_usec() -> float:
	var f := FileAccess.open("/proc/thread-self/schedstat", FileAccess.READ)
	if f == null:
		return float(Time.get_ticks_usec())
	var ns := f.get_line().get_slice(" ", 0)
	return ns.to_float() / 1000.0 if ns.is_valid_int() else float(Time.get_ticks_usec())


const RETRIES := 5
const MIN_RETRY_MS := 2.0
const RETRY_GAP_MS := 40
const REF_LOOPS := 100000
const REF_QUIET_US := 2000.0  # REF_LOOPS on a quiet Steam Machine (TestTime.calibrate())


## Prints the reference loop's best time here (set REF_QUIET_US from a quiet machine).
static func calibrate() -> float:
	var best := INF
	for i in 20:
		var t := cpu_usec()
		var acc := 0
		for j in REF_LOOPS:
			acc = (acc * 31 + j) % 1000003
		best = minf(best, cpu_usec() - t)
		if acc < 0:
			print(acc)
	print("TestTime reference: %.0f us" % best)
	return best
