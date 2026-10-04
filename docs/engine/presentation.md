# Presentation engine (UI, HUD, dialogue, awards, meshes, creatures, skies, sound, music)

Shared, code-only building blocks so every game looks and sounds like part of one polished arcade.
All modules are plain scripts: `const X := preload("res://core/x.gd")` (no `class_name`). Everything
is generated in code (no image, font, audio or model files) and cached in Engine metadata through
`core/res_cache.gd`, which empties itself when the game quits (no leaked GPU resources).

| Module | What it gives you |
|---|---|
| `core/ui_kit.gd` | Theme, palette, panels, labels, badges, button glyphs, vector icons, animated bars, tweens, 3D panel/label helpers, VR placement |
| `core/ui_input.gd` | Per-player input reader (one controller / key set / VR hand -> "up", "confirm", ...) with latch + key repeat |
| `core/ui_menu.gd` | Controller menus bound to ONE player: lists, grids, tabs, scrolling, disabled items with reasons |
| `core/vr_menu.gd` | World-space VR menu: point + trigger, touch, or stick + A |
| `core/dialogue.gd` | Typewriter dialogue with speakers, choices, branching script format; TV + VR |
| `core/hud_kit.gd` | Banners, toasts, damage popups, 3D HP bars, scoreboards, countdown, timer, party status cards, objectives, speech bubbles, VR cards |
| `core/hints.gd` | "How to play" intro cards per role (VR / TV) and once-only contextual hints with cooldowns |
| `core/awards.gd` | Per-player stats, award picker (MVP, LIFESAVER...), results screen (TV) and VR summary |
| `core/mesh_kit.gd` | Merge vertex-coloured primitives into one mesh; MultiMesh scatter; ready props |
| `core/creatures.gd` | Chibi humanoids (classes, hats, weapons) and monsters/animals with a small animator |
| `core/sky_kit.gd` | Environment presets (day, sunset, night, cave, space, underwater, storm, indoor...) |
| `core/sfx.gd` | Procedural sound effects (old API kept) + many new sounds, loops, 3D sounds, buses |
| `core/music.gd` | Procedural music (old `play_track` kept) + moods, `add_track`, crossfades |
| `core/res_cache.gd` | `ResCache.get_or_make(key, maker)`: shared resource cache that survives reloads |

Tested by `tests/engine_ui_test.tscn` (`godot --headless --path . --fixed-fps 60 res://tests/engine_ui_test.tscn`,
`ENGINE_PARTS=ui,world,audio` picks parts). Read its parts in `tests/engine_ui/` for more usage examples.

## With the engine systems (core/party.gd, core/split_view.gd, core/vr_rig.gd)

`games/engine_template/` (Star Catch) uses every module below on top of the systems: copy it.

```gdscript
var ui := UiKit.ui_root(split.hud(slot))          # per view; undoes SplitView's HUD scaling itself
var shared_ui := UiKit.ui_root(split.shared_hud())
UiMenu.open(ui, {"party": party, "slot": slot, "items": [...]})       # that seat's pad / keyboard
VrMenu.open(self, {"rig": vr_rig, "items": [...]})                   # guarded trigger, right hand
dlg.bind_party(party); dlg.set_vr_rig(vr_rig)     # any local seat (or the VR trigger) advances
hints.bind_party(party); hints.set_vr_rig(vr_rig, self); hints.add_view(ui, slot)
Awards.results_screen(shared_ui, data, {"party": party}); Awards.vr_summary(self, null, data, null, {"rig": vr_rig})
var input := UiInput.for_party(party, slot)      # or UiInput.for_rig(vr_rig) for your own screens
if UiMenu.slot_busy(slot): return                # skip that seat's gameplay input while its menu is open
```
Player colours (`UiKit.player_color(slot)`) are `Party.COLORS`: slot 0 is the VR player (P1, blue).
Put round/phase/results data in the net state store (`net.state_set("results", awards.results())`)
and build the UI in `state_changed`, so the host and the TV machine show the same thing.

## Rules of thumb

- **Every TV view gets a UI root**: `var ui := UiKit.ui_root(view)` where `view` is Main (full screen),
  a split-screen `SubViewport`, or an existing CanvasLayer/Control. The root's Theme follows the view's
  size (scale 1.0 at 1920x1080, about 0.55 for a 3x2 split cell), so text never gets too big or small.
  Put every panel/menu/HUD for that view under its root.
- **Each player's UI is bound to that player's input**: a party seat (`{"party": party, "slot": slot}`),
  or a raw `device` (joypad id) + `keys` (key set or `UiInput.KEYS_NONE`) without core/party.gd. Six
  players can each have a menu open at once. Real controllers on the dev machine use low ids: bots
  should use the party's virtual pads (40+).
