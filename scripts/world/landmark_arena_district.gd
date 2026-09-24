class_name LandmarkArenaDistrict
extends RefCounted
## The arena district at the south-west edge of downtown (owner, 2026-09-24: "downtown must match
## real downtown LA, we need staple center"): the real buildings' FORMS in their real places
## relative to the core, with every NAME invented (trademarks) - the arena is RANDO ARENA, the
## entertainment plaza STARLIGHT PLAZA with the STARLIGHT THEATER, the hotel HOTEL ALTAIR, and
## every brand on the screens is made up (LedScreen.SLIDES).
##
## - `arena` (the block south of the plaza): an oval bowl on a stepped podium, a glass curtain
##   ring that LEANS OUT as it rises, a banded metal drum overhanging it, a shallow domed roof you
##   can land on, the marquee on the plaza corner (two pylons, a double-sided LED screen, a ticker
##   and the lit name), LED screens on the drum, palms, masts and a crowd on the plaza.
## - `live_plaza` (north of the arena, across the street): an open plaza between a theatre box
##   with a glass lobby and a giant LED column, a cinema block whose whole upper face is LED
##   screens, and a strip of restaurants with neon, lit masts, planting and a crowd.
## - `live_hotel` (the next block east, nearest the core): a slim 200 m slab of dark blue glass on
##   a podium, with a lit crown of fins.
## - `convention_center` (south of the arena): a long low white panelled hall with a clerestory,
##   skylight monitors on the roof, and two glass pavilions whose green glass walls tilt outward
##   under an exposed white space frame, linked by a glass concourse, on an entrance plaza.
##
## Each takes the whole block its anchor falls in (Landmarks.site_rect) and fits itself to it,
## so it never sits on a road whatever the seed; the numbers below are the default seed's fit.
## Everything is LandmarkGeo geometry (one mesh per building, a surface per material) plus a
## MultiMeshBatch for repeats, so a building is a handful of draw calls.
##
## Collision: the arena's podium, walls and roof are one concave shape (you can land on the roof
## and walk the steps); every box is a box shape; screens and trim are not solid.

const ARENA_NAME := "RANDO ARENA"
const PLAZA_NAME := "STARLIGHT PLAZA"
const THEATER_NAME := "STARLIGHT THEATER"
const HOTEL_NAME := "HOTEL ALTAIR"
const CONVENTION_NAME := "CONVENTION CENTER"

# --- Arena ----------------------------------------------------------------------------------
## Oval radii at the foot of the glass (metres), before fitting to the block.
const ARENA_RADII := Vector2(36.0, 37.0)
## The podium: three steps of STEP_RISE, each STEP_TREAD deep; the outermost reaches PODIUM_OUT
## beyond the foot of the glass.
const STEP_RISE := 0.4
const STEP_TREAD := 0.8
const PODIUM_OUT := 4.0
## Top of the glass ring, top of the drum, rise of the roof dome (metres above the plaza).
const GLASS_TOP := 17.0
const DRUM_TOP := 30.0
const ROOF_RISE := 4.5
## How far the glass leans out between its foot and its head, and how far the drum overhangs it.
const GLASS_LEAN := 3.0
const DRUM_OVERHANG := 1.2
## The glass wraps the plaza sides (west through north to a little past east); the service side
## (south and south-west) is solid concrete with fins. Angles from +X toward +Z (south).
const GLASS_FROM := PI
const GLASS_TO := TAU + 0.35

# --- Hotel ----------------------------------------------------------------------------------
const HOTEL_HEIGHT := 196.0
const HOTEL_PODIUM := 14.0

const WHITE_PANEL := Color(0.90, 0.90, 0.88)
const STEEL_DARK := Color(0.20, 0.21, 0.23)


static func build(id: String, anchor: Vector2, parent: Node3D, statics: StaticBody3D, plan: CityPlan, detailed: bool) -> void:
	var site := Landmarks.site_rect(plan, anchor)
	var y0 := ground(plan, site)
	match id:
		"arena":
			_arena(site, y0, parent, statics, detailed)
		"live_plaza":
			_live_plaza(site, y0, parent, statics, detailed)
		"live_hotel":
			_live_hotel(site, y0, parent, statics, detailed)
		"convention_center":
			_convention(site, y0, parent, statics, detailed)


## The pad the site is laid on: the pavement height at its highest corner.
static func ground(plan: CityPlan, site: Rect2) -> float:
	var h := 0.0
	if plan and plan.macro:
		for c: Vector2 in [site.position, Vector2(site.end.x, site.position.y), site.end, Vector2(site.position.x, site.end.y), site.get_center()]:
			h = maxf(h, plan.macro.relief_at(c))
	return CityChunk.SIDEWALK_TOP + h


## Crowds for the chunk to spawn: [[rect, sidewalk, count], ...] (see Landmarks.crowds()).
static func crowds(id: String, anchor: Vector2, plan: CityPlan) -> Array:
	var s := Landmarks.site_rect(plan, anchor)
	match id:
		"arena":
			var c := _arena_centre(s)
			var r := _arena_radii(s)
			var apron := r + Vector2(PODIUM_OUT, PODIUM_OUT)
			# The corner plaza under the marquee and the strip along the front, both clear of the
			# podium steps (the crowd walks straight lines between points on its ring).
			var corner := Rect2(Vector2(c.x + apron.x * 0.72, s.position.y + 1.5), Vector2(s.end.x - 1.5 - (c.x + apron.x * 0.72), c.y - apron.y * 0.72 - s.position.y - 1.5))
			var front := Rect2(Vector2(c.x - apron.x * 0.6, s.position.y + 1.0), Vector2(apron.x * 1.2, maxf(2.0, c.y - apron.y - s.position.y - 1.5)))
			return [[corner, minf(corner.size.x, corner.size.y) * 0.5, 26], [front, front.size.y * 0.5, 14]]
		"live_plaza":
			# Clear of the planters down both edges of the plaza.
			var p := _plaza_open(s)
			var r := Rect2(p.position + Vector2(5.5, 3.0), p.size - Vector2(11.0, 5.0))
			return [[r, minf(r.size.x, r.size.y) * 0.5, 46]]
		"convention_center":
			var f := Rect2(s.position + Vector2(s.size.x * 0.28, 3.5), Vector2(s.size.x * 0.44, _convention_front(s) - 5.5))
			return [[f, minf(f.size.x, f.size.y) * 0.5, 18]]
	return []


# ============================================================================================
# The arena
# ============================================================================================

static func _arena_radii(s: Rect2) -> Vector2:
	return Vector2(clampf(minf(ARENA_RADII.x, s.size.x * 0.5 - 10.0), 20.0, ARENA_RADII.x),
		clampf(minf(ARENA_RADII.y, s.size.y * 0.5 - 9.0), 20.0, ARENA_RADII.y))


## The bowl sits toward the back (south-west) corner of its block, leaving the plaza and the
## marquee on the corner that faces the entertainment plaza and the towers.
static func _arena_centre(s: Rect2) -> Vector2:
	var r := _arena_radii(s)
	var reach := r + Vector2(PODIUM_OUT, PODIUM_OUT)
	var c := s.get_center() + Vector2(-5.0, 4.0)
	c.x = clampf(c.x, s.position.x + reach.x, s.end.x - reach.x)
	c.y = clampf(c.y, s.position.y + reach.y, s.end.y - reach.y)
	return c


