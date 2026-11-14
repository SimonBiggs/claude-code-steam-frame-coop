extends Node
## PICK FLOW: the ONE team pick every game runs on its pick orbs (core/pick_orbs.gd draws them). A game's picks.gd
## `extends "res://core/pick_flow.gd"` and keeps only its real differences; the flow is the same everywhere:
##   "mode"  GENTLE / BRAVE / HARD once a session; "gift" (or a game's own word) before later rounds.
##   begin -> start(): the host / local machine puts the orbs up (show_row on every machine via the sticky "orbs" event
##     or net state: a machine joining mid-pick sees them too).
##   tick(): t counts UP (a loading hitch never eats the wait: at most 0.1 s a frame). After `open` seconds a taker
##     that MOVES INTO an orb and stays dwell_for(kind) seconds takes it for the team. One already in an orb when they
##     popped up (RESTING), or one that vanished and came back inside, must leave and come in again: a glove resting
##     there or a boat parked under one never picks by itself, a hand sweeping past never picks.
##   Nobody in wait_for() seconds (x wait_scale)? The middle orb (it glows brightest): a little one is never stuck.
##   take(i, slot) -> take_fx on every machine (a dot in the taker's colour, the game's fx) -> after `after` seconds
##   _finish(): history [stage, option, slot], the orbs go (publish(orbs_off())), on_done(stage, option, slot).
## A game's differences, as explicit options / overrides (never its own copy of the flow: tests/shared_picks_test.gd):
##   vars (set in _init): after, open, waits {stage: s}, wait_scale, hand_r, foot_r, hand_dwell, foot_dwell, sync
##     ("event": net.event("orbs") | "state": net.state_set("orbs")), orb_layer
##   begin(...)            its own args: where the orbs go -> start(stage, opts, done), show_row(...), publish([...])
##   show_row(...)         every machine: its own look (PickOrbs opts)
##   takers()              {id: [point, slot, kind]} who can reach into an orb this frame (kind "hand" = a VR glove)
##   orb_at(kind, point)   which orb that point is in (default: "hand" nearest_hit(hand_r), else at_point(foot_r))
##   dwell_for(kind)       seconds to stay (default "hand" hand_dwell, else foot_dwell; 0 = on entering: a fly-through)
##   wait_for()            seconds before nobody chose (default waits[stage])
##   follow(delta)         every frame before picking (a VR row following the head; call reset_dwell() if it moved)
##   extra_pick()          [orb, slot] or [] every frame (a stick press, a CPU's own choice ...: it checks `open` itself);
##                         shots / clicks call take() directly after can_take()
##   passed()              true: nobody chose now (Dragon Rider flew past the row)
##   slot_color(slot), fx(i, slot, at, color)   every machine: the taker's colour, sound / burst / haptics
##   orbs_off()            the "orbs" payload when they go (each game keeps its own shape on the wire)
##   send_take(i, slot), publish(payload), closed()   a game with its own transport (Party Board fx, Roller Coaster state)
## HUD STRIPS (pictures + buttons on each local screen, Rhythm Band / Roller Coaster): strip(), layout_strip(), dim_strip().
## EVERYONE VOTES (`vote = true` in _init; Hide & Seek, Elemental Bender, Snowball Blitz, Duo Arena): a taker's dwell (or
##   a shot / press through choose(i, slot)) records THAT PLAYER'S vote (one per slot; moving to another orb changes
##   it), shown as a dot in their colour on every machine (net state "pick_votes" {slot: orb}). It finishes once every
##   voter (voters(): default the slots in takers()) has voted and vote_hold seconds passed with no change, or the
##   wait runs out; the most votes wins, a tie goes to tie_pick() (tie_rule "middle": the default orb if tied, else
##   the tied one nearest it; "gentler": the gentlest mode on a "mode" stage). Nobody voted: the default as always.
##   One player alone: their vote ends it after vote_hold. No voters at all for empty_wait seconds (>= 0): the default.
##   history gets [stage, option, slot, {slot: orb}], net state "pick_result" [stage, options, votes, winner] (bots:
##   BotKit.check_votes). A game never counts votes itself (tests/shared_picks_test.gd).

const PickOrbs := preload("res://core/pick_orbs.gd")
const Party := preload("res://core/party.gd")
const StoryCard := preload("res://core/story_card.gd")