- **UI is local.** Menus, dialogue and HUD run on each machine. The host decides; send results and
  one-off displays with `net.event(...)` / `net.send_action(...)` and show them on the client. The
  data you pass (`awards.results()`, dialogue line indices, scoreboard rows) is plain and network-safe.
- **VR text** (vr_menu, dialogue VR box, VrCard, hints, awards summary) is world-space, never on the
  camera and never billboarded, ~2-2.5 m away and lazily follows the view (core/vr_text.gd rules).
  Pass the XR camera and the right hand. Use `layers` to keep VR-only panels off TV cameras when the
  same world is rendered by a TV window on the host.
- **No symbol glyphs in text** (the font has no hearts, stars or arrows): use `UiKit.icon(...)` shapes
  and `UiKit.glyph("A")` button badges.
- **UI sounds** go through one shared, always-processing sfx node (`UiKit.sound(name)`), so menus work
  while paused and in every game.
- A button still held from the previous screen never acts on the next one (`UiInput.latch()` is called
  whenever a menu/dialogue/card opens).

## UiKit (core/ui_kit.gd)

```gdscript
const UiKit := preload("res://core/ui_kit.gd")
var ui := UiKit.ui_root(self)                    # CanvasLayer + themed full-rect root (mouse-transparent)
var card := UiKit.panel("card")                  # "default", "card", "accent", "toast", "pill", "dialogue",
                                                 # "flat", "danger", "success", "info", "tooltip", "clear"
var v := UiKit.vbox()
card.add_child(v)
v.add_child(UiKit.title("TREASURE!"))
v.add_child(UiKit.label("You found 30 coins", "body", "gold"))
v.add_child(UiKit.prompts([["A", "Take"], ["B", "Leave"]]))
ui.add_child(card)
card.set_anchors_preset(Control.PRESET_CENTER)
UiKit.pop_in(card)
var hp := UiKit.bar("hp", 300, 24); hp.show_numbers = true; hp.prefix = "HP"
hp.set_value(35, 100)                            # animated, trailing damage chip, low-HP pulse
```

- Palette constants: `BG`, `BG_CARD`, `BG_DEEP`, `TEXT`, `TEXT_DIM`, `TEXT_OFF`, `ACCENT` (gold), `GOOD`,
  `BAD`, `INFO`, `WARN`, `MAGIC`, `GOLD`, `SILVER`, `BRONZE`, `HP_FULL/MID/LOW`, `MP`, `XP`,
  `PLAYER_COLORS` (= `Party.COLORS`, by slot: P1/VR blue, P2 gold, P3 pink, P4 green, P5 white, P6 purple, P7 teal).
- `player_color(i)`, `color_of(Color | "good" | player_index)`, `hp_color(frac)`.
- `scale_for_size(size)`, `scale_of(node)`, `font_size(kind, scale)`, `font(bold, spacing)`, `theme(scale)`,
  `stylebox(bg, scale, radius, border, border_w, shadow, margin)`.
- `ui_root(parent, layer=5, fixed_scale=0)` -> Control (`UiRoot`, emits `scale_changed`).
- `panel(style)`, `tinted_panel(color, scale, style)`, `label(text, kind, color, align)` (kinds: banner,
  title, heading, number, subtitle, body, small, tiny, dim, accent), `title(text)`, `paragraph(text)`,
  `vbox()/hbox()`, `spacer()`, `badge(text, color, scale, icon)`, `glyph("A"|"B"|"X"|"Y"|"LB"|"START"|...)`,
  `prompts([[glyph, text], ...])`, `icon(kind, color, px)`, `bar(kind, w, h, color)`, `stat_bar(name, kind, w)`.
- Icon kinds: heart, star, coin, gem, sword, shield, potion, skull, check, cross, arrow_up/down/left/right,
  play, clock, bolt, crown, lock, dot, plus, minus, flag, key, music, bag, fire, drop, eye, person, trophy,
  question, exclaim.
- Animations (return the Tween): `pop_in(c, delay)`, `pop_out(c, free_after)`, `slide_in(c, offset)`,
  `fade(c, to)`, `pulse(c)`, `shake(c)`, `count_up(label, from, to, time, "%d PTS")`. Containers reset
  their children's scale, so pop/pulse/shake fall back to fades/flashes inside containers.
