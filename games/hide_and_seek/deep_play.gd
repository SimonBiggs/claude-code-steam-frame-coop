extends Node3D
## HIDE AND SEEK second pass in the game (data and rules: deep.gd). One node under main.gd on every machine:
## - the MODE pick before the first round and PIP'S GIFT pick before every later round (core/pick_orbs.gd orbs over
##   the counting room's floor: stand under one, or reach a VR hand into it, for DWELL seconds; the most picked wins,
##   nobody in time = the middle one),
## - RUMBLE'S SURPRISES while the seeker looks (core/warn_rings.gd tells on the floor first, then Rumble rolls
##   along his band bumping hiders out of disguise, or the pepper pot puffs and everyone in the ring sneezes),
## - the season's props + drift and PIP'S KENNEL pieces in the house's garden.
## The host decides; pack() rides main.gd's snapshot, events ("deep_tell", "deep_go", "deep_bump") tell the rest.

const Deep := preload("res://games/hide_and_seek/deep.gd")
const PickOrbs := preload("res://core/pick_orbs.gd")
const WarnRings := preload("res://core/warn_rings.gd")
const SeasonKit := preload("res://core/season_kit.gd")
const MeshKit := preload("res://core/mesh_kit.gd")
const Seeded := preload("res://core/seeded.gd")
const HouseGen := preload("res://games/hide_and_seek/housegen.gd")
const HouseScript := preload("res://games/hide_and_seek/map_house.gd")

var main
var orbs: PickOrbs
var rings: WarnRings
var mode := ""  # GENTLE / BRAVE / HARD picked this visit ("" until the first pick)
var gift := ""  # this round's gift
var gift_side := ""  # who it helps: "seeker" / "hider"
var stage := ""  # "" / "mode" / "gift": a pick is open
var choices: Array = []
var takes := {}  # player index -> orb index
var stage_t := 0.0
var last_loser := ""  # host: who picks the next gift
var plan: Array = []  # host: this round's surprises (Deep.plan)
var plan_i := 0
var live := {}  # host: the surprise being told / rolling
var bubbles := {}  # hider index -> true (BUBBLE)
var grace := {}  # host: hider index -> seconds nobody can tag them (a popped bubble)
var season := ""
var first_at := Deep.FIRST_AT  # (bots shorten it, like their count)
var kennel_rounds := 0
var stats := {"picks": 0, "tells": 0, "goes": 0, "bumped": 0, "sneezed": 0, "pops": 0}
var _dwell := {}  # host: index -> [orb, seconds]
var _hold := 0.0
var _shown := ""
var _dressed: Node3D
var _dress_key := ""
var _rumble: Node3D
var _roll := {}  # every machine: {from, dir, len, t}
var _bubble_nodes := {}
var _told := {}  # surprise kinds told on a card this visit


func setup(m) -> void:
	main = m
	name = "Deep"
	orbs = PickOrbs.new()
	orbs.collision_layer = 0  # nothing to bump into: you stand under them
	add_child(orbs)
	rings = WarnRings.new()
	add_child(rings)
	season = Seeded.season()
	kennel_rounds = int(main.save.data.get("kennel", 0))


func host() -> bool:
	return main.net == null or main.net.mode != "client"


func mode_id() -> String:
	return Deep.mode_of(mode if mode != "" else String(main.save.data.get("mode", "brave")))


func md() -> Dictionary:
	return Deep.mode_data(mode_id())


# --- Gifts, read by main.gd ---------------------------------------------------------------

func has_gift(id: String, side: String) -> bool:
	return gift == id and gift_side == side


func tag_range(base: float) -> float:
	return Deep.TORCH_RANGE if has_gift("torch", "seeker") else base


func tag_angle(base: float) -> float:
	return Deep.TORCH_ANGLE if has_gift("torch", "seeker") else base


func touch_k() -> float:
	return Deep.REACH_K if has_gift("reach", "seeker") else 1.0


func sniff_range(base: float) -> float:
	return Deep.NOSE_RANGE if has_gift("nose", "seeker") else base


func sniff_cd() -> float:
	return Deep.NOSE_CD if has_gift("nose", "seeker") else float(md().sniff_cd)


