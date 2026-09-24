class_name LandmarkMasjidOmar
extends RefCounted
## Masjid Omar ibn Al-Khattab, 1025 W Exposition Blvd, Los Angeles - a replica of the real
## building (owner, 2026-09-24: "make masjid omar ibn khattab way more detailed and 1:1 accurate",
## with six photos: the aerial from the south, the street elevation, the entrance, the stairs
## out to Exposition and the prayer hall).
##
## The footprint is the real one, off OpenStreetMap way 412475901 (building=mosque, height 15.7,
## start_date 1993), converted to metres: 49.2 m east-west, a tall west block 17.9 x 18.7 m with
## the prayer hall in it, and a lower east wing 31.3 x 21.3 m that stands 2.6 m further out to the
## street, carrying the green dome. The minaret rises from the wing's roof where the two meet,
## over the entrance: three arched doors with green surrounds and fanlights under a green
## awning, up a flight of grey marble steps with black nosing strips and black handrails, straight
## off the Exposition pavement. What the photos show and this builds:
##
##   - the west block: white, a green cornice and a crenellated parapet, five tall round-arched
##     bays a face filled with green lattice screens (masjid_lattice.gdshader) over dark glass;
##   - the east wing: a row of narrow arched windows with green surrounds and lattice, a green
##     band and the parapet of little round-topped merlons from the entrance photo;
##   - the dome: sea green, 24 ribs, on a short white drum, a gold finial and crescent, its apex at
##     the real 15.7 m above the street;
##   - the minaret: a square white shaft, a balcony, a white octagonal tier, a green lantern of
##     lattice openings, a green cap and a crescent;
##   - the site: raised on a plinth behind a black steel fence, palms and planting along the
##     frontage, the car park on the west side with a ramp up from the street.
##
## Inside (the owner's interior photo): the prayer hall is the west block. Red prayer carpet laid
## in rows toward the qibla (masjid_carpet.gdshader), cream walls, a gallery on square columns
## round all four sides with a white parapet, the tall windows showing as two tiers of lattice
## arches, recessed lights in the gallery soffit, a large crystal chandelier from the ceiling, the
## mihrab on the north wall - the nearest wall to the qibla, which from Los Angeles is about 24
## degrees east of north - and a wooden minbar beside it. A stair under the west gallery climbs to
## it. The entrance lobby opens into the hall and, east, into a second carpeted hall under the
## dome, which is hollow: you look up into the drum and the dome from inside.
##
## It is a sanctuary: the guns will not fire at it, through it or from its grounds, rockets that
## reach it fizzle, and nothing marks it (see Sanctuary). The zone is added by the far build too.
##
## Placement: the parcel the old Masjid Al Noor stood on (Landmarks.all()), in a 103 x 91 m block
## whose south pavement plays Exposition Boulevard, so the building faces the street it faces in
## life. REAL_LATLON is kept for the 1:1 downtown re-lay, which will move it to its real block.
##
## Frame: +X east, +Z south, y 0 at the prayer-hall floor, the origin at the centre of the real
## footprint's bounding box. The site is BLD_OFFSET from the landmark anchor.
##
## The meshes are built once, merged one surface per material, and cached; a chunk streaming back
## in costs only the node and shape set-up.

## The real building, for the re-lay (Nominatim, OSM way 412475901).
const REAL_LATLON := Vector2(34.018543, -118.292465)
const OSM_WAY := 412475901

# --- The site -----------------------------------------------------------------------------------

## The building frame's origin measured from the landmark anchor: the east wing's street face
## then stands BLD_OFFSET.z + E_Z1 = 41.7 m south of the anchor, and the foot of the entrance
## flight lands on the south pavement of the block, 46.5 m south of it.
const BLD_OFFSET := Vector3(0.0, 0.0, 30.97)
## The prayer-hall floor above the terrain sampled at the anchor. The block lays a lawn over its
## whole area whose blades reach about 1.29 m (the grass multimesh's tallest), so the
## plinth the site stands on is 1.30 up and the floor one step above it.
const FLOOR_LIFT := 1.46
## Plinth top in the building frame (one step below the floor), and the block's pavement.
const SITE_Y := -0.16
const PAVE_Y := 0.29 - FLOOR_LIFT
## The fenced parcel, in the building frame.
const SITE_X0 := -44.0
const SITE_X1 := 30.0
const SITE_Z0 := -18.97
const SITE_Z1 := 15.33
## The car park on the west side and its ramp up from the street.
const PARK_X1 := -26.2
const RAMP_X0 := -44.0
const RAMP_X1 := -38.0
const RAMP_Z0 := 7.0

# --- The footprint (real, OSM) ----------------------------------------------------------------

const W_X0 := -24.60
const W_X1 := -6.71
const W_Z0 := -10.73
const W_Z1 := 8.02
const E_X0 := -6.71
const E_X1 := 24.60
const E_Z0 := -10.59
const E_Z1 := 10.73

# --- Heights ----------------------------------------------------------------------------------

## Wall thickness, in metres.
const WALL_T := 0.45
## The west block: wall top under the green cornice, the cornice, the parapet wall and merlons.
const W_WALL := 11.3
const W_CORNICE := 0.55
const W_PARAPET := 0.7
const W_MERLON := 0.75
## Inside the west block: the ceiling, the gallery floor's top and thickness, and its depth
## out from the walls.
const HALL_CEIL := 10.6
const GALLERY_Y := 4.9
const GALLERY_T := 0.35
const GALLERY_D := 3.0
## The east wing: wall top, the green band, the round-topped merlons, the inside ceiling.
const E_WALL := 5.9
const E_BAND := 0.5
const E_MERLON := 0.7
const E_CEIL := 5.3

# --- Openings ---------------------------------------------------------------------------------

## The tall lattice bays of the west block: width, sill and the arch's springing line.
const BAY_W := 2.2
const BAY_SILL := 0.9
const BAY_SPRING := 9.5
## The east wing's windows.
const WIN_W := 1.2
const WIN_SILL := 1.1
const WIN_SPRING := 3.5
## The entrance: three arched doors on the wing's street face at the west end.
const DOOR_X := [-5.45, -3.05, -0.65]
const DOOR_W := [1.5, 2.0, 1.5]
const DOOR_SPRING := 2.6
## The door from the lobby into the prayer hall, in the west block's east wall.
const HALL_DOOR_Z := 3.2
const HALL_DOOR_W := 2.4

# --- Dome and minaret ---------------------------------------------------------------------------

const DOME_C := Vector2(10.0, 0.0)
const DRUM_R := 6.6
const DRUM_TOP := 7.5
const DOME_R := 6.5
const DOME_H := 6.8
const DOME_RIBS := 24
const MIN_C := Vector2(-3.05, 7.3)
const MIN_W := 2.6
const MIN_SHAFT_TOP := 19.2
const MIN_BALC := 3.6
const MIN_TIER_TOP := 21.6
const MIN_LANTERN_TOP := 24.0
const MIN_CAP_TOP := 26.2

# --- Entrance flight ----------------------------------------------------------------------------

const PORCH_D := 1.2
const STEPS := 9
const STEP_RUN := 0.4
const STEP_RISE := -PAVE_Y / float(STEPS)
const STAIR_X0 := -6.71
const STAIR_X1 := 0.6

## The interior lights' energy (the chandelier and the soffit lights read as the sources).
const HALL_LIGHT := 1.6

static var _mesh_ext: ArrayMesh
static var _mesh_int: ArrayMesh
static var _faces: PackedVector3Array
static var _far_mesh: ArrayMesh


static func build(anchor: Vector2, parent: Node3D, statics: StaticBody3D, plan: CityPlan, detailed: bool) -> void:
	var ground: float = plan.height_at(anchor) if plan != null else 0.0
	var root := Node3D.new()
	root.name = "MasjidOmar"
	root.position = Vector3(anchor.x, ground + FLOOR_LIFT, anchor.y) + BLD_OFFSET
	parent.add_child(root)
	# The zone covers the fenced grounds and the airspace over the minaret.
	Sanctuary.add_zone(root, Vector3((SITE_X0 + SITE_X1) * 0.5, 13.0, (SITE_Z0 + SITE_Z1 + 0.2) * 0.5),
		Vector3((SITE_X1 - SITE_X0) * 0.5 + 0.5, 16.0, (SITE_Z1 + 0.2 - SITE_Z0) * 0.5 + 0.5))
	if not detailed:
		if _far_mesh == null:
			_far_mesh = _build_far()
		var far := MeshInstance3D.new()
		far.mesh = _far_mesh
		root.add_child(far)
		return
	if _mesh_ext == null:
		_build_meshes()
	var ext := MeshInstance3D.new()
	ext.name = "Exterior"
	ext.mesh = _mesh_ext
	root.add_child(ext)
	var inner := MeshInstance3D.new()
	inner.name = "Interior"
	inner.mesh = _mesh_int
	inner.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	# Nothing inside can be seen from further off than this, through a door or a lattice.
	inner.visibility_range_end = 140.0
	root.add_child(inner)
	if statics != null:
		var body := StaticBody3D.new()
		body.name = "MasjidBody"
		body.collision_layer = statics.collision_layer
		body.collision_mask = statics.collision_mask
		body.add_to_group(Sanctuary.BODY_GROUP)
		var cs := CollisionShape3D.new()
		var shape := ConcavePolygonShape3D.new()
		shape.backface_collision = true
		shape.set_faces(_faces)
		cs.shape = shape
		body.add_child(cs)
		root.add_child(body)
	_plant(root)
	_lights(root)


# --- Materials ----------------------------------------------------------------------------------

static func _materials() -> Dictionary:
	var m := {}
	m["stucco"] = PropFactory.pbr("plaster_white", 2.2, Color(0.97, 0.96, 0.93))
	m["stucco_in"] = PropFactory.pbr("plaster_white", 2.2, Color(0.97, 0.93, 0.84))
	m["green"] = _std(Color(0.09, 0.29, 0.21), 0.2, 0.36)
	var dome := _std(Color(0.26, 0.58, 0.50), 0.15, 0.24)
	dome.clearcoat_enabled = true
	dome.clearcoat = 0.7
	dome.clearcoat_roughness = 0.12
	m["dome"] = dome
	var lattice := ShaderMaterial.new()
	lattice.shader = load("res://shaders/masjid_lattice.gdshader")
	m["lattice"] = lattice
	var glass := _std(Color(0.06, 0.08, 0.08, 0.38), 0.3, 0.05)
	glass.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	glass.cull_mode = BaseMaterial3D.CULL_DISABLED
	m["glass"] = glass
	var marble := ShaderMaterial.new()
	marble.shader = load("res://shaders/masjid_marble.gdshader")
	m["marble"] = marble
	m["black"] = _std(Color(0.025, 0.025, 0.03), 0.6, 0.4)
	var carpet := ShaderMaterial.new()
	carpet.shader = load("res://shaders/masjid_carpet.gdshader")
	# Rows are measured back from the qibla wall's inner face (UV v is the frame's z).
	carpet.set_shader_parameter("origin", Vector2(0.0, W_Z0 + WALL_T))
	m["carpet"] = carpet
	var carpet2 := carpet.duplicate() as ShaderMaterial
	carpet2.set_shader_parameter("origin", Vector2(0.0, E_Z0 + WALL_T))
	m["carpet2"] = carpet2
	m["wood"] = PropFactory.pbr("planks", 1.2, Color(0.62, 0.38, 0.22))
	m["gold"] = _std(Color(0.83, 0.64, 0.28), 1.0, 0.26)
	var crystal := _std(Color(1.0, 0.97, 0.92), 0.0, 0.05)
	crystal.emission_enabled = true
	crystal.emission = Color(1.0, 0.9, 0.72)
	crystal.emission_energy_multiplier = 2.4
	m["crystal"] = crystal
	var lamp := _std(Color(1.0, 0.95, 0.85), 0.0, 0.3)
	lamp.emission_enabled = true
	lamp.emission = Color(1.0, 0.9, 0.74)
	lamp.emission_energy_multiplier = 3.0
	m["lamp"] = lamp
	m["paving"] = PropFactory.pbr("sidewalk", 3.0, Color(0.92, 0.90, 0.86))
	m["asphalt"] = PropFactory.pbr("asphalt", 5.0, Color(0.84, 0.84, 0.88))
	m["soil"] = _std(Color(0.19, 0.13, 0.09), 0.0, 1.0)
	m["paint"] = _std(Color(0.92, 0.92, 0.88), 0.0, 0.7)
	m["red"] = _std(Color(0.42, 0.07, 0.07), 0.0, 0.6)
	return m


