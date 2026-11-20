extends Node
## FIRST GOAL (a service, core/services.gd): a first-time player sees, within seconds of play starting, WHAT THEY ARE
## and THE ONE THING TO DO FIRST, as a prompt with the right button for their device (TV / Deck pad glyph, VR trigger),
## plus an arrow over the thing to do it to. It fades with a cheer after their first small win and is remembered per
## profile, so it never nags again. Evidence: most arcade rounds ended within 1-4 min (telemetry); a VR guest on
## 2026-11-19 kept asking "What do I do?".
## EVERY PLAYER HAS THEIR OWN (2026-11-20): one "seat" per player. Split screen: each player's card sits in their own
## view (core/split_view.gd views, or a classic game's own per-player SubViewport); players sharing one picture get a
## row of cards, one each, with their name. Each gets their own "Nice one!" on their own first win.
## Networked: the HOST decides (it simulates the game, so it sees every player's wins), publishes them in the net state
## store ("_fg": {"go": play started, "won": {slot: seconds}}), and every machine shows / remembers its own players'.
## Remembered per Steam profile ON THE MACHINE WHERE THE PLAYER SITS (user://first_goals.cfg there): section = profile,
## key "<game>/<device>" for the machine's first player, "<game>/<device>#2".. for the 2nd.. pad on that machine.
## Every game has ONE data file, found by itself (no game code changes):
##   games/<id>/first_goal.gd
##     const GOAL := {
##       "you": "a Balloon Popper",                    # what they are ("you_vr" / "you_tv" when it differs)
##       "do": {"tv": ["A", "Pop the balloon near you!"],         # [button glyph, the one thing to do]
##              "deck": [...],                                    # optional (default: tv)
##              "vr": ["TRIGGER", "Point at a balloon and pull!"]},
##       "start": "phase() == 'play'",       # optional: play has begun (default: no pick / intro / story card up)
##       "rise": "st('score0', 0)",          # the small win: this number goes up (or "done": a true/false expression)
##       "rise_p": "v('hits', [])[p]",       # optional: THIS player's own win (`p` = their slot); see "Whose win"
##       "target": "nearest('balloons')",    # optional: a Node3D / Vector3 to put the arrow over
##       (any of start / rise / done / rise_p / done_p / target / miss may have a "_vr" or "_tv" version)
##       "miss": "v('misses')",              # optional: a rising count of misses (core/rescue.gd struggling signal)
##       "flat_y": 0.5,                      # optional: where the TV / Deck card sits (share of the screen height,
##                                           #   default 0.82) when the game's own UI lives low (answer tiles)
##       "seats": {0: {"you": "the Gunner", "do": ["RT", "..."]}},  # optional: a seat with its own role on TV / Deck
##                                           #   ("as": "vr": that flat seat plays the VR role, so it uses the _vr
##                                           #   expressions; every game whose flat P1 is the VR role needs one: a lone
##                                           #   flat pilot was told "YOU ARE THE ROCKET CREW" and quit, 2026-11-15)
##       "wordless": true, "icon": "star",   # optional: a game made without how-to words on purpose (the family found
##     }                                     #   games too text-driven; its bot fails on words): button glyph + icon
##                                           #   on the TV, only the arrow in VR. Needs a "target" or an "icon".
## Whose win (host): "rise_p"/"done_p" when the data has them; else the player's own core/awards.gd stats going up
## (main.awards: score, hits, finds..., not deaths / damage taken); else the shared "rise"/"done" when only this
## player uses it (the VR player's own rise_vr); else the shared win is credited, after ATTRIBUTE s with no per-player
## sign, to the players who were pressing / steering just then (or to everyone in it, when nobody was).
## Expressions (Godot Expression) run on this node with `main` (the game's main node) and `p` (the player's slot) in
## scope, plus helpers:
##   v(prop, def)  main.get(prop)        st(key, def)  main.net state      phase()  net phase or main.phase
##   count(group)  nodes in a group      nearest(group) / nearest_of(array or dict)  the nearest to the player's camera
##   node(name)    main.find_child(name)  sum(x)  sum of an Array / Dictionary's numbers   local_slot() (= p)
##   aw(p, stat)   the player's core/awards.gd stat
## (Expression gotcha: a ternary inside parentheses doesn't parse; a top-level "a if c else b" does. `device` is in scope.)
## A broken expression is an engine ERROR from res:// (fails every bot), so all game bots check the data.
## Rescue: while the goal waits, core/rescue.gd ticks (time waiting without the win = struggling); a game's "miss"
## counter feeds it too. When help kicks in, the prompt pulses back bigger with its arrow (also after the first win,
## if the misses pile up). tests/first_goal_test.gd fails any game without data, or with missing / broken fields, and
## checks seats, sync and remembering; tests/whack_a_mole_bot.gd (BotKit.check_first_goals) checks split screen and
## networked machines in a real game.
## Telemetry: RUN lines carry fg_secs (seconds to the first win, -1 = never) and fg_dev of this machine's first player,
## fg_n (players here) and fg_won (how many of them won) (core/telemetry.gd).

const UiKit := preload("res://core/ui_kit.gd")
const HudKit := preload("res://core/hud_kit.gd")
const Rescue := preload("res://core/rescue.gd")
const Save := preload("res://core/save.gd")
const Machine := preload("res://core/machine.gd")
const VrViewCheck := preload("res://core/vr_view_check.gd")
const SAVE_PATH := "user://first_goals.cfg"
const NET_KEY := "_fg"
const DEVICES := ["tv", "deck", "vr"]
const REQUIRED := ["you", "do", "rise|done"]
const EXPR_KEYS := ["start", "rise", "done", "rise_p", "done_p", "target", "miss"]
## Seconds play must have been running (no pick / intro / story card) before the prompt shows.
const SETTLE := 0.6
## The prompt waits this long for its win, then shrinks to a corner reminder (rescue still pulses it back).
const SHRINK_AFTER := 40.0
## A shared win with several players on it: seconds to wait for a per-player sign before guessing whose it was.
const ATTRIBUTE := 1.5
## Pressing / steering within this many seconds counts as "was playing just then".
const ACTIVE_WINDOW := 3.0
## Awards stats that are not wins.
const NOT_WINS := ["deaths", "damage_taken", "drops", "falls", "slot", "revived", "best_time", "fastest_answer", "bonks"]
## Seconds of play VR story cards may hold the prompt back (time to read them); then it shows and steps aside.
const STORY_READ := 6.0
## Bands tried in turn: low (under the action), a little higher, then up under the top HUD.
const BANDS := [0.82, 0.66, 0.3]


