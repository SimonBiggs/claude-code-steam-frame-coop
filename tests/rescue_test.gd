extends SceneTree
## RESCUE (core/rescue.gd): struggling players get quiet help, doing-fine players lose it again.
##   godot-test --headless --path . -s res://tests/rescue_test.gd
## - misses ramp the level up to 1 within ~8 s, hits bring it back down, crossed() fires exactly once;
## - waiting with something to do (a loose goblin) and no success counts as struggling; a success resets it;
## - a player doing fine never gets help;
## - the games that use it (Rhythm Band, Giant's Table, Kart Race) feed it, use its level and put
##   rescue_peak / rescue_secs on their RUN line (so play-record can see who needed help).
## Prints "SCRIPT ERROR: ..." per failure and "RESCUE: PASS" or "FAIL" (exit code 1).

const Rescue := preload("res://core/rescue.gd")
const USERS := {
	"res://games/rhythm_band/main.gd": ["rescue.note(", "rescue_lvl)", "rescue.run_fields()"],
	"res://games/giants_table/main.gd": ["rescue.note(true)", "rescue.note(false)", "rescue.level()", "rescue.run_fields()"],
	"res://games/giants_table/goblin.gd": ["goblin_pace()"],
	"res://games/kart_race/kart.gd": ["rescue.note(false)", "rescue.note(true)", "rescue.level()"],
	"res://games/kart_race/main.gd": ["\"rescue_peak\""],
}

var fails := 0


func _check(ok: bool, what: String) -> void:
	if not ok:
		fails += 1
		print("SCRIPT ERROR: RESCUE: " + what)


func _initialize() -> void:
	# Struggling: 8 misses, then 10 s.
	var r = Rescue.new()
	for i in 8:
		r.note(false)
	var crossed := 0
	for i in 600:
		r.tick(1.0 / 60.0)
		if r.crossed():
			crossed += 1
	_check(r.level() > 0.99, "8 misses then 10 s: level %.2f, wants 1" % r.level())
	_check(crossed == 1, "crossed() fired %d times, wants 1" % crossed)
	_check(r.run_fields().rescue_peak >= 0.99 and r.run_fields().rescue_secs > 7.0, "run fields %s" % str(r.run_fields()))
	# Getting the hang of it: hits bring it down.
	for i in 12:
		r.note(true)
	for i in 60 * 30:
		r.tick(1.0 / 60.0)
	_check(r.level() < 0.01, "12 hits then 30 s: level %.2f, wants 0" % r.level())
	for i in 600:
		r.tick(1.0 / 60.0)
		if r.crossed():
			crossed += 1
	_check(crossed == 1, "crossed() fired again after recovering")
	# Waiting with nothing done.
	var w = Rescue.new()
	for i in 60 * 5:
		w.tick(1.0 / 60.0, true)
	_check(w.level() == 0.0, "5 s waiting already helps (%.2f)" % w.level())
	for i in 60 * 6:
		w.tick(1.0 / 60.0, true)
	_check(w.level() > 0.4, "11 s waiting: level %.2f, wants > 0.4" % w.level())
	w.note(true)
	var before: float = w.level()
	for i in 60 * 3:
		w.tick(1.0 / 60.0, true)
	_check(w.level() <= before, "a success didn't stop the help rising (%.2f -> %.2f)" % [before, w.level()])
	# Doing fine: never helped.
	var f = Rescue.new()
	for i in 60 * 60:
		if i % 60 == 0:
			f.note(i % 300 != 0)  # 1 miss in 5
		f.tick(1.0 / 60.0, true)
	_check(f.peak == 0.0, "a player hitting 80%% got help (peak %.2f)" % f.peak)
	# The games use it.
	for path in USERS:
		var src := FileAccess.get_file_as_string(path)
		for want in USERS[path]:
			_check(src.contains(want), "%s doesn't contain %s" % [path, want])
	print("RESCUE: " + ("PASS" if fails == 0 else "FAIL"))
	quit(1 if fails > 0 else 0)
