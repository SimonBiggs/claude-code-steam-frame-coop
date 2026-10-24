extends Node
## SIMPLE_MODE visual teaching (no how-to words): main.gd makes one of these on every machine.
## - Low in each TV player's view, a pulsing glowing button in that player's own controls plus a picture
##   (cue.gd), on a soft dark pill:
##     TV pilot (slot 0, local split screen only): X / F + a fist + the glowing practice bat (punch),
##     RT / CTRL + the beam + the bat (beam, from round 2), A / SPACE + an arrow + the gold ring (dash,
##     from round 3);
##     support vehicles: STICK / W + their vehicle + the green ring (fly / drive through it), A / SPACE +
##     a bolt + a kaiju (jet / tank), A / SPACE + a plus + the Titan (drone), STICK / W + the truck + the
##     people jumping (go get them) / + the green shelter (take them there), Y / R + an arrow + the new
##     vehicle (swap, once there's more than one);
##     a pulsing bolt while that player's controller is unplugged.
##   Each goes once that player has done it twice (cue_did / cue_learned). A seat's cues reset when its
##   player leaves. While a cue shows and its target is off screen, a big glowing arrow at the view's
##   edge points the way.
## - A glowing 3D arrow (everyone sees it, VR too) bobs over what to hit / go to: the practice bat, the
##   pilot's gold dash ring, a dizzy kaiju (punch it home).
## - VR dash practice: a glowing pulsing button on each controller (the A / X button), until the pilot
##   has dashed twice. The ghost hand (ghost_hand.gd) still shows the punch and the beam.
## - The shared view (nobody seated): a pulsing A + plus + person (a controller can join).
## - A lost controller: a soft pop (and the bolt); back: a happy ding; a full party: a soft pop.
## Everything is built once (views when they're made, arrows at load); per frame only moves / shows.

const Data := preload("res://games/mech_titans/data.gd")
const UiKit := preload("res://core/ui_kit.gd")
const Party := preload("res://core/party.gd")
const MeshKit := preload("res://core/mesh_kit.gd")
const CueScript := preload("res://games/mech_titans/cue.gd")
const Support := preload("res://games/mech_titans/support.gd")
const Kaiju := preload("res://games/mech_titans/kaiju.gd")

const GOLD := Color(1.0, 0.9, 0.45)

var main: Node
var cue_done := {}  ## slot -> {cue key: times done} (kept on the machine that draws that player's view)
var views := {}  ## slot -> {"cue": Cue, "edge": EdgeArrow, "sig": String}
var arrow: Node3D  ## the glowing 3D arrow
var arrow_kind := ""  ## bots: what the 3D arrow points at ("bat", "dash", "dizzy", "")
var vr_buttons: Array[Node3D] = []  ## VR: glowing buttons on the controllers (dash practice)
var _warm := 4  ## frames the arrows / buttons show at load (their pipelines get made then, not mid-game)
var _beam_was := false
var _carry_was := {}  ## slot -> carry
var _ring_was := {}  ## slot -> had a ring last frame
var _hold_t := {}  ## slot -> seconds A has been held (since the last count)


func setup(m: Node) -> void:
	main = m
	name = "Teach"
	var mat := MeshKit.material(Color(1.0, 0.85, 0.3), 2.5)
	arrow = CueScript.make_arrow(mat, 1.0)
	arrow.name = "CueArrow"
	main.world_root.add_child(arrow)
	if main.vr_rig != null:
		var sm := SphereMesh.new()
		sm.radius = 0.012
		sm.height = 0.024
		sm.radial_segments = 10
		sm.rings = 5
		for h in [main.vr_rig.hand_l, main.vr_rig.hand_r]:
			var b := MeshInstance3D.new()
			b.name = "CueButton"
			b.mesh = sm
			b.material_override = mat
			b.layers = Data.LAYER_VR_ONLY
			b.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			b.position = Vector3(0.0, 0.02, 0.03)
			(h as Node3D).add_child(b)
			vr_buttons.append(b)
	var party: Party = main.party
	party.device_lost.connect(func(_slot: int) -> void: main.sfx.play("pop", -8.0, 0.6))
	party.device_restored.connect(func(_slot: int) -> void: main.sfx.play("ding", -8.0, 1.3))
	party.join_refused.connect(func(_dev: int, why: String) -> void:
		if why == "full":
			main.sfx.play("pop", -10.0, 0.7))


# --- What's been done -------------------------------------------------------------------------------

## Player `slot` has done `key` once more; its cue goes once done twice.
func cue_did(slot: int, key: String) -> void:
	var done: Dictionary = cue_done.get(slot, {})
	done[key] = int(done.get(key, 0)) + 1
	cue_done[slot] = done


func cue_learned(slot: int, key: String) -> bool:
	var done: Dictionary = cue_done.get(slot, {})
	return int(done.get(key, 0)) >= 2


## Host / local: what the pilot just did (out / intent from pilot.update).
func note_pilot(out: Dictionary, intent: Dictionary, phase: String) -> void:
	if phase != "play":
		_beam_was = false
		return
	if not (out.get("punches", []) as Array).is_empty():
		cue_did(0, "punch")
	var beam: bool = bool(out.get("beam", false)) and main.move_ok("beam")
	if beam and not _beam_was:
		cue_did(0, "beam")
	_beam_was = beam
	if bool(intent.get("dash", false)):
		cue_did(0, "dash")


# --- Views --------------------------------------------------------------------------------------------

## A TV player's view was made (slot >= 0): its cue and edge arrow, the rows built on the first tick.
func add_view(slot: int, ui: Control) -> void:
	var edge := CueScript.EdgeArrow.new()
	ui.add_child(edge)
	var cue := CueScript.new()
	ui.add_child(cue)
	views[slot] = {"cue": cue, "edge": edge, "sig": ""}


## The shared view's join cue (pulsing A + plus + person), built once.
func make_join(ui: Control) -> Control:
	var jc := CueScript.join_row()
	ui.add_child(jc)
	UiKit.pin(jc, Control.PRESET_BOTTOM_RIGHT, false)
	jc.offset_left = -200
	jc.offset_top = -74
	jc.offset_right = -16
	jc.offset_bottom = -10
	var tw := jc.create_tween().set_loops()
	tw.tween_property(jc, "modulate:a", 0.5, 0.7)
	tw.tween_property(jc, "modulate:a", 1.0, 0.7)
	return jc


## A seat's player left: forget what they learned (the next player sees the cues again).
func player_left(slot: int) -> void:
	views.erase(slot)
	cue_done.erase(slot)
	_carry_was.erase(slot)
	_ring_was.erase(slot)
	_hold_t.erase(slot)
	main.sfx.play("pop", -10.0, 0.6)  # no sentence: a soft puff


func _build_rows(slot: int, cue: CueScript, kb: bool, sc: float) -> void:
	cue.clear_rows()
	cue.s = sc
	cue.add_row("plug", [UiKit.icon("bolt", Color(1.0, 0.8, 0.3), 64.0 * sc)])
	if slot == 0:
		var b1 := CueScript.bat_icon(46.0 * sc)
		var f := CueScript.fist_icon(44.0 * sc)
		cue.add_row("punch", [UiKit.glyph("F" if kb else "X", sc), f, b1], [f, b1])
		var b2 := CueScript.bat_icon(46.0 * sc)
		var bm := CueScript.beam_icon(40.0 * sc)
		cue.add_row("beam", [UiKit.glyph("CTRL" if kb else "RT", sc), bm, b2], [bm, b2])
		var r := CueScript.ring_icon(56.0 * sc, Color(1.0, 0.9, 0.35))
		cue.add_row("dash", [UiKit.glyph("SPACE" if kb else "A", sc), UiKit.icon("arrow_up", GOLD, 44.0 * sc), r], [r])
		return
	var mv := "W" if kb else "STICK"
	var act := "SPACE" if kb else "A"
	for kind in Data.VEHICLES:
		var info: Dictionary = Data.VEHICLE_INFO[kind]
		var rg := CueScript.ring_icon(56.0 * sc)
		cue.add_row("ring_" + kind, [UiKit.glyph(mv, sc), CueScript.vehicle_icon(kind, info["color"], 44.0 * sc),
			UiKit.icon("arrow_right", GOLD, 36.0 * sc), rg], [rg])
		cue.add_row("swap_" + kind, [UiKit.glyph("R" if kb else "Y", sc), UiKit.icon("arrow_right", GOLD, 36.0 * sc),
			CueScript.vehicle_icon(kind, info["color"], 48.0 * sc)])
	cue.add_row("act_jet", [UiKit.glyph(act, sc), UiKit.icon("bolt", Color(1.0, 0.85, 0.3), 44.0 * sc), CueScript.kaiju_icon(50.0 * sc)])
	cue.add_row("act_tank", [UiKit.glyph(act, sc), UiKit.icon("bolt", Color(0.8, 0.65, 1.0), 44.0 * sc), CueScript.kaiju_icon(50.0 * sc)])
	cue.add_row("act_drone", [UiKit.glyph(act, sc), UiKit.icon("plus", Color(0.45, 1.0, 0.55), 44.0 * sc), CueScript.titan_icon(50.0 * sc)])
	var truck: Dictionary = Data.VEHICLE_INFO["truck"]
	var ppl := CueScript.people_icon(46.0 * sc)
	cue.add_row("pickup", [UiKit.glyph(mv, sc), CueScript.vehicle_icon("truck", truck["color"], 44.0 * sc),
		UiKit.icon("arrow_right", GOLD, 36.0 * sc), ppl], [ppl])
	cue.add_row("deliver", [UiKit.glyph(mv, sc), CueScript.vehicle_icon("truck", truck["color"], 44.0 * sc),
		UiKit.icon("arrow_right", GOLD, 36.0 * sc), CueScript.shelter_icon(50.0 * sc)])


