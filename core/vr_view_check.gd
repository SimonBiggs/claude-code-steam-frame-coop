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
## - no two panels drawn over each other: their rectangles, seen from the eyes, overlap (overlap());
## - no world words (name tags, pop-ups) right in front of the eyes;
## - no text glued to the face: a visible Label3D under the XR camera turns with the head.
## - its words are drawn on top of its own panel and readable on it (text_problems()): a panel that skips the depth
##   test shows through a nearer leaf or wall, so its text must skip it too (Fruit Catch 2026-11-12: TODAY'S HARVEST
##   was a dark bar with no words in front of a low branch); text above the panel's render priority; enough lightness
##   gap against the panel's fill.
## - not washed out: no see-through scenery (water, glass, mist) behind a panel draws after it. VR panels sit at
##   UiKit.VR_PRIO_PANEL (-4, under their own text), so a blended surface at the default priority 0 behind a card
##   is blended OVER it (Fishing Lake 2026-11-11: the lake's water made Ollie's cards a faint, far-looking ghost).
##   Give such surfaces UiKit.VR_PRIO_UNDER_UI.
## - every pick orb near the VR player (picture and words) in plain sight: nothing solid in front of any part of its
##   name (pick_hidden; Rhythm Band 2026-11-12: HARD half behind the green cymbal).
## - never over a pick: no panel covers (seen from the eyes) anything in the KEEP_CLEAR group (core/pick_orbs.gd puts
##   every pick orb there while it shows). UiKit.vr_spot moves VR UI up or down clear of them (vr_dodge); a game
##   never has to lift its orbs or push its cards about for this (story cards sat on picks for ~2 s at a pick's start).
## - the head itself is where a real headset's would be (head_problems()): a tracked XRCamera3D under an XROrigin3D at a
##   real eye height (VrRig.REAL_EYE_RANGE, world_scale divided out). Fake heads riding on a flat camera (over / behind
##   the arena) or 1.6 world units up in a giant game (ant's eyes) judged VR placement from the wrong spot (2026-11-12).
## A node (or ancestor) with meta "vr_check_ignore" is skipped.

## (UiKit.vr_spot brings a panel to 0.55 m only when a wall is right in front of the face)
const MIN_D := 0.5
## VrText.COMFORT puts cards 1.6 x 1.6 = 2.56 m away on purpose (players found ~1.7 m text cross-eyed), and the lazy
## follow lets a card drift to 1.45 x that before it glides back (the player walked away from it).
const MAX_D := 3.8
const FACE_DOT := 0.6
const MIN_TEXT_DEG := 0.8
const IGNORE_META := "vr_check_ignore"
## Meshes with more triangles than this count by their box only (cheap, may over-report: rare in VR games).
const MAX_FACES := 20000
## Two panels whose drawn rectangles (seen from the eyes, at any depth: a near banner hides a far card just the same)
## share more than this many square degrees are drawn over each other. Panels with no size yet (nothing drawn) fall
## back to their middles being closer than OVERLAP_DEG. (Ghost Lantern 2026-11-11: NIGHT 2 at 1.7 m sat over Granny
## Boo's card at 2.56 m; the old "middles within 5 deg AND within 0.6 m in depth" rule missed it.)
const OVERLAP_DEG := 5.0
const OVERLAP_MIN_DEG2 := 1.0
## World words nearer than this (metres) in front of the eyes are "in the face".
const FACE_D := 0.45
const VR_LAYER := preload("res://core/vr_layer.gd").LAYER
const VR_PRIO_PANEL := -4  ## UiKit.VR_PRIO_PANEL (tests/core_math_test.gd checks they match)
const VR_PRIO_HILITE := -3  ## UiKit.VR_PRIO_HILITE (tests/core_math_test.gd checks they match)
## Words on a VR panel need at least this Oklab lightness gap from the panel's fill (UiKit.TEXT on UiKit.BG is ~0.8).
const MIN_TEXT_GAP := 0.35
## Node group: things VR panels must never cover (pick orbs). Any game can add its own must-see things.
const KEEP_CLEAR := "vr_keep_clear"
## Picks further than this (real metres) from the VR head are for other players; their sight lines aren't checked.
const PICK_SEE_D := 6.0
const VrRig := preload("res://core/vr_rig.gd")
## Meta on a fake XRCamera3D that the game itself puts exactly where its real fit puts a real head (Kart Race: the
## seat's eye point), so it needs no XROrigin3D. The value says why.
const HEAD_FITTED_META := "vr_head_fitted"


