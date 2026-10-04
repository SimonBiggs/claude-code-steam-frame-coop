extends RefCounted
## MINI GOLF PARTY: shared constants (physics, layers, sizes, themes). Plain consts only, so every
## script can preload it without side effects and hot reloads stay cheap.

const GAME_ID := "mini_golf_party"

# --- Sizes (metres): life-size mini golf, with a party-size ball that kids can see and hit in VR ----
const BALL_R := 0.04
const CUP_R := 0.1
const WALL_H := 0.11
const WALL_T := 0.08
## Floor slabs go this far down (their sides are the step faces of raised greens).
const FLOOR_DEPTH := 0.35

# --- Physics layers (high bits: the TV camera rig only avoids layer 1) ------------------------
const L_FLOOR := 1 << 10
const L_RAIL := 1 << 11
const L_OBST := 1 << 12
const L_BALL := 1 << 13
## Moving gimmicks (windmill sails, ships, asteroids...): balls hit them, line-of-sight checks don't.
const L_MOVER := 1 << 14
const MASK_ALL := L_FLOOR | L_RAIL | L_OBST | L_BALL | L_MOVER
## Ghost ball: through obstacles and other balls, never through the outer rails or the floor.
const MASK_GHOST := L_FLOOR | L_RAIL

# --- Ball physics (host simulates; tuned for a felt green) -------------------------------------
const GRAVITY := 9.8
## Constant rolling resistance (m/s^2) plus a little speed-proportional drag (1/s).
const ROLL_DECEL := 0.55
const DRAG := 0.12
const WALL_BOUNCE := 0.68
const BUMPER_BOUNCE := 1.05
const FLOOR_BOUNCE := 0.28
## Below this speed (m/s) a grounded ball on a flat spot stops.
const STOP_SPEED := 0.045
## Strongest putt (m/s) without power-ups; the TV power meter maps 0..1 onto MIN..MAX.
const MAX_PUTT := 4.8
const MIN_PUTT := 0.3
const MEGA_FACTOR := 1.5
## A ball rolling slower than this over the cup drops in; faster ones can lip out.
const CAPTURE_SPEED := 1.9
## Kids' assist: a gentle pull towards the cup within this radius when slow.
const ASSIST_R := 0.32
const ASSIST_ACCEL := 0.75
## Seconds a roll may last before the balls are stopped (stuck in a bowl, on a belt...).
const MAX_ROLL_TIME := 22.0

# --- Rules ------------------------------------------------------------------------------------
const MAX_STROKES := 6
## Score written down when a player picks up after MAX_STROKES.
const PICKUP_SCORE := 7
## Turn time limits (s): then a friendly auto-putt keeps the game moving.
const TV_TURN_TIME := 40.0
const VR_TURN_TIME := 90.0

# --- Power-ups (party mode) ---------------------------------------------------------------------
const POWERUPS: Array[String] = ["sticky", "bouncy", "mega", "ghost"]
const POWERUP_NAMES := {"sticky": "STICKY BALL", "bouncy": "BOUNCY BALL", "mega": "MEGA PUTT", "ghost": "GHOST BALL"}
const POWERUP_TEXT := {
	"sticky": "Your next putt stops dead - no bounces!",
	"bouncy": "Your next putt bounces like crazy!",
	"mega": "Your next putt is SUPER strong!",
	"ghost": "Your next putt rolls through obstacles!",
}
const POWERUP_COLORS := {"sticky": Color(0.45, 0.95, 0.35), "bouncy": Color(1.0, 0.45, 0.85),
	"mega": Color(1.0, 0.55, 0.15), "ghost": Color(0.8, 0.9, 1.0)}
const POWERUP_ICONS := {"sticky": "drop", "bouncy": "arrow_up", "mega": "bolt", "ghost": "eye"}

# --- Courses ------------------------------------------------------------------------------------
const COURSES := {
	"pirate": {"name": "PIRATE COVE", "desc": "Windmills, cannons, shipwrecks and a sneaky pirate ship!",
		"sky": "day", "mood": "party", "color": Color(1.0, 0.72, 0.3)},
	"space": {"name": "SPACE STATION", "desc": "Loop-the-loops, low gravity, portals and asteroids!",
		"sky": "space", "mood": "space", "color": Color(0.5, 0.75, 1.0)},
	"tour": {"name": "GRAND TOUR", "desc": "All 18 holes: Pirate Cove, then blast off to the Space Station!",
		"sky": "day", "mood": "party", "color": Color(0.7, 1.0, 0.55)},
}
const COURSE_ORDER: Array[String] = ["pirate", "space", "tour"]
## Ring layout: hole plots sit on a circle round the course's landmark.
const RING_R := 27.0