## One player: their slot, device, progress and prompt.
class Seat:
	var slot := 0
	var idx := 0  ## the n-th player on THIS machine (0 = first; remembering keys); -1 = on another machine
	var local := true
	var device := "tv"
	var state := "wait"  # wait (play not started) / show / done / off (already won before)
	var settle := 0.0
	var play_t := 0.0
	var win_secs := -1.0
	var on_screen_t := -1.0
	var on_screen := false
	var base := 0.0
	var pbase := 0.0
	var aw_base := 0.0
	var miss_base := 0.0
	var rise_last := 0.0
	var shared_t := -1.0  ## seconds since the shared win rose for this seat (waiting to see whose it was)
	var active_t := 99.0  ## seconds since this player last pressed / steered (local party seats)
	var rescue: Rescue = null
	var card: Control = null
	var vr_card: Node3D = null
	var arrow: Node3D = null
	var view: SubViewport = null  ## their own split-screen view (null: the shared screen)
	var shown_in: Object = null  ## where their card last came up (their view, or null = the shared screen); bots check it
	var shown_slot_view := false  ## that card came up while split screen gave them a view of their own
	var layer: CanvasLayer = null  ## our layer inside that view
	var ui: Control = null
	var pulse := 0.0
	var small := false
	var after_t := 0.0
	var band := 0.82
	var band_t := 0.0
	var nice := false  ## "Nice one!" was shown on their card
	var name := ""

var game := ""
var main: Node = null
var data: Dictionary = {}
var seats: Array = []  ## Seat, in slot order
var t := 0.0
var save_path := SAVE_PATH
var _poll := 0.0
var _exprs := {}  # text -> Expression
var _failed := {}  # text -> true (reported once)
var _layer: CanvasLayer = null
var _ui: Control = null
var _cur: Seat = null  ## the seat expressions are evaluated for
var _story_wait := 0.0  ## game seconds play waited for VR story cards
var _story_hit := false  ## the last _blocked() was a VR story card


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS


func _process(delta: float) -> void:
	_poll += delta
	_track_input(delta)
	if _poll >= 0.25:
		var dt := _poll
		_poll = 0.0
		_step(dt)
	_animate(delta)


# --- Finding the game ------------------------------------------------------------------------------------------------

static func game_of(n: Node) -> String:
	if n == null:
		return ""
	var p := n.scene_file_path
	if p.begins_with("res://games/") and p.ends_with("/main.tscn"):
		return p.get_slice("/", 3)
	return ""


func _find_main() -> Node:
	var cs := get_tree().current_scene
	if cs == null:
		return null
	if game_of(cs) != "":
		return cs
	for c in cs.get_children():  # bots: tests/<id>_bot.tscn adds the game's main under itself
		if game_of(c) != "":
			return c
	return null


## The data of a game (empty when it has none).
static func data_of(id: String) -> Dictionary:
	var path := "res://games/%s/first_goal.gd" % id
	if not ResourceLoader.exists(path):
		return {}
	var s := load(path) as GDScript
	if s == null:
		return {}
	var c: Dictionary = s.get_script_constant_map()
	return c.get("GOAL", {})


## Problems with a game's data (tests/first_goal_test.gd): missing file / fields, unparsable expressions.
static func problems_of(id: String) -> Array[String]:
	var out: Array[String] = []
	var d := data_of(id)
	if d.is_empty():
		return ["%s: no games/%s/first_goal.gd with a GOAL (core/first_goal.gd)" % [id, id]]
	if String(d.get("you", "")).strip_edges() == "":
		out.append("%s: no \"you\" (what the player is)" % id)
	for dev in ["tv", "vr"]:
		var has_win := false
		for k in ["rise", "done", "rise_" + dev, "done_" + dev]:
			has_win = has_win or d.has(k)
		if not has_win:
			out.append("%s: no \"rise\" or \"done\" (the small win) for %s" % [id, dev])
	if bool(d.get("wordless", false)) and not d.has("target") and not d.has("icon"):
		out.append("%s: wordless needs a \"target\" (arrow) or an \"icon\"" % id)
	var dd: Dictionary = d.get("do", {})
	for dev in ["tv", "vr"]:
		var pair: Array = dd.get(dev, [])
		if pair.size() != 2 or String(pair[1]).strip_edges() == "":
			out.append("%s: \"do\".%s must be [button, text]" % [id, dev])
		elif String(pair[1]).length() > 44:
			out.append("%s: \"do\".%s text is %d letters (keep it under 45: one glance)" % [id, dev, String(pair[1]).length()])
	var roles: Variant = d.get("seats", {})
	if not (roles is Dictionary):
		out.append("%s: \"seats\" must be {slot: {you, do}}" % id)
	else:
		for slot in roles:
			var r: Dictionary = roles[slot] if roles[slot] is Dictionary else {}
			var rp: Array = r.get("do", ["", "x"])
			if not (slot is int) or rp.size() != 2 or String(rp[1]).strip_edges() == "" or String(rp[1]).length() > 44:
				out.append("%s: \"seats\".%s must be {\"you\": text, \"do\": [button, text under 45 letters]}" % [id, str(slot)])
	for k in d:
		var base := String(k).trim_suffix("_vr").trim_suffix("_tv")
		if base in EXPR_KEYS:
			var e := Expression.new()
			if e.parse(String(d[k]), ["main", "p"]) != OK:
				out.append("%s: \"%s\" doesn't parse: %s" % [id, k, e.get_error_text()])
	return out


## Which games exist (every games/<id>/main.tscn).
static func game_ids() -> Array[String]:
	var out: Array[String] = []
	var dir := DirAccess.open("res://games")
	if dir == null:
		return out
	for d in dir.get_directories():
		if ResourceLoader.exists("res://games/%s/main.tscn" % d) and d != "engine_template":
			out.append(d)
	out.sort()
	return out


# --- Seats: who plays (every machine: its own players; the host: everyone) -------------------------------------------

func _net() -> Object:
	var n: Variant = main.get("net") if main != null else null
	return n as Object if n is Object and is_instance_valid(n) else null


func _mode() -> String:
	var n := _net()
	return String(n.get("mode")) if n != null and n.get("mode") != null else "local"


func _party() -> Object:
	var p: Variant = main.get("party") if main != null else null
	return p as Object if p is Object and is_instance_valid(p) and (p as Object).has_method("local_slots") else null


func _split() -> Object:
	var s: Variant = main.get("split") if main != null else null
	return s as Object if s is Object and is_instance_valid(s) and (s as Object).has_method("viewport") else null


