class_name RcChurchSunday
extends RefCounted
## The Mission church on a Sunday morning (wave 8 refcam5 "church_sunday", docs/HANDOFF.md "The
## Mission church on a Sunday morning"). What the view from across the street gave away, fixed:
##
## - The front was hidden: the kerb's street trees and the grounds' own lawn trees stood square in
##   front of the facade and the bell tower, so from the opposite pavement the church was a white
##   wall seen through leaves. `keeps_tree_off()` (one hook in CityChunk._add_tree(), after every
##   roll) keeps the kerb trees off a place of worship's front (the facade and the tower, with a
##   margin), and WorshipBuild's grounds keep their trees out of the lawn before the facade
##   (`front_clear()`): they stand to the sides, palms and trees framing it, as a real one is
##   planted.
##
## - The stucco was one flat sheet of white: the worship sites' stucco materials take
##   shaders/lime_wash.gdshaderinc (`lime_params()`: patchy coats, repair patches, streaks from the
##   copings, damp at the foot, the trowel's relief; a factor in linear light on both renderers).
##
## - The bell tower's shaft was a plain white box that merged with the facade into one white mass:
##   `tower_dress()` gives it a painted base, a moulded string course splitting it into two stages,
##   corner pilasters on the upper stage and a round, cast-stone-ringed light, all proud of the
##   wall so the sun draws their shadows.
##
## - A strip of sky ran across the facade under the espadana: the parapet's slab stands 0.3 m proud
##   of the wall it sits on and its underside was left open (`_slab_profile()` hides its bottom
##   edges), so from the street below the sky showed through it. `espadana_soffit()` closes it.
## - The stained glass read as bright confetti by day: from outside in daylight a stained window
##   is dark, its colour only a hint under the sky's sheen; worship_glass.gdshader's `day_dark`
##   (`glass_params()`) takes its daylight albedo and through-glow down, night untouched.
##
## A/B: RC5_CHURCH=0 in the environment (the trees as before). The congregation is WorshipSunday's
## (WORSHIP_SUNDAY=0).

static func _static_init() -> void: LoadPulse.compiled()  # a boot frame: docs/HANDOFF.md "The boot compile"

static var enabled: bool = OS.get_environment("RC5_CHURCH") != "0"

## Metres either side of the front the kerb keeps clear.
const TREE_CLEAR := 3.0


## The span of a site's front in its frame (local x0, x1): the building group the view is about.
static func front_span(p: Dictionary) -> Vector2:
	match int(p.kind):
		Worship.Kind.MISSION:
			var xc: float = p.xc
			var W: float = p.W
			return Vector2(xc - W * 0.5 - float(p.tower) - 0.4, xc + W * 0.5 + float(p.arcade) + 0.6)
		Worship.Kind.STOREFRONT:
			return Vector2(float(p.BX) - float(p.W) * 0.5, float(p.BX) + float(p.W) * 0.5)
	var w: float = float(p.get("W", 16.0)) + 6.0
	var c: float = float(p.get("xc", 0.0))
	return Vector2(c - w * 0.5, c + w * 0.5)


## True when a kerb tree at `at` (true world) would stand in front of a place of worship's front.
static func keeps_tree_off(plan: CityPlan, at: Vector3) -> bool:
	if not enabled or plan == null or not Worship.enabled:
		return false
	var q := Vector2(at.x, at.z)
	for s: Dictionary in Worship.near_rect(plan, Rect2(q - Vector2(2, 2), Vector2(4, 4)), plan.sidewalk_width + 2.0):
		var f: Dictionary = s.frame
		var n: Vector2 = f.n
		var front := Industrial.fp(f, float(s.L) * 0.5, 0.0)
		var d := q - front
		var lz := -d.dot(n)
		var lx := d.dot(Vector2(-n.y, n.x))
		if lz < -0.5 or lz > plan.sidewalk_width + 1.5:
			continue
		var span := front_span(WorshipBuild.plan_of(s))
		if lx > span.x - TREE_CLEAR and lx < span.y + TREE_CLEAR:
			return true
	return false


