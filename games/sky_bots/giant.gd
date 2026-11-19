extends Node3D
## SKY BOTS: the GIANT (the VR player, host). The islands float at waist height in front of a giant standing on the
## cloud floor (world scale S: a robot is about 10 cm tall), like a toy diorama. The giant HELPS with their hands:
##   - grab a LIFT's yellow handle with the right trigger and lift it up (or down) for the robots; let go and it carries
##     on by itself
##   - flick a GRUMBLE off its floor (touch it with a moving hand), poke CRANKY CRAB while it's dizzy
##   - poke the secret room's CRACKED WALL open, pick up bolts, boop a robot (a little hop)
##   - every island's GIANT JOB (levelgen.gd _job): pull the DRAWBRIDGES down (trigger on a tip's knob), turn the
##     CRANK round (trigger on its handle, circle), throw the BOULDER away (trigger on it, carry it off), smash the ICE
##     WALL (hit it hard, three times), push the PALM TREES over (just push their crowns down), swing the CLOCK HAND
##     round (trigger on its tip). The robots wait for the giant (a button wakes up if the giant takes too long).
##   - left stick walks along the islands, right stick snap-turns
## Without a VR giant the lifts just go up and down by themselves; everything can be done without one (levelgen.gd
## check() never counts on the giant).
## The TV machine draws the giant's head and gloves (giant-sized) from VrRig.pack_pose().

const VrRig := preload("res://core/vr_rig.gd")
const G := preload("res://games/sky_bots/levelgen.gd")

const S := 10.0  ## XR world scale: 10 units = 1 real metre
const FLOOR_Y := -8.0  ## the cloud floor the giant stands on (the islands are about 0.8 m up)
const FEET_Z := 7.0
const WALK_X := 44.0  ## levelgen.gd X_MIN / X_MAX
const GRAB_R := 1.3  ## a hand this near a lift's handle grabs it with the trigger
const TOUCH_R := 0.8

var main: Node
var rig: VrRig
var host := true
var held_lift := -1
var grab_dy := 0.0
var touch_on := [{}, {}]
var lifts_used := 0
var flicks := 0
var held_job := -1  ## the job whose piece the right hand holds
var held_piece := 0
var crank_last := NAN
var jobs_done := 0  ## jobs the giant's hands opened (telemetry, bots)
var job_moves := 0  ## times the giant moved a job (bots)
var _last_hand: Array = [Vector3.INF, Vector3.INF]
var _hit_cd: Array = [0.0, 0.0]
const JOB_GRAB_R := 1.7
const BOULDER_GRAB_R := 2.4
const SMASH_SPEED := 5.0  ## a hand this fast (world units / s; 0.5 m/s for real) smashes ice
const BOULDER_AWAY := 3.0  ## carry the boulder this far and it's thrown
var avatar_head: Node3D
var avatar_hands: Array[Node3D] = []


func setup(m: Node, r: VrRig, is_host: bool) -> void:
	main = m
	rig = r
	host = is_host
	if rig != null:
		rig.set_scale_of_world(S)
		rig.move_speed = 0.5 * S
		rig.bounds = Rect2(-WALK_X, FEET_Z - 2.0, WALK_X * 2.0, 5.0)
		rig.camera.far = 3000.0
		rig.camera.near = 0.05
		rig.place(feet(), 0.0)


## Where the giant stands: on the cloud floor in front of the islands (+Z), facing them (-Z).
static func feet() -> Vector3:
	return Vector3(0.0, FLOOR_Y, FEET_Z)