# --- Every frame ---------------------------------------------------------------------------------------

func tick(delta: float) -> void:
	var phase := String(main.net.state_get("phase", ""))
	_update_arrow(phase)
	for slot in views.keys():
		var v: Dictionary = views[slot]
		var cue: CueScript = v["cue"]
		if not is_instance_valid(cue):
			views.erase(slot)
			continue
		var sc := cue.want_scale()
		if sc <= 0.0:
			continue
		var kb: bool = main.party.device_of(slot) == Party.KEYBOARD
		var sig := "%.1f|%d" % [sc, int(kb)]
		if String(v["sig"]) != sig:
			v["sig"] = sig
			_build_rows(int(slot), cue, kb, sc)
		_learn(int(slot), phase)
		var kt := _cue_now(int(slot), phase)
		var k: String = kt[0]
		cue.show_cue(k, delta)
		var edge: CueScript.EdgeArrow = v["edge"]
		edge.cam = main.view_camera(int(slot))
		edge.target = kt[1]
		edge.on = k != "" and k != "plug" and kt[1] != Vector3.INF and not edge.target_in_view()


## Learn from what a TV seat does on this machine (support vehicles; the pilot is note_pilot).
func _learn(slot: int, phase: String) -> void:
	if slot == 0 or phase != "play":
		return
	var v: Support.Vehicle = main.support.vehicles.get(slot, null)
	if v == null:
		return
	var party: Party = main.party
	# a press, or every 1.5 s of holding A (the jet's guns and the repair beam are hold-to-use)
	var held := float(_hold_t.get(slot, 0.0))
	if party.pressed(slot, "accept"):
		held += get_process_delta_time()
		if party.just_pressed(slot, "accept") or held >= 1.5:
			cue_did(slot, "act_" + v.kind)
			held = 0.0
	_hold_t[slot] = held
	if party.just_pressed(slot, "y"):
		cue_did(slot, "swap")
	var carry := v.carry
	var was := int(_carry_was.get(slot, carry))
	if carry > was:
		cue_did(slot, "pickup")
	elif carry < was:
		cue_did(slot, "deliver")
	_carry_was[slot] = carry
	var ring := (main.net.state_get("rings", {}) as Dictionary).has(str(slot))
	if bool(_ring_was.get(slot, false)) and not ring:
		cue_did(slot, "ring")
	_ring_was[slot] = ring