## True when a grounds tree at local `q` would stand between the street and the front.
static func front_clear(p: Dictionary, q: Vector2) -> bool:
	if not enabled:
		return false
	var span := front_span(p)
	return q.x > span.x - 2.0 and q.x < span.y + 2.0 and q.y > -float(p.get("fz", 8.0)) - 1.0


## The lime-wash uniforms for the worship stucco (landmark_facade.gdshader); {} with the pass off.
static func lime_params() -> Dictionary:
	if not enabled:
		return {}
	return {"lime_wash": 1.0, "lime_patch": 0.10, "lime_streaks": 0.14, "lime_damp": 0.22, "lime_relief": 0.5}


## The bell tower's shaft dressed (WorshipBuild._mission(), after the shaft and its cap moulding):
## `tc` the tower's foot (frame), `tw` its width, `sh` the shaft's height. Nothing with the pass off.
static func tower_dress(g: LandmarkGeo, tc: Vector3, tw: float, sh: float) -> void:
	if not enabled:
		return
	var stage := sh * 0.46
	# A painted base (the facade's) and a plinth course a little proud.
	g.box("trim", tc + Vector3(0, 0.45, 0), Vector3(tw + 0.08, 0.9, tw + 0.08))
	g.box("stucco", tc + Vector3(0, 1.05, 0), Vector3(tw + 0.16, 0.22, tw + 0.16), Color.WHITE, Basis(), 0.04)
	# The string course between the stages: a fillet, a cyma and a fillet, each a little wider.
	g.box("trim", tc + Vector3(0, stage, 0), Vector3(tw + 0.3, 0.18, tw + 0.3), Color.WHITE, Basis(), 0.03)
	g.box("trim", tc + Vector3(0, stage + 0.17, 0), Vector3(tw + 0.44, 0.16, tw + 0.44), Color.WHITE, Basis(), 0.05)
	g.box("stucco", tc + Vector3(0, stage + 0.32, 0), Vector3(tw + 0.22, 0.14, tw + 0.22), Color.WHITE, Basis(), 0.03)
	# Corner pilasters up the upper stage, 0.12 m proud, to the cap moulding.
	var ph := sh - stage - 0.4
	var py := stage + 0.4 + ph * 0.5
	var hw := tw * 0.5
	for sx: float in [-1.0, 1.0]:
		for sz: float in [-1.0, 1.0]:
			var c := tc + Vector3(sx * (hw - 0.3), py, sz * (hw - 0.3))
			g.box("stucco", c, Vector3(0.84, ph, 0.84), Color.WHITE, Basis(), 0.03)
	# A round light high on the front and the back, ringed in cast stone.
	for side: float in [1.0, -1.0]:
		var wc := tc + Vector3(0, sh - 1.6, side * (hw + 0.13))
		for k in 16:
			var t := TAU * float(k) / 16.0
			g.box("trim", wc + Vector3(cos(t) * 0.62, sin(t) * 0.62, 0.0), Vector3(0.34, 0.2, 0.14), Color.WHITE, Basis(Vector3(0, 0, 1), t + PI * 0.5))
		g.box("glass_stained", wc - Vector3(0, 0, side * 0.1), Vector3(0.92, 0.92, 0.02))


## The underside of the espadana's overhang (WorshipBuild._mission(), after the parapet's slab): a
## quad facing down at `fh` across the facade's width, from the wall's face `z0` out to `z1`.
static func espadana_soffit(g: LandmarkGeo, xc: float, hw: float, fh: float, z0: float, z1: float) -> void:
	if not enabled:
		return
	var y := fh + 0.002
	g.quad("trim", Vector3(xc - hw, y, z0), Vector3(xc + hw, y, z0), Vector3(xc + hw, y, z1), Vector3(xc - hw, y, z1), Vector3(0, -1, 0),
		Vector2(0, z0), Vector2(hw * 2.0, z0), Vector2(hw * 2.0, z1), Vector2(0, z1))


## worship_glass.gdshader's uniforms for the pass ({} off: the old daylight look).
static func glass_params() -> Dictionary:
	if not enabled:
		return {}
	return {"day_dark": 1.0}