## Host, every physics frame while an island is up: the hands.
func step(delta: float) -> void:
	if not host or rig == null:
		return
	var level: Node = main.level
	var playing := level != null and not (level.lv as Dictionary).is_empty() and String(main.net.state_get("phase", "")) == "play"
	if not playing:
		if held_lift >= 0 and level != null:
			level.hold_lift(held_lift, NAN)
		held_lift = -1
		held_job = -1
		return
	if _jobs(delta, level):
		return  # (the right hand is busy with a job)
	var hr := rig.hand_point(VrRig.RIGHT)
	if held_lift >= 0:
		if rig.trigger_down():
			level.hold_lift(held_lift, hr.y - grab_dy)
		else:
			level.hold_lift(held_lift, NAN)
			held_lift = -1
			rig.pulse(VrRig.RIGHT, 0.3, 0.05)
	elif rig.trigger_pressed() and not _grab_job(level, hr):
		var best := -1
		var bd := GRAB_R
		for i in level.lifts():
			var d: float = level.handle_point(i).distance_to(hr)
			if d < bd:
				bd = d
				best = i
		if best >= 0:
			held_lift = best
			grab_dy = hr.y - level.plat_pos(best).y
			lifts_used += 1
			main.on_lift_grabbed()
			main.sound_at("pop", hr, -6.0, 0.9)
			rig.pulse(VrRig.RIGHT, 0.5, 0.06)
	for h in 2:
		var p := rig.hand_point(h)
		var now := {}
		for i in level.grumbles.size():
			if level.grumble_alive(i) and p.distance_to(level.grumble_pos(i) + Vector3(0, 0.4, 0)) < TOUCH_R:
				now["g%d" % i] = true
				if not touch_on[h].has("g%d" % i):
					flicks += 1
					main.pop_grumble(i, "giant")
					rig.pulse(h, 0.5, 0.06)
		if level.near_wall(p, 0.4):
			now["wall"] = true
			if not touch_on[h].has("wall"):
				main.break_wall("giant")
				rig.pulse(h, 0.6, 0.08)
		var k: int = level.bolt_at(p, 0.6)
		if k >= 0:
			main.take_bolt(k, 0)
		var bx: int = level.box_near(p, 0.6)  # (a finger taps a bot box open)
		if bx >= 0:
			main.open_box(bx, 0)
			rig.pulse(h, 0.5, 0.06)
		if main.boss != null and main.boss.alive() and p.distance_to(main.boss.position + Vector3(0, 0.9, 0)) < 1.4:
			now["boss"] = true
			if not touch_on[h].has("boss") and main.boss_hit("giant"):
				rig.pulse(h, 0.7, 0.1)
		for rid in main.robots:
			var rb: Node3D = main.robots[rid]
			if p.distance_to(rb.position + Vector3(0, 0.6, 0)) < TOUCH_R:
				now["r%d" % int(rid)] = true
				if not touch_on[h].has("r%d" % int(rid)):
					main.boop(int(rid))
					rig.pulse(h, 0.3, 0.04)
		touch_on[h] = now


# --- The TV machine: the giant as seen from there ------------------------------------------------------------------

func make_avatar() -> void:
	var mat := VrRig.vertex_color_material()
	avatar_head = Node3D.new()
	add_child(avatar_head)
	var face := MeshInstance3D.new()
	face.mesh = VrRig.VrRigStatics.head_mesh(Color(0.4, 0.75, 1.0))
	face.material_override = mat
	face.scale = Vector3.ONE * S
	face.layers = VrRig.AVATAR_LAYER
	avatar_head.add_child(face)
	for i in 2:
		var n := Node3D.new()
		add_child(n)
		var g := MeshInstance3D.new()
		g.mesh = VrRig.glove_mesh(i == 0, Color(1.0, 0.86, 0.6), Color.WHITE)
		g.material_override = mat
		g.scale = Vector3.ONE * S
		g.layers = VrRig.AVATAR_LAYER
		n.add_child(g)
		avatar_hands.append(n)
	avatar_head.visible = false
	for n in avatar_hands:
		n.visible = false


func apply_pose(p: PackedFloat32Array, delta: float) -> void:
	if avatar_head == null:
		return
	if p.size() < 21:
		avatar_head.visible = false
		for n in avatar_hands:
			n.visible = false
		return
	var nodes: Array[Node3D] = [avatar_head, avatar_hands[0], avatar_hands[1]]
	for i in 3:
		var o := i * 7
		var t := Transform3D(Basis(Quaternion(p[o + 3], p[o + 4], p[o + 5], p[o + 6]).normalized()), Vector3(p[o], p[o + 1], p[o + 2]))
		var n := nodes[i]
		if not n.visible:
			n.global_transform = t
			n.visible = true
		else:
			n.global_transform = n.global_transform.interpolate_with(t, 1.0 - exp(-15.0 * delta))


# --- GIANT JOBS ----------------------------------------------------------------------------------------------------

## A fresh right trigger pull near a job's handle grabs it (true: taken).
func _grab_job(level: Node, hr: Vector3) -> bool:
	var jobs: Array = level.lv.get("jobs", [])
	var best := -1
	var bp := 0
	var bd := INF
	for j in jobs.size():
		var job: Dictionary = jobs[j]
		var kind := String(job.kind)
		if level.job_open(j) or kind == "ice" or kind == "tree":
			continue
		for i in (level.jobs_prog[j] as Array).size():
			var d := G.gate_handle(job, i, level.lv.plats, float(level.jobs_prog[j][i])).distance_to(hr)
			var lim := BOULDER_GRAB_R if kind == "boulder" else JOB_GRAB_R
			if d < lim and d < bd and float(level.jobs_prog[j][i]) < 1.0:
				bd = d
				best = j
				bp = i
	if best < 0:
		return false
	held_job = best
	held_piece = bp
	crank_last = NAN
	main.sound_at("pop", hr, -6.0, 0.8)
	rig.pulse(VrRig.RIGHT, 0.5, 0.06)
	return true