func speed_k(p) -> float:
	return Deep.ZOOMY_K if gift == "zoomy" and p.role == gift_side else 1.0


func no_sneeze() -> bool:
	return has_gift("hanky", "hider")


## Host, the seeker tags h: false when a bubble pops instead (or it just popped: a moment to run).
func can_tag(h) -> bool:
	if float(grace.get(h.index, 0.0)) > 0.0:
		return false
	if bubbles.has(h.index):
		bubbles.erase(h.index)
		grace[h.index] = Deep.BUBBLE_GRACE
		stats.pops += 1
		var c: Vector3 = h.center()
		main.sound("pop", 0.0, 1.0)
		main.burst(c, Color(0.6, 0.9, 1.0), 26, 0.09)
		main.net.event("burst", [c, Color(0.6, 0.9, 1.0), 26, 0.09])
		main.popup(c + Vector3.UP * 0.8, "POP!", Color(0.6, 0.9, 1.0), false)
		main.net.event("popup", [c + Vector3.UP * 0.8, "POP!", Color(0.6, 0.9, 1.0), false])
		print("Round %d: P%d's bubble popped" % [main.round_no, h.index + 1])
		return false
	return true


# --- Round flow (host) ----------------------------------------------------------------------

## A new round: a pick first? (true: main.gd waits in phase "pick" until pick_done()).
func begin_round() -> bool:
	gift = ""
	gift_side = ""
	bubbles.clear()
	grace.clear()
	plan.clear()
	plan_i = 0
	live = {}
	rings.clear()
	takes.clear()
	_dwell.clear()
	_hold = 0.0
	if mode == "":
		stage = "mode"
		choices = PickOrbs.mode_ids(Deep.mode_of(String(main.save.data.get("mode", "brave"))))
	elif last_loser != "":
		stage = "gift"
		gift_side = last_loser
		choices = Deep.gift_choices(int(main.map_spec.get("seed", 0)) + int(main.save.data.get("kennel", 0)), main.round_no, gift_side)
	else:
		stage = ""
		return false
	stage_t = float(Deep.PICK_WAIT[stage])
	_face_orbs()
	var card := {"who": "HOW TRICKY?", "line": "Pick one!", "pic": "star", "color": Color(1.0, 0.85, 0.4)} if stage == "mode" else \
		{"who": "PIP'S GIFT", "line": "For the seeker!" if gift_side == "seeker" else "For the hiders!", "pic": "gift", "color": Color(1.0, 0.72, 0.42)}
	card["duration"] = 3.5
	main._story(card)
	print("Round %d: %s pick %s (%s)" % [main.round_no, stage, str(choices), gift_side if stage == "gift" else "everyone"])
	return true


## The seeker turns to the orbs (the flat camera and the VR rig alike).
func _face_orbs() -> void:
	var s = main.players[0]
	var spots := Deep.pick_spots(main.md())
	if not s.active or spots.size() < 2:
		return
	var d: Vector3 = (spots[1] as Vector3) - s.global_position
	main._place_player(s, main.spawn_pos(0), atan2(-d.x, -d.z))


func can_pick(p) -> bool:
	if not p.active or p.late:
		return false
	if stage == "mode":
		return true
	return (gift_side == "seeker" and p.index == 0) or (gift_side == "hider" and p.role == "hider")


