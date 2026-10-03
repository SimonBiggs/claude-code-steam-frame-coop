extends RefCounted
## Level themes: sky colours, island colours, decorative props and music for each look.
## props_far: tall props along the back edge of each island (away from the builder's view);
## props_near: small props along the front edge. Props are visual only (no collision).

const THEMES := {
	"meadow": {
		"sky_top": Color(0.22, 0.5, 0.95), "sky_horizon": Color(0.72, 0.87, 1.0), "ground": Color(0.5, 0.7, 0.9),
		"grass": [Color(0.45, 0.85, 0.35), Color(0.5, 0.9, 0.45), Color(0.4, 0.8, 0.4)],
		"dirt": Color(0.55, 0.38, 0.24), "rock": Color(0.45, 0.32, 0.22),
		"props_far": [["tree", Color(0.3, 0.72, 0.3)], ["tree", Color(0.42, 0.8, 0.3)], ["bush", Color(0.3, 0.65, 0.3)]],
		"props_near": [["flowers", Color.WHITE], ["rock", Color(0.6, 0.6, 0.62)]],
		"sun": Color(1.0, 0.96, 0.88), "sun_energy": 1.15, "ambient": Color(0.8, 0.85, 1.0), "ambient_energy": 0.75,
		"cloud": Color(1.0, 1.0, 1.0), "pitch": 1.0, "track": 0,
	},
	"volcano": {
		"sky_top": Color(0.3, 0.14, 0.2), "sky_horizon": Color(1.0, 0.55, 0.32), "ground": Color(0.4, 0.15, 0.1),
		"grass": [Color(0.48, 0.42, 0.4), Color(0.54, 0.44, 0.38)],
		"dirt": Color(0.34, 0.24, 0.22), "rock": Color(0.25, 0.2, 0.2),
		"props_far": [["crystal", Color(1.0, 0.4, 0.15)], ["rock", Color(0.3, 0.25, 0.25)]],
		"props_near": [["rock", Color(0.38, 0.3, 0.28)]],
		"sun": Color(1.0, 0.75, 0.6), "sun_energy": 1.05, "ambient": Color(1.0, 0.8, 0.7), "ambient_energy": 0.8,
		"cloud": Color(0.75, 0.6, 0.6), "pitch": 0.96, "track": 1,
	},
	"canyon": {
		"sky_top": Color(0.3, 0.55, 0.95), "sky_horizon": Color(1.0, 0.86, 0.62), "ground": Color(0.85, 0.6, 0.4),
		"grass": [Color(0.95, 0.76, 0.46), Color(0.98, 0.8, 0.5)],
		"dirt": Color(0.82, 0.48, 0.3), "rock": Color(0.7, 0.4, 0.26),
		"props_far": [["cactus", Color.WHITE], ["rock", Color(0.78, 0.46, 0.3)]],
		"props_near": [["rock", Color(0.85, 0.6, 0.4)], ["flowers", Color.WHITE]],
		"sun": Color(1.0, 0.93, 0.8), "sun_energy": 1.2, "ambient": Color(1.0, 0.9, 0.8), "ambient_energy": 0.72,
		"cloud": Color(1.0, 0.97, 0.92), "pitch": 1.03, "track": 2,
	},
	"candy": {
		"sky_top": Color(0.65, 0.5, 0.95), "sky_horizon": Color(1.0, 0.82, 0.92), "ground": Color(0.9, 0.7, 0.9),
		"grass": [Color(1.0, 0.62, 0.8), Color(0.75, 0.95, 0.8), Color(1.0, 0.9, 0.55)],
		"dirt": Color(0.48, 0.3, 0.22), "rock": Color(0.4, 0.25, 0.2),
		"props_far": [["lollipop", Color(1.0, 0.35, 0.5)], ["lollipop", Color(0.4, 0.7, 1.0)], ["mushroom", Color(1.0, 0.3, 0.35)]],
		"props_near": [["mushroom", Color(0.6, 0.45, 1.0)], ["flowers", Color.WHITE]],
		"sun": Color(1.0, 0.95, 0.95), "sun_energy": 1.1, "ambient": Color(1.0, 0.88, 1.0), "ambient_energy": 0.8,
		"cloud": Color(1.0, 0.92, 0.97), "pitch": 1.05, "track": 0,
	},
	"snow": {
		"sky_top": Color(0.4, 0.62, 0.92), "sky_horizon": Color(0.9, 0.95, 1.0), "ground": Color(0.8, 0.85, 0.95),
		"grass": [Color(0.93, 0.96, 1.0), Color(0.88, 0.93, 1.0)],
		"dirt": Color(0.55, 0.6, 0.72), "rock": Color(0.45, 0.5, 0.62),
		"props_far": [["pine", Color(0.2, 0.5, 0.35)], ["pine", Color(0.25, 0.55, 0.4)]],
		"props_near": [["rock", Color(0.7, 0.75, 0.85)]],
		"sun": Color(0.95, 0.97, 1.0), "sun_energy": 1.1, "ambient": Color(0.85, 0.9, 1.0), "ambient_energy": 0.8,
		"cloud": Color(1.0, 1.0, 1.0), "pitch": 0.98, "track": 2,
	},
	"night": {
		"sky_top": Color(0.03, 0.04, 0.16), "sky_horizon": Color(0.25, 0.18, 0.45), "ground": Color(0.05, 0.05, 0.12),
		"grass": [Color(0.32, 0.6, 0.62), Color(0.38, 0.55, 0.7)],
		"dirt": Color(0.3, 0.26, 0.4), "rock": Color(0.22, 0.2, 0.32),
		"props_far": [["crystal", Color(0.4, 0.8, 1.0)], ["crystal", Color(0.9, 0.5, 1.0)], ["lamp", Color.WHITE]],
		"props_near": [["crystal", Color(0.5, 1.0, 0.7)]],
		"sun": Color(0.7, 0.75, 1.0), "sun_energy": 0.75, "ambient": Color(0.6, 0.65, 1.0), "ambient_energy": 0.9,
		"cloud": Color(0.45, 0.45, 0.65), "pitch": 0.94, "track": 2, "stars": true,
	},
	"beach": {
		"sky_top": Color(0.2, 0.6, 1.0), "sky_horizon": Color(0.82, 0.95, 1.0), "ground": Color(0.3, 0.6, 0.9),
		"grass": [Color(1.0, 0.88, 0.6), Color(0.98, 0.85, 0.55)],
		"dirt": Color(0.82, 0.66, 0.45), "rock": Color(0.6, 0.5, 0.4),
		"props_far": [["palm", Color.WHITE], ["bush", Color(0.35, 0.7, 0.35)]],
		"props_near": [["rock", Color(0.95, 0.8, 0.75)], ["flowers", Color.WHITE]],
		"sun": Color(1.0, 0.97, 0.9), "sun_energy": 1.2, "ambient": Color(0.85, 0.92, 1.0), "ambient_energy": 0.75,
		"cloud": Color(1.0, 1.0, 1.0), "pitch": 1.02, "track": 1,
	},
	"autumn": {
		"sky_top": Color(0.3, 0.4, 0.85), "sky_horizon": Color(1.0, 0.7, 0.5), "ground": Color(0.7, 0.5, 0.5),
		"grass": [Color(0.75, 0.7, 0.3), Color(0.85, 0.6, 0.3)],
		"dirt": Color(0.5, 0.34, 0.24), "rock": Color(0.42, 0.3, 0.24),
		"props_far": [["tree", Color(1.0, 0.5, 0.15)], ["tree", Color(0.95, 0.75, 0.2)], ["tree", Color(0.85, 0.3, 0.2)]],
		"props_near": [["mushroom", Color(0.9, 0.35, 0.25)], ["bush", Color(0.8, 0.45, 0.2)]],
		"sun": Color(1.0, 0.85, 0.7), "sun_energy": 1.1, "ambient": Color(1.0, 0.88, 0.8), "ambient_energy": 0.78,
		"cloud": Color(1.0, 0.9, 0.85), "pitch": 0.98, "track": 0,
	},
	"castle": {
		"sky_top": Color(0.35, 0.45, 0.85), "sky_horizon": Color(1.0, 0.78, 0.65), "ground": Color(0.6, 0.5, 0.6),
		"grass": [Color(0.5, 0.75, 0.4), Color(0.72, 0.72, 0.78)],
		"dirt": Color(0.55, 0.52, 0.58), "rock": Color(0.45, 0.42, 0.5),
		"props_far": [["tower", Color(1.0, 0.3, 0.35)], ["tower", Color(0.3, 0.6, 1.0)], ["tree", Color(0.35, 0.65, 0.35)]],
		"props_near": [["flowers", Color.WHITE], ["bush", Color(0.35, 0.6, 0.35)]],
		"sun": Color(1.0, 0.88, 0.75), "sun_energy": 1.1, "ambient": Color(0.9, 0.85, 1.0), "ambient_energy": 0.78,
		"cloud": Color(1.0, 0.92, 0.9), "pitch": 1.0, "track": 1,
	},
	"rainbow": {
		"sky_top": Color(0.4, 0.55, 1.0), "sky_horizon": Color(1.0, 0.85, 0.95), "ground": Color(0.8, 0.8, 1.0),
		"grass": [Color(0.55, 0.95, 0.6), Color(1.0, 0.7, 0.85), Color(0.6, 0.8, 1.0)],
		"dirt": Color(0.6, 0.45, 0.6), "rock": Color(0.5, 0.4, 0.55),
		"props_far": [["tree", Color(1.0, 0.6, 0.8)], ["lollipop", Color(0.5, 0.9, 0.5)], ["crystal", Color(1.0, 0.85, 0.4)]],
		"props_near": [["flowers", Color.WHITE], ["mushroom", Color(1.0, 0.75, 0.3)]],
		"sun": Color(1.0, 0.97, 0.95), "sun_energy": 1.15, "ambient": Color(0.95, 0.9, 1.0), "ambient_energy": 0.8,
		"cloud": Color(1.0, 0.95, 1.0), "pitch": 1.06, "track": 0, "rainbow": true,
	},
}


static func get_theme(theme_name: String) -> Dictionary:
	return THEMES.get(theme_name, THEMES["meadow"])
