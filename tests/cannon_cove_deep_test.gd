extends SceneTree
## CANNON COVE second pass validator (no game, no window): games/cannon_cove/deep.gd.
##   godot-test --headless --path . -s res://tests/cannon_cove_deep_test.gd      (SEEDS=40 for more)
## Proves, for every mode over every wave, season and many seeds:
##   - every deck event is fair (deep.gd problems(): Kraken arms slam on the deck, clear of the cannons (the gunner),
##     the cannonball pile and the masts, coming over the rail away from the cannons, with a lane past and time to step
##     out while told; squalls never cover a cannon row or the pile and never push too far; never two at once; none on
##     wave 1; only arms on the Kraken's wave) and the same every time, and unchanged over the network;
##   - GENTLE <= BRAVE <= HARD: the mode table (deep.gd ordered()) AND what the waves really get (events a wave,
##     warning seconds, slam size, how far a squall pushes);
##   - Polly's gifts: three different unlocked ones, the newest among them, not the last again when there are others,
##     every picture drawn, short names; every gift opens within a few weeks of play;
##   - the seasons: each has drifting things, a tree, a picture and a line;
##   - the pick row: every orb inside the cannon's swing and reach from every cannon, orbs far enough apart that one
##     ball never takes two, above the sea even when the hold floods, and the wait is long enough to aim;
##   - Polly's harbour: only grows, stands clear of every pirate's circle and lane, pieces don't overlap;
##   - every key colour stands out (core/contrast.gd, games/cannon_cove/palette.gd);
##   - fast: well under 100 ms a wave (a Deck builds one between waves).
## Prints "SCRIPT ERROR: ..." for each failure and "COVE DEEP: PASS" / "FAIL".

const Contrast := preload("res://core/contrast.gd")
const Deep := preload("res://games/cannon_cove/deep.gd")
const VoyageGen := preload("res://games/cannon_cove/voyagegen.gd")
const World := preload("res://games/cannon_cove/world.gd")
const PickOrbs := preload("res://core/pick_orbs.gd")
const StoryCard := preload("res://core/story_card.gd")
const Seeded := preload("res://core/seeded.gd")
const Cannon := preload("res://games/cannon_cove/cannon.gd")
const EnemyShip := preload("res://games/cannon_cove/enemy_ship.gd")

var fails := 0


func _init() -> void:
	var t0 := Time.get_ticks_msec()
	var seeds := int(OS.get_environment("SEEDS")) if OS.has_environment("SEEDS") else 12
	for w in Deep.ordered():
		_fail("modes: " + str(w))
	for w in Contrast.check_game("cannon_cove"):
		_fail("contrast: " + str(w))
	var per := {}
	var checked := 0
	var worst_ms := 0.0
	for mode in PickOrbs.MODE_IDS:
		var sum := {"events": 0, "waves": 0, "warn": 0.0, "arm": 0.0, "arms": 0, "drift": 0.0, "squalls": 0}
		for season in Deep.SEASONS:
			for w in range(1, VoyageGen.MAX_WAVE + 1):
				for s in seeds:
					var vseed := 4400 + s * 7919
					var t1 := Time.get_ticks_usec()
					var spec := {"mode": mode, "season": season, "wave": w}
					var es := Seeded.derive(VoyageGen.wave_seed(vseed, w), "events")
					var list := Deep.events(es, spec)
					worst_ms = maxf(worst_ms, (Time.get_ticks_usec() - t1) / 1000.0)
					checked += 1
					var tag := "%s %s wave %d seed %d" % [mode, season, w, vseed]
					for x in Deep.problems(list, spec):
						_fail("%s: %s" % [tag, x])
					if s == 0 and str(Deep.events(es, spec)) != str(list):
						_fail("%s: events differ for the same seed" % tag)
					if w < Deep.FIRST_WAVE and not list.is_empty():
						_fail("%s: events on a calm wave" % tag)
					for e in list:
						if str(Deep.unpack(Deep.pack(e))) != str(e):
							_fail("%s: an event changes over the network" % tag)
					# Bots turn events on from wave 1, doubled: still fair.
					var bot_spec := {"mode": mode, "season": season, "wave": w, "from": 1, "scale": 2.0, "first": 4.0}
					for x in Deep.problems(Deep.events(es, bot_spec), bot_spec):
						_fail("%s (bot spec): %s" % [tag, x])
					if w >= Deep.FIRST_WAVE:
						sum.waves += 1
						sum.events += list.size()
						for e in list:
							sum.warn += float(Deep.mode_data(mode).warn)
							if String(e.kind) == "arm":
								sum.arms += 1
								sum.arm += float((e.size as Vector2).x)
							else:
								sum.squalls += 1
								sum.drift += float(Deep.mode_data(mode).push) * float(Deep.mode_data(mode).gust)
		var waves := maxf(1.0, sum.waves)
		per[mode] = {"events": sum.events / waves, "warn": sum.warn / maxf(1.0, sum.events), "arm": sum.arm / maxf(1.0, sum.arms),
			"drift": sum.drift / maxf(1.0, sum.squalls), "arms": sum.arms, "squalls": sum.squalls}
		print("COVE DEEP %s: %.2f events a wave, told %.1f s, slams r %.2f m, squalls push %.1f m (%d arms, %d squalls)" % [mode,
			per[mode].events, per[mode].warn, per[mode].arm, per[mode].drift, sum.arms, sum.squalls])
	var g: Dictionary = per.gentle
	var b: Dictionary = per.brave
	var h: Dictionary = per.hard
	for k in ["events", "arm", "drift"]:
		if not (float(g[k]) <= float(b[k]) + 0.001 and float(b[k]) <= float(h[k]) + 0.001):
			_fail("real waves: %s not gentle <= brave <= hard (%.2f %.2f %.2f)" % [k, g[k], b[k], h[k]])
	if not (float(g.warn) >= float(b.warn) and float(b.warn) >= float(h.warn)):
		_fail("real waves: warnings not longest on gentle")
	for m in per:
		if float(per[m].events) < 0.8:
			_fail("%s: hardly any deck events (%.2f a wave)" % [m, per[m].events])
		if int(per[m].arms) == 0 or int(per[m].squalls) == 0:
			_fail("%s: never an arm or never a squall" % m)
	_gifts()
	_seasons()
	_row()
	_harbour()
	print("COVE DEEP: %d waves checked, %.1f ms worst, %d ms total" % [checked, worst_ms, Time.get_ticks_msec() - t0])
	if worst_ms > 100.0:
		_fail("a wave took %.0f ms to make (a Deck must stay well under 100 ms)" % worst_ms)
	print("COVE DEEP: %s" % ("PASS" if fails == 0 else "FAIL (%d)" % fails))
	quit(1 if fails > 0 else 0)