## The VR player's camera (the current XRCamera3D, else the first one a headset would track: under an XROrigin3D or
## meta HEAD_FITTED_META, else the first one), or null when nobody is in VR. gdev's camshot (g.vrShot) picks the same.
static func vr_camera(root: Node) -> XRCamera3D:
	var first: XRCamera3D = null
	var tracked: XRCamera3D = null
	for n in root.find_children("*", "XRCamera3D", true, false):
		var c := n as XRCamera3D
		if not c.is_inside_tree():
			continue
		if c.current:
			return c
		if first == null:
			first = c  # fake VR (bots): the TV camera is current, the headset's camera still is the VR view
		if tracked == null and (c.get_parent() is XROrigin3D or c.has_meta(HEAD_FITTED_META)):
			tracked = c
	return tracked if tracked != null else first


## Is this VR head where a real Steam Frame player's would be? A real XRCamera3D is tracked under an XROrigin3D, at the
## player's real eye height times XRServer.world_scale. Fake heads (bots) must be stood the same way: VrRig.fake_stand
## (own XR nodes), tests/bot_kit.gd vr_stand / vr_idle / vr_head_height (VrRig), VrRig.fake_head_at (games whose fake VR
## player plays through a flat camera: an origin on the game's VR spawn, never the flat camera).
static func head_problems(cam: XRCamera3D) -> Array[String]:
	var out: Array[String] = []
	if cam == null or not cam.is_inside_tree() or cam.has_meta(HEAD_FITTED_META) or VrRig.headset_available():
		return out
	var origin := cam.get_parent() as XROrigin3D
	if origin == null:
		out.append("VR head %s is not under an XROrigin3D (it rides on %s, not where a VR player stands): use VrRig.fake_head_at on the game's VR spawn" % [cam.name, cam.get_parent().name])
		return out
	var eye := cam.position.y / maxf(XRServer.world_scale, 0.001)
	var r := VrRig.REAL_EYE_RANGE
	if eye < r.x or eye > r.y:
		out.append("VR head %s: %.2f m above the floor in real metres (a real player %.1f-%.1f m; world_scale %.2f): stand it with VrRig.fake_stand / kit.vr_idle" % [cam.name, eye, r.x, r.y, XRServer.world_scale])
	return out


static func problems(root: Node) -> Array[String]:
	var out: Array[String] = []
	var cam := vr_camera(root)
	if cam == null:
		return out
	var ws := maxf(XRServer.world_scale, 0.001)
	out.append_array(head_problems(cam))
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
		for tp in text_problems(c):
			out.append("%s: %s" % [name, tp])
		var wash := washer(cam, c, p)
		if wash != "":
			out.append("%s: washed out by %s drawn over it (give it UiKit.VR_PRIO_UNDER_UI)" % [name, wash])
		var hit := blocker(cam, c, p)
		if hit != "":
			out.append("%s: hidden behind %s, it is %.1f m away%s" % [name, hit, d, " " + str(c.get_meta("vr_spot")) if OS.has_environment("VR_VIEW_DEBUG") and c.has_meta("vr_spot") else ""])
	# Two panels in the same spot are drawn over each other (a banner over the last one, a card over a sign).
	for i in shown.size():
		for j in range(i + 1, shown.size()):
			var a := shown[i]
			var b := shown[j]
			if a.is_ancestor_of(b) or b.is_ancestor_of(a):
				continue
			if overlap(head, a, b):
				out.append("%s: drawn over %s" % [_name(a), _name(b)])
	# A panel over a pick orb: the player can't see what they're choosing.
	var keep := keep_clear(root, cam)
	if not keep.is_empty():
		var boxes: Array[AABB] = []
		for k in keep:
			boxes.append(thing_box(k, cam.cull_mask))
		for c in shown:
			var size := panel_extent(c)
			var p := _centre(c)
			for i in keep.size():
				if keep[i] != c and not c.is_ancestor_of(keep[i]) and cover_deg2(head, p, size, boxes[i]) > 0.0:
					out.append("%s: drawn over the pick %s (UiKit.vr_dodge keeps VR UI clear of VrViewCheck.KEEP_CLEAR)" % [_name(c), _name(keep[i])])
		# A pick orb (or the name under it) behind scenery: the player can't read what they're choosing (Rhythm Band
		# 2026-11-12: HARD's label half behind the green cymbal).
		for k in keep:
			for pp in pick_hidden(cam, k):
				out.append(pp)
	# Words right in front of the eyes (a TV player's name tag walking through the VR player): giant letters.
	var origin := cam.get_parent()
	for n in root.find_children("*", "Label3D", true, false):
		var l := n as Label3D
		if l.has_meta("vr_placed") or not l.is_visible_in_tree() or l.text.strip_edges() == "" or l.transparency > 0.65:
			continue
		var dist := l.global_position.distance_to(head)
		if dist >= FACE_D * ws or dist < l.visibility_range_begin or (origin != null and origin.is_ancestor_of(l)) or _ignored(l):
			continue
		if (l.layers & cam.cull_mask) == 0 or cam.is_ancestor_of(l):
			continue
		var to := (l.global_position - head).normalized()
		if to.dot(-cam.global_basis.z) > 0.5:
			out.append("%s: text in the face (%.2f m from the eyes)" % [_name(l), dist / ws])
	for n in cam.find_children("*", "Label3D", true, false):
		var l := n as Label3D
		if l.is_visible_in_tree() and l.text.strip_edges() != "" and l.transparency < 0.65 and not _ignored(l):
			out.append("%s: text glued to the face (a Label3D under the XR camera)" % _name(l))
	return out


