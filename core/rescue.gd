extends RefCounted
## RESCUE (shared): a player who is struggling in their first minute gets quiet help, so the first round
## isn't a wall they bounce off. Evidence (telemetry): Rhythm Band on the TV 2026-11-15, a first play on
## HARD, 8 hits / 11 misses, quit at 31 s; Giant's Table in VR 2026-11-19, a guest beat 0 of 5 goblins in
## wave 1 and quit at 101 s; people kept bouncing to another game.
## Feed it:
##   note(true / false)  a hit / a miss (notes, grabs that worked, goblins beaten / lost);
##   tick(delta, waiting) every frame; waiting = there is something to do right now (a goblin on the
##     table, a note due) - time spent waiting without a success counts as struggling too.
## level() rises 0 -> 1 over ~8 s while struggling and falls slowly once they're doing fine; a game scales
## its timing window / reach / speed by it. crossed() is true once, the first time help kicks in (a game
## can show its how-to again). run_fields() goes on the RUN line so play-record can see who needed it.

const WINDOW := 12          # recent results looked at
const MIN_RESULTS := 6      # before the miss rate counts
const HARD_RATE := 0.5      # miss rate above this = struggling
const EASY_RATE := 0.25     # below this = doing fine
const IDLE_START := 6.0     # seconds waiting with nothing done = struggling
const RISE := 0.125         # level per second while struggling (0 -> 1 in 8 s)
const FALL := 0.04          # level per second while doing fine (1 -> 0 in 25 s)
const CROSS := 0.4

var recent: Array[bool] = []
var idle_t := 0.0
var lvl := 0.0
var peak := 0.0
var helped_t := 0.0
var successes := 0
var _crossed := false
var _told := false


func note(ok: bool) -> void:
	recent.append(ok)
	if recent.size() > WINDOW:
		recent.pop_front()
	if ok:
		idle_t = 0.0
		successes += 1


func miss_rate() -> float:
	if recent.is_empty():
		return 0.0
	var m := 0
	for r in recent:
		if not r:
			m += 1
	return float(m) / float(recent.size())


func struggling() -> bool:
	return idle_t > IDLE_START or (recent.size() >= MIN_RESULTS and miss_rate() > HARD_RATE)


func doing_fine() -> bool:
	return recent.size() >= MIN_RESULTS and miss_rate() < EASY_RATE


func tick(delta: float, waiting: bool = false) -> void:
	if waiting:
		idle_t += delta
	if struggling():
		lvl = minf(1.0, lvl + RISE * delta)
		helped_t += delta
	elif doing_fine() or successes > 0 and idle_t < 1.0:
		lvl = maxf(0.0, lvl - FALL * delta)
	peak = maxf(peak, lvl)
	if lvl >= CROSS and not _told:
		_told = true
		_crossed = true


func level() -> float:
	return lvl


## True once, the first frame help passes CROSS.
func crossed() -> bool:
	var c := _crossed
	_crossed = false
	return c


func run_fields() -> Dictionary:
	return {"rescue_peak": snappedf(peak, 0.01), "rescue_secs": snappedf(helped_t, 0.1)}
