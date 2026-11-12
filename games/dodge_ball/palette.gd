extends RefCounted
## What must be seen in Dodge Ball, and what it is on (core/contrast.gd; tests/contrast_test.gd).
## The players dodge on the sandy court (and its centre spot, and the lawn round it); the balls fly and bounce over
## the court and against the day sky; the cushions to hide behind stand on the court. TumTum's trick tells (deep.gd: the
## red STOMP band, the purple BALL SHOWER circle) glow on the court, its centre spot and (a band's ends) the lawn.

const Contrast := preload("res://core/contrast.gd")
const Party := preload("res://core/party.gd")
const World := preload("res://games/dodge_ball/world.gd")
const CourtGen := preload("res://games/dodge_ball/courtgen.gd")
const Deep := preload("res://games/dodge_ball/deep.gd")


static func key_colors() -> Dictionary:
	return Contrast.humanoids(Party.COLORS, World.LOOKS)


static func backgrounds() -> Dictionary:
	return {"court": World.COURT, "centre spot": World.COURT_SPOT, "lawn": World.LAWN}


static func groups() -> Array:
	var balls := {}
	for i in World.BALL_COLORS.size():  # (each with its ink outline: world.gd BALL_OUTLINE)
		balls["ball %d" % (i + 1)] = {"color": World.BALL_COLORS[i], "rim": World.BALL_OUTLINE}
	return [{"keys": balls,
		"bgs": Contrast.merge({"court": World.COURT, "centre spot": World.COURT_SPOT}, Contrast.sky("day"))},
		# The soft cushions the runners hide behind, standing on the court.
		{"keys": Contrast.merge(Contrast.named("cushion", CourtGen.CUSHION_COLORS), {"gold cushion": CourtGen.GOLD}), "bgs": {"court": World.COURT}},
		{"keys": {"stomp tell": Deep.STOMP_COLOR, "shower tell": Deep.SHOWER_COLOR},
		"bgs": {"court": World.COURT, "centre spot": World.COURT_SPOT, "lawn": World.LAWN}}]