## Host, phase "pick": true once it's decided.
func update_pick(delta: float) -> bool:
	stage_t -= delta
	var spots := Deep.pick_spots(main.md())
	var want := 0
	for p in main.players:
		if not can_pick(p):
			continue
		want += 1
		if takes.has(p.index):
			continue
		var at := -1
		var feet: Vector3 = p.global_position
		for i in spots.size():
			var sp: Vector3 = spots[i]
			if Vector2(feet.x - sp.x, feet.z - sp.z).length() < Deep.PICK_TOUCH:
				at = i
			if p.vr and p.hand_l != null:
				var ball := sp + Vector3.UP * Deep.PICK_Y
				if p.hand_l.global_position.distance_to(ball) < Deep.HAND_R or p.hand_r.global_position.distance_to(ball) < Deep.HAND_R:
					at = i
		var dw: Array = _dwell.get(p.index, [-1, 0.0])
		if at < 0:
			_dwell.erase(p.index)
			continue
		dw = [at, float(dw[1]) + delta if int(dw[0]) == at else delta]
		_dwell[p.index] = dw
		if float(dw[1]) >= Deep.DWELL:
			takes[p.index] = at
			stats.picks += 1
			main.sound("ding", -2.0, 1.0 + 0.1 * at)
			var o: Vector3 = sp_at(spots, at)
			main.burst(o, p.color, 14)
			main.net.event("burst", [o, p.color, 14, 0.08])
			print("Round %d: P%d picks %s" % [main.round_no, p.index + 1, choices[at]])
	if want > 0 and takes.size() >= want:
		_hold += delta
	var done := _hold >= 0.6 or stage_t <= 0.0 or (want == 0 and stage_t <= float(Deep.PICK_WAIT[stage]) - Deep.EMPTY_WAIT)
	if done:
		_resolve()
	return done


func sp_at(spots: Array, i: int) -> Vector3:
	return (spots[i] as Vector3) + Vector3.UP * Deep.PICK_Y


func _resolve() -> void:
	var votes := []
	votes.resize(choices.size())
	votes.fill(0)
	for k in takes:
		votes[int(takes[k])] += 1
	var mid := choices.size() / 2
	var best := mid
	for i in choices.size():
		if votes[i] > votes[best]:
			best = i
	var id := String(choices[best])
	if stage == "mode":
		mode = id
		main.save.data["mode"] = id
		main.save.mark_dirty()
		main._story({"who": PickOrbs.mode_name(id), "line": String(PickOrbs.MODE_LINES.get(id, "")), "pic": String(PickOrbs.mode(id).get("pic", "star")),
			"color": PickOrbs.mode_color(id), "duration": 2.5})
	else:
		gift = id
		var gd := Deep.gift(id)
		main._story({"who": String(gd.name), "line": "Thank you, Pip!", "pic": String(gd.pic), "color": gd.color, "duration": 2.5})
		if id == "bubble":
			for p in main.players:
				if p.is_hiding():
					bubbles[p.index] = true
	print("Round %d: %s -> %s (votes %s)" % [main.round_no, stage, id, str(votes)])
	stage = ""
	choices = []
	takes.clear()
	main.run["mode"] = mode_id()
	main.run["gift"] = gift


## Host, the seeker sets off: this round's surprises.
func seek_start() -> void:
	plan = Deep.plan(int(main.map_spec.get("seed", 0)), main.round_no, mode_id(), main.seek_len, main.solo_round, first_at)
	plan_i = 0
	live = {}


## Host, every seek frame.
func update_seek(delta: float) -> void:
	for k in grace.keys():
		grace[k] = float(grace[k]) - delta
		if float(grace[k]) <= 0.0:
			grace.erase(k)
	var gone: float = main.seek_len - main.phase_t
	if live.is_empty() and plan_i < plan.size() and gone >= float(plan[plan_i].t):
		_tell(plan[plan_i])
		plan_i += 1
	if live.is_empty():
		return
	live.t = float(live.t) + delta
	if not bool(live.went) and float(live.t) >= float(live.secs):
		live.went = true
		_go()
	if bool(live.went) and String(live.kind) == "hoover":
		var k := clampf((float(live.t) - float(live.secs)) / Deep.HOOVER_ROLL, 0.0, 1.0)
		var at: Vector3 = (live.from as Vector3) + (live.dir as Vector3) * float(live.len) * k
		for p in main.players:
			if p.is_hiding() and not (live.hit as Dictionary).has(p.index):
				var hp: Vector3 = p.global_position
				if Vector2(hp.x - at.x, hp.z - at.z).length() < Deep.HOOVER_W * 0.5 + 0.35 and \
						WarnRings.inside("line", live.from, live.dir, Vector2(float(live.len), Deep.HOOVER_W), hp, 0.1):
					live.hit[p.index] = true
					_bump(p, live.dir)
		if k >= 1.0:
			live = {}
	elif bool(live.went):
		live = {}


