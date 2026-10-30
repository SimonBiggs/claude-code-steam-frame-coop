extends RefCounted
## VrLayer: the ONE render layer for world-space UI that only the VR player may see (story / hint /
## result cards, banners, toasts, countdowns, VR menus, dialogue boxes, wrist buttons, headset fades).
## The TV, Deck and every other flat camera must never draw it: on one machine the TV split views share
## the VR player's world, and a VR card seen from the TV camera shows up as a dark rectangle (its back).
##   - core/vr_layer_guard.gd (a service) enforces it on EVERY camera, every frame: XR cameras and VR
##     views (mirrors that follow the headset: group "vr_view") always draw LAYER, all others never do.
##     So games may write any cull_mask (whitelists, 0xFFFFF) and still get it right.
##   - core HUD helpers default to it (HudKit.vr_card/vr_banner/vr_toast/vr_countdown, VrMenu, Dialogue's
##     VR box, Awards' VR summary, StoryCard.show_vr), and UiKit.vr_place/vr_follow and VrText.follow
##     mark whatever they place. A VR-only node made by hand: VrLayer.mark(node).
##   - Games must leave bit 18 alone for their own layers (tests/engine_ui/vr_layer_test.gd lints games/).
## Same bit as UiKit.VR_LAYER. VrRig.AVATAR_LAYER (bit 19) is the opposite: TV-only.

const LAYER := 1 << 18  ## render layer 19
const GROUP_VIEW := "vr_view"  ## flat cameras that show the VR player's view (VR mirrors / bubbles)


## Put `n` (if it is a VisualInstance3D) and every VisualInstance3D under it that is still on the
## default layer 1 on the VR-only layer. Nodes a game gave its own layers keep them.
static func mark(n: Node) -> void:
	if n == null or not is_instance_valid(n):
		return
	if n is VisualInstance3D and (n as VisualInstance3D).layers == 1:
		(n as VisualInstance3D).layers = LAYER
	for c in n.get_children():
		if not c is Viewport:  # a SubViewport's contents (StoryCard medallion pictures) render on their own
			mark(c)


## mark() once per node (cheap enough to call every frame from follow helpers).
static func mark_once(n: Node) -> void:
	if n != null and is_instance_valid(n) and not n.has_meta("vr_layer"):
		n.set_meta("vr_layer", true)
		mark(n)


## True for cameras that show what the VR player sees.
static func is_vr_camera(cam: Camera3D) -> bool:
	return cam is XRCamera3D or cam.is_in_group(GROUP_VIEW)


## A flat (TV / Deck) camera's mask without the VR-only layer.
static func tv_mask(mask: int = 0xFFFFF) -> int:
	return mask & ~LAYER


## Apply the rule to one camera (the guard does this every frame; call it when you can't wait a frame).
static func fix_camera(cam: Camera3D) -> void:
	var m := cam.cull_mask
	if is_vr_camera(cam):
		if m & LAYER == 0:
			cam.cull_mask = m | LAYER
	elif m & LAYER != 0:
		cam.cull_mask = m & ~LAYER