## VR here: a headset (or the fake one) with a camera.
func _vr_here() -> bool:
	if OS.has_environment("BOT_VR") or get_viewport().use_xr or Machine.kind() == "frame":
		return VrViewCheck.vr_camera(get_tree().root) != null
	return false


func _flat_kind() -> String:
	return "deck" if Machine.kind() == "deck" else "tv"


## [slot, local, device] for every player this machine tracks.
func _wanted() -> Array:
	var out: Array = []
	var mode := _mode()
	var party := _party()
	var vr := mode != "client" and _vr_here()
	if party != null:
		if vr:
			out.append([0, true, "vr"])
		var slots: Array = party.call("active_slots") if mode != "client" else party.call("local_slots")
		for s in slots:
			if vr and int(s) == 0:
				continue
			var loc: bool = bool(party.call("is_local", s))
			var dev := _flat_kind()
			if not loc:
				dev = "deck" if String(party.call("machine_kind", s)) == "deck" else "tv"
			out.append([int(s), loc, dev])
		return out
	var players: Variant = main.get("players")
	var cs: Variant = main.get("seats")
	if players is Array and not (players as Array).is_empty() and cs is Object and (cs as Object).has_method("owners"):
		var owners: Dictionary = (cs as Object).call("owners")
		var me := 1
		var n := _net()
		if n != null and n.has_method("my_peer_id"):
			me = int(n.call("my_peer_id"))
		for i in (players as Array).size():
			var pl: Variant = players[i]
			if not (pl is Object) or not is_instance_valid(pl) or (pl as Object).get("active") == false:
				continue
			if mode == "host" and (pl as Object).get("remote") == true and not owners.has(i) and not owners.has(str(i)):
				continue  # a host's seat kept for a TV machine nobody has taken: nobody sits there (Rocket Workshop's crew)
			var owner := int(owners.get(i, owners.get(str(i), 1 if mode != "client" or i == 0 else -1)))
			var loc := owner == me if mode == "client" else (owner == 1 or not owners.has(i))
			if mode == "client" and (not loc or i == 0):
				continue  # (a TV machine never plays seat 0: the host's)
			var dev := _flat_kind() if loc else "tv"
			if loc and (pl as Object).get("vr") == true and vr:
				dev = "vr"
			out.append([i, loc, dev])
		if not out.is_empty():
			return out
	# (no seats known: one player here, as before)
	if vr:
		return [[0, true, "vr"]]
	return [[1 if mode == "client" else 0, true, _flat_kind()]]


func _sync_seats() -> void:
	var want := _wanted()
	var keep: Array = []
	var idx := 0
	for w in want:
		var s: Seat = _seat(int(w[0]))
		if s == null:
			s = Seat.new()
			s.slot = int(w[0])
			s.device = String(w[2])
			s.rescue = Rescue.new()
		s.local = bool(w[1])
		if s.device != String(w[2]):  # (the headset joined late: VR watch)
			_drop_seat_ui(s)
			s.device = String(w[2])
			if s.state == "show" and s.local:
				_cur = s
				_show(s)
				_cur = null
		s.idx = idx if s.local else -1
		if s.local:
			idx += 1
		s.name = _name_of(s.slot)
		keep.append(s)
	for s in seats:
		if not keep.has(s):
			_drop_seat_ui(s)
	keep.sort_custom(func(a: Seat, b: Seat) -> bool: return a.slot < b.slot)
	seats = keep


func _seat(slot: int) -> Seat:
	for s in seats:
		if (s as Seat).slot == slot:
			return s
	return null


func _name_of(slot: int) -> String:
	var party := _party()
	if party != null and party.has_method("name_of"):
		return String(party.call("name_of", slot))
	return "P%d" % (slot + 1)


## Local seats, in order.
func local_seats() -> Array:
	return seats.filter(func(s: Seat) -> bool: return s.local)


# --- The loop -------------------------------------------------------------------------------------------------------

func _step(dt: float) -> void:
	var m := _find_main()
	if m != main:
		_reset()
		main = m
		game = game_of(m)
		if main != null:
			data = data_of(game)
	if main == null or data.is_empty() or not is_instance_valid(main):
		return
	t += dt
	_sync_seats()
	var client := _mode() == "client"
	var host_fg: Dictionary = _host_fg() if client else {}
	for s: Seat in seats:
		_cur = s
		_step_seat(s, dt, _blocked() if s.local else false, client, host_fg)
		_place_arrow(s)
	_cur = null
	if not client:
		_publish()


func _step_seat(s: Seat, dt: float, blocked: bool, client: bool, host_fg: Dictionary) -> void:
	var host_won: bool = client and (host_fg.get("won", {}) as Dictionary).has(str(s.slot))
	match s.state:
		"wait":
			var started := _truthy("start", true) or (client and bool(host_fg.get("go", false)))
			if started and blocked and _story_hit:
				_story_wait += dt
			if (blocked and s.local) or not started:
				s.settle = 0.0
				return
			s.settle += dt
			if s.settle < SETTLE:
				return
			_bases(s)
			if s.local and _remembered(s):
				s.state = "off"
				return
			s.state = "show"
			s.play_t = 0.0
			if host_won:  # (joined after their win: just remember it)
				_win(s, true)
				return
			if s.local:
				print("FIRST GOAL: %s %s P%d shown %.1f s after the game started" % [game, s.device, s.slot + 1, t])
				_show(s)
		"show":
			s.play_t += dt
			if s.local:
				_set_visible(s, not blocked)
				if blocked:
					return
				s.band_t -= dt
				if s.band_t <= 0.0 and s.device != "vr":
					s.band_t = 0.5
					_pick_band(s)
				if not s.on_screen:
					s.on_screen = true
					s.on_screen_t = t
					print("FIRST GOAL: %s %s P%d on screen %.1f s after the game started" % [game, s.device, s.slot + 1, t])
				_feed_rescue(s, dt, true)
			if host_won or (not client and _won(s, dt)):
				_win(s)
			elif s.play_t > SHRINK_AFTER and not s.small and s.local:
				_shrink(s, true)
		"done", "off":
			s.after_t += dt
			if s.local and s.after_t < 90.0 and data.has(_k("miss")):
				_feed_rescue(s, dt, false)


func _bases(s: Seat) -> void:
	s.base = _num("rise")
	s.rise_last = s.base
	s.pbase = _num("rise_p")
	s.aw_base = _aw_sum(s.slot)
	s.miss_base = _num("miss")
	s.shared_t = -1.0


