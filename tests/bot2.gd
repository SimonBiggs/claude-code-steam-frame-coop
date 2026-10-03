extends Node
# Throwaway test: both players stand still, aim at the nearest enemy and hold fire.
var main
var t := 0.0
var shots := 0
var spitters := 0
func _count(n):
	if n.get_script() and n.get_script().resource_path.ends_with("enemy_shot.gd"): shots += 1
	if n.get("kind") == "spitter": spitters += 1
func _exit_tree():
	print("spitters=%d shots=%d" % [spitters, shots])
func _ready():
	get_tree().node_added.connect(_count)
	main = load("res://main.tscn").instantiate()
	add_child(main)
	main.wave = int(OS.get_environment("START_WAVE")) if OS.has_environment("START_WAVE") else 0
	for k in [KEY_SPACE, KEY_ENTER]:
		var e := InputEventKey.new()
		e.physical_keycode = k
		e.pressed = true
		Input.parse_input_event(e)
func _physics_process(delta):
	t += delta
	for p in main.players:
		var best = null
		for e in get_tree().get_nodes_in_group("enemies"):
			if best == null or e.global_position.distance_to(p.global_position) < best.global_position.distance_to(p.global_position):
				best = e
		if best:
			var d: Vector3 = best.global_position + Vector3.UP * best.radius - (p.global_position + Vector3.UP * 1.55)
			var flat := Vector2(d.x, d.z).length()
			if flat > 0.1:
				p.yaw = atan2(-d.x, -d.z)
				p.pitch = atan2(d.y, flat)
	if int(t * 60) % 120 == 0 and t < 15:
		print("pos ", main.players[0].global_position.snapped(Vector3.ONE*0.1), " ", main.players[1].global_position.snapped(Vector3.ONE*0.1), " joy ", main.players[0].joy, main.players[1].joy)
	if int(t * 60) % 600 == 0:
		var pickups = main.get_children().filter(func(c): return c is Area3D and c.get("kind") != null)
		print("t=%.0f wave=%d score=%d hp=%.0f/%.0f down=%s/%s enemies=%d pickups=%d" % [t, main.wave, main.score, main.players[0].hp, main.players[1].hp, main.players[0].is_down, main.players[1].is_down, get_tree().get_nodes_in_group("enemies").size(), pickups.size()])
func _process(_d):
	if OS.has_environment("SHOT") and t > 14.0 and t < 14.05:
		get_viewport().get_texture().get_image().save_png(OS.get_environment("SHOT"))
		get_tree().quit()
