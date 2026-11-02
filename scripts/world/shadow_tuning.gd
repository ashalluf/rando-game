class_name ShadowTuning
## The sun's shadow, tuned per Quality level and by the camera's height, in ONE table (fleet wave
## 5, `shadows-review`; docs/HANDOFF.md, "Shadows across the game"). Quality._apply_render()
## calls apply_level(); DayNight._apply() calls follow() every frame (it re-reads the height four
## times a second). SHADOW_TUNING=0 is the A/B: the old numbers (city.tscn's splits, bias and
## fade, Quality's reach and blur), exactly, and nothing follows the camera.
##
## What the review found (Forward+ under lavapipe, tools/shadows_review/shadow_lab.tscn, and the
## refcams on opengl3; the HANDOFF section has the stills and numbers):
## - Godot fits each cascade round the camera's view depth, so from the air the first three
##   cascades (0-210 m of depth) held nothing but sky and the ground got the last one alone -
##   and past 500 m of depth there was no shadow at all: a golden-hour aerial was a lit city with
##   a ring of shadow at its feet. In the air the cascades now slide out with the clearance under
##   the camera (AIR_GAIN), so each one starts where there is something to shadow, and the reach
##   grows toward the LOD ring (AIR_CAP; the far city past it casts nothing anyway).
## - The 8 % fade drew that edge as a line: 20 % now.
## - A far landmark copy's planting cast no shadow (it is drawn from ~240 m out, well inside the
##   reach): FAR_PLANT_REACH.

static var enabled: bool = OS.get_environment("SHADOW_TUNING") != "0"

## Per Quality level (HIGH, MEDIUM, LOW, LOWEST): the reach on the ground (metres of view
## depth) and the PCF / PCSS blur. Unchanged from Quality.
const DISTANCE := [500.0, 380.0, 220.0, 120.0]
const BLUR := [1.0, 1.0, 0.7, 0.7]
## The old splits (city.tscn) and fade: where the four cascades end, as shares of the reach.
const OLD_SPLITS := [0.055, 0.16, 0.42]
const OLD_FADE := 0.92
## The fade now: the last 20 % of the reach.
const FADE_START := 0.8
## Metres each cascade's far end moves out per metre of clearance under the camera (the four
## ends: split 1, 2, 3 and the reach). From 140 m up (before the cap): 104 / 248 / 518 / 920 m. Ratios kept near
## the ground's (each cascade a little over twice the last), so no cascade is wasted.
const AIR_GAIN := [0.55, 1.2, 2.2, 3.0]
## The longest reach in the air per level (0: the level does not follow the camera). At 1000 m
## (the LOD ring's reach) the golden aerial refcam's shadow passes went 1.9 M -> 3.6 M triangles
## and +1,770 draws (every LOD chunk's batches in the last cascade); 750 keeps most of the look.
const AIR_CAP := [750.0, 560.0, 0.0, 0.0]
## Clearance under which the camera counts as on the ground, and the step it is rounded to (a
## hovering camera must not re-fit the cascades every frame: a new cascade radius re-snaps the
## texels and the shadow edges crawl).
const AIR_FROM := 12.0
## Under the cap each cascade still ends at least this many times further out than the one before.
const MIN_RATIO := 1.75
const AIR_STEP := 8.0
## Seconds between the downward rays, and how fast the clearance followed rises (it falls at
## once: a camera dropping to the street needs its fine cascade back now).
const PROBE_SECONDS := 0.25
const RISE_PER_SECOND := 60.0

## How far from the camera a far landmark copy's trees and palms cast (ArenaGrounds._far_shadows:
## they cast nothing before this pass, and a park seen from 300 m or from the air was a lawn of
## shadowless cut-outs). Measured to the grove's centre plus half its spread.
const FAR_PLANT_REACH := 450.0

static var level: int = 0
## The clearance the cascades were last fitted to (metres over AIR_FROM, stepped), and the raw
## clearance being followed.
static var air: float = 0.0
static var clearance: float = 0.0
static var _probe_at: float = -1.0
static var _last_ms: int = 0


static func apply_level(sun: DirectionalLight3D, lvl: int) -> void:
	level = clampi(lvl, 0, 3)
	if sun == null:
		return
	sun.shadow_blur = BLUR[level]
	if not enabled:
		sun.directional_shadow_max_distance = DISTANCE[level]
		return
	_fit(sun)


## Each cascade's far end in metres of view depth for a clearance `a` (metres above AIR_FROM).
static func ends(lvl: int, a: float) -> Array:
	var reach: float = DISTANCE[clampi(lvl, 0, 3)]
	var out := []
	for i in 4:
		var base: float = reach * (OLD_SPLITS[i] if i < 3 else 1.0)
		out.append(base + AIR_GAIN[i] * a)
	var cap: float = AIR_CAP[clampi(lvl, 0, 3)]
	if cap > 0.0 and out[3] > cap:
		# The reach stops at the cap; the near ends keep their slide (they cost little: what they
		# hold is near) as long as each cascade stays at least MIN_RATIO of the one before.
		out[3] = cap
		for i in [2, 1, 0]:
			out[i] = minf(out[i], out[i + 1] / MIN_RATIO)
	elif cap <= 0.0:
		for i in 4:
			out[i] = reach * (OLD_SPLITS[i] if i < 3 else 1.0)
	return out


static func _fit(sun: DirectionalLight3D) -> void:
	var e := ends(level, air)
	var reach: float = e[3]
	sun.directional_shadow_max_distance = reach
	sun.directional_shadow_split_1 = e[0] / reach
	sun.directional_shadow_split_2 = e[1] / reach
	sun.directional_shadow_split_3 = e[2] / reach
	sun.directional_shadow_fade_start = FADE_START


## Follows the camera's clearance over whatever is under it (a world-layer ray straight down,
## PROBE_SECONDS apart): on a rooftop or under a deck that is the roof or the street, so the hero
## standing on a tower keeps the fine cascade.
static func follow(sun: DirectionalLight3D, cam: Camera3D) -> void:
	if not enabled or sun == null or cam == null or not cam.is_inside_tree():
		return
	var now := Time.get_ticks_msec()
	var dt := clampf(float(now - _last_ms) / 1000.0, 0.0, 0.5)
	_last_ms = now
	_probe_at -= dt
	if _probe_at <= 0.0:
		_probe_at = PROBE_SECONDS
		var target := _clearance(cam)
		if target < clearance:
			clearance = target
		else:
			clearance = minf(target, clearance + RISE_PER_SECOND * PROBE_SECONDS)
		var a := snappedf(maxf(clearance - AIR_FROM, 0.0), AIR_STEP)
		if a != air:
			air = a
			_fit(sun)


static func _clearance(cam: Camera3D) -> float:
	var space := cam.get_world_3d().direct_space_state if cam.get_world_3d() else null
	if space == null:
		return 0.0
	var from := cam.global_position
	var q := PhysicsRayQueryParameters3D.create(from, from + Vector3.DOWN * 1500.0, 1)
	var hit := space.intersect_ray(q)
	if hit.is_empty():
		return 0.0
	return from.y - (hit.position as Vector3).y


## Puts the clearance back to the street (a teleport, a test).
static func reset() -> void:
	air = 0.0
	clearance = 0.0
	_probe_at = -1.0