static func _std(c: Color, metallic: float, rough: float) -> StandardMaterial3D:
	var mat := StandardMaterial3D.new()
	mat.albedo_color = c
	mat.metallic = metallic
	mat.roughness = rough
	return mat


# --- Building the meshes ------------------------------------------------------------------------

static func _build_meshes() -> void:
	var mats := _materials()
	var ext := _Kit.new()
	var inner := _Kit.new()
	_site(ext)
	_west_block(ext, inner)
	_east_wing(ext, inner)
	_entrance(ext, inner)
	_dome(ext, inner)
	_minaret(ext)
	_hall(inner)
	_lobby_and_domed_hall(inner)
	_mesh_ext = ext.commit(mats)
	_mesh_int = inner.commit(mats)
	_faces = ext.faces
	_faces.append_array(inner.faces)


## The far copy: the plinth, the two blocks, the drum, the dome and the minaret. No openings,
## no interior, no collision; about 900 triangles.
static func _build_far() -> ArrayMesh:
	var mats := _materials()
	var k := _Kit.new()
	k.box("paving", Vector3((SITE_X0 + SITE_X1) * 0.5, (SITE_Y + PAVE_Y - 0.6) * 0.5, (SITE_Z0 + SITE_Z1) * 0.5), Vector3(SITE_X1 - SITE_X0, SITE_Y - PAVE_Y + 0.6, SITE_Z1 - SITE_Z0), false)
	k.box("stucco", Vector3((W_X0 + W_X1) * 0.5, (W_WALL + W_CORNICE + W_PARAPET) * 0.5, (W_Z0 + W_Z1) * 0.5), Vector3(W_X1 - W_X0, W_WALL + W_CORNICE + W_PARAPET, W_Z1 - W_Z0), false)
	_band_ring(k, "green", Rect2(W_X0, W_Z0, W_X1 - W_X0, W_Z1 - W_Z0), W_WALL, W_CORNICE, 0.6)
	k.box("stucco", Vector3((E_X0 + E_X1) * 0.5, (E_WALL + E_BAND) * 0.5, (E_Z0 + E_Z1) * 0.5), Vector3(E_X1 - E_X0, E_WALL + E_BAND, E_Z1 - E_Z0), false)
	k.cyl("stucco", Vector3(DOME_C.x, E_WALL, DOME_C.y), DRUM_R, DRUM_R, DRUM_TOP - E_WALL, 16, false, false)
	var prof := PackedVector2Array()
	for i in 7:
		var a := PI * 0.5 * float(i) / 6.0
		prof.append(Vector2(DOME_R * cos(a), DOME_H * sin(a)))
	k.revolve("dome", Vector3(DOME_C.x, DRUM_TOP, DOME_C.y), prof, 16, true, false)
	k.box("stucco", Vector3(MIN_C.x, (E_WALL + MIN_TIER_TOP) * 0.5, MIN_C.y), Vector3(MIN_W, MIN_TIER_TOP - E_WALL, MIN_W), false)
	k.cyl("green", Vector3(MIN_C.x, MIN_TIER_TOP, MIN_C.y), 1.05, 1.05, MIN_LANTERN_TOP - MIN_TIER_TOP, 8, false, false)
	k.cyl("green", Vector3(MIN_C.x, MIN_LANTERN_TOP, MIN_C.y), 1.2, 0.05, MIN_CAP_TOP - MIN_LANTERN_TOP, 8, false, false)
	return k.commit(mats)


# --- The site ----------------------------------------------------------------------------------

static func _site(k: _Kit) -> void:
	var bottom := PAVE_Y - 0.8
	var h := SITE_Y - bottom
	var cy := (SITE_Y + bottom) * 0.5
	# The plinth, in four pieces round the entrance flight and the ramp.
	var pieces := [
		[RAMP_X1, STAIR_X0, SITE_Z0, SITE_Z1],
		[STAIR_X1, SITE_X1, SITE_Z0, SITE_Z1],
		[STAIR_X0, STAIR_X1, SITE_Z0, E_Z1 + PORCH_D],
		[RAMP_X0, RAMP_X1, SITE_Z0, RAMP_Z0],
	]
	for p in pieces:
		k.box("stucco", Vector3((p[0] + p[1]) * 0.5, cy, (p[2] + p[3]) * 0.5), Vector3(p[1] - p[0], h, p[3] - p[2]), true, false, true)
	# The surfaces laid on it: the car park, the walks round the building, the planting beds.
	var top := SITE_Y + 0.012
	k.flat("asphalt", Rect2(RAMP_X0, SITE_Z0, PARK_X1 - RAMP_X0, RAMP_Z0 - SITE_Z0), top)
	k.flat("asphalt", Rect2(RAMP_X1, RAMP_Z0, PARK_X1 - RAMP_X1, SITE_Z1 - RAMP_Z0), top)
	# Parking bays: stripes every 2.7 m along the north edge and the west side of the building.
	var x := RAMP_X0 + 2.0
	while x < PARK_X1 - 1.0:
		k.flat("paint", Rect2(x - 0.06, SITE_Z0 + 0.4, 0.12, 5.2), top + 0.004)
		x += 2.7
	var z := SITE_Z0 + 8.5
	while z < RAMP_Z0 - 0.5:
		k.flat("paint", Rect2(PARK_X1 - 5.6, z - 0.06, 5.2, 0.12), top + 0.004)
		z += 2.7
	k.flat("paving", Rect2(PARK_X1, SITE_Z0, SITE_X1 - PARK_X1, W_Z0 - SITE_Z0), top)
	k.flat("paving", Rect2(PARK_X1, W_Z0, W_X0 - PARK_X1, SITE_Z1 - W_Z0), top)
	k.flat("paving", Rect2(E_X1, E_Z0, SITE_X1 - E_X1, E_Z1 - E_Z0), top)
	# The front: a walk along the building, then the beds up to the fence.
	k.flat("paving", Rect2(W_X0, W_Z1, W_X1 - W_X0, 1.3), top)
	k.flat("soil", Rect2(W_X0 - 1.0, W_Z1 + 1.3, STAIR_X0 - W_X0 + 1.0, SITE_Z1 - W_Z1 - 1.5), top + 0.03)
	k.flat("paving", Rect2(STAIR_X1, E_Z1, E_X1 - STAIR_X1, 1.3), top)
	k.flat("soil", Rect2(STAIR_X1, E_Z1 + 1.3, SITE_X1 - STAIR_X1 - 0.4, SITE_Z1 - E_Z1 - 1.5), top + 0.03)
	k.flat("paving", Rect2(E_X1, E_Z1, SITE_X1 - E_X1, 1.3), top)
	# Bed kerbs.
	k.box("stucco", Vector3((W_X0 - 1.0 + STAIR_X0) * 0.5, top + 0.12, W_Z1 + 1.3), Vector3(STAIR_X0 - W_X0 + 1.0, 0.24, 0.14), false)
	k.box("stucco", Vector3((STAIR_X1 + SITE_X1 - 0.4) * 0.5, top + 0.12, E_Z1 + 1.3), Vector3(SITE_X1 - 0.4 - STAIR_X1, 0.24, 0.14), false)
	# The ramp from the street into the car park.
	var rise := SITE_Y - PAVE_Y
	var run := SITE_Z1 + 0.2 - RAMP_Z0
	var slope := atan2(rise, run)
	var ramp_len := sqrt(rise * rise + run * run)
	var xf := Transform3D(Basis(Vector3.RIGHT, slope), Vector3((RAMP_X0 + RAMP_X1) * 0.5, (SITE_Y + PAVE_Y) * 0.5 - 0.15, (RAMP_Z0 + SITE_Z1 + 0.2) * 0.5))
	k.obox("asphalt", xf, Vector3(RAMP_X1 - RAMP_X0, 0.3, ramp_len), true)
	_fence(k)


## The black steel fence on the plinth's edge, open at the entrance flight and the ramp.
static func _fence(k: _Kit) -> void:
	var y0 := SITE_Y
	var runs := [
		[Vector3(RAMP_X1, y0, SITE_Z1), Vector3(STAIR_X0, y0, SITE_Z1)],
		[Vector3(STAIR_X1, y0, SITE_Z1), Vector3(SITE_X1, y0, SITE_Z1)],
		[Vector3(SITE_X1, y0, SITE_Z1), Vector3(SITE_X1, y0, SITE_Z0)],
		[Vector3(SITE_X1, y0, SITE_Z0), Vector3(SITE_X0, y0, SITE_Z0)],
		[Vector3(SITE_X0, y0, SITE_Z0), Vector3(SITE_X0, y0, RAMP_Z0 - 0.5)],
		# Along both sides of the entrance flight, falling with it.
	]
	for r in runs:
		_fence_run(k, r[0], r[1], 1.8)
	# The stair cheeks carry a lower rail of their own (the handrails), see _entrance().


static func _fence_run(k: _Kit, a: Vector3, b: Vector3, h: float) -> void:
	var d := b - a
	var length := d.length()
	if length < 0.3:
		return
	var along := d / length
	var yaw := atan2(-along.x, -along.z)
	var basis := Basis(Vector3.UP, yaw)
	var mid := (a + b) * 0.5
	# Rails top and bottom, posts every 2.4 m, pickets every 0.13 m with pointed heads.
	for ry in [0.12, h - 0.1]:
		k.obox("black", Transform3D(basis, mid + Vector3(0.0, ry, 0.0)), Vector3(0.05, 0.05, length), false)
	var n_posts := int(ceil(length / 2.4))
	for i in n_posts + 1:
		var p := a + along * (length * float(i) / float(n_posts))
		k.box("black", p + Vector3(0.0, (h + 0.12) * 0.5, 0.0), Vector3(0.08, h + 0.12, 0.08), false)
	var n := int(length / 0.13)
	for i in n:
		var p := a + along * ((float(i) + 0.5) * length / float(n))
		k.box("black", p + Vector3(0.0, h * 0.5, 0.0), Vector3(0.022, h - 0.02, 0.022), false)
		k.gem("black", p + Vector3(0.0, h + 0.04, 0.0), Vector3(0.03, 0.07, 0.03))
	# One solid collision plane for the whole run.
	var side := basis * Vector3.RIGHT * 0.03
	k.solid_quad(a + side, b + side, b + side + Vector3(0.0, h, 0.0), a + side + Vector3(0.0, h, 0.0))


# --- The west block -----------------------------------------------------------------------------

static func _west_block(k: _Kit, inner: _Kit) -> void:
	var faces := [
		# origin, along, outward normal, length
		[Vector3(W_X0, 0.0, W_Z1), Vector3.RIGHT, Vector3.BACK, W_X1 - W_X0],   # south
		[Vector3(W_X1, 0.0, W_Z0), Vector3.LEFT, Vector3.FORWARD, W_X1 - W_X0], # north
		[Vector3(W_X0, 0.0, W_Z0), Vector3.BACK, Vector3.LEFT, W_Z1 - W_Z0],    # west
	]
	for f in faces:
		var bays := _even_openings(f[3], 5, BAY_W, BAY_SILL, BAY_SPRING)
		_arch_wall(k, inner, "stucco", "stucco_in", f[0], f[1], f[2], f[3], SITE_Y, W_WALL, bays, true)
	# The east wall: inside the wing up to its roof, then an outside face above it with five
	# short upper windows into the hall's clerestory.
	var east_o := Vector3(W_X1, 0.0, W_Z1)
	var hall_door := [{"c": W_Z1 - HALL_DOOR_Z, "w": HALL_DOOR_W, "sill": 0.0, "spring": 2.8, "door": true}]
	_arch_wall(inner, inner, "stucco_in", "stucco_in", east_o, Vector3.FORWARD, Vector3.RIGHT, W_Z1 - W_Z0, 0.0, E_CEIL, hall_door, false)
	var upper := _even_openings(W_Z1 - W_Z0, 5, 1.6, E_WALL + 0.9, 9.4)
	_arch_wall(k, inner, "stucco", "stucco_in", east_o + Vector3(0.0, 0.0, 0.0), Vector3.FORWARD, Vector3.RIGHT, W_Z1 - W_Z0, E_CEIL, W_WALL, upper, true)
	# Pilaster strips between the bays, a base course, the cornice and the parapet.
	for f in faces:
		_pilasters(k, f[0], f[1], f[2], f[3], 5, BAY_W)
	_cornice_and_parapet(k, Rect2(W_X0, W_Z0, W_X1 - W_X0, W_Z1 - W_Z0), W_WALL, W_CORNICE, W_PARAPET, W_MERLON, false)
	# Roof slab, and the hall's ceiling under it.
	k.box("stucco", Vector3((W_X0 + W_X1) * 0.5, W_WALL - 0.2, (W_Z0 + W_Z1) * 0.5), Vector3(W_X1 - W_X0 - 0.1, 0.4, W_Z1 - W_Z0 - 0.1), true)
	inner.flat_down("stucco_in", Rect2(W_X0 + WALL_T, W_Z0 + WALL_T, W_X1 - W_X0 - 2.0 * WALL_T, W_Z1 - W_Z0 - 2.0 * WALL_T), HALL_CEIL)