## Every physics frame: the held job follows the right hand; ice and palm trees by touch (either hand). True while
## the right hand holds a job (no lift grabs then).
func _jobs(delta: float, level: Node) -> bool:
	var jobs: Array = level.lv.get("jobs", [])
	if jobs.is_empty():
		return false
	var speed := [0.0, 0.0]
	for h in 2:
		var p := rig.hand_point(h)
		var last: Vector3 = _last_hand[h]
		speed[h] = 0.0 if last == Vector3.INF or delta <= 0.0 else p.distance_to(last) / delta
		_last_hand[h] = p
		_hit_cd[h] = maxf(0.0, float(_hit_cd[h]) - delta)
	# Touch jobs: smash the ice, push the palm trees over.
	for j in jobs.size():
		var job: Dictionary = jobs[j]
		if level.job_open(j):
			continue
		match String(job.kind):
			"ice":
				var bc: Vector3 = job.block.c
				var bs: Vector3 = job.block.s
				for h in 2:
					var p := rig.hand_point(h)
					var rel := p - (bc + Vector3(0, bs.y * 0.5, 0))
					if absf(rel.x) < bs.x * 0.5 + 0.6 and absf(rel.y) < bs.y * 0.5 + 0.6 and absf(rel.z) < bs.z * 0.5 + 0.6 \
							and float(speed[h]) > SMASH_SPEED and float(_hit_cd[h]) <= 0.0:
						_hit_cd[h] = 0.45
						var k := float(level.jobs_prog[j][0]) + 1.0 / 3.0
						level.set_job(j, 0, 1.0 if k > 0.98 else k)
						job_moves += 1
						rig.pulse(h, 0.9, 0.12)
						main.job_hit(j, p)
			"tree":
				for i in (level.jobs_prog[j] as Array).size():
					var k := float(level.jobs_prog[j][i])
					if k >= 0.5:
						continue  # (it's falling by itself now)
					var pv: Vector3 = job.pivots[i]
					var d := float(job.dirs[i])
					var tip := G.gate_handle(job, i, level.lv.plats, k)
					for h in 2:
						var p := rig.hand_point(h)
						if p.distance_to(tip) < 2.0 and absf(p.z - pv.z) < 2.5:
							var ang := atan2(p.y - pv.y, (p.x - pv.x) * d)
							var want := 1.0 - clampf(ang, 0.0, PI * 0.5) / (PI * 0.5)
							if want > k + 0.01:
								level.set_job(j, i, want)
								job_moves += 1
								if want >= 0.5:
									main.job_hit(j, p)
								rig.pulse(h, 0.2, 0.03)
	if held_job < 0:
		return false
	var hj := held_job
	var job: Dictionary = jobs[hj]
	var hr := rig.hand_point(VrRig.RIGHT)
	if level.job_open(hj) or not rig.trigger_down():
		# Let go: a bridge almost down drops into place; the boulder goes back.
		if String(job.kind) != "boulder" and float(level.jobs_prog[hj][held_piece]) > 0.85:
			level.set_job(hj, held_piece, 1.0)
		if String(job.kind) == "boulder":
			level.job_held[hj] = Vector3.INF
			if not level.job_open(hj):
				level.set_job(hj, 0, 0.0)
		held_job = -1
		rig.pulse(VrRig.RIGHT, 0.3, 0.05)
		return false
	var before := float(level.jobs_prog[hj][held_piece])
	match String(job.kind):
		"bridge":
			var pv: Vector3 = job.pivots[held_piece]
			var d := float(job.dirs[held_piece])
			var ang := atan2(hr.y - pv.y, (hr.x - pv.x) * d)
			level.set_job(hj, held_piece, 1.0 - clampf(ang, 0.0, PI * 0.5) / (PI * 0.5))
		"clock":
			var pv2: Vector3 = job.pivots[0]
			var th := atan2(hr.z - pv2.z, hr.x - pv2.x)
			level.set_job(hj, 0, 1.0 - absf(sin(th)))
		"crank":
			var cc: Vector3 = job.crank
			var a := atan2(hr.y - cc.y, hr.x - cc.x)
			if not is_nan(crank_last):
				var da := absf(wrapf(a - crank_last, -PI, PI))
				level.set_job(hj, 0, before + da / (TAU * 2.0))
			crank_last = a
		"boulder":
			var bc: Vector3 = job.block.c
			var home := bc + Vector3(0, (job.block.s as Vector3).y * 0.6, 0)
			level.job_held[hj] = hr
			level.set_job(hj, 0, minf(1.0, hr.distance_to(home) / BOULDER_AWAY))
	var now := float(level.jobs_prog[hj][held_piece])
	if absf(now - before) > 0.0001:
		job_moves += 1
		if int(now * 8.0) != int(before * 8.0):
			rig.pulse(VrRig.RIGHT, 0.25, 0.03)
			main.job_tick(hj, hr, now)
	if now >= 0.98:  # locked in place: the hand lets go (the next pull takes the next piece)
		level.set_job(hj, held_piece, 1.0)
		if String(job.kind) != "boulder":
			held_job = -1
			main.sound_at("land", hr, -4.0, 0.7)
			rig.pulse(VrRig.RIGHT, 0.6, 0.1)
	return true