func _gifts() -> void:
	var ids: Array = []
	for gd in Deep.GIFTS:
		ids.append(String(gd.id))
		if not StoryCard.has_picture(String(gd.pic)):
			_fail("gift %s: no picture %s" % [gd.id, gd.pic])
		if String(gd.name).length() > 14 or String(gd.line).length() > 20:
			_fail("gift %s: name or line too long" % gd.id)
		if int(gd.unlock) > Deep.HARBOUR.size():
			_fail("gift %s never opens" % gd.id)
		# Treasures to open it: a few weeks of play (about 4 waves cleared a day).
		if int(gd.unlock) * Deep.HARBOUR_EVERY > 4 * 14:
			_fail("gift %s takes too long to open" % gd.id)
	for pieces in range(0, Deep.HARBOUR.size() + 1):
		var un := Deep.unlocked(pieces)
		for last in [""] + ids:
			for s in 6:
				var ch := Deep.gift_choices(pieces, String(last), 300 + s * 7)
				var tag := "gifts (harbour %d, last %s, seed %d)" % [pieces, last, s]
				if ch.size() != mini(3, un.size()):
					_fail("%s: %d choices" % [tag, ch.size()])
				var seen := {}
				for id in ch:
					if seen.has(id):
						_fail("%s: %s twice" % [tag, id])
					seen[id] = true
					if not un.has(id):
						_fail("%s: %s is still locked" % [tag, id])
				if not ch.has(un[un.size() - 1]) and un[un.size() - 1] != last:
					_fail("%s: the newest gift is missing" % tag)
				if un.size() > 3 and ch.has(last):
					_fail("%s: the last gift again" % tag)
				if str(ch) != str(Deep.gift_choices(pieces, String(last), 300 + s * 7)):
					_fail("%s: choices differ for the same seed" % tag)


func _seasons() -> void:
	for s in ["spring", "summer", "autumn", "winter"]:
		if not Deep.SEASONS.has(s):
			_fail("no %s" % s)
			continue
		var sd: Dictionary = Deep.SEASONS[s]
		for k in ["drift", "tree", "pic", "line", "weights"]:
			if not sd.has(k):
				_fail("season %s has no %s" % [s, k])
		if not StoryCard.has_picture(String(sd.pic)):
			_fail("season %s: no picture %s" % [s, sd.pic])
		if String(sd.line).length() > 20:
			_fail("season %s: line too long" % s)
	for date in ["2026-01-10", "2026-04-10", "2026-07-10", "2026-10-10"]:
		if not Deep.SEASONS.has(Seeded.season(date)):
			_fail("no seas for %s" % Seeded.season(date))
	for p in ["krakenarm", "squall", "harbour", "gift", "parrot"]:
		if not StoryCard.has_picture(p):
			_fail("no picture %s" % p)