func _tell(s: Dictionary) -> void:
	var hiding: Array = []
	for p in main.players:
		if p.is_hiding():
			hiding.append(p)
	if hiding.is_empty():
		return
	var h = hiding[int(s.k) % hiding.size()]
	var hp: Vector3 = h.global_position
	var kind := String(s.kind)
	var secs := float(md().tell)
	var tell := {}
	if kind == "hoover":
		var dir := Vector3.RIGHT if float(s.a) < 0.5 else Vector3.BACK
		var from := Vector3(hp.x, 0.3, hp.z)
		var band := Deep.hoover_band(hp, dir, _free(from, -dir), _free(from, dir))
		if band.is_empty():
			kind = "pepper"
		else:
			tell = {"kind": "hoover", "shape": "line", "from": band.from, "dir": dir, "len": float(band.len),
				"size": Vector2(float(band.len), Deep.HOOVER_W)}
	if kind == "pepper":
		var a := float(s.a) * TAU
		var c := Vector3(hp.x + cos(a) * Deep.PEPPER_OFF, 0.0, hp.z + sin(a) * Deep.PEPPER_OFF)
		tell = {"kind": "pepper", "shape": "circle", "from": c, "dir": Vector3.FORWARD, "len": 0.0, "size": Vector2(Deep.PEPPER_R, 0.0)}
	tell["t"] = 0.0
	tell["secs"] = secs
	tell["went"] = false
	tell["hit"] = {}
	live = tell
	stats.tells += 1
	var args := [tell.kind, tell.from, tell.dir, tell.size, secs]
	show_tell(args)
	main.net.event("deep_tell", args)
	if not _told.has(tell.kind):
		_told[tell.kind] = true
		main._story({"who": String(Deep.KIND_NAMES[tell.kind]), "line": "Watch the floor!" if tell.kind == "hoover" else "Step out!",
			"pic": String(Deep.KIND_PICS[tell.kind]), "color": Deep.HOOVER_COLOR if tell.kind == "hoover" else Deep.PEPPER_COLOR, "duration": 2.5})
	print("Round %d: told %s by P%d (%.1f s)" % [main.round_no, tell.kind, h.index + 1, secs])
	main.run["surprises"] = int(main.run.get("surprises", 0)) + 1


## Free floor from `from` along dir (to the first wall or piece of furniture), up to his reach.
func _free(from: Vector3, dir: Vector3) -> float:
	var reach := Deep.HOOVER_REACH + 0.4
	var hit: Dictionary = main.ray(from, from + dir * reach)
	if hit.is_empty():
		return Deep.HOOVER_REACH
	return maxf(0.0, from.distance_to(hit.position) - 0.4)


## Every machine: draw a tell.
func show_tell(a: Array) -> void:
	var kind := String(a[0])
	var col := Deep.HOOVER_COLOR if kind == "hoover" else Deep.PEPPER_COLOR
	if kind == "hoover":
		rings.shape("line", a[1], a[2], a[3], col, float(a[4]), {"style": "flash", "stay": Deep.HOOVER_ROLL})
	else:
		rings.shape("circle", a[1], a[2], a[3], col, float(a[4]), {"style": "disc", "stay": 0.6})
	main.local_sound("beep", -4.0, 1.4 if kind == "pepper" else 0.9)


func _go() -> void:
	stats.goes += 1
	var args := [live.kind, live.from, live.dir, float(live.len)]
	show_go(args)
	main.net.event("deep_go", args)
	if String(live.kind) == "pepper":
		for p in main.players:
			if not p.is_hiding():
				continue
			if WarnRings.inside("circle", live.from, live.dir, live.size, p.global_position, 0.0):
				if no_sneeze():
					main.popup(p.center() + Vector3.UP * 0.8, "HANKY!", Color(0.85, 0.7, 1.0), false)
					main.net.event("popup", [p.center() + Vector3.UP * 0.8, "HANKY!", Color(0.85, 0.7, 1.0), false])
					continue
				stats.sneezed += 1
				var pos: Vector3 = p.global_position + Vector3.UP * 0.7
				main._achoo(pos, p.index)
				main.net.event("achoo", [pos, p.index])
		print("Round %d: the pepper pot puffs" % main.round_no)
	else:
		print("Round %d: Rumble rolls" % main.round_no)