## Host: what this machine decided ("_fg" in the net state store; every machine reads it).
func _publish() -> void:
	var n := _net()
	if n == null or not n.has_method("state_set") or _mode() != "host":
		return
	var won := {}
	var go := false
	for s: Seat in seats:
		go = go or s.state != "wait"
		if s.state == "done":
			won[str(s.slot)] = snappedf(s.win_secs, 0.1)
	var fg := {"go": go, "won": won}
	if n.call("state_get", NET_KEY, null) != fg:
		n.call("state_set", NET_KEY, fg)


func _host_fg() -> Dictionary:
	var x: Variant = st(NET_KEY, {})
	return x if x is Dictionary else {}


func _feed_rescue(s: Seat, dt: float, waiting: bool) -> void:
	if s.rescue == null:
		return
	var r := _num("rise")
	if data.has(_k("rise")) and r > s.rise_last:
		s.rescue.note(true)
	s.rise_last = r
	if data.has(_k("miss")):
		var m := _num("miss")
		while m > s.miss_base and m - s.miss_base < 50:
			s.rescue.note(false)
			s.miss_base += 1.0
		s.miss_base = m
	s.rescue.tick(dt, waiting and not _blocked())
	if s.rescue.crossed():
		_help(s)


## Host / local: did this seat's player get their own first win? (see "Whose win" at the top)
func _won(s: Seat, dt: float) -> bool:
	var explicit := data.has(_k("rise_p")) or data.has(_k("done_p"))
	if data.has(_k("done_p")) and _truthy("done_p", false):
		return true
	if data.has(_k("rise_p")):
		var pr := _num("rise_p")
		if pr > s.pbase + 0.001:
			return true
		s.pbase = minf(s.pbase, pr)  # (a new round reset it)
	var aw := _aw_sum(s.slot)
	if aw > s.aw_base + 0.001:
		return true
	s.aw_base = minf(s.aw_base, aw)
	if explicit:
		return false
	var shared := false
	if data.has(_k("done")) and _truthy("done", false):
		shared = true
	elif data.has(_k("rise")):
		var r := _num("rise")
		shared = r > s.base + 0.001
		if r < s.base:
			s.base = r
	if not shared:
		s.shared_t = -1.0
		return false
	var group := _group(s)
	if group.size() <= 1:
		return true
	if s.shared_t < 0.0:
		s.shared_t = 0.0
	s.shared_t += dt
	if s.shared_t < ATTRIBUTE:
		return false
	# nobody showed their own sign: whoever was playing just then (everyone in it, when nobody was)
	var any_active := false
	for o: Seat in group:
		any_active = any_active or _active(o)
	if _active(s) or not any_active:
		return true
	s.base = _num("rise")
	s.shared_t = -1.0
	return false


## The seats whose shared win is the same expression as this seat's (a VR player's own rise_vr is theirs alone).
func _group(s: Seat) -> Array:
	var mine := _win_text(s)
	var out: Array = []
	var keep := _cur
	for o: Seat in seats:
		_cur = o
		if _win_text(o) == mine:
			out.append(o)
	_cur = keep
	return out


func _win_text(s: Seat) -> String:
	var keep := _cur
	_cur = s
	var text := "%s|%s" % [String(data.get(_k("done"), "")), String(data.get(_k("rise"), ""))]
	_cur = keep
	return text


## Was this player pressing / steering just now? (unknown for players not on a local party pad: yes)
func _active(s: Seat) -> bool:
	var party := _party()
	if not s.local or party == null or not bool(party.call("is_local", s.slot)):
		return true
	return s.active_t < ACTIVE_WINDOW


const _INPUTS := ["a", "b", "x", "y", "lb", "rb", "lt", "rt"]


func _track_input(delta: float) -> void:
	if seats.is_empty() or main == null or not is_instance_valid(main):
		return
	var party := _party()
	for s: Seat in seats:
		s.active_t += delta
		if party == null or not s.local or not bool(party.call("is_local", s.slot)):
			continue
		var on := (party.call("stick", s.slot, "move") as Vector2).length() > 0.3
		for a in _INPUTS:
			if on:
				break
			on = bool(party.call("pressed", s.slot, a))
		if on:
			s.active_t = 0.0


## The player's own core/awards.gd stats that are wins (score, hits, finds...).
func _aw_sum(slot: int) -> float:
	var a: Variant = main.get("awards") if main != null else null
	if not (a is Object) or not is_instance_valid(a):
		return 0.0
	var all: Variant = (a as Object).get("stats")
	if not (all is Dictionary) or not (all as Dictionary).has(slot):
		return 0.0
	var tot := 0.0
	var d: Dictionary = all[slot]
	for k in d:
		if String(k) not in NOT_WINS and (d[k] is float or d[k] is int):
			tot += maxf(0.0, float(d[k]))
	return tot


func aw(slot: int, stat: String) -> float:
	var a: Variant = main.get("awards") if main != null else null
	if a is Object and is_instance_valid(a) and (a as Object).has_method("get_stat"):
		return float((a as Object).call("get_stat", slot, stat))
	return 0.0


func _win(s: Seat, quiet: bool = false) -> void:
	s.state = "done"
	s.win_secs = s.play_t
	s.after_t = 0.0
	if not s.local:
		print("FIRST GOAL: %s P%d (on another machine) first win after %.1f s" % [game, s.slot + 1, s.play_t])
		return
	print("FIRST GOAL: %s %s P%d first win after %.1f s" % [game, s.device, s.slot + 1, s.play_t])
	_remember(s)
	if quiet:
		_drop_seat_ui(s)
		return
	UiKit.sound("ui_select", -4.0, 1.2)
	if s.card != null and is_instance_valid(s.card):
		var l: Label = s.card.get_meta("text_label") if s.card.has_meta("text_label") else null  # (a null default errors)
		if l != null and is_instance_valid(l):
			l.text = "Nice one!"
		s.nice = true
		var c := s.card
		var tw := c.create_tween()
		tw.tween_property(c, "scale", Vector2(1.12, 1.12), 0.12)
		tw.tween_property(c, "scale", Vector2.ONE, 0.18)
		tw.tween_interval(1.0)
		tw.tween_property(c, "modulate:a", 0.0, 0.35)
		tw.tween_callback(c.queue_free)
	if s.vr_card != null and is_instance_valid(s.vr_card) and s.vr_card.has_method("set_text"):
		s.vr_card.call("set_text", "Nice one!", "")
		s.nice = true
		var vc := s.vr_card
		get_tree().create_timer(1.4).timeout.connect(func() -> void: _drop_vr_card_node(vc))
		s.vr_card = null
	if s.arrow != null and is_instance_valid(s.arrow):
		s.arrow.queue_free()
	s.arrow = null


