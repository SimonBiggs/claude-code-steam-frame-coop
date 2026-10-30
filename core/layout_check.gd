extends RefCounted
## LayoutCheck: finds on-screen text the family can't read because of layout: text cut off by the screen edge, and
## text drawn over other text (a story card over the score, a toast over the timer, two HUD rows on top of each
## other). Used by tests/deck_bot.gd on every game (headless: TV size; rendered at 1280x800 by brepl godot.launch:
## Deck size) and by the visual QA sweep (g.eval("LayoutCheck.problems(root)")).
##   const LayoutCheck := preload("res://core/layout_check.gd")
##   var probs := LayoutCheck.problems(get_tree().root)   # [] = fine
## Rules (kept simple so it never cries wolf):
## - only text that is really drawn: visible in tree, not faded out (modulate chain alpha > 0.35), non-empty;
## - the box is the TEXT's own box (a wide label that centres a short word only counts the word);
## - clipped by a clip_contents ancestor (ScrollContainer lists): only the part inside it counts, nothing if hidden;
## - two texts overlap when they share > 30 % of the smaller one, in the same viewport, and neither contains the
##   other (a label inside a panel inside another label's box is the same widget);
## - a node (or an ancestor) with meta "layout_check_ignore" is skipped (on purpose: a giant faded title behind play);
## - a BIG word (a headline: font >= 3.6 % of the screen height) drawn over two split-screen views at once crosses the
##   line between them ("divider: ..."): use HudKit.split_center(label) so each view gets its own copy. Text on its own
##   panel or band (a results card, HudKit.banner's band: meta "layout_band") may sit over the line on purpose.

const IGNORE_META := "layout_check_ignore"
## Opaque things drawn over the HUD (story cards' panels): text underneath them counts as hidden.
const COVER_GROUP := "layout_cover"
const MIN_ALPHA := 0.35
## Text on its own band/panel across the views (HudKit.banner): allowed over the split line.
const BAND_META := "layout_band"
## A headline: font size at least this share of the screen height.
const BIG_FRAC := 0.036
## A split view: a visible SubViewportContainer at least this share of the screen in both directions.
const VIEW_MIN_FRAC := 0.2


## The split-screen views drawn in viewport `vp` (visible SubViewportContainers of a real size, outermost only), in
## vp's coordinates. One shared answer for HudKit.split_center (a headline per view), HudKit.popup (which cameras
## see a pop-up) and the divider check.
static func view_containers(vp: Viewport) -> Array[SubViewportContainer]:
	var out: Array[SubViewportContainer] = []
	if vp == null:
		return out
	var area := vp.get_visible_rect().size
	for n in vp.find_children("*", "SubViewportContainer", true, false):
		var c := n as SubViewportContainer
		if c.get_viewport() != vp or not c.is_visible_in_tree():
			continue
		var r := c.get_global_rect()
		if r.size.x < area.x * VIEW_MIN_FRAC or r.size.y < area.y * VIEW_MIN_FRAC:
			continue
		out.append(c)
	return out


static func view_rects(vp: Viewport) -> Array[Rect2]:
	var out: Array[Rect2] = []
	for c in view_containers(vp):
		out.append(c.get_global_rect())
	return out


## Problems as short strings: "cut: \"SCORE 12\" ..." / "overlap: \"POPPY\" / \"0:42\"". Empty = fine.
static func problems(root: Node, max_items: int = 8) -> Array[String]:
	var out: Array[String] = []
	var boxes := text_boxes(root)
	for b in boxes:
		var vr: Rect2 = b.view
		var r: Rect2 = b.rect
		if r.position.x < vr.position.x - 4 or r.position.y < vr.position.y - 4 or r.end.x > vr.end.x + 4 or r.end.y > vr.end.y + 4:
			out.append("cut: \"%s\" at %s in %s" % [b.text, _r(r), _r(vr)])
	# Text hidden under a cover (a story card's panel: group COVER_GROUP) that isn't the cover's own text.
	var covers: Array = root.get_tree().get_nodes_in_group(COVER_GROUP) if root.is_inside_tree() else []
	for cv in covers:
		var cc := cv as Control
		if cc == null or not cc.is_visible_in_tree() or not _shown(cc.get_viewport()) or _alpha(cc) < MIN_ALPHA:
			continue
		var cr := _screen_rect(cc, Rect2(Vector2.ZERO, cc.size))
		for b in boxes:
			var n: Node = b.node
			if b.vp != cc.get_viewport().get_instance_id() or cc.is_ancestor_of(n):
				continue
			var inter: Rect2 = (b.rect as Rect2).intersection(cr)
			if inter.get_area() > 0.15 * (b.rect as Rect2).get_area():
				out.append("covered: \"%s\" under %s at %s" % [b.text, cc.name, _r(inter)])
	# Headlines over the line between split views.
	var views_of := {}
	for b in boxes:
		if not b.big or b.band:
			continue
		if not views_of.has(b.vp):
			views_of[b.vp] = view_rects((b.node as Node).get_viewport())
		var vs: Array = views_of[b.vp]
		if vs.size() < 2:
			continue
		var hit := 0
		for v in vs:
			var inter: Rect2 = (b.rect as Rect2).intersection(v)
			if inter.size.x >= 8.0 and inter.size.y >= 8.0:
				hit += 1
		if hit >= 2:
			out.append("divider: \"%s\" crosses the line between split views at %s (HudKit.split_center)" % [b.text, _r(b.rect)])
	for i in boxes.size():
		for j in range(i + 1, boxes.size()):
			var a: Dictionary = boxes[i]
			var b: Dictionary = boxes[j]
			if a.vp != b.vp:
				continue
			var na: Node = a.node
			var nb: Node = b.node
			if na.is_ancestor_of(nb) or nb.is_ancestor_of(na):
				continue
			var inter: Rect2 = (a.rect as Rect2).intersection(b.rect)
			if inter.get_area() <= 0.0:
				continue
			var small := minf((a.rect as Rect2).get_area(), (b.rect as Rect2).get_area())
			if inter.get_area() > 0.3 * small:
				out.append("overlap: \"%s\" / \"%s\" at %s" % [a.text, b.text, _r(inter)])
	if out.size() > max_items:
		out.resize(max_items)
	return out