## Every machine: the surprise goes off (Rumble rolls / the pepper puffs).
func show_go(a: Array) -> void:
	if String(a[0]) == "pepper":
		main.burst((a[1] as Vector3) + Vector3.UP * 0.6, Color(0.55, 0.4, 0.3), 40, 0.12)
		main.local_sound("whoosh", -2.0, 1.4)
		return
	_roll = {"from": a[1], "dir": a[2], "len": float(a[3]), "t": 0.0}
	if _rumble == null or not is_instance_valid(_rumble):
		_rumble = _make_rumble()
		add_child(_rumble)
	_rumble.visible = true
	_rumble.global_position = a[1]
	_rumble.rotation.y = atan2((a[2] as Vector3).x, (a[2] as Vector3).z)
	main.local_sound("engine", -8.0, 1.6)


func _bump(p, dir: Vector3) -> void:
	stats.bumped += 1
	var side := Vector3(-dir.z, 0.0, dir.x)
	var rel: Vector3 = p.global_position - (live.from as Vector3)
	if side.dot(rel) < 0.0:
		side = -side
	if p.prop_kind >= 0:
		main.set_disguise(p, -1)
	var push := side * Deep.HOOVER_PUSH
	on_bump(p.index, push)
	main.net.event("deep_bump", [p.index, push])
	main.popup(p.center() + Vector3.UP * 0.7, "BUMP!", Deep.HOOVER_COLOR, false)
	main.net.event("popup", [p.center() + Vector3.UP * 0.7, "BUMP!", Deep.HOOVER_COLOR, false])
	main.sound("boing", -4.0, 1.3)
	print("Round %d: Rumble bumps P%d" % [main.round_no, p.index + 1])


## The machine that moves player i: a little shove sideways (player.gd adds it for KNOCK_T).
func on_bump(i: int, push: Vector3) -> void:
	if i >= main.players.size():
		return
	var p = main.players[i]
	if p.remote or p.ghost:
		return
	p.set_meta("knock", push)
	p.set_meta("knock_t", Deep.KNOCK_T)


## Host, the round is over: who picks the next gift, the kennel.
func round_over(seeker_won: bool) -> void:
	rings.clear()
	live = {}
	if main.solo_round:
		last_loser = "seeker"
	else:
		last_loser = "hider" if seeker_won else "seeker"
	var before := Deep.kennel_stage(kennel_rounds)
	kennel_rounds += 1
	main.save.data["kennel"] = kennel_rounds
	main.save.mark_dirty()
	var after := Deep.kennel_stage(kennel_rounds)
	if after > before:
		var piece := String(Deep.KENNEL_STEPS[after - 1][1])
		main._story_later(4.0, {"who": "PIP'S KENNEL", "line": String(Deep.KENNEL_NAMES[piece]), "pic": "kennel", "color": Color(0.95, 0.72, 0.42), "duration": 3.5})
		print("Round %d: Pip's kennel grows a %s (%d rounds)" % [main.round_no, piece, kennel_rounds])


# --- Net ------------------------------------------------------------------------------------

func pack() -> Array:
	var tk: Array = []
	for k in takes:
		tk.append([int(k), int(takes[k])])
	return [mode, gift, gift_side, stage, choices, tk, snappedf(stage_t, 0.1), season, kennel_rounds, bubbles.keys()]


func unpack(a: Array) -> void:
	if a.size() < 10:
		return
	mode = String(a[0])
	gift = String(a[1])
	gift_side = String(a[2])
	stage = String(a[3])
	choices = (a[4] as Array).duplicate()
	takes.clear()
	for e in a[5]:
		takes[int(e[0])] = int(e[1])
	stage_t = float(a[6])
	season = String(a[7])
	kennel_rounds = int(a[8])
	bubbles.clear()
	for i in a[9]:
		bubbles[int(i)] = true