const RESTING := 99  # inside[id]: in an orb when they opened (or came back inside): never a pick until it leaves
const HAND_DWELL := 0.3  # seconds a VR glove must stay in an orb
const FOOT_DWELL := 0.15  # seconds a walker / boat / cursor must stay under one

var main
var orbs: PickOrbs
var stage := ""  # host / local: "" | "mode" | "gift" | a game's own stage
var options: Array = []  # host / local: what each orb means
var spots: Array = []  # the orbs' places (each game says in what space)
var t := 0.0  # seconds the orbs have been up
var chosen := -1
var chosen_by := -1
var taker := ""  # the takers() id that took it ("" = a shot, a press, nobody)
var done_t := 0.0
var on_done: Callable  # host / local: (stage, option, slot)
var history: Array = []  # [stage, option, slot] (telemetry, bots)
var inside := {}  # taker id -> orb index it is in now (-1 none, RESTING)
var dwell := {}  # taker id -> seconds in that orb

# Options (a game sets them in _init):
var after := 1.1  # seconds the taken orb shows its dot before the orbs go
var open := 0.8  # seconds after the orbs pop up before they can be taken
var waits := {"mode": 14.0, "gift": 12.0}
var wait_default := 12.0
var wait_scale := 1.0  # bots: shorter waits
var hand_r := 0.1
var foot_r := -1.0  # (-1: the orbs' own reach, PickOrbs opts touch x scale)
var hand_dwell := HAND_DWELL
var foot_dwell := FOOT_DWELL
var sync := "event"  # "event": the sticky net event "orbs" | "state": net state "orbs"
var orb_layer := 0  # the orbs' collision layer (0: nothing physical bumps into them)
var vote := false  # everyone votes (see the header) instead of the first taker deciding
var vote_hold := 0.6  # seconds after the last voter voted (no change) before it closes
var tie_rule := "middle"  # "middle" | "gentler" (mode stages: the gentlest tied mode); or override tie_pick()
var empty_wait := -1.0  # vote: nobody can vote for this long -> the default (-1: wait the whole time)

# Vote state (host / local):
var votes := {}  # slot -> orb index
var _held := 0.0
var _empty := 0.0
var _vote_key := ""  # every machine: the vote dots drawn


func _ready() -> void:
	name = "Picks"
	orbs = make_orbs()
	if orbs.get_parent() == null:
		orbs.collision_layer = orb_layer
		orbs_parent().add_child(orbs)
	if vote:
		get_tree().process_frame.connect(_show_votes)


## The orbs this flow draws on (default: its own). A game whose other picks (each player's own) share one row
## returns that PickOrbs.
func make_orbs() -> PickOrbs:
	return PickOrbs.new()


## Where the orbs live (default main).
func orbs_parent() -> Node:
	return main


func active() -> bool:
	return stage != ""


func showing() -> bool:
	return not orbs.orbs.is_empty()


## Host / local, from the game's begin(): a new pick (then the game shows its row and publishes it).
func start(new_stage: String, opts: Array, done: Callable) -> void:
	stage = new_stage
	options = opts
	on_done = done
	t = 0.0
	chosen = -1
	chosen_by = -1
	taker = ""
	done_t = 0.0
	reset_dwell()
	votes = {}
	_held = 0.0
	_empty = 0.0
	if vote:
		_share_votes()
	print("PICKS %s: %s" % [new_stage, opts])


## The orbs moved (a refit, a row following the head): everyone must move in again.
func reset_dwell() -> void:
	inside = {}
	dwell = {}


## Host / local: tell every machine what the orbs are now.
func publish(payload: Array) -> void:
	if sync == "state":
		if main.net.mode != "client":
			main.net.state_set("orbs", payload)
	else:
		main.net.event("orbs", payload)


func orbs_off() -> Array:
	return ["", [], []]


## Orb i's middle in the world (bots aim there), INF if none.
func orb_position(i: int) -> Vector3:
	if i < 0 or i >= orbs.orbs.size() or not is_instance_valid(orbs.orbs[i]) or not (orbs.orbs[i] as Node3D).is_inside_tree():
		return Vector3.INF
	var o = orbs.orbs[i]
	return o.icon.global_position if o.icon != null and o.icon.is_inside_tree() else (o as Node3D).global_position


func wait_for() -> float:
	return float(waits.get(stage, wait_default))


