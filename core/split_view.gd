extends CanvasLayer
## SplitView: the TV picture. One SubViewport view per local player in a grid (1 full screen,
## 2 side by side, 3-4 as 2x2, 5-6 as 3x2, 7 as 4x2), or one SHARED view for everyone (board games,
## quiz shows, RPG battles), switchable at runtime. Every view has its own Camera3D and a HUD root
## Control (inside a CanvasLayer in that view) that is scaled to the view, so a HUD laid out for a
## full screen still fits a quarter of it. More views = lower 3D resolution, no MSAA, fewer effects.
## Optional VR bubble: a round picture-in-picture of the VR player's view (an empty grid cell if
## there is one, else the top-right corner).
## Usage:
##   const SplitView := preload("res://core/split_view.gd")
##   split = SplitView.new(); add_child(split)
##   split.bind_party(party)            # views follow party.local_slots() automatically
##   var cam := split.camera(slot)      # place it yourself or with core/camera_rig.gd
##   split.hud(slot).add_child(my_label)
##   split.set_shared(true)             # one camera: split.shared_camera(), split.shared_hud()
##   split.set_bubble(rig.mirror)       # or VrRig.build_mirror(self, avatar.head) on the TV machine
## Views are created lazily and kept when hidden (hidden views don't render), so hot reloads and
## players dropping in and out are cheap.

## Emitted after every re-layout with the number of views on screen.
signal layout_changed(view_count: int)

const GAP := 4.0
const BUBBLE_SHADER := """
shader_type canvas_item;
uniform vec4 ring_color : source_color = vec4(0.3, 0.7, 1.0, 1.0);
void fragment() {
	float r = length(UV - 0.5);
	vec4 c = texture(TEXTURE, UV);
	float inside = 1.0 - smoothstep(0.485, 0.5, r);
	float ring = smoothstep(0.45, 0.47, r);
	COLOR = vec4(mix(c.rgb, ring_color.rgb, ring), inside);
}
"""

## The 3D world every view shows (default: the main viewport's world).
var world: World3D
## Colour behind and between the views.
var background := Color(0.0, 0.0, 0.0)
## HUD scale = clamp(min(view.x / x, view.y / y), min_hud_scale, 1).
var hud_reference := Vector2(940.0, 900.0)
var min_hud_scale := 0.5
## 3D resolution scale by number of views on screen (index = view count).
var res_scales: Array[float] = [1.0, 1.0, 1.0, 0.72, 0.7, 0.58, 0.55, 0.5]
## MSAA 2x only while at most this many views are on screen.
var msaa_max_views := 2
## Turn off SSAO beyond 2 views and directional shadows beyond 4 (WorldEnvironment and
## DirectionalLight3D children of `effects_root`, default the parent). Never touches VR.
var manage_effects := true
var effects_root: Node
## New cameras start with these.
var camera_fov := 70.0
var camera_near := 0.05
var camera_far := 500.0
## Where the VR bubble goes: "auto" (an empty grid cell, else the corner), "corner" or "center".
var bubble_mode := "auto"
## Bubble diameter as a fraction of the screen height when it sits in the corner.
var bubble_size := 0.28
## With nobody seated on this screen, show the shared view (e.g. the world behind "Press A to join").
var shared_when_empty := true

var _root: Control
var _bg: ColorRect
var _views := {}  # slot -> view Dictionary (see _make_view)
var _slots: Array[int] = []
var _shared_on := false
var _shared: Dictionary = {}
var _bubble: TextureRect
var _bubble_tag: Label
var _last_area := Vector2.ZERO
var _empty_cell := Rect2()
var _party: Node


func _ready() -> void:
	if layer == 1:
		layer = -1  # behind the game's own HUD layers and the pause menu
	_ensure_root()
	layout()


# --- Slots ------------------------------------------------------------------------------

## Show exactly these slots (in slot order). Views are created on first use and kept.
func set_slots(slots: Array) -> void:
	_slots.clear()
	for s in slots:
		var si := int(s)
		if not _slots.has(si):
			_slots.append(si)
	_slots.sort()
	for s in _slots:
		_ensure_view(s)
	layout()


func add_slot(slot: int) -> void:
	if not _slots.has(slot):
		var list: Array = _slots.duplicate()
		list.append(slot)
		set_slots(list)