## Help kicks in (core/rescue.gd): the prompt comes back big, with its arrow.
func _help(s: Seat) -> void:
	print("FIRST GOAL: %s %s P%d rescue: help kicks in (%s)" % [game, s.device, s.slot + 1, s.state])
	if s.state == "show":
		_shrink(s, false)
		s.pulse = 1.0
		UiKit.sound("ui_notify", -6.0, 1.0)
		if s.device == "vr":
			_drop_vr_card(s)
			_show(s)
	elif s.state == "done" or s.state == "off":
		s.state = "show"
		s.play_t = 0.0
		_bases(s)
		_show(s, "Try this: ")


## Something else has the player's attention: a pick row, a how-to card, a story card, the pause menu.
func _blocked() -> bool:
	if not is_inside_tree():
		return false  # (tests/first_goal_test.gd drives seats by hand)
	var tree := get_tree()
	if tree.paused:
		return true
	if not tree.get_nodes_in_group("pause_menu").filter(func(n: Node) -> bool: return n is CanvasItem and (n as CanvasItem).is_visible_in_tree()).is_empty():
		return true
	for h in tree.get_nodes_in_group("hints"):  # core/hints.gd how-to cards
		if h.has_method("intro_showing") and bool(h.call("intro_showing")):
			return true
	_story_hit = false
	if _story_wait < STORY_READ:  # VR story cards being read hold it back a little (Whack-a-Mole solo VR tells one after
		for c in tree.get_nodes_in_group("story_card_vr"):  # another all round 1); then it shows and steps aside
			if c is Node3D and (c as Node3D).is_visible_in_tree() and not c.is_queued_for_deletion():
				_story_hit = true
				return true
	for n in tree.get_nodes_in_group("pick_orb"):  # pick orbs showing (core/pick_orbs.gd PICK_GROUP)
		if n is Node3D and (n as Node3D).is_visible_in_tree():
			return true
	var flat := _cur == null or _cur.device != "vr"
	if flat and not tree.get_nodes_in_group("hint_pill").is_empty():  # a game's own hint is showing
		return true
	for n in tree.get_nodes_in_group("layout_cover"):  # story / how-to panels on the TV, where they'd sit under it
		if n is Control and (n as Control).is_visible_in_tree() and _covers(n as Control):
			return true
	return false


## Does a panel (in any view: split screens are SubViewports) reach the prompt's band low in the screen, or fill most
## of its view (a big story card)? Compared as fractions of each one's own view.
func _covers(c: Control) -> bool:
	var vs := c.get_viewport_rect().size
	if vs.x < 1.0 or vs.y < 1.0:
		return false
	var r := c.get_global_rect()
	var top := r.position.y / vs.y
	var bottom := r.end.y / vs.y
	return bottom > 0.72 or (bottom - top) > 0.5


# --- Expressions -----------------------------------------------------------------------------------------------------

func _eval(key: String, def: Variant) -> Variant:
	key = _k(key)
	if not data.has(key):
		return def
	var text := String(data[key])
	var e: Expression = _exprs.get(text, null)
	if e == null:
		e = Expression.new()
		if e.parse(text, ["main", "p"]) != OK:
			_fail(key, text, e.get_error_text())
			return def
		_exprs[text] = e
	var out: Variant = e.execute([main, _cur.slot if _cur != null else 0], self, false)
	if e.has_execute_failed():
		_fail(key, text, e.get_error_text())
		return def
	return out


## The device of the seat being looked at (expressions read `device`).
var device: String:
	get:
		return _cur.device if _cur != null else "tv"


## A key's device version when the data has one ("rise_vr" for the VR player, "rise_tv" for TV and Deck).
func _k(key: String) -> String:
	var vrish := device == "vr" or (_cur != null and String(_role(_cur).get("as", "")) == "vr")  # a flat seat in the VR role
	var dk := key + ("_vr" if vrish else "_tv")
	return dk if data.has(dk) else key


func _fail(key: String, text: String, why: String) -> void:
	if _failed.has(text):
		return
	_failed[text] = true
	push_error("FirstGoal %s: \"%s\" (%s) failed: %s (games/%s/first_goal.gd)" % [game, key, text, why, game])


func _truthy(key: String, def: bool) -> bool:
	var x: Variant = _eval(key, def)
	return bool(x) if x != null else false


func _num(key: String) -> float:
	var x: Variant = _eval(key, 0.0)
	if x is int or x is float or x is bool:
		return float(x)
	if x is Array or x is Dictionary:
		return sum(x)
	return 0.0


## Helpers for the expressions.
func v(prop: String, def: Variant = null) -> Variant:
	if main == null:
		return def
	var x: Variant = main.get(prop)
	return def if x == null else x


func st(key: String, def: Variant = null) -> Variant:
	var net := _net()
	if net != null and net.has_method("state_get"):
		var x: Variant = net.call("state_get", key, def)
		return def if x == null else x
	return def


func phase() -> String:
	var p: Variant = st("phase", null)
	if p == null:
		p = v("phase", "")
	return String(p) if p != null else ""


func count(group: String) -> int:
	return get_tree().get_nodes_in_group(group).size()


func node(name: String) -> Node:
	return main.find_child(name, true, false) if main != null else null


func sum(x: Variant) -> float:
	var s := 0.0
	var vals: Array = (x as Dictionary).values() if x is Dictionary else (x as Array) if x is Array else [x]
	for a in vals:
		if a is int or a is float:
			s += float(a)
		elif a is Array or a is Dictionary:
			s += sum(a)
	return s


## The player's slot (the seat being looked at).
func local_slot() -> int:
	return _cur.slot if _cur != null else 0


func nearest(group: String) -> Node3D:
	return nearest_of(get_tree().get_nodes_in_group(group))


## The nearest Node3D of an Array / Dictionary's values (e.g. main's balloons {id: node}) to the player's camera.
func nearest_of(x: Variant) -> Node3D:
	var cam := _cam()
	var from := cam.global_position if cam != null and cam.is_inside_tree() else Vector3.ZERO
	var best: Node3D = null
	var bd := INF
	var list: Array = (x as Dictionary).values() if x is Dictionary else (x as Array) if x is Array else []
	for n in list:
		if n is Node3D and is_instance_valid(n) and (n as Node3D).is_visible_in_tree():
			var d := (n as Node3D).global_position.distance_squared_to(from)
			if d < bd:
				bd = d
				best = n
	return best


