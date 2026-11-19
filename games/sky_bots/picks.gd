extends "res://core/pick_flow.gd"
## SKY BOTS PICKS on the shared pick orbs (core/pick_orbs.gd), picture first, team choices in Gizmo Town:
##   "mode"    GENTLE / BRAVE / HARD once a session (the family's last mode in the middle)
##   "island"  which island to hop to: MEADOW HOP, GEAR WORKS, CRAB COVE (each opens when the one before is cleared) and
##             TODAY'S ISLAND (once Meadow Hop is cleared). The suggested one (story.gd suggest) glows in the middle-ish:
##             nobody chose in time -> that one.
## With robots in the hub the big orbs float over the town's front and a robot STANDS under one for TV_DWELL s (running
## past never picks); the VR giant can reach into them too. With only the VR giant here (CPU buddies fill in) small
## orbs float an arm's reach in front of the giant's head. A hand or robot already in an orb when they pop up must
## leave and come back. The host sends the sticky "orbs" event [stage, entries, spots, vr, def] and "take" [orb, slot].

const Giant := preload("res://games/sky_bots/giant.gd")
const Hub := preload("res://games/sky_bots/hub.gd")

const ORB_Y := 2.4  ## big orbs: this high over the town's grass
const ORB_SCALE := 0.8
const ROW_Z := 2.0  ## ... across the front, this far forward of the town's middle
const ROW_GAP := 3.2  ## (four long island names side by side)
const TV_R := 0.8  ## a robot this near (across the grass) is under an orb ...
const TV_DWELL := 0.8  ## ... for this long
const VR_S := Giant.S
const VR_X: Array[float] = [-0.3, -0.1, 0.1, 0.3]
const VR_AHEAD := 0.42
const VR_BELOW := 0.14
const VR_SCALE := 0.14 * VR_S
const HAND_R := 0.06 * VR_S
const DWELL := 0.35
const ROW_WAIT := {"mode": 20.0, "island": 25.0}
const EMPTY_WAIT := 7.0

var vr_row := false  # every machine
var def_i := 1  # host: the suggested orb (nobody chose -> this)
var entries_now: Array = []


func _init() -> void:
	after = 1.1
	hand_r = HAND_R
	hand_dwell = DWELL
	foot_dwell = TV_DWELL


func begin(new_stage: String, entries: Array, opts: Array, vr: bool, suggested: int, done: Callable) -> void:
	start(new_stage, opts, done)
	def_i = clampi(suggested, 0, opts.size() - 1)
	entries_now = entries
	var in_vr: bool = vr and main.vr_rig != null
	if in_vr and not main.vr_rig.refitted.is_connected(_on_refit):
		main.vr_rig.refitted.connect(_on_refit)
	var at := vr_spots(main.vr_rig.head_position(), entries.size()) if in_vr else row_spots(entries.size())
	show_row(new_stage, entries, at, in_vr, def_i)
	publish([new_stage, entries, spots, vr_row, def_i])


func _on_refit(_h: float) -> void:
	if not vr_row or stage == "" or chosen >= 0 or main.vr_rig == null:
		return
	var at := vr_spots(main.vr_rig.head_position(), entries_now.size())
	show_row(stage, entries_now, at, true, def_i)
	publish([stage, entries_now, spots, vr_row, def_i])
	reset_dwell()


func default_pick() -> int:
	return def_i


func orbs_off() -> Array:
	return ["", [], [], false, 0]


static func row_spots(n: int) -> Array:
	var out: Array = []
	for i in n:
		out.append(Hub.CENTER + Vector3((float(i) - float(n - 1) * 0.5) * ROW_GAP, ORB_Y, ROW_Z))
	return out


static func vr_spots(head: Vector3, n: int) -> Array:
	var out: Array = []
	for i in n:
		var x: float = lerpf(VR_X[0], VR_X[3], float(i) / maxf(1.0, n - 1)) if n > 1 else 0.0
		if n == 3:
			x = [-0.3, 0.0, 0.3][i]
		out.append(Vector3(head.x + x * VR_S, head.y - VR_BELOW * VR_S, head.z - VR_AHEAD * VR_S))
	return out


## Every machine: the row of orbs ("" stage: none).
func show_row(new_stage: String, entries: Array, at: Array, vr: bool, def: int = 1) -> void:
	if new_stage == "" or entries.is_empty() or at.size() < entries.size():
		orbs.clear()
		spots = []
		return
	spots = at.duplicate()
	vr_row = vr
	if vr:
		orbs.show_orbs(new_stage, entries, at[0], 0.0, 0.0, {"at": at, "scale": VR_SCALE, "pop": true, "font": 56, "def": def,
			"label_y": -1.15, "label_px": 0.0042, "two_lines": true, "bob": 0.01 * VR_S, "hit_r": PickOrbs.BALL_R, "dot_r": 0.8})
	else:
		orbs.show_orbs(new_stage, entries, at[0], 0.0, 0.0, {"at": at, "scale": ORB_SCALE, "pop": true, "font": 64, "def": def,
			"label_y": 1.25, "label_px": 0.0105, "two_lines": true, "bob": 0.08})
	main.pick_banner()


func wait_for() -> float:
	return EMPTY_WAIT if main.pick_nobody() else float(ROW_WAIT.get(stage, 20.0))


## The VR giant's hands (either row: they can reach the big ones too) and the people's robots under a big orb (CPU
## buddies never pick).
func takers() -> Dictionary:
	var points := {}
	if main.vr_rig != null:
		for h in 2:
			points["h%d" % h] = [main.vr_rig.hand_point(h), 0, "hand"]
	if not vr_row:
		for id in main.robots:
			if int(id) < 10:
				points["r%d" % int(id)] = [(main.robots[id] as Node3D).position, int(id), "walk"]
	return points


func orb_at(kind: String, point: Variant) -> int:
	if kind == "hand":
		return orbs.nearest_hit(point, hand_r if vr_row else hand_r * 2.0)
	var best := -1
	var bd := TV_R
	var p: Vector3 = point
	for i in spots.size():
		var s: Vector3 = spots[i]
		var d := Vector2(s.x - p.x, s.z - p.z).length()
		if d < bd:
			bd = d
			best = i
	return best


func fx(i: int, slot: int, at: Vector3, col: Color) -> void:
	if at != Vector3.INF:
		main.sfx.play_at("power_up", at, -4.0, 1.0 + 0.1 * i)
		main.confetti(at, col, 18)
	if slot == 0 and main.vr_rig != null:
		main.vr_rig.pulse(0, 0.5, 0.08)
		main.vr_rig.pulse(1, 0.5, 0.08)
