extends RefCounted
## What must be seen in Penalty Shootout (core/contrast.gd; tests/contrast_test.gd): the strikers, the ball and the
## keeper's power bubbles on the night pitch, and the ball against the night sky behind the goal.

const Contrast := preload("res://core/contrast.gd")
const WorldScript := preload("res://games/penalty_shootout/world.gd")
const Ball := preload("res://games/penalty_shootout/ball.gd")
const Striker := preload("res://games/penalty_shootout/striker.gd")
const Keeper := preload("res://games/penalty_shootout/keeper.gd")


static func _ball() -> Dictionary:
	return {"color": Ball.WHITE, "rim": Ball.PATCH}


## The keeper (P1: the strikers see the keeper's body in their colour), the strikers (P2..) in their jerseys over
## white shorts, the ball, the power bubbles (see-through, as main.gd draws them).
static func key_colors() -> Dictionary:
	var out := {"ball": _ball(), "keeper": WorldScript.PLAYER_COLORS[0]}
	for i in range(1, WorldScript.PLAYER_COLORS.size()):
		out["striker %d" % (i + 1)] = {"color": WorldScript.PLAYER_COLORS[i], "rim": Striker.SHORTS}
	for k in Keeper.POWER_COLORS:
		var c: Color = Keeper.POWER_COLORS[k]
		out["%s bubble" % k] = Color(c.r, c.g, c.b, Keeper.BUBBLE_ALPHA)
	return out


static func backgrounds() -> Dictionary:
	return {"pitch": WorldScript.PITCH, "pitch stripe": WorldScript.PITCH_STRIPE}


static func groups() -> Array:
	return [{"keys": {"ball": _ball()}, "bgs": {"night sky": WorldScript.NIGHT}}]