## `count` openings of width `w`, spaced evenly along a face of `length`.
static func _even_openings(length: float, count: int, w: float, sill: float, spring: float, lattice: bool = true) -> Array:
	var out := []
	var pitch := length / float(count)
	for i in count:
		out.append({"c": pitch * (float(i) + 0.5), "w": w, "sill": sill, "spring": spring, "lattice": lattice})
	return out


static func _pilasters(k: _Kit, o: Vector3, u: Vector3, n: Vector3, length: float, count: int, w: float) -> void:
	var pitch := length / float(count)
	for i in count + 1:
		var c := pitch * float(i)
		var pw := 0.5 if i == 0 or i == count else 0.36
		var cc := clampf(c, pw * 0.5, length - pw * 0.5)
		var p := o + u * cc + n * 0.06
		var size := Vector3(absf(u.x) * pw + absf(n.x) * 0.12, W_WALL - SITE_Y, absf(u.z) * pw + absf(n.z) * 0.12)
		k.box("stucco", p + Vector3(0.0, (W_WALL + SITE_Y) * 0.5, 0.0), size, false)
	# A plinth course along the foot of the face.
	var base_size := Vector3(absf(u.x) * length + absf(n.x) * 0.2, 0.55, absf(u.z) * length + absf(n.z) * 0.2)
	k.box("stucco", o + u * length * 0.5 + n * 0.1 + Vector3(0.0, SITE_Y + 0.275, 0.0), base_size, false)


## A band `h` tall and `w` wide round the edge of a rect at height `y`, centred on its walls:
## a ring of four boxes, never a slab, or it would lay its colour over the whole roof and close
## the opening under the dome.
static func _band_ring(k: _Kit, key: String, r: Rect2, y: float, h: float, w: float, skip_west: bool = false) -> void:
	var cx := r.position.x + r.size.x * 0.5
	var cz := r.position.y + r.size.y * 0.5
	var yy := y + h * 0.5
	k.box(key, Vector3(cx, yy, r.end.y), Vector3(r.size.x + w, h, w), true)
	k.box(key, Vector3(cx, yy, r.position.y), Vector3(r.size.x + w, h, w), true)
	if not skip_west:
		k.box(key, Vector3(r.position.x, yy, cz), Vector3(w, h, r.size.y - w), true)
	k.box(key, Vector3(r.end.x, yy, cz), Vector3(w, h, r.size.y - w), true)


## A green cornice band round a rect of walls at `y`, then a white parapet wall and merlons.
## `rounded` gives the east wing's round-topped merlons; otherwise square ones with green caps.
static func _cornice_and_parapet(k: _Kit, r: Rect2, y: float, cornice: float, parapet: float, merlon: float, rounded: bool, skip_west: bool = false) -> void:
	_band_ring(k, "green", r, y, cornice, 0.6, skip_west)
	var top := y + cornice
	var sides := [
		[Vector3(r.position.x, top, r.end.y), Vector3.RIGHT, r.size.x, Vector3.BACK],
		[Vector3(r.position.x, top, r.position.y), Vector3.RIGHT, r.size.x, Vector3.FORWARD],
		[Vector3(r.position.x, top, r.position.y), Vector3.BACK, r.size.y, Vector3.LEFT],
		[Vector3(r.end.x, top, r.position.y), Vector3.BACK, r.size.y, Vector3.RIGHT],
	]
	for i in sides.size():
		if skip_west and i == 2:
			continue
		var s = sides[i]
		var o: Vector3 = s[0]
		var u: Vector3 = s[1]
		var length: float = s[2]
		var n: Vector3 = s[3]
		var inset := n * -0.12
		var wall_size := Vector3(absf(u.x) * length + absf(n.x) * 0.3, parapet, absf(u.z) * length + absf(n.z) * 0.3)
		k.box("stucco", o + u * length * 0.5 + inset + Vector3(0.0, parapet * 0.5, 0.0), wall_size, true)
		var step := 1.1 if not rounded else 0.78
		var mw := 0.55 if not rounded else 0.46
		var count := int(length / step)
		var start := (length - float(count - 1) * step) * 0.5
		for j in count:
			var p := o + u * (start + float(j) * step) + inset + Vector3(0.0, parapet, 0.0)
			if rounded:
				k.merlon_round("stucco", p, u, n, mw, merlon - mw * 0.5, 0.3)
			else:
				var size := Vector3(absf(u.x) * mw + absf(n.x) * 0.32, merlon, absf(u.z) * mw + absf(n.z) * 0.32)
				k.box("stucco", p + Vector3(0.0, merlon * 0.5, 0.0), size, false)
				k.box("green", p + Vector3(0.0, merlon + 0.04, 0.0), size + Vector3(0.06, 0.08, 0.06), false)


# --- The east wing ------------------------------------------------------------------------------

static func _east_wing(k: _Kit, inner: _Kit) -> void:
	# Street face, east of the entrance.
	var south_len := E_X1 - STAIR_X1
	var south := _even_openings(south_len, 9, WIN_W, WIN_SILL, WIN_SPRING)
	_arch_wall(k, inner, "stucco", "stucco_in", Vector3(STAIR_X1, 0.0, E_Z1), Vector3.RIGHT, Vector3.BACK, south_len, SITE_Y, E_WALL, south, true)
	# The short return where the wing steps out past the west block, and the north and east faces.
	_arch_wall(k, inner, "stucco", "stucco_in", Vector3(E_X0, 0.0, W_Z1), Vector3.BACK, Vector3.LEFT, E_Z1 - W_Z1, SITE_Y, E_WALL, [], true)
	var north := _even_openings(E_X1 - E_X0, 12, WIN_W, WIN_SILL, WIN_SPRING)
	_arch_wall(k, inner, "stucco", "stucco_in", Vector3(E_X1, 0.0, E_Z0), Vector3.LEFT, Vector3.FORWARD, E_X1 - E_X0, SITE_Y, E_WALL, north, true)
	var east := _even_openings(E_Z1 - E_Z0, 8, WIN_W, WIN_SILL, WIN_SPRING)
	_arch_wall(k, inner, "stucco", "stucco_in", Vector3(E_X1, 0.0, E_Z1), Vector3.FORWARD, Vector3.RIGHT, E_Z1 - E_Z0, SITE_Y, E_WALL, east, true)
	# The wing's north strip west of the west block's east wall is the block itself.
	_cornice_and_parapet(k, Rect2(E_X0, E_Z0, E_X1 - E_X0, E_Z1 - E_Z0), E_WALL, E_BAND, 0.25, E_MERLON, true, true)
	# The roof, with the round opening under the dome, and the ceiling under it.
	_roof_with_hole(k, "stucco", Rect2(E_X0 + 0.05, E_Z0 + 0.05, E_X1 - E_X0 - 0.1, E_Z1 - E_Z0 - 0.1), E_WALL, true, true)
	_roof_with_hole(inner, "stucco_in", Rect2(E_X0 + WALL_T, E_Z0 + WALL_T, E_X1 - E_X0 - 2.0 * WALL_T, E_Z1 - E_Z0 - 2.0 * WALL_T), E_CEIL, false, false)
	# The slab's edge round the opening, seen from below.
	inner.cyl("stucco_in", Vector3(DOME_C.x, E_CEIL, DOME_C.y), DRUM_R - 0.45, DRUM_R - 0.45, E_WALL - E_CEIL, 48, false, false, true)


## A flat roof over `r` at height `y` (facing up), or a ceiling under it (facing down), with the
## round opening under the dome's drum: an annulus from the opening out to a square round it,
## then plain rects for the rest.
static func _roof_with_hole(k: _Kit, key: String, r: Rect2, y: float, up: bool, solid: bool) -> void:
	var hole := DRUM_R - 0.45
	var sq := DRUM_R + 0.2
	var c := Vector3(DOME_C.x, y, DOME_C.y)
	var n := Vector3.UP if up else Vector3.DOWN
	var segs := 48
	for i in segs:
		var a0 := TAU * float(i) / float(segs)
		var a1 := TAU * float(i + 1) / float(segs)
		var d0 := Vector3(cos(a0), 0.0, sin(a0))
		var d1 := Vector3(cos(a1), 0.0, sin(a1))
		var s0 := d0 * (sq / maxf(absf(d0.x), absf(d0.z)))
		var s1 := d1 * (sq / maxf(absf(d1.x), absf(d1.z)))
		k.quad(key, c + d0 * hole, c + d1 * hole, c + s1, c + s0, n, solid)
	# The rest of the rect, outside the square.
	var x0 := DOME_C.x - sq
	var x1 := DOME_C.x + sq
	var z0 := DOME_C.y - sq
	var z1 := DOME_C.y + sq
	var parts := [
		Rect2(r.position.x, r.position.y, x0 - r.position.x, r.size.y),
		Rect2(x1, r.position.y, r.end.x - x1, r.size.y),
		Rect2(x0, r.position.y, x1 - x0, z0 - r.position.y),
		Rect2(x0, z1, x1 - x0, r.end.y - z1),
	]
	for p in parts:
		if p.size.x > 0.01 and p.size.y > 0.01:
			if up:
				k.flat(key, p, y, solid)
			else:
				k.flat_down(key, p, y)


# --- Walls with arched openings ----------------------------------------------------------------

