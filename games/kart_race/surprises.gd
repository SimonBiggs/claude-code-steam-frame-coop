extends Node3D
## KART RACE SURPRISES + HAZARD TELLS (deep.gd): every tell goes through core/warn_rings.gd.
##  - Host: from the second race of a cup / tour place, when a person comes up to one of the track's surprise spots
##    (trackgen.gd: proven to leave a wide clear lane), it may go off: every machine shows a steady glowing circle on
##    the road for Deep.TELL seconds while the thing (gumball, coconut, snowball, meteor, ball, acorn) falls out of the
##    sky into it; it lands, the circle glows hot for Deep.STAY, and karts inside spin out (harmless; a star or a
##    bubble saves you). It can never land before its circle has shown for TELL seconds (st.early counts any that did).
##    Then it bounces off the side of the road and is gone.
##  - Every machine, for its own karts: the cups' puddles / ice / moon pads / bumpers get a glowing outline as you
##    come up to them, so nothing on the road is a surprise.
##   main.gd: surprises.begin(kind) at a race start, host_update(dt) on the host while racing, update(dt) everywhere,
##   tell(i, kind) on every machine (the "surprise" event), stop() after the race.

const WarnRings := preload("res://core/warn_rings.gd")
const Deep := preload("res://games/kart_race/deep.gd")

var main
var rings: WarnRings
var kind := ""  # this race's surprise ("" = none)
var drops: Array = []  # {i, kind, t, pos, dir, side, node, hits: {}}
var cool := {}  # host: spot index -> seconds before it may go off again
var hz_cool := {}  # hazard index -> seconds before its outline shows again (this machine)
var st := {"tells": 0, "lands": 0, "hits": 0, "early": 0, "saved": 0, "hz_tells": 0, "min_tell": INF}


func _ready() -> void:
	rings = WarnRings.new()
	rings.name = "Rings"
	add_child(rings)


## A new race (every machine): what drops here ("" none).
func begin(k: String) -> void:
	stop()
	kind = k


func stop() -> void:
	kind = ""
	for d in drops:
		if is_instance_valid(d.node):
			d.node.queue_free()
	drops.clear()
	cool.clear()
	hz_cool.clear()
	rings.clear()


func active() -> int:
	var n := 0
	for d in drops:
		if float(d.t) < Deep.TELL + Deep.STAY:
			n += 1
	return n


## Host, while racing: people coming up to a spot may set it off; landings spin karts in the circle.
func host_update(dt: float) -> void:
	var tr = main.track
	for i in cool:
		cool[i] = float(cool[i]) - dt
	if kind != "" and not tr.surprises.is_empty():
		var rate: Dictionary = Deep.RATE.get(main.speed_mode, Deep.RATE.gentle)
		for i in tr.surprises.size():
			if float(cool.get(i, 0.0)) > 0.0 or active() >= int(rate.max):
				continue
			var sp: Array = tr.surprises[i]
			for k in main.players:
				if not k.active or k.finished:
					continue
				var d := fposmod(float(sp[0]) - k.s, tr.length)
				if d > Deep.TRIGGER[0] and d < Deep.TRIGGER[1]:
					cool[i] = 14.0  # one roll per approach
					if randf() < float(rate.chance) or OS.has_environment("KART_SURPRISE"):
						main.surprise(i, kind)
					break
	for d in drops:
		var t := float(d.t)
		if t < Deep.TELL or t > Deep.TELL + Deep.STAY:
			continue
		for k in main.karts:
			if not k.active or d.hits.has(k.index):
				continue
			if WarnRings.inside("circle", d.pos, d.dir, Vector2(Deep.R, 0.0), k.position, 0.3) and absf(k.position.y - d.pos.y) < 2.5:
				d.hits[k.index] = true
				st.hits += 1
				if t < Deep.TELL - 0.01:
					st.early += 1
				st.min_tell = minf(float(st.min_tell), t)
				main.surprise_hit(k, d.pos, String(d.kind))


## Every machine: spot i goes off (the glowing circle now, the thing lands in Deep.TELL seconds).
func tell(i: int, k: String) -> void:
	var tr = main.track
	if i < 0 or i >= tr.surprises.size():
		return
	var sp: Array = tr.surprises[i]
	var s := float(sp[0])
	var lat := float(sp[1])
	var c: Vector3 = tr.point_at(s, lat)[0]
	var top := c.y
	for e in [[s - Deep.R, lat], [s + Deep.R, lat], [s, lat - Deep.R], [s, lat + Deep.R]]:
		top = maxf(top, float((tr.point_at(float(e[0]), float(e[1]))[0] as Vector3).y))
	var dir: Vector3 = (tr.point_at(s + 1.0, lat)[0] as Vector3) - c
	dir.y = 0.0
	dir = dir.normalized() if dir.length() > 0.01 else Vector3.FORWARD
	c.y = top
	rings.shape("circle", c, dir, Vector2(Deep.R, 0.0), Deep.RING_COLOR, Deep.TELL,
		{"style": "disc", "alpha": 0.4, "stay": Deep.STAY, "hot": Deep.HOT_COLOR, "y": top + 0.1})
	var n := _model(k)
	n.position = c + Vector3(0, 40.0, 0)
	add_child(n)
	drops.append({"i": i, "kind": k, "t": 0.0, "pos": c, "dir": dir, "side": signf(lat), "node": n, "hits": {}})
	st.tells += 1