## A VR UI panel mesh: UiKit.vr_panel_material (panel / highlight priority, no depth test: floats over scenery).
static func is_floating_panel(n: Node) -> bool:
	if not n is MeshInstance3D:
		return false
	var mat := (n as MeshInstance3D).material_override as BaseMaterial3D
	return mat != null and mat.no_depth_test and mat.render_priority >= VR_PRIO_PANEL and mat.render_priority <= VR_PRIO_HILITE


## The floating panel a Label3D is written on (a panel mesh beside it or beside one of its parents, up to the placed
## card), or null. Such text must skip the depth test like its panel (core/vr_text_guard.gd): otherwise a leaf or wall
## between the eyes and the card hides the words while the panel still shows, a dark bar with nothing on it.
static func panel_of(l: Node) -> MeshInstance3D:
	var x := l.get_parent()
	for i in 4:
		if x == null or not x is Node3D or x is XROrigin3D or x is XRCamera3D:
			return null
		for c in x.get_children():
			if c != l and is_floating_panel(c) and (c as MeshInstance3D).visible:
				return c as MeshInstance3D
		if x.has_meta("vr_placed"):
			return null
		x = x.get_parent()
	return null


## The panel's fill colour: the most common nearly-opaque vertex colour of its mesh (UiKit.panel_mesh is
## vertex-coloured: shadow rim, border, fill), or the material's albedo.
static func panel_fill(m: MeshInstance3D) -> Color:
	var mat := m.material_override as BaseMaterial3D
	if m.mesh == null or mat == null or not mat.vertex_color_use_as_albedo:
		return mat.albedo_color if mat != null else Color.BLACK
	var key := "vr_check_fill"
	if m.mesh.has_meta(key):
		return m.mesh.get_meta(key)
	var counts := {}
	for s in m.mesh.get_surface_count():
		var cols = m.mesh.surface_get_arrays(s)[Mesh.ARRAY_COLOR]
		if cols == null:
			continue
		for c in (cols as PackedColorArray):
			if c.a >= 0.8:
				var h := c.to_html()
				counts[h] = int(counts.get(h, 0)) + 1
	var best := mat.albedo_color
	var most := 0
	for h in counts:
		if int(counts[h]) > most:
			most = int(counts[h])
			best = Color.html(h)
	m.mesh.set_meta(key, best)
	return best


