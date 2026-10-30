extends RefCounted
## VrViewCheck: finds VR UI the headset player can't read comfortably. Used by the VrViewCheck service in fake-VR bot
## runs (BOT_VR=1: core/vr_view_watch.gd) and by the VR visual QA sweep (g.eval("VrViewCheck.problems(root)")).
##   const VrViewCheck := preload("res://core/vr_view_check.gd")
##   var probs := VrViewCheck.problems(get_tree().root)   # [] = fine
## Checks every VR card / banner / toast / panel in front of the player (meta "vr_placed": UiKit.vr_place, VrText.follow)
## that is really drawn (visible, not faded out), measured in real metres (XRServer.world_scale divided out):
## - distance from the head between MIN_D and MAX_D (closer hurts to focus or hits the near plane; further is tiny);
## - it faces the head (Label3D reads from +Z; text seen from behind is mirrored);
## - its text is at least MIN_TEXT_DEG high in the eye (story-card body text is ~1.2 deg);
## - nothing solid between the eyes and its centre (a physics ray, then the real triangles of every mesh on the way:
##   a tree, a wall, a garden prop from saved growth); meshes around the head (rooms, sky domes) don't count;
## - no text glued to the face: a visible Label3D under the XR camera turns with the head.
## A node (or ancestor) with meta "vr_check_ignore" is skipped.

const MIN_D := 0.8
## VrText.COMFORT puts cards 1.6 x 1.6 = 2.56 m away on purpose (players found ~1.7 m text cross-eyed); a little room.
const MAX_D := 3.3
const FACE_DOT := 0.6
const MIN_TEXT_DEG := 0.9
const IGNORE_META := "vr_check_ignore"
## Meshes with more triangles than this count by their box only (cheap, may over-report: rare in VR games).
const MAX_FACES := 20000
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
	for n in root.find_children("*", "Node3D", true, false):
		var c := n as Node3D
		if not c.has_meta("vr_placed") or not _drawn(c) or _ignored(c):
			continue
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
	for n in cam.find_children("*", "Label3D", true, false):
		var l := n as Label3D
		if l.is_visible_in_tree() and l.text.strip_edges() != "" and l.transparency < 0.65 and not _ignored(l):
			out.append("%s: text glued to the face (a Label3D under the XR camera)" % _name(l))
	return out


## What hides `card` (centre `p`) from the head, or "": a physics body on the ray, else a mesh whose triangles cross it.
static func blocker(cam: Camera3D, card: Node3D, p: Vector3) -> String:
	var head := cam.global_position
	var seg := p - head
	if seg.length() < 0.05:
		return ""
	# stop a little short of the card: its own panel (and a backdrop it stands on) don't count
	var to := head + seg * 0.96
	var space := cam.get_world_3d().direct_space_state
	if space != null:
		var q := PhysicsRayQueryParameters3D.create(head, to)
		q.collide_with_areas = false
		var r := space.intersect_ray(q)
		if not r.is_empty() and r.collider is Node and not _skip_blocker(r.collider as Node, card, cam):
			return _name(r.collider as Node)
	for n in cam.get_viewport().find_children("*", "MeshInstance3D", true, false):
		var m := n as MeshInstance3D
		if m.mesh == null or not m.is_visible_in_tree() or m.transparency > 0.5 or (m.layers & cam.cull_mask) == 0:
			continue
		if m.layers == VR_LAYER or m.get_world_3d() != cam.get_world_3d() or _skip_blocker(m, card, cam):
			continue
		var box := m.global_transform * m.get_aabb()
		if box.grow(0.05).has_point(head) or box.intersects_segment(head, to) == null:
			continue
		if _mesh_hit(m, head, to):
			return _name(m)
	return ""


static func _mesh_hit(m: MeshInstance3D, a: Vector3, b: Vector3) -> bool:
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
		return true
	for i in range(0, faces.size() - 2, 3):
		if Geometry3D.segment_intersects_triangle(la, lb, faces[i], faces[i + 1], faces[i + 2]) != null:
			return true
	return false


## Not a blocker: the card itself, the VR player's own rig (hands, held things), other VR UI, gdev tools.
static func _skip_blocker(n: Node, card: Node3D, cam: Camera3D) -> bool:
	var origin := cam.get_parent()
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