func _wait() -> float:
	return wait_for() * wait_scale


## Seconds left to pick.
func left() -> float:
	return maxf(0.0, _wait() - t) if stage != "" and chosen < 0 else 0.0


## A shot / press / click may take one now.
func can_take() -> bool:
	return stage != "" and chosen < 0 and t >= open


func default_pick() -> int:
	return options.size() / 2  # the middle one (it glows brightest)


## Host / local, every frame while the orbs are up.
func tick(delta: float) -> void:
	if stage == "":
		return
	if chosen >= 0:
		done_t += delta
		if done_t >= after:
			_finish()
		return
	t += minf(delta, 0.1)  # (a loading hitch never eats the wait)
	follow(delta)
	var points := takers()
	var picks := _dwell_picks(delta, points)
	var extra := extra_pick() if picks.is_empty() or vote else []
	if extra.size() == 2:
		picks.append([int(extra[0]), int(extra[1]), ""])
	if vote:
		_vote_tick(delta, picks, points)
		return
	if not picks.is_empty():
		taker = String(picks[0][2])
		take(int(picks[0][0]), int(picks[0][1]))
		return
	if t > _wait() or passed():
		take(default_pick(), -1)  # nobody took one: the middle one


## This frame's dwell picks ([[orb, slot, taker id], ...]): takers that moved into an orb and stayed dwell_for(kind)
## seconds (each once per entering).
func _dwell_picks(delta: float, points: Dictionary) -> Array:
	for id in inside.keys():
		if not points.has(id):  # gone (carrying something, left the game): back inside is resting again
			inside.erase(id)
			dwell.erase(id)
	var got: Array = []
	for id in points:
		var p: Array = points[id]
		var kind := String(p[2]) if p.size() > 2 else "foot"
		var i := orb_at(kind, p[0])
		if not inside.has(id):  # where it was when the orbs came up: resting in one is never a pick until it leaves
			inside[id] = RESTING if i >= 0 else -1
		var before := int(inside[id])
		if before == RESTING:
			inside[id] = RESTING if i >= 0 else -1
			dwell[id] = 0.0
			continue
		var was := 0.0 if i != before else float(dwell.get(id, 0.0))
		dwell[id] = was
		inside[id] = i
		if i >= 0 and t >= open:
			dwell[id] = was + delta
			var need := dwell_for(kind)
			if float(dwell[id]) >= need and (was < need or i != before):
				got.append([i, int(p[1]), String(id)])
	return got


# --- Everyone votes (vote = true) ---------------------------------------------------------------------------------

## The slots that may vote now (default: everyone in takers(), plus whoever already voted). A game whose players
## can't all reach the orbs (or pick by shooting) says who counts; nobody who can't reach is ever waited for.
func voters(points: Dictionary) -> Array:
	var out: Array = []
	for id in points:
		var p: Array = points[id]
		var s := int(p[1])
		if s >= 0 and not out.has(s):
			out.append(s)
	for s in votes:
		if not out.has(int(s)):
			out.append(int(s))
	return out


## Host / local: slot votes for orb i (a shot, a press, a click: the same as a dwell). Not a vote mode: takes it.
func choose(i: int, slot: int) -> void:
	if not can_take() or i < 0 or i >= options.size():
		return
	if not vote:
		take(i, slot)
		return
	_cast(i, slot)


func _cast(i: int, slot: int) -> void:
	if slot < 0 or int(votes.get(slot, -1)) == i:
		return
	votes[slot] = i
	_held = 0.0
	_share_votes()
	vote_fx(i, slot)
	print("VOTE %s: P%d -> %d (%s) %s" % [stage, slot + 1, i, str(options[i]), str(votes)])


func _vote_tick(delta: float, picks: Array, points: Dictionary) -> void:
	for pk in picks:
		_cast(int(pk[0]), int(pk[1]))
	var who := voters(points)
	_empty = _empty + delta if who.is_empty() else 0.0
	var all := not who.is_empty()
	for s in who:
		if not votes.has(s):
			all = false
	_held = _held + delta if all else 0.0
	var timeout := t > _wait() or passed() or (empty_wait >= 0.0 and _empty >= empty_wait and votes.is_empty())
	if _held >= vote_hold or timeout:
		var win := winner_of(stage, options, votes, default_pick())
		var by := -1
		for s in votes:  # the first voter of the winning orb shows the take (-1: nobody chose it)
			if int(votes[s]) == win and (by < 0 or int(s) < by):
				by = int(s)
		if main.net.mode != "client":
			main.net.state_set("pick_result", [stage, options.duplicate(), votes.duplicate(), win])
		print("PICK %s: votes %s -> %d (%s)" % [stage, str(votes), win, str(options[win])])
		take(win, by)


