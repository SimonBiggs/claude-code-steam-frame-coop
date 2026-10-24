extends RefCounted
## Special boss rules (host only), used by kaiju_ai.gd and combat.gd:
## - PINCHY (crab): a tough shell. Body hits do 30% until both SHELL GEMS on its back are broken;
##   "shell_guard" makes it hide in the shell for a moment (10% damage).
## - WOBBLES (jelly): splits into two smaller jellies when it drops below half health (two generations).
## - DUSTY (moth): flies too high to punch; stun shells (and a full stun meter) knock it down to the
##   ground for a punchable "downed" window.
## - GIGA GRUMBLE (mega kaiju), three phases: 1) armoured (15% body damage) until both shoulder
##   CRYSTALS break; 2) "watch the sky": summons minis and throws rocks until below 40% health;
##   3) the MEGA CORE opens (double damage, it roars).
## `g` is combat.gd.

const Data := preload("res://games/mech_titans/data.gd")

const PHASE3_FRAC := 0.4


## Called while roaming, before picking an attack. True = it did something special this frame.
static func special(k: Node3D, g: Node) -> bool:
	if k.is_mini:
		return false
	if k.kind == "mega":
		if k.phase == 1 and _broken_count(k, ["LEFT CRYSTAL", "RIGHT CRYSTAL"]) >= 2:
			_set_phase(k, 2, g)
			return true
		if k.phase == 2 and k.hp < k.hp_max * PHASE3_FRAC:
			_set_phase(k, 3, g)
			return true
	return false


## May this kaiju use attack `id` right now?
static func attack_allowed(k: Node3D, id: String, _g: Node) -> bool:
	match id:
		"shell_guard":
			return not k.shell_broken and k.hp < k.hp_max * 0.9
		"summon", "rock_throw":
			return k.phase >= 2
		"mega_roar":
			return k.phase >= 3
	return true


## Damage multiplier for a hit on weak spot `weak_i` (-1 = the body).
static func damage_mult(k: Node3D, weak_i: int) -> float:
	var m := 1.0
	if k.state == "stunned" or k.state == "downed":
		m *= 1.5
	if float(k.cooldowns.get("guarding", 0.0)) > 0.0:
		return m * 0.1
	if k.kind == "crab" and not k.shell_broken and weak_i < 0:
		m *= 0.3
	if k.kind == "mega":
		if k.mega_shield and weak_i < 0:
			m *= 0.15
		if k.phase >= 3 and weak_i >= 0 and String(k.weak[weak_i]["name"]) == "MEGA CORE":
			m *= 2.0
	return m


## A weak spot just broke.
static func on_weak_broken(k: Node3D, i: int, g: Node) -> void:
	var wname: String = k.weak[i]["name"]
	g.call("emit_fx", "burst", ["sparks", k.weak_world(i), 3.0])
	if k.kind == "crab" and _broken_count(k, ["SHELL GEM"]) >= 2 and not k.shell_broken:
		k.shell_broken = true
		g.call("announce", "SHELL CRACKED!", "Now PINCHY's soft belly is open!", "good")
	elif k.kind == "mega" and wname.ends_with("CRYSTAL"):
		g.call("announce", "%s BROKEN!" % wname, "Keep going!", "good")
	else:
		g.call("announce", "%s BROKEN!" % wname, "", "good")


## After damage: splits and phase changes that depend on health.
static func after_damage(k: Node3D, g: Node) -> void:
	if k.kind == "jelly" and k.split_gen < 2 and k.hp < k.hp_max * 0.5 and k.hp > 0.0:
		g.call("split_jelly", k)
	elif k.kind == "mega":
		if k.phase < 3 and k.hp < k.hp_max * 0.25:
			k.hp = k.hp_max * 0.25  # a boss can't be beaten before its last phase
		if k.phase == 1 and k.hp < k.hp_max * 0.6:
			k.hp = k.hp_max * 0.6


## A stun shell / full stun meter: flyers drop to the ground (punchable), walkers get stunned.
static func stun_state(k: Node3D) -> String:
	if k.fly_alt > 8.0:
		return "downed"
	return "stunned"


static func _broken_count(k: Node3D, names: Array) -> int:
	var n := 0
	for w in k.weak:
		if bool(w["broken"]) and names.has(String(w["name"])):
			n += 1
	return n


static func _set_phase(k: Node3D, p: int, g: Node) -> void:
	k.phase = p
	match p:
		2:
			k.mega_shield = false
			g.call("announce", "PHASE 2!", "GIGA GRUMBLE calls its friends. Watch the sky!", "boss")
			g.call("summon_minis", k, 4)
		3:
			for i in k.weak.size():
				if String(k.weak[i]["name"]) == "MEGA CORE":
					k.weak[i]["broken"] = false
					(k.weak[i]["node"] as Node3D).visible = true
			g.call("announce", "PHASE 3!", "The MEGA CORE is open: paint it and blast it!", "boss")
	g.call("emit_fx", "ring", [k.global_position + Vector3.UP, 30.0, Color(0.6, 0.4, 1.0)])
	g.call("emit_fx", "sfx", ["power_up", k.global_position, 4.0, 0.6])
