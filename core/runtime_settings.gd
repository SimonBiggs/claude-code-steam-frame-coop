extends Node
## Runtime settings (a service, core/services.gd): the project settings that matter while the game runs, applied
## from code so changing them hot-reloads instead of needing a restart (project.godot is only read at launch).
## Change a value here and save: every machine applies it at the next safe point (core/safe_apply.gd).
## Still need a relaunch (engine level, read once at start): the renderer (Forward Plus), OpenXR on/off and its
## shaders, the project name (it names the user:// folder), the main scene, and the autoloads (only Boot + gdev's).

const SETTINGS := {
	"stretch_size": Vector2i(1920, 1080),  # display/window/size/viewport_width/height
	"stretch_mode": Window.CONTENT_SCALE_MODE_CANVAS_ITEMS,  # display/window/stretch/mode
	"stretch_aspect": Window.CONTENT_SCALE_ASPECT_EXPAND,  # display/window/stretch/aspect
	"msaa_3d": Viewport.MSAA_2X,  # rendering/anti_aliasing/quality/msaa_3d
}


func _ready() -> void:
	apply()


func _on_hot_reload() -> void:
	apply()


func apply() -> void:
	var w := get_tree().root
	w.content_scale_size = SETTINGS.stretch_size
	w.content_scale_mode = SETTINGS.stretch_mode
	w.content_scale_aspect = SETTINGS.stretch_aspect
	w.msaa_3d = SETTINGS.msaa_3d