func apply_event(kind: String, args: Array) -> bool:
	match kind:
		"deep_tell":
			show_tell(args)
		"deep_go":
			show_go(args)
		"deep_bump":
			on_bump(int(args[0]), args[1])
		_:
			return false
	return true


# --- Every machine, every frame ----------------------------------------------------------------

func _process(delta: float) -> void:
	if main == null or not main.ready_to_play:
		return
	_show_orbs()
	_update_rumble(delta)
	_update_bubbles()
	_dress()


func _show_orbs() -> void:
	var key := "%s|%s|%d" % [stage, str(choices), main.map_idx]
	if stage == "" or main.phase != "pick":
		if orbs.showing():
			orbs.clear()
		_shown = ""
		return
	if key != _shown:
		_shown = key
		var entries: Array = []
		for id in choices:
			if stage == "mode":
				var m := PickOrbs.mode(String(id))
				entries.append({"id": id, "name": String(m.name), "pic": String(m.pic), "color": m.color})
			else:
				var g := Deep.gift(String(id))
				entries.append({"id": id, "name": String(g.name), "pic": String(g.pic), "color": g.color})
		var spots := Deep.pick_spots(main.md())
		orbs.show_orbs(stage, entries, Vector3.ZERO, Deep.PICK_GAP, Deep.PICK_Y, {"at": spots, "scale": 0.55, "touch": Deep.PICK_TOUCH,
			"pop": true, "two_lines": true, "label_y": -0.9, "for_others": stage == "gift" and gift_side == "hider"})
	var cols := {}
	for p in main.players:
		cols[p.index] = p.color
	orbs.show_takers(takes, cols)


func _make_rumble() -> Node3D:
	var b := MeshKit.Builder.new()
	b.cylinder(0.36, 0.38, 0.2, MeshKit.at(Vector3(0, 0.14, 0)), Color(0.25, 0.75, 0.95), 18)
	b.cylinder(0.3, 0.36, 0.08, MeshKit.at(Vector3(0, 0.28, 0)), Color(0.85, 0.92, 1.0), 18)
	b.cylinder(0.39, 0.39, 0.05, MeshKit.at(Vector3(0, 0.04, 0)), Color(0.3, 0.3, 0.35), 18)
	for s in [-1.0, 1.0]:
		b.sphere(0.07, MeshKit.at(Vector3(0.13 * s, 0.24, 0.3)), Color(1, 1, 1), 8)
		b.sphere(0.035, MeshKit.at(Vector3(0.13 * s, 0.25, 0.36)), Color(0.08, 0.08, 0.1), 6)
	b.sphere(0.05, MeshKit.at(Vector3(0, 0.36, 0)), Color(1.0, 0.4, 0.3), 8)
	var n := MeshKit.instance(b.build(), false)
	n.name = "Rumble"
	return n


func _update_rumble(delta: float) -> void:
	if _roll.is_empty() or _rumble == null or not is_instance_valid(_rumble):
		return
	_roll.t = float(_roll.t) + delta
	var k := clampf(float(_roll.t) / Deep.HOOVER_ROLL, 0.0, 1.0)
	_rumble.global_position = (_roll.from as Vector3) + (_roll.dir as Vector3) * float(_roll.len) * k + Vector3.UP * absf(sin(float(_roll.t) * 18.0)) * 0.02
	if float(_roll.t) > Deep.HOOVER_ROLL + 0.4:
		_rumble.visible = false
		_roll = {}


## BUBBLE: a see-through ball round every hider who still has one (everyone sees it: it's fair).
func _update_bubbles() -> void:
	for i in _bubble_nodes.keys():
		var gone: bool = not bubbles.has(i) or i >= main.players.size() or not main.players[i].is_hiding() or main.phase == "over"
		if gone:
			if is_instance_valid(_bubble_nodes[i]):
				_bubble_nodes[i].queue_free()
			_bubble_nodes.erase(i)
	for i in bubbles:
		if _bubble_nodes.has(i) or i >= main.players.size() or not main.players[i].is_hiding():
			continue
		var mi := MeshInstance3D.new()
		var sm := SphereMesh.new()
		sm.radius = 0.62
		sm.height = 1.24
		sm.radial_segments = 16
		sm.rings = 8
		mi.mesh = sm
		var m := MeshKit.material(Color(0.6, 0.9, 1.0), 0.6).duplicate() as StandardMaterial3D
		m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		m.albedo_color.a = 0.22
		mi.material_override = m
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		mi.position = Vector3.UP * 0.5
		main.players[i].add_child(mi)
		_bubble_nodes[i] = mi