- `sound(name, volume_db, pitch)` - UI sounds on the shared sfx node.
- `normalize_items(list)` - the item format shared by menus and dialogue choices.
- 3D: `panel3d(size_m, fill, border)`, `panel_mesh(...)`, `vr_panel_material(priority, depth_test, billboard)`,
  `label3d(text, height_m, color, bold, width_m)`, `wrap_text(text, width_px, size)`,
  `vr_place(node, cam, dist, height)`, `vr_follow(node, cam, dist, height, delta)` (lazy follow),
  `xr_camera(node)` (the XR camera if this viewport renders VR, else null).

## UiInput (core/ui_input.gd)

```gdscript
var input := UiInput.for_party(party, slot)            # a core/party.gd seat (slot -1 = any local seat)
var vr_in := UiInput.for_rig(vr_rig)                   # the VR player through core/vr_rig.gd
var raw := UiInput.new(p.joy, UiInput.KEYS_NONE)       # without the systems: (PAD_ANY, KEYS_ALL), (.., .., hand_r)
input.latch()                                           # ignore buttons still held from before
for a in input.poll(delta):                             # "up","down","left","right","confirm","cancel","tab_prev","tab_next"
	...
```
Key sets: `KEYS_WASD` (WASD, Space/F confirm, X/Backspace back, Q/E tabs), `KEYS_ARROWS` (arrows, Enter,
Backspace/Delete, PgUp/PgDn), `KEYS_ALL`, `KEYS_NONE`. Pads: A confirm, B back, d-pad/left stick move,
LB/RB tabs. A VR hand (XRController3D or a fake Node3D with metadata `trigger`, `ax_button`,
`by_button`, `primary`): trigger/A confirm, B back, stick up/down. Also `held(action)`, `state()`,
`glyphs()` (prompt names for this input), `note_event(ev)` (lets PAD_ANY hear bots' fake pads).

## UiMenu (core/ui_menu.gd)

```gdscript
const UiMenu := preload("res://core/ui_menu.gd")
var m := UiMenu.open(ui, {"title": "COMMAND", "party": party, "slot": slot, "anchor": "bottom_left",
	"items": [{"id": "attack", "text": "Attack", "icon": "sword", "desc": "Hit one enemy."},
		{"id": "fire", "text": "Fireball", "icon": "fire", "right": "6 MP", "disabled": mp < 6, "reason": "Not enough MP"},
		{"id": "item", "text": "Item", "icon": "bag"}, "Run"]})
m.chosen.connect(func(id: String, item: Dictionary) -> void: net.request(slot, "command", [id]))
m.cancelled.connect(...)
```
- Items: String or `{id, text, desc, disabled, reason, icon, icon_color, right, badge, badge_color, color, data}`.
- Options: title, items | tabs `[{title, items}]`, columns (grid), max_rows (scrolls), width, party +
  slot (the usual way; also `bind_party(party, slot)`), player (tint + "P3" badge; defaults to the
  slot), device, keys (without a party), mouse, anchor (center, top, bottom, left, right, top_left, ...), margin,
  close_on_choose, allow_cancel, free_on_close, prompts, desc, wrap, start (id/index), sounds,
  cancel_text, confirm_text, accent, input (false = only `press()` drives it).
- Signals: `chosen(id, item)`, `cancelled()`, `rejected(id, item)` (disabled item: error sound, shake,
  reason shown), `focus_changed(id, item)`, `tab_changed(i)`, `closed()`.
- Methods: `press("down"|"confirm"|...)` (bots / network), `confirm(i)`, `cancel()`, `focus(id|index)`,
  `choose_id(id)`, `set_tab(i)`, `set_items(list)`, `set_disabled(id, bool, reason)`, `focused_id()`,
  `close()`, `open_menu()`, `bind_party(party, slot)`; static `UiMenu.slot_busy(slot)` /
  `UiMenu.device_busy(joy)` (skip gameplay input while that player's menu is open), `UiMenu.vr(world, opts)`.
- Shops: `close_on_choose: false` and `set_disabled(...)` when money changes. Inventories: `columns: 4`
  with `icon` + `badge: "x3"`. Quiz answers: `columns: 2`.

## VrMenu (core/vr_menu.gd)

```gdscript
const VrMenu := preload("res://core/vr_menu.gd")
var vm := VrMenu.open(self, {"title": "YOUR TURN", "rig": vr_rig,
	"items": ["Attack", "Magic", {"id": "item", "text": "Item", "disabled": true, "reason": "Bag is empty"}]})
vm.chosen.connect(func(id: String, _item: Dictionary) -> void: ...)
```
Point the right hand (laser + dot appear on the panel) and pull the trigger, or stick up/down + A, or
touch an option. Options: as UiMenu plus `rig` (a core/vr_rig.gd VrRig: camera, right hand, guarded
trigger/A and haptics; also `bind_rig(rig)`) or `cam` + `hand`, `distance` (1.25 -> 2 m after the vr_text
comfort factor), `height`, `follow` (lazy follow), `reach: true` (0.42 m away and low: touchable),
`touch`, `columns` (2 = 2x2 quiz answers), `position` (fixed world spot), `layers`, `haptics`.
`allow_cancel` adds a BACK row. Signals and `press()/confirm()/focus()/set_items()` as UiMenu.

## Dialogue (core/dialogue.gd)

```gdscript
const Dialogue := preload("res://core/dialogue.gd")
var dlg := Dialogue.new()
add_child(dlg)
for slot in party.local_slots(): dlg.add_tv_view(huds[slot], slot)   # a box at the bottom of each view
dlg.bind_party(party)                                   # any local seat advances (A)
dlg.set_vr_rig(vr_rig)                                  # and a world-space box in VR (trigger / A)
dlg.play([
	{"speaker": "ELDER", "color": "gold", "text": "Welcome, {hero}!"},
	{"speaker": "ELDER", "text": "Will you help us?", "choices": [
		{"text": "Of course!", "goto": "yes", "set": {"helping": true}},
		{"text": "Not today", "goto": "no"}]},
	{"label": "yes", "text": "Wonderful! Take this map.", "event": "got_map", "goto": "end"},
	{"label": "no", "speaker": "ELDER", "text": "Oh... come back soon."},
	{"label": "end"},
], {"vars": {"hero": "Sir Bun"}})
dlg.event.connect(func(name: String, _line: Dictionary) -> void: ...)
await dlg.finished
```
- Line keys: `speaker`, `text` (`{var}` substitution), `color`, `portrait` (initials, an icon kind, or ""),
  `choices`, `label`, `goto` ("end" stops), `event`, `set`, `if` ("var" / "!var"), `call` (Callable),
  `wait` (s, no box), `auto` (advance N s after typing), `speed`, `pitch`, `sound`, `chooser` ("tv"/"vr"),
  `device` (who answers the choice), `end`.
- Input: A / Enter / trigger finishes the typing, then advances; holding it skips to the next choice
  (running the skipped lines' events). Options: device (PAD_ANY default), keys, speed, skippable, vars.
- Signals: `started`, `line_started(index, line)`, `line_typed(index)`, `choice_made(id, i)`,
  `event(name, line)`, `finished`; mirrors (`remote = true`): `advance_requested`, `choice_requested(i)`.
- Methods: `play(lines, opts)`, `say(speaker, text, color)`, `advance()`, `choose(i)`, `skip()`, `stop()`,
  `show_line(i)` (mirrors), `is_playing()`.
- Network pattern: host plays and sends `line_started` indices with `net.event("dlg", [i])`; the client
  plays the same lines with `remote: true` and calls `show_line(i)`; client input arrives via
  `advance_requested` -> `net.send_action("dlg_next", [])` -> host `dlg.advance()`.

## HudKit (core/hud_kit.gd)

```gdscript
const HudKit := preload("res://core/hud_kit.gd")
HudKit.banner(all_roots, "ROUND 2", "Fight!", {"style": "default"})   # "victory", "defeat", "info", "boss", "level"
HudKit.toast(ui, "P2 found a key!", {"icon": "key", "color": 1})
HudKit.damage(self, enemy.global_position + Vector3.UP * 1.5, 42, crit)  # also heal(), score(), miss(), popup()
var hp := HudKit.bar3d(enemy, {"max": 30, "name": "GOBLIN", "hide_full": true}); hp.set_value(12)
var board := HudKit.scoreboard(ui, rows, {"title": "ROUND 1"}); board.set_rows(new_rows)  # animated
var cd := HudKit.countdown(all_roots, 3); await cd.finished
var clock := HudKit.timer(ui, {"seconds": 90, "warn": 10}); clock.timeout.connect(...)
var party := HudKit.party_bar(ui, [{"player": 0, "name": "KNIGHT", "level": 5, "hp": [80, 100], "mp": [10, 20]}, ...])
var card: HudKit.StatusCard = party.get_child(0); card.set_hp(40); card.set_active(true)
HudKit.objectives(ui, ["Find the key", "Open the door"]).set_done("Find the key")
HudKit.bubble3d(npc, "Hello, traveller!")              # speech bubble over a 3D object
HudKit.nameplate(player_node, "P2", 1)
HudKit.vr_banner(self, xr_cam, "VICTORY!", "", {"style": "victory"}); HudKit.vr_toast(self, xr_cam, "Key found!")
```
- Banners/toasts/countdowns accept one root or an Array of roots (all split-screen views).
- Popups face the VR camera when that viewport renders VR, else billboard; styles damage, crit, heal,
  score, xp, miss, bad, info. `size` scales them (1 = ~0.3 m).
- `rank_rows(rows, ascending)`, `rank_color(rank)`, `ordinal(n)` ("1ST"), `clock_text(s, tenths)`.
- VR: `vr_card(world, cam, title, body, opts)` (`VrCard`: `set_text`, `hide_card`), `vr_banner`, `vr_toast`,
  `vr_countdown`.

## Hints (core/hints.gd)

```gdscript
const Hints := preload("res://core/hints.gd")
var hints := Hints.new(); add_child(hints)
hints.add_view(huds[slot], slot)          # each TV view (slot -1 = a shared screen)
hints.bind_party(party)                   # any local seat dismisses the intro
hints.set_vr_rig(vr_rig, self)            # the VR player is slot 0
hints.intro({"title": "DRAGON DUNGEON", "goal": "Find the key and escape together!",
	"vr": {"role": "THE KNIGHT", "controls": [["TRIGGER", "Swing your sword"], ["STICK", "Walk"]]},
	"tv": {"role": "THE WIZARDS", "color": "magic", "controls": [["A", "Cast"], ["L-STICK", "Move"]],
		"tips": ["Stay close to the knight!"]}})
await hints.intro_done
hints.hint("door", "Doors open with a KEY!", {"icon": "key"})                      # once, everyone
hints.hint("low_hp", "Drink a potion!", {"to": slot, "button": "Y", "times": 3, "cooldown": 40})
```
Intro options: `slots` (per-player roles), `duration` (auto close, 14 s), `min_time` (1.5 s). Hint options:
`to` ("all", "tv", "vr", slot), `times`, `cooldown`, `duration`, `icon`, `button`, `vr_text`, `color`,
`priority`, `force`. A busy screen queues hints (shown in turn, dropped after 12 s). `was_shown()`,
`reset()`, `persist = true` remembers once-only hints across sessions.

## Awards (core/awards.gd)

```gdscript
const Awards := preload("res://core/awards.gd")
var awards := Awards.new()
awards.set_player(0, "KNIGHT")                # colour defaults to the player colour
awards.add(i, "damage", 35); awards.add(i, "revives"); awards.best(i, "best_time", 41.2, true)
awards.define("pie_master", "PIE MASTER", "%s pies baked", "pies")          # game-specific, shown first
var data := awards.results({"title": "VICTORY!", "style": "victory", "stats": [["TIME", "4:12"]], "score_format": "%d PTS"})
net.event("results", [data])                  # plain data
var screen := Awards.results_screen(shared_ui, data, {"party": party})  # TV: standings, award cards, Continue (A)
await screen.continued
Awards.vr_summary(self, null, data, null, {"rig": vr_rig})   # VR: trigger continues
```
Catalogue stats -> titles: score MVP, damage HEAVY HITTER, revives LIFESAVER, healing GUARDIAN ANGEL,
damage_taken IRON WALL, blocks SHIELD WALL, hits SHARPSHOOTER, crits CRITICAL!, kills MONSTER MASHER,
spells ARCHMAGE, pickups TREASURE HUNTER, coins MONEYBAGS, best_time SPEED DEMON (lowest),
fastest_answer QUICK DRAW (lowest), correct BRAINIAC, best_streak ON FIRE, clutch CLUTCH, assists TEAM
PLAYER, distance EXPLORER, builds MASTER BUILDER, clues SUPER SLEUTH, holes_in_one HOLE IN ONE, sixes
LUCKY DICE, jumps BOUNCY, drops BUTTERFINGERS, falls DAREDEVIL, deaths TOO BRAVE. `pick(max)` gives each
player one award before doubling up, most remarkable first; players without one get a friendly
consolation title (GOOD SPORT, TEAM SPIRIT...). `standings(stat)`, `get_stat`, `total`, `reset`.

## Meshes (core/mesh_kit.gd)

`const MeshKit := preload("res://core/mesh_kit.gd")` bakes many vertex-coloured primitives into ONE
ArrayMesh: one draw call (plus one if some parts glow). Primitives are centred on their origin and placed
by a part transform; normals and winding stay correct under any rotation, non-uniform scale or mirroring.

```gdscript
var b := MeshKit.Builder.new()
b.rounded_box(Vector3(1.2, 0.8, 1.0), 0.15, MeshKit.at(Vector3(0, 0.4, 0)), Color(0.9, 0.6, 0.4))
b.cone(0.8, 0.6, MeshKit.at(Vector3(0, 1.1, 0)), Color(0.8, 0.3, 0.3))
b.sphere(0.12, MeshKit.at(Vector3(0, 0.5, 0.52)), Color(1, 0.9, 0.5), 10, true)   # glowing window
var hut: ArrayMesh = ResCache.get_or_make("mygame_hut_v1", b.build)
add_child(MeshKit.instance(hut))
add_child(MeshKit.scatter_random(MeshKit.prop("pine"), 80, Vector3.ZERO, 60.0, 15.0))  # a forest: 1 draw call
```
- Builder parts `(sizes..., xf, color, [segs], [emissive])`: `box(size)`, `rounded_box(size, radius)`,
  `sphere(r)`, `ellipsoid(radii)`, `dome(r)` (base at y=0), `cylinder(r_top, r_bottom, h)`, `cone(r, h)`,
  `capsule(r, h)`, `torus(ring_r, tube_r)`, `wedge(size)` (high side at -Z), `prism(sides, r, h)`; flat:
  `disc(r)` (faces +Y), `panel(size2, corner_r)` (faces +Z), `star(points, outer, inner, depth)`,
  `polygon(outline2d, depth)`; between points: `tube(a, b, r_a, r_b, color)`, `capsule_between(a, b, r, color)`;
  `add_mesh(mesh, xf, tint)`. Finish with `build(lit_mat = null, glow_mat = null) -> ArrayMesh` (surfaces
  "lit" and "glow"); `vertex_count()`, `triangle_count()`, `flag` (written to UV.x for custom shaders).
- Transforms: `MeshKit.at(pos, scale, rot_radians)`, `MeshKit.aim(pos, dir, scale)` (part +Y along dir).
- Materials (cached): `vertex_material(unshaded = false, transparent = false)` (sRGB vertex colours),
  `glow_material()`, `additive_material()`, `material(color, glow)`; `instance(mesh, shadows = true)`.
- `merge([[Mesh, Transform3D, Color(, flag)], ...])` accepts the games' old mesh_kit.gd format.
- MultiMesh: `scatter(mesh, transforms, colors = [], custom = [], shadows) -> MultiMeshInstance3D` (one
  draw call, per-instance tint), `scatter_random(mesh, count, center, max_r, min_r, scale_min, scale_max, palette, seed)`.
- Ready props (one cached mesh each, origin at the base, front +Z): `prop(name, variant = 0)`,
  `prop_names()`: tree, pine, palm, bush, rock, grass, flower, mushroom, crate, barrel, chest, lamp_post,
  torch, fence, sign, cloud, coin, gem, heart, star, table, chair, bookshelf, candle, pot.

## Creatures (core/creatures.gd)

`const Creatures := preload("res://core/creatures.gd")`: cute chibi characters, about 1.1 m tall.
**Origin at the feet, front = +Z**: turn them with `anim.face(dir)` or `look_at(target, Vector3.UP, true)`
(plain `look_at` turns their back to the target). Meshes are cached per look, so identical creatures share them.

```gdscript
var hero := Creatures.humanoid({"class": "knight", "hair": Color(0.9, 0.6, 0.2), "seed": 3})
add_child(hero)
var anim := Creatures.anim(hero)
anim.face_point(slime.global_position)
anim.play("attack", -1.0, slime.global_position - hero.global_position)
await anim.action_finished
Creatures.anim(slime).hurt(Color(1, 1, 1), hero.global_position - slime.global_position)
```
- `humanoid(opts) -> Node3D`, 6 draw calls (torso, head, 2 arms, 2 legs; +1 while blinking, +1 for glowing
  items). opts: `class` (`CLASSES`: knight, mage, healer, thief, archer, bard, pirate, astronaut, chef,
  detective, monk, ninja, king, queen, princess, villager, scientist, farmer, viking, crew, pilot, golfer,
  host, athlete), `skin`, `hair`, `hair_style` (short, long, spiky, bob, ponytail, bun, curly, mohawk,
  pigtails, bald), `beard` (none, short, long, moustache), `ears` ("round"/"pointy"), `eye_color`, `outfit`,
  `outfit2`, `pants`, `shoes`, `cape`, `hat` (`HATS`), `weapon` / `offhand` (`ITEMS`: sword, dagger, katana,
  cutlass, axe, hammer, spear, club, staff, rod, wand, bow, shield, round_shield, lute, ladle, magnifier,
  flask, torch, pitchfork, sceptre, book, lantern, blaster, wrench, golf_club, microphone, pan,
  fishing_rod, broom, tablet, flag), `seed`, `scale`, `lod` ("near" | "far" = 1 merged mesh | "auto"),
  `lod_distance` (14 m). `random_humanoid_opts(seed)`, `resolve_humanoid(opts)`.
- `monster(kind, opts) -> Node3D`: slime, bat, goblin, skeleton, wolf, dragon, robot, ghost, fish, bird,
  mushroom, mimic, frog, spider, penguin, bunny, bee, crab, golem, cat, dog, fox, pig, sheep (`list_kinds()`,
  rigs and draw calls in `MONSTER_INFO`: 1-7). opts: `color`, `color2`, `eye_color`, `scale`, `boss`
  (bigger, glowing eyes, crown/horns), `lod`, `weapon` (goblin, skeleton).
- `crowd(transforms, looks = 4, seed, kind = "humanoid") -> Crowd`: a MultiMesh audience in `looks` draw
  calls; `crowd.cheer` (0-1) makes them bounce.
- `height_of(c)` (for name tags), `face_now(node, dir)`.
- Animation `var a := Creatures.anim(c)`: `a.walk(speed_mps)`, `a.face(dir)`, `a.face_point(pos)`,
  `a.flying`; one-shots `a.play("attack" | "hurt" | "cast" | "cheer" | "jump" | "wave" | "talk" | "nod", duration, dir)`;
  `a.play("victory")` loops until `a.stop()`; `a.faint()` / `a.revive()`; `a.hurt(color, from_dir)`,
  `a.flash(color, t)`, `a.squash(amount)`, `a.blink()`; `a.is_busy()`, `a.is_down()`, `a.rate`; signal
  `action_finished(action)`.
- Thousands of random looks? Call `ResCache.clear("cr_")` now and then (looks are cached until quit).

## Skies (core/sky_kit.gd)

`const SkyKit := preload("res://core/sky_kit.gd")`. `SkyKit.apply(parent, preset, vr) -> SkyRig` adds the
WorldEnvironment, the sun/moon DirectionalLight3D and cheap extras (don't add your own).

```gdscript
var sky := SkyKit.apply(self, "sunset", players[0].vr)
sky.lightning.connect(func(_s: float) -> void: sfx.play("thunder"))
sky.set_preset("stormy", 5.0)            # blend over 5 s
# city builder: sky.set_time_of_day(clock_hours) every frame
```
- Presets: day, dawn, sunset, night (stars + moon), spooky, dungeon (alias cave), space (stars + ringed
  planet), underwater (bubbles + light shafts), stormy (rain + lightning), snowy, indoor (alias cosy).
  `preset_names()`, `resolve(name)`.
- VR (`vr = true`): no fog, SSAO, SSR, SDFGI, glow or directional shadows, half the particles. TV: distance
  fog where it suits, soft sun shadows (max 60 m), gentle glow.
- SkyRig: `set_preset(name, blend_seconds)`, `set_time_of_day(hour)`, `follow(camera)` (default: the
  viewport's current camera; call it per view in split screen), `flash(strength)` + signal
  `lightning(strength)`, `set_rain(on)`, `set_snow(on)`, `set_clouds(count)`, `draw_calls()`; members
  `env`, `sun`, `sky_mat`, `world_env`, `cloud_drift`. Extra draw calls: day/dawn/sunset 1, night 4,
  spooky 5, dungeon/indoor 1, space/underwater/stormy/snowy 2.
- `SkyKit.flicker_light(color, energy, range) -> OmniLight3D`: a gently flickering torch/candle light.

## Sound effects (core/sfx.gd)

`const SfxScript := preload("res://core/sfx.gd")`, then `sfx = SfxScript.new(); add_child(sfx)` (the old API
is unchanged). Every sound is synthesised once and shared for the whole session. UI sounds (`ui_*`,
`type`) play on the **UI** bus; everything else on **SFX**; music on **Music**.

| API | What it does |
|---|---|
| `play(name, volume_db := 0.0, pitch := 1.0)` | One-shot with a small random pitch jitter. Unknown names are ignored. |
| `play_at(name, position: Vector3, volume_db, pitch)` | Positional 3D one-shot (pool of 12 voices). Without a current 3D camera (split screen) it plays flat, faded by the distance to `sfx.listener`. |
| `play_loop(name, volume_db := 0.0, fade := 0.3)` / `stop_loop(name, fade := 0.5)` / `stop_all_loops(fade)` | Seamless loops; calling `play_loop` again only changes the volume. |
| `is_looping(name)`, `set_loop_volume(name, db, fade)`, `set_loop_pitch(name, pitch)` | Control a running loop (e.g. an engine revving with speed). |
| `play_loop_at(name, node3d, volume_db) -> AudioStreamPlayer3D` / `stop_loop_at(node3d, name)` | A positional loop on a moving object. |
| `add_sound(name, [secs, f0, f1, vol, wave, noise])` | Classic 6-value sweep (replaces a built-in of the same name). |
| `add_recipe(name, recipe)` / `add_loop(name, recipe)` | Layered custom sound / loop (recipe format in the file header). |
| `warm(names := [], background := false)` | Pre-synthesise: call `sfx.warm([], true)` once at game start so no first play hitches (~15 ms each). |
| `get_stream(name)`, `get_loop_stream(name)` | The cached AudioStream. |
| `SfxScript.list_sounds()` / `list_loops()` | All built-in names. |
| `SfxScript.ensure_buses()`, `set_bus_volume(bus, linear)`, `get_bus_volume(bus)` | "Music", "SFX", "UI" buses. |

- Classic: shoot, hit, kill, big_kill, hurt, down, revive, pickup, dash, wave, clear, gameover, zap, spit.
- UI: ui_move, ui_select, ui_back, ui_error, ui_open, ui_close, ui_tick, ui_toggle, ui_notify, type.
- RPG: sword, sword_hit, magic, fire, ice, heal, level_up, crit, potion, coin, chest, door, footstep, block,
  miss, faint, explosion, jump, land, bow, buff, debuff, equip, kaching.
- Sports: kick, ball_hit, bounce, swish, cheer, whistle, applause, crowd_oh, horn.
- Sci-fi: laser, warp, alarm, beep, power_up, power_down, teleport, computer.
- Quiz: buzzer, correct, wrong, tick, tock, countdown, go, time_up, fanfare, reveal, drumroll, crash.
- Party: dice, card, pop, boing, ding, bell, whoosh, splash, honk, party_horn, clap, sparkle, win,
  sad_trombone, achievement.
- Loops: alarm, hum, engine, rain, wind, crowd, fire, clock, bubbles, space, waves, birds, heartbeat.

```gdscript
sfx.warm([], true)                      # once, at load
sfx.play_at("sword_hit", enemy.global_position)
sfx.play_loop("rain", -8.0)             # ambience; sfx.stop_loop("rain") later
sfx.add_recipe("zing", {"len": 0.3, "layers": [{"w": "tri", "f": 880.0, "f1": 1760.0, "len": 0.25, "dec": 8.0}]})
```

## Music (core/music.gd)

`music = MusicScript.new(); add_child(music)` (plays on the **Music** bus; `volume_db`, `pitch_scale` and
`play_track(i)` work as before; track 0 still autoplays one frame later unless you pick a mood first).

| API | What it does |
|---|---|
| `play_mood(name, fade := 1.5)` | Crossfade to a mood; synthesised in the background the first time (~0.5-1.5 s) while the old music keeps playing. |
| `prepare(["battle", "victory"])` | Synthesise ahead so later switches are instant (do it at load). |
| `fade_out(seconds := 1.0)` | Silence moods and classic tracks. |
| `add_track(def)` + `play_mood(def.name)` | Custom composition: bpm, key, scale, parts/form or chords, lead/melody, bass, pad, arp, drums, hits/roll, reverb, `loop` (format in the file header). |
| `play_track(i)` | Classic synthwave loops 0-2, unchanged (fades any mood out). |
| `current_mood`, `is_mood_ready(name)`, `is_music_playing()`, `list_moods()`, `MusicScript.builtin_moods()`, `MusicScript.resolve(alias)` | State and lookup. |
| `resume_after_jingle := true` | After a one-shot (victory, defeat, custom `loop: false`) the previous mood fades back in where it stopped. |
| signals `mood_changed(mood)`, `jingle_finished(mood)` | |

Moods: town (cosy), overworld (heroic), battle (driving), boss (intense), victory (one-shot fanfare),
defeat (one-shot), dungeon (mysterious), quiz (quiz-show swing), space (floaty), cosy (3/4 lullaby), party
(four-on-the-floor), shop (bossa), mystery (detective jazz), race (fast rock), tension (countdown pulse).
Aliases: sleepy/lullaby -> cosy, adventure -> overworld, detective -> mystery, fanfare -> victory,
gameover -> defeat, menu -> town. Seeded: host and TV hear the same tune. `music.playing` is false
while a mood plays (two child decks): use `is_music_playing()` / `current_mood`.

```gdscript
music = MusicScript.new()
add_child(music)
music.play_mood("town")
music.prepare(["battle", "victory"])
music.play_mood("battle", 0.8)          # later: crossfade
music.play_mood("victory")              # fanfare, then battle resumes
```