func remove_slot(slot: int) -> void:
	if _slots.has(slot):
		_slots.erase(slot)
		layout()


func has_slot(slot: int) -> bool:
	return _slots.has(slot)


## The slots that currently have a view (in grid order).
func slots() -> Array[int]:
	return _slots.duplicate()


## Follow a core/party.gd PartyManager: a view for every player seated on THIS machine.
func bind_party(party: Node) -> void:
	_party = party
	if not party.player_joined.is_connected(_on_party_joined):
		party.player_joined.connect(_on_party_joined)
	if not party.player_left.is_connected(_on_party_left):
		party.player_left.connect(_on_party_left)
	set_slots(party.local_slots())


func _on_party_joined(slot: int, _device: int) -> void:
	if _party != null and _party.is_local(slot):
		add_slot(slot)


func _on_party_left(slot: int) -> void:
	remove_slot(slot)


# --- Views ------------------------------------------------------------------------------

## The slot's own camera (created on demand; hidden while the shared view is on).
func camera(slot: int) -> Camera3D:
	return _ensure_view(slot)["camera"]


## The slot's HUD root: a Control covering its view, scaled down in small views (hud_scale), so
## anchor your HUD controls to its edges / corners and design them at full-screen size.
func hud(slot: int) -> Control:
	return _ensure_view(slot)["hud"]


func viewport(slot: int) -> SubViewport:
	return _ensure_view(slot)["viewport"]


## Where the slot's view is on the screen (Rect2() if it isn't shown).
func view_rect(slot: int) -> Rect2:
	if _showing_shared() or not _slots.has(slot) or not _views.has(slot):
		return Rect2()
	return _views[slot]["rect"]


## The scale applied to the slot's HUD root (1 = full size).
func hud_scale(slot: int) -> float:
	if not _views.has(slot):
		return 1.0
	return float(_views[slot]["hud_scale"])


## The camera that is on screen for `slot` right now (the shared one in shared mode).
func active_camera(slot: int) -> Camera3D:
	return shared_camera() if _showing_shared() else camera(slot)


## Number of views on screen.
func view_count() -> int:
	return 1 if _showing_shared() else _slots.size()


## One view for everyone (true) or one view per player (false). Switch any time.
func set_shared(on: bool) -> void:
	if on == _shared_on:
		return
	_shared_on = on
	if on:
		_ensure_shared()
	layout()


## True in shared mode (set_shared(true)). See also showing_shared().
func is_shared() -> bool:
	return _shared_on


## True while the shared view is on screen: shared mode, or nobody seated with shared_when_empty.
func showing_shared() -> bool:
	return _showing_shared()


func _showing_shared() -> bool:
	return _shared_on or (shared_when_empty and _slots.is_empty())


func shared_camera() -> Camera3D:
	return _ensure_shared()["camera"]


func shared_hud() -> Control:
	return _ensure_shared()["hud"]


func shared_viewport() -> SubViewport:
	return _ensure_shared()["viewport"]


## The unused grid cell (3, 5 or 7 views), e.g. for a scoreboard or map; Rect2() if none.
func empty_cell_rect() -> Rect2:
	return _empty_cell


## Columns and rows for n views: 1 = 1x1, 2 = 2x1, 3-4 = 2x2, 5-6 = 3x2, 7-8 = 4x2.
static func grid_for(n: int) -> Vector2i:
	if n <= 1:
		return Vector2i(1, 1)
	if n == 2:
		return Vector2i(2, 1)
	if n <= 4:
		return Vector2i(2, 2)
	if n <= 6:
		return Vector2i(3, 2)
	return Vector2i(4, 2)


## The screen rectangles of n views in `area` (row by row, GAP pixels apart).
static func cell_rects(n: int, area: Vector2, gap: float = GAP) -> Array[Rect2]:
	var out: Array[Rect2] = []
	var g := grid_for(n)
	var cell := Vector2((area.x - gap * (g.x - 1)) / g.x, (area.y - gap * (g.y - 1)) / g.y)
	for k in g.x * g.y:
		var col := k % g.x
		var row := k / g.x
		out.append(Rect2(Vector2(col * (cell.x + gap), row * (cell.y + gap)), cell))
	return out


