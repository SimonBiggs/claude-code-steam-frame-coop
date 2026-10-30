extends RefCounted
## VrViewCheck: finds VR UI the headset player can't read comfortably. Used by the VrViewCheck service in fake-VR bot
## runs (BOT_VR=1: core/vr_view_watch.gd) and by the VR visual QA sweep (g.eval("VrViewCheck.problems(root)")).
##   const VrViewCheck := preload("res://core/vr_view_check.gd")
##   var probs := VrViewCheck.problems(get_tree().root)   # [] = fine
## Checks every VR card / banner / toast / panel in front of the player (meta "vr_placed": UiKit.vr_place, VrText.follow)
## that is really drawn (visible, not faded out), measured in real metres (XRServer.world_scale divided out):
## - distance from the head between MIN_D and MAX_D (closer hurts to focus or hits the near plane; further is tiny);
## - it faces the head (Label3D reads from +Z; text seen from behind is mirrored);
## - its text is at least MIN_TEXT_DEG high in the eye (story-card body text is ~1.2 deg at its usual 2.56 m);
## - nothing solid between the eyes and its centre (a physics ray, then the real triangles of every mesh on the way:
##   a tree, a wall, a garden prop from saved growth); meshes around the head (rooms, sky domes) don't count;
## - no two panels in the same spot (drawn over each other);
## - no text glued to the face: a visible Label3D under the XR camera turns with the head.
## A node (or ancestor) with meta "vr_check_ignore" is skipped.

const MIN_D := 0.8
## VrText.COMFORT puts cards 1.6 x 1.6 = 2.56 m away on purpose (players found ~1.7 m text cross-eyed), and the lazy
## follow lets a card drift to 1.45 x that before it glides back (the player walked away from it).
const MAX_D := 3.8
const FACE_DOT := 0.6
const MIN_TEXT_DEG := 0.8
const IGNORE_META := "vr_check_ignore"
## Meshes with more triangles than this count by their box only (cheap, may over-report: rare in VR games).
const MAX_FACES := 20000
## Two panels whose middles are closer than this (seen from the eyes) are drawn over each other.
const OVERLAP_DEG := 5.0
const VR_LAYER := preload("res://core/vr_layer.gd").LAYER


## The VR player's camera (the current XRCamera3D, else the first one), or null when nobody is in VR.
static func vr_camera(root: Node) -> XRCamera3D:
	var first: XRCamera3D = null
	for n in root.find_children("*", "XRCamera3D", true, false):
		var c := n as XRCamera3D
		if not c.is_inside_tree():
			continue
		if c.current:
			return c
		if first == null:
			first = c  # fake VR (bots): the TV camera is current, the headset's camera still is the VR view
	return first


static func problems(root: Node) -> Array[String]:
	var out: Array[String] = []
	var cam := vr_camera(root)
	if cam == null:
		return out
	var ws := maxf(XRServer.world_scale, 0.001)
	var head := cam.global_position
	var shown: Array[Node3D] = []
	for n in root.find_children("*", "Node3D", true, false):
		var c := n as Node3D
		if not c.has_meta("vr_placed") or not _drawn(c) or _ignored(c):
			continue
		shown.append(c)
		var name := _name(c)
		var p := _centre(c)
		var d := head.distance_to(p) / ws
		if d < MIN_D or d > MAX_D:
			out.append("%s: %.2f m from the head (%.1f-%.1f m)" % [name, d, MIN_D, MAX_D])
		var face := c.global_basis.z.normalized().dot((head - c.global_position).normalized())
		if face < FACE_DOT:
			out.append("%s: doesn't face the head (%.2f)" % [name, face])
		var small := _smallest_text_deg(c, head)
		if small > 0.0 and small < MIN_TEXT_DEG:
			out.append("%s: text only %.2f deg high (min %.1f)" % [name, small, MIN_TEXT_DEG])
		var hit := blocker(cam, c, p)
		if hit != "":
			out.append("%s: hidden behind %s" % [name, hit])
	# Two panels in the same spot are drawn over each other (a banner over the last one, a card over a sign).
	for i in shown.size():
		for j in range(i + 1, shown.size()):
			var a := shown[i]
			var b := shown[j]
			if a.is_ancestor_of(b) or b.is_ancestor_of(a):
				continue
			if overlap(head, a, b):
				out.append("%s: drawn over %s" % [_name(a), _name(b)])
	for n in cam.find_children("*", "Label3D", true, false):
		var l := n as Label3D
		if l.is_visible_in_tree() and l.text.strip_edges() != "" and l.transparency < 0.65 and not _ignored(l):
			out.append("%s: text glued to the face (a Label3D under the XR camera)" % _name(l))
	return out