static func _arena(s: Rect2, y0: float, parent: Node3D, statics: StaticBody3D, detailed: bool) -> void:
	var g := LandmarkGeo.new()
	var batch := MultiMeshBatch.new()
	var segs := 96 if detailed else 32
	var c := _arena_centre(s)
	var r0 := _arena_radii(s)
	var r_top := r0 + Vector2(GLASS_LEAN, GLASS_LEAN)
	var r_drum := r_top + Vector2(DRUM_OVERHANG, DRUM_OVERHANG)
	var concrete := LandmarkMats.facade("arena_concrete", "concrete", 4.0,
		{"tint": Color(0.80, 0.79, 0.76), "roughness": 0.85, "joint_spacing": Vector2(2.4, 3.0), "joint_width": 0.03, "joint_dark": 0.3, "grime": 0.3, "base_y": y0,
		"flood_strength": 0.5, "flood_base_y": y0, "flood_reach": 8.0, "flood_spacing": 7.2})
	var stone := LandmarkMats.facade("arena_steps", "paving", 3.0,
		{"tint": Color(0.70, 0.69, 0.67), "roughness": 0.8, "joint_spacing": Vector2(1.2, 0.0), "joint_dark": 0.2})
	var glass := LandmarkMats.glass("arena", {"glass_tint": Color(0.22, 0.30, 0.34), "frame_color": Color(0.70, 0.72, 0.75),
		"grid": Vector2(1.6, 2.8), "frame_width": 0.08, "room_depth": 9.0, "storey": 5.4, "floor_y": y0 + STEP_RISE * 3.0, "interior_night": 1.7})
	var drum := LandmarkMats.facade("arena_drum", "", 1.0,
		{"tint": Color(0.70, 0.72, 0.75), "roughness": 0.34, "metallic": 0.6, "band_spacing": 0.9, "band_reveal": 0.09, "band_tone": 0.05,
		"joint_spacing": Vector2(4.8, 0.0), "joint_width": 0.03, "joint_dark": 0.25,
		"flood_strength": 0.55, "flood_base_y": y0 + GLASS_TOP, "flood_reach": 9.0, "flood_floor": 0.3, "flood_spacing": 9.6, "flood_color": Color(0.85, 0.9, 1.0)})
	var roof := LandmarkMats.facade("arena_roof", "", 1.0,
		{"tint": Color(0.84, 0.85, 0.86), "roughness": 0.62, "joint_spacing": Vector2(5.0, 5.0), "joint_width": 0.05, "joint_dark": 0.18})
	var metal := LandmarkMats.plain("arena_metal", Color(0.62, 0.64, 0.67), 0.35, 0.7)
	g.use("stone", stone)
	g.use("concrete", concrete)
	g.use("glass", glass)
	g.use("drum", drum)
	g.use("roof", roof)
	g.use("metal", metal)

	# The podium: three steps up all round, then the apron the glass stands on.
	var yb := y0
	for k in 3:
		var ro := r0 + Vector2.ONE * (PODIUM_OUT - float(k) * STEP_TREAD)
		var ri := ro - Vector2.ONE * STEP_TREAD
		g.band("stone", c, ro, ro, yb + float(k) * STEP_RISE - 0.02, yb + float(k + 1) * STEP_RISE, 0.0, TAU, segs, Color.WHITE, statics != null)
		g.ring_flat("stone", c, ri if k < 2 else r0 - Vector2.ONE * 0.5, ro, yb + float(k + 1) * STEP_RISE, 0.0, TAU, segs, Color.WHITE, statics != null)
	var ya := yb + STEP_RISE * 3.0
	# The glass ring on the plaza sides, leaning out, and the solid service side.
	var glass_segs := int(segs * (GLASS_TO - GLASS_FROM) / TAU)
	g.band("glass", c, r0, r_top, ya, y0 + GLASS_TOP, GLASS_FROM, GLASS_TO, glass_segs, Color.WHITE, statics != null)
	g.band("concrete", c, r0, r_top, ya, y0 + GLASS_TOP, GLASS_TO - TAU, GLASS_FROM, segs - glass_segs, Color.WHITE, statics != null)
	# The soffit under the drum's overhang, and the drum itself with a proud lip at its top.
	g.ring_flat("metal", c, r_top - Vector2.ONE * 0.2, r_drum, y0 + GLASS_TOP, 0.0, TAU, segs, Color(0.8, 0.8, 0.82), false, true)
	g.band("drum", c, r_drum, r_drum, y0 + GLASS_TOP, y0 + DRUM_TOP, 0.0, TAU, segs, Color.WHITE, statics != null)
	var r_lip := r_drum + Vector2.ONE * 0.25
	g.band("metal", c, r_lip, r_lip, y0 + DRUM_TOP - 0.2, y0 + DRUM_TOP + 0.9, 0.0, TAU, segs, Color(0.9, 0.9, 0.92), statics != null)
	g.ring_flat("metal", c, r_drum - Vector2.ONE * 0.6, r_lip, y0 + DRUM_TOP + 0.9, 0.0, TAU, segs, Color(0.9, 0.9, 0.92), statics != null)
	g.ring_flat("metal", c, r_drum, r_lip, y0 + DRUM_TOP - 0.2, 0.0, TAU, segs, Color(0.8, 0.8, 0.82), false, true)
	# The roof: a shallow dome from inside the lip. Walkable: the player lands on it.
	g.dome("roof", c, r_drum - Vector2.ONE * 0.6, y0 + DRUM_TOP + 0.6, ROOF_RISE, segs, 8 if detailed else 3, Color.WHITE, statics != null)

	if detailed:
		_arena_detail(g, batch, parent, c, r0, r_top, r_drum, y0, ya, s, statics)
		# The name on the drum, on the side facing the freeway and the far side of the city.
		_arc_letters(batch, "arena_ltr", ARENA_NAME, c, r_drum + Vector2.ONE * 0.35, y0 + (GLASS_TOP + DRUM_TOP) * 0.5 + 1.0, 4.2, PI * 0.75)
	# LED screens on the drum: the big one over the main doors faces the corner plaza.
	var screens := [[-PI * 0.25, Vector2(20.0, 9.0), 150.0], [-PI * 0.62, Vector2(13.0, 7.0), 110.0], [0.12, Vector2(13.0, 7.0), 110.0]]
	if not detailed:
		screens = [screens[0]]
	for i in screens.size():
		var t: float = screens[i][0]
		var size: Vector2 = screens[i][1]
		var p := LandmarkGeo.ell(c, r_drum + Vector2.ONE * 0.5, t)
		var n := LandmarkGeo.ell_normal(r_drum, t)
		var at := Vector3(p.x, y0 + (GLASS_TOP + DRUM_TOP) * 0.5 - 0.5, p.y)
		# A dark frame round the screen, standing off the drum.
		var face_yaw := atan2(-n.x, -n.y)
		g.box("metal", at - Vector3(n.x, 0.0, n.y) * 0.25, Vector3(size.x + 0.8, size.y + 0.8, 0.5), Color(0.25, 0.26, 0.28), LandmarkGeo.yaw(face_yaw), 0.08 if detailed else 0.0)
		LedScreen.add(g, "led_drum_%d" % i, at + Vector3(n.x, 0.0, n.y) * 0.02, size, face_yaw, screens[i][2], float(i) * 1.7 + 0.3)
	_marquee(g, batch, s, y0, statics, detailed)
	g.commit(parent, "Arena")
	g.commit_collision(statics)
	batch.build(parent)
	_occluder(parent, [[Vector3(c.x, y0 + DRUM_TOP * 0.5, c.y), Vector3(r0.x * 1.35, DRUM_TOP - 2.0, r0.y * 1.35)]])