## The winning orb for these votes ({slot: orb}): the most votes; a tie goes to tie_pick(); none: def.
func winner_of(st: String, opts: Array, vs: Dictionary, def: int) -> int:
	if vs.is_empty():
		return def
	var count := {}
	for s in vs:
		count[int(vs[s])] = int(count.get(int(vs[s]), 0)) + 1
	var most := 0
	for i in count:
		most = maxi(most, int(count[i]))
	var tied: Array = []
	for i in count:
		if int(count[i]) == most:
			tied.append(int(i))
	tied.sort()
	return int(tied[0]) if tied.size() == 1 else tie_pick(st, opts, tied, def)


## A tie between orbs `tied`: "gentler" on a mode stage takes the gentlest mode, else the default orb when it is
## tied, else the tied one nearest it (the lower one when two are as near).
func tie_pick(st: String, opts: Array, tied: Array, def: int) -> int:
	if tie_rule == "gentler" and st == "mode":
		var best := -1
		var best_r := 99
		for i in tied:
			var r := PickOrbs.MODE_IDS.find(String(PickOrbs.mode(str(opts[i])).get("id", "")))
			if r >= 0 and r < best_r:
				best_r = r
				best = int(i)
		if best >= 0:
			return best
	if tied.has(def):
		return def
	var near := int(tied[0])
	for i in tied:
		if absi(int(i) - def) < absi(near - def):
			near = int(i)
	return near


## Host / local: a vote was cast (the game's little sound / burst; the dot comes by itself).
func vote_fx(_i: int, _slot: int) -> void:
	pass


func _share_votes() -> void:
	if main.net.mode != "client":
		main.net.state_set("pick_votes", votes.duplicate())


## Every machine, every frame (vote mode): the vote dots from net state "pick_votes".
func _show_votes() -> void:
	if not is_instance_valid(orbs) or orbs.orbs.is_empty() or main == null or main.net == null:
		_vote_key = ""
		return
	var vs: Dictionary = main.net.state_get("pick_votes", {})
	var key := str(vs) + str(orbs.orbs.size()) + str(orbs.orbs[0].get_instance_id())
	if key == _vote_key:
		return
	_vote_key = key
	var cols := {}
	for s in vs:
		cols[s] = slot_color(int(s))
	orbs.show_takers(vs, cols)


## {id: [point, slot, kind]}: who can reach into an orb this frame (host / local).
func takers() -> Dictionary:
	return {}


func orb_at(kind: String, point: Variant) -> int:
	if kind == "hand":
		return orbs.nearest_hit(point, hand_r)
	return orbs.at_point(point, foot_r)


func dwell_for(kind: String) -> float:
	return hand_dwell if kind == "hand" else foot_dwell


func follow(_delta: float) -> void:
	pass


func extra_pick() -> Array:
	return []


func passed() -> bool:
	return false


## A VR row in front of the head follows it: the head stepped 30 cm away or turned more than ~25 degrees.
static func head_moved(was: Transform3D, now: Transform3D) -> bool:
	var f_now := (-now.basis.z).slide(Vector3.UP)
	var f_was := (-was.basis.z).slide(Vector3.UP)
	var turned := f_now.length() > 0.2 and f_was.length() > 0.2 and f_now.normalized().dot(f_was.normalized()) < 0.9
	return turned or now.origin.distance_to(was.origin) >= 0.3


## Host / local: orb i taken by slot (-1: nobody chose, the middle one).
func take(i: int, slot: int) -> void:
	if stage == "" or chosen >= 0 or i < 0 or i >= options.size():
		return
	chosen = i
	chosen_by = slot
	send_take(i, slot)
	print("PICK %s: %s took %d (%s)" % [stage, "nobody" if slot < 0 else "P%d" % (slot + 1), i, str(options[i])])


## Host / local: show the take here and on every machine.
func send_take(i: int, slot: int) -> void:
	take_fx(i, slot)
	main.net.event("take", [i, slot])


