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
## - a node (or an ancestor) with meta "layout_check_ignore" is skipped (on purpose: a giant faded title behind play).

const IGNORE_META := "layout_check_ignore"
const MIN_ALPHA := 0.35


## Problems as short strings: "cut: \"SCORE 12\" ..." / "overlap: \"POPPY\" / \"0:42\"". Empty = fine.
static func problems(root: Node, max_items: int = 8) -> Array[String]:
	var out: Array[String] = []
	var boxes := text_boxes(root)
	for b in boxes:
		var vr: Rect2 = b.view
		var r: Rect2 = b.rect
		if r.position.x < vr.position.x - 4 or r.position.y < vr.position.y - 4 or r.end.x > vr.end.x + 4 or r.end.y > vr.end.y + 4:
			out.append("cut: \"%s\" at %s in %s" % [b.text, _r(r), _r(vr)])
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
	var p: Node = c
	while p != null:
		if p.has_meta(IGNORE_META):
			return
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
	out.append({"node": c, "text": text.substr(0, 28).replace("\n", " "), "rect": r, "view": vp.get_visible_rect(), "vp": vp.get_instance_id()})


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


static func _r(r: Rect2) -> String:
	return "%d,%d %dx%d" % [int(r.position.x), int(r.position.y), int(r.size.x), int(r.size.y)]