## A wall panel in a vertical plane: `o` is its lower-left corner on the outer face (y is taken
## from y0), `u` runs along it, `n` is the outward normal, and the inner face is WALL_T behind.
## Openings are round-arched ({c, w, sill, spring} and optional door / lattice). The outer face
## goes to `k` in `key`, the inner face to `ki` in `key_in`, the reveals to the outer kit. With
## `band`, every opening gets a green surround on the outer face.
static func _arch_wall(k: _Kit, ki: _Kit, key: String, key_in: String, o: Vector3, u: Vector3, n: Vector3, length: float, y0: float, y1: float, openings: Array, band: bool) -> void:
	var up := Vector3.UP
	var base := Vector3(o.x, 0.0, o.z)
	var pt := func(uu: float, yy: float, depth: float) -> Vector3:
		return base + u * uu + up * yy - n * depth
	for side in 2:
		var depth := 0.0 if side == 0 else WALL_T
		var kk: _Kit = k if side == 0 else ki
		var kkey := key if side == 0 else key_in
		var nn := n if side == 0 else -n
		# The inner face starts at the floor, not the plinth.
		var yb := y0 if side == 0 else maxf(y0, 0.0)
		var prev := 0.0
		for op in openings:
			var a: float = op.c - op.w * 0.5
			var b: float = op.c + op.w * 0.5
			var sill: float = maxf(op.sill, yb)
			var spring: float = op.spring
			var r: float = op.w * 0.5
			if a > prev:
				kk.quad(kkey, pt.call(prev, yb, depth), pt.call(a, yb, depth), pt.call(a, y1, depth), pt.call(prev, y1, depth), nn, true)
			if sill > yb + 0.001:
				kk.quad(kkey, pt.call(a, yb, depth), pt.call(b, yb, depth), pt.call(b, sill, depth), pt.call(a, sill, depth), nn, true)
			var segs := 12
			for s in segs:
				var ua: float = a + op.w * float(s) / float(segs)
				var ub: float = a + op.w * float(s + 1) / float(segs)
				var ha := spring + sqrt(maxf(r * r - pow(ua - op.c, 2.0), 0.0))
				var hb := spring + sqrt(maxf(r * r - pow(ub - op.c, 2.0), 0.0))
				if y1 > minf(ha, hb) + 0.001:
					kk.quad(kkey, pt.call(ua, ha, depth), pt.call(ub, hb, depth), pt.call(ub, y1, depth), pt.call(ua, y1, depth), nn, true)
			prev = b
		if length > prev:
			kk.quad(kkey, pt.call(prev, yb, depth), pt.call(length, yb, depth), pt.call(length, y1, depth), pt.call(prev, y1, depth), nn, true)
	# Reveals, fills and surrounds.
	for op in openings:
		var a: float = op.c - op.w * 0.5
		var b: float = op.c + op.w * 0.5
		var r: float = op.w * 0.5
		var sill: float = maxf(op.sill, y0)
		var spring: float = op.spring
		var is_door: bool = op.get("door", false)
		var reveal_key := "stucco" if key == "stucco" else key_in
		if sill > y0 + 0.001 and not is_door:
			k.quad(reveal_key, pt.call(a, sill, 0.0), pt.call(b, sill, 0.0), pt.call(b, sill, WALL_T), pt.call(a, sill, WALL_T), up, true)
			# A projecting sill.
			k.box("stucco", pt.call(op.c, sill - 0.04, -0.07), Vector3(absf(u.x) * (op.w + 0.3) + absf(n.x) * 0.2, 0.08, absf(u.z) * (op.w + 0.3) + absf(n.z) * 0.2), false)
		k.quad(reveal_key, pt.call(a, sill, 0.0), pt.call(a, spring, 0.0), pt.call(a, spring, WALL_T), pt.call(a, sill, WALL_T), u, true)
		k.quad(reveal_key, pt.call(b, sill, 0.0), pt.call(b, spring, 0.0), pt.call(b, spring, WALL_T), pt.call(b, sill, WALL_T), -u, true)
		var segs := 12
		for s in segs:
			var t0 := PI * float(s) / float(segs)
			var t1 := PI * float(s + 1) / float(segs)
			var ua: float = op.c - r * cos(t0)
			var ub: float = op.c - r * cos(t1)
			var ha := spring + r * sin(t0)
			var hb := spring + r * sin(t1)
			var tm := (t0 + t1) * 0.5
			var nrm: Vector3 = (u * cos(tm) - up * sin(tm)).normalized()
			k.quad(reveal_key, pt.call(ua, ha, 0.0), pt.call(ub, hb, 0.0), pt.call(ub, hb, WALL_T), pt.call(ua, ha, WALL_T), nrm, true)
		if is_door:
			continue
		# The window: lattice near the outer face, dark glass behind it, and a collision pane.
		if op.get("lattice", true):
			_opening_fill(k, "lattice", pt, op, sill, 0.14, false)
		_opening_fill(k, "glass", pt, op, sill, 0.30, true)
		if band:
			_surround(k, pt, u, n, op, sill, 0.18, 0.045)


## The opening's own shape (a rect up to the spring, a half-disc above) at `depth` into the wall.
static func _opening_fill(k: _Kit, key: String, pt: Callable, op: Dictionary, sill: float, depth: float, solid: bool) -> void:
	var a: float = op.c - op.w * 0.5
	var b: float = op.c + op.w * 0.5
	var r: float = op.w * 0.5
	var spring: float = op.spring
	var n: Vector3 = (pt.call(0.0, 0.0, -1.0) - pt.call(0.0, 0.0, 0.0)).normalized()
	k.quad(key, pt.call(a, sill, depth), pt.call(b, sill, depth), pt.call(b, spring, depth), pt.call(a, spring, depth), n, solid)
	var segs := 12
	var c: Vector3 = pt.call(op.c, spring, depth)
	for s in segs:
		var t0 := PI * float(s) / float(segs)
		var t1 := PI * float(s + 1) / float(segs)
		k.tri(key, c, pt.call(op.c - r * cos(t0), spring + r * sin(t0), depth), pt.call(op.c - r * cos(t1), spring + r * sin(t1), depth), n, solid)


## A green band round an opening, standing `proud` off the face, `w` wide.
static func _surround(k: _Kit, pt: Callable, u: Vector3, n: Vector3, op: Dictionary, sill: float, w: float, proud: float) -> void:
	var r: float = op.w * 0.5
	var spring: float = op.spring
	var inner := PackedVector2Array()
	var outer := PackedVector2Array()
	inner.append(Vector2(op.c - r, sill))
	outer.append(Vector2(op.c - r - w, sill))
	var segs := 14
	for s in segs + 1:
		var t := PI * float(s) / float(segs)
		inner.append(Vector2(op.c - r * cos(t), spring + r * sin(t)))
		outer.append(Vector2(op.c - (r + w) * cos(t), spring + (r + w) * sin(t)))
	inner.append(Vector2(op.c + r, sill))
	outer.append(Vector2(op.c + r + w, sill))
	for i in inner.size() - 1:
		var a0: Vector3 = pt.call(inner[i].x, inner[i].y, -proud)
		var a1: Vector3 = pt.call(inner[i + 1].x, inner[i + 1].y, -proud)
		var b0: Vector3 = pt.call(outer[i].x, outer[i].y, -proud)
		var b1: Vector3 = pt.call(outer[i + 1].x, outer[i + 1].y, -proud)
		k.quad("green", a0, a1, b1, b0, n, false)
		# The band's outer edge.
		var e0: Vector3 = pt.call(outer[i].x, outer[i].y, 0.0)
		var e1: Vector3 = pt.call(outer[i + 1].x, outer[i + 1].y, 0.0)
		var mid := (outer[i] + outer[i + 1]) * 0.5
		var ctr := Vector2(op.c, spring if mid.y > spring else mid.y)
		var dir2 := (mid - ctr).normalized()
		k.quad("green", b0, b1, e1, e0, (u * dir2.x + Vector3.UP * dir2.y).normalized(), false)


# --- The entrance -------------------------------------------------------------------------------

static func _entrance(k: _Kit, inner: _Kit) -> void:
	# The entrance wall: three arched doors with fanlights.
	var ops := []
	for i in 3:
		ops.append({"c": DOOR_X[i] - STAIR_X0, "w": DOOR_W[i], "sill": 0.0, "spring": DOOR_SPRING + (0.25 if i == 1 else 0.0), "door": true})
	_arch_wall(k, inner, "stucco", "stucco_in", Vector3(STAIR_X0, 0.0, E_Z1), Vector3.RIGHT, Vector3.BACK, STAIR_X1 - STAIR_X0, 0.0, E_WALL, ops, false)
	for op in ops:
		var cx: float = STAIR_X0 + op.c
		var r: float = op.w * 0.5
		var spring: float = op.spring
		var pt := func(uu: float, yy: float, depth: float) -> Vector3:
			return Vector3(STAIR_X0 + uu, yy, E_Z1 - depth)
		# Green surround, broader than the windows'.
		_surround(k, pt, Vector3.RIGHT, Vector3.BACK, op, 0.0, 0.26, 0.06)
		# Fanlight: glass in the arch with black radial glazing bars and a transom.
		_fanlight(k, Vector3(cx, spring, E_Z1 - 0.2), r)
		# Door leaves, black frames round glass: the centre pair standing open, the side ones shut.
		var leaf_w := r
		var hgt := spring - 0.05
		if op.w > 1.8:
			for sgn in [-1.0, 1.0]:
				var hinge := Vector3(cx + sgn * r, 0.0, E_Z1 - WALL_T + 0.05)
				var yaw: float = sgn * deg_to_rad(80.0)
				var basis := Basis(Vector3.UP, yaw)
				var centre := hinge + basis * Vector3(-sgn * leaf_w * 0.5, hgt * 0.5, 0.0)
				_door_leaf(k, Transform3D(basis, centre), leaf_w, hgt, false)
		else:
			for sgn in [-1.0, 1.0]:
				var centre := Vector3(cx + sgn * leaf_w * 0.5, hgt * 0.5, E_Z1 - 0.25)
				_door_leaf(k, Transform3D(Basis.IDENTITY, centre), leaf_w, hgt, true)
	# The awning over all three: a green canopy on thin brackets.
	var aw_y := DOOR_SPRING + 1.45
	k.box("green", Vector3((STAIR_X0 + STAIR_X1) * 0.5, aw_y, E_Z1 + 0.65), Vector3(STAIR_X1 - STAIR_X0 + 0.2, 0.08, 1.3), true)
	k.box("green", Vector3((STAIR_X0 + STAIR_X1) * 0.5, aw_y - 0.12, E_Z1 + 1.3), Vector3(STAIR_X1 - STAIR_X0 + 0.2, 0.3, 0.05), false)
	for x in [STAIR_X0 + 0.3, (STAIR_X0 + STAIR_X1) * 0.5, STAIR_X1 - 0.3]:
		k.obox("black", Transform3D(Basis(Vector3.RIGHT, deg_to_rad(-40.0)), Vector3(x, aw_y + 0.45, E_Z1 + 0.55)), Vector3(0.04, 0.04, 1.35), false)
	# Porch and flight: grey marble, a black strip behind every nosing.
	k.box("marble", Vector3((STAIR_X0 + STAIR_X1) * 0.5, -0.4, E_Z1 + PORCH_D * 0.5), Vector3(STAIR_X1 - STAIR_X0, 0.8, PORCH_D), true)
	for i in STEPS:
		var top := -STEP_RISE * float(i + 1)
		var z0 := E_Z1 + PORCH_D + STEP_RUN * float(i)
		var h := top - (PAVE_Y - 0.3)
		k.box("marble", Vector3((STAIR_X0 + STAIR_X1) * 0.5, top - h * 0.5, z0 + STEP_RUN * 0.5), Vector3(STAIR_X1 - STAIR_X0, h, STEP_RUN), true)
		k.flat("black", Rect2(STAIR_X0 + 0.15, z0 + 0.04, STAIR_X1 - STAIR_X0 - 0.3, 0.06), top + 0.004)
	# The flight's cheeks are the plinth's own faces either side of it.
	# Handrails: one down each side and two down the middle, black steel.
	var z_top := E_Z1 + PORCH_D - 0.2
	var z_bot := E_Z1 + PORCH_D + STEP_RUN * STEPS + 0.2
	var fall := PAVE_Y
	for x in [STAIR_X0 + 0.12, -4.2, -1.9, STAIR_X1 - 0.12]:
		var a := Vector3(x, 0.95, z_top)
		var b := Vector3(x, fall + 0.95, z_bot)
		_rail(k, a, b)
		for t in [0.0, 0.5, 1.0]:
			var p := a.lerp(b, t)
			k.box("black", p + Vector3(0.0, -0.475, 0.0), Vector3(0.05, 0.95, 0.05), false)
		# The middle rails turn down into the steps at the foot, as in the photo.
		k.box("black", Vector3(x, fall + 0.5, z_bot + 0.1), Vector3(0.05, 0.9, 0.05), false)


static func _rail(k: _Kit, a: Vector3, b: Vector3) -> void:
	var d := b - a
	var basis := Basis.looking_at(d.normalized(), Vector3.UP)
	k.obox("black", Transform3D(basis, (a + b) * 0.5), Vector3(0.05, 0.05, d.length()), false)


static func _fanlight(k: _Kit, c: Vector3, r: float) -> void:
	var segs := 12
	for s in segs:
		var t0 := PI * float(s) / float(segs)
		var t1 := PI * float(s + 1) / float(segs)
		k.tri("glass", c, c + Vector3(-r * cos(t0), r * sin(t0), 0.0), c + Vector3(-r * cos(t1), r * sin(t1), 0.0), Vector3.BACK, false)
	k.box("black", c + Vector3(0.0, 0.0, 0.02), Vector3(2.0 * r, 0.07, 0.05), false)
	for i in 7:
		var t := PI * (float(i) + 0.5) / 7.0
		var d := Vector3(-cos(t), sin(t), 0.0)
		var basis := Basis(Vector3.BACK, atan2(d.y, d.x) - PI * 0.5)
		k.obox("black", Transform3D(basis, c + d * r * 0.5 + Vector3(0.0, 0.0, 0.02)), Vector3(0.035, r, 0.04), false)
	k.cyl("black", c + Vector3(0.0, 0.0, 0.02), 0.18, 0.18, 0.04, 12, true, false)