## What's wrong with the words on a VR card's panels: hidden by scenery the panel floats over (depth-tested text on a
## no-depth panel), drawn under the panel (render priority), or too close to the panel's colour to read.
static func text_problems(card: Node3D) -> Array[String]:
	var out: Array[String] = []
	for c in [card] + card.find_children("*", "SpriteBase3D", true, false):
		var s := c as SpriteBase3D  # pictures on the panel (story medallions): the same depth rule as words
		if s == null or not s.is_visible_in_tree() or s.transparency > 0.65 or panel_of(s) == null:
			continue
		var smat := panel_of(s).material_override as BaseMaterial3D
		if not s.no_depth_test:
			out.append("picture %s is depth-tested on a panel that isn't: scenery in front hides it, not the panel" % s.name)
		if s.render_priority <= smat.render_priority:
			out.append("picture %s drawn under its own panel (priority %d, panel %d)" % [s.name, s.render_priority, smat.render_priority])
	for c in [card] + card.find_children("*", "Label3D", true, false):
		if not c is Label3D:
			continue
		var l := c as Label3D
		if not l.is_visible_in_tree() or l.text.strip_edges() == "" or l.transparency > 0.65 or l.modulate.a < 0.1:
			continue
		var p := panel_of(l)
		if p == null:
			continue
		var mat := p.material_override as BaseMaterial3D
		var words := "\"%s\"" % l.text.substr(0, 20).replace("\n", " ")
		if not l.no_depth_test:
			out.append("text %s is depth-tested on a panel that isn't: scenery in front hides the words, not the panel" % words)
		if l.render_priority <= mat.render_priority or (l.outline_size > 0 and l.outline_render_priority <= mat.render_priority):
			out.append("text %s drawn under its own panel (priority %d / outline %d, panel %d)" % [words, l.render_priority, l.outline_render_priority, mat.render_priority])
		const Contrast := preload("res://core/contrast.gd")
		var fill := panel_fill(p)
		var gap := absf(Contrast.lightness_gap(Color(l.modulate, 1.0), fill))
		if gap < MIN_TEXT_GAP:
			out.append("text %s hard to read on its panel (lightness gap %.2f, min %.2f)" % [words, gap, MIN_TEXT_GAP])
	return out


## See-through scenery behind `card` (on the line from the head through its centre) that draws after the card
## (blended, render_priority >= the card's panel), or "".
static func washer(cam: Camera3D, card: Node3D, p: Vector3) -> String:
	var head := cam.global_position
	var dir := (p - head).normalized()
	var prio := VR_PRIO_PANEL
	var rig := cam.get_parent()  # the VR player's own hands and what they hold (a laser sight) aren't scenery
	for n in cam.get_tree().root.find_children("*", "GeometryInstance3D", true, false):
		var g := n as GeometryInstance3D
		if g is Label3D or g is GPUParticles3D or g is CPUParticles3D or not g.is_visible_in_tree() or g.transparency > 0.65:
			continue
		if (g.layers & cam.cull_mask) == 0 or card.is_ancestor_of(g) or g == card or _ignored(g) or _placed(g) \
				or (rig != null and rig.is_ancestor_of(g)):
			continue
		var mat := _material(g)
		if mat == null or mat.render_priority < prio or not _blended(mat):
			continue
		var box := g.global_transform * g.get_aabb()
		if box.size.length() < 0.01 or box.has_point(head):
			continue
		if box.intersects_ray(p + dir * 0.02, dir) != null:
			return "%s (see-through, priority %d)" % [_name(g), mat.render_priority]
	return ""


static func _placed(n: Node) -> bool:
	var x := n
	while x != null:
		if x.has_meta("vr_placed"):
			return true
		x = x.get_parent()
	return false


static func _material(g: GeometryInstance3D) -> Material:
	if g.material_override != null:
		return g.material_override
	if g is MeshInstance3D and (g as MeshInstance3D).mesh != null and (g as MeshInstance3D).mesh.get_surface_count() > 0:
		return (g as MeshInstance3D).get_active_material(0)
	return null


## Alpha-blended (mixed over what's behind it; additive glows and alpha-scissor cut-outs don't wash a card out).
static func _blended(mat: Material) -> bool:
	if mat is BaseMaterial3D:
		var b := mat as BaseMaterial3D
		return b.blend_mode == BaseMaterial3D.BLEND_MODE_MIX and (b.transparency == BaseMaterial3D.TRANSPARENCY_ALPHA \
			or b.transparency == BaseMaterial3D.TRANSPARENCY_ALPHA_DEPTH_PRE_PASS) and b.albedo_color.a < 0.99
	if mat is ShaderMaterial:
		var sh := (mat as ShaderMaterial).shader
		return sh != null and sh.code.contains("ALPHA") and not sh.code.contains("blend_add") and not sh.code.contains("ALPHA_SCISSOR")
	return false


