extends Node3D
## Base for everything the giant can pick up and throw (goblins, boulders, embers).
## The origin is at the bottom of the object. The host simulates flight; the TV only interpolates.

const W := preload("res://games/giants_table/world.gd")
const GRAVITY := 60.0  # units/s^2 (3 m/s^2 for the giant: a slightly floaty, cartoon fall)

var main
var net_id := 0
var ghost := false
var held := false      # in the giant's hand
var flying := false    # thrown or dropped
var vel := Vector3.ZERO
var radius := 0.4      # size for grabbing and collisions
var center_h := 0.4    # height of the centre above the origin
var net_target := Vector3.ZERO
var net_yaw := 0.0
var net_started := false


func can_grab() -> bool:
	return true


func grab_center() -> Vector3:
	return global_position + Vector3.UP * center_h


func on_grabbed() -> void:
	held = true
	flying = false
	vel = Vector3.ZERO


func on_released(v: Vector3) -> void:
	held = false
	flying = true
	vel = v


## The giant's hand moves us: put our centre at the grab point.
func hold_at(p: Vector3, yaw: float) -> void:
	global_position = p - Vector3.UP * center_h
	rotation.y = yaw


## Ground under us, including resting boulders we could land on.
func support_height(p: Vector3) -> float:
	var g := W.height(p.x, p.z)
	for b in get_tree().get_nodes_in_group("boulders"):
		if b == self or b.held or b.flying:
			continue
		var bp: Vector3 = b.global_position
		var d := Vector2(p.x - bp.x, p.z - bp.z).length()
		if d < b.radius * 0.9 + radius * 0.5:
			g = maxf(g, bp.y + b.radius * 1.8)
	return g


## Ballistic flight. Calls _landed(impact_speed) or _fell_off().
func fly(delta: float) -> void:
	vel.y -= GRAVITY * delta
	var p := global_position + vel * delta
	var g := support_height(p)
	if g > -50.0 and p.y <= g and vel.y <= 0.0:
		p.y = g
		global_position = p
		var impact := vel.length()
		_landed(impact)
		return
	global_position = p
	if p.y < W.FLOOR_Y + 0.3:
		_fell_off()


func _landed(_impact: float) -> void:
	flying = false
	vel = Vector3.ZERO


func _fell_off() -> void:
	queue_free()


## TV: smooth towards the host's position.
func apply_net(item: Array) -> void:
	net_target = item[2]
	net_yaw = item[3]
	if not net_started:
		net_started = true
		global_position = net_target


func ghost_update(delta: float) -> void:
	var k := 1.0 - exp(-18.0 * delta)
	if global_position.distance_to(net_target) > 6.0:
		global_position = net_target
	global_position = global_position.lerp(net_target, k)
	rotation.y = lerp_angle(rotation.y, net_yaw, k)