## What hides `card` (centre `p`) from the head, or "": a physics body on the ray, else a mesh whose triangles cross it.
static func blocker(cam: Camera3D, card: Node3D, p: Vector3) -> String:
	var head := cam.global_position
	if head.distance_to(p) < 0.05:
		return ""
	# stop a little short of the card: its own panel (and a backdrop it stands on) don't count
	var hit := first_hit(cam, head.lerp(p, 0.96), card)
	return _name(hit.node) if hit.node != null else ""


## The nearest solid thing between the eyes and `to`: {node, f} with f the fraction (0..1) of the way, or
## {node: null, f: 1.0}. Solid = a StaticBody3D (walls, doors, tables) or a drawn mesh's real triangles (signs,
## props from saved growth, trees); not moving things (players walking past, balls), not `skip`, VR UI or the VR
## player's own rig, not meshes around the head (rooms, sky domes). UiKit.vr_clear uses it to bring VR UI in front.
static func first_hit(cam: Camera3D, to: Vector3, skip: Node = null) -> Dictionary:
	var best := {"node": null, "f": 1.0}
	var head := cam.global_position
	var length := head.distance_to(to)
	if length < 0.01 or not cam.is_inside_tree():
		return best
	var space := cam.get_world_3d().direct_space_state
	if space != null:
		var q := PhysicsRayQueryParameters3D.create(head, to)
		q.collide_with_areas = false
		var ex: Array[RID] = []
		for i in 6:  # skipped bodies (the player's own body, held things) are left out and the ray tried again
			q.exclude = ex
			var r := space.intersect_ray(q)
			if r.is_empty() or not r.collider is CollisionObject3D:
				break
			if r.collider is StaticBody3D and not _skip_blocker(r.collider as Node, skip, cam):
				best = {"node": r.collider, "f": head.distance_to(r.position) / length}
				break
			ex.append((r.collider as CollisionObject3D).get_rid())
	for n in cam.get_viewport().find_children("*", "MeshInstance3D", true, false):
		var m := n as MeshInstance3D
		if m.mesh == null or not m.is_visible_in_tree() or m.transparency > 0.5 or (m.layers & cam.cull_mask) == 0:
			continue
		if m.layers == VR_LAYER or m.get_world_3d() != cam.get_world_3d():
			continue
		var box := m.global_transform * m.get_aabb()
		if box.grow(0.05).has_point(head) or box.intersects_segment(head, to) == null:
			continue
		if _skip_blocker(m, skip, cam) or _moving(m) or _see_through(m):
			continue
		var f := _mesh_hit(m, head, to)
		if f < float(best.f):
			best = {"node": m, "f": f}
	return best


## The nearest crossing of segment a->b with m's triangles as a fraction of the way (1.0 = none).
static func _mesh_hit(m: MeshInstance3D, a: Vector3, b: Vector3) -> float:
	var inv := m.global_transform.affine_inverse()
	var la := inv * a
	var lb := inv * b
	var faces: PackedVector3Array
	var key := "vr_check_faces"
	if m.mesh.has_meta(key):
		faces = m.mesh.get_meta(key)
	else:
		faces = m.mesh.get_faces()
		m.mesh.set_meta(key, faces)
	if faces.size() / 3 > MAX_FACES:
		var box := m.get_aabb()
		var at = box.intersects_segment(la, lb)
		return (la.distance_to(at) / maxf(la.distance_to(lb), 0.0001)) if at != null else 1.0
	var best := 1.0
	var span := maxf(la.distance_to(lb), 0.0001)
	for i in range(0, faces.size() - 2, 3):
		var at = Geometry3D.segment_intersects_triangle(la, lb, faces[i], faces[i + 1], faces[i + 2])
		if at != null:
			best = minf(best, la.distance_to(at) / span)
	return best


## Not a blocker: the card itself, the VR player's own rig and body (hands, held things: anything the camera is
## inside), other VR UI, gdev tools.
static func _skip_blocker(n: Node, card: Node, cam: Camera3D) -> bool:
	var origin := cam.get_parent()
	if n.is_ancestor_of(cam):
		return true
	var x := n
	while x != null:
		if x == card or x == origin or x.has_meta("vr_placed") or x.has_meta(IGNORE_META) or str(x.name) == "GDev":
			return true
		x = x.get_parent()
	return false