## The camera of the seat being looked at: the headset, their own view's camera, else the screen's.
func _cam() -> Camera3D:
	if _cur != null and _cur.device == "vr":
		var c := VrViewCheck.vr_camera(get_tree().root)
		if c != null:
			return c
	if _cur != null:
		var vp := _view_of(_cur)
		if vp != null and vp.get_camera_3d() != null:
			return vp.get_camera_3d()
	return get_viewport().get_camera_3d()


# --- Remembering (per profile: the Steam account playing on THIS machine, else this machine's user) ------------------

static func profile() -> String:
	for k in ["SteamAppUser", "SteamUser", "USER"]:
		if OS.get_environment(k) != "":
			return OS.get_environment(k).to_lower()
	return "player"


## The key a seat is remembered under: "<game>/<device>", "#2".. for the 2nd.. player on this machine.
static func key_of(game_id: String, dev: String, idx: int) -> String:
	return "%s/%s%s" % [game_id, dev, "" if idx <= 0 else "#%d" % (idx + 1)]


func _remembering() -> bool:
	return not Save.test_mode() or OS.has_environment("FIRST_GOAL_REMEMBER") or save_path != SAVE_PATH


func _remembered(s: Seat) -> bool:
	if not _remembering() or not s.local:
		return false
	var cfg := ConfigFile.new()
	return cfg.load(save_path) == OK and bool(cfg.get_value(profile(), key_of(game, s.device, s.idx), false))


func _remember(s: Seat) -> void:
	if not _remembering() or not s.local:
		return
	var cfg := ConfigFile.new()
	cfg.load(save_path)
	cfg.set_value(profile(), key_of(game, s.device, s.idx), true)
	cfg.save(save_path)


## Telemetry (core/telemetry.gd adds these to the game's RUN lines): this machine's first player, and how many won.
func run_fields(id: String) -> Dictionary:
	if id != game or data.is_empty():
		return {}
	var mine := local_seats()
	if mine.is_empty():
		mine = seats
	if mine.is_empty():
		return {}
	var s: Seat = mine[0]
	var won := 0
	for o: Seat in mine:
		if o.state == "done":
			won += 1
	var out := {"fg_secs": snappedf(s.win_secs, 0.1), "fg_dev": s.device, "fg_shown": snappedf(s.on_screen_t, 0.1),
		"fg_n": mine.size(), "fg_won": won}
	if s.state == "off":
		out["fg_secs"] = -2.0  # already learned (remembered): no prompt shown
	if s.rescue != null:
		out.merge(s.rescue.run_fields())
	return out


## Bots / tests: every seat's state as plain data.
func seats_info() -> Array:
	var out: Array = []
	for s: Seat in seats:
		out.append({"slot": s.slot, "local": s.local, "device": s.device, "state": s.state, "nice": s.nice,
			"shown": s.on_screen_t, "win": s.win_secs, "card": s.card if s.card != null and is_instance_valid(s.card) else null,
			"view": s.view if s.view != null and is_instance_valid(s.view) else null, "name": s.name,
			"shown_in": s.shown_in if s.shown_in != null and is_instance_valid(s.shown_in) else null,
			"split_view": s.shown_slot_view})
	return out


# --- Showing it ------------------------------------------------------------------------------------------------------

## A flat player whose seat has its own role (data "seats": {slot: {"you", "do"}}: Cannon Cove's P1 is the gunner even
## without a headset), else {}.
func _role(s: Seat) -> Dictionary:
	var roles: Dictionary = data.get("seats", {})
	return roles.get(s.slot, {}) if s.device != "vr" else {}


func _pair(s: Seat) -> Array:
	if _role(s).has("do"):
		return _role(s)["do"]
	var dd: Dictionary = data.get("do", {})
	var pair: Array = dd.get(s.device, dd.get("tv", ["", ""]))
	return pair


func _you(s: Seat) -> String:
	var you := String(_role(s).get("you", data.get("you_" + ("vr" if s.device == "vr" else "tv"), data.get("you", ""))))
	return "YOU ARE " + you.to_upper() if you != "" else ""


## The seat's own split-screen view (a core/split_view.gd view, or a classic game's per-player SubViewport), or null
## when they share the screen with others.
func _view_of(s: Seat) -> SubViewport:
	if s.device == "vr" or not s.local:
		return null
	var split := _split()
	if split != null:
		if bool(split.call("showing_shared")) or not bool(split.call("has_slot", s.slot)) or int(split.call("view_count")) < 2:
			return null
		var vp: Variant = split.call("viewport", s.slot)
		return vp as SubViewport if vp is SubViewport else null
	var players: Variant = main.get("players")
	if not (players is Array) or s.slot >= (players as Array).size() or not (players[s.slot] is Object):
		return null
	var cam: Variant = (players[s.slot] as Object).get("camera")
	if not (cam is Camera3D) or not is_instance_valid(cam) or not (cam as Camera3D).is_inside_tree():
		return null
	var vp := (cam as Camera3D).get_viewport()
	if not (vp is SubViewport) or not (vp.get_parent() is SubViewportContainer):
		return null
	var box := vp.get_parent() as Control
	var screen := get_viewport().get_visible_rect().size
	if not box.is_visible_in_tree() or box.size.x * box.size.y < screen.x * screen.y * 0.15:
		return null  # (a minimap or mirror, not their view)
	if box.size.x * box.size.y > screen.x * screen.y * 0.9:
		return null  # (one view fills the screen: the shared row is the same thing)
	return vp as SubViewport


## The Control a seat's card goes in: their own view's layer, or the screen's.
func _ui_for(s: Seat) -> Control:
	var vp := _view_of(s)
	if vp != null:
		if s.view != vp or s.ui == null or not is_instance_valid(s.ui):
			if s.layer != null and is_instance_valid(s.layer):
				s.layer.queue_free()
			s.view = vp
			s.layer = CanvasLayer.new()
			s.layer.layer = 60
			s.layer.name = "FirstGoalLayer%d" % s.slot
			s.layer.set_meta("first_goal", true)
			vp.add_child(s.layer)
			s.ui = UiKit.ui_root(s.layer)
			s.ui.set_meta("first_goal", true)
		return s.ui
	s.view = null
	if _layer == null or not is_instance_valid(_layer):
		_layer = CanvasLayer.new()
		_layer.layer = 60
		_layer.name = "FirstGoalLayer"
		add_child(_layer)
		_ui = UiKit.ui_root(_layer)
	return _ui