## What hides `card` (centre `p`) from the head, or "": a physics body on the ray, else a mesh whose triangles cross it.
static func blocker(cam: Camera3D, card: Node3D, p: Vector3) -> String:
	var head := cam.global_position
	if head.distance_to(p) < 0.05:
		return ""
	# stop a little short of the card: its own panel (and a backdrop it stands on) don't count
	var hit := first_hit(cam, head.lerp(p, 0.96), card)
	if hit.node == null:
		return ""
	# a wall the player has their nose against (nearer than UiKit.VR_CLOSEST): nothing can go in front of it
	if float(hit.f) * head.distance_to(p) * 0.96 < 0.6 * maxf(XRServer.world_scale, 0.001):
		return ""
	return "%s (%.1f m away)" % [_name(hit.node), float(hit.f) * head.distance_to(p) * 0.96 / maxf(XRServer.world_scale, 0.001)]


## A pick orb (KEEP_CLEAR) the VR head can't fully see: its picture or any part of its words (a 3 x 3 grid over each
## Label3D under it: middle, ends, top, bottom, corners) behind something solid (first_hit). Picks further than PICK_SEE_D real
## metres are for other players (a far field's big orbs) and aren't checked. [] = all clear.
static func pick_hidden(cam: Camera3D, k: Node3D) -> Array[String]:
	var out: Array[String] = []
	var head := cam.global_position
	var ws := maxf(XRServer.world_scale, 0.001)
	if head.distance_to(k.global_position) / ws > PICK_SEE_D:
		return out
	var right := cam.global_basis.x.normalized()
	var up := cam.global_basis.y.normalized()
	var meshes := cam.get_viewport().find_children("*", "MeshInstance3D", true, false)
	var spots: Array = [[k, k.global_position]]
	for n in k.find_children("*", "Label3D", true, false):
		var l := n as Label3D
		if not l.is_visible_in_tree() or l.text.strip_edges() == "" or l.modulate.a < 0.1 or l.transparency > 0.65 or (l.layers & cam.cull_mask) == 0:
			continue
		var sz := label_size(l) * 0.42
		for fx in [0.0, -1.0, 1.0]:
			for fy in [0.0, -1.0, 1.0]:  # middle, ends, top, bottom and corners (Rhythm Band: only HARD's bottom right was hidden)
				spots.append([l, l.global_position + right * sz.x * fx + up * sz.y * fy])
	for s in spots:
		var p: Vector3 = s[1]
		var dist := head.distance_to(p)
		if dist < 0.05:
			continue
		var hit := first_hit(cam, head.lerp(p, 0.97), k, meshes)
		if hit.node == null or float(hit.f) * dist * 0.97 < 0.6 * ws:
			continue
		var what: Node = s[0]
		out.append("%s of the pick %s: hidden behind %s%s (%.1f m away; move the pick or the scenery)" % [
			("words " + _name(what)) if what is Label3D else "picture", _name(k), _name(hit.node), made_by(hit.node), float(hit.f) * dist * 0.97 / ws])
		break  # one line per pick is enough
	return out


## The nearest solid thing between the eyes and `to`: {node, f} with f the fraction (0..1) of the way, or
## {node: null, f: 1.0}. Solid = a StaticBody3D (walls, doors, tables) or a drawn mesh's real triangles (signs,
## props from saved growth, trees); not moving things (players walking past, balls), not `skip`, VR UI or the VR
## player's own rig, not meshes around the head (rooms, sky domes). UiKit.vr_clear uses it to bring VR UI in front.
## `meshes`: the viewport's MeshInstance3Ds when the caller already has them (many rays in one check).
static func first_hit(cam: Camera3D, to: Vector3, skip: Node = null, meshes: Array = []) -> Dictionary:
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
	for n in (meshes if not meshes.is_empty() else cam.get_viewport().find_children("*", "MeshInstance3D", true, false)):
		var m := n as MeshInstance3D
		if m == null or not is_instance_valid(m) or m.mesh == null or not m.is_visible_in_tree() or m.transparency > 0.5 or (m.layers & cam.cull_mask) == 0:
			continue
		if m.layers == VR_LAYER or m.get_world_3d() != cam.get_world_3d():
			continue
		var box := m.global_transform * m.get_aabb()
		if box.grow(0.05).has_point(head) or box.intersects_segment(head, to) == null:
			continue
		if _skip_blocker(m, skip, cam) or _moving(m) or _walks_about(m) or _see_through(m):
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
	if n is Label3D and ((n as Label3D).text.strip_edges() == "" or (n as Label3D).modulate.a < 0.1):
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
	if n is Label3D:
		return n.global_position  # (its own box isn't built in headless runs; the text is centred on it)
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


