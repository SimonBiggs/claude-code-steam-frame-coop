extends Node
## Re-lays out a classic game's split-screen views when Machine.view_on() changes its answer (a Deck's keyboard seat
## gets a pad, a hot reload, the machine kind changes), so a player never drives an invisible view. Started by
## Machine.view_on() itself the first time a game asks; checks 4 times a second.

const Machine := preload("res://core/machine.gd")

var main: Node
var _sig := ""
var _t := 0.0


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS


func _process(delta: float) -> void:
	_t -= delta
	if _t > 0.0 or main == null or not is_instance_valid(main):
		return
	_t = 0.25
	var ps: Variant = main.get("players")
	if not (ps is Array):
		return
	var sig := ""
	for p in ps:
		sig += "1" if (p is Object and Machine.view_on(main, p)) else "0"
	if sig == _sig:
		return
	var first := _sig == ""
	_sig = sig
	if first:
		return  # the game laid itself out with these answers
	if "views_dirty" in main:
		main.set("views_dirty", true)
	if main.has_method("_sync_view_visibility"):
		main.call("_sync_view_visibility")
	elif main.has_method("_layout_views"):
		main.call("_layout_views")