## The arena's near detail: glass fins, a transom, entrance canopies, doors, rooftop plant,
## the plaza paving, palms, masts and their lights.
static func _arena_detail(g: LandmarkGeo, batch: MultiMeshBatch, parent: Node3D, c: Vector2, r0: Vector2, r_top: Vector2, r_drum: Vector2,
		y0: float, ya: float, s: Rect2, statics: StaticBody3D) -> void:
	# Mullion fins leaning with the glass, every few metres round the plaza sides.
	var arc := LandmarkGeo.ell_arc(r0, GLASS_FROM, GLASS_TO)
	var fins := int(arc / 4.8)
	for i in fins + 1:
		var t := lerpf(GLASS_FROM, GLASS_TO, float(i) / float(fins))
		var pb := LandmarkGeo.ell(c, r0, t)
		var pt := LandmarkGeo.ell(c, r_top, t)
		var n := LandmarkGeo.ell_normal(r0, t)
		var up := (Vector3(pt.x, y0 + GLASS_TOP, pt.y) - Vector3(pb.x, ya, pb.y))
		var length := up.length()
		var y_axis := up / length
		var z_axis := Vector3(n.x, 0.0, n.y)
		var x_axis := y_axis.cross(z_axis).normalized()
		z_axis = x_axis.cross(y_axis).normalized()
		var mid := (Vector3(pb.x, ya, pb.y) + Vector3(pt.x, y0 + GLASS_TOP, pt.y)) * 0.5 + z_axis * 0.35
		g.box("metal", mid, Vector3(0.22, length, 0.7), Color(0.78, 0.8, 0.83), Basis(x_axis, y_axis, z_axis), 0.05)
	# A transom band round the glass at the concourse floor.
	var rt := r0.lerp(r_top, (8.8 - (ya - y0)) / (GLASS_TOP - (ya - y0))) + Vector2.ONE * 0.12
	g.band("metal", c, rt, rt, y0 + 8.5, y0 + 9.1, GLASS_FROM, GLASS_TO, 80, Color(0.72, 0.74, 0.77))
	# Entrance canopies at the main doors (north-east, north, east): a thick slab cantilevered
	# off the glass, lit underneath, and the glass doors under it.
	for t: float in [-PI * 0.25, -PI * 0.55, 0.02]:
		var p := LandmarkGeo.ell(c, r0, t)
		var n := LandmarkGeo.ell_normal(r0, t)
		var yaw := atan2(-n.x, -n.y)
		var wide := 22.0 if t == -PI * 0.25 else 13.0
		var out := Vector3(n.x, 0.0, n.y)
		g.box("metal", Vector3(p.x, y0 + 7.2, p.y) + out * 3.4, Vector3(wide, 0.9, 7.0), Color(0.86, 0.87, 0.89), LandmarkGeo.yaw(yaw), 0.12)
		LandmarkGeo.shape_box(statics, Vector3(p.x, y0 + 7.2, p.y) + out * 3.4, Vector3(wide, 0.9, 7.0), LandmarkGeo.yaw(yaw))
		batch.add("arena_pool", PropFactory.light_pool(Color(1.0, 0.9, 0.75), 1.3), Transform3D(Basis(Vector3.RIGHT, -PI * 0.5).scaled(Vector3(wide * 0.9, 1.0, 7.0)).rotated(Vector3.UP, yaw), Vector3(p.x, ya + 0.04, p.y) + out * 3.0))
		# Doors: dark glass panels with bright push bars, standing just proud of the curtain.
		g.box("metal", Vector3(p.x, ya + 1.5, p.y) + out * 0.25, Vector3(wide * 0.7, 3.0, 0.12), Color(0.12, 0.13, 0.15), LandmarkGeo.yaw(yaw))
	# Rooftop plant: a few big air handlers and a walkway round the crown of the dome.
	var rng := RandomNumberGenerator.new()
	rng.seed = 91021
	for i in 7:
		var t := TAU * float(i) / 7.0 + 0.3
		var p := LandmarkGeo.ell(c, r_drum * 0.55, t)
		var rho := 0.55
		var yr := y0 + DRUM_TOP + 0.6 + ROOF_RISE * (1.0 - rho * rho)
		g.box("metal", Vector3(p.x, yr + 0.9, p.y), Vector3(rng.randf_range(3.0, 5.0), 1.9, rng.randf_range(2.2, 3.0)), Color(0.66, 0.68, 0.70), LandmarkGeo.yaw(-t), 0.08)
	# Plaza paving over the whole site, just proud of the block's pavement.
	g.use("paving", LandmarkMats.paving("pavers", 2.5, Color(0.92, 0.90, 0.87), 4411, 3.0, 0.25))
	g.cap("paving", LandmarkGeo.ccw(_rect_poly(s)), y0 + 0.03)
	# Palms down the avenue side, masts on the corner plaza.
	for i in 6:
		var z := lerpf(s.position.y + 20.0, s.end.y - 4.0, float(i) / 5.0)
		var v := i % PropFactory.PALM_VARIANTS
		batch.add("palm_%d" % v, PropFactory.palm(v), Transform3D(Basis(Vector3.UP, float(i) * 1.3), Vector3(s.end.x - 2.2, y0, z)), Color(1.0, 1.0, 1.0))
	var mast := PropFactory.cylinder("lm_mast", 0.2, 1.0, STEEL_DARK, 0.13, 10)
	for q: Vector2 in [Vector2(s.end.x - 6.0, s.position.y + 6.0), Vector2(s.end.x - 20.0, s.position.y + 5.0), Vector2(s.end.x - 5.0, s.position.y + 20.0)]:
		_mast(batch, Vector3(q.x, y0, q.y), 12.0, mast)
		_add_light(parent, Vector3(q.x, y0 + 11.0, q.y))


## The arena's marquee on its plaza corner: two tall pylons carrying a double-sided LED screen,
## a ticker under it, and the name in lit letters on a band above.
static func _marquee(g: LandmarkGeo, batch: MultiMeshBatch, s: Rect2, y0: float, statics: StaticBody3D, detailed: bool) -> void:
	# Right on the corner, facing the crossing, its pylons at the plaza's two street edges.
	var at := Vector2(s.end.x - 7.0, s.position.y + 7.0)
	var face_yaw := -PI * 0.25 # faces north-east, toward the corner
	var fwd := Vector3(-sin(face_yaw), 0.0, -cos(face_yaw))
	var right := Vector3(-cos(face_yaw), 0.0, sin(face_yaw))
	var base := Vector3(at.x, y0, at.y)
	var width := 17.0
	for side: float in [-1.0, 1.0]:
		var p := base + right * side * (width * 0.5 + 0.9)
		g.box("metal", p + Vector3(0.0, 12.5, 0.0), Vector3(1.4, 25.0, 1.4), Color(0.22, 0.23, 0.25), LandmarkGeo.yaw(face_yaw), 0.1 if detailed else 0.0)
		g.box("concrete", p + Vector3(0.0, 0.6, 0.0), Vector3(2.4, 1.2, 2.4), Color.WHITE, LandmarkGeo.yaw(face_yaw), 0.06 if detailed else 0.0)
		LandmarkGeo.shape_box(statics, p + Vector3(0.0, 12.5, 0.0), Vector3(1.4, 25.0, 1.4), LandmarkGeo.yaw(face_yaw))
	# The screen cabinet, the ticker and the name band.
	g.box("metal", base + Vector3(0.0, 15.5, 0.0), Vector3(width + 0.6, 8.6, 1.3), Color(0.16, 0.17, 0.19), LandmarkGeo.yaw(face_yaw), 0.08 if detailed else 0.0)
	g.box("metal", base + Vector3(0.0, 10.2, 0.0), Vector3(width, 1.8, 0.9), Color(0.16, 0.17, 0.19), LandmarkGeo.yaw(face_yaw))
	g.box("metal", base + Vector3(0.0, 21.4, 0.0), Vector3(width + 1.6, 2.8, 1.5), Color(0.86, 0.87, 0.89), LandmarkGeo.yaw(face_yaw), 0.1 if detailed else 0.0)
	LandmarkGeo.shape_box(statics, base + Vector3(0.0, 15.5, 0.0), Vector3(width + 0.6, 8.6, 1.3), LandmarkGeo.yaw(face_yaw))
	LandmarkGeo.shape_box(statics, base + Vector3(0.0, 21.4, 0.0), Vector3(width + 1.6, 2.8, 1.5), LandmarkGeo.yaw(face_yaw))
	for side: float in [1.0, -1.0]:
		var yaw := face_yaw if side > 0.0 else face_yaw + PI
		var off := fwd * side * 0.66
		LedScreen.add(g, "led_marquee", base + Vector3(0.0, 15.5, 0.0) + off, Vector2(width, 8.0), yaw, 170.0, 4.1)
		LedScreen.add(g, "led_ticker", base + Vector3(0.0, 10.2, 0.0) + fwd * side * 0.46, Vector2(width - 0.4, 1.5), yaw, 200.0, 2.7)
		batch.add("arena_marquee_name", Signage.text_mesh(ARENA_NAME, 1.9, Signage.Letters.LIT),
			Transform3D(_face(yaw, 1.0), base + Vector3(0.0, 21.4, 0.0) + fwd * side * 0.8), Color(1.0, 0.95, 0.88))
	batch.set_no_shadow("arena_marquee_name")


## Letters of `text` round an ellipse (the arena drum), each turned to the curve, centred on
## angle `t_mid`. One MultiMesh per distinct letter, lit channel letters (Signage).
static func _arc_letters(batch: MultiMeshBatch, key: String, text: String, c: Vector2, r: Vector2, y: float, height: float, t_mid: float) -> void:
	var advance := height * 0.78
	var total := advance * float(text.length())
	var arc_r := (r.x + r.y) * 0.5
	var t := t_mid - total / arc_r * 0.5
	for ch in text:
		t += advance / arc_r * 0.5
		if ch != " ":
			var p := LandmarkGeo.ell(c, r, t)
			var n := LandmarkGeo.ell_normal(r, t)
			var yaw := atan2(-n.x, -n.y)
			batch.add("%s_%s" % [key, ch], Signage.text_mesh(ch, height, Signage.Letters.LIT),
				Transform3D(_face(yaw, 1.0), Vector3(p.x, y, p.y)), Color(1.0, 0.96, 0.9))
			batch.set_no_shadow("%s_%s" % [key, ch])
		t += advance / arc_r * 0.5


# ============================================================================================
# The entertainment plaza
# ============================================================================================

## Where the open plaza is on the plaza block: between the theatre (west) and the restaurant
## strip (east), south of the cinema block, open to the street facing the arena.
static func _plaza_open(s: Rect2) -> Rect2:
	var theater_w := clampf(s.size.x * 0.33, 18.0, 32.0)
	var north_d := clampf(s.size.y * 0.28, 10.0, 17.0)
	var east_w := clampf(s.size.x * 0.2, 10.0, 18.0)
	return Rect2(Vector2(s.position.x + theater_w, s.position.y + north_d), Vector2(s.size.x - theater_w - east_w, s.size.y - north_d))


static func _live_plaza(s: Rect2, y0: float, parent: Node3D, statics: StaticBody3D, detailed: bool) -> void:
	var g := LandmarkGeo.new()
	var batch := MultiMeshBatch.new()
	var p := _plaza_open(s)
	var dark_panel := LandmarkMats.facade("live_dark", "metal_painted", 3.0,
		{"tint": Color(0.30, 0.31, 0.34), "roughness": 0.45, "metallic": 0.5, "joint_spacing": Vector2(1.5, 3.0), "joint_width": 0.03, "joint_dark": 0.35, "grime": 0.1, "base_y": y0,
		"flood_strength": 0.5, "flood_base_y": y0, "flood_reach": 10.0, "flood_color": Color(0.8, 0.7, 1.0), "flood_spacing": 5.0})
	var cream := LandmarkMats.facade("live_stucco", "plaster_white", 3.5,
		{"tint": Color(0.86, 0.83, 0.78), "roughness": 0.85, "grime": 0.3, "base_y": y0, "win_pitch": Vector2(3.2, 4.0), "win_size": Vector2(0.6, 0.55),
		"win_band": Vector2(y0 + 5.0, y0 + 30.0), "lit_ratio": 0.5})
	var lobby := LandmarkMats.glass("live_lobby", {"glass_tint": Color(0.18, 0.2, 0.24), "frame_color": Color(0.2, 0.21, 0.23),
		"grid": Vector2(2.0, 3.0), "frame_width": 0.1, "room_depth": 12.0, "storey": 6.0, "floor_y": y0, "interior_day": 0.18, "interior_night": 2.0,
		"interior_color": Color(1.0, 0.78, 0.55)})
	var shopfront := LandmarkMats.glass("live_shop", {"glass_tint": Color(0.2, 0.22, 0.24), "frame_color": Color(0.12, 0.12, 0.13),
		"grid": Vector2(1.8, 4.2), "frame_width": 0.09, "room_depth": 7.0, "storey": 4.2, "floor_y": y0, "interior_day": 0.25, "interior_night": 2.2,
		"interior_color": Color(1.0, 0.72, 0.45)})
	var metal := LandmarkMats.plain("live_metal", Color(0.5, 0.5, 0.52), 0.4, 0.6)
	g.use("dark", dark_panel)
	g.use("cream", cream)
	g.use("lobby", lobby)
	g.use("shop", shopfront)
	g.use("metal", metal)

	# The theatre: a big dark box with a full-height glass lobby on the plaza side, a canopy and
	# a giant LED column on its plaza corner.
	var th := Rect2(s.position, Vector2(p.position.x - s.position.x - 1.0, s.size.y - 3.0))
	var th_h := 24.0
	g.box("dark", Vector3(th.get_center().x - 2.0, y0 + th_h * 0.5, th.get_center().y), Vector3(th.size.x - 4.0, th_h, th.size.y), Color.WHITE, Basis(), 0.25 if detailed else 0.0, false, 0.0)
	LandmarkGeo.shape_box(statics, Vector3(th.get_center().x - 2.0, y0 + th_h * 0.5, th.get_center().y), Vector3(th.size.x - 4.0, th_h, th.size.y))
	var lobby_x := th.end.x - 4.0
	var lobby_z0 := th.position.y + 4.0
	var lobby_z1 := th.end.y - 2.0
	g.wall("lobby", Vector2(lobby_x + 4.0, lobby_z1), Vector2(lobby_x + 4.0, lobby_z0), y0, y0 + 13.0)
	# The lobby's two ends, so the glass box is closed.
	for lz: float in [lobby_z0 - 0.4, lobby_z1 + 0.4]:
		g.box("dark", Vector3(lobby_x + 2.0, y0 + 6.5, lz), Vector3(4.4, 13.0, 0.8), Color.WHITE)
	g.box("dark", Vector3(lobby_x + 2.0, y0 + 13.6, (lobby_z0 + lobby_z1) * 0.5), Vector3(4.8, 1.2, lobby_z1 - lobby_z0 + 0.8), Color.WHITE, Basis(), 0.1 if detailed else 0.0)
	LandmarkGeo.shape_box(statics, Vector3(lobby_x + 2.0, y0 + 6.5, (lobby_z0 + lobby_z1) * 0.5), Vector3(4.0, 13.0, lobby_z1 - lobby_z0))
	# The LED column on the plaza corner of the theatre, and the name on the parapet.
	var col_at := Vector3(th.end.x + 0.2, y0 + 15.0, th.end.y - 7.0)
	LedScreen.add(g, "led_theater", col_at + Vector3(0.5, 0.0, 0.0), Vector2(8.0, 18.0), -PI * 0.5, 64.0, 5.3)
	g.box("metal", col_at, Vector3(0.9, 19.0, 9.0), Color(0.15, 0.15, 0.16), Basis(), 0.06 if detailed else 0.0)
	batch.add("live_theater_name", Signage.text_mesh(THEATER_NAME, 1.6, Signage.Letters.LIT),
		Transform3D(_face(-PI * 0.5, 1.0), Vector3(lobby_x + 4.5, y0 + 16.2, (lobby_z0 + lobby_z1) * 0.5)), Color(1.0, 0.86, 0.6))
	batch.set_no_shadow("live_theater_name")

	# The cinema block along the north side: restaurants at the foot, the plaza's wall of screens
	# above them.
	var nb := Rect2(Vector2(p.position.x, s.position.y), Vector2(s.end.x - p.position.x, p.position.y - s.position.y))
	var nb_h := 21.0
	g.box("dark", Vector3(nb.get_center().x, y0 + nb_h * 0.5, nb.get_center().y), Vector3(nb.size.x, nb_h, nb.size.y), Color(0.9, 0.9, 0.95), Basis(), 0.2 if detailed else 0.0)
	LandmarkGeo.shape_box(statics, Vector3(nb.get_center().x, y0 + nb_h * 0.5, nb.get_center().y), Vector3(nb.size.x, nb_h, nb.size.y))
	var face_z := nb.end.y + 0.02
	g.wall("shop", Vector2(nb.position.x + 1.0, face_z), Vector2(nb.end.x - 1.0, face_z), y0, y0 + 5.2)
	# The screens: three across the upper face, facing the plaza (south).
	var widths := [nb.size.x * 0.28, nb.size.x * 0.36, nb.size.x * 0.28]
	var x := nb.position.x + nb.size.x * 0.02
	for i in 3:
		var w: float = widths[i]
		var hgt := 11.0 if i == 1 else 8.5
		var at := Vector3(x + w * 0.5, y0 + 6.4 + hgt * 0.5 + (1.0 if i == 1 else 0.6), face_z + 0.3)
		g.box("metal", at - Vector3(0.0, 0.0, 0.2), Vector3(w + 0.5, hgt + 0.5, 0.4), Color(0.15, 0.15, 0.16))
		LedScreen.add(g, "led_wall_%d" % i, at + Vector3(0.0, 0.0, 0.02), Vector2(w - 0.4, hgt), PI, 120.0 if i == 1 else 96.0, 1.1 + float(i) * 2.3)
		x += w + nb.size.x * 0.02
	# A canopy over the restaurants, lit underneath.
	g.box("metal", Vector3(nb.get_center().x, y0 + 5.6, face_z + 2.2), Vector3(nb.size.x - 2.0, 0.35, 4.4), Color(0.24, 0.25, 0.27))

	# The restaurant strip on the east side: two storeys of stucco, shopfronts on the plaza.
	var eb := Rect2(Vector2(p.end.x, p.position.y), Vector2(s.end.x - p.end.x, s.end.y - p.position.y - 2.0))
	g.box("cream", Vector3(eb.get_center().x, y0 + 5.5, eb.get_center().y), Vector3(eb.size.x, 11.0, eb.size.y), Color.WHITE, Basis(), 0.12 if detailed else 0.0, false, 3.2)
	LandmarkGeo.shape_box(statics, Vector3(eb.get_center().x, y0 + 5.5, eb.get_center().y), Vector3(eb.size.x, 11.0, eb.size.y))
	g.wall("shop", Vector2(eb.position.x - 0.02, eb.position.y + 1.0), Vector2(eb.position.x - 0.02, eb.end.y - 1.0), y0, y0 + 4.6)

	if detailed:
		_plaza_detail(g, batch, parent, p, nb, eb, y0, statics)
	g.commit(parent, "StarlightPlaza")
	batch.build(parent)
	_occluder(parent, [[Vector3(th.get_center().x - 2.0, y0 + th_h * 0.5, th.get_center().y), Vector3(th.size.x - 4.0, th_h, th.size.y)],
		[Vector3(nb.get_center().x, y0 + nb_h * 0.5, nb.get_center().y), Vector3(nb.size.x, nb_h, nb.size.y)]])


## The plaza's near detail: granite paving with inlaid bands, neon over the restaurants, lit
## masts with real lights, planters with trees, café tables.
static func _plaza_detail(g: LandmarkGeo, batch: MultiMeshBatch, parent: Node3D, p: Rect2, nb: Rect2, eb: Rect2, y0: float, statics: StaticBody3D) -> void:
	g.use("paving", LandmarkMats.paving("paving", 2.2, Color(0.62, 0.60, 0.60), 5521, 2.4, 0.2))
	g.cap("paving", LandmarkGeo.ccw(_rect_poly(Rect2(p.position, p.size + Vector2(0.0, 0.0)))), y0 + 0.03)
	# Bright inlaid bands across the plaza, the lines the eye runs along to the screens.
	g.use("inlay", LandmarkMats.plain("live_inlay", Color(0.82, 0.8, 0.76), 0.35, 0.3))
	for i in 5:
		var z := p.position.y + 4.0 + float(i) * (p.size.y - 8.0) / 4.0
		g.box("inlay", Vector3(p.get_center().x, y0 + 0.05, z), Vector3(p.size.x - 2.0, 0.04, 0.35))
	# Neon over each restaurant along the cinema block and on the east strip.
	var neon := Signage.NEON
	var units := maxi(2, int(nb.size.x / 11.0))
	for i in units:
		var cx := nb.position.x + (float(i) + 0.5) * nb.size.x / float(units)
		var col: Color = neon[(i * 3 + 1) % neon.size()]
		batch.add("live_tube", Signage.tube_mesh(), Transform3D(_face(PI, 1.0) * Basis.from_scale(Vector3(6.0, 0.18, 0.12)), Vector3(cx, y0 + 4.9, nb.end.y + 0.2)), col)
		batch.add("live_word_%d" % (i % 4), Signage.text_mesh(["TACOS", "RAMEN", "BURGERS", "COCKTAILS"][i % 4], 0.7, Signage.Letters.TUBE),
			Transform3D(_face(PI, 1.0), Vector3(cx, y0 + 4.1, nb.end.y + 0.25)), col)
	for i in maxi(2, int(eb.size.y / 12.0)):
		var cz := eb.position.y + (float(i) + 0.5) * eb.size.y / float(maxi(2, int(eb.size.y / 12.0)))
		var col: Color = neon[(i * 5 + 2) % neon.size()]
		batch.add("live_tube", Signage.tube_mesh(), Transform3D(_face(PI * 0.5, 1.0) * Basis.from_scale(Vector3(7.0, 0.2, 0.12)), Vector3(eb.position.x - 0.25, y0 + 5.3, cz)), col)
		batch.add("live_word_%d" % ((i + 2) % 4), Signage.text_mesh(["TACOS", "RAMEN", "BURGERS", "COCKTAILS"][(i + 2) % 4], 0.8, Signage.Letters.TUBE),
			Transform3D(_face(PI * 0.5, 1.0), Vector3(eb.position.x - 0.3, y0 + 4.3, cz)), col)
	for k in ["live_tube", "live_word_0", "live_word_1", "live_word_2", "live_word_3"]:
		batch.set_no_shadow(k)
	# Lit masts, with real lights on two of them.
	var mast := PropFactory.cylinder("lm_mast", 0.2, 1.0, STEEL_DARK, 0.13, 10)
	var spots := [Vector2(p.position.x + 5.0, p.position.y + 6.0), Vector2(p.end.x - 5.0, p.position.y + 6.0),
		Vector2(p.position.x + 5.0, p.end.y - 5.0), Vector2(p.end.x - 5.0, p.end.y - 5.0)]
	for i in spots.size():
		var q: Vector2 = spots[i]
		_mast(batch, Vector3(q.x, y0, q.y), 13.0, mast)
		if i % 2 == 0:
			_add_light(parent, Vector3(q.x, y0 + 12.0, q.y))
	# Planters with trees down the plaza's edges, and café tables in front of the restaurants.
	var rng := RandomNumberGenerator.new()
	rng.seed = 7741
	for i in 3:
		var z := p.position.y + 10.0 + float(i) * (p.size.y - 16.0) / 2.0
		for side: float in [0.0, 1.0]:
			var x := lerpf(p.position.x + 3.0, p.end.x - 3.0, side)
			g.box("inlay", Vector3(x, y0 + 0.35, z), Vector3(3.2, 0.7, 3.2), Color(0.62, 0.6, 0.58), Basis(), 0.06)
			LandmarkGeo.shape_box(statics, Vector3(x, y0 + 0.35, z), Vector3(3.2, 0.7, 3.2))
			var v := 1 + (i + int(side)) % 3
			var sc := PropFactory.city_tree_scale(v, rng.randf_range(6.5, 8.5))
			batch.add("tree_%d" % v, PropFactory.model_tree(v), Transform3D(Basis(Vector3.UP, rng.randf() * TAU).scaled(Vector3(sc, sc, sc)), Vector3(x, y0 + 0.7, z)),
				Color(1.0, 1.0, 1.0), Color(rng.randf(), rng.randf(), rng.randf(), rng.randf_range(0.4, 1.0)))
	var cafe := PropFactory.model_cafe_set()
	for i in maxi(2, int(nb.size.x / 9.0)):
		var cx := nb.position.x + 4.0 + float(i) * 8.5
		if cx > nb.end.x - 3.0:
			break
		batch.add("live_cafe", cafe, Transform3D(Basis(Vector3.UP, float(i) * 0.9), Vector3(cx, y0 + 0.04, nb.end.y + 6.0)))


# ============================================================================================
# The hotel tower
# ============================================================================================

static func _live_hotel(s: Rect2, y0: float, parent: Node3D, statics: StaticBody3D, detailed: bool) -> void:
	var g := LandmarkGeo.new()
	var batch := MultiMeshBatch.new()
	var c := s.get_center()
	# The podium: glass-fronted lobby floors and ballroom panels, the porte-cochère on the east.
	var pod := Vector3(minf(s.size.x - 6.0, 60.0), HOTEL_PODIUM, minf(s.size.y - 6.0, 44.0))
	Landmarks._facade_box(parent, statics, pod, Vector3(c.x, y0 + pod.y * 0.5, c.y), Color(0.34, 0.37, 0.42), Building.Finish.GLASS, Building.WindowStyle.RIBBON, 6.0)
	# The slab: slim, long east-west, dark blue curtain wall, set to the west of the podium so its
	# lit crown stands over the corner.
	var slab := Vector3(minf(pod.x * 0.62, 36.0), HOTEL_HEIGHT - HOTEL_PODIUM, minf(pod.z * 0.5, 20.0))
	var sc := Vector3(c.x - (pod.x - slab.x) * 0.25, y0 + HOTEL_PODIUM + slab.y * 0.5, c.y - 2.0)
	var tower := Landmarks._facade_box(parent, statics, slab, sc, Color(0.12, 0.17, 0.26), Building.Finish.GLASS, Building.WindowStyle.CURTAIN, 0.0)
	var tm := tower.material_override as ShaderMaterial
	tm.set_shader_parameter("window_tint", Color(0.16, 0.24, 0.36))
	tm.set_shader_parameter("lit_ratio", 0.32)
	tm.set_shader_parameter("window_pitch_x", slab.x / roundf(slab.x / 1.5))
	tm.set_shader_parameter("window_pitch_z", slab.z / roundf(slab.z / 1.5))
	tm.set_shader_parameter("floor_height", slab.y / roundf(slab.y / 3.3))
	tm.set_shader_parameter("sky_zenith", Color(0.22, 0.36, 0.62))
	var fin_mat := LandmarkMats.plain("hotel_fin", Color(0.86, 0.88, 0.9), 0.3, 0.6)
	var crown_glow := LandmarkMats.glow("hotel_crown", Color(0.75, 0.88, 1.0))
	g.use("fin", fin_mat)
	g.use("crown", crown_glow)
	var top := sc.y + slab.y * 0.5
	# White vertical fins up the four corners and the middle of the long faces: the lines that
	# make the slab read as slim from across the basin.
	var fin_len := slab.y + 10.0
	for fx: float in [-0.5, 0.0, 0.5]:
		for fz: float in [-0.5, 0.5]:
			g.box("fin", Vector3(sc.x + fx * slab.x, sc.y + 5.0, sc.z + fz * (slab.z + 0.6)), Vector3(0.7, fin_len, 0.7), Color.WHITE, Basis(), 0.1 if detailed else 0.0)
	for fz: float in [-0.5, 0.5]:
		for fx: float in [-0.5, 0.5]:
			g.box("fin", Vector3(sc.x + fx * (slab.x + 0.6), sc.y + 5.0, sc.z + fz * slab.z * 0.5), Vector3(0.7, fin_len, 0.7), Color.WHITE, Basis(), 0.1 if detailed else 0.0)
	# The crown: a screen of glass fins round an open top, lit from inside after dark, and a
	# glowing band that marks the skyline.
	var fins := 28 if detailed else 12
	for i in fins:
		var f := (float(i) + 0.5) / float(fins)
		var x := sc.x - slab.x * 0.5 + f * slab.x
		for fz: float in [-1.0, 1.0]:
			g.box("fin", Vector3(x, top + 5.0, sc.z + fz * slab.z * 0.5), Vector3(0.35, 10.0, 0.9), Color(0.9, 0.93, 0.96))
	g.box("crown", Vector3(sc.x, top + 0.6, sc.z), Vector3(slab.x + 0.8, 1.2, slab.z + 0.8), Color(1.0, 1.0, 1.0))
	g.box("crown", Vector3(sc.x, top + 9.6, sc.z), Vector3(slab.x + 0.4, 0.5, slab.z + 0.4), Color(1.0, 1.0, 1.0))
	LandmarkGeo.shape_box(statics, Vector3(sc.x, top + 5.0, sc.z), Vector3(slab.x, 10.0, slab.z))
	# The name, lit, high on the long faces and over the porte-cochère.
	for side: float in [-1.0, 1.0]:
		var yaw := 0.0 if side < 0.0 else PI
		batch.add("hotel_name", Signage.text_mesh(HOTEL_NAME, 3.2, Signage.Letters.LIT),
			Transform3D(_face(yaw, 1.0), Vector3(sc.x, top - 4.0, sc.z + side * (slab.z * 0.5 + 0.35))), Color(0.9, 0.95, 1.0))
	batch.set_no_shadow("hotel_name")
	if detailed:
		# Porte-cochère on the east side: a flat canopy on columns, lit underneath.
		var pc := Vector3(c.x + pod.x * 0.5 + 4.0, y0 + 6.0, c.y)
		g.use("metal", LandmarkMats.plain("hotel_metal", Color(0.3, 0.31, 0.33), 0.4, 0.6))
		g.box("metal", pc, Vector3(8.0, 0.8, 16.0), Color.WHITE, Basis(), 0.1)
		LandmarkGeo.shape_box(statics, pc, Vector3(8.0, 0.8, 16.0))
		for dz: float in [-6.5, 6.5]:
			g.cylinder("metal", Vector3(pc.x + 3.2, y0, pc.z + dz), 0.25, 5.6, 10)
		batch.add("hotel_pool", PropFactory.light_pool(Color(1.0, 0.88, 0.7), 1.2), Transform3D(Basis(Vector3.RIGHT, -PI * 0.5).scaled(Vector3(8.0, 1.0, 16.0)), Vector3(pc.x, y0 + 0.05, pc.z)))
		batch.add("hotel_name_low", Signage.text_mesh(HOTEL_NAME, 0.9, Signage.Letters.LIT),
			Transform3D(_face(-PI * 0.5, 1.0), pc + Vector3(4.1, 0.0, 0.0)), Color(1.0, 0.92, 0.8))
		batch.set_no_shadow("hotel_name_low")
		# A beacon mast on the roof.
		g.cylinder("metal", Vector3(sc.x, top + 10.0, sc.z), 0.35, 8.0, 8)
		g.box("crown", Vector3(sc.x, top + 18.3, sc.z), Vector3(0.8, 0.8, 0.8), Color(1.0, 0.25, 0.2))
	g.commit(parent, "HotelAltair")
	batch.build(parent)
	_occluder(parent, [[sc, slab], [Vector3(c.x, y0 + pod.y * 0.5, c.y), pod]])


# ============================================================================================
# The convention centre
# ============================================================================================

## Depth of the entrance plaza in front of the pavilions (metres from the block's north edge).
static func _convention_front(s: Rect2) -> float:
	return clampf(s.size.y * 0.16, 8.0, 15.0)


static func _convention(s: Rect2, y0: float, parent: Node3D, statics: StaticBody3D, detailed: bool) -> void:
	var g := LandmarkGeo.new()
	var batch := MultiMeshBatch.new()
	var front := _convention_front(s)
	var white := LandmarkMats.facade("conv_white", "", 1.0,
		{"tint": WHITE_PANEL, "roughness": 0.55, "metallic": 0.15, "joint_spacing": Vector2(3.0, 1.2), "joint_width": 0.028, "joint_dark": 0.22, "grime": 0.25, "base_y": y0,
		"flood_strength": 0.35, "flood_base_y": y0, "flood_reach": 7.0, "flood_spacing": 9.0})
	var green := LandmarkMats.glass("conv_green", {"glass_tint": Color(0.16, 0.40, 0.33), "frame_color": Color(0.26, 0.46, 0.38),
		"grid": Vector2(2.2, 2.2), "frame_width": 0.12, "room_depth": 14.0, "storey": 26.0, "floor_y": y0, "interior_day": 0.14, "interior_night": 1.6,
		"sky_horizon": Color(0.40, 0.52, 0.48), "reflect_energy": 1.2})
	var band := LandmarkMats.glass("conv_band", {"glass_tint": Color(0.18, 0.34, 0.32), "frame_color": Color(0.85, 0.86, 0.86),
		"grid": Vector2(1.5, 4.0), "frame_width": 0.08, "room_depth": 20.0, "storey": 8.0, "floor_y": y0, "interior_night": 1.3})
	var frame := LandmarkMats.plain("conv_frame", Color(0.93, 0.93, 0.92), 0.4, 0.35)
	g.use("white", white)
	g.use("green", green)
	g.use("band", band)
	g.use("frame", frame)

	# The hall: long, low and white, filling the back of the block.
	var hall := Rect2(Vector2(s.position.x + 1.0, s.position.y + front + 12.0), Vector2(s.size.x - 2.0, s.size.y - front - 13.0))
	var hall_h := 19.0
	var hc := Vector3(hall.get_center().x, y0 + hall_h * 0.5, hall.get_center().y)
	g.box("white", hc, Vector3(hall.size.x, hall_h, hall.size.y), Color.WHITE, Basis(), 0.3 if detailed else 0.0)
	LandmarkGeo.shape_box(statics, hc, Vector3(hall.size.x, hall_h, hall.size.y))
	# The clerestory: a band of glass high along the front, under a white fascia.
	g.wall("band", Vector2(hall.end.x - 3.0, hall.position.y - 0.03), Vector2(hall.position.x + 3.0, hall.position.y - 0.03), y0 + 12.5, y0 + 16.8)
	g.box("white", Vector3(hc.x, y0 + 17.5, hall.position.y - 0.6), Vector3(hall.size.x - 4.0, 1.4, 1.2), Color(0.97, 0.97, 0.96), Basis(), 0.1 if detailed else 0.0)
	# Roof: three long skylight monitors, and a parapet.
	for i in 3:
		var z := hall.position.y + hall.size.y * (0.22 + 0.28 * float(i))
		g.box("white", Vector3(hc.x, y0 + hall_h + 1.2, z), Vector3(hall.size.x - 10.0, 2.4, 4.0), Color(0.95, 0.95, 0.94), Basis(), 0.1 if detailed else 0.0)
		g.wall("band", Vector2(hall.end.x - 5.2, z - 2.03), Vector2(hall.position.x + 5.2, z - 2.03), y0 + hall_h + 0.2, y0 + hall_h + 2.1)
	# The two pavilions at the front corners, their green glass walls tilting outward as they
	# rise, capped by an exposed white space frame; and the glass concourse between them.
	var pw := clampf(s.size.x * 0.24, 14.0, 22.0)
	var ph := 26.0
	var flare := 2.6
	var pz := s.position.y + front + pw * 0.5
	for side: float in [-1.0, 1.0]:
		var pcx := s.get_center().x + side * (s.size.x * 0.5 - pw * 0.5 - flare - 1.5)
		_pavilion(g, Vector2(pcx, pz), pw, ph, flare, y0, statics, detailed)
	var con := Rect2(Vector2(s.get_center().x - (s.size.x * 0.5 - pw - flare * 2.0 - 2.0), s.position.y + front + 4.0),
		Vector2((s.size.x * 0.5 - pw - flare * 2.0 - 2.0) * 2.0, hall.position.y - (s.position.y + front + 4.0) + 0.5))
	var con_h := 11.0
	var cc := Vector3(con.get_center().x, y0 + con_h * 0.5, con.get_center().y)
	g.wall("green", Vector2(con.end.x, con.position.y), Vector2(con.position.x, con.position.y), y0, y0 + con_h)
	g.box("frame", Vector3(cc.x, y0 + con_h + 0.4, cc.z), Vector3(con.size.x + 1.0, 0.8, con.size.y + 1.0), Color.WHITE, Basis(), 0.12 if detailed else 0.0)
	LandmarkGeo.shape_box(statics, cc, Vector3(con.size.x, con_h, con.size.y))
	LandmarkGeo.shape_box(statics, Vector3(cc.x, y0 + con_h + 0.4, cc.z), Vector3(con.size.x + 1.0, 0.8, con.size.y + 1.0))
	# The name on a low wall at the front of the plaza.
	var sign_at := Vector3(s.get_center().x, y0, s.position.y + 2.0)
	g.box("white", sign_at + Vector3(0.0, 0.8, 0.0), Vector3(22.0, 1.6, 0.8), Color(0.9, 0.9, 0.9), Basis(), 0.08 if detailed else 0.0)
	LandmarkGeo.shape_box(statics, sign_at + Vector3(0.0, 0.8, 0.0), Vector3(22.0, 1.6, 0.8))
	batch.add("conv_name", Signage.text_mesh(CONVENTION_NAME, 0.95, Signage.Letters.LIT),
		Transform3D(_face(0.0, 1.0), sign_at + Vector3(0.0, 0.85, -0.45)), Color(0.9, 1.0, 0.95))
	batch.set_no_shadow("conv_name")
	if detailed:
		g.use("paving", LandmarkMats.paving("paving", 2.8, Color(0.82, 0.81, 0.79), 6617, 3.0, 0.3))
		g.cap("paving", LandmarkGeo.ccw(_rect_poly(Rect2(s.position, Vector2(s.size.x, front + 12.0)))), y0 + 0.03)
		# Flag poles along the plaza, and planters.
		var pole := PropFactory.cylinder("conv_pole", 0.09, 1.0, Color(0.85, 0.86, 0.88), 0.06, 8)
		var flag_cols := [Color(0.2, 0.45, 0.4), Color(0.9, 0.9, 0.88), Color(0.85, 0.35, 0.2), Color(0.2, 0.3, 0.55)]
		for i in 7:
			var fx := lerpf(con.position.x + 3.0, con.end.x - 3.0, float(i) / 6.0)
			var at := Vector3(fx, y0, s.position.y + front - 1.0)
			batch.add("conv_pole", pole, Transform3D(Basis().scaled(Vector3(1.0, 12.0, 1.0)), at + Vector3(0.0, 6.0, 0.0)))
			g.box("frame", at + Vector3(0.0, 10.6, -0.95), Vector3(0.05, 2.4, 1.8), flag_cols[i % flag_cols.size()])
		var mast := PropFactory.cylinder("lm_mast", 0.2, 1.0, STEEL_DARK, 0.13, 10)
		for fx: float in [s.position.x + 8.0, s.end.x - 8.0]:
			_mast(batch, Vector3(fx, y0, s.position.y + 4.0), 10.0, mast)
			_add_light(parent, Vector3(fx, y0 + 9.0, s.position.y + 4.0))
	g.commit(parent, "ConventionCenter")
	batch.build(parent)
	_occluder(parent, [[hc, Vector3(hall.size.x, hall_h, hall.size.y)]])


## One pavilion: a square of green glass whose walls lean out from `w` at the foot to
## `w + 2 flare` at the head, mullions on the tilt, and a white space frame on top.
static func _pavilion(g: LandmarkGeo, c: Vector2, w: float, h: float, flare: float, y0: float,
		statics: StaticBody3D, detailed: bool) -> void:
	var b := w * 0.5
	var t := b + flare
	var foot := [Vector2(-b, -b), Vector2(-b, b), Vector2(b, b), Vector2(b, -b)]
	var head := [Vector2(-t, -t), Vector2(-t, t), Vector2(t, t), Vector2(t, -t)]
	var u := 0.0
	for i in 4:
		var a0: Vector2 = c + foot[i]
		var a1: Vector2 = c + foot[(i + 1) % 4]
		var h0: Vector2 = c + head[i]
		var h1: Vector2 = c + head[(i + 1) % 4]
		var n2 := Vector2((a1 - a0).y * -1.0, (a1 - a0).x).normalized()
		var n := Vector3(n2.x, -flare / h, n2.y).normalized()
		var length := a0.distance_to(a1)
		var top_len := h0.distance_to(h1)
		var ext := (top_len - length) * 0.5
		g.quad("green", Vector3(a0.x, y0, a0.y), Vector3(h0.x, y0 + h, h0.y), Vector3(h1.x, y0 + h, h1.y), Vector3(a1.x, y0, a1.y), n,
			Vector2(u, y0), Vector2(u - ext, y0 + h), Vector2(u + length + ext, y0 + h), Vector2(u + length, y0), Color.WHITE, statics != null)
		u += length
		if detailed:
			# Green steel mullions on the tilt, every few metres.
			var bays := int(length / 3.3)
			for k in range(1, bays):
				var f := float(k) / float(bays)
				var pb := a0.lerp(a1, f)
				var pt := h0.lerp(h1, f)
				var p0 := Vector3(pb.x, y0, pb.y)
				var p1 := Vector3(pt.x, y0 + h, pt.y)
				var ya := (p1 - p0).normalized()
				var za := Vector3(n2.x, 0.0, n2.y)
				var xa := ya.cross(za).normalized()
				za = xa.cross(ya).normalized()
				g.box("frame", (p0 + p1) * 0.5 + za * 0.18, Vector3(0.18, (p1 - p0).length(), 0.36), Color(0.36, 0.55, 0.46), Basis(xa, ya, za))
	# The space frame: a lattice of white tubes over the top, deeper than it is wide, a lid.
	var lid := t + 0.8
	g.box("frame", Vector3(c.x, y0 + h + 0.5, c.y), Vector3(lid * 2.0, 1.0, lid * 2.0), Color.WHITE, Basis(), 0.1 if detailed else 0.0)
	LandmarkGeo.shape_box(statics, Vector3(c.x, y0 + h + 0.5, c.y), Vector3(lid * 2.0, 1.0, lid * 2.0))
	LandmarkGeo.shape_box(statics, Vector3(c.x, y0 + h * 0.5, c.y), Vector3(w + flare, h, w + flare))
	if detailed:
		var n := 6
		for i in n + 1:
			var f := -lid + 2.0 * lid * float(i) / float(n)
			g.box("frame", Vector3(c.x + f, y0 + h + 2.2, c.y), Vector3(0.35, 0.35, lid * 2.0), Color.WHITE)
			g.box("frame", Vector3(c.x, y0 + h + 2.2, c.y + f), Vector3(lid * 2.0, 0.35, 0.35), Color.WHITE)
			for j in n:
				var f2 := -lid + 2.0 * lid * (float(j) + 0.5) / float(n)
				# Diagonal struts from the lid up to the top chords.
				g.box("frame", Vector3(c.x + f, y0 + h + 1.6, c.y + f2), Vector3(0.18, 1.4, 0.18), Color.WHITE, Basis(Vector3.RIGHT, 0.5))


# ============================================================================================
# Shared bits
# ============================================================================================

static func _rect_poly(r: Rect2) -> PackedVector2Array:
	return PackedVector2Array([r.position, Vector2(r.end.x, r.position.y), r.end, Vector2(r.position.x, r.end.y)])


## A basis facing `yaw` (the direction the face looks), for TextMesh and screens, scaled.
static func _face(yaw: float, s: float) -> Basis:
	return Basis(Vector3.UP, yaw + PI).scaled(Vector3(s, s, s))


## A light mast: a tapered pole, a head and a pool of light at its foot.
static func _mast(batch: MultiMeshBatch, at: Vector3, height: float, mast: Mesh) -> void:
	batch.add("lm_mast", mast, Transform3D(Basis().scaled(Vector3(1.0, height, 1.0)), at + Vector3(0.0, height * 0.5, 0.0)))
	batch.add("lm_mast_head", PropFactory.lamp_head(), Transform3D(Basis().scaled(Vector3(2.4, 1.4, 2.4)), at + Vector3(0.0, height, 0.0)))
	batch.add("lm_mast_pool", PropFactory.light_pool(Color(1.0, 0.9, 0.76), 1.1), Transform3D(Basis(Vector3.RIGHT, -PI * 0.5).scaled(Vector3(16.0, 1.0, 16.0)), at + Vector3(0.0, 0.06, 0.0)))
	batch.set_no_shadow("lm_mast_pool")


## A real light over a plaza, for the detailed version only: DayNight drives every node in the
## "lamp_light" group with the street lamps (Quality turns them off at the low levels). A few per
## landmark, never one per fitting - the additive pools carry the rest.
static func _add_light(parent: Node3D, at: Vector3, reach: float = 22.0) -> void:
	var light := OmniLight3D.new()
	light.position = at
	light.omni_range = reach
	light.omni_attenuation = 1.2
	light.light_color = Color(1.0, 0.9, 0.78)
	light.light_energy = 0.0
	light.shadow_enabled = false
	light.distance_fade_enabled = true
	light.distance_fade_begin = 70.0
	light.distance_fade_length = 20.0
	light.add_to_group("lamp_light")
	parent.add_child(light)


## An OccluderInstance3D of boxes (centre, size), each pulled in so it never sticks out past
## the building it stands for (see CityChunk._build_occluder()). Detailed (chunk) builds only.
static func _occluder(parent: Node3D, boxes: Array) -> void:
	var verts := PackedVector3Array()
	var idx := PackedInt32Array()
	for b: Array in boxes:
		var c: Vector3 = b[0]
		var sz: Vector3 = b[1]
		var hx := sz.x * 0.5 - minf(1.75, sz.x * 0.2)
		var hz := sz.z * 0.5 - minf(1.75, sz.z * 0.2)
		var bottom := c.y - sz.y * 0.5
		var top := c.y + sz.y * 0.5 - 1.0
		if hx < 1.5 or hz < 1.5 or top - bottom < 4.0:
			continue
		var o := verts.size()
		for y: float in [bottom, top]:
			verts.append(Vector3(c.x - hx, y, c.z - hz))
			verts.append(Vector3(c.x + hx, y, c.z - hz))
			verts.append(Vector3(c.x + hx, y, c.z + hz))
			verts.append(Vector3(c.x - hx, y, c.z + hz))
		for f: Array in [[0, 1, 5, 4], [1, 2, 6, 5], [2, 3, 7, 6], [3, 0, 4, 7], [4, 5, 6, 7]]:
			idx.append_array(PackedInt32Array([o + f[0], o + f[1], o + f[2], o + f[0], o + f[2], o + f[3]]))
	if idx.is_empty() or not (parent is CityChunk):
		return
	var occ := ArrayOccluder3D.new()
	occ.set_arrays(verts, idx)
	var node := OccluderInstance3D.new()
	node.name = "LandmarkOccluder"
	node.occluder = occ
	parent.add_child(node)