## " (made by games/x/props.gd Fence)": the nearest scripted ancestor of an unnamed mesh, so a failure says what it is.
static func made_by(n: Node) -> String:
	var what := ""
	if n is MeshInstance3D and (n as MeshInstance3D).mesh != null:
		var b := (n as MeshInstance3D).get_aabb()
		what = " %s %.1fx%.1fx%.1f m at %s" % [(n as MeshInstance3D).mesh.get_class(), b.size.x, b.size.y, b.size.z, (n as Node3D).global_position.snapped(Vector3.ONE * 0.1)]
	var x := n
	while x != null:
		var s: Script = x.get_script()
		if s != null and s.resource_path != "":
			return " (%s in %s %s)" % [what.strip_edges(), s.resource_path.get_file(), x.name]
		x = x.get_parent()
	return " (%s)" % what.strip_edges()


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


## Part of a player or creature built by core/creatures.gd (meta "creature"), or something one carries (a basket on a
## head): they walk about and step out of the way, so they don't count as in the way (Dodge Ball 2026-11-12: a runner
## standing under the big orb it picks; Fruit Catch: a TV player's basket walking past the VR player).
static func _walks_about(n: Node) -> bool:
	var x := n.get_parent()
	while x != null:
		if x.has_meta("creature"):
			return true
		x = x.get_parent()
	return false


## Are panels a and b drawn over each other, seen from `head`? (HudKit's VrCard steps out of the way with it.)
static func overlap(head: Vector3, a: Node3D, b: Node3D) -> bool:
	return overlap_deg2(head, a, b) > OVERLAP_MIN_DEG2


## How much panels a and b cover each other seen from `head` (square degrees; 0 = clear). Depth doesn't matter.
static func overlap_deg2(head: Vector3, a: Node3D, b: Node3D) -> float:
	var pa := _centre(a) - head
	var pb := _centre(b) - head
	var sa := panel_extent(a)
	var sb := panel_extent(b)
	if sa.length() < 0.01 or sb.length() < 0.01 or pa.length() < 0.01 or pb.length() < 0.01:
		return 100.0 if rad_to_deg(pa.angle_to(pb)) < OVERLAP_DEG else 0.0
	var f := pa.normalized()
	var right := f.cross(Vector3.UP)
	right = right.normalized() if right.length() > 0.01 else Vector3.RIGHT
	var up := right.cross(f).normalized()
	var ra := _ang_rect(pa, sa, f, right, up)
	var rb := _ang_rect(pb, sb, f, right, up)
	if pb.dot(f) <= 0.05:
		return 0.0
	var ox := minf(ra.end.x, rb.end.x) - maxf(ra.position.x, rb.position.x)
	var oy := minf(ra.end.y, rb.end.y) - maxf(ra.position.y, rb.position.y)
	return ox * oy if ox > 0.0 and oy > 0.0 else 0.0


## A panel `size` metres big whose middle is at `v` from the eyes, as a rectangle of view angles (degrees) around `f`.
static func _ang_rect(v: Vector3, size: Vector2, f: Vector3, right: Vector3, up: Vector3) -> Rect2:
	var z := maxf(v.dot(f), 0.05)
	var c := Vector2(rad_to_deg(atan2(v.dot(right), z)), rad_to_deg(atan2(v.dot(up), z)))
	var d := v.length()
	var h := Vector2(rad_to_deg(atan2(size.x * 0.5, d)), rad_to_deg(atan2(size.y * 0.5, d)))
	return Rect2(c - h, h * 2.0)



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


## Things in the KEEP_CLEAR group the VR camera sees now (shown, in its world, not freed).
static func keep_clear(n: Node, cam: Camera3D) -> Array[Node3D]:
	var out: Array[Node3D] = []
	if n == null or cam == null or not n.is_inside_tree() or not cam.is_inside_tree():
		return out
	for k in n.get_tree().get_nodes_in_group(KEEP_CLEAR):
		var t := k as Node3D
		if t != null and t.is_visible_in_tree() and not t.is_queued_for_deletion() and t.get_world_3d() == cam.get_world_3d() \
				and not _ignored(t):
			out.append(t)
	return out