## Seats whose cards share the main screen (a row, one card each).
func _screen_seats() -> Array:
	return seats.filter(func(o: Seat) -> bool: return o.local and o.device != "vr" and o.view == null \
		and o.card != null and is_instance_valid(o.card) and o.state in ["show", "done"])


func _show(s: Seat, prefix: String = "") -> void:
	s.small = false
	s.nice = false
	var pair := _pair(s)
	var wordless := bool(data.get("wordless", false))
	if s.device == "vr":
		var cam := VrViewCheck.vr_camera(get_tree().root)
		if cam == null or wordless:
			return
		var world: Node = self  # a service under /root: freed with the prompt, never inside the game's own tree
		var body := "%s:  %s" % [String(pair[0]), prefix + String(pair[1])]
		s.vr_card = HudKit.vr_card(world, cam, _you(s), body,
			{"width": 1.1, "color": "gold", "height": -0.34, "distance": 1.6, "title_size": 0.06, "body_size": 0.05})
		s.vr_card.set_meta("first_goal", true)
		s.vr_card.set_meta("vr_yields", true)  # it steps aside / hides for the game's cards, never they for it
	else:
		var ui := _ui_for(s)
		if s.card != null and is_instance_valid(s.card):
			s.card.queue_free()
		var flat_others := 0
		for o: Seat in seats:
			if o != s and o.local and o.device != "vr" and o.view == null and o.state == "show":
				flat_others += 1
		var many := s.view == null and flat_others > 0  # sharing the screen: say whose card it is
		var sc := UiKit.scale_of(ui) * (0.8 if many and flat_others >= 2 else 1.0)
		var tint := UiKit.color_of(s.slot) if many else UiKit.color_of("gold", UiKit.ACCENT)
		s.shown_in = s.view
		var split := _split()
		s.shown_slot_view = split != null and not bool(split.call("showing_shared")) and bool(split.call("has_slot", s.slot)) \
			and int(split.call("view_count")) >= 2
		s.card = UiKit.tinted_panel(tint, sc, "accent")
		s.card.name = "FirstGoal%d" % s.slot
		s.card.set_meta("first_goal", true)
		ui.add_child(s.card)
		var vb := UiKit.vbox(4, sc)
		s.card.add_child(vb)
		var you := "" if wordless else _you(s)
		if many and not wordless:
			you = "%s: %s" % [s.name, you] if you != "" else s.name
		if you != "":
			var yl := UiKit.label(you, "small", tint.lightened(0.25), HORIZONTAL_ALIGNMENT_CENTER)
			vb.add_child(yl)
			s.card.set_meta("you_label", yl)
		var h := UiKit.hbox(12, sc)
		h.alignment = BoxContainer.ALIGNMENT_CENTER
		vb.add_child(h)
		if String(pair[0]) != "":
			var gl := UiKit.glyph(String(pair[0]), sc)
			gl.size_flags_vertical = Control.SIZE_SHRINK_CENTER
			h.add_child(gl)
		if wordless:
			if data.has("icon"):
				var ic := UiKit.icon(String(data["icon"]), "gold", 56.0 * sc)
				ic.size_flags_vertical = Control.SIZE_SHRINK_CENTER
				h.add_child(ic)
		else:
			var l := UiKit.label(prefix + String(pair[1]), "heading" if not many or flat_others < 2 else "body")
			h.add_child(l)
			s.card.set_meta("text_label", l)
		s.card.pivot_offset_ratio = Vector2(0.5, 0.5)
		s.card.modulate.a = 0.0
		UiKit.fade(s.card, 1.0, 0.3)
		UiKit.sound("ui_notify", -6.0, 1.1)
	s.pulse = 0.6


func _shrink(s: Seat, on: bool) -> void:
	s.small = on
	if s.card != null and is_instance_valid(s.card) and s.card.has_meta("you_label"):
		(s.card.get_meta("you_label") as Control).visible = not on


func _set_visible(s: Seat, on: bool) -> void:
	if s.card != null and is_instance_valid(s.card) and s.state == "show":
		s.card.visible = on
	if s.vr_card != null and is_instance_valid(s.vr_card):
		s.vr_card.visible = on and not _vr_covered(s)
	if s.arrow != null and is_instance_valid(s.arrow):
		s.arrow.visible = on


## Is the VR prompt over one of the game's own panels (after stepping aside)? Then it waits, hidden.
func _vr_covered(s: Seat) -> bool:
	var cam := VrViewCheck.vr_camera(get_tree().root)
	if cam == null or s.vr_card == null:
		return false
	for o in VrViewCheck.shown_panels(get_tree().root):
		if o != s.vr_card and not s.vr_card.is_ancestor_of(o) and VrViewCheck.overlap(cam.global_position, s.vr_card, o):
			return true
	return false


func _animate(delta: float) -> void:
	var row := _screen_seats()
	for s: Seat in seats:
		s.pulse = maxf(0.0, s.pulse - delta)
		if s.card == null or not is_instance_valid(s.card) or s.state != "show":
			continue
		var parent := s.card.get_parent() as Control
		var vs := parent.size if parent != null and parent.size.x > 1.0 else s.card.get_viewport_rect().size
		var sz := s.card.get_combined_minimum_size()
		s.card.size = sz
		var k := (0.78 if s.small else 1.0) + 0.1 * sin(s.pulse * PI * 4.0) * s.pulse
		s.card.scale = Vector2(k, k)
		# low in the view (story toasts and scores live at the top; core/hints.gd pills at 0.74 hide it while they show)
		var y := vs.y * (s.band if not s.small else 0.9) - sz.y * 0.5
		var cx := vs.x * 0.5
		var i := row.find(s)
		if i >= 0 and row.size() > 1:
			cx = vs.x * (float(i) + 0.5) / float(row.size())
		s.card.position = Vector2(clampf(cx - sz.x * 0.5, 0.0, maxf(0.0, vs.x - sz.x)), y)