# --- Seasons and Pip's kennel ----------------------------------------------------------------

func _dress() -> void:
	var wr: Node3D = main.world_root
	if wr == null or not is_instance_valid(wr):
		return
	var key := "%d|%s|%s|%d|%d" % [main.map_idx, str(main.map_spec.get("seed", 0)), season, Deep.kennel_stage(kennel_rounds), wr.get_instance_id()]
	if key == _dress_key:
		return
	_dress_key = key
	if _dressed != null and is_instance_valid(_dressed):
		_dressed.queue_free()
	_dressed = Node3D.new()
	_dressed.name = "SeasonAndKennel"
	wr.add_child(_dressed)
	var sd := Deep.season_data(season)
	var b := MeshKit.Builder.new()
	var spots := season_spots(main.map_idx, main.map_spec)
	for i in spots.size():
		SeasonKit.prop(b, season, spots[i][0], i, 0.9, spots[i][1])
	if main.map_idx == 0:
		_kennel(b)
	if not b.is_empty():
		_dressed.add_child(MeshKit.instance(b.build(), false))
	var drift := drift_box(main.map_idx, main.map_spec)
	if not drift.is_empty():
		_dressed.add_child(SeasonKit.drift(sd.drift, season, drift))


## [[position, facing], ...] for the season's props: the house's garden fence (clear of everything in the garden),
## the castle courtyard's corners, the spaceship's mess hall corners.
static func season_spots(map_i: int, spec: Dictionary) -> Array:
	if map_i == 1:
		return [[Vector3(-2.4, 0, -2.4), Vector3(1, 0, 1)], [Vector3(2.4, 0, -2.4), Vector3(-1, 0, 1)]]
	if map_i == 2:
		return [[Vector3(-2.5, 0, 6.4), Vector3(0.5, 0, -1)]]
	var g := HouseScript.house(spec)
	var garden: Rect2
	for rm in g.get("rooms_info", []):
		if String(rm.get("type", "")) == "garden":
			garden = rm.inner
	if garden.size == Vector2.ZERO:
		return []
	var gside := int(g.get("gside", 1))
	var fx := garden.end.x - 0.55 if gside > 0 else garden.position.x + 0.55
	var avoid: Array = []
	for pc in g.pieces:
		avoid.append(HouseGen.footprint(pc).grow(0.45))
	var pts: Array = (g.hide_spots as Array) + (g.star_spots as Array) + (g.get("party", []) as Array)
	var out: Array = []
	var z := -HouseGen.HALF_Z + 1.0
	while z <= HouseGen.HALF_Z - 1.0 and out.size() < 4:
		var p := Vector3(fx, 0.0, z)
		var ok := true
		for r in avoid:
			if (r as Rect2).has_point(Vector2(p.x, p.z)):
				ok = false
		for q in pts:
			if q is Vector3 and Vector2((q as Vector3).x - p.x, (q as Vector3).z - p.z).length() < 1.0:
				ok = false
		if ok:
			out.append([p, Vector3(-gside, 0, 0)])
			z += 2.6
		else:
			z += 0.5
	return out


static func drift_box(map_i: int, spec: Dictionary) -> Dictionary:
	if map_i == 1:
		return {"at": Vector3(0, 5.5, 0), "box": Vector3(2.8, 0.4, 2.8), "amount": 50}
	if map_i == 2:
		return {}
	var g := HouseScript.house(spec)
	for rm in g.get("rooms_info", []):
		if String(rm.get("type", "")) == "garden":
			var r: Rect2 = rm.rect
			return {"at": Vector3(r.get_center().x, 5.0, r.get_center().y), "box": Vector3(r.size.x * 0.5, 0.4, r.size.y * 0.5), "amount": 90}
	return {}