## Re-arrange the views now (also happens by itself when the screen size changes).
func layout() -> void:
	_ensure_root()
	var area := _area()
	_last_area = area
	_empty_cell = Rect2()
	var shared_now := _showing_shared()
	if shared_now:
		_ensure_shared()
	for s in _views:
		var v: Dictionary = _views[s]
		_show_view(v, not shared_now and _slots.has(int(s)))
	if not _shared.is_empty():
		_show_view(_shared, shared_now)
	var n := view_count()
	if shared_now:
		_place_view(_shared, Rect2(Vector2.ZERO, area), 1)
	elif n > 0:
		var rects := cell_rects(n, area)
		for k in n:
			_place_view(_views[_slots[k]], rects[k], n)
		if rects.size() > n:
			_empty_cell = rects[n]
	_place_bubble(area)
	_set_view_effects(n)
	layout_changed.emit(n)


func _process(_delta: float) -> void:
	if _root != null and _root.size != _last_area and _root.size.x > 2.0:
		layout()


func _area() -> Vector2:
	var area := _root.size if _root != null else Vector2.ZERO
	if area.x < 2.0 or area.y < 2.0:
		area = get_viewport().get_visible_rect().size
	return area


func _ensure_root() -> void:
	if _root != null and is_instance_valid(_root):
		return
	_bg = ColorRect.new()
	_bg.name = "Background"
	_bg.color = background
	_bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_bg)
	_bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_root = Control.new()
	_root.name = "Views"
	_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_root)
	_root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)


func _world() -> World3D:
	if world != null:
		return world
	return get_viewport().find_world_3d()


func _ensure_view(slot: int) -> Dictionary:
	if _views.has(slot):
		var v: Dictionary = _views[slot]
		if is_instance_valid(v["container"]):
			return v
	var nv := _make_view("View%d" % slot)
	nv["slot"] = slot
	_views[slot] = nv
	return nv


func _ensure_shared() -> Dictionary:
	if _shared.is_empty() or not is_instance_valid(_shared["container"]):
		_shared = _make_view("SharedView")
		_shared["slot"] = -1
		_show_view(_shared, _showing_shared())
	return _shared


func _make_view(view_name: String) -> Dictionary:
	_ensure_root()
	var c := SubViewportContainer.new()
	c.name = view_name
	c.stretch = true
	c.mouse_filter = Control.MOUSE_FILTER_IGNORE
	c.visible = false
	_root.add_child(c)
	var vp := SubViewport.new()
	vp.world_3d = _world()
	vp.msaa_3d = Viewport.MSAA_2X
	vp.screen_space_aa = Viewport.SCREEN_SPACE_AA_FXAA
	vp.render_target_update_mode = SubViewport.UPDATE_DISABLED
	c.add_child(vp)
	var cam := Camera3D.new()
	cam.fov = camera_fov
	cam.near = camera_near
	cam.far = camera_far
	vp.add_child(cam)
	cam.current = true
	var hud_layer := CanvasLayer.new()
	hud_layer.name = "Hud"
	vp.add_child(hud_layer)
	var hud_root := Control.new()
	hud_root.name = "HudRoot"
	hud_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hud_layer.add_child(hud_root)
	return {"container": c, "viewport": vp, "camera": cam, "hud_layer": hud_layer, "hud": hud_root,
		"rect": Rect2(), "hud_scale": 1.0, "slot": -1}


func _show_view(v: Dictionary, on: bool) -> void:
	var c: SubViewportContainer = v["container"]
	var vp: SubViewport = v["viewport"]
	c.visible = on
	vp.render_target_update_mode = SubViewport.UPDATE_WHEN_VISIBLE if on else SubViewport.UPDATE_DISABLED
	if not on:
		v["rect"] = Rect2()


