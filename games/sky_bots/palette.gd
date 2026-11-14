extends RefCounted
## What must be seen in Sky Bots, and what it is on (core/contrast.gd; tests/contrast_test.gd).
## The robots (player colours and the CPU buddies), the bolts, grumbles and Cranky Crab carry an ink outline
## (Contrast.outline); they stand on every island floor (meadow tops in every season, gear works metal, cove sand,
## the orange movers and purple lifts) and on Gizmo Town's grass (the meadow tops). The zap pads' flash, a grumble's
## charge line and the crab's stomp ring lie on those same floors; the gold gear and the spark too.

const Contrast := preload("res://core/contrast.gd")
const Party := preload("res://core/party.gd")
const Level := preload("res://games/sky_bots/level.gd")
const Robot := preload("res://games/sky_bots/robot.gd")
const Boss := preload("res://games/sky_bots/boss.gd")


static func key_colors() -> Dictionary:
	var out := Contrast.merge(Contrast.named("robot", Party.COLORS), Contrast.named("cpu robot", Robot.CPU_COLORS))
	out["bolt"] = Level.BOLT_COLOR
	out["grumble"] = Level.GRUMBLE_COLOR
	out["cranky crab"] = Boss.COLOR
	for k in out:  # (each with the ink outline)
		out[k] = {"color": out[k], "rim": Robot.OUTLINE}
	out["gold gear"] = {"color": Level.GEAR_COLOR, "rim": Level.GEAR_COLOR.darkened(0.45)}  # (its dark hub)
	out["spark"] = {"color": Level.SPARK_COLOR, "rim": Color(0.3, 0.32, 0.4)}  # (on its grey pedestal ring)
	out["zap flash"] = Level.ZAP_COLOR
	out["grumble charge line"] = Level.WARN_COLOR
	out["crab stomp ring"] = Boss.RING_COLOR
	return out


static func backgrounds() -> Dictionary:
	var out := Contrast.named("meadow", (Level.MEADOW_TOPS as Dictionary).values())
	for th in Level.THEME:
		out["%s floor" % th] = (Level.THEME[th] as Dictionary).top
	out["mover"] = Level.MOVER_TOP
	out["lift"] = Level.LIFT_TOP
	return out