## Every drawn text: [{node, text, rect (screen/viewport coordinates), view (that viewport's visible rect), vp}].
static func text_boxes(root: Node) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for n in root.find_children("*", "Label", true, false):
		_add(n as Control, (n as Label).text, out)
	for n in root.find_children("*", "RichTextLabel", true, false):
		_add(n as Control, (n as RichTextLabel).get_parsed_text(), out)
	for n in root.find_children("*", "Button", true, false):
		_add(n as Control, (n as Button).text, out)
	return out


static func _add(c: Control, text: String, out: Array[Dictionary]) -> void:
	text = text.strip_edges()
	if text == "" or not c.is_visible_in_tree() or c.size.x < 2.0 or c.size.y < 2.0:
		return
	if String(c.get_path()).contains("/GDev/"):
		return
	var alpha := 1.0
	var clip := Rect2()
	var clipped := false
	var band := false
	var p: Node = c
	while p != null:
		if p.has_meta(IGNORE_META):
			return
		if p.has_meta(BAND_META) or (p != c and (p is PanelContainer or p is Panel)):
			band = true
		if p is CanvasItem:
			alpha *= (p as CanvasItem).modulate.a * (p as CanvasItem).self_modulate.a if p == c else (p as CanvasItem).modulate.a
		if p != c and p is Control and (p as Control).clip_contents:
			var pr := _screen_rect(p as Control, Rect2(Vector2.ZERO, (p as Control).size))
			clip = pr if not clipped else clip.intersection(pr)
			clipped = true
		if p is Viewport:
			break
		p = p.get_parent()
	if alpha < MIN_ALPHA:
		return
	var r := _screen_rect(c, _text_local_rect(c))
	if clipped:
		r = r.intersection(clip)
		if r.get_area() < 4.0:
			return
	var vp := c.get_viewport()
	if not _shown(vp):
		return
	var big := false
	if c is Label:
		var fs := float((c as Label).label_settings.font_size if (c as Label).label_settings != null else c.get_theme_font_size("font_size"))
		var vs := vp.get_visible_rect().size
		big = fs * c.get_global_transform_with_canvas().get_scale().y >= BIG_FRAC * minf(vs.y, vs.x * 9.0 / 16.0)  # (a 16:9 height: headless windows can be square)
	out.append({"node": c, "text": text.substr(0, 28).replace("\n", " "), "rect": r, "view": vp.get_visible_rect(), "vp": vp.get_instance_id(), "big": big, "band": band})


## Is this viewport on screen? (Games prebuild hidden split views: a 2x2 SubViewport, or one in a hidden container.)
static func _shown(vp: Viewport) -> bool:
	while vp is SubViewport:
		var sv := vp as SubViewport
		if sv.size.x < 64 or sv.size.y < 64:
			return false
		var holder := sv.get_parent()
		if not (holder is SubViewportContainer) or not (holder as Control).is_visible_in_tree():
			return false
		vp = holder.get_viewport()
	return true


## The part of a text control the text itself takes (alignment-aware), in its own coordinates.
static func _text_local_rect(c: Control) -> Rect2:
	var full := Rect2(Vector2.ZERO, c.size)
	if c is Label:
		var l := c as Label
		var font := l.get_theme_font("font")
		var fs := l.get_theme_font_size("font_size")
		if font == null:
			return full
		var w := 0.0
		var lines := l.get_line_count() if l.autowrap_mode != TextServer.AUTOWRAP_OFF else l.text.count("\n") + 1
		if l.autowrap_mode != TextServer.AUTOWRAP_OFF:
			w = c.size.x
		else:
			for line in l.text.split("\n"):
				w = maxf(w, font.get_string_size(line.strip_edges() if l.uppercase == false else line.strip_edges().to_upper(), HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x)
		w = minf(w, c.size.x)
		var h := minf(c.size.y, lines * l.get_line_height())
		var x := 0.0
		match l.horizontal_alignment:
			HORIZONTAL_ALIGNMENT_CENTER:
				x = (c.size.x - w) * 0.5
			HORIZONTAL_ALIGNMENT_RIGHT:
				x = c.size.x - w
		var y := 0.0
		match l.vertical_alignment:
			VERTICAL_ALIGNMENT_CENTER:
				y = (c.size.y - h) * 0.5
			VERTICAL_ALIGNMENT_BOTTOM:
				y = c.size.y - h
		return Rect2(x, y, w, h)
	return full


static func _screen_rect(c: Control, local: Rect2) -> Rect2:
	var xf := c.get_global_transform_with_canvas()
	var a := xf * local.position
	var b := xf * local.end
	return Rect2(Vector2(minf(a.x, b.x), minf(a.y, b.y)), (b - a).abs())


static func _alpha(c: CanvasItem) -> float:
	var a := 1.0
	var p: Node = c
	while p != null and not p is Viewport:
		if p is CanvasItem:
			a *= (p as CanvasItem).modulate.a
		p = p.get_parent()
	return a


static func _r(r: Rect2) -> String:
	return "%d,%d %dx%d" % [int(r.position.x), int(r.position.y), int(r.size.x), int(r.size.y)]