## One glazed door leaf, `w` wide and `h` high, centred on xf.
static func _door_leaf(k: _Kit, xf: Transform3D, w: float, h: float, solid: bool) -> void:
	var f := 0.09
	k.obox("black", xf * Transform3D(Basis.IDENTITY, Vector3(-w * 0.5 + f * 0.5, 0.0, 0.0)), Vector3(f, h, 0.06), false)
	k.obox("black", xf * Transform3D(Basis.IDENTITY, Vector3(w * 0.5 - f * 0.5, 0.0, 0.0)), Vector3(f, h, 0.06), false)
	k.obox("black", xf * Transform3D(Basis.IDENTITY, Vector3(0.0, h * 0.5 - f * 0.5, 0.0)), Vector3(w, f, 0.06), false)
	k.obox("black", xf * Transform3D(Basis.IDENTITY, Vector3(0.0, -h * 0.5 + 0.12, 0.0)), Vector3(w, 0.24, 0.06), false)
	k.obox("black", xf * Transform3D(Basis.IDENTITY, Vector3(0.0, 0.0, 0.0)), Vector3(w, 0.05, 0.05), false)
	k.obox("glass", xf, Vector3(w - 2.0 * f, h - 0.3, 0.02), solid)
	k.obox("gold", xf * Transform3D(Basis.IDENTITY, Vector3(w * 0.5 - 0.16, 0.0, 0.05)), Vector3(0.03, 0.5, 0.03), false)


# --- The dome -------------------------------------------------------------------------------------

static func _dome(k: _Kit, inner: _Kit) -> void:
	var c := Vector3(DOME_C.x, 0.0, DOME_C.y)
	# The drum: white, a green band at its top, a slim base course.
	k.cyl("stucco", c + Vector3(0.0, E_WALL, 0.0), DRUM_R, DRUM_R, DRUM_TOP - E_WALL - 0.35, 48, false, true)
	# No caps: a capped cylinder here would lay a green disc across the inside of the dome.
	k.cyl("green", c + Vector3(0.0, DRUM_TOP - 0.35, 0.0), DRUM_R + 0.12, DRUM_R + 0.12, 0.35, 48, false, true)
	k.annulus("green", c + Vector3(0.0, DRUM_TOP, 0.0), DRUM_R - 0.45, DRUM_R + 0.12, 48, true)
	inner.cyl("stucco_in", c + Vector3(0.0, E_WALL, 0.0), DRUM_R - 0.45, DRUM_R - 0.45, DRUM_TOP - E_WALL, 48, false, false, true)
	# The shell: an ellipse in section, a little stilted, as in the aerial photo.
	var prof := PackedVector2Array()
	var prof_in := PackedVector2Array()
	var rings := 18
	for i in rings + 1:
		var a := PI * 0.5 * float(i) / float(rings)
		prof.append(Vector2(DOME_R * cos(a), DOME_H * sin(a)))
		prof_in.append(Vector2((DOME_R - 0.35) * cos(a), (DOME_H - 0.35) * sin(a)))
	var base := c + Vector3(0.0, DRUM_TOP, 0.0)
	k.revolve("dome", base, prof, 64, true, true)
	inner.revolve("stucco_in", base, prof_in, 64, false, false)
	# The ribs: 24 half-round strips down the gores, and a gold ring where the ribs meet the top.
	for rib in DOME_RIBS:
		var az := TAU * float(rib) / float(DOME_RIBS)
		var d := Vector3(cos(az), 0.0, sin(az))
		var side := Vector3(-d.z, 0.0, d.x)
		for i in rings - 2:
			var p0 := prof[i]
			var p1 := prof[i + 1]
			var a0 := base + d * p0.x + Vector3.UP * p0.y
			var a1 := base + d * p1.x + Vector3.UP * p1.y
			var nrm0 := (d * p0.x / (DOME_R * DOME_R) + Vector3.UP * p0.y / (DOME_H * DOME_H)).normalized()
			var nrm1 := (d * p1.x / (DOME_R * DOME_R) + Vector3.UP * p1.y / (DOME_H * DOME_H)).normalized()
			var hw := 0.07
			var pr := 0.07
			k.quad("dome", a0 - side * hw + nrm0 * pr, a0 + side * hw + nrm0 * pr, a1 + side * hw + nrm1 * pr, a1 - side * hw + nrm1 * pr, (nrm0 + nrm1).normalized(), false)
			k.quad("dome", a0 - side * hw, a0 - side * hw + nrm0 * pr, a1 - side * hw + nrm1 * pr, a1 - side * hw, -side, false)
			k.quad("dome", a0 + side * hw, a0 + side * hw + nrm0 * pr, a1 + side * hw + nrm1 * pr, a1 + side * hw, side, false)
	var apex := base + Vector3.UP * DOME_H
	k.cyl("gold", apex - Vector3(0.0, 0.25, 0.0), 0.55, 0.45, 0.3, 24, true, false)
	_finial(k, apex + Vector3(0.0, 0.05, 0.0), 1.0)
	# Inside: a gold ring at the dome's springing and a chandelier from its crown.
	inner.cyl("gold", base - Vector3(0.0, 0.08, 0.0), DOME_R - 0.3, DOME_R - 0.3, 0.16, 64, false, false, true)
	_chandelier(inner, apex - Vector3(0.0, 0.35, 0.0), 0.62, 6.0)


## The finial: a rod, stacked gold balls and a crescent open to the sky. `s` scales it.
static func _finial(k: _Kit, at: Vector3, s: float) -> void:
	k.cyl("gold", at, 0.05 * s, 0.05 * s, 1.5 * s, 8, true, false)
	for b in [[0.3, 0.2], [0.75, 0.15], [1.1, 0.11]]:
		k.sphere("gold", at + Vector3(0.0, b[0] * s, 0.0), b[1] * s, 12, 6)
	# The crescent: a thick arc in the XY plane, horns up.
	var c := at + Vector3(0.0, 1.62 * s, 0.0)
	var ro := 0.36 * s
	var ri := 0.28 * s
	var off := Vector3(0.0, 0.08 * s, 0.0)
	var segs := 16
	for i in segs:
		var t0 := PI * (0.12 + 0.76 * float(i) / float(segs)) + PI
		var t1 := PI * (0.12 + 0.76 * float(i + 1) / float(segs)) + PI
		var o0 := c + Vector3(cos(t0), -sin(t0), 0.0) * ro
		var o1 := c + Vector3(cos(t1), -sin(t1), 0.0) * ro
		var i0 := c + off + Vector3(cos(t0), -sin(t0), 0.0) * ri
		var i1 := c + off + Vector3(cos(t1), -sin(t1), 0.0) * ri
		for side in [-1.0, 1.0]:
			var z := Vector3(0.0, 0.0, 0.035 * s * side)
			k.quad("gold", o0 + z, o1 + z, i1 + z, i0 + z, Vector3(0.0, 0.0, side), false)
		k.quad("gold", o0 - Vector3(0, 0, 0.035 * s), o1 - Vector3(0, 0, 0.035 * s), o1 + Vector3(0, 0, 0.035 * s), o0 + Vector3(0, 0, 0.035 * s), (o0 + o1 - 2.0 * c).normalized(), false)
		k.quad("gold", i0 - Vector3(0, 0, 0.035 * s), i1 - Vector3(0, 0, 0.035 * s), i1 + Vector3(0, 0, 0.035 * s), i0 + Vector3(0, 0, 0.035 * s), -(i0 + i1 - 2.0 * (c + off)).normalized(), false)


# --- The minaret --------------------------------------------------------------------------------

static func _minaret(k: _Kit) -> void:
	var c := Vector3(MIN_C.x, 0.0, MIN_C.y)
	var hw := MIN_W * 0.5
	# The square shaft from the wing's roof, with a recessed panel down each face.
	k.box("stucco", c + Vector3(0.0, (E_WALL + MIN_SHAFT_TOP) * 0.5, 0.0), Vector3(MIN_W, MIN_SHAFT_TOP - E_WALL, MIN_W), true)
	for n in [Vector3.BACK, Vector3.FORWARD, Vector3.LEFT, Vector3.RIGHT]:
		var along := Vector3(absf(n.z), 0.0, absf(n.x))
		k.box("green", c + n * (hw + 0.01) + Vector3(0.0, 14.6, 0.0), along * 0.5 + Vector3(0.0, 1.4, 0.0) + n.abs() * 0.02, false)
		k.box("stucco", c + n * (hw + 0.03) + Vector3(0.0, MIN_SHAFT_TOP - 0.45, 0.0), along * (MIN_W + 0.1) + Vector3(0.0, 0.18, 0.0) + n.abs() * 0.06, false)
	# The balcony: a slab on a corbel course, a white balustrade with a green rail.
	k.box("stucco", c + Vector3(0.0, MIN_SHAFT_TOP - 0.15, 0.0), Vector3(MIN_W + 0.4, 0.3, MIN_W + 0.4), false)
	k.box("stucco", c + Vector3(0.0, MIN_SHAFT_TOP + 0.15, 0.0), Vector3(MIN_BALC, 0.3, MIN_BALC), true)
	for n in [Vector3.BACK, Vector3.FORWARD, Vector3.LEFT, Vector3.RIGHT]:
		var along := Vector3(absf(n.z), 0.0, absf(n.x))
		var edge: Vector3 = c + n * (MIN_BALC * 0.5 - 0.06)
		k.box("stucco", edge + Vector3(0.0, MIN_SHAFT_TOP + 0.7, 0.0), along * MIN_BALC + Vector3(0.0, 0.8, 0.0) + n.abs() * 0.12, true)
		k.box("green", edge + Vector3(0.0, MIN_SHAFT_TOP + 1.14, 0.0), along * (MIN_BALC + 0.04) + Vector3(0.0, 0.08, 0.0) + n.abs() * 0.18, false)
		# Pierced panels in the balustrade: little arches.
		for i in 4:
			var t := (float(i) + 0.5) / 4.0 - 0.5
			k.box("green", edge + along * t * (MIN_BALC - 0.6) + n * 0.065 + Vector3(0.0, MIN_SHAFT_TOP + 0.7, 0.0), along * 0.36 + Vector3(0.0, 0.5, 0.0) + n.abs() * 0.01, false)
	# The white octagonal tier.
	var tier0 := MIN_SHAFT_TOP + 0.3
	k.cyl("stucco", c + Vector3(0.0, tier0, 0.0), 1.1, 1.1, MIN_TIER_TOP - tier0, 8, false, true)
	k.cyl("green", c + Vector3(0.0, MIN_TIER_TOP - 0.2, 0.0), 1.22, 1.22, 0.2, 8, true, false)
	# The lantern: eight green piers round lattice openings, then a cornice.
	var lan_h := MIN_LANTERN_TOP - MIN_TIER_TOP
	for i in 8:
		var a := TAU * (float(i) + 0.5) / 8.0
		var d := Vector3(cos(a), 0.0, sin(a))
		k.box("green", c + d * 0.98 + Vector3(0.0, MIN_TIER_TOP + lan_h * 0.5, 0.0), Vector3(0.22, lan_h, 0.22), true)
		var fa := TAU * float(i) / 8.0
		var fd := Vector3(cos(fa), 0.0, sin(fa))
		var fu := Vector3(-fd.z, 0.0, fd.x)
		var fc := c + fd * 0.9
		var pt := func(uu: float, yy: float, depth: float) -> Vector3:
			return fc + fu * (uu - 0.4) + Vector3.UP * yy - fd * depth
		_opening_fill(k, "lattice", pt, {"c": 0.4, "w": 0.62, "spring": MIN_TIER_TOP + lan_h - 0.65}, MIN_TIER_TOP + 0.1, 0.0, false)
	k.cyl("green", c + Vector3(0.0, MIN_LANTERN_TOP - 0.25, 0.0), 1.18, 1.18, 0.25, 8, true, true)
	# The cap: an eight-sided pointed dome, green, and the finial.
	var prof := PackedVector2Array()
	for i in 9:
		var t := float(i) / 8.0
		prof.append(Vector2(1.15 * (1.0 - t) * (1.0 + 0.35 * sin(t * PI)), (MIN_CAP_TOP - MIN_LANTERN_TOP) * t))
	k.revolve("green", c + Vector3(0.0, MIN_LANTERN_TOP, 0.0), prof, 8, true, false)
	_finial(k, c + Vector3(0.0, MIN_CAP_TOP - 0.05, 0.0), 0.75)
	# A speaker horn under the balcony, facing the street, as minarets carry.
	k.cyl("black", c + Vector3(0.0, MIN_SHAFT_TOP - 1.0, hw + 0.05), 0.12, 0.25, 0.4, 10, true, false)