## Every machine: a dot in the taker's colour circles orb i, then the game's sound / burst / haptics.
func take_fx(i: int, slot: int) -> void:
	var col := slot_color(slot) if slot >= 0 else Color(1, 1, 1)
	var voted := false
	if vote and main != null and main.net != null:
		for s in (main.net.state_get("pick_votes", {}) as Dictionary).values():
			voted = voted or int(s) == i
	var at := orbs.cheer(i) if voted else orbs.take(i, col)  # (its voters' dots are there already)
	fx(i, slot, at, col)


func slot_color(slot: int) -> Color:
	return Party.COLORS[slot % Party.COLORS.size()]


func fx(_i: int, _slot: int, _at: Vector3, _col: Color) -> void:
	pass


func closed() -> void:
	orbs.clear()


func _finish() -> void:
	var st := stage
	var opt: Variant = options[chosen]
	var by := chosen_by
	history.append([st, str(opt), by, votes.duplicate()] if vote else [st, str(opt), by])
	stage = ""
	options = []
	spots = []
	closed()
	publish(orbs_off())
	if vote:
		votes = {}
		_share_votes()
	if on_done.is_valid():
		on_done.call(st, opt, by)


# --- HUD strips: the picks' pictures (and the button for each) on a local screen --------------------------------

## A strip of entries in `order` (orb indices left to right), buttons[k] under the k-th (none if buttons is empty).
static func strip(entries: Array, order: Array, buttons: Array) -> HBoxContainer:
	var box := HBoxContainer.new()
	box.name = "PickStrip"
	box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	box.alignment = BoxContainer.ALIGNMENT_CENTER
	for k in order.size():
		var i: int = order[k]
		var e: Dictionary = entries[i]
		var col: Color = e.get("color", Color.WHITE)
		var v := VBoxContainer.new()
		v.set_meta("orb", i)
		v.mouse_filter = Control.MOUSE_FILTER_IGNORE
		v.alignment = BoxContainer.ALIGNMENT_CENTER
		var pic := StoryCard.picture(String(e.get("pic", "star")), 96.0, col)
		pic.mouse_filter = Control.MOUSE_FILTER_IGNORE
		v.add_child(pic)
		var nm := Label.new()
		nm.text = String(e.get("name", ""))
		nm.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		nm.add_theme_font_size_override("font_size", 22)
		nm.add_theme_color_override("font_color", col.lightened(0.35))
		nm.add_theme_color_override("font_outline_color", PickOrbs.LABEL_OUTLINE)
		nm.add_theme_constant_override("outline_size", 8)
		v.add_child(nm)
		if k < buttons.size():
			var bt := Label.new()
			bt.text = String(buttons[k])
			bt.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
			bt.add_theme_font_size_override("font_size", 30)
			bt.add_theme_color_override("font_color", Color(1, 1, 1))
			bt.add_theme_color_override("font_outline_color", PickOrbs.LABEL_OUTLINE)
			bt.add_theme_constant_override("outline_size", 10)
			v.add_child(bt)
		box.add_child(v)
	box.add_theme_constant_override("separation", 28)
	return box


## Centred, 30 % down the screen, scaled to its height.
static func layout_strip(hud: Control, box: Control) -> void:
	var area: Vector2 = hud.size
	if area.x < 10.0:
		return
	var s := clampf(area.y / 720.0, 0.45, 1.3)
	box.scale = Vector2(s, s)
	var sz := box.get_combined_minimum_size()
	box.size = sz
	box.position = Vector2((area.x - sz.x * s) * 0.5, area.y * 0.3)


## Orb i was taken: the other pictures fade.
static func dim_strip(box: Control, i: int) -> void:
	if not is_instance_valid(box):
		return
	for c in box.get_children():
		if int(c.get_meta("orb", -1)) != i:
			c.modulate.a = 0.3


## The order of orbs at `points` left to right as seen along `right` (a screen's camera basis.x).
static func order_along(points: Array, right: Vector3) -> Array:
	var keyed: Array = []
	for i in points.size():
		keyed.append([(points[i] as Vector3).dot(right), i])
	keyed.sort_custom(func(a: Array, b: Array) -> bool: return a[0] < b[0])
	var out: Array = []
	for k in keyed:
		out.append(int(k[1]))
	return out