func _place_view(v: Dictionary, r: Rect2, n: int) -> void:
	var c: SubViewportContainer = v["container"]
	c.set_anchors_preset(Control.PRESET_TOP_LEFT)
	c.position = r.position
	c.size = r.size
	var vp: SubViewport = v["viewport"]
	vp.scaling_3d_scale = res_scales[clampi(n, 0, res_scales.size() - 1)]
	vp.msaa_3d = Viewport.MSAA_2X if n <= msaa_max_views else Viewport.MSAA_DISABLED
	var s := clampf(minf(r.size.x / hud_reference.x, r.size.y / hud_reference.y), min_hud_scale, 1.0)
	var hud_root: Control = v["hud"]
	hud_root.scale = Vector2(s, s)
	hud_root.position = Vector2.ZERO
	hud_root.size = r.size / s
	v["rect"] = r
	v["hud_scale"] = s


# --- VR bubble --------------------------------------------------------------------------

## Show a round picture-in-picture of `source` (the VR mirror) over the views.
func set_bubble(source: SubViewport, ring_color: Color = Color(0.3, 0.7, 1.0), label: String = "P1 (VR)") -> void:
	_ensure_root()
	if _bubble == null or not is_instance_valid(_bubble):
		_bubble = TextureRect.new()
		_bubble.name = "VrBubble"
		_bubble.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		_bubble.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
		_bubble.mouse_filter = Control.MOUSE_FILTER_IGNORE
		var mat := ShaderMaterial.new()
		mat.shader = Shader.new()
		mat.shader.code = BUBBLE_SHADER
		_bubble.material = mat
		add_child(_bubble)
		_bubble_tag = Label.new()
		_bubble_tag.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		_bubble_tag.add_theme_font_size_override("font_size", 24)
		_bubble_tag.add_theme_constant_override("outline_size", 6)
		_bubble_tag.add_theme_color_override("font_outline_color", Color.BLACK)
		_bubble.add_child(_bubble_tag)
	_bubble.texture = source.get_texture() if source != null else null
	(_bubble.material as ShaderMaterial).set_shader_parameter("ring_color", ring_color)
	_bubble_tag.text = label
	_bubble_tag.add_theme_color_override("font_color", ring_color)
	_bubble.visible = source != null
	_place_bubble(_area())


func clear_bubble() -> void:
	if _bubble != null and is_instance_valid(_bubble):
		_bubble.visible = false
		_bubble.texture = null


## Where the bubble is on screen (Rect2() if hidden).
func bubble_rect() -> Rect2:
	if _bubble == null or not is_instance_valid(_bubble) or not _bubble.visible:
		return Rect2()
	return Rect2(_bubble.position, _bubble.size)


func _place_bubble(area: Vector2) -> void:
	if _bubble == null or not is_instance_valid(_bubble):
		return
	var d := area.y * bubble_size
	var pos := Vector2(area.x - d - 24.0, 24.0)
	if bubble_mode == "center":
		pos = area * 0.5 - Vector2(d, d) * 0.5
	elif bubble_mode == "auto" and _empty_cell.size.x > 2.0:
		d = minf(_empty_cell.size.x, _empty_cell.size.y) * 0.8
		pos = _empty_cell.get_center() - Vector2(d, d) * 0.5
	_bubble.position = pos
	_bubble.size = Vector2(d, d)
	_bubble_tag.add_theme_font_size_override("font_size", int(clampf(d * 0.09, 16.0, 30.0)))
	_bubble_tag.size = Vector2(d, 34.0)
	_bubble_tag.position = Vector2(0.0, d - 6.0)


# --- Effects ----------------------------------------------------------------------------

## Many views share one GPU: drop SSAO beyond two views and directional shadows beyond four
## (originals are remembered and restored when views go away). Skipped in VR.
func _set_view_effects(n: int) -> void:
	if not manage_effects or get_viewport().use_xr:
		return
	var root := effects_root if effects_root != null else get_parent()
	if root == null:
		return
	for node in root.get_children():
		if node is WorldEnvironment and (node as WorldEnvironment).environment != null:
			var e: Environment = (node as WorldEnvironment).environment
			if not node.has_meta("split_ssao0"):
				node.set_meta("split_ssao0", e.ssao_enabled)
			e.ssao_enabled = bool(node.get_meta("split_ssao0")) and n <= 2
		elif node is DirectionalLight3D:
			var l: DirectionalLight3D = node
			if not l.has_meta("split_shadow0"):
				l.set_meta("split_shadow0", l.shadow_enabled)
			l.shadow_enabled = bool(l.get_meta("split_shadow0")) and n <= 4
