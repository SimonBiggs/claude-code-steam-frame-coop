extends RefCounted
## What must be seen in Kart Race, and every road it is on (core/contrast.gd; tests/contrast_test.gd).
## Karts and hazards are on the road; each cup's hazards only show on its own place's road.

const Contrast := preload("res://core/contrast.gd")
const Cups := preload("res://games/kart_race/cups.gd")
const Track := preload("res://games/kart_race/track.gd")
const TrackGen := preload("res://games/kart_race/trackgen.gd")
const Props := preload("res://games/kart_race/track_props.gd")
const Deep := preload("res://games/kart_race/deep.gd")


## Karts, and the tells on the road (deep.gd): the surprise circle, its hot landing, the hazards' outlines.
static func key_colors() -> Dictionary:
	var out := Contrast.merge(Contrast.named("kart", Cups.PLAYER_COLORS), Contrast.named("cpu kart", Cups.CPU_COLORS))
	out["surprise circle"] = Deep.RING_COLOR
	out["surprise landing"] = Deep.HOT_COLOR
	out["hazard outline"] = Deep.HAZARD_TELL
	return out


## Every place's road (and the rainbow road trackgen.gd lays).
static func backgrounds() -> Dictionary:
	var out := Contrast.field("road", Track.TRACKS, "road", "theme")
	out["rainbow road"] = TrackGen.RAINBOW_ROAD
	return out


## Each cup's puddles and bumpers on its place's road.
static func groups() -> Array:
	var out := []
	for cp in Cups.CUPS:
		var hz: Dictionary = Cups.HAZARDS[String(cp.hz)]
		var keys := {"%s patch" % hz.patch_look: Props.PATCH_COLORS[hz.patch_look]}
		keys.merge(Contrast.named("%s bump" % hz.bump_look, Props.BUMP_COLORS[hz.bump_look]))
		var tr: Dictionary = Track.TRACKS[int(cp.palette)]
		keys["%s surprise" % Deep.CUP_SURPRISE[String(cp.hz)]] = Deep.SURPRISES[Deep.CUP_SURPRISE[String(cp.hz)]].body
		out.append({"keys": keys, "bgs": {"%s road" % tr.theme: tr.road}})
	# The seasons' surprises land on every road of the tour.
	var sk := {}
	for se in Deep.SEASON_SURPRISE:
		sk["%s %s" % [se, Deep.SEASON_SURPRISE[se]]] = Deep.SURPRISES[Deep.SEASON_SURPRISE[se]].body
	out.append({"keys": sk, "bgs": backgrounds()})
	return out