## The game's own words and pictures in a seat's picture: Controls under main in the seat's own view (view
## coordinates), or anywhere on the screen (screen pixels, mapped out of split-screen SubViewports).
func _hud_rects(s: Seat) -> Array[Rect2]:
	var out: Array[Rect2] = []
	if main == null:
		return out
	var vs := get_viewport().get_visible_rect().size
	for n in main.find_children("*", "Control", true, false):
		var c := n as Control
		if not (c is Label or c is TextureRect or c is Button or c is RichTextLabel) or not c.is_visible_in_tree():
			continue
		if c.modulate.a < 0.2 or c.get_global_rect().size.x * c.get_global_rect().size.y < 64.0 or _ours(c):
			continue
		var r := c.get_global_rect()
		var vp := c.get_viewport()
		if s.view != null:
			if vp == s.view:
				out.append(r)
			continue
		if vp is SubViewport:
			var box := vp.get_parent() as Control
			if box == null or not box.is_visible_in_tree():
				continue
			var k := box.get_global_rect().size / Vector2(maxf(1.0, (vp as SubViewport).size.x), maxf(1.0, (vp as SubViewport).size.y))
			r = Rect2(box.get_global_rect().position + r.position * k, r.size * k)
		elif r.size.x >= vs.x * 0.9 and r.size.y >= vs.y * 0.9:
			continue  # full-screen backdrops
		out.append(r)
	return out


func _ours(c: Node) -> bool:
	var x := c
	while x != null and x != main:
		if x.has_meta("first_goal"):
			return true
		x = x.get_parent()
	return false


## Sit in the first band (BANDS) where the card covers none of the game's HUD; data "flat_y" pins it.
func _pick_band(s: Seat) -> void:
	if data.has("flat_y"):
		s.band = float(data["flat_y"])
		return
	if s.card == null or not is_instance_valid(s.card):
		return
	var parent := s.card.get_parent() as Control
	if parent == null:
		return
	var vs := parent.size
	var sz := s.card.get_combined_minimum_size()
	var xf := parent.get_global_transform()
	var rects := _hud_rects(s)
	var x0 := s.card.position.x
	for b in BANDS:
		var cr := xf * Rect2(Vector2(x0, vs.y * float(b) - sz.y * 0.5), sz).grow(8.0)
		var hit := false
		for r in rects:
			if cr.intersects(r):
				hit = true
				break
		if not hit:
			s.band = float(b)
			return
	# (all taken: stay where it is, rather than hopping)


## A bobbing arrow over the thing to do it to (in the world: every view and the headset see it).
func _place_arrow(s: Seat) -> void:
	if not s.local or s.state != "show" or not data.has(_k("target")):
		if s.arrow != null and is_instance_valid(s.arrow) and s.state != "show":
			s.arrow.queue_free()
			s.arrow = null
		return
	var tg: Variant = _eval("target", null)
	var pos: Variant = null
	if tg is Node3D and is_instance_valid(tg) and (tg as Node3D).is_inside_tree():
		pos = (tg as Node3D).global_position
	elif tg is Vector3:
		pos = tg
	for o: Seat in seats:  # one arrow per thing, even when several players are told about it
		if o == s:
			break
		if pos != null and o.arrow != null and is_instance_valid(o.arrow) and o.arrow.visible \
				and Vector3(o.arrow.get_meta("target", Vector3.INF)).distance_to(pos) < 0.05:
			pos = null
	if pos == null or not (main is Node3D or main.get_viewport() != null):
		if s.arrow != null and is_instance_valid(s.arrow):
			s.arrow.visible = false
		return
	if s.arrow == null or not is_instance_valid(s.arrow):
		s.arrow = _make_arrow()
		main.add_child(s.arrow)
	var cam := _cam()
	var dist := cam.global_position.distance_to(pos) if cam != null and cam.is_inside_tree() else 10.0
	# about 5% of the view, but never much bigger than the thing itself (a golf ball under a huge arrow)
	var size := clampf(dist * 0.05, 0.15, 6.0)
	if tg is Node3D:
		size = minf(size, maxf(0.15, _size_of(tg as Node3D) * 0.9))
	s.arrow.set_meta("target", pos)
	s.arrow.set_meta("base", pos + Vector3.UP * size * 1.8)
	s.arrow.set_meta("size", size)
	s.arrow.visible = not _blocked()


## A node's rough size in metres: its biggest drawn piece's box (scaled), 0 = unknown (then no cap).
func _size_of(n: Node3D) -> float:
	var best := 0.0
	var list: Array = [n]
	list.append_array(n.find_children("*", "VisualInstance3D", true, false).slice(0, 24))
	for x in list:
		if x is VisualInstance3D:
			var vi := x as VisualInstance3D
			var sz := vi.get_aabb().size * vi.global_transform.basis.get_scale()
			best = maxf(best, maxf(sz.x, maxf(sz.y, sz.z)))
	return best if best > 0.0 else 99.0


func _make_arrow() -> Node3D:
	var a := Arrow.new()
	a.name = "FirstGoalArrow"
	a.set_meta("vr_check_ignore", true)
	return a


class Arrow extends Node3D:
	var tt := 0.0
	var mesh: MeshInstance3D

	func _ready() -> void:
		mesh = MeshInstance3D.new()
		var cone := CylinderMesh.new()
		cone.top_radius = 0.5
		cone.bottom_radius = 0.0
		cone.height = 1.0
		cone.radial_segments = 12
		mesh.mesh = cone
		var m := StandardMaterial3D.new()
		m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		m.albedo_color = Color(1.0, 0.82, 0.2)
		# (depth-tested like any solid thing: no_depth_test breaks VR depth, docs/GAME_DEV_GUIDE.md; it hid VR card text too)
		mesh.material_override = m
		mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(mesh)

	func _process(delta: float) -> void:
		tt += delta
		var s := float(get_meta("size", 1.0))
		global_position = Vector3(get_meta("base", global_position)) + Vector3.UP * sin(tt * 5.0) * s * 0.25
		scale = Vector3.ONE * s
		mesh.rotation.y = tt * 2.0


func _drop_vr_card(s: Seat) -> void:
	_drop_vr_card_node(s.vr_card)
	s.vr_card = null


func _drop_vr_card_node(c: Node3D) -> void:
	if c != null and is_instance_valid(c) and c.has_method("hide_card"):
		c.call("hide_card")


func _drop_seat_ui(s: Seat) -> void:
	if s.card != null and is_instance_valid(s.card):
		s.card.queue_free()
	s.card = null
	_drop_vr_card(s)
	if s.arrow != null and is_instance_valid(s.arrow):
		s.arrow.queue_free()
	s.arrow = null
	if s.layer != null and is_instance_valid(s.layer):
		s.layer.queue_free()
	s.layer = null
	s.ui = null
	s.view = null


func _reset() -> void:
	for s: Seat in seats:
		_drop_seat_ui(s)
	seats.clear()
	data = {}
	game = ""
	main = null
	t = 0.0
	_exprs.clear()
	_failed.clear()
	_cur = null
	_story_wait = 0.0