# --- The prayer hall ------------------------------------------------------------------------------

static func _hall(k: _Kit) -> void:
	var ix0 := W_X0 + WALL_T
	var ix1 := W_X1 - WALL_T
	var iz0 := W_Z0 + WALL_T
	var iz1 := W_Z1 - WALL_T
	var cx := (ix0 + ix1) * 0.5
	var cz := (iz0 + iz1) * 0.5
	# The carpet over the whole floor, on a slab.
	k.box("stucco_in", Vector3(cx, -0.1, cz), Vector3(ix1 - ix0, 0.2, iz1 - iz0), true)
	k.flat("carpet", Rect2(ix0, iz0, ix1 - ix0, iz1 - iz0), 0.012)
	# The gallery ring: four slabs, a hole over the stair in the west one.
	var ax0 := ix0 + GALLERY_D
	var ax1 := ix1 - GALLERY_D
	var az0 := iz0 + GALLERY_D
	var az1 := iz1 - GALLERY_D
	var gy := GALLERY_Y - GALLERY_T * 0.5
	var stair_x1 := ix0 + 1.25
	var stair_top_z := -2.4
	var hole_z1 := 1.4
	var slabs := [
		Rect2(ix0, iz0, ix1 - ix0, GALLERY_D),                     # north
		Rect2(ix0, az1, ix1 - ix0, GALLERY_D),                     # south
		Rect2(ax1, az0, GALLERY_D, az1 - az0),                     # east
		Rect2(stair_x1, az0, ax0 - stair_x1, az1 - az0),           # west, beside the stair
		Rect2(ix0, az0, 1.25, stair_top_z - az0),                  # west, north of the stair hole
		Rect2(ix0, hole_z1, 1.25, az1 - hole_z1),                  # west, south of it
	]
	for r in slabs:
		k.box("stucco_in", Vector3(r.position.x + r.size.x * 0.5, gy, r.position.y + r.size.y * 0.5), Vector3(r.size.x, GALLERY_T, r.size.y), true)
		k.flat("carpet", r, GALLERY_Y + 0.01)
	# The gallery parapet: white, 1.05 m, with a gold line and a wooden cap rail.
	var par := [
		[Vector3(ax0, 0.0, az0), Vector3(ax1, 0.0, az0)],
		[Vector3(ax0, 0.0, az1), Vector3(ax1, 0.0, az1)],
		[Vector3(ax0, 0.0, az0), Vector3(ax0, 0.0, az1)],
		[Vector3(ax1, 0.0, az0), Vector3(ax1, 0.0, az1)],
	]
	for p in par:
		var a: Vector3 = p[0]
		var b: Vector3 = p[1]
		var mid := (a + b) * 0.5
		var size := Vector3(absf(b.x - a.x) + 0.2, 1.05, absf(b.z - a.z) + 0.2)
		k.box("stucco_in", mid + Vector3(0.0, GALLERY_Y + 0.525, 0.0), size, true)
		k.box("wood", mid + Vector3(0.0, GALLERY_Y + 1.08, 0.0), size + Vector3(0.06, -0.99, 0.06), false)
		k.box("gold", mid + Vector3(0.0, GALLERY_Y + 0.8, 0.0), size + Vector3(0.02, -1.02, 0.02), false)
		# The slab's edge fascia, with a gold band.
		k.box("stucco_in", mid + Vector3(0.0, GALLERY_Y - GALLERY_T - 0.15, 0.0), size + Vector3(0.0, -0.75, 0.0), false)
	# Stair-hole guard on the gallery side.
	k.box("stucco_in", Vector3(stair_x1 + 0.1, GALLERY_Y + 0.525, (stair_top_z + hole_z1) * 0.5), Vector3(0.2, 1.05, hole_z1 - stair_top_z), true)
	# Columns: square, cream, with a base and a capital, along the ring's inner edge.
	var cols := []
	for x in [ax0, ax0 + (ax1 - ax0) / 3.0, ax0 + (ax1 - ax0) * 2.0 / 3.0, ax1]:
		cols.append(Vector2(x, az0))
		cols.append(Vector2(x, az1))
	for z in [az0 + (az1 - az0) / 3.0, az0 + (az1 - az0) * 2.0 / 3.0]:
		cols.append(Vector2(ax0, z))
		cols.append(Vector2(ax1, z))
	var soffit := GALLERY_Y - GALLERY_T
	for c in cols:
		k.box("stucco_in", Vector3(c.x, soffit * 0.5, c.y), Vector3(0.55, soffit, 0.55), true)
		k.box("stucco_in", Vector3(c.x, 0.15, c.y), Vector3(0.75, 0.3, 0.75), false)
		k.box("stucco_in", Vector3(c.x, soffit - 0.2, c.y), Vector3(0.75, 0.25, 0.75), false)
		k.box("gold", Vector3(c.x, soffit - 0.36, c.y), Vector3(0.6, 0.05, 0.6), false)
	# Recessed lights in the soffit, every 2 m round the ring, and round the ceiling's edge.
	for r in slabs:
		var x: float = r.position.x + 1.0
		while x < r.end.x - 0.5:
			var z: float = r.position.y + 1.0
			while z < r.end.y - 0.5:
				k.disc_down("lamp", Vector3(x, soffit - 0.005, z), 0.12)
				z += 2.0
			x += 2.0
	# The ceiling's centre: a recessed square coffer with a gold rim, the chandelier's rose.
	var coffer := 3.2
	k.box("gold", Vector3(cx, HALL_CEIL - 0.05, cz), Vector3(coffer * 2.0 + 0.2, 0.1, coffer * 2.0 + 0.2), false)
	k.cyl("gold", Vector3(cx, HALL_CEIL - 0.25, cz), 0.5, 0.5, 0.25, 24, true, false)
	_chandelier(k, Vector3(cx, HALL_CEIL - 0.25, cz), 1.0, 3.8)
	# Ceiling lights round the coffer.
	for i in 16:
		var a := TAU * float(i) / 16.0
		k.disc_down("lamp", Vector3(cx + cos(a) * 4.6, HALL_CEIL - 0.01, cz + sin(a) * 4.6), 0.14)
	_mihrab_and_minbar(k, cx, iz0)
	_stair(k, ix0, stair_top_z)
	# Bookshelves along the south wall under the gallery: the Qur'an shelves.
	for i in 3:
		var x := ix0 + 4.0 + float(i) * 3.5
		_bookshelf(k, Vector3(x, 0.0, iz1 - 0.3))


## The mihrab and the minbar on the qibla (north) wall.
static func _mihrab_and_minbar(k: _Kit, cx: float, iz0: float) -> void:
	# Mihrab: a projecting frame of green with gold borders round a half-octagon niche.
	var w := 2.4
	var h := 4.1
	var depth := 0.55
	var face := iz0 + depth
	for sgn in [-1.0, 1.0]:
		k.box("green", Vector3(cx + sgn * (w * 0.5 - 0.2), h * 0.5, iz0 + depth * 0.5), Vector3(0.4, h, depth), true)
		k.box("gold", Vector3(cx + sgn * (w * 0.5 - 0.02), h * 0.5, face + 0.01), Vector3(0.06, h, 0.04), false)
		k.box("gold", Vector3(cx + sgn * (w * 0.5 - 0.38), h * 0.5, face + 0.01), Vector3(0.04, h - 0.4, 0.04), false)
	k.box("green", Vector3(cx, h - 0.45, iz0 + depth * 0.5), Vector3(w, 0.9, depth), true)
	k.box("gold", Vector3(cx, h - 0.02, face + 0.01), Vector3(w, 0.06, 0.04), false)
	k.box("gold", Vector3(cx, h - 0.88, face + 0.01), Vector3(w - 0.8, 0.04, 0.04), false)
	# The niche: five panels of a half-octagon, cream, with an arched head.
	var r := 0.72
	var spring := 2.2
	for i in 4:
		var a0 := PI * float(i) / 4.0
		var a1 := PI * float(i + 1) / 4.0
		var p0 := Vector3(cx - cos(a0) * r, 0.0, iz0 + depth - sin(a0) * depth * 0.9)
		var p1 := Vector3(cx - cos(a1) * r, 0.0, iz0 + depth - sin(a1) * depth * 0.9)
		var nn := Vector3(p0.z - p1.z, 0.0, p1.x - p0.x).normalized()
		if nn.z < 0.0:
			nn = -nn
		k.quad("stucco_in", p0, p1, p1 + Vector3.UP * spring, p0 + Vector3.UP * spring, nn, false)
	# The niche head: a half-dome of gold.
	var prof := PackedVector2Array()
	for i in 7:
		var a := PI * 0.5 * float(i) / 6.0
		prof.append(Vector2(r * cos(a), r * sin(a)))
	k.half_dome("gold", Vector3(cx, spring, iz0 + depth), prof, 10)
	# Fill between the niche head and the frame.
	k.quad("green", Vector3(cx - w * 0.5 + 0.4, spring, face), Vector3(cx + w * 0.5 - 0.4, spring, face), Vector3(cx + w * 0.5 - 0.4, h - 0.9, face), Vector3(cx - w * 0.5 + 0.4, h - 0.9, face), Vector3.BACK, false)
	# The minbar to the mihrab's right (east): a straight wooden flight to a platform under a
	# small domed canopy, an arched gate at its foot.
	var mx := cx + 2.4
	var steps := 7
	var rise := 0.21
	var run := 0.34
	var mw := 0.9
	var z_back := iz0 + 0.3
	var z_foot := z_back + float(steps) * run + 0.9
	for i in steps:
		var top := rise * float(i + 1)
		var z := z_foot - 0.9 - float(i) * run
		k.box("wood", Vector3(mx, top * 0.5, z - run * 0.5), Vector3(mw, top, run), true)
	k.box("wood", Vector3(mx, rise * float(steps) * 0.5, z_back + 0.45), Vector3(mw, rise * float(steps), 0.9), true)
	for sgn in [-1.0, 1.0]:
		# Triangular side panels, stepped as boxes, with a lattice inset.
		for i in steps:
			var top := rise * float(i + 1) + 0.9
			var z := z_foot - 0.9 - float(i) * run
			k.box("wood", Vector3(mx + sgn * (mw * 0.5 + 0.04), top * 0.5, z - run * 0.5), Vector3(0.08, top, run), false)
		# Canopy posts.
		for dz in [0.1, 0.8]:
			k.box("wood", Vector3(mx + sgn * (mw * 0.5 - 0.05), rise * steps + 1.2, z_back + dz), Vector3(0.1, 2.4, 0.1), false)
		# Gate posts at the foot.
		k.box("wood", Vector3(mx + sgn * (mw * 0.5 + 0.05), 1.3, z_foot), Vector3(0.14, 2.6, 0.14), false)
	k.box("wood", Vector3(mx, 2.55, z_foot), Vector3(mw + 0.3, 0.18, 0.18), false)
	k.box("gold", Vector3(mx, 2.7, z_foot), Vector3(0.12, 0.12, 0.12), false)
	var canopy_y := rise * steps + 2.4
	k.box("wood", Vector3(mx, canopy_y, z_back + 0.45), Vector3(mw + 0.2, 0.14, 1.0), false)
	var cp := PackedVector2Array()
	for i in 7:
		var a := PI * 0.5 * float(i) / 6.0
		cp.append(Vector2(0.48 * cos(a), 0.62 * sin(a)))
	k.revolve("wood", Vector3(mx, canopy_y + 0.07, z_back + 0.45), cp, 8, true, false)
	k.sphere("gold", Vector3(mx, canopy_y + 0.75, z_back + 0.45), 0.07, 8, 4)


