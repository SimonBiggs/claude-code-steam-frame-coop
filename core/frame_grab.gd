extends RefCounted
## Safe viewport screenshots for bots and tools: FrameGrab.image(vp) -> Image or null.

## The viewport's picture, or null when nothing is drawn yet or it is gone (offscreen runs, 2026-10-30: a grab before
## the first draw logged "tex is null at texture_get_data" and _save_frame then called get_width on null).
## Always grab through this, never get_image() straight off get_texture() (dev.debt flags that).
static func image(vp: Viewport) -> Image:
	if vp == null or not is_instance_valid(vp) or not vp.is_inside_tree():
		return null
	var tex := vp.get_texture()
	if tex == null or not tex.get_rid().is_valid() or tex.get_width() <= 0 or tex.get_height() <= 0:
		return null
	var img := tex.get_image()
	return img if img != null and not img.is_empty() else null