## The world box of what `n` draws for a camera with `mask` (meshes, sprites and its words; not lights or sparkles).
## Label3D boxes aren't built in headless runs, so words are measured from their text.
static func thing_box(n: Node3D, mask: int = 0xFFFFF) -> AABB:
	var box := AABB()
	var have := false
	for c in [n] + n.find_children("*", "GeometryInstance3D", true, false):
		if not c is GeometryInstance3D or c is GPUParticles3D or c is CPUParticles3D:
			continue
		var g := c as GeometryInstance3D
		if not g.is_visible_in_tree() or g.transparency > 0.65 or (g.layers & mask) == 0:
			continue
		var b := AABB()
		if g is Label3D:
			var sz := label_size(g as Label3D)
			if sz == Vector2.ZERO:
				continue
			b = AABB(g.global_position - Vector3(sz.x, sz.y, sz.x) * 0.5, Vector3(sz.x, sz.y, sz.x))
		else:
			b = g.global_transform * g.get_aabb()
		if b.size.length() < 0.001:
			continue
		box = b if not have else box.merge(b)
		have = true
	return box if have else AABB(n.global_position, Vector3.ZERO)


## A Label3D's width and height in metres, worked out from its text (its own box only exists with a renderer).
static func label_size(l: Label3D) -> Vector2:
	var t := l.text.strip_edges()
	if t == "":
		return Vector2.ZERO
	var lines := t.split("\n")
	var longest := 0
	for s in lines:
		longest = maxi(longest, s.length())
	var em := l.font_size * l.pixel_size
	if l.width > 0.0 and l.autowrap_mode != TextServer.AUTOWRAP_OFF:
		longest = mini(longest, int(l.width / 0.6 / maxf(l.font_size, 1.0)) + 1)
	var sc := l.global_basis.get_scale()
	return Vector2(longest * em * 0.6 * sc.x, lines.size() * em * 1.1 * sc.y)


## A panel's width and height (metres): its boxes (panel_size), or for bare words their text (label_size).
static func panel_extent(n: Node3D) -> Vector2:
	var s := panel_size(n)
	if s.length() < 0.01 and n is Label3D:
		s = label_size(n as Label3D)
	return s


## How much of `box` a panel `size` metres big at `centre` (facing the eyes) covers, seen from `head`: the area of
## the overlap in square degrees (0 = clear). `margin` (degrees) grows the panel (UiKit.vr_dodge keeps a gap).
static func cover_deg2(head: Vector3, centre: Vector3, size: Vector2, box: AABB, margin: float = 0.0) -> float:
	if size == Vector2.ZERO or box.size.length() < 0.001 or box.grow(0.05).has_point(head):
		return 0.0
	var f := centre - head
	var d := f.length()
	if d < 0.01:
		return 0.0
	f /= d
	var right := f.cross(Vector3.UP)
	right = right.normalized() if right.length() > 0.01 else Vector3.RIGHT
	var up := right.cross(f).normalized()
	var hx := rad_to_deg(atan2(size.x * 0.5, d)) + margin
	var hy := rad_to_deg(atan2(size.y * 0.5, d)) + margin
	var lo := Vector2(INF, INF)
	var hi := Vector2(-INF, -INF)
	var behind := 0
	for i in 8:
		var v := box.get_endpoint(i) - head
		var z := v.dot(f)
		if z < 0.05:
			behind += 1
			z = 0.05
		var a := Vector2(rad_to_deg(atan2(v.dot(right), z)), rad_to_deg(atan2(v.dot(up), z)))
		lo = lo.min(a)
		hi = hi.max(a)
	if behind == 8:
		return 0.0
	var ox := minf(hi.x, hx) - maxf(lo.x, -hx)
	var oy := minf(hi.y, hy) - maxf(lo.y, -hy)
	return ox * oy if ox > 0.0 and oy > 0.0 else 0.0


## A panel's drawn width and height (metres, as it is scaled now), from its own and its children's boxes.
static func panel_size(n: Node3D) -> Vector2:
	var inv := n.global_transform.affine_inverse()
	var box := AABB()
	var have := false
	for c in [n] + n.find_children("*", "VisualInstance3D", true, false):
		if c is VisualInstance3D:
			var b: AABB = (inv * (c as VisualInstance3D).global_transform) * (c as VisualInstance3D).get_aabb()
			box = b if not have else box.merge(b)
			have = true
	var sc := n.global_basis.get_scale()
	return Vector2(box.size.x * sc.x, box.size.y * sc.y) if have else Vector2.ZERO