## The stair to the gallery: up the west wall from the south, arriving at stair_top_z.
static func _stair(k: _Kit, x0: float, top_z: float) -> void:
	var steps := int(ceil(GALLERY_Y / 0.175))
	var rise := GALLERY_Y / float(steps)
	var run := 0.28
	var w := 1.2
	for i in steps:
		var top := rise * float(i + 1)
		var z := top_z + float(steps - 1 - i) * run
		k.box("wood", Vector3(x0 + w * 0.5, top - rise * 0.5, z + run * 0.5), Vector3(w, rise, run), true)
		k.flat("carpet", Rect2(x0, z, w, run), top + 0.005)
		k.box("stucco_in", Vector3(x0 + w * 0.5, (top - rise) * 0.5, z + run * 0.5), Vector3(w, maxf(top - rise, 0.01), run), false)
	# A handrail on the open side.
	var a := Vector3(x0 + w + 0.05, 0.95, top_z + float(steps) * run)
	var b := Vector3(x0 + w + 0.05, GALLERY_Y + 0.95, top_z)
	var d := b - a
	k.obox("wood", Transform3D(Basis.looking_at(d.normalized(), Vector3.UP), (a + b) * 0.5), Vector3(0.06, 0.06, d.length()), false)
	for t in [0.0, 0.25, 0.5, 0.75, 1.0]:
		var p := a.lerp(b, t)
		k.box("wood", p + Vector3(0.0, -0.475, 0.0), Vector3(0.05, 0.95, 0.05), false)


static func _bookshelf(k: _Kit, at: Vector3) -> void:
	var w := 2.0
	var h := 1.3
	var d := 0.4
	k.box("wood", at + Vector3(0.0, h * 0.5, 0.0), Vector3(w, h, 0.04) + Vector3(0.0, 0.0, 0.0), false)
	for y in [0.05, 0.45, 0.85, 1.25]:
		k.box("wood", at + Vector3(0.0, y, -d * 0.5 + 0.02), Vector3(w, 0.04, d), false)
	for sgn in [-1.0, 1.0]:
		k.box("wood", at + Vector3(sgn * w * 0.5, h * 0.5, -d * 0.5 + 0.02), Vector3(0.04, h, d), false)
	# Books: a run of bound volumes on each shelf, green, red and gold spines.
	var keys := ["green", "red", "gold", "green", "red"]
	for sy in [0.07, 0.47, 0.87]:
		var x := -w * 0.5 + 0.08
		var i := 0
		while x < w * 0.5 - 0.1:
			var bw := 0.045 + 0.02 * float((i * 7) % 3)
			var bh := 0.26 + 0.04 * float((i * 5) % 3)
			k.box(keys[i % keys.size()], at + Vector3(x + bw * 0.5, sy + bh * 0.5, -d * 0.5 + 0.02), Vector3(bw, bh, 0.24), false)
			x += bw + 0.006
			i += 1


## A crystal chandelier: `s` scales it, `drop` is how far it hangs below `top`.
static func _chandelier(k: _Kit, top: Vector3, s: float, drop: float) -> void:
	var body_top := top - Vector3(0.0, drop - 2.6 * s, 0.0)
	k.cyl("gold", body_top, 0.025 * s, 0.025 * s, drop - 2.6 * s, 6, false, false)
	# The central column.
	k.cyl("gold", body_top - Vector3(0.0, 2.3 * s, 0.0), 0.08 * s, 0.08 * s, 2.3 * s, 10, true, false)
	k.sphere("crystal", body_top - Vector3(0.0, 2.45 * s, 0.0), 0.16 * s, 10, 6)
	# Tiers: a gold ring each, crystal strands hanging from it, candle lights on the middle two.
	var tiers := [[-0.3, 0.55], [-0.95, 0.95], [-1.6, 1.25], [-2.15, 0.8]]
	for ti in tiers.size():
		var y: float = tiers[ti][0] * s
		var r: float = tiers[ti][1] * s
		var ring_c := body_top + Vector3(0.0, y, 0.0)
		k.torus("gold", ring_c, r, 0.025 * s, 36, 5)
		var strands := int(r / s * 22.0)
		for i in strands:
			var a := TAU * float(i) / float(strands)
			var p := ring_c + Vector3(cos(a) * r, 0.0, sin(a) * r)
			for j in 3:
				k.gem("crystal", p - Vector3(0.0, (0.1 + 0.11 * float(j)) * s, 0.0), Vector3(0.03, 0.055, 0.03) * s)
		if ti == 1 or ti == 2:
			for i in 12:
				var a := TAU * (float(i) + 0.5) / 12.0
				var p := ring_c + Vector3(cos(a) * r, 0.0, sin(a) * r)
				k.cyl("gold", p, 0.03 * s, 0.03 * s, 0.1 * s, 6, true, false)
				k.sphere("crystal", p + Vector3(0.0, 0.16 * s, 0.0), 0.05 * s, 6, 4)
		# Arms from the column out to the ring.
		for i in 6:
			var a := TAU * float(i) / 6.0
			var mid := ring_c + Vector3(cos(a) * r * 0.5, 0.0, sin(a) * r * 0.5)
			k.obox("gold", Transform3D(Basis(Vector3.UP, -a), mid), Vector3(r, 0.02 * s, 0.02 * s), false)


# --- The lobby and the domed hall -------------------------------------------------------------

static func _lobby_and_domed_hall(k: _Kit) -> void:
	var ix0 := E_X0 + WALL_T
	var ix1 := E_X1 - WALL_T
	var iz0 := E_Z0 + WALL_T
	var iz1 := E_Z1 - WALL_T
	var split := 1.2
	# The lobby floor is marble, the hall under the dome carpeted.
	k.box("stucco_in", Vector3((ix0 + ix1) * 0.5, -0.1, (iz0 + iz1) * 0.5), Vector3(ix1 - ix0, 0.2, iz1 - iz0), true)
	k.flat("marble", Rect2(ix0, iz0, split - ix0, iz1 - iz0), 0.01)
	k.flat("carpet2", Rect2(split + 0.1, iz0, ix1 - split - 0.1, iz1 - iz0), 0.012)
	# The partition between them: a wall with a broad arched opening.
	var op := [{"c": (iz1 - iz0) * 0.5, "w": 4.0, "sill": 0.0, "spring": 2.9, "door": true}]
	_arch_wall(k, k, "stucco_in", "stucco_in", Vector3(split + 0.1, 0.0, iz0), Vector3.BACK, Vector3.RIGHT, iz1 - iz0, 0.0, E_CEIL, op, false)
	# Shoe racks along the lobby's north wall, as every masjid lobby has.
	for i in 2:
		var at := Vector3(ix0 + 1.5 + float(i) * 2.4, 0.0, iz0 + 0.25)
		k.box("wood", at + Vector3(0.0, 0.55, 0.0), Vector3(2.2, 1.1, 0.45), true)
		for y in [0.3, 0.7]:
			k.box("stucco_in", at + Vector3(0.0, y, 0.2), Vector3(2.1, 0.05, 0.06), false)
	# Lobby lights.
	for z in [iz0 + 3.0, iz0 + 8.0, iz0 + 13.0, iz0 + 18.0]:
		k.disc_down("lamp", Vector3((ix0 + split) * 0.5, E_CEIL - 0.01, z), 0.2)
	for x in [4.0, 16.0, 21.0]:
		for z in [iz0 + 2.5, iz1 - 2.5]:
			k.disc_down("lamp", Vector3(x, E_CEIL - 0.01, z), 0.16)


# --- Planting and lights --------------------------------------------------------------------------

## Palms along the frontage (the aerial counts eight), shrubs in the beds, a few trees in the
## side yard. Nodes rather than merged geometry, so they keep their wind-swaying materials.
static func _plant(root: Node3D) -> void:
	var y := SITE_Y + 0.04
	var palms := [-36.0, -29.0, -21.5, -14.0, 3.5, 10.0, 17.0, 26.0]
	for i in palms.size():
		var mi := MeshInstance3D.new()
		mi.mesh = PropFactory.palm(i % 3)
		var s := 1.05 + 0.12 * float((i * 5) % 3)
		mi.transform = Transform3D(Basis(Vector3.UP, float(i) * 1.7).scaled(Vector3.ONE * s), Vector3(palms[i], y, SITE_Z1 - 1.6))
		root.add_child(mi)
	var x := W_X0
	var i := 0
	while x < SITE_X1 - 1.0:
		if x < STAIR_X0 - 0.8 or x > STAIR_X1 + 0.8:
			var mi := MeshInstance3D.new()
			mi.mesh = PropFactory.model_shrub(i % 4)
			mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			var zz := SITE_Z1 - 0.9 - 0.6 * float((i * 3) % 2)
			mi.transform = Transform3D(Basis(Vector3.UP, float(i) * 2.3).scaled(Vector3.ONE * (0.8 + 0.1 * float(i % 3))), Vector3(x, y, zz))
			root.add_child(mi)
			i += 1
		x += 1.9
	for p in [Vector3(27.0, y, -14.0), Vector3(27.5, y, -4.0), Vector3(-30.0, y, -16.5)]:
		var mi := MeshInstance3D.new()
		mi.mesh = PropFactory.model_tree(int(absf(p.x + p.z)) % PropFactory.CITY_TREES.size())
		mi.position = p
		root.add_child(mi)


## The interior lights: warm, no shadows, on day and night (a hall with its lights on).
static func _lights(root: Node3D) -> void:
	var cx := (W_X0 + W_X1) * 0.5
	var cz := (W_Z0 + W_Z1) * 0.5
	var spots := [
		[Vector3(cx, 7.5, cz), 16.0, HALL_LIGHT],
		[Vector3(cx, 3.8, cz - 5.0), 9.0, HALL_LIGHT * 0.5],
		[Vector3(cx, 3.8, cz + 5.0), 9.0, HALL_LIGHT * 0.5],
		[Vector3(DOME_C.x, 6.0, DOME_C.y), 13.0, HALL_LIGHT * 0.8],
		[Vector3(-2.6, 3.8, 3.0), 8.0, HALL_LIGHT * 0.5],
	]
	for s in spots:
		var l := OmniLight3D.new()
		l.position = s[0]
		l.omni_range = s[1]
		l.light_energy = s[2]
		l.light_color = Color(1.0, 0.9, 0.76)
		l.shadow_enabled = false
		l.distance_fade_enabled = true
		l.distance_fade_begin = 60.0
		l.distance_fade_length = 20.0
		root.add_child(l)


# --- The mesh kit ---------------------------------------------------------------------------------