func _row() -> void:
	var catch := Deep.catch_r()
	var reach := VoyageGen.cannon_range()
	for spot in World.CANNON_SPOTS:
		var cp: Vector3 = spot[0]
		var ob: Vector3 = spot[1]
		for sea_y in [World.BASE_SEA, World.SUNK_SEA]:
			var spots := Deep.row_spots(cp, ob, sea_y)
			if spots.size() != 3:
				_fail("pick row: %d orbs" % spots.size())
				continue
			for i in spots.size():
				var p: Vector3 = spots[i]
				var to := p - cp
				var yaw := absf(ob.signed_angle_to(Vector3(to.x, 0.0, to.z).normalized(), Vector3.UP))
				if yaw > Cannon.YAW_LIMIT - 0.2:
					_fail("pick row: orb %d outside the cannon's swing (%.2f rad)" % [i, yaw])
				var flat := Vector2(to.x, to.z).length()
				if flat > reach - 10.0 or flat < 8.0:
					_fail("pick row: orb %d at %.0f m (the cannon reaches %.0f m)" % [i, flat, reach])
				# The cannon can drop a ball onto it: the ball's path at the orb's distance passes within its catch.
				if not _can_hit(cp, p, catch):
					_fail("pick row: orb %d can't be hit from the cannon" % i)
				if p.y - PickOrbs.HIT_R * Deep.ORB_SCALE * 0.5 < sea_y:
					_fail("pick row: orb %d sinks in the sea" % i)
				for j in i:
					if p.distance_to(spots[j]) < catch * 2.0 + 0.5:
						_fail("pick row: orbs %d and %d too close (one ball takes both)" % [i, j])
				if World.on_deck(p, -1.0):
					_fail("pick row: orb %d on our deck" % i)
	if Deep.ROW_WAIT < 12.0:
		_fail("pick row: too little time to aim (%.0f s)" % Deep.ROW_WAIT)


## Is there a pitch inside the cannon's range whose ball passes within `r` of p?
func _can_hit(cp: Vector3, p: Vector3, r: float) -> bool:
	var to := p - cp
	var flat := Vector2(to.x, to.z).length()
	var v := Cannon.MUZZLE_SPEED
	var pitch := Cannon.PITCH_MIN
	while pitch <= Cannon.PITCH_MAX:
		var t := flat / (v * cos(pitch))
		var y := v * sin(pitch) * t - 0.5 * VoyageGen.GRAVITY * t * t
		if absf(y - to.y) < r * 0.8:
			return true
		pitch += 0.005
	return false


func _harbour() -> void:
	var last := 0
	for n in 400:
		var hb := Deep.harbour(n)
		if hb < last:
			_fail("the harbour shrank at %d treasures" % n)
		last = hb
	if Deep.harbour(9999) != Deep.HARBOUR.size():
		_fail("the harbour never finishes")
	var far := 0.0
	for k in EnemyShip.KINDS:
		far = maxf(far, float(EnemyShip.KINDS[k][2]) + VoyageGen.ORBIT_JITTER.y)
	for i in Deep.HARBOUR.size():
		var p := Deep.harbour_spot(i)
		var d := Vector2(p.x, p.z).length()
		if d < far + Deep.HARBOUR_CLEAR:
			_fail("harbour piece %d inside the pirates' circle (%.0f m, ships circle out to %.0f m)" % [i, d, far])
		# Pirates (and bomb boats) come in from port and starboard within APPROACH of straight out.
		var bearing := absf(atan2(p.z, absf(p.x)))
		if bearing < VoyageGen.APPROACH + 0.25:
			_fail("harbour piece %d in a pirate's lane" % i)
		for j in i:
			if p.distance_to(Deep.harbour_spot(j)) < 3.5:
				_fail("harbour pieces %d and %d overlap" % [i, j])
		if p.distance_to(Deep.HARBOUR_AT) > Deep.HARBOUR_R - 1.0:
			_fail("harbour piece %d off the island" % i)


func _fail(what: String) -> void:
	fails += 1
	if fails <= 40:
		print("SCRIPT ERROR: COVE DEEP: " + what)
