class_name LandmarkDowntown
extends RefCounted
## The downtown skyline (owner, 2026-09-24: "the downtown skyline [must] become a 1:1 match of
## DTLA skyline ... It needs more buildings").
##
## What is matched is the MASSING of the real downtown: which towers stand where relative to each
## other, how tall each is against the rest, their silhouettes, crowns and facade character - the
## 335 m sail with its spire on the west edge, the 310 m round tower with the crenellated glass
## crown up on the hill, the flat white granite slab, the blue elliptical crown, the rounded crown
## and its shorter sister, the two identical black towers, the bronze slab, the curved white
## tower with its stepped top, the red granite pair with angled tops, the stepped pyramid, the
## dark glass tower, the pyramid with a spire, the five mirrored drums, and the slender glass
## towers of South Park beside the frame of an unfinished cluster. What is NOT copied: names and
## logos. Every name here and on the minimap is original, and there is no lettering on any crown.
##
## Scale. Heights are REAL metres, 1:1 - the player jumps hundreds of metres, and a skyline is
## the ratio of its heights. The plan is the real street grid laid onto the game's own downtown
## streets one real block to one game block (about 2/3 scale; the game's blocks are 70-110 m
## where the real ones are 110-180), with each tower in the block it really stands on relative
## to its neighbours: west of the first avenue, the sail; the next avenue's blocks, the drums, the
## black twins, the pyramid and the curved tower; then the dark glass, bronze and white slabs;
## the round tower and the red pair up the hill; the blue crown and the rounded pair to the east.
## Footprints are close to real (0.8-1.0) so the towers keep their bulk, which leaves them a
## little closer together than in life - the way every skyline in a game is.
##
## The grid those blocks come from is the default seed's own, and CityPlan pins it for every
## seed (CityPlan.PINNED_ROADS), because these anchors are fixed and would otherwise stand in the
## road on any other seed.
##
## Construction: TowerMesh. Each tower is one ArrayMesh (facade surfaces on the building shader's
## outline mode, a metal surface, a lit crown surface), a billboard mesh of aviation lights, an
## occluder, and - detailed only - convex collision and a little street-level and rooftop detail.
## Meshes are cached per id and shared by the far copy CityStreamer keeps and the detailed one a
## chunk builds, so the skyline seen from the freeway IS the tower you land on.

## Every tower stands on the pavement top: landmarks keep the relief flat under them.
const BASE_Y := 0.25

## THE downtown table: one row per tower, and the only place a tower's placement lives.
##   anchor     game world XZ of the plan's centre, in its block of the pinned grid (the current,
##              about-2/3-scale layout: one real block to one game block)
##   radius     half-extent the landmark reserves (lots, relief) - covers `plan`
##   height     metres to the highest point, REAL (1:1); the smoke test checks the geometry
##   plan       metres, the extent of the plan as built (x, z), podium included
##   crown      what stands on top, in words
##   real       APPROXIMATE real position, metres east (x) and north (y) of REAL_ORIGIN, from the
##              tower's rough latitude / longitude (public maps, from memory: good to about
##              +/-50 m, check before a 1:1 re-lay). park_a..d are representative South Park
##              spots, not particular buildings.
##   real_plan  APPROXIMATE real footprint (m), for a 1:1 re-lay
## The builders below make each tower in its own local metres round (0, 0), so moving a tower
## is changing its anchor; nothing else knows where it stands.
const TOWERS := {
	"dt_sail_tower": {"anchor": Vector2(456.1, 595.65), "radius": 43.0, "height": 335.0, "plan": Vector2(70.0, 84.0),
		"crown": "sloping glass sail rising east to a 35 m spire, on a stone hotel podium",
		"real": Vector2(-470.0, 11.0), "real_plan": Vector2(75.0, 45.0)},
	"dt_five_drums": {"anchor": Vector2(548.5, 377.7), "radius": 29.0, "height": 112.0, "plan": Vector2(49.0, 57.0),
		"crown": "flat tops; lit restaurant band near the top of the middle drum; glass lifts outside",
		"real": Vector2(-148.0, 300.0), "real_plan": Vector2(110.0, 110.0)},
	"dt_black_twins": {"anchor": Vector2(548.5, 474.55), "radius": 46.0, "height": 213.0, "plan": Vector2(42.0, 91.2),
		"crown": "flat; two identical black towers across a plaza",
		"real": Vector2(-171.0, 172.0), "real_plan": Vector2(48.0, 48.0)},
	"dt_pyramid_crown": {"anchor": Vector2(548.5, 590.0), "radius": 22.0, "height": 218.0, "plan": Vector2(42.0, 42.0),
		"crown": "stepped glass pyramid, lit green",
		"real": Vector2(-350.0, -55.0), "real_plan": Vector2(45.0, 45.0)},
	"dt_spire_pyramid": {"anchor": Vector2(548.5, 694.95), "radius": 19.0, "height": 163.0, "plan": Vector2(36.0, 36.0),
		"crown": "dark glass pyramid roof and a spire",
		"real": Vector2(-443.0, -155.0), "real_plan": Vector2(42.0, 42.0)},
	"dt_curved_white": {"anchor": Vector2(548.5, 781.2), "radius": 25.0, "height": 221.0, "plan": Vector2(48.0, 43.0),
		"crown": "three curved setbacks and a lit band",
		"real": Vector2(-516.0, -266.0), "real_plan": Vector2(55.0, 45.0)},
	"dt_bronze_slab": {"anchor": Vector2(624.95, 285.7), "radius": 27.0, "height": 224.0, "plan": Vector2(38.0, 52.0),
		"crown": "flat, corners cut",
		"real": Vector2(-28.0, 411.0), "real_plan": Vector2(60.0, 45.0)},
	"dt_dark_glass": {"anchor": Vector2(624.95, 377.7), "radius": 22.0, "height": 191.0, "plan": Vector2(38.0, 42.0),
		"crown": "two notched setbacks",
		"real": Vector2(-55.0, 311.0), "real_plan": Vector2(45.0, 45.0)},
	"dt_granite_slab": {"anchor": Vector2(624.95, 595.65), "radius": 30.0, "height": 262.0, "plan": Vector2(38.2, 58.2),
		"crown": "flat; dark mechanical band with one lit line",
		"real": Vector2(-184.0, -33.0), "real_plan": Vector2(61.0, 40.0)},
	"dt_park_a": {"anchor": Vector2(624.95, 694.95), "radius": 23.0, "height": 190.0, "plan": Vector2(38.0, 44.0),
		"crown": "violet lit top; balconies winding round the tower",
		"real": Vector2(-553.0, -555.0), "real_plan": Vector2(32.0, 32.0)},
	"dt_park_c": {"anchor": Vector2(624.95, 790.0), "radius": 15.0, "height": 160.0, "plan": Vector2(29.2, 29.2),
		"crown": "warm lit top; vertical fins",
		"real": Vector2(-323.0, -499.0), "real_plan": Vector2(30.0, 30.0)},
	"dt_faceted_twins": {"anchor": Vector2(697.8, 285.7), "radius": 40.0, "height": 220.0, "plan": Vector2(38.0, 78.0),
		"crown": "sloping glass tops facing apart (220 m and 192 m)",
		"real": Vector2(185.0, 283.0), "real_plan": Vector2(45.0, 45.0)},
	"dt_crown_cylinder": {"anchor": Vector2(697.8, 377.7), "radius": 22.0, "height": 310.0, "plan": Vector2(42.0, 42.0),
		"crown": "crenellated glass lantern, lit, and a helipad; wings step back in a spiral",
		"real": Vector2(74.0, 111.0), "real_plan": Vector2(50.0, 50.0)},
	"dt_park_b": {"anchor": Vector2(697.8, 767.0), "radius": 17.0, "height": 175.0, "plan": Vector2(31.2, 33.2),
		"crown": "ice-white lit top; staggered balconies",
		"real": Vector2(-369.0, -666.0), "real_plan": Vector2(30.0, 30.0)},
	"dt_plaza_one": {"anchor": Vector2(774.0, 267.0), "radius": 18.0, "height": 176.0, "plan": Vector2(35.0, 33.0),
		"crown": "flat, granite penthouse",
		"real": Vector2(415.0, 344.0), "real_plan": Vector2(40.0, 40.0)},
	"dt_round_crown": {"anchor": Vector2(789.0, 305.0), "radius": 20.0, "height": 229.0, "plan": Vector2(40.0, 38.0),
		"crown": "rounded glass barrel vault, lit warm, and a finial",
		"real": Vector2(378.0, 288.0), "real_plan": Vector2(45.0, 45.0)},
	"dt_ellipse_crown": {"anchor": Vector2(782.05, 458.0), "radius": 25.0, "height": 229.0, "plan": Vector2(47.0, 35.0),
		"crown": "elliptical blue glass crown, lit blue",
		"real": Vector2(184.0, 0.0), "real_plan": Vector2(55.0, 40.0)},
	"dt_park_d": {"anchor": Vector2(782.05, 694.95), "radius": 17.0, "height": 145.0, "plan": Vector2(33.4, 33.4),
		"crown": "blue lit top; boxed-out balconies",
		"real": Vector2(-231.0, -754.0), "real_plan": Vector2(30.0, 30.0)},
	"dt_unfinished": {"anchor": Vector2(782.05, 781.2), "radius": 40.0, "height": 190.0, "plan": Vector2(62.3, 78.0),
		"crown": "bare concrete frames on three towers, a tower crane on the tallest",
		"real": Vector2(-812.0, -810.0), "real_plan": Vector2(120.0, 100.0)},
}

## Where `real` is measured from: latitude, longitude (a point just north-west of the central
## square), and the bearing of the real street grid's "north" (the avenues run from about 45
## degrees east of true north). real_grid() turns `real` into grid-aligned metres, which is what
## an axis-aligned game grid wants.
const REAL_ORIGIN := Vector2(34.0500, -118.2550)
const GRID_BEARING_DEG := 45.0


## A tower's approximate real position in the real grid's frame: x metres along the numbered
## streets (toward the old commercial core), y metres along the avenues toward the higher street
## numbers (so +y is "grid south", like the game's +Z).
static func real_grid(id: String) -> Vector2:
	var en: Vector2 = TOWERS[id].real
	var b := deg_to_rad(GRID_BEARING_DEG)
	var grid_north := Vector2(sin(b), cos(b))
	var grid_east := Vector2(cos(b), -sin(b))
	return Vector2(en.dot(grid_east), -en.dot(grid_north))


## The landmark rows for Landmarks.all(), in the table's order.
static func entries() -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for id: String in TOWERS:
		out.append({"id": id, "anchor": TOWERS[id].anchor, "radius": TOWERS[id].radius})
	return out


# Colours of the metal and lit parts.
const STEEL := Color(0.62, 0.64, 0.66)
const DARK_STEEL := Color(0.20, 0.21, 0.23)
const WHITE_METAL := Color(0.86, 0.87, 0.88)
const CONCRETE := Color(0.60, 0.59, 0.56)
const HELIPAD := Color(0.33, 0.34, 0.35)
const COPPER := Color(0.30, 0.46, 0.40)
const CRANE := Color(0.86, 0.66, 0.12)
const CROWN_WHITE := Color(0.86, 0.93, 1.0)
const WARM := Color(1.0, 0.84, 0.60)
const ICE := Color(0.70, 0.86, 1.0)
const BLUE := Color(0.25, 0.52, 1.0)
const GREEN := Color(0.46, 1.0, 0.64)
const VIOLET := Color(0.72, 0.52, 1.0)
const RED := Color(1.0, 0.10, 0.06)

static var _towers: Dictionary = {}
static var _materials: Dictionary = {}


static func is_tower(id: String) -> bool:
	return TOWERS.has(id)


## Builds one tower under `parent` at its anchor (children at true world coordinates, like every
## landmark). `statics` null means the far copy: no collision, no street-level detail.
static func build(lm: Dictionary, parent: Node3D, statics: StaticBody3D, detailed: bool) -> void:
	var id: String = lm.id
	var t := tower(id)
	var anchor: Vector2 = lm.anchor
	var at := Vector3(anchor.x, BASE_Y, anchor.y)
	var body := MeshInstance3D.new()
	body.name = "Tower_" + id
	body.mesh = t.mesh
	body.position = at
	parent.add_child(body)
	if detailed and t.detail != null:
		var extra := MeshInstance3D.new()
		extra.name = "Detail_" + id
		extra.mesh = t.detail
		extra.position = at
		# Street-level and rooftop clutter: no one sees it from a kilometre away.
		extra.visibility_range_end = 700.0
		extra.visibility_range_end_margin = 60.0
		extra.visibility_range_fade_mode = GeometryInstance3D.VISIBILITY_RANGE_FADE_SELF
		parent.add_child(extra)
	if t.lights != null:
		var lights := MeshInstance3D.new()
		lights.name = "Lights_" + id
		lights.mesh = t.lights
		lights.position = at
		lights.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		# Every corner of a light is its centre point, and the shader draws them past the far
		# plane on purpose (see AmbientCraft._build_lights()).
		lights.custom_aabb = AABB(Vector3(-80.0, -10.0, -80.0), Vector3(160.0, 360.0, 160.0))
		lights.extra_cull_margin = 16000.0
		parent.add_child(lights)
	if t.occluder != null:
		var occ := OccluderInstance3D.new()
		occ.name = "Occluder_" + id
		occ.occluder = t.occluder
		occ.position = at
		parent.add_child(occ)
	if statics:
		for hull: PackedVector3Array in t.hulls:
			var shape := CollisionShape3D.new()
			var convex := ConvexPolygonShape3D.new()
			convex.points = hull
			shape.shape = convex
			shape.position = at
			statics.add_child(shape)


## The tower's parts, built once and cached: {mesh, detail, lights, occluder, hulls, extent
## (local Rect2 of the plan), top (m above BASE_Y), tris}.
static func tower(id: String) -> Dictionary:
	if _towers.has(id):
		return _towers[id]
	var tm := TowerMesh.new(1.5)
	tm.metal_material = _metal_material()
	var detail := TowerMesh.new(1.5)
	detail.metal_material = _metal_material()
	match id:
		"dt_sail_tower":
			_sail_tower(tm, detail)
		"dt_crown_cylinder":
			_crown_cylinder(tm, detail)
		"dt_granite_slab":
			_granite_slab(tm, detail)
		"dt_ellipse_crown":
			_ellipse_crown(tm, detail)
		"dt_round_crown":
			_round_crown(tm, detail)
		"dt_plaza_one":
			_plaza_one(tm, detail)
		"dt_faceted_twins":
			_faceted_twins(tm, detail)
		"dt_bronze_slab":
			_bronze_slab(tm, detail)
		"dt_dark_glass":
			_dark_glass(tm, detail)
		"dt_five_drums":
			_five_drums(tm, detail)
		"dt_black_twins":
			_black_twins(tm, detail)
		"dt_pyramid_crown":
			_pyramid_crown(tm, detail)
		"dt_spire_pyramid":
			_spire_pyramid(tm, detail)
		"dt_curved_white":
			_curved_white(tm, detail)
		"dt_park_a":
			_park_a(tm, detail)
		"dt_park_b":
			_park_b(tm, detail)
		"dt_park_c":
			_park_c(tm, detail)
		"dt_park_d":
			_park_d(tm, detail)
		"dt_unfinished":
			_unfinished(tm, detail)
	if tm.glow_material == null:
		tm.glow_material = _glow_material("default", Color(0.30, 0.38, 0.46), 1, 1.6)
	detail.glow_material = tm.glow_material
	var mesh := tm.commit()
	var extra: ArrayMesh = detail.commit()
	var occluder: ArrayOccluder3D = null
	if not tm.occluders.is_empty():
		var verts := PackedVector3Array()
		var idx := PackedInt32Array()
		for box: AABB in tm.occluders:
			var o := verts.size()
			for y: float in [box.position.y, box.end.y]:
				verts.append(Vector3(box.position.x, y, box.position.z))
				verts.append(Vector3(box.end.x, y, box.position.z))
				verts.append(Vector3(box.end.x, y, box.end.z))
				verts.append(Vector3(box.position.x, y, box.end.z))
			for f: Array in [[0, 1, 5, 4], [1, 2, 6, 5], [2, 3, 7, 6], [3, 0, 4, 7], [4, 5, 6, 7]]:
				idx.append_array(PackedInt32Array([o + f[0], o + f[1], o + f[2], o + f[0], o + f[2], o + f[3]]))
		occluder = ArrayOccluder3D.new()
		occluder.set_arrays(verts, idx)
	var t := {
		"mesh": mesh,
		"detail": extra if extra.get_surface_count() > 0 else null,
		"lights": tm.light_mesh(_light_material()),
		"occluder": occluder,
		"hulls": tm.hulls + detail.hulls,
		"extent": tm.extent,
		"top": tm.top,
		"tris": tm.triangle_count(mesh) + (detail.triangle_count(extra) if extra.get_surface_count() > 0 else 0),
	}
	_towers[id] = t
	return t


## The plan a tower stands on, in world XZ (for the checks: it has to stay off the road).
static func footprint(lm: Dictionary) -> Rect2:
	var ext: Rect2 = tower(lm.id).extent
	return Rect2(ext.position + (lm.anchor as Vector2), ext.size)


# --- Materials -------------------------------------------------------------------------------

## A facade material on shaders/building.gdshader in its outline (uv_facade) mode. Cached by key:
## a tower's styles are shared between its far and detailed copies and between twins.
static func _facade(key: String, finish: int, style: int, facade: Color, tint: Color, accent: Color, lit: float,
		floor_h: float, pitch: float, storefront: float = 0.0, base_h: float = 0.0, lit_color: Color = Color(1.0, 0.90, 0.72)) -> ShaderMaterial:
	if _materials.has(key):
		return _materials[key]
	var mat := ShaderMaterial.new()
	mat.shader = Building.SHADER
	mat.set_shader_parameter("uv_facade", true)
	mat.set_shader_parameter("facade_color", facade)
	mat.set_shader_parameter("accent_color", accent)
	mat.set_shader_parameter("facade_finish", finish)
	mat.set_shader_parameter("window_style", style)
	mat.set_shader_parameter("window_tint", tint)
	mat.set_shader_parameter("lit_color", lit_color)
	mat.set_shader_parameter("lit_ratio", lit)
	mat.set_shader_parameter("window_pitch_x", pitch)
	mat.set_shader_parameter("window_pitch_z", pitch)
	mat.set_shader_parameter("floor_height", floor_h)
	mat.set_shader_parameter("ground_floor_height", BASE_Y + storefront)
	mat.set_shader_parameter("base_y", BASE_Y)
	mat.set_shader_parameter("has_storefront", storefront > 0.0)
	mat.set_shader_parameter("part_size", Vector3(60.0, 300.0, 60.0))
	mat.set_shader_parameter("seed", float(absi(hash(key)) % 1000))
	# White membrane: the cool roof every new tower up here has.
	mat.set_shader_parameter("roof_style", 1)
	mat.set_shader_parameter("base_height", base_h)
	if base_h > 0.0:
		mat.set_shader_parameter("base_color", facade.lerp(Color(0.60, 0.58, 0.55), 0.35).darkened(0.12))
	var wall_set: Array = [["concrete", 4.0]] if finish == Building.Finish.PANELS else []
	Building._apply_wall_texture(mat, finish, false, wall_set[0] if not wall_set.is_empty() else [], 0.15)
	_materials[key] = mat
	return mat


static func _glow_material(key: String, day: Color, pattern: int, rib: float, energy: float = 3.2,
		mirror: float = 0.35, height: float = 20.0) -> ShaderMaterial:
	var k := "glow_" + key
	if _materials.has(k):
		return _materials[k]
	var mat := ShaderMaterial.new()
	mat.shader = load("res://shaders/tower_crown.gdshader")
	mat.set_shader_parameter("day_color", day)
	mat.set_shader_parameter("pattern", pattern)
	mat.set_shader_parameter("rib", rib)
	mat.set_shader_parameter("glow_energy", energy)
	mat.set_shader_parameter("day_mirror", mirror)
	mat.set_shader_parameter("part_height", height)
	_materials[k] = mat
	return mat


static func _metal_material() -> StandardMaterial3D:
	if _materials.has("metal"):
		return _materials["metal"]
	var mat := StandardMaterial3D.new()
	mat.vertex_color_use_as_albedo = true
	mat.metallic = 0.45
	mat.roughness = 0.42
	_materials["metal"] = mat
	return mat


static func _light_material() -> ShaderMaterial:
	if _materials.has("lights"):
		return _materials["lights"]
	var mat := ShaderMaterial.new()
	mat.shader = load("res://shaders/aircraft_lights.gdshader")
	# Obstruction lights are dim by day and nothing like a strobe; they pulse slowly at night.
	mat.set_shader_parameter("day_level", 0.12)
	_materials["lights"] = mat
	return mat


## Red obstruction lights at the corners of a roof outline (and one on top).
static func _roof_lights(tm: TowerMesh, outline: PackedVector2Array, y: float, every: int = 1) -> void:
	for i in range(0, outline.size(), maxi(every, 1)):
		tm.light(Vector3(outline[i].x, y, outline[i].y), RED, 2.0, 0)


# --- The towers ------------------------------------------------------------------------------
# Local coordinates: metres from the anchor, +X east, +Z south, y from the pavement top.

## 335 m. The tallest: an elongated glass shaft with pointed ends, tapering in two setbacks,
## crowned by a sloping glass sail that rises east to a spire, on a stone hotel podium.
static func _sail_tower(tm: TowerMesh, detail: TowerMesh) -> void:
	tm.add_facade("glass", _facade("sail_glass", Building.Finish.GLASS, Building.WindowStyle.CURTAIN,
		Color(0.17, 0.23, 0.29), Color(0.32, 0.45, 0.56), Color(0.62, 0.64, 0.66), 0.5, 4.0, 1.5))
	tm.add_facade("podium", _facade("sail_podium", Building.Finish.PANELS, Building.WindowStyle.RIBBON,
		Color(0.72, 0.70, 0.66), Color(0.28, 0.38, 0.46), Color(0.42, 0.41, 0.39), 0.55, 4.5, 1.8, 6.5))
	tm.glow_material = _glow_material("sail", Color(0.30, 0.42, 0.52), 1, 1.5, 3.4, 0.4, 32.0)
	tm.prism(TowerMesh.chamfered(70.0, 84.0, 6.0), 0.0, 15.0, "podium")
	var plan := PackedVector2Array([Vector2(-26.0, -17.0), Vector2(26.0, -17.0), Vector2(31.0, 0.0),
		Vector2(26.0, 17.0), Vector2(-26.0, 17.0), Vector2(-31.0, 0.0)])
	tm.prism(plan, 15.0, 204.0, "glass", false, false)
	var mid := TowerMesh.moved(plan, Vector2(0.5, 0.0), Vector2(0.97, 0.91))
	tm.prism(mid, 204.0, 248.0, "glass", false, false)
	var upper := TowerMesh.moved(plan, Vector2(1.0, 0.0), Vector2(0.93, 0.82))
	tm.prism(upper, 248.0, 272.0, "glass", false, false)
	# The sail: glass carried on up past the roof, its top a plane rising from west to east.
	var sail := TowerMesh.inset(upper, 0.25)
	tm.wedge("glow", sail, 272.0, 289.0, Vector2(0.52, 0.0), Vector2(1.0, 0.0), ICE, 1.0)
	# The spire stands on the high end of the sail.
	tm.mast(Vector3(27.0, 300.0, 0.0), 35.0, 1.5, 0.25, WHITE_METAL, 10)
	tm.light(Vector3(27.0, 335.2, 0.0), RED, 3.0, 2)
	tm.light(Vector3(27.0, 318.0, 0.0), RED, 2.2, 0)
	for p: Vector2 in [upper[0], upper[4], upper[5]]:
		tm.light(Vector3(p.x, 273.0 + 0.52 * (p.x - 1.0) + 17.0, p.y), RED, 1.8, 0)
	# Street level: a glass canopy over the hotel entrance on the avenue side (east).
	detail.box("metal", Vector3(35.5, 6.8, 0.0), Vector3(3.2, 0.35, 20.0), DARK_STEEL)
	for z: float in [-8.0, 8.0]:
		detail.box("metal", Vector3(36.8, 3.4, z), Vector3(0.3, 6.8, 0.3), DARK_STEEL)
	# Pool deck and planters on the podium roof.
	detail.box("metal", Vector3(-18.0, 16.3, 28.0), Vector3(18.0, 0.4, 10.0), Color(0.20, 0.42, 0.52))
	for x: float in [-30.0, -10.0, 10.0]:
		detail.box("metal", Vector3(x, 16.6, -36.0), Vector3(6.0, 1.0, 2.0), Color(0.24, 0.36, 0.20))


## 310 m. A granite cylinder with four square wings that end one after another as it climbs (a
## spiral of setbacks), topped by a glass lantern ringed with glass merlons - lit at night - and
## a helipad.
static func _crown_cylinder(tm: TowerMesh, detail: TowerMesh) -> void:
	tm.add_facade("granite", _facade("crown_granite", Building.Finish.PANELS, Building.WindowStyle.RIBBON,
		Color(0.72, 0.70, 0.65), Color(0.20, 0.26, 0.31), Color(0.40, 0.39, 0.36), 0.42, 4.1, 1.5, 7.0))
	tm.glow_material = _glow_material("crown", Color(0.32, 0.40, 0.46), 1, 1.6, 3.6, 0.45, 14.0)
	var core := TowerMesh.circle(17.0, 56)
	# Wings W, S, E, N, and the height each one stops at.
	var wings := [
		[TowerMesh.moved(TowerMesh.rect(10.0, 16.0), Vector2(-16.0, 0.0)), 196.0],
		[TowerMesh.moved(TowerMesh.rect(16.0, 10.0), Vector2(0.0, 16.0)), 226.0],
		[TowerMesh.moved(TowerMesh.rect(10.0, 16.0), Vector2(16.0, 0.0)), 256.0],
		[TowerMesh.moved(TowerMesh.rect(16.0, 10.0), Vector2(0.0, -16.0)), 280.0],
	]
	var edges := [0.0, 196.0, 226.0, 256.0, 280.0, 296.0]
	for k in edges.size() - 1:
		var parts: Array = [core]
		for w: Array in wings:
			if float(w[1]) > float(edges[k]):
				parts.append(w[0])
		var outline := TowerMesh.union(parts)
		tm.prism(outline, edges[k], edges[k + 1], "granite", false, k == edges.size() - 2)
	# The lantern: a glass drum inside the parapet, then merlons of glass round its rim.
	tm.loft("glow", TowerMesh.circle(15.6, 48), 296.0, TowerMesh.circle(15.6, 48), 306.5, CROWN_WHITE, 1.0, true)
	var merlons := 20
	for i in merlons * 2:
		if i % 2 == 1:
			continue
		var a := TAU * float(i) / float(merlons * 2)
		var p := Vector2(cos(a), sin(a)) * 15.35
		tm.box("glow", Vector3(p.x, 308.25, p.y), Vector3(2.5, 3.5, 0.5), CROWN_WHITE, a + PI * 0.5, 1.0)
	tm.slab("metal", TowerMesh.circle(14.6, 40), 306.5, 306.9, HELIPAD)
	# Aviation lights round the lantern and a beacon on the helipad.
	for i in 4:
		var a := TAU * (float(i) + 0.5) / 4.0
		tm.light(Vector3(cos(a) * 15.4, 310.4, sin(a) * 15.4), RED, 2.2, 2)
	tm.light(Vector3(0.0, 297.6, 17.2), RED, 1.6, 0)
	# Detail: the helipad's markings ring, a window-washing crane on the lantern roof, and the
	# grand stair that climbs the hill beside the base.
	detail.slab("metal", TowerMesh.circle(9.0, 32), 306.9, 306.95, Color(0.78, 0.66, 0.18))
	detail.slab("metal", TowerMesh.circle(8.4, 32), 306.95, 307.0, HELIPAD)
	for i in 10:
		detail.box("metal", Vector3(-12.0 + float(i) * 1.2, float(i) * 0.6 + 0.3, 21.5), Vector3(1.2, 0.6, 8.0), CONCRETE)


## 262 m. A flat-topped slab of white granite with the corners cut, dark windows in narrow vertical
## strips between the piers, and a dark mechanical band round the top with one lit line.
static func _granite_slab(tm: TowerMesh, detail: TowerMesh) -> void:
	tm.add_facade("granite", _facade("slab_granite", Building.Finish.PANELS, Building.WindowStyle.NARROW,
		Color(0.84, 0.83, 0.80), Color(0.12, 0.14, 0.17), Color(0.55, 0.55, 0.53), 0.38, 4.0, 1.35, 0.0, 9.0))
	tm.add_facade("band", _facade("slab_band", Building.Finish.GLASS, Building.WindowStyle.RIBBON,
		Color(0.10, 0.11, 0.13), Color(0.10, 0.12, 0.14), Color(0.08, 0.08, 0.09), 0.1, 4.0, 1.35))
	tm.glow_material = _glow_material("slab", Color(0.12, 0.13, 0.15), 0, 1.0, 3.0, 0.1, 2.0)
	var plan := TowerMesh.chamfered(38.0, 58.0, 4.0)
	tm.prism(plan, 0.0, 246.0, "granite", false, false)
	tm.prism(plan, 246.0, 260.9, "band")
	tm.loft("glow", TowerMesh.inset(plan, -0.12), 253.5, TowerMesh.inset(plan, -0.12), 254.7, CROWN_WHITE, 1.0, false, false)
	_roof_lights(tm, plan, 262.3, 2)
	detail.box("metal", Vector3(0.0, 263.0, 8.0), Vector3(14.0, 3.0, 10.0), CONCRETE)
	detail.box("metal", Vector3(0.0, 5.5, -29.8), Vector3(16.0, 0.4, 3.2), DARK_STEEL)


## 229 m. Blue glass faces between granite corner piers, a setback, and an elliptical crown of
## blue glass standing on the roof - lit blue after dark.
static func _ellipse_crown(tm: TowerMesh, detail: TowerMesh) -> void:
	tm.add_facade("glass", _facade("flame_glass", Building.Finish.GLASS, Building.WindowStyle.CURTAIN,
		Color(0.20, 0.28, 0.38), Color(0.26, 0.42, 0.60), Color(0.55, 0.58, 0.62), 0.45, 4.0, 1.5, 6.0))
	tm.add_facade("granite", _facade("flame_granite", Building.Finish.PANELS, Building.WindowStyle.RIBBON,
		Color(0.70, 0.67, 0.62), Color(0.25, 0.34, 0.44), Color(0.42, 0.40, 0.37), 0.4, 4.0, 1.5, 6.0))
	tm.glow_material = _glow_material("flame", Color(0.20, 0.36, 0.60), 1, 1.4, 3.8, 0.45, 20.0)
	var plan := TowerMesh.notched(46.0, 34.0, 4.0)
	tm.prism(plan, 0.0, 196.0, "glass", false, false)
	for s: Vector2 in [Vector2(-1, -1), Vector2(1, -1), Vector2(1, 1), Vector2(-1, 1)]:
		var pier := TowerMesh.moved(TowerMesh.rect(5.2, 5.2), Vector2(s.x * 20.9, s.y * 14.9))
		tm.prism(pier, 0.0, 199.0, "granite", true, true)
	tm.prism(TowerMesh.notched(38.0, 27.0, 3.5), 196.0, 208.0, "glass", false, false)
	tm.loft("glow", TowerMesh.ellipse(14.5, 6.5, 44), 208.0, TowerMesh.ellipse(14.5, 6.5, 44), 228.6, BLUE, 1.0, true)
	tm.slab("metal", TowerMesh.ellipse(14.8, 6.8, 44), 228.6, 229.0, DARK_STEEL)
	tm.light(Vector3(14.6, 229.3, 0.0), RED, 2.2, 2)
	tm.light(Vector3(-14.6, 229.3, 0.0), RED, 2.2, 2)
	detail.box("metal", Vector3(0.0, 6.3, 17.6), Vector3(18.0, 0.35, 3.0), DARK_STEEL)


## The rounded pair's shared look: blue-green glass between rose granite corner piers.
static func _plaza_facades(tm: TowerMesh) -> void:
	tm.add_facade("glass", _facade("plaza_glass", Building.Finish.GLASS, Building.WindowStyle.CURTAIN,
		Color(0.18, 0.27, 0.28), Color(0.28, 0.46, 0.48), Color(0.50, 0.55, 0.55), 0.45, 4.0, 1.5, 6.0))
	tm.add_facade("granite", _facade("plaza_granite", Building.Finish.PANELS, Building.WindowStyle.RIBBON,
		Color(0.68, 0.61, 0.57), Color(0.26, 0.40, 0.42), Color(0.40, 0.36, 0.34), 0.4, 4.0, 1.5, 6.0))
	tm.glow_material = _glow_material("plaza", Color(0.22, 0.34, 0.36), 1, 1.6, 3.0, 0.4, 14.0)


static func _corner_piers(tm: TowerMesh, w: float, d: float, n: float, top: float) -> void:
	for s: Vector2 in [Vector2(-1, -1), Vector2(1, -1), Vector2(1, 1), Vector2(-1, 1)]:
		var c := Vector2(s.x * (w * 0.5 - n * 0.5 + 0.25), s.y * (d * 0.5 - n * 0.5 + 0.25))
		tm.prism(TowerMesh.moved(TowerMesh.rect(n + 0.5, n + 0.5), c), 0.0, top, "granite", true, true)


## 229 m, the taller of the pair: a notched shaft, a setback, and a rounded crown - a glass
## barrel vault across the roof, lit warm - with a finial.
static func _round_crown(tm: TowerMesh, detail: TowerMesh) -> void:
	_plaza_facades(tm)
	tm.prism(TowerMesh.notched(39.0, 37.0, 5.0), 0.0, 200.0, "glass", false, false)
	_corner_piers(tm, 39.0, 37.0, 5.0, 203.0)
	tm.prism(TowerMesh.notched(33.0, 31.0, 4.5), 200.0, 210.0, "glass", false, false)
	tm.vault("glow", Vector3(0.0, 210.0, 0.0), 30.0, 14.5, WARM, 1.0, 18)
	tm.mast(Vector3(0.0, 224.2, 0.0), 4.8, 0.45, 0.12, WHITE_METAL, 8)
	tm.light(Vector3(0.0, 229.2, 0.0), RED, 2.2, 2)
	tm.light(Vector3(15.0, 210.5, 0.0), RED, 1.6, 0)
	tm.light(Vector3(-15.0, 210.5, 0.0), RED, 1.6, 0)
	detail.box("metal", Vector3(0.0, 6.2, -18.9), Vector3(14.0, 0.35, 3.0), DARK_STEEL)


## 176 m, the shorter of the pair: the same notched shaft and piers with a flat top and a
## granite penthouse.
static func _plaza_one(tm: TowerMesh, detail: TowerMesh) -> void:
	_plaza_facades(tm)
	tm.prism(TowerMesh.notched(34.0, 32.0, 4.5), 0.0, 166.0, "glass", false, false)
	_corner_piers(tm, 34.0, 32.0, 4.5, 169.0)
	tm.prism(TowerMesh.notched(26.0, 24.0, 3.0), 166.0, 174.9, "granite", true, true)
	_roof_lights(tm, TowerMesh.rect(26.0, 24.0), 176.2)
	detail.box("metal", Vector3(0.0, 177.3, 0.0), Vector3(10.0, 2.0, 8.0), CONCRETE)


## 220 m and 192 m. Two faceted red granite towers, eight-sided, with sloping glass tops that face
## away from each other.
static func _faceted_twins(tm: TowerMesh, detail: TowerMesh) -> void:
	tm.add_facade("granite", _facade("facet_granite", Building.Finish.PANELS, Building.WindowStyle.RIBBON,
		Color(0.52, 0.31, 0.25), Color(0.30, 0.24, 0.18), Color(0.30, 0.18, 0.15), 0.4, 4.0, 1.5, 6.0))
	tm.glow_material = _glow_material("facet", Color(0.30, 0.25, 0.20), 2, 2.0, 2.6, 0.35, 12.0)
	var north := Vector2(0.0, -20.5)
	var south := Vector2(0.0, 20.5)
	tm.prism(TowerMesh.moved(TowerMesh.chamfered(38.0, 38.0, 10.0), north), 0.0, 196.0, "granite", false, false)
	var nd := Vector2(-0.707, -0.707) * 0.33
	tm.sloped(TowerMesh.moved(TowerMesh.chamfered(34.0, 34.0, 9.0), north), 196.0, 214.0, nd, north, "granite", Color(WARM.r, WARM.g, WARM.b, 0.8))
	tm.prism(TowerMesh.moved(TowerMesh.chamfered(36.0, 36.0, 9.5), south), 0.0, 170.0, "granite", false, false)
	var sd := Vector2(0.707, 0.707) * 0.33
	tm.sloped(TowerMesh.moved(TowerMesh.chamfered(32.0, 32.0, 8.5), south), 170.0, 186.5, sd, south, "granite", Color(WARM.r, WARM.g, WARM.b, 0.8))
	tm.light(Vector3(north.x - 11.0, 220.2, north.y - 11.0), RED, 2.2, 2)
	tm.light(Vector3(south.x + 10.0, 192.2, south.y + 10.0), RED, 2.2, 2)
	detail.box("metal", Vector3(0.0, 5.0, 0.0), Vector3(20.0, 0.4, 3.6), DARK_STEEL)


## 224 m. A flat-topped slab of dark red-brown granite, corners cut, bronze glass set deep.
static func _bronze_slab(tm: TowerMesh, detail: TowerMesh) -> void:
	tm.add_facade("granite", _facade("bronze_granite", Building.Finish.PANELS, Building.WindowStyle.PUNCHED,
		Color(0.30, 0.19, 0.15), Color(0.30, 0.23, 0.16), Color(0.18, 0.12, 0.10), 0.4, 4.0, 1.55, 0.0, 10.0))
	var plan := TowerMesh.chamfered(38.0, 52.0, 5.0)
	tm.prism(plan, 0.0, 222.9, "granite")
	_roof_lights(tm, plan, 224.3, 2)
	detail.box("metal", Vector3(0.0, 225.4, 6.0), Vector3(16.0, 2.2, 12.0), CONCRETE)
	# A red steel sculpture of arches in the plaza by the entrance.
	for i in 4:
		detail.box("metal", Vector3(-8.0 + float(i) * 5.0, 3.0, -32.0), Vector3(0.6, 6.0, 0.6), Color(0.62, 0.12, 0.08))
	detail.box("metal", Vector3(-0.5, 6.2, -32.0), Vector3(16.0, 0.6, 0.6), Color(0.62, 0.12, 0.08))


## 191 m. Near-black reflective glass, notched corners, stepping in twice at the top.
static func _dark_glass(tm: TowerMesh, detail: TowerMesh) -> void:
	tm.add_facade("glass", _facade("dark_glass", Building.Finish.GLASS, Building.WindowStyle.CURTAIN,
		Color(0.07, 0.09, 0.11), Color(0.10, 0.14, 0.18), Color(0.05, 0.06, 0.07), 0.42, 4.0, 1.5, 6.0))
	tm.prism(TowerMesh.notched(38.0, 42.0, 3.5), 0.0, 176.0, "glass", false, false)
	tm.prism(TowerMesh.notched(33.0, 37.0, 4.0), 176.0, 184.0, "glass", false, false)
	var top := TowerMesh.notched(27.0, 31.0, 4.5)
	tm.prism(top, 184.0, 189.9, "glass")
	_roof_lights(tm, TowerMesh.rect(27.0, 31.0), 191.3)
	detail.box("metal", Vector3(0.0, 192.0, 0.0), Vector3(9.0, 2.0, 12.0), CONCRETE)


## 112 m. Five mirrored bronze-glass drums - a big one in the middle, four around it - on a
## concrete podium, with glass lifts running up the outside of the middle drum and a lit
## revolving-restaurant band near its top.
static func _five_drums(tm: TowerMesh, detail: TowerMesh) -> void:
	tm.add_facade("mirror", _facade("drums_mirror", Building.Finish.GLASS, Building.WindowStyle.RIBBON,
		Color(0.20, 0.17, 0.14), Color(0.44, 0.36, 0.26), Color(0.30, 0.25, 0.20), 0.5, 3.2, 1.4, 0.0, 0.0, Color(1.0, 0.86, 0.62)))
	tm.add_facade("podium", _facade("drums_podium", Building.Finish.PANELS, Building.WindowStyle.RIBBON,
		Color(0.60, 0.58, 0.55), Color(0.25, 0.28, 0.30), Color(0.40, 0.39, 0.37), 0.4, 5.0, 2.4))
	tm.glow_material = _glow_material("drums", Color(0.36, 0.30, 0.22), 1, 1.4, 3.0, 0.4, 4.0)
	tm.prism(TowerMesh.chamfered(49.0, 57.0, 2.0), 0.0, 10.0, "podium", true)
	tm.prism(TowerMesh.circle(12.5, 44), 10.0, 110.9, "mirror")
	for s: Vector2 in [Vector2(-1, -1), Vector2(1, -1), Vector2(1, 1), Vector2(-1, 1)]:
		var c := Vector2(s.x * 15.0, s.y * 19.5)
		tm.prism(TowerMesh.moved(TowerMesh.circle(8.8, 36), c), 10.0, 102.9, "mirror")
		tm.light(Vector3(c.x, 104.3, c.y), RED, 1.6, 0)
	tm.loft("glow", TowerMesh.circle(12.68, 44), 97.0, TowerMesh.circle(12.68, 44), 100.6, WARM, 1.0, false, false)
	# The lifts: glass shafts on the middle drum facing east and west, the cars lit inside.
	for side: float in [-1.0, 1.0]:
		var x := side * 13.0
		tm.box("glow", Vector3(x, 56.0, 0.0), Vector3(1.0, 90.0, 2.4), ICE, 0.0, 0.25)
		for car in 3:
			tm.box("glow", Vector3(x + side * 0.1, 22.0 + float(car) * 27.0 + side * 6.0, 0.0), Vector3(1.0, 3.0, 2.0), WARM, 0.0, 1.0)
	tm.light(Vector3(0.0, 112.4, 0.0), RED, 2.0, 2)
	detail.box("metal", Vector3(0.0, 4.5, -29.0), Vector3(20.0, 0.4, 3.0), DARK_STEEL)


## 213 m, twice. Two identical towers of black granite and near-black glass, flat topped, side by
## side across a plaza.
static func _black_twins(tm: TowerMesh, detail: TowerMesh) -> void:
	tm.add_facade("black", _facade("twin_black", Building.Finish.PANELS, Building.WindowStyle.NARROW,
		Color(0.055, 0.055, 0.06), Color(0.07, 0.08, 0.09), Color(0.03, 0.03, 0.035), 0.36, 4.0, 1.3, 0.0, 8.0))
	for z: float in [-25.6, 25.6]:
		var plan := TowerMesh.moved(TowerMesh.rect(42.0, 40.0), Vector2(0.0, z))
		tm.prism(plan, 0.0, 211.9, "black")
		_roof_lights(tm, plan, 213.3)
		detail.box("metal", Vector3(6.0, 214.0, z), Vector3(14.0, 2.2, 10.0), CONCRETE)
	# The plaza between them: a round fountain basin and a low glass pavilion.
	detail.loft("metal", TowerMesh.circle(6.0, 28), 0.0, TowerMesh.circle(6.0, 28), 0.7, CONCRETE, 0.0, true, false)
	detail.loft("metal", TowerMesh.circle(5.4, 28), 0.7, TowerMesh.circle(5.4, 28), 0.72, Color(0.14, 0.30, 0.40), 0.0, true, false)
	detail.box("glow", Vector3(-12.0, 2.5, 0.0), Vector3(12.0, 5.0, 6.0), WARM, 0.0, 0.5)


## 218 m. A rose granite shaft with notched corners under a stepped pyramid of glass, lit green.
static func _pyramid_crown(tm: TowerMesh, detail: TowerMesh) -> void:
	tm.add_facade("granite", _facade("pyramid_granite", Building.Finish.PANELS, Building.WindowStyle.RIBBON,
		Color(0.60, 0.47, 0.43), Color(0.24, 0.38, 0.40), Color(0.35, 0.28, 0.26), 0.42, 4.0, 1.5, 6.0))
	tm.glow_material = _glow_material("pyramid", Color(0.24, 0.34, 0.34), 1, 1.5, 3.2, 0.4, 6.0)
	tm.prism(TowerMesh.notched(42.0, 42.0, 4.5), 0.0, 190.0, "granite", false, false)
	var steps := [[36.0, 190.0, 197.0], [30.0, 197.0, 203.0], [24.0, 203.0, 208.0], [18.0, 208.0, 212.0]]
	for s: Array in steps:
		var o := TowerMesh.notched(s[0], s[0], 3.0)
		tm.loft("glow", o, s[1], o, s[2], GREEN, 0.9, true)
	tm.spike("glow", TowerMesh.rect(12.0, 12.0), 212.0, Vector3(0.0, 218.0, 0.0), GREEN, 1.0)
	tm.light(Vector3(0.0, 218.3, 0.0), RED, 2.2, 2)
	detail.box("metal", Vector3(0.0, 6.2, 21.9), Vector3(16.0, 0.35, 3.0), DARK_STEEL)


## 163 m. Red granite, corners cut, under a pyramid roof of dark glass with a spire.
static func _spire_pyramid(tm: TowerMesh, detail: TowerMesh) -> void:
	tm.add_facade("granite", _facade("spire_granite", Building.Finish.PANELS, Building.WindowStyle.RIBBON,
		Color(0.52, 0.34, 0.29), Color(0.18, 0.21, 0.25), Color(0.30, 0.20, 0.17), 0.4, 4.0, 1.5, 6.0))
	tm.glow_material = _glow_material("spire", Color(0.16, 0.18, 0.21), 1, 2.0, 2.4, 0.45, 16.0)
	var plan := TowerMesh.chamfered(36.0, 36.0, 6.0)
	tm.prism(plan, 0.0, 140.0, "granite", false, false)
	tm.spike("glow", plan, 140.0, Vector3(0.0, 156.0, 0.0), WARM, 0.45)
	tm.mast(Vector3(0.0, 154.5, 0.0), 8.5, 0.7, 0.12, WHITE_METAL, 8)
	tm.light(Vector3(0.0, 163.2, 0.0), RED, 2.0, 2)
	detail.box("metal", Vector3(0.0, 6.2, 18.8), Vector3(14.0, 0.35, 2.6), DARK_STEEL)


## 221 m. White mullions over pale glass on faces that bow outward, corners cut, and a top that
## steps back in three curved tiers with a lit band.
static func _curved_white(tm: TowerMesh, detail: TowerMesh) -> void:
	# White metal spandrels between ribbons of pale glass: as a curtain wall the panes are 90 % of
	# the face and the "white" tower rendered as a dark glass one.
	tm.add_facade("white", _facade("curve_white", Building.Finish.PANELS, Building.WindowStyle.RIBBON,
		Color(0.88, 0.89, 0.90), Color(0.40, 0.52, 0.62), Color(0.95, 0.95, 0.96), 0.45, 4.0, 1.5, 6.0))
	var plan := TowerMesh.bowed(44.0, 40.0, 1.5, 2.0, 4.0)
	tm.prism(plan, 0.0, 196.0, "white", false, false)
	tm.prism(TowerMesh.moved(plan, Vector2.ZERO, Vector2(0.9, 0.9)), 196.0, 204.0, "white", false, false)
	tm.prism(TowerMesh.moved(plan, Vector2.ZERO, Vector2(0.8, 0.8)), 204.0, 211.0, "white", false, false)
	var top := TowerMesh.moved(plan, Vector2.ZERO, Vector2(0.68, 0.68))
	tm.prism(top, 211.0, 219.9, "white")
	tm.loft("glow", TowerMesh.inset(top, -0.12), 216.2, TowerMesh.inset(top, -0.12), 217.6, CROWN_WHITE, 1.0, false, false)
	tm.light(Vector3(0.0, 221.3, 0.0), RED, 2.2, 2)
	detail.box("metal", Vector3(0.0, 6.2, -21.9), Vector3(16.0, 0.35, 3.0), WHITE_METAL)


# --- South Park -------------------------------------------------------------------------------

static func _park_facades(tm: TowerMesh, key: String, glass: Color, tint: Color) -> void:
	tm.add_facade("glass", _facade("park_" + key, Building.Finish.GLASS, Building.WindowStyle.CURTAIN,
		glass, tint, Color(0.74, 0.77, 0.79), 0.55, 3.2, 1.4, 6.0, 0.0, Color(1.0, 0.88, 0.70)))
	tm.add_facade("podium", _facade("park_podium", Building.Finish.PANELS, Building.WindowStyle.RIBBON,
		Color(0.62, 0.61, 0.58), Color(0.26, 0.34, 0.40), Color(0.38, 0.38, 0.37), 0.5, 4.5, 1.8, 6.0))


## 190 m. A slender glass tower whose balconies wind round it floor by floor, so the whole face
## reads as a slow twist; a violet crown.
static func _park_a(tm: TowerMesh, _detail: TowerMesh) -> void:
	_park_facades(tm, "a", Color(0.24, 0.34, 0.38), Color(0.32, 0.46, 0.52))
	tm.glow_material = _glow_material("park_a", Color(0.26, 0.30, 0.40), 1, 1.4, 3.2, 0.4, 3.0)
	tm.prism(TowerMesh.rounded(38.0, 44.0, 3.0, 3), 0.0, 12.0, "podium")
	var plan := TowerMesh.rounded(30.0, 32.0, 4.0, 4)
	tm.prism(plan, 12.0, 186.9, "glass")
	tm.loft("glow", TowerMesh.inset(plan, 1.2), 188.0, TowerMesh.inset(plan, 1.2), 190.0, VIOLET, 1.0, true, false)
	var perimeter := _perimeter(plan)
	var floor_h := 3.2
	var y := 16.0
	var k := 0
	while y < 184.0:
		var s0 := float(k) * perimeter * 0.021
		tm.balcony(plan, s0, s0 + perimeter * 0.42, y, 1.8, 0.28, WHITE_METAL)
		y += floor_h
		k += 1
	_roof_lights(tm, TowerMesh.rect(26.0, 28.0), 190.3)


## 175 m. Balconies staggered: the east and west faces on one floor, north and south on the next.
static func _park_b(tm: TowerMesh, _detail: TowerMesh) -> void:
	_park_facades(tm, "b", Color(0.22, 0.30, 0.34), Color(0.30, 0.44, 0.50))
	tm.glow_material = _glow_material("park_b", Color(0.22, 0.30, 0.36), 1, 1.4, 3.0, 0.4, 3.0)
	var plan := TowerMesh.rounded(28.0, 30.0, 3.0, 3)
	tm.prism(plan, 0.0, 172.4, "glass")
	tm.loft("glow", TowerMesh.inset(plan, 1.2), 173.5, TowerMesh.inset(plan, 1.2), 175.0, ICE, 1.0, true, false)
	var perimeter := _perimeter(plan)
	var y := 10.0
	var k := 0
	while y < 170.0:
		var start := perimeter * (0.0 if k % 2 == 0 else 0.25)
		for half in 2:
			var s0 := start + float(half) * perimeter * 0.5
			tm.balcony(plan, s0 + 2.0, s0 + perimeter * 0.25 - 2.0, y, 1.6, 0.26, Color(0.80, 0.81, 0.82))
		y += 3.2
		k += 1
	_roof_lights(tm, TowerMesh.rect(24.0, 26.0), 175.3)


## 160 m. Plain glass with vertical fins and a lit top.
static func _park_c(tm: TowerMesh, detail: TowerMesh) -> void:
	_park_facades(tm, "c", Color(0.28, 0.36, 0.40), Color(0.34, 0.48, 0.54))
	tm.glow_material = _glow_material("park_c", Color(0.24, 0.32, 0.38), 1, 1.4, 3.0, 0.4, 3.0)
	var plan := TowerMesh.rounded(28.0, 28.0, 3.0, 3)
	tm.prism(plan, 0.0, 156.9, "glass")
	tm.loft("glow", TowerMesh.inset(plan, 1.0), 158.0, TowerMesh.inset(plan, 1.0), 160.0, WARM, 1.0, true, false)
	tm.fins(TowerMesh.rect(28.0, 28.0), 8.0, 156.0, 4.2, 0.6, 0.35, WHITE_METAL, "metal", 0.0, 3.2)
	_roof_lights(tm, TowerMesh.rect(24.0, 24.0), 160.3)
	detail.box("metal", Vector3(0.0, 6.0, 14.6), Vector3(12.0, 0.35, 2.4), DARK_STEEL)


## 145 m. Square, corners cut, balconies boxed out on alternate floors.
static func _park_d(tm: TowerMesh, _detail: TowerMesh) -> void:
	_park_facades(tm, "d", Color(0.30, 0.34, 0.36), Color(0.36, 0.46, 0.50))
	tm.glow_material = _glow_material("park_d", Color(0.26, 0.30, 0.34), 1, 1.4, 3.0, 0.4, 3.0)
	var plan := TowerMesh.chamfered(30.0, 30.0, 3.0)
	tm.prism(plan, 0.0, 142.4, "glass")
	tm.loft("glow", TowerMesh.inset(plan, 1.2), 143.5, TowerMesh.inset(plan, 1.2), 145.0, BLUE, 1.0, true, false)
	var perimeter := _perimeter(plan)
	var y := 9.0
	var k := 0
	while y < 140.0:
		if k % 2 == 0:
			for q in 4:
				var s0 := perimeter * (float(q) * 0.25 + (0.04 if k % 4 == 0 else 0.12))
				tm.balcony(plan, s0, s0 + perimeter * 0.1, y, 1.7, 0.3, Color(0.78, 0.77, 0.74))
		y += 3.2
		k += 1
	_roof_lights(tm, TowerMesh.rect(26.0, 26.0), 145.3)


## Three towers of an abandoned project on a shared podium: glass part way up, then bare concrete
## frame - slabs, columns and cores - with a tower crane still standing on the tallest. Dark at
## night but for the crane's beacon.
static func _unfinished(tm: TowerMesh, _detail: TowerMesh) -> void:
	tm.add_facade("glass", _facade("unfinished_glass", Building.Finish.GLASS, Building.WindowStyle.CURTAIN,
		Color(0.22, 0.30, 0.36), Color(0.28, 0.40, 0.48), Color(0.45, 0.47, 0.48), 0.0, 3.3, 1.5))
	tm.add_facade("podium", _facade("unfinished_podium", Building.Finish.PANELS, Building.WindowStyle.RIBBON,
		Color(0.56, 0.55, 0.52), Color(0.16, 0.18, 0.20), Color(0.36, 0.36, 0.35), 0.0, 5.0, 2.4))
	tm.prism(TowerMesh.rect(62.0, 78.0), 0.0, 16.0, "podium", true)
	# [centre, glass top, frame top]
	var towers := [[Vector2(-17.0, -21.0), 104.0, 150.0], [Vector2(17.0, -21.0), 98.0, 140.0], [Vector2(0.0, 19.0), 118.0, 165.0]]
	for t: Array in towers:
		var c: Vector2 = t[0]
		var glass_top: float = t[1]
		var frame_top: float = t[2]
		tm.prism(TowerMesh.moved(TowerMesh.rect(20.0, 20.0), c), 16.0, glass_top, "glass", false, false)
		# The frame: a slab every floor, columns on a grid round the edge, a core up the middle.
		var y := glass_top
		while y <= frame_top + 0.1:
			tm.box("metal", Vector3(c.x, y + 0.18, c.y), Vector3(20.0, 0.36, 20.0), CONCRETE, 0.0, 0.0, false)
			y += 3.3
		for i in 5:
			for j in 5:
				if i != 0 and i != 4 and j != 0 and j != 4:
					continue
				var p := c + Vector2(-9.5 + float(i) * 4.75, -9.5 + float(j) * 4.75)
				tm.box("metal", Vector3(p.x, (glass_top + frame_top) * 0.5, p.y), Vector3(0.8, frame_top - glass_top, 0.8), CONCRETE)
		tm.box("metal", Vector3(c.x, (glass_top + frame_top) * 0.5 + 2.0, c.y), Vector3(6.0, frame_top - glass_top + 4.0, 6.0), CONCRETE, 0.0, 0.0, true)
	# The crane on the tallest: mast, jib, counter-jib, cab.
	var cc := Vector2(0.0, 19.0)
	tm.box("metal", Vector3(cc.x + 7.5, 177.0, cc.y), Vector3(2.0, 24.0, 2.0), CRANE)
	tm.box("metal", Vector3(cc.x + 7.5 - 15.0, 189.2, cc.y), Vector3(42.0, 1.6, 1.6), CRANE)
	tm.box("metal", Vector3(cc.x + 7.5 + 12.0, 189.2, cc.y), Vector3(14.0, 1.4, 1.4), CRANE)
	tm.box("metal", Vector3(cc.x + 7.5 + 17.0, 187.6, cc.y), Vector3(4.0, 3.0, 2.4), CONCRETE)
	tm.box("metal", Vector3(cc.x + 7.5, 190.2, cc.y), Vector3(2.4, 0.4, 2.4), CRANE)
	tm.light(Vector3(cc.x + 7.5, 190.6, cc.y), RED, 2.2, 2)
	tm.light(Vector3(cc.x + 7.5 - 35.5, 190.0, cc.y), RED, 1.6, 0)


static func _perimeter(outline: PackedVector2Array) -> float:
	var total := 0.0
	for i in outline.size():
		total += outline[i].distance_to(outline[(i + 1) % outline.size()])
	return total