## Accumulates triangles per material key and, for the solid ones, a collision soup. Winding is
## chosen per triangle to face the normal it is given (Godot's front faces wind clockwise), so
## callers only ever say which way a face looks.
class _Kit:
	var tools := {}
	var faces := PackedVector3Array()

	func _st(key: String) -> SurfaceTool:
		if not tools.has(key):
			var st := SurfaceTool.new()
			st.begin(Mesh.PRIMITIVE_TRIANGLES)
			tools[key] = st
		return tools[key]

	static func _uv(p: Vector3, n: Vector3) -> Vector2:
		var a := n.abs()
		if a.y >= a.x and a.y >= a.z:
			return Vector2(p.x, p.z)
		if a.x >= a.z:
			return Vector2(p.z, -p.y)
		return Vector2(p.x, -p.y)

	func tri(key: String, a: Vector3, b: Vector3, c: Vector3, n: Vector3, solid: bool) -> void:
		tri_n(key, a, b, c, n, n, n, solid)

	func tri_n(key: String, a: Vector3, b: Vector3, c: Vector3, na: Vector3, nb: Vector3, nc: Vector3, solid: bool) -> void:
		var n := (na + nb + nc)
		if (b - a).cross(c - a).dot(n) > 0.0:
			var t := b
			b = c
			c = t
			var tn := nb
			nb = nc
			nc = tn
		var st := _st(key)
		for v in [[a, na], [b, nb], [c, nc]]:
			st.set_normal(v[1])
			st.set_uv(_uv(v[0], n))
			st.add_vertex(v[0])
		if solid:
			faces.append(a)
			faces.append(b)
			faces.append(c)

	func quad(key: String, a: Vector3, b: Vector3, c: Vector3, d: Vector3, n: Vector3, solid: bool) -> void:
		tri(key, a, b, c, n, solid)
		tri(key, a, c, d, n, solid)

	func quad_n(key: String, a: Vector3, b: Vector3, c: Vector3, d: Vector3, na: Vector3, nb: Vector3, nc: Vector3, nd: Vector3, solid: bool) -> void:
		tri_n(key, a, b, c, na, nb, nc, solid)
		tri_n(key, a, c, d, na, nc, nd, solid)

	## A collision-only quad (a fence run, a glazed door).
	func solid_quad(a: Vector3, b: Vector3, c: Vector3, d: Vector3) -> void:
		faces.append_array(PackedVector3Array([a, b, c, a, c, d]))

	## An axis-aligned box. `no_bottom` skips the face nobody sees; `no_top` the one covered.
	func box(key: String, c: Vector3, s: Vector3, solid: bool, no_top: bool = false, no_bottom: bool = true) -> void:
		obox(key, Transform3D(Basis.IDENTITY, c), s, solid, no_top, no_bottom)

	func obox(key: String, xf: Transform3D, s: Vector3, solid: bool, no_top: bool = false, no_bottom: bool = false) -> void:
		var h := s * 0.5
		var dirs := [Vector3.RIGHT, Vector3.LEFT, Vector3.UP, Vector3.DOWN, Vector3.BACK, Vector3.FORWARD]
		for d in dirs:
			if no_top and d == Vector3.UP:
				continue
			if no_bottom and d == Vector3.DOWN:
				continue
			var u := Vector3(d.y, d.z, d.x)
			var v: Vector3 = d.cross(u)
			var c: Vector3 = d * h
			var ue := u * h
			var ve: Vector3 = v * h
			var n: Vector3 = (xf.basis * d).normalized()
			quad(key, xf * (c - ue - ve), xf * (c + ue - ve), xf * (c + ue + ve), xf * (c - ue + ve), n, solid)

	## A horizontal rect facing up at height y.
	func flat(key: String, r: Rect2, y: float, solid: bool = false) -> void:
		quad(key, Vector3(r.position.x, y, r.position.y), Vector3(r.end.x, y, r.position.y), Vector3(r.end.x, y, r.end.y), Vector3(r.position.x, y, r.end.y), Vector3.UP, solid)

	## A horizontal rect facing down (a ceiling) at height y.
	func flat_down(key: String, r: Rect2, y: float) -> void:
		quad(key, Vector3(r.position.x, y, r.position.y), Vector3(r.end.x, y, r.position.y), Vector3(r.end.x, y, r.end.y), Vector3(r.position.x, y, r.end.y), Vector3.DOWN, false)

	## A flat ring between r0 and r1 at `c`, facing up (or down).
	func annulus(key: String, c: Vector3, r0: float, r1: float, sides: int, up: bool) -> void:
		var n := Vector3.UP if up else Vector3.DOWN
		for i in sides:
			var a0 := TAU * float(i) / float(sides)
			var a1 := TAU * float(i + 1) / float(sides)
			var d0 := Vector3(cos(a0), 0.0, sin(a0))
			var d1 := Vector3(cos(a1), 0.0, sin(a1))
			quad(key, c + d0 * r0, c + d1 * r0, c + d1 * r1, c + d0 * r1, n, false)

	## A small downward-facing disc (a recessed light).
	func disc_down(key: String, c: Vector3, r: float) -> void:
		for i in 10:
			var a0 := TAU * float(i) / 10.0
			var a1 := TAU * float(i + 1) / 10.0
			tri(key, c, c + Vector3(cos(a0), 0.0, sin(a0)) * r, c + Vector3(cos(a1), 0.0, sin(a1)) * r, Vector3.DOWN, false)

	## A cylinder or cone frustum standing on `bottom`. `inward` turns its side to face the axis.
	func cyl(key: String, bottom: Vector3, r0: float, r1: float, h: float, sides: int, caps: bool, solid: bool, inward: bool = false) -> void:
		for i in sides:
			var a0 := TAU * float(i) / float(sides)
			var a1 := TAU * float(i + 1) / float(sides)
			var d0 := Vector3(cos(a0), 0.0, sin(a0))
			var d1 := Vector3(cos(a1), 0.0, sin(a1))
			var slope := (r0 - r1) / maxf(h, 0.001)
			var n0 := (d0 + Vector3.UP * slope).normalized()
			var n1 := (d1 + Vector3.UP * slope).normalized()
			if inward:
				n0 = -n0
				n1 = -n1
			var smooth := sides >= 12
			var b0 := bottom + d0 * r0
			var b1 := bottom + d1 * r0
			var t0 := bottom + d0 * r1 + Vector3.UP * h
			var t1 := bottom + d1 * r1 + Vector3.UP * h
			if smooth:
				quad_n(key, b0, b1, t1, t0, n0, n1, n1, n0, solid)
			else:
				quad(key, b0, b1, t1, t0, (n0 + n1).normalized(), solid)
			if caps:
				tri(key, bottom + Vector3.UP * h, t0, t1, Vector3.UP, solid)
				tri(key, bottom, b0, b1, Vector3.DOWN, solid)

	## A surface of revolution: `prof` is (radius, height) from the base up.
	func revolve(key: String, base: Vector3, prof: PackedVector2Array, sides: int, outward: bool, solid: bool) -> void:
		for i in prof.size() - 1:
			var p0 := prof[i]
			var p1 := prof[i + 1]
			var t := Vector2(p1.x - p0.x, p1.y - p0.y).normalized()
			var n2 := Vector2(t.y, -t.x)
			if n2.x < 0.0 and outward:
				n2 = -n2
			if not outward:
				n2 = -n2 if n2.x > 0.0 else n2
			for s in sides:
				var a0 := TAU * float(s) / float(sides)
				var a1 := TAU * float(s + 1) / float(sides)
				var d0 := Vector3(cos(a0), 0.0, sin(a0))
				var d1 := Vector3(cos(a1), 0.0, sin(a1))
				var q00 := base + d0 * p0.x + Vector3.UP * p0.y
				var q10 := base + d1 * p0.x + Vector3.UP * p0.y
				var q11 := base + d1 * p1.x + Vector3.UP * p1.y
				var q01 := base + d0 * p1.x + Vector3.UP * p1.y
				var n00 := (d0 * n2.x + Vector3.UP * n2.y).normalized()
				var n10 := (d1 * n2.x + Vector3.UP * n2.y).normalized()
				if p1.x < 0.001:
					tri_n(key, q00, q10, q01, n00, n10, Vector3.UP if outward else Vector3.DOWN, solid)
				else:
					quad_n(key, q00, q10, q11, q01, n00, n10, n10, n00, solid)

	## Half a dome of revolution opening toward +Z (a mihrab niche head), facing inward.
	func half_dome(key: String, base: Vector3, prof: PackedVector2Array, sides: int) -> void:
		for i in prof.size() - 1:
			var p0 := prof[i]
			var p1 := prof[i + 1]
			for s in sides:
				var a0 := PI * float(s) / float(sides)
				var a1 := PI * float(s + 1) / float(sides)
				var d0 := Vector3(-cos(a0), 0.0, -sin(a0))
				var d1 := Vector3(-cos(a1), 0.0, -sin(a1))
				var q00 := base + d0 * p0.x + Vector3.UP * p0.y
				var q10 := base + d1 * p0.x + Vector3.UP * p0.y
				var q11 := base + d1 * p1.x + Vector3.UP * p1.y
				var q01 := base + d0 * p1.x + Vector3.UP * p1.y
				var n := -((q00 + q11) * 0.5 - base).normalized()
				quad(key, q00, q10, q11, q01, n, false)

	func sphere(key: String, c: Vector3, r: float, seg: int, rings: int) -> void:
		for j in rings:
			var v0 := PI * float(j) / float(rings)
			var v1 := PI * float(j + 1) / float(rings)
			for i in seg:
				var u0 := TAU * float(i) / float(seg)
				var u1 := TAU * float(i + 1) / float(seg)
				var p := func(u: float, v: float) -> Vector3:
					return Vector3(sin(v) * cos(u), cos(v), sin(v) * sin(u))
				var a: Vector3 = p.call(u0, v0)
				var b: Vector3 = p.call(u1, v0)
				var cc: Vector3 = p.call(u1, v1)
				var d: Vector3 = p.call(u0, v1)
				quad_n(key, c + a * r, c + b * r, c + cc * r, c + d * r, a, b, cc, d, false)

	func torus(key: String, c: Vector3, big: float, small: float, seg: int, sides: int) -> void:
		for i in seg:
			var a0 := TAU * float(i) / float(seg)
			var a1 := TAU * float(i + 1) / float(seg)
			for j in sides:
				var b0 := TAU * float(j) / float(sides)
				var b1 := TAU * float(j + 1) / float(sides)
				var p := func(a: float, b: float) -> Vector3:
					var d := Vector3(cos(a), 0.0, sin(a))
					return c + d * (big + small * cos(b)) + Vector3.UP * small * sin(b)
				var nrm := func(a: float, b: float) -> Vector3:
					return (Vector3(cos(a), 0.0, sin(a)) * cos(b) + Vector3.UP * sin(b)).normalized()
				quad_n(key, p.call(a0, b0), p.call(a1, b0), p.call(a1, b1), p.call(a0, b1), nrm.call(a0, b0), nrm.call(a1, b0), nrm.call(a1, b1), nrm.call(a0, b1), false)

	## An octahedron stretched to `s` (a crystal drop, a picket's point).
	func gem(key: String, c: Vector3, s: Vector3) -> void:
		var top := c + Vector3(0.0, s.y, 0.0)
		var bot := c - Vector3(0.0, s.y, 0.0)
		var ring := [c + Vector3(s.x, 0, 0), c + Vector3(0, 0, s.z), c - Vector3(s.x, 0, 0), c - Vector3(0, 0, s.z)]
		for i in 4:
			var a: Vector3 = ring[i]
			var b: Vector3 = ring[(i + 1) % 4]
			var mid := (a + b) * 0.5 - c
			tri(key, top, a, b, (mid + Vector3(0, s.y * 0.5, 0)).normalized(), false)
			tri(key, bot, a, b, (mid - Vector3(0, s.y * 0.5, 0)).normalized(), false)

	## A merlon with a round top: a block `w` wide and `h` tall, then a half-disc on it, `t` deep.
	func merlon_round(key: String, base: Vector3, u: Vector3, n: Vector3, w: float, h: float, t: float) -> void:
		var size := Vector3(absf(u.x) * w + absf(n.x) * t, h, absf(u.z) * w + absf(n.z) * t)
		box(key, base + Vector3(0.0, h * 0.5, 0.0), size, false)
		var r := w * 0.5
		var c := base + Vector3(0.0, h, 0.0)
		var segs := 8
		for i in segs:
			var a0 := PI * float(i) / float(segs)
			var a1 := PI * float(i + 1) / float(segs)
			var p0 := u * (-r * cos(a0)) + Vector3.UP * (r * sin(a0))
			var p1 := u * (-r * cos(a1)) + Vector3.UP * (r * sin(a1))
			for side in [-1.0, 1.0]:
				var off: Vector3 = n * (t * 0.5 * side)
				tri(key, c + off, c + off + p0, c + off + p1, n * side, false)
			var nm := ((p0 + p1) * 0.5).normalized()
			quad(key, c + p0 - n * t * 0.5, c + p1 - n * t * 0.5, c + p1 + n * t * 0.5, c + p0 + n * t * 0.5, nm, false)

	## One ArrayMesh, a surface per material key, in a fixed order so the build is repeatable.
	func commit(mats: Dictionary) -> ArrayMesh:
		var mesh := ArrayMesh.new()
		var keys := tools.keys()
		keys.sort()
		for key in keys:
			var st: SurfaceTool = tools[key]
			st.commit(mesh)
			mesh.surface_set_material(mesh.get_surface_count() - 1, mats.get(key))
			mesh.surface_set_name(mesh.get_surface_count() - 1, key)
		return mesh