static func _drawn(n: Node3D) -> bool:
	if not n.is_visible_in_tree():
		return false
	var any := false
	for c in n.find_children("*", "GeometryInstance3D", true, false):
		var g := c as GeometryInstance3D
		if g.is_visible_in_tree() and g.transparency < 0.65:
			any = true
			break
	if n is GeometryInstance3D and (n as GeometryInstance3D).transparency < 0.65:
		any = true
	if n is Label3D and (n as Label3D).text.strip_edges() == "":
		return false
	return any


static func _ignored(n: Node) -> bool:
	var x := n
	while x != null:
		if x.has_meta(IGNORE_META):
			return true
		x = x.get_parent()
	return false


## The middle of what's drawn (its children's boxes), else its position.
static func _centre(n: Node3D) -> Vector3:
	var box := AABB()
	var have := false
	for c in [n] + n.find_children("*", "VisualInstance3D", true, false):
		if c is VisualInstance3D and (c as VisualInstance3D).is_visible_in_tree():
			var b: AABB = (c as VisualInstance3D).global_transform * (c as VisualInstance3D).get_aabb()
			box = b if not have else box.merge(b)
			have = true
	return box.get_center() if have else n.global_position


## The smallest visible text's cap height, in degrees of view (0 = no text).
static func _smallest_text_deg(n: Node3D, head: Vector3) -> float:
	var best := 0.0
	for c in [n] + n.find_children("*", "Label3D", true, false):
		if not c is Label3D:
			continue
		var l := c as Label3D
		if not l.is_visible_in_tree() or l.text.strip_edges() == "":
			continue
		var h := l.font_size * l.pixel_size / 1.35 * l.global_basis.get_scale().y
		var deg := rad_to_deg(atan2(h, maxf(0.01, head.distance_to(l.global_position))))
		best = deg if best == 0.0 else minf(best, deg)
	return best


static func _name(n: Node) -> String:
	var s := str(n.name)
	if n is Label3D:
		s += " \"%s\"" % (n as Label3D).text.substr(0, 24).replace("\n", " ")
	else:
		for c in n.find_children("*", "Label3D", true, false):
			if (c as Label3D).text.strip_edges() != "":
				s += " \"%s\"" % (c as Label3D).text.substr(0, 24).replace("\n", " ")
				break
	var p := n.get_parent()
	return ("%s/%s" % [p.name, s]) if p != null else s


## Part of something that moves about (a player, a creature, a ball): walks past, doesn't count as in the way.
static func _moving(n: Node) -> bool:
	var x := n.get_parent()
	while x != null:
		if x is CharacterBody3D or x is RigidBody3D:
			return true
		x = x.get_parent()
	return false


## Are panels a and b drawn over each other, seen from `head`? (HudKit's VrCard steps out of the way with it.)
static func overlap(head: Vector3, a: Node3D, b: Node3D) -> bool:
	var pa := _centre(a) - head
	var pb := _centre(b) - head
	return rad_to_deg(pa.angle_to(pb)) < OVERLAP_DEG and absf(pa.length() - pb.length()) < 0.6 * maxf(XRServer.world_scale, 0.001)


## Panels in front of the VR player that are drawn right now (meta "vr_placed").
static func shown_panels(root: Node) -> Array[Node3D]:
	var out: Array[Node3D] = []
	for n in root.find_children("*", "Node3D", true, false):
		if n.has_meta("vr_placed") and _drawn(n as Node3D) and not _ignored(n):
			out.append(n as Node3D)
	return out


## A see-through mesh (a ghost building preview, glass, a light beam) doesn't hide what's behind it.
static func _see_through(m: MeshInstance3D) -> bool:
	var mat: Material = m.material_override
	if mat == null and m.mesh.get_surface_count() > 0:
		mat = m.get_active_material(0)
	if mat is BaseMaterial3D:
		var b := mat as BaseMaterial3D
		return b.transparency != BaseMaterial3D.TRANSPARENCY_DISABLED and b.albedo_color.a < 0.9
	if mat is ShaderMaterial:
		var sh := (mat as ShaderMaterial).shader
		return sh != null and (sh.code.contains("ALPHA") or sh.code.contains("blend_add"))
	return false