## Every machine: falling things, landings, the hazards' outlines for this machine's karts.
func update(dt: float) -> void:
	var i := 0
	while i < drops.size():
		var d: Dictionary = drops[i]
		var was := float(d.t)
		d.t = was + dt
		var t := float(d.t)
		var n: Node3D = d.node
		var c: Vector3 = d.pos
		var fall := 0.9  # seconds of falling at the end of the tell (before that it waits high up, out of sight)
		if t < Deep.TELL:
			var f := clampf((t - (Deep.TELL - fall)) / fall, 0.0, 1.0)
			n.visible = f > 0.0
			n.position = c + Vector3(0, 1.2 + 26.0 * (1.0 - f * f), 0)
			n.rotation.x += dt * 4.0
		else:
			if was < Deep.TELL:
				st.lands += 1
				main.surprise_landed(c, String(d.kind))
			var a := t - Deep.TELL  # bounce off the side of the road and away
			var side := Vector3(-d.dir.z, 0, d.dir.x) * float(d.side)
			n.position = c + side * a * 7.0 + Vector3(0, 1.2 + absf(sin(a * 5.0)) * 2.2 * maxf(0.0, 1.0 - a * 0.6), 0)
			n.rotation.z -= dt * 6.0 * float(d.side)
			n.scale = Vector3.ONE * clampf(2.2 - a, 0.01, 1.0)
		if t > Deep.TELL + 2.2:
			n.queue_free()
			drops.remove_at(i)
			continue
		i += 1
	_hazard_tells(dt)


func _hazard_tells(dt: float) -> void:
	for h in hz_cool:
		hz_cool[h] = float(hz_cool[h]) - dt
	var tr = main.track
	if tr.hazards.is_empty() or main.state != "race":
		return
	for k in main.players:
		if not k.active or not k.is_local() or k.finished:
			continue
		for hi in tr.hazards.size():
			if float(hz_cool.get(hi, 0.0)) > 0.0:
				continue
			var h: Array = tr.hazards[hi]
			var s0 := float(h[0])
			var bump := String(h[2]) == "bump"
			var size := float(h[3])
			var d := fposmod(s0 - (size if bump else 0.0) - k.s, tr.length)
			if d < 12.0 or d > 55.0:
				continue
			hz_cool[hi] = 7.0
			st.hz_tells += 1
			var lat := float(h[1])
			var a: Vector3 = tr.point_at(s0, lat)[0]
			if bump:
				rings.shape("circle", a, Vector3.FORWARD, Vector2(size + 0.6, 0.0), Deep.HAZARD_TELL, 2.6,
					{"style": "disc", "alpha": 0.22, "y": a.y + 0.1})
			else:
				var ln := float(h[4])
				var b: Vector3 = tr.point_at(s0 + ln, lat)[0]
				var dir := Vector3(b.x - a.x, 0.0, b.z - a.z)
				rings.shape("line", Vector3(a.x, 0, a.z) - dir.normalized() * 0.5, dir, Vector2(dir.length() + 1.0, size * 2.0 + 0.8),
					Deep.HAZARD_TELL, 2.6, {"style": "disc", "alpha": 0.22, "y": maxf(a.y, b.y) + 0.1})


## The falling thing (one merged mesh, kart-sized).
func _model(k: String) -> Node3D:
	var info: Dictionary = Deep.SURPRISES.get(k, Deep.SURPRISES.bouncyball)
	var body: Color = info.body
	var det: Color = info.detail
	var st2 := SurfaceTool.new()
	st2.begin(Mesh.PRIMITIVE_TRIANGLES)
	match k:
		"acorn":
			main.add_ellipsoid(st2, Vector3(0, -0.15, 0), Vector3(0.9, 1.1, 0.9), body, 12, 8)
			main.add_ellipsoid(st2, Vector3(0, 0.6, 0), Vector3(1.05, 0.5, 1.05), det, 12, 6)
			main.add_cyl(st2, Vector3(0, 1.15, 0), 0.1, 0.4, det.darkened(0.2))
		"coconut":
			main.add_ellipsoid(st2, Vector3.ZERO, Vector3(1.1, 1.0, 1.1), body, 12, 8)
			for a in [0.0, 2.1, 4.2]:
				main.add_ellipsoid(st2, Vector3(cos(a) * 0.3, 0.92, sin(a) * 0.3), Vector3(0.14, 0.1, 0.14), det, 6, 3)
		"meteor":
			main.add_ellipsoid(st2, Vector3.ZERO, Vector3(1.15, 1.0, 1.05), body, 10, 6)
			for a in [0.4, 2.0, 3.6, 5.1]:
				main.add_ellipsoid(st2, Vector3(cos(a) * 0.8, 0.4, sin(a) * 0.8), Vector3(0.3, 0.3, 0.3), det, 6, 3)
		"beachball":
			main.add_ellipsoid(st2, Vector3.ZERO, Vector3(1.1, 1.1, 1.1), body, 14, 8)
			for j in 3:
				var a := TAU * j / 3.0
				main.add_ellipsoid(st2, Vector3(cos(a) * 0.55, 0, sin(a) * 0.55), Vector3(0.62, 1.05, 0.62),
					[det, Color(0.3, 0.6, 1.0), Color(1.0, 0.85, 0.2)][j], 10, 6)
		_:
			main.add_ellipsoid(st2, Vector3.ZERO, Vector3(1.1, 1.1, 1.1), body, 14, 8)
			main.add_ellipsoid(st2, Vector3(0.35, 0.55, 0.55), Vector3(0.3, 0.25, 0.3), det, 8, 4)
	var mi := MeshInstance3D.new()
	mi.mesh = st2.commit()
	var m := StandardMaterial3D.new()
	m.vertex_color_use_as_albedo = true
	m.vertex_color_is_srgb = true
	m.roughness = 0.45
	if k == "meteor":
		m.emission_enabled = true
		m.emission = Color(0.6, 0.25, 0.05)
	mi.material_override = m
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
	var root := Node3D.new()
	root.name = "Surprise_" + k
	root.add_child(mi)
	root.visible = false
	return root