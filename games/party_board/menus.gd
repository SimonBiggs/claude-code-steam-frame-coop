extends Node
## Choices on every machine, driven by the replicated state:
##  - "menu" {seq, pid, title, sub, items, kind}: the host asks one player to choose (items, shop,
##    star, duel opponent...). Where that player sits, a core/ui_menu.gd menu (TV seat) or a
##    core/vr_menu.gd panel (VR player) opens; the choice goes back with net.request(pid, "menu",
##    [seq, id]). CPU players are answered by the host (turn_flow.gd).
##  - the title-screen SETUP menu (turns, kid mode, start) for the first TV seat and the VR player;
##  - board input for local seats: hit the dice block (A), pick a branch (stick / point), Quick Draw.

const UiKit := preload("res://core/ui_kit.gd")
const UiMenu := preload("res://core/ui_menu.gd")
const VrMenu := preload("res://core/vr_menu.gd")
const MeshKit := preload("res://core/mesh_kit.gd")

var main: Node
var menu_seq := -1
var tv_menu: UiMenu
var vr_menu: VrMenu
var setup_tv: UiMenu
var setup_tv_slot := -1
var setup_vr: VrMenu
var laser: MeshInstance3D
var _branch_hover := -1
var _stick_ready := {}  # slot -> bool (stick back to centre before the next branch step)


func _ready() -> void:
	if main.vr_rig != null:
		laser = MeshInstance3D.new()
		var bm := BoxMesh.new()
		bm.size = Vector3(0.006, 0.006, 1.0)
		laser.mesh = bm
		laser.material_override = MeshKit.material(Color(1.0, 0.9, 0.4, 0.8), 2.0)
		laser.visible = false
		main.add_child(laser)


func on_state(key: String, value: Variant) -> void:
	match key:
		"menu":
			_on_menu(value if value is Dictionary else {})
		"phase", "settings", "players":
			_refresh_setup()


# --- Generic menus ------------------------------------------------------------------------------------

func _on_menu(m: Dictionary) -> void:
	var seq := int(m.get("seq", -1))
	if seq == menu_seq and not m.is_empty():
		return
	_close_menus()
	menu_seq = seq
	if m.is_empty():
		return
	var pid := int(m.get("pid", -1))
	var items: Array = m.get("items", [])
	var title := String(m.get("title", ""))
	if main.is_local_vr(pid):
		vr_menu = VrMenu.open(main, {"title": title, "items": items, "rig": main.vr_rig, "player": 0,
			"distance": 1.15, "height": -0.16})
		vr_menu.chosen.connect(func(id: String, _it: Dictionary) -> void: main.net.request(0, "menu", [seq, id]))
		main.vr_rig.guard_trigger()
	elif main.is_local_tv(pid) and main.tv_ui != null:
		tv_menu = UiMenu.open(main.tv_ui, {"title": title, "items": items, "party": main.party, "slot": pid,
			"anchor": "right", "allow_cancel": false, "desc": true, "width": 600.0})
		tv_menu.chosen.connect(func(id: String, _it: Dictionary) -> void: main.net.request(pid, "menu", [seq, id]))


func _close_menus() -> void:
	if tv_menu != null and is_instance_valid(tv_menu):
		tv_menu.close()
	tv_menu = null
	if vr_menu != null and is_instance_valid(vr_menu):
		vr_menu.close()
	vr_menu = null


# --- Setup menu (title screen) --------------------------------------------------------------------------

func _setup_items() -> Array:
	var cfg: Dictionary = main.net.state_get("settings", {})
	return [
		{"id": "start", "text": "START THE PARTY!", "icon": "play", "desc": "Everyone in? Let's go!"},
		{"id": "turns", "text": "TURNS: %d" % int(cfg.get("turns", 10)), "icon": "clock", "desc": "How long the party lasts: 5, 10 or 15 turns."},
		{"id": "kid", "text": "KID MODE: %s" % ("ON" if bool(cfg.get("kid", false)) else "OFF"), "icon": "heart",
			"desc": "Red spaces take less and the player in last place gets catch-up coins."},
	]


func _refresh_setup() -> void:
	var title_on := String(main.net.state_get("phase", "")) == "title"
	if not title_on:
		if setup_tv != null and is_instance_valid(setup_tv):
			setup_tv.close()
		setup_tv = null
		if setup_vr != null and is_instance_valid(setup_vr):
			setup_vr.close()
		setup_vr = null
		return
	var items := _setup_items()
	if main.tv_ui != null:
		var seats: Array[int] = main.party.local_slots()
		var leader := -1
		for s in seats:
			if not (s == 0 and main.vr_rig != null):
				leader = s
				break
		if leader != setup_tv_slot and setup_tv != null and is_instance_valid(setup_tv):
			setup_tv.close()
			setup_tv = null
		setup_tv_slot = leader
		if leader >= 0:
			if setup_tv == null or not is_instance_valid(setup_tv):
				setup_tv = UiMenu.open(main.tv_ui, {"title": "NEW PARTY", "items": items, "party": main.party, "slot": leader,
					"anchor": "right", "allow_cancel": false, "close_on_choose": false, "desc": true, "width": 560.0})
				setup_tv.chosen.connect(func(id: String, _it: Dictionary) -> void: main.net.request(setup_tv_slot, "setup", [id]))
			else:
				var f := setup_tv.focused_id()
				setup_tv.set_items(items)
				setup_tv.focus(f)
	if main.vr_rig != null:
		if setup_vr == null or not is_instance_valid(setup_vr):
			setup_vr = VrMenu.open(main, {"title": "NEW PARTY", "items": items, "rig": main.vr_rig, "close_on_choose": false,
				"distance": 1.15, "height": -0.1})
			setup_vr.chosen.connect(func(id: String, _it: Dictionary) -> void: main.net.request(0, "setup", [id]))
		else:
			var i := setup_vr.index
			setup_vr.set_items(items)
			setup_vr.focus(i)


# --- Board input (local seats) -------------------------------------------------------------------------

## Called every frame for each local TV seat (main._tv_input).
func board_input(slot: int) -> void:
	if get_tree().paused or main.net.just_unpaused():
		return
	var phase := String(main.net.state_get("phase", ""))
	if phase != "board":
		return
	var step := String(main.net.state_get("step", ""))
	var party: Node = main.party
	if step == "roll":
		var d: Dictionary = main.net.state_get("dice", {})
		if int(d.get("pid", -1)) == slot and String(d.get("mode", "")) == "tv" and party.just_pressed(slot, "accept"):
			main.net.request(slot, "dice_hit", [int(d.get("id", 0))])
	elif step == "branch":
		var br: Dictionary = main.net.state_get("branch", {})
		if int(br.get("pid", -1)) != slot:
			return
		var options: Array = br.get("options", [])
		var sel := int(br.get("sel", 0))
		var mv: Vector2 = party.stick(slot, "move")
		var nav: Vector2i = party.nav(slot)
		if nav.x != 0 and mv.length() < 0.3:
			var ni := posmod(sel + nav.x, options.size())
			main.net.request(slot, "branch_sel", [ni])
		elif mv.length() > 0.55:
			if bool(_stick_ready.get(slot, true)):
				var best := _best_option(int(br.get("from", 0)), options, main.tv_dir(mv))
				if best >= 0 and best != sel:
					main.net.request(slot, "branch_sel", [best])
		_stick_ready[slot] = mv.length() < 0.3
		if party.just_pressed(slot, "accept"):
			main.net.request(slot, "branch_go", [sel])
	elif step == "duel":
		var du: Dictionary = main.net.state_get("duel", {})
		if (int(du.get("a", -1)) == slot or int(du.get("b", -1)) == slot) and party.just_pressed(slot, "accept"):
			main.net.request(slot, "duel_hit", [])


## The option whose direction best matches `dir` (board units).
func _best_option(from: int, options: Array, dir: Vector3) -> int:
	var p: Vector3 = main.data.pos(from)
	var best := -1
	var bd := -2.0
	for i in options.size():
		var q: Vector3 = main.data.pos(int(options[i]))
		var od := Vector3(q.x - p.x, 0, q.z - p.z).normalized()
		var d := od.dot(dir.normalized())
		if d > bd:
			bd = d
			best = i
	return best


func _process(_delta: float) -> void:
	if main.vr_rig == null or laser == null:
		return
	laser.visible = false
	if get_tree().paused:
		return
	var phase := String(main.net.state_get("phase", ""))
	var step := String(main.net.state_get("step", ""))
	if phase == "board" and step == "branch":
		var br: Dictionary = main.net.state_get("branch", {})
		if int(br.get("pid", -1)) == 0:
			_vr_branch(br)
	elif phase == "board" and step == "duel":
		var du: Dictionary = main.net.state_get("duel", {})
		if (int(du.get("a", -1)) == 0 or int(du.get("b", -1)) == 0) and main.vr_rig.trigger_pressed():
			main.net.request(0, "duel_hit", [])


## VR: point the right hand at a branch arrow (a laser shows where), trigger or A picks it; touching
## an arrow works too.
func _vr_branch(br: Dictionary) -> void:
	var rig: Node = main.vr_rig
	var arrows: Array = main.board.arrows
	if arrows.is_empty():
		return
	var hand: Node3D = rig.hand_r
	var o := hand.global_position
	var d := -hand.global_basis.z.normalized()
	var best := -1
	var best_ang := deg_to_rad(14.0)
	for i in arrows.size():
		var a: Node3D = arrows[i]
		if not is_instance_valid(a):
			continue
		var to := a.global_position - o
		if rig.touching(1, a.global_position, 0.08) or rig.touching(0, a.global_position, 0.08):
			best = i
			best_ang = 0.0
			break
		var ang := d.angle_to(to)
		if ang < best_ang:
			best_ang = ang
			best = i
	laser.visible = true
	var length := 1.2
	if best >= 0:
		length = o.distance_to((arrows[best] as Node3D).global_position)
	laser.global_transform = Transform3D(Basis.looking_at(d, Vector3.UP if absf(d.y) < 0.98 else Vector3.FORWARD), o + d * length * 0.5)
	laser.scale = Vector3(1, 1, length)
	if best >= 0 and best != int(br.get("sel", 0)):
		main.net.request(0, "branch_sel", [best])
		rig.pulse(1, 0.25, 0.03)
	if best >= 0 and (rig.trigger_pressed() or rig.a_pressed()):
		main.net.request(0, "branch_go", [best])
		rig.pulse(1, 0.6, 0.08)
	elif best < 0 and rig.a_pressed():
		main.net.request(0, "branch_go", [int(br.get("sel", 0))])