## PIP'S KENNEL pieces the family has built (Deep.KENNEL_STEPS), around his kennel in the garden.
func _kennel(b: MeshKit.Builder) -> void:
	var g := HouseScript.house(main.map_spec)
	var kn := {}
	for pc in g.pieces:
		if pc.k == "kennel":
			kn = pc
	if kn.is_empty():
		return
	var n: Vector3 = kn.n
	var frame := Transform3D(Basis(HouseGen.along(n), Vector3.UP, n), kn.o)  # (map_house.gd _xf: the kennel's own frame)
	var at := func(local: Vector3, sc := Vector3.ONE, rot := Vector3.ZERO) -> Transform3D:
		return frame * MeshKit.at(local, sc, rot)
	var stage := Deep.kennel_stage(kennel_rounds)
	for k in stage:
		match String(Deep.KENNEL_STEPS[k][1]):
			"flag":
				b.cylinder(0.02, 0.02, 0.7, at.call(Vector3(0.0, 1.45, 0.5)), Color(0.45, 0.32, 0.2), 6)
				b.box(Vector3(0.03, 0.2, 0.32), at.call(Vector3(0.0, 1.68, 0.67)), Color(1.0, 0.85, 0.3))
			"bowl":
				b.cylinder(0.15, 0.12, 0.1, at.call(Vector3(-0.75, 0.05, 1.2)), Color(1.0, 0.45, 0.55), 12)
				b.box(Vector3(0.16, 0.03, 0.05), at.call(Vector3(-0.75, 0.12, 1.2)), Color(0.98, 0.95, 0.88))
			"flowers":
				for s in [-1.0, 1.0]:
					b.cylinder(0.14, 0.11, 0.2, at.call(Vector3(0.75 * s, 0.1, 0.25)), Color(0.55, 0.32, 0.18), 8)
					for f in 3:
						b.sphere(0.06, at.call(Vector3(0.75 * s + (f - 1) * 0.07, 0.28 + 0.03 * (f % 2), 0.25)), [Color(1.0, 0.4, 0.6), Color(1, 1, 1), Color(1.0, 0.85, 0.3)][f], 6)
			"bone":
				b.box(Vector3(0.36, 0.08, 0.04), at.call(Vector3(0.0, 0.88, 1.03)), Color(0.98, 0.95, 0.88))
				for s in [-1.0, 1.0]:
					for u in [-1.0, 1.0]:
						b.sphere(0.05, at.call(Vector3(0.18 * s, 0.88 + 0.04 * u, 1.03)), Color(0.98, 0.95, 0.88), 6)
			"porch":
				for s in [-1.0, 1.0]:
					b.cylinder(0.03, 0.03, 1.0, at.call(Vector3(0.62 * s, 0.5, 1.35)), Color(0.55, 0.38, 0.22), 6)
				b.box(Vector3(1.4, 0.05, 0.5), at.call(Vector3(0.0, 1.02, 1.2)), Color(0.85, 0.3, 0.25))
			"lights":
				for f in 7:
					b.sphere(0.035, at.call(Vector3(-0.55 + f * 0.183, 0.78 + 0.05 * sin(f * 1.3), 1.06)), [Color(1.0, 0.4, 0.4), Color(1.0, 0.9, 0.3), Color(0.4, 0.8, 1.0)][f % 3], 6)
			"tower":
				b.cylinder(0.2, 0.22, 1.5, at.call(Vector3(0.85, 0.75, 0.3)), Color(0.85, 0.3, 0.25), 10)
				b.cone(0.28, 0.45, at.call(Vector3(0.85, 1.72, 0.3)), Color(0.45, 0.3, 0.2), 10)
			"gold":
				for s in [-1.0, 1.0]:
					b.box(Vector3(0.66, 0.03, 1.12), at.call(Vector3(0.27 * s, 1.02, 0.5), Vector3.ONE, Vector3(0, 0, 0.65 * s)), Color(1.0, 0.82, 0.25))
				b.sphere(0.08, at.call(Vector3(0.0, 1.26, 0.5)), Color(1.0, 0.9, 0.35), 8)