## [cue key, world point it's about (INF = none)] for a TV seat now.
func _cue_now(slot: int, phase: String) -> Array:
	var party: Party = main.party
	if party.is_lost(slot):
		return ["plug", Vector3.INF]
	if phase != "play" or main.get_tree().paused or main.slot_busy(slot):
		return ["", Vector3.INF]
	var rings: Dictionary = main.net.state_get("rings", {})
	if slot == 0:
		if rings.has("dash") and not cue_learned(0, "dash"):
			return ["dash", rings["dash"]]
		var bat := _practice_bat()
		if bat != null:
			var far: bool = (bat.center() - main.mech.chest_world()).length() > 20.0
			var kk := "beam" if far and main.move_ok("beam") else "punch"
			if not cue_learned(0, kk):
				return [kk, bat.center()]
			return ["", Vector3.INF]
		var boss := _boss()
		if boss == null:
			return ["", Vector3.INF]
		if not cue_learned(0, "punch"):
			return ["punch", boss.center()]
		if main.move_ok("beam") and not cue_learned(0, "beam"):
			return ["beam", boss.center()]
		if main.move_ok("dash") and not cue_learned(0, "dash"):
			return ["dash", boss.center()]
		return ["", Vector3.INF]
	var v: Support.Vehicle = main.support.vehicles.get(slot, null)
	if v == null:
		return ["", Vector3.INF]
	if rings.has(str(slot)) and not cue_learned(slot, "ring"):
		return ["ring_" + v.kind, rings[str(slot)]]
	match v.kind:
		"truck":
			if v.carry > 0 and not cue_learned(slot, "deliver") and not main.city.shelters.is_empty():
				return ["deliver", main.support._nearest_shelter(v.global_position)]
			var gi: int = main.support._nearest_group(v.global_position)
			if v.carry == 0 and gi >= 0 and not cue_learned(slot, "pickup"):
				return ["pickup", main.support.groups[gi]["pos"]]
		"drone":
			if not cue_learned(slot, "act_drone"):
				return ["act_drone", main.mech.chest_world()]
		_:
			var k := _boss()
			if k != null and not cue_learned(slot, "act_" + v.kind):
				return ["act_" + v.kind, k.center()]
	var kinds: Array = main.vehicle_kinds()
	if kinds.size() > 1 and not cue_learned(slot, "swap"):
		var nk: String = kinds[(kinds.find(v.kind) + 1) % kinds.size()]
		return ["swap_" + nk, Vector3.INF]
	return ["", Vector3.INF]


func _practice_bat() -> Kaiju:
	for id in main.combat.kaiju:
		var k: Kaiju = main.combat.kaiju[id]
		if k.state == "practice":
			return k
	return null


## The kaiju to go for: a dizzy one first, else the biggest one still about.
func _boss() -> Kaiju:
	var best: Kaiju = null
	for id in main.combat.kaiju:
		var k: Kaiju = main.combat.kaiju[id]
		if k.state == "home" or k.state == "gone" or k.state == "practice":
			continue
		if k.state == "dizzy":
			return k
		if best == null or (best.is_mini and not k.is_mini):
			best = k
	return best


## The glowing 3D arrow over the practice bat / the pilot's dash ring / a dizzy kaiju; the VR buttons.
func _update_arrow(phase: String) -> void:
	var t := Time.get_ticks_msec() / 1000.0
	var bob := absf(sin(t * 4.0))
	if _warm > 0:
		_warm -= 1  # shown for a few frames at load, so their first draw isn't mid-game
		arrow.visible = true
		arrow.global_position = main.mech.chest_world() + main.mech.forward() * 12.0
		for b in vr_buttons:
			b.visible = true
		return
	arrow_kind = ""
	var at := Vector3.INF
	var size_m := 1.0
	if phase == "play":
		var rings: Dictionary = main.net.state_get("rings", {})
		if rings.has("dash"):
			arrow_kind = "dash"
			at = (rings["dash"] as Vector3) + Vector3.UP * 7.0
			size_m = 4.0
		else:
			var bat := _practice_bat()
			if bat != null:
				arrow_kind = "bat"
				at = bat.center() + Vector3.UP * 1.4
				size_m = 1.2
			else:
				for id in main.combat.kaiju:
					var k: Kaiju = main.combat.kaiju[id]
					if not k.is_mini and k.state == "dizzy":
						arrow_kind = "dizzy"
						at = k.center() + Vector3.UP * (k.height * 0.6 + 1.0)
						size_m = clampf(k.height * 0.35, 2.5, 6.0)
						break
	arrow.visible = at != Vector3.INF
	if arrow.visible:
		arrow.global_position = at + Vector3.UP * (0.25 * size_m * bob)
		arrow.scale = Vector3.ONE * size_m
		arrow.rotation.y = t * 2.0
	var btn := arrow_kind == "dash" and not cue_learned(0, "dash")
	for b in vr_buttons:
		b.visible = btn
		if btn:
			b.scale = Vector3.ONE * (1.0 + 0.5 * bob)
