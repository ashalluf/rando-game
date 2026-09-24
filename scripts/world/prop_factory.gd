class_name PropFactory
extends RefCounted
## Meshes for street furniture and trees, built once and shared. Primitives for the cheap
## repeated bits (dashes, stripes, lamps, trees), real CC0 models (Poly Haven, see
## docs/ASSETS.md) for the things the player gets close to: model_* below.

static var _cache: Dictionary = {}

## CC0 texture sets in assets/textures (see docs/ASSETS.md). Map names: Color, NormalGL, Roughness.
const TEXTURE_SETS := {
	"asphalt": "Asphalt033", "brick": "Bricks104", "concrete": "Concrete034", "grass": "Grass004",
	"sand": "Ground054", "metal": "MetalPlates006", "paving": "PavingStones138", "rock": "Rock064",
	"hill": "AerialGrassRock", "hill_rock": "RockyTerrain02",
	# Street surface sets (Poly Haven), picked per road and per block for variety.
	"asphalt_aerial": "AerialAsphalt01", "pavers": "LargeSquarePattern01", "sidewalk": "GravelConcrete03",
	# Facade sets (Poly Haven), picked per building by Building._apply_wall_texture().
	"brick_red": "RedBrick", "brick_mossy": "Brick4", "brick_factory": "RedBrick03",
	"plaster_painted": "PaintedPlasterWall", "plaster_beige": "BeigeWall001", "plaster_white": "WhitePlaster02",
	"concrete_painted": "ConcreteWall003", "concrete_cracked": "CrackedConcreteWall", "concrete_layers": "ConcreteLayers02",
	"metal_corrugated": "CorrugatedIron", "metal_factory": "FactoryWall",
	# Facade detail kit (ambientCG): awning canvas, painted steel, weathered tank staves.
	"fabric": "Fabric036", "metal_painted": "Metal016", "planks": "Planks023A",
	# Clay barrel tiles (Poly Haven), the Esplanade replica's pitched roofs.
	"roof_clay": "ClayRoofTiles02",
	# Encampment kit (ambientCG): tent nylon, woven poly tarp, torn cardboard, mattress ticking,
	# wool blanket, trash-bag plastic.
	"camp_nylon": "Fabric048", "camp_tarp": "Fabric015", "camp_cardboard": "Cardboard001",
	"camp_ticking": "Fabric040", "camp_wool": "Fabric031", "camp_plastic": "Plastic006",
}


static func texture(set_key: String, map: String) -> Texture2D:
	var set_name: String = TEXTURE_SETS.get(set_key, set_key)
	var key := "tex_%s_%s" % [set_name, map]
	if _cache.has(key):
		return _cache[key]
	var path := "res://assets/textures/%s/%s_1K-JPG_%s.jpg" % [set_name, set_name, map]
	var tex: Texture2D = load(path) if ResourceLoader.exists(path) else null
	_cache[key] = tex
	return tex


## A textured material projected in world space (triplanar), `scale_m` meters per tile.
## `vertex_color` turns on vertex_color_use_as_albedo, for a surface that carries large-scale
## tone the texture cannot - the beach's wet/dry banding, which a 5 m tile mips away by forty
## metres. It is part of the cache key, so it never leaks into anything else's material.
static func pbr(set_key: String, scale_m: float = 4.0, tint: Color = Color.WHITE, roughness_scale: float = 1.0, vertex_color: bool = false) -> StandardMaterial3D:
	var key := "pbr_%s_%.2f_%s_%.2f_%s" % [set_key, scale_m, tint, roughness_scale, vertex_color]
	if _cache.has(key):
		return _cache[key]
	var mat := StandardMaterial3D.new()
	mat.albedo_color = tint
	mat.albedo_texture = texture(set_key, "Color")
	var normal := texture(set_key, "NormalGL")
	if normal:
		mat.normal_enabled = true
		mat.normal_texture = normal
		mat.normal_scale = 0.8
	var rough := texture(set_key, "Roughness")
	if rough:
		mat.roughness_texture = rough
		mat.roughness_texture_channel = BaseMaterial3D.TEXTURE_CHANNEL_RED
	mat.roughness = roughness_scale
	mat.vertex_color_use_as_albedo = vertex_color
	mat.uv1_triplanar = true
	mat.uv1_world_triplanar = true
	mat.uv1_scale = Vector3.ONE / scale_m
	mat.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS_ANISOTROPIC
	_cache[key] = mat
	return mat


## Lawns and park grass (see shaders/lawn.gdshader). A tiled grass texture mips down to one
## flat green rectangle from any height, and the grass-blade multimesh only reaches a few dozen
## metres, so past that the ground itself has to carry the detail: dry patches, mower stripes and
## worn dirt, all from world position. Cached per tint, seed and dryness like the road material.
static func lawn(tint: Color, seed_value: int, dryness: float = 0.35, stripes: float = 3.4) -> ShaderMaterial:
	var key := "lawn_%d_%d_%.2f_%.2f" % [tint.to_rgba32(), seed_value, dryness, stripes]
	if _cache.has(key):
		return _cache[key]
	var mat := ShaderMaterial.new()
	mat.shader = load("res://shaders/lawn.gdshader")
	mat.set_shader_parameter("albedo_tex", texture("grass", "Color"))
	mat.set_shader_parameter("normal_tex", texture("grass", "NormalGL"))
	mat.set_shader_parameter("rough_tex", texture("grass", "Roughness"))
	mat.set_shader_parameter("tint", tint)
	mat.set_shader_parameter("tex_scale", 5.0)
	mat.set_shader_parameter("seed", float(seed_value % 997) * 0.37)
	mat.set_shader_parameter("dryness", dryness)
	mat.set_shader_parameter("stripe_width", stripes)
	_cache[key] = mat
	return mat


## The linear mean albedo of a texture set's colour map, measured from the 1K JPG (numpy over
## every texel, sRGB decoded). Only for what is seen from so far that it is one colour - the far
## city's plates under an airport apron or a port yard, which the chunks draw with road() and a
## tint well above 1. Add a set here when a non-city zone lays its ground with it.
const TEXTURE_MEAN := {
	"asphalt": Color(0.0936, 0.0844, 0.0645), "concrete": Color(0.4818, 0.4818, 0.4818),
	"asphalt_aerial": Color(0.1382, 0.1265, 0.1408), "sidewalk": Color(0.1042, 0.1034, 0.0877),
}


## The colour (LINEAR) a surface drawn with `mat` averages to from a long way off: a road()
## material is its texture's mean times its tint, a plain material its albedo; anything else is
## `fallback`. The far city uses it so a plate matches the ground the LOD chunk actually drew.
static func far_albedo(mat: Material, fallback: Color) -> Color:
	if mat is ShaderMaterial and mat.has_meta("texture_set"):
		var mean: Color = TEXTURE_MEAN.get(str(mat.get_meta("texture_set")), Color(-1.0, 0.0, 0.0))
		var tint = (mat as ShaderMaterial).get_shader_parameter("tint")
		if mean.r >= 0.0 and tint is Color:
			var t: Color = (tint as Color).srgb_to_linear()
			return Color(mean.r * t.r, mean.g * t.g, mean.b * t.b, 1.0)
	elif mat is StandardMaterial3D and (mat as StandardMaterial3D).albedo_texture == null:
		var c := (mat as StandardMaterial3D).albedo_color.srgb_to_linear()
		return Color(c.r, c.g, c.b, 1.0)
	return fallback


## Worn asphalt for road surfaces (see shaders/road.gdshader). Cached per set, scale, tint and
## seed, so every road in a chunk shares one material.
static func road(set_key: String, scale_m: float, tint: Color, seed_value: int, joints: float = 0.0, wear: float = 1.0) -> ShaderMaterial:
	# The tint goes into the key as itself, not through to_rgba32(): that clamps each channel to
	# 0..255, so any two tints above 1.0 collide and the second caller silently gets the first
	# one's material. Paving tints run above 1.0 (a tint multiplies, so only a tint above 1 can
	# brighten a dark texture set) and SUBURBS has two "sidewalk" rows that would have merged.
	var key := "road_%s_%.2f_%s_%d_%.2f_%.2f" % [set_key, scale_m, tint, seed_value, joints, wear]
	if _cache.has(key):
		return _cache[key]
	var mat := ShaderMaterial.new()
	mat.shader = load("res://shaders/road.gdshader")
	mat.set_shader_parameter("albedo_tex", texture(set_key, "Color"))
	mat.set_shader_parameter("normal_tex", texture(set_key, "NormalGL"))
	mat.set_shader_parameter("rough_tex", texture(set_key, "Roughness"))
	mat.set_shader_parameter("tint", tint)
	mat.set_shader_parameter("tex_scale", scale_m)
	mat.set_shader_parameter("seed", float(seed_value % 997) * 0.37)
	mat.set_shader_parameter("joint_spacing", joints)
	# Pavements are patched and stained far less than the carriageway.
	mat.set_shader_parameter("patch_amount", 0.30 * wear)
	mat.set_shader_parameter("crack_amount", 0.5 * wear)
	mat.set_shader_parameter("stain_amount", 0.32 * wear)
	mat.set_meta("texture_set", set_key)
	_cache[key] = mat
	return mat


static func terrain_material() -> ShaderMaterial:
	if _cache.has("terrain_mat"):
		return _cache["terrain_mat"]
	var mat := ShaderMaterial.new()
	mat.shader = load("res://shaders/terrain.gdshader")
	mat.set_shader_parameter("grass_albedo", texture("hill", "Color"))
	mat.set_shader_parameter("grass_normal", texture("hill", "NormalGL"))
	mat.set_shader_parameter("rock_albedo", texture("hill_rock", "Color"))
	mat.set_shader_parameter("rock_normal", texture("hill_rock", "NormalGL"))
	_cache["terrain_mat"] = mat
	return mat


static func material(color: Color, roughness: float = 0.85, unshaded: bool = false) -> StandardMaterial3D:
	var key := "m%d_%d_%d" % [color.to_rgba32(), int(roughness * 100), int(unshaded)]
	if _cache.has(key):
		return _cache[key]
	var mat := StandardMaterial3D.new()
	mat.albedo_color = color
	mat.roughness = roughness
	mat.vertex_color_use_as_albedo = true
	if unshaded:
		mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_cache[key] = mat
	return mat


static func box(key: String, size: Vector3, color: Color) -> Mesh:
	if _cache.has(key):
		return _cache[key]
	var mesh := BoxMesh.new()
	mesh.size = size
	mesh.material = material(color)
	_cache[key] = mesh
	return mesh


## A capped cylinder. `segments` defaults to 16, not 8: every pole, bollard and hydrant in
## this city is one of these, the player walks right past them, and a six-sided pole in the
## foreground is a six-sided pole. Sixteen sides on a lamp post is about 60 triangles.
static func cylinder(key: String, radius: float, height: float, color: Color, top_radius: float = -1.0, segments: int = 16) -> Mesh:
	if _cache.has(key):
		return _cache[key]
	var mesh := CylinderMesh.new()
	mesh.bottom_radius = radius
	mesh.top_radius = radius if top_radius < 0.0 else top_radius
	mesh.height = height
	mesh.radial_segments = segments
	mesh.rings = 1
	mesh.material = material(color)
	_cache[key] = mesh
	return mesh


# --- Ready-made pieces (origin at the base, Y up) ---------------------------------

static func trunk() -> Mesh:
	return cylinder("trunk", 0.18, 2.2, Color(0.42, 0.30, 0.18), 0.14, 14)


static func canopy_round() -> Mesh:
	if _cache.has("canopy_round"):
		return _cache["canopy_round"]
	var mesh := SphereMesh.new()
	mesh.radius = 1.6
	mesh.height = 3.2
	mesh.radial_segments = 18
	mesh.rings = 12
	mesh.material = material(Color(0.32, 0.58, 0.28))
	_cache["canopy_round"] = mesh
	return mesh


static func canopy_cone() -> Mesh:
	return cylinder("canopy_cone", 1.5, 4.0, Color(0.20, 0.45, 0.24), 0.0, 16)


static func lamp_pole() -> Mesh:
	return cylinder("lamp_pole", 0.09, 6.0, Color(0.28, 0.29, 0.32), 0.07, 14)


static func lamp_head() -> Mesh:
	if _cache.has("lamp_head"):
		return _cache["lamp_head"]
	var mesh := BoxMesh.new()
	mesh.size = Vector3(0.7, 0.18, 0.3)
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(1.0, 0.95, 0.8)
	mat.emission_enabled = true
	mat.emission = Color(1.0, 0.9, 0.6)
	mat.emission_energy_multiplier = 1.5
	mat.vertex_color_use_as_albedo = true
	mesh.material = mat
	_cache["lamp_head"] = mesh
	return mesh


## A tuft of real grass blades for the lawn MultiMesh. Each blade is a tapered, curved strip
## (four segments, narrowing to a point, leaning further over toward the tip) rather than the
## single upright 14 x 55 cm rectangle this used to be, which read as a green flag stuck in the
## ground. Blades fan out around the tuft centre at different heights and angles.
##
## The important trick is the normals: they are bent toward straight up instead of pointing out
## of each blade's face. Lit per-face, a field of blades turns into a mess of bright and black
## slivers; lit as if it were one soft surface, it reads as a carpet of grass. Every real-time
## grass system does this.
## Ten blades of four segments, each split down a midrib, is 160 triangles a tuft against the
## 30 it used to be. A tuft is one mesh in the "grass" MultiMesh batch, so this costs no extra
## draw call at all - a lawn is still one draw whatever a blade is made of.
const GRASS_BLADES := 10
const GRASS_SEGMENTS := 4
const GRASS_HEIGHT := 0.34
const GRASS_WIDTH := 0.018
## How far the midrib stands out of the chord between the blade's two edges, as a fraction of
## the half-width. A grass blade is a folded V in section, not a ribbon, and it is the two
## halves catching the light at different angles that stops close-up grass reading as plastic.
const GRASS_CREASE := 0.6


static func grass_blade() -> Mesh:
	if _cache.has("grass_blade"):
		return _cache["grass_blade"]
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var rng := RandomNumberGenerator.new()
	rng.seed = 90210
	for b in GRASS_BLADES:
		var yaw := TAU * (float(b) / GRASS_BLADES) + rng.randf_range(-0.30, 0.30)
		var dir := Vector3(sin(yaw), 0.0, cos(yaw))
		var side := Vector3(dir.z, 0.0, -dir.x)
		var height := GRASS_HEIGHT * rng.randf_range(0.42, 1.35)
		var width := GRASS_WIDTH * rng.randf_range(0.8, 1.2)
		# How far the tip leans away from vertical, and where the blade starts.
		var lean := rng.randf_range(0.24, 0.78) * height
		var root := dir * rng.randf_range(0.0, 0.055)
		# A little twist along the length, so the two halves of the blade do not present the
		# same face to the sun all the way up.
		var twist := rng.randf_range(-0.55, 0.55)
		for seg in GRASS_SEGMENTS:
			var t0 := float(seg) / GRASS_SEGMENTS
			var t1 := float(seg + 1) / GRASS_SEGMENTS
			# Quadratic bend: the blade is upright at the root and arcs over near the tip.
			var p0 := root + Vector3(0.0, height * t0, 0.0) + dir * (lean * t0 * t0)
			var p1 := root + Vector3(0.0, height * t1, 0.0) + dir * (lean * t1 * t1)
			# Widest just above the sheath, running out to a real point rather than stopping
			# at 15 per cent of the width the way a three-segment strip had to.
			var w0 := width * (1.0 - pow(t0, 1.3) * 0.96)
			var w1 := width * (1.0 - pow(t1, 1.3) * 0.96)
			var along := (p1 - p0).normalized()
			var face := side.cross(along).normalized()
			var s0 := side.rotated(along, twist * t0)
			var s1 := side.rotated(along, twist * t1)
			# The midrib, proud of the chord between the edges.
			var c0 := p0 + face * (w0 * GRASS_CREASE)
			var c1 := p1 + face * (w1 * GRASS_CREASE)
			# One normal per half, tilted toward that half's edge and then bent hard toward up
			# so the tuft still lights as one soft surface instead of a pile of lit slivers.
			var nl := face.lerp(-s0, 0.34).normalized().lerp(Vector3.UP, 0.6).normalized()
			var nr := face.lerp(s0, 0.34).normalized().lerp(Vector3.UP, 0.6).normalized()
			_grass_quad(st, p0 - s0 * w0, c0, c1, p1 - s1 * w1, nl, t0, t1)
			_grass_quad(st, c0, p0 + s0 * w0, p1 + s1 * w1, c1, nr, t0, t1)
	var mesh := st.commit()
	var mat := ShaderMaterial.new()
	mat.shader = load("res://shaders/grass.gdshader")
	mesh.surface_set_material(0, mat)
	_cache["grass_blade"] = mesh
	return mesh


## One half of a creased grass blade: a-b sit at `t0` up the blade, c-d at `t1`, sharing one
## smooth normal. UV.y is the height the grass shader shades from, so it has to be the blade's
## own fraction and not the tuft's.
static func _grass_quad(st: SurfaceTool, a: Vector3, b: Vector3, c: Vector3, d: Vector3, n: Vector3, t0: float, t1: float) -> void:
	for v: Array in [[a, t0], [b, t0], [c, t1], [a, t0], [c, t1], [d, t1]]:
		st.set_normal(n)
		st.set_uv(Vector2(0.5, v[1]))
		st.add_vertex(v[0])


static func bush() -> Mesh:
	if _cache.has("bush"):
		return _cache["bush"]
	var mesh := SphereMesh.new()
	mesh.radius = 0.9
	mesh.height = 1.4
	mesh.radial_segments = 16
	mesh.rings = 10
	mesh.material = material(Color(0.30, 0.52, 0.26))
	_cache["bush"] = mesh
	return mesh


static func bench() -> Mesh:
	return box("bench", Vector3(1.8, 0.1, 0.5), Color(0.5, 0.36, 0.22))


static func bench_legs() -> Mesh:
	return box("bench_legs", Vector3(1.6, 0.45, 0.4), Color(0.25, 0.25, 0.27))


static func hydrant() -> Mesh:
	return cylinder("hydrant", 0.16, 0.8, Color(0.85, 0.15, 0.12), 0.12, 16)


## Center-line piece; white so the instance color picks yellow or white.
static func dash() -> Mesh:
	return box("dash", Vector3(0.16, 0.02, 3.0), Color(1.0, 1.0, 1.0))


## Shared worn-paint material for every road marking batch (shaders/road_paint.gdshader).
static func road_paint_material() -> ShaderMaterial:
	if _cache.has("road_paint_mat"):
		return _cache["road_paint_mat"]
	var mat := ShaderMaterial.new()
	mat.shader = load("res://shaders/road_paint.gdshader")
	_cache["road_paint_mat"] = mat
	return mat


static func stripe() -> Mesh:
	return box("stripe", Vector3(0.6, 0.02, 3.0), Color(0.95, 0.95, 0.92))


static func sign_pole() -> Mesh:
	return cylinder("sign_pole", 0.05, 2.6, Color(0.5, 0.5, 0.52), -1.0, 12)


static func stop_sign() -> Mesh:
	return cylinder("stop_sign", 0.45, 0.05, Color(0.8, 0.12, 0.1), -1.0, 8)


static func signal_pole() -> Mesh:
	return cylinder("signal_pole", 0.12, 6.5, Color(0.2, 0.2, 0.22), 0.1, 16)


static func signal_arm() -> Mesh:
	return box("signal_arm", Vector3(5.0, 0.14, 0.14), Color(0.2, 0.2, 0.22))


static func signal_box() -> Mesh:
	return box("signal_box", Vector3(0.35, 1.0, 0.35), Color(0.15, 0.15, 0.16))


static func signal_light(color: Color) -> Mesh:
	var key := "signal_light_%d" % color.to_rgba32()
	if _cache.has(key):
		return _cache[key]
	var mesh := SphereMesh.new()
	mesh.radius = 0.12
	mesh.height = 0.24
	mesh.radial_segments = 14
	mesh.rings = 9
	mesh.material = material(color, 0.5, true)
	_cache[key] = mesh
	return mesh


static func trash_can_mesh() -> Mesh:
	return cylinder("trash_can", 0.35, 1.0, Color(0.25, 0.35, 0.3), -1.0, 20)


## A whole palm tree as one mesh: a curved tapering trunk with a ridged bark profile, a crown of
## drooping fronds built from real leaflets, a skirt of dead fronds and a few coconuts. Three
## seeded variants. Owner, 2026-09-20: "it's Cali, put palm trees" - the old palm was a cylinder
## with three flat boxes stuck on top, which is the least convincing thing in the game.
##
## It is one mesh with vertex colours rather than several, so a street of palms is one MultiMesh
## draw. Frond leaflets are single-sided quads, so the material disables backface culling.
## Six, not three: a promenade lined with palms at even spacing shows the repeat immediately.
##
## Each variant is one cached mesh of about 24k triangles, up from 5.6k. That is deliberate and
## it is the cheapest realism in the game: the mesh is shared by every palm on the street through
## one MultiMesh, so a boulevard of two hundred of them is still ONE draw call whatever the mesh
## costs, and a palm crown is pure silhouette against the sky - the one place the eye finds a
## straight edge or a missing leaflet instantly.
const PALM_VARIANTS := 6
## Trunk tessellation. 40 x 18 instead of 22 x 10: at street level the old trunk showed ten flat
## facets round its circumference, and a ten-sided pole in the foreground is a ten-sided pole.
const PALM_TRUNK_RINGS := 40
const PALM_TRUNK_SIDES := 18
## Leaflet pairs along one frond. A real Washingtonia frond carries fifty-odd a side.
const PALM_FROND_STEPS := 60
const PALM_DEAD_STEPS := 38
## Length segments in one leaflet. A leaflet that is a single quad cannot droop or come to a
## point; a frond of flat quads reads as a comb, which is what the old crown did edge-on.
const PALM_LEAFLET_SEGMENTS := 4
## Which way each palm variant's trunk leans, as a yaw in radians, filled in by palm() as it
## builds. A street palm's crown is three metres across and its trunk leans up to another 1.5 m,
## so on a four-metre pavement with the building on the lot line the crown WILL reach the wall -
## and a frond modelled through a glass facade is the single most obvious kind of wrong. Instead
## of shrinking the palms, CityChunk turns each one so its lean points at the road; see
## palm_lean() and CityChunk._add_palm().
static var _palm_lean: Dictionary = {}


## The baked lean yaw of a palm variant, so a caller can cancel it and aim the lean somewhere.
static func palm_lean(variant: int) -> float:
	if not _palm_lean.has(variant):
		palm(variant)
	return _palm_lean.get(variant, 0.0)


static func palm(variant: int) -> Mesh:
	var key := "palm_%d" % variant
	if _cache.has(key):
		return _cache[key]
	var rng := RandomNumberGenerator.new()
	rng.seed = 7000 + variant
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)

	# Tall and slender, like the Washingtonia palms that line Los Angeles streets, rather than
	# the short fat coconut palm the old primitive suggested.
	var height := rng.randf_range(9.0, 18.5)
	# Palms lean, and the lean grows toward the top rather than tilting the whole trunk.
	var lean_angle := rng.randf() * TAU
	var lean_dir := Vector3(cos(lean_angle), 0.0, sin(lean_angle))
	var lean := rng.randf_range(0.4, 1.5)
	# Yaw of that lean in the mesh's own space, so an instance can rotate it to point at the road.
	_palm_lean[variant] = atan2(lean_dir.x, lean_dir.z)
	var segments := PALM_TRUNK_RINGS
	var sides := PALM_TRUNK_SIDES
	# Grey-tan, not chocolate: a Washingtonia trunk is the colour of dry rope.
	var bark := Color(0.46, 0.41, 0.33)

	var centre := func(t: float) -> Vector3:
		return Vector3(0.0, height * t, 0.0) + lean_dir * (lean * t * t)
	# Taper toward the crown, a swell at the root, and a ring ridge per old frond scar. Kept as
	# a function so the boots and the crownshaft sit on the trunk instead of near it.
	var radius := func(t: float, ring: int) -> float:
		return lerpf(0.30, 0.13, t) * (1.0 + 0.38 * exp(-t * 8.0)) * (1.0 + (0.030 if ring % 2 == 0 else -0.030))

	for i in segments:
		var t0 := float(i) / segments
		var t1 := float(i + 1) / segments
		var c0: Vector3 = centre.call(t0)
		var c1: Vector3 = centre.call(t1)
		var r0: float = radius.call(t0, i)
		var r1: float = radius.call(t1, i + 1)
		var shade0 := bark * (0.90 + 0.16 * float(i % 3) / 2.0)
		# The criss-cross of old frond bases. A palm trunk is not a smooth pole: it is a
		# lattice of cut stubs in a diamond lattice, and at street level that pattern is
		# the thing that tells you which tree you are standing under.
		# Subtle: at 0.76 this read as a chessboard wrapped round the trunk from two metres
		# away. Real frond scars are a shallow change in tone, not two colours.
		#
		# The lattice indices are scaled back to the 22 x 10 grid it was tuned on. Alternating
		# per quad at 40 x 18 would put the diamonds below a pixel at any distance and shimmer.
		var li := int(float(i) * 22.0 / float(segments))
		for k in sides:
			var a0 := TAU * k / sides
			var a1 := TAU * (k + 1) / sides
			var d0 := Vector3(cos(a0), 0.0, sin(a0))
			var d1 := Vector3(cos(a1), 0.0, sin(a1))
			var lk := int(float(k) * 10.0 / float(sides))
			var lattice := 1.0 if (li + lk) % 2 == 0 else 0.91
			# Break the perfect alternation so it is a lattice, not a checker.
			if (li * 3 + lk * 5) % 7 == 0:
				lattice = 0.96
			# The pattern wears away toward the base, where the trunk has gone smooth and grey.
			lattice = lerpf(1.0, lattice, smoothstep(0.08, 0.35, t0))
			_quad(st, c0 + d0 * r0, c0 + d1 * r0, c1 + d1 * r1, c1 + d0 * r1, shade0 * lattice, d0, d1)

	# The boots: the sawn-off stubs of old fronds, as real geometry on the upper trunk rather
	# than only as a change of tone. Standing under a palm these are the whole difference
	# between a grey pole and a tree, and they break the trunk's outline against the sky.
	for ring in 6:
		var bt: float = lerpf(0.58, 0.962, float(ring) / 5.0)
		var bc: Vector3 = centre.call(bt)
		var br: float = radius.call(bt, ring * 2)
		var boots := 9
		for k in boots:
			var ba := TAU * (float(k) + 0.5 * float(ring % 2)) / float(boots)
			var bd := Vector3(cos(ba), 0.0, sin(ba))
			var bs := Vector3(-bd.z, 0.0, bd.x)
			var bw := bs * (br * 0.62)
			var bl := bd * (br * rng.randf_range(0.55, 0.95))
			var bh := Vector3(0.0, -0.085 * (height / 14.0), 0.0)
			var e0 := bc + bd * (br * 0.94) - bw
			var e1 := bc + bd * (br * 0.94) + bw
			var tip0 := e0 + bl + bh
			var tip1 := e1 + bl + bh
			var boot := bark * rng.randf_range(0.76, 1.02)
			var nt := (Vector3.UP * 0.85 + bd).normalized()
			_quad(st, e0, e1, tip1, tip0, boot, nt, nt)
			var under := Vector3(0.0, -0.045 * (height / 14.0), 0.0)
			_quad(st, tip0 + under, tip1 + under, e1 + under, e0 + under, boot * 0.66, -nt, -nt)

	var top: Vector3 = centre.call(1.0)
	# The crownshaft: the smooth green column the fronds actually grow out of. Without it the
	# fronds sprout straight off the flat top of a pipe, which is what the old crown did.
	var r_top: float = radius.call(1.0, segments)
	var shaft_h := maxf(0.38, height * 0.038)
	var shaft := Color(0.33, 0.36, 0.23)
	var shaft_rings := 7
	for i in shaft_rings:
		var u0 := float(i) / shaft_rings
		var u1 := float(i + 1) / shaft_rings
		var c0 := top + Vector3(0.0, shaft_h * u0, 0.0) + lean_dir * (lean * 0.07 * u0)
		var c1 := top + Vector3(0.0, shaft_h * u1, 0.0) + lean_dir * (lean * 0.07 * u1)
		var r0 := lerpf(r_top * 1.06, r_top * 0.45, u0 * u0)
		var r1 := lerpf(r_top * 1.06, r_top * 0.45, u1 * u1)
		var tone := bark.lerp(shaft, smoothstep(0.0, 0.8, u0))
		for k in sides:
			var a0 := TAU * k / sides
			var a1 := TAU * (k + 1) / sides
			var d0 := Vector3(cos(a0), 0.0, sin(a0))
			var d1 := Vector3(cos(a1), 0.0, sin(a1))
			_quad(st, c0 + d0 * r0, c0 + d1 * r0, c1 + d1 * r1, c1 + d0 * r1, tone, d0, d1)

	var crown := top + Vector3(0.0, shaft_h * 0.72, 0.0)
	var fronds := rng.randi_range(14, 19)
	for f in fronds:
		# Uneven spacing and a wide spread of length and lift, or the crown is a perfect disc
		# and every palm on the street is the same tree. Real crowns carry fronds of several
		# ages at once: new ones held up, old ones nearly horizontal.
		var yaw := TAU * f / fronds + rng.randf_range(-0.30, 0.30)
		_palm_frond(st, crown, yaw, rng.randf_range(3.1, 6.1), rng.randf_range(-0.35, 1.05), rng, false)
	# A skirt of dead fronds hanging under the crown.
	for f in rng.randi_range(4, 7):
		var yaw := rng.randf_range(0.0, TAU)
		_palm_frond(st, top + Vector3(0.0, -0.25, 0.0), yaw, rng.randf_range(2.0, 3.0), -1.25, rng, true)
	# Coconuts clustered under the crown. Round ones: an eight-triangle octahedron at arm's
	# length is a cut gemstone, not a fruit.
	for c in rng.randi_range(4, 8):
		var a := rng.randf_range(0.0, TAU)
		var at := top + Vector3(cos(a), 0.0, sin(a)) * rng.randf_range(0.15, 0.45) + Vector3(0.0, -0.35, 0.0)
		var cr := rng.randf_range(0.13, 0.19)
		_sphere_into(st, at, Vector3(cr, cr * 1.18, cr), Color(0.40, 0.30, 0.17) * rng.randf_range(0.85, 1.12))

	# No generate_normals() here. Flat per-triangle normals are what made the crown read as a
	# folded paper fan: every leaflet caught the light at its own angle, so the canopy was a
	# mess of bright and black shards. Every part sets its own smooth normal instead, the same
	# trick the grass blades use.
	# Indexed and given LODs like every imported model. It had none: 22,600 triangles per palm
	# at any distance, in the view and in every shadow cascade, down a whole boulevard of them.
	# The renderer only switches LOD below a pixel of error, so up close nothing changes.
	st.index()
	var im := ImporterMesh.new()
	# Wind sway lives in the vertex shader (shaders/foliage.gdshader), so a palm-lined street
	# moves without any per-tree work on the CPU. Backface culling stays off: leaflets are
	# single-sided.
	im.add_surface(Mesh.PRIMITIVE_TRIANGLES, st.commit_to_arrays(), [], {}, foliage_material())
	im.generate_lods(25.0, 60.0, [])
	var mesh := im.get_mesh()
	_build_shadow_proxy(im, mesh, 0.45, 0.45)
	var proxy := shadow_proxy(mesh)
	if proxy:
		proxy.surface_set_material(0, foliage_material())
	_cache[key] = mesh
	return mesh


## One frond: a rachis arcing out and drooping, carrying a folded rank of narrow leaflets.
## `rise` lifts the frond before it droops; dead fronds hang almost straight down and go brown.
##
## The shape that matters is the FOLD. A palm frond is not flat: it is creased along its rib
## like a paper fan stood on edge, steeply folded where it leaves the crown and opening out
## toward the tip. Laying the leaflets flat in one plane - which is what this did first - makes
## each one overlap its neighbours into a solid sheet, and the crown reads as a green paper fan
## rather than a tree. Folding them, and jittering the fold per leaflet, is what opens daylight
## between the blades and gives the canopy its depth.
static func _palm_frond(st: SurfaceTool, base: Vector3, yaw: float, reach: float, rise: float, rng: RandomNumberGenerator, dead: bool) -> void:
	var out := Vector3(cos(yaw), 0.0, sin(yaw))
	var side := Vector3(-out.z, 0.0, out.x)
	# Dense: a real frond carries fifty-odd leaflets a side, close enough at the rib that the
	# frond reads as one feathered blade. At thirty they are separate spikes and it reads as a
	# fishbone.
	var steps := PALM_DEAD_STEPS if dead else PALM_FROND_STEPS
	# Each frond droops by its own amount, or the crown is a set of identical arcs.
	var droop := reach * (1.5 if dead else rng.randf_range(0.55, 1.25))
	# Palm fronds are a dusty, yellow-grey green, not the vivid green of a lawn, and the tone
	# runs from dark near the rachis to bleached at the tips.
	var green := Color(0.17, 0.26, 0.11).lerp(Color(0.36, 0.43, 0.19), rng.randf())
	var colour := Color(0.46, 0.37, 0.20) if dead else green
	# Fold angle down from horizontal: steep at the base of the frond, nearly flat at the tip.
	var fold_base := rng.randf_range(0.55, 1.00)
	var fold_tip := rng.randf_range(0.08, 0.34)
	var rachis := func(t: float) -> Vector3:
		return base + out * (reach * t) + Vector3(0.0, rise * t - droop * t * t, 0.0)
	for i in steps:
		var t0 := float(i) / steps
		var t1 := float(i + 1) / steps
		var p0: Vector3 = rachis.call(t0)
		var p1: Vector3 = rachis.call(t1)
		var along := p1 - p0
		# Longest a third of the way out, short at the crown and short again at the tip, so the
		# frond has a leaf shape instead of a rectangular comb.
		var blade := reach * 0.30 * (0.22 + 0.78 * sin(pow(t0, 0.72) * PI))
		var tone := colour * (0.78 + 0.42 * t0) * rng.randf_range(0.90, 1.10)
		for dir: float in [1.0, -1.0]:
			# The fold, jittered per leaflet: neighbours at slightly different angles are what
			# let the light through instead of shingling into a sheet.
			var ang := lerpf(fold_base, fold_tip, t0) * rng.randf_range(0.72, 1.28)
			# Swept FORWARD, toward the tip of the frond, the way a feather's barbs lie. Swept
			# back - which is what this did - points every leaflet at the trunk and the frond
			# reads as a fishbone laid the wrong way round.
			var blade_dir := (side * dir * cos(ang) - Vector3.UP * sin(ang) + out * 0.58).normalized()
			# One smooth normal per leaflet, leaning hard toward up, so the crown lights as one
			# soft mass rather than a pile of lit facets catching the sun at their own angles.
			var nrm := (Vector3.UP * 1.7 + blade_dir * 0.45).normalized()
			# Tips curl further down the further out along the frond they sit.
			_palm_leaflet(st, p0, p1 + along * 0.06, blade_dir, blade, blade * (0.16 + 0.42 * t0), tone, nrm)
		# The rachis itself, as a shallow V in section rather than a flat ribbon, so the frond
		# still reads when the light is edge-on to it.
		var rib_n := (Vector3.UP + out * 0.3).normalized()
		var rib_w := side * (0.030 * (1.0 - t0 * 0.55))
		var keel := Vector3(0.0, -0.05 * (1.0 - t0 * 0.5), 0.0)
		_quad(st, p0 - rib_w, p1 - rib_w, p1 + keel, p0 + keel, colour * 0.58, rib_n, rib_n)
		_quad(st, p0 + keel, p1 + keel, p1 + rib_w, p0 + rib_w, colour * 0.52, rib_n, rib_n)


## One leaflet of a frond: a tapered blade leaving the rachis between `a` and `b`, running
## `length` out along `dir`, narrowing to a real point and curling `curl` metres down at the
## tip. Built in PALM_LEAFLET_SEGMENTS pieces rather than as one quad, because a quad cannot
## bend: a frond of straight quads is a comb, and the droop of the outer leaflets is most of
## what gives a palm crown its shape against the sky.
static func _palm_leaflet(st: SurfaceTool, a: Vector3, b: Vector3, dir: Vector3, length: float,
		curl: float, colour: Color, nrm: Vector3) -> void:
	var mid := (a + b) * 0.5
	var half := (b - a) * 0.5
	var prev_a := a
	var prev_b := b
	for seg in PALM_LEAFLET_SEGMENTS:
		var u := float(seg + 1) / float(PALM_LEAFLET_SEGMENTS)
		# Width runs out to nothing at the tip; the drop is the leaflet's own droop.
		var w := 1.0 - pow(u, 0.8)
		var c := mid + dir * (length * u) + Vector3(0.0, -curl * u * u, 0.0)
		var tone := colour * (1.0 - 0.12 * u)
		var na := c - half * w
		var nb := c + half * w
		if seg == PALM_LEAFLET_SEGMENTS - 1:
			# The tip: one triangle closing on the point.
			for v: Vector3 in [prev_a, prev_b, c]:
				st.set_color(tone)
				st.set_uv(Vector2.ZERO)
				st.set_normal(nrm)
				st.add_vertex(v)
		else:
			_quad(st, prev_a, prev_b, nb, na, tone, nrm, nrm)
		prev_a = na
		prev_b = nb


## A quad a-b-c-d. `na` / `nb` are the normals for the a,d and b,c edges; leave them at zero to
## let the caller's generate_normals() work it out (flat shading).
static func _quad(st: SurfaceTool, a: Vector3, b: Vector3, c: Vector3, d: Vector3, colour: Color,
		na: Vector3 = Vector3.ZERO, nb: Vector3 = Vector3.ZERO) -> void:
	var smooth := na != Vector3.ZERO
	for pair: Array in [[a, na], [b, nb], [c, nb], [a, na], [c, nb], [d, na]]:
		st.set_color(colour)
		st.set_uv(Vector2.ZERO)
		if smooth:
			st.set_normal(pair[1])
		st.add_vertex(pair[0])


## A smooth-shaded ellipsoid (coconuts, fruit, berries), `r` being the radius on each axis so
## fruit can be slightly oblate the way real fruit is. 140 triangles at the default detail: an
## eight-triangle octahedron at arm's length reads as a cut gemstone, not as something grown.
static func _sphere_into(st: SurfaceTool, at: Vector3, r: Vector3, colour: Color, sectors: int = 10, rings: int = 7) -> void:
	var on := func(u: float, v: float) -> Vector3:
		return Vector3(sin(v) * cos(u), cos(v), sin(v) * sin(u))
	for i in rings:
		var v0 := PI * float(i) / float(rings)
		var v1 := PI * float(i + 1) / float(rings)
		for j in sectors:
			var u0 := TAU * float(j) / float(sectors)
			var u1 := TAU * float(j + 1) / float(sectors)
			var p00: Vector3 = on.call(u0, v0)
			var p10: Vector3 = on.call(u1, v0)
			var p11: Vector3 = on.call(u1, v1)
			var p01: Vector3 = on.call(u0, v1)
			# The normal of an ellipsoid is the direction divided by the radii, not the
			# direction itself, or a squashed coconut lights like a round one.
			_quad(st, at + p00 * r, at + p10 * r, at + p11 * r, at + p01 * r, colour,
				(p00 / r).normalized(), (p10 / r).normalized())


## A cheap faceted blob, kept for callers that want the coarse version.
static func _ico(st: SurfaceTool, at: Vector3, r: float, colour: Color) -> void:
	_sphere_into(st, at, Vector3(r, r, r), colour, 6, 4)


## A balcony, built in a unit cube: 1 wide (X), 1 tall (Y), 1 deep (+Z, pointing out of the
## wall). Instances scale it to the real size, so bars are kept thin in unit space to survive
## being stretched across a window bay. Slab, top rail, and uprights.
static func balcony() -> Mesh:
	if _cache.has("balcony"):
		return _cache["balcony"]
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var slab := Color(0.70, 0.69, 0.66)
	var metal := Color(0.22, 0.22, 0.24)
	# Floor slab, slightly proud of the wall on both sides.
	_box_into(st, Vector3(0.0, 0.03, 0.5), Vector3(1.04, 0.06, 1.0), slab)
	# Top rail, a mid rail and a kick rail: three horizontals is what a real guard rail has,
	# and the gaps between them are the pattern the eye reads from the street.
	_box_into(st, Vector3(0.0, 0.98, 0.98), Vector3(1.02, 0.045, 0.05), metal)
	_box_into(st, Vector3(0.0, 0.64, 0.98), Vector3(1.0, 0.022, 0.026), metal)
	_box_into(st, Vector3(0.0, 0.30, 0.98), Vector3(1.0, 0.025, 0.03), metal)
	_box_into(st, Vector3(0.0, 0.10, 0.98), Vector3(1.0, 0.022, 0.026), metal)
	# Returns along the sides.
	for sx: float in [-0.5, 0.5]:
		_box_into(st, Vector3(sx, 0.98, 0.5), Vector3(0.04, 0.045, 1.0), metal)
		_box_into(st, Vector3(sx, 0.55, 0.5), Vector3(0.03, 0.9, 0.03), metal)
	# Uprights across the front, and along the returns so the balcony is not open at the sides.
	for i in 15:
		var x := -0.465 + float(i) * 0.0664
		_box_into(st, Vector3(x, 0.55, 0.98), Vector3(0.013, 0.9, 0.020), metal)
	for sx: float in [-0.5, 0.5]:
		for i in 5:
			var z := 0.16 + float(i) * 0.19
			_box_into(st, Vector3(sx, 0.55, z), Vector3(0.020, 0.9, 0.013), metal)
	st.generate_normals()
	var mesh := st.commit()
	var mat := StandardMaterial3D.new()
	mat.vertex_color_use_as_albedo = true
	mat.roughness = 0.8
	mesh.surface_set_material(0, mat)
	_cache["balcony"] = mesh
	return mesh


## Adds a coloured box to a SurfaceTool being built in local space.
static func _box_into(st: SurfaceTool, centre: Vector3, size: Vector3, colour: Color) -> void:
	var h := size * 0.5
	var c := centre
	var p := [
		c + Vector3(-h.x, -h.y, -h.z), c + Vector3(h.x, -h.y, -h.z),
		c + Vector3(h.x, h.y, -h.z), c + Vector3(-h.x, h.y, -h.z),
		c + Vector3(-h.x, -h.y, h.z), c + Vector3(h.x, -h.y, h.z),
		c + Vector3(h.x, h.y, h.z), c + Vector3(-h.x, h.y, h.z),
	]
	var faces := [[0, 1, 2, 3], [5, 4, 7, 6], [4, 0, 3, 7], [1, 5, 6, 2], [3, 2, 6, 7], [4, 5, 1, 0]]
	for f: Array in faces:
		_quad(st, p[f[0]], p[f[1]], p[f[2]], p[f[3]], colour)


## One floor of a fire escape, built in a unit cube: 1 wide (X), 1 tall (Y, one storey), 1 deep
## (+Z out of the wall). A platform with a railing, and a stair running down across the bay.
## Instanced once per floor with the X scale flipped on alternate floors so the stairs zigzag.
static func fire_escape() -> Mesh:
	if _cache.has("fire_escape"):
		return _cache["fire_escape"]
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	# Weathered black ironwork. Not near-black: a solid 0.17 slab in its own shadow reads as a
	# hole punched in the wall rather than as metal hanging off it.
	var iron := Color(0.30, 0.30, 0.32)
	var rust := Color(0.40, 0.27, 0.19)
	# Grated platform: real fire-escape decks are open bar grating, so the wall and the sky show
	# through them. A solid slab is the single biggest thing that made this read as a black box.
	var slats := 17
	for i in slats:
		var z := lerpf(0.06, 0.94, float(i) / float(slats - 1))
		_box_into(st, Vector3(0.0, 0.0, z), Vector3(1.0, 0.035, 0.045), iron)
	# Two cross bearers under the grating.
	for bz: float in [0.18, 0.82]:
		_box_into(st, Vector3(0.0, -0.04, bz), Vector3(1.0, 0.05, 0.05), iron)
	# Railing: top rail, mid rail, uprights, and the two end posts.
	_box_into(st, Vector3(0.0, 0.44, 0.98), Vector3(1.0, 0.035, 0.035), iron)
	_box_into(st, Vector3(0.0, 0.24, 0.98), Vector3(1.0, 0.025, 0.025), iron)
	for i in 13:
		var x := -0.45 + float(i) * 0.075
		_box_into(st, Vector3(x, 0.24, 0.98), Vector3(0.016, 0.44, 0.016), iron)
	for sx: float in [-0.49, 0.49]:
		# End posts are frames, not plates: uprights plus rails, so daylight passes through the
		# sides too.
		_box_into(st, Vector3(sx, 0.24, 0.06), Vector3(0.035, 0.46, 0.035), rust)
		_box_into(st, Vector3(sx, 0.24, 0.94), Vector3(0.035, 0.46, 0.035), rust)
		_box_into(st, Vector3(sx, 0.44, 0.5), Vector3(0.03, 0.03, 0.9), rust)
		_box_into(st, Vector3(sx, 0.24, 0.5), Vector3(0.022, 0.022, 0.9), rust)
	# Stair down to the floor below, sloped across the bay.
	var steps := 11
	for i in steps:
		var t := float(i) / float(steps - 1)
		var x := lerpf(-0.36, 0.36, t)
		var y := lerpf(-0.06, -0.86, t)
		var z := lerpf(0.85, 0.25, t)
		_box_into(st, Vector3(x, y, z), Vector3(0.12, 0.025, 0.28), iron)
	# Stringer under the stair.
	_box_into(st, Vector3(0.0, -0.47, 0.55), Vector3(0.9, 0.05, 0.05), rust)
	st.generate_normals()
	var mesh := st.commit()
	var mat := StandardMaterial3D.new()
	mat.vertex_color_use_as_albedo = true
	# Half-metal with a broad highlight: painted iron picks up a sheen off the sky along the
	# rails, which is what tells the eye it is metal and not a silhouette.
	# Painted ironwork is mostly a dielectric: a high metallic reading killed the diffuse and
	# put the whole escape back into silhouette. A little metal plus a broad highlight is what
	# reads as old black paint over steel.
	mat.metallic = 0.25
	mat.metallic_specular = 0.65
	mat.roughness = 0.45
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	mesh.surface_set_material(0, mat)
	_cache["fire_escape"] = mesh
	return mesh


## The pool of light a lamp throws on the pavement: a unit quad lying flat, additive and
## unshaded (see shaders/light_pool.gdshader). Instances scale it to the pool's diameter.
static func light_pool(tint: Color = Color(1.0, 0.84, 0.58), strength: float = 1.0) -> Mesh:
	var key := "light_pool_%d_%.2f" % [tint.to_rgba32(), strength]
	if _cache.has(key):
		return _cache[key]
	var mesh := QuadMesh.new()
	mesh.size = Vector2.ONE
	# The quad faces +Z, so it is laid flat by the instance transform, not here.
	var mat := ShaderMaterial.new()
	mat.shader = load("res://shaders/light_pool.gdshader")
	mat.set_shader_parameter("tint", tint)
	mat.set_shader_parameter("strength", strength)
	mesh.material = mat
	_cache[key] = mesh
	return mesh


## A glowing lamp face (headlight, tail light, sign light): the same additive night quad as the
## light pool but with a tight falloff, so it reads as a lamp rather than a smear.
static func lamp_face(tint: Color, strength: float = 1.6) -> Mesh:
	var key := "lamp_face_%d_%.2f" % [tint.to_rgba32(), strength]
	if _cache.has(key):
		return _cache[key]
	var mesh := QuadMesh.new()
	mesh.size = Vector2.ONE
	var mat := ShaderMaterial.new()
	mat.shader = load("res://shaders/light_pool.gdshader")
	mat.set_shader_parameter("tint", tint)
	mat.set_shader_parameter("strength", strength)
	mat.set_shader_parameter("falloff", 1.1)
	mesh.material = mat
	_cache[key] = mesh
	return mesh


## Shop sign lettering: cream, a little emissive so the names still read after dark without
## needing a light on every shopfront.
static func sign_material() -> StandardMaterial3D:
	if _cache.has("sign_mat"):
		return _cache["sign_mat"]
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.95, 0.92, 0.85)
	mat.roughness = 0.6
	mat.emission_enabled = true
	mat.emission = Color(1.0, 0.93, 0.78)
	mat.emission_energy_multiplier = 0.55
	_cache["sign_mat"] = mat
	return mat


## Shared vertex-colour foliage material with the wind sway (see shaders/foliage.gdshader).
static func foliage_material() -> ShaderMaterial:
	if _cache.has("foliage_mat"):
		return _cache["foliage_mat"]
	var mat := ShaderMaterial.new()
	mat.shader = load("res://shaders/foliage.gdshader")
	_cache["foliage_mat"] = mat
	return mat


## Turns a downloaded plant's leaf material into the swaying one (shaders/foliage_tex.gdshader),
## carrying its textures and UV scale across. Only the leaf surfaces get this: the trunk stays
## opaque and still.
## `blossom` recolours the leaf cards to a flower colour (see shaders/foliage_tex.gdshader):
## used for the jacaranda, whose source scan is out of bloom and therefore plain green.
static func foliage_textured(src: StandardMaterial3D, blossom: Color = Color.TRANSPARENT) -> ShaderMaterial:
	var key := "foliage_tex_%d_%d" % [src.get_instance_id(), blossom.to_rgba32()]
	if _cache.has(key):
		return _cache[key]
	var mat := ShaderMaterial.new()
	mat.shader = load("res://shaders/foliage_tex.gdshader")
	mat.set_shader_parameter("albedo_tex", src.albedo_texture)
	mat.set_shader_parameter("normal_tex", src.normal_texture)
	mat.set_shader_parameter("rough_tex", src.roughness_texture)
	mat.set_shader_parameter("has_normal", src.normal_texture != null)
	mat.set_shader_parameter("has_rough", src.roughness_texture != null)
	mat.set_shader_parameter("base_color", src.albedo_color)
	mat.set_shader_parameter("uv_scale", Vector2(src.uv1_scale.x, src.uv1_scale.y))
	mat.set_shader_parameter("alpha_cut", 0.45)
	if blossom.a > 0.0:
		mat.set_shader_parameter("blossom_mix", blossom.a)
		mat.set_shader_parameter("blossom", Color(blossom.r, blossom.g, blossom.b))
	_cache[key] = mat
	return mat


## Every light on one car in a single mesh: two headlights, two tail lights and the beam they
## throw on the road ahead, in car-local space (forward is -Z). One mesh, one draw, instead of
## five MeshInstance3D per car across a hundred and fifty cars. Colours ride in the vertex
## colour; see shaders/light_pool.gdshader.
static func vehicle_lights(width: float, length: float, y: float) -> Mesh:
	var key := "car_lights_%.2f_%.2f_%.2f" % [width, length, y]
	if _cache.has(key):
		return _cache[key]
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var head := Color(1.0, 0.95, 0.82, 1.0)
	var tail := Color(1.0, 0.16, 0.10, 0.78)
	for side: float in [-1.0, 1.0]:
		var x := side * (width * 0.5 - 0.26)
		_light_quad(st, Vector3(x, y, -length * 0.5 - 0.06), Vector3(0.62, 0.0, 0.0), Vector3(0.0, 0.34, 0.0), head)
		_light_quad(st, Vector3(x, y, length * 0.5 + 0.06), Vector3(0.58, 0.0, 0.0), Vector3(0.0, 0.30, 0.0), tail)
	# The beam on the road: a wide wedge lying flat in front of the car.
	# Its UVs sit in 2..3 instead of 0..1, which is how light_pool.gdshader tells it from a
	# round lamp pool and draws a fan instead of a blob.
	# Nine metres, not eleven: the further the flat quad reaches, the more a change of grade
	# ahead of the car puts its far end under the road, where it is cut off along a hard line.
	_light_quad(st, Vector3(0.0, 0.12 - y, -length * 0.5 - 3.4), Vector3(width * 2.2, 0.0, 0.0), Vector3(0.0, 0.0, 9.0), Color(1.0, 0.94, 0.80, 0.62), 2.0)
	var mesh := st.commit()
	mesh.surface_set_material(0, light_pool_material())
	_cache[key] = mesh
	return mesh


## One quad centred at `at`, spanning `u` and `v`, with UVs 0..1 so the light shader's radial
## falloff works, and `c` in the vertex colour.
static func _light_quad(st: SurfaceTool, at: Vector3, u: Vector3, v: Vector3, c: Color, uv_shift: float = 0.0) -> void:
	var corners := [[-0.5, -0.5, Vector2(0.0, 1.0)], [0.5, -0.5, Vector2(1.0, 1.0)],
		[0.5, 0.5, Vector2(1.0, 0.0)], [-0.5, 0.5, Vector2(0.0, 0.0)]]
	var order := [0, 1, 2, 0, 2, 3]
	for i in order:
		var corner: Array = corners[i]
		st.set_color(c)
		st.set_uv(corner[2] + Vector2(0.0, uv_shift))
		st.set_normal(Vector3(0.0, 0.0, 1.0))
		st.add_vertex(at + u * corner[0] + v * corner[1])


## Shared material for the additive night lights (see shaders/light_pool.gdshader).
static func light_pool_material() -> ShaderMaterial:
	if _cache.has("light_pool_mat"):
		return _cache["light_pool_mat"]
	var mat := ShaderMaterial.new()
	mat.shader = load("res://shaders/light_pool.gdshader")
	mat.set_shader_parameter("tint", Color(1.0, 1.0, 1.0))
	mat.set_shader_parameter("strength", 1.6)
	mat.set_shader_parameter("falloff", 1.3)
	_cache["light_pool_mat"] = mat
	return mat


static func palm_trunk() -> Mesh:
	return cylinder("palm_trunk", 0.22, 7.0, Color(0.55, 0.42, 0.28), 0.14, 16)


static func palm_frond() -> Mesh:
	return box("palm_frond", Vector3(0.5, 0.06, 3.2), Color(0.30, 0.62, 0.30))


static func coconut() -> Mesh:
	if _cache.has("coconut"):
		return _cache["coconut"]
	var mesh := SphereMesh.new()
	mesh.radius = 0.5
	mesh.height = 1.0
	mesh.radial_segments = 14
	mesh.rings = 9
	mesh.material = material(Color(0.45, 0.32, 0.18))
	_cache["coconut"] = mesh
	return mesh


static func lifeguard_cabin() -> Mesh:
	return box("lifeguard_cabin", Vector3(3.0, 2.4, 3.0), Color(0.35, 0.65, 0.85))


static func lifeguard_leg() -> Mesh:
	return box("lifeguard_leg", Vector3(0.25, 2.6, 0.25), Color(0.8, 0.78, 0.7))


static func lifeguard_ramp() -> Mesh:
	return box("lifeguard_ramp", Vector3(1.0, 0.1, 4.2), Color(0.8, 0.78, 0.7))


static func container() -> Mesh:
	return box("container", Vector3(12.0, 2.6, 2.4), Color(0.9, 0.9, 0.9))


static func unit_box() -> Mesh:
	return box("unit_box", Vector3.ONE, Color(0.9, 0.9, 0.9))


## A unit ellipsoid of 24 triangles, -0.5..0.5 on every axis like unit_box(): the far city's tree
## and scrub canopies (Skyline). A box read as a crate from the LOD ring in; this reads as foliage
## from there out. 24, not 48: a tree 300 m off is a dozen pixels, and there are tens of thousands.
static func canopy_blob() -> Mesh:
	if _cache.has("canopy_blob"):
		return _cache["canopy_blob"]
	var mesh := SphereMesh.new()
	mesh.radius = 0.5
	mesh.height = 1.0
	mesh.radial_segments = 6
	mesh.rings = 2
	_cache["canopy_blob"] = mesh
	return mesh


static func planter() -> Mesh:
	return box("planter", Vector3(2.4, 0.7, 2.4), Color(0.55, 0.5, 0.45))


# --- Real models -----------------------------------------------------------------------------
# Poly Haven glTF props packed to one .glb each (tools/pack_gltf.py). Several ship two variants
# side by side (a fresh and an aged hydrant, a clean and a rusty can), so a model is picked by
# node-name filters, moved to the origin and merged into one ArrayMesh with LODs so it can go
# through MultiMeshBatch like everything else. Merged once per variant and cached.

const MODEL_DIR := "res://assets/models/"


## Merges the MeshInstance3D nodes of the model at `path` whose names contain every string in
## `include` and none in `exclude` into one mesh. `xform` is applied to everything (used to
## move a variant to the origin and turn it to face -Z); `overrides` maps a node-name substring
## to a Transform3D that replaces that node's own transform (kits that ship parts unassembled).
## Most triangles a street prop's full-detail mesh may have, by model file. The Poly Haven scans
## are film assets: a street lamp came in at 30,610 triangles, a hydrant at 43,158 and a concrete
## road barrier at 60,928 - a whole generated car is about thirty thousand. Street props go
## through MultiMesh batches, and a batch picks ONE mesh LOD for all its instances from its
## nearest point, so every lamp on a block the player is standing on drew at full detail, and
## again into the shadow cascades: on a downtown street the lamps alone were eleven million
## triangles across the streamed blocks. Over budget, model_mesh() makes the LOD nearest the
## budget the new base mesh (and rebuilds the coarser ones under it). Hard-surface props only:
## foliage LODs collapse leaf cards, so trees and bushes are not listed.
const TRI_BUDGET := {
	"prop_lamp.glb": 3000, "prop_hydrant.glb": 9000, "prop_bench_kit.glb": 4000,
	"prop_cafe_set.glb": 3500, "prop_planter.glb": 1500, "prop_trash_can.glb": 2500,
	"prop_manhole.glb": 400, "prop_barrier.glb": 2000, "prop_barrier_b.glb": 2000,
	"prop_tyre.glb": 1500, "prop_ac.glb": 3000,
	# Facade detail kit pieces (tools/facade_kit.py), keyed file:node. These are guards rather
	# than cuts: every piece is modelled under its number, and one that grows past it in a
	# regenerated kit is taken back down to it here instead of silently doubling a street.
	# Window surrounds are per window (hundreds a building), so they are the tightest.
	"facade_kit.glb:kit_cornice_classic": 900, "facade_kit.glb:kit_cornice_bracket": 1100,
	"facade_kit.glb:kit_cornice_simple": 200, "facade_kit.glb:kit_coping": 120,
	"facade_kit.glb:kit_surround_brick_a": 260, "facade_kit.glb:kit_surround_brick_b": 260,
	"facade_kit.glb:kit_surround_stucco": 360, "facade_kit.glb:kit_ac_window": 700,
	"facade_kit.glb:kit_awning": 200, "facade_kit.glb:kit_balcony": 1400,
	"facade_kit.glb:kit_fe_stair_l": 2200, "facade_kit.glb:kit_fe_stair_r": 2200,
	"facade_kit.glb:kit_fe_bottom": 2000, "facade_kit.glb:kit_water_tank": 2400,
	"facade_kit.glb:kit_vent_mushroom": 400, "facade_kit.glb:kit_vent_turbine": 500,
	"facade_kit.glb:kit_hvac": 2000,
	# Encampment kit (tools/encampment_kit.py), keyed file:node like the facade kit: guards at
	# about each piece's modelled count. A camp is a few dozen instances a chunk, so the cart and
	# the bike - wire and spokes - are the ones that matter.
	"encampment_kit.glb:camp_tent_dome": 3000, "encampment_kit.glb:camp_tent_pop": 3000,
	"encampment_kit.glb:camp_tarp_canopy": 2200, "encampment_kit.glb:camp_tarp_mound": 2400,
	"encampment_kit.glb:camp_cart": 6000, "encampment_kit.glb:camp_bag_trash": 900,
	"encampment_kit.glb:camp_bag_duffel": 700, "encampment_kit.glb:camp_bags_pile": 2800,
	"encampment_kit.glb:camp_mattress": 1800, "encampment_kit.glb:camp_bedding": 2400,
	"encampment_kit.glb:camp_cardboard": 700, "encampment_kit.glb:camp_box": 400,
	"encampment_kit.glb:camp_chair": 1800, "encampment_kit.glb:camp_bicycle": 5200,
	"encampment_kit.glb:camp_bike_wheel": 1800, "encampment_kit.glb:camp_bike_frame": 3400,
	# Traffic signal hardware (tools/make_signals.py). Guards, like the kit's: a head is the most
	# repeated piece (up to a dozen an intersection), so it is the one that matters.
	"traffic_signal.glb:sig_pole": 1500, "traffic_signal.glb:sig_arm": 450,
	"traffic_signal.glb:sig_head": 2200, "traffic_signal.glb:sig_bracket": 150,
	"traffic_signal.glb:sig_ped": 1000, "traffic_signal.glb:sig_button": 350,
	"traffic_signal.glb:sig_cabinet": 800,
}


static func model_mesh(path: String, include: PackedStringArray = [], exclude: PackedStringArray = [], xform: Transform3D = Transform3D.IDENTITY, overrides: Dictionary = {}, proxy: bool = true) -> Mesh:
	var key := "model_%s_%s_%s_%s" % [path, ",".join(include), ",".join(exclude), var_to_str(xform)]
	if _cache.has(key):
		return _cache[key]
	var mesh: ArrayMesh = ArrayMesh.new()
	if ResourceLoader.exists(path):
		var scene: PackedScene = load(path)
		var root: Node = scene.instantiate()
		var importer := ImporterMesh.new()
		_merge_into(root, root, importer, include, exclude, xform, overrides)
		if importer.get_surface_count() > 0:
			importer.generate_lods(25.0, 60.0, [])
			# A kit that ships many pieces in one file budgets them one by one ("file:node").
			var budget: int = TRI_BUDGET.get(path.get_file(), 0)
			if include.size() == 1:
				budget = TRI_BUDGET.get(path.get_file() + ":" + include[0], budget)
			if budget > 0:
				importer = _within_budget(importer, budget)
			mesh = importer.get_mesh()
			if proxy:
				_build_shadow_proxy(importer, mesh)
		root.free()
	else:
		push_warning("PropFactory: missing model " + path)
	_cache[key] = mesh
	return mesh


## Shadow-only stand-ins for foliage meshes, keyed by the mesh they stand in for.
static var _shadow_proxies: Dictionary = {}


## The lighter mesh a batch casts its shadow with, or null (MultiMeshBatch.build()). Every
## imported model gets one (model_mesh()), and the palms; the street props' shadows were most of
## what was left in the shadow pass once the trees had theirs, 0.6 million triangles of lamp
## posts and hydrants that a shadow map shows as a few dark texels.
## Trees were the biggest single cost in a frame, and most of it was their shadows: a batch
## picks one LOD for all its instances from its nearest point, so every tree in the blocks
## around the player went into all four shadow cascades at full detail - 2.4 of the 3.2 million
## triangles the planting cost at a downtown street. A shadow map cannot show a twig or a leaf
## card's edge anyway, so the shadow comes from a quarter of the triangles instead. Godot's own
## shadow_mesh cannot do this: it only serves materials with no cut-out and no vertex motion,
## and the leaves have both.
static func shadow_proxy(mesh: Mesh) -> Mesh:
	return _shadow_proxies.get(mesh)


## Builds `mesh`'s shadow stand-in from the LODs `im` generated: per surface, the coarsest LOD
## that keeps `leaf_share` of a leaf surface's triangles (leaf cards thin out fast, and a sparse
## canopy casts a sparse shadow) or `wood_share` of a trunk's or twigs'. It shares the vertex
## layout and, via _tree_mesh(), the materials, so the cut-out and the sway match the tree.
static func _build_shadow_proxy(im: ImporterMesh, mesh: Mesh, leaf_share: float = 0.45, wood_share: float = 0.25) -> void:
	var out := ImporterMesh.new()
	var total := 0
	var kept := 0
	for s in im.get_surface_count():
		var arrays := im.get_surface_arrays(s)
		var base = arrays[Mesh.ARRAY_INDEX]
		if base == null:
			return
		var mat := im.get_surface_material(s)
		var leaf := mat is BaseMaterial3D and (mat as BaseMaterial3D).transparency != BaseMaterial3D.TRANSPARENCY_DISABLED
		var want := int(ceil(float((base as PackedInt32Array).size() / 3) * (leaf_share if leaf else wood_share)))
		var best: PackedInt32Array = base
		for l in im.get_surface_lod_count(s):
			var lod := im.get_surface_lod_indices(s, l)
			if lod.size() / 3 >= want and lod.size() < best.size():
				best = lod
		total += (base as PackedInt32Array).size() / 3
		kept += best.size() / 3
		arrays[Mesh.ARRAY_INDEX] = best
		out.add_surface(im.get_surface_primitive_type(s), arrays, [], {}, mat, im.get_surface_name(s))
	# Not worth a second node for a small saving.
	if kept > total * 0.8:
		return
	out.generate_lods(25.0, 60.0, [])
	_shadow_proxies[mesh] = out.get_mesh()


## `src` rebuilt with each surface's base indices swapped for its coarsest generated LOD that
## still keeps its share of `budget` triangles, then LODs regenerated below that. Unchanged if it
## is already under budget or no LOD is coarse enough to help.
static func _within_budget(src: ImporterMesh, budget: int) -> ImporterMesh:
	var total := 0
	for s in src.get_surface_count():
		var idx = src.get_surface_arrays(s)[Mesh.ARRAY_INDEX]
		if idx != null:
			total += (idx as PackedInt32Array).size() / 3
	if total <= budget:
		return src
	var share := float(budget) / float(total)
	var out := ImporterMesh.new()
	for s in src.get_surface_count():
		var arrays := src.get_surface_arrays(s)
		var base = arrays[Mesh.ARRAY_INDEX]
		if base != null:
			var want := int(ceil(float((base as PackedInt32Array).size() / 3) * share))
			var best: PackedInt32Array = base
			for l in src.get_surface_lod_count(s):
				var lod := src.get_surface_lod_indices(s, l)
				if lod.size() / 3 >= want and lod.size() < best.size():
					best = lod
			arrays[Mesh.ARRAY_INDEX] = best
		out.add_surface(src.get_surface_primitive_type(s), arrays, [], {}, src.get_surface_material(s), src.get_surface_name(s))
	out.generate_lods(25.0, 60.0, [])
	return out


static func _merge_into(node: Node, root: Node, importer: ImporterMesh, include: PackedStringArray, exclude: PackedStringArray, xform: Transform3D, overrides: Dictionary) -> void:
	if node is MeshInstance3D:
		var mi := node as MeshInstance3D
		var lower := mi.name.to_lower()
		var wanted := true
		for s in include:
			if not lower.contains(s):
				wanted = false
		for s in exclude:
			if lower.contains(s):
				wanted = false
		if wanted and mi.mesh:
			var local := mi.transform
			var parent := mi.get_parent()
			while parent and parent != root:
				if parent is Node3D:
					local = (parent as Node3D).transform * local
				parent = parent.get_parent()
			for name in overrides:
				if lower.contains(name):
					local = overrides[name]
			var full := xform * local
			for s in mi.mesh.get_surface_count():
				var arrays := _transformed_arrays(mi.mesh.surface_get_arrays(s), full)
				importer.add_surface(Mesh.PRIMITIVE_TRIANGLES, arrays, [], {}, mi.get_active_material(s), "%s_%d" % [mi.name, s])
	for child in node.get_children():
		_merge_into(child, root, importer, include, exclude, xform, overrides)


static func _transformed_arrays(arrays: Array, t: Transform3D) -> Array:
	var out := arrays.duplicate()
	var verts: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	var moved := PackedVector3Array()
	moved.resize(verts.size())
	for i in verts.size():
		moved[i] = t * verts[i]
	out[Mesh.ARRAY_VERTEX] = moved
	if arrays[Mesh.ARRAY_NORMAL] != null:
		var normals: PackedVector3Array = arrays[Mesh.ARRAY_NORMAL]
		var turned := PackedVector3Array()
		turned.resize(normals.size())
		for i in normals.size():
			turned[i] = (t.basis * normals[i]).normalized()
		out[Mesh.ARRAY_NORMAL] = turned
	if arrays[Mesh.ARRAY_TANGENT] != null:
		var tangents: PackedFloat32Array = arrays[Mesh.ARRAY_TANGENT]
		var turned_t := PackedFloat32Array()
		turned_t.resize(tangents.size())
		for i in tangents.size() / 4:
			var v := (t.basis * Vector3(tangents[i * 4], tangents[i * 4 + 1], tangents[i * 4 + 2])).normalized()
			turned_t[i * 4] = v.x
			turned_t[i * 4 + 1] = v.y
			turned_t[i * 4 + 2] = v.z
			turned_t[i * 4 + 3] = tangents[i * 4 + 3]
		out[Mesh.ARRAY_TANGENT] = turned_t
	return out


static func _shift(offset: Vector3) -> Transform3D:
	return Transform3D(Basis(), offset)


## Fire hydrant, 0.8 m tall, base at the origin. Fresh or aged paint.
static func model_hydrant(aged: bool) -> Mesh:
	if aged:
		return model_mesh(MODEL_DIR + "prop_hydrant.glb", ["aged"], [], _shift(Vector3(-0.3, 0.0, 0.0)))
	return model_mesh(MODEL_DIR + "prop_hydrant.glb", [], ["aged"], _shift(Vector3(0.3, 0.0, 0.0)))


## Metal trash can with a loose lid, 0.91 m tall, base at the origin. Clean or rusty.
static func model_trash_can(rusty: bool) -> Mesh:
	if rusty:
		return model_mesh(MODEL_DIR + "prop_trash_can.glb", ["rust"], [], _shift(Vector3(0.5, 0.0, 0.0)))
	return model_mesh(MODEL_DIR + "prop_trash_can.glb", [], ["rust"], _shift(Vector3(-0.5, 0.0, 0.0)))


## Timber and steel street bench assembled from the Poly Haven seating kit: 1.86 m wide, seat at
## 0.45 m, back rest leaning back, facing -Z, base at the origin.
static func model_bench() -> Mesh:
	var face_minus_z := Transform3D(Basis(Vector3.UP, PI), Vector3.ZERO) * _shift(Vector3(1.16, 0.0, 0.0))
	var parts: PackedStringArray = ["legs_single", "legs_double", "crossbar", "suspended_support_01", "seat", "back_support", "arm_rest"]
	var overrides := {"seat_back": Transform3D(Basis(Vector3.RIGHT, deg_to_rad(69.0)), Vector3(-1.16, 0.473, 0.098))}
	var mesh := model_mesh(MODEL_DIR + "prop_bench_kit.glb", [], ["connector", "seat_bench", "suspended_support_02"], face_minus_z, overrides)
	if mesh.get_surface_count() > 0:
		return mesh
	return bench()


## Concrete road barrier, 1.55 x 0.83 x 0.64 m, base at the origin.
static func model_barrier() -> Mesh:
	return model_mesh(MODEL_DIR + "prop_barrier.glb")


## Red steel drum, 0.56 m across and 0.88 m tall, base at the origin.
static func model_barrel() -> Mesh:
	return model_mesh(MODEL_DIR + "prop_barrel.glb")


## Old tyre lying flat, 0.6 m across and 0.16 m thick, bottom at the origin.
static func model_tyre() -> Mesh:
	return model_mesh(MODEL_DIR + "prop_tyre.glb", [], [], Transform3D(Basis(Vector3.RIGHT, PI * 0.5), Vector3(0.0, 0.08, 0.0)))


## Wooden planter box, 0.91 x 0.42 x 0.41 m, base at the origin.
static func model_planter() -> Mesh:
	return model_mesh(MODEL_DIR + "prop_planter.glb")


## Folding cafe table with two chairs, 0.79 x 0.86 x 1.71 m, base at the origin.
static func model_cafe_set() -> Mesh:
	return model_mesh(MODEL_DIR + "prop_cafe_set.glb")


## Street lamp, 3.87 m tall, base at the origin. The bulb and glass surfaces glow.
static func model_lamp() -> Mesh:
	var mesh := model_mesh(MODEL_DIR + "prop_lamp.glb")
	if not _cache.has("model_lamp_lit"):
		_cache["model_lamp_lit"] = true
		for i in mesh.get_surface_count():
			var mat := mesh.surface_get_material(i)
			if mat is StandardMaterial3D:
				var name := (mat as StandardMaterial3D).resource_name.to_lower()
				if name.contains("bulb") or name.contains("glass"):
					var lit: StandardMaterial3D = mat.duplicate()
					lit.emission_enabled = true
					lit.emission = Color(1.0, 0.9, 0.65)
					lit.emission_energy_multiplier = 3.0 if name.contains("bulb") else 0.8
					mesh.surface_set_material(i, lit)
				else:
					# The post takes the instance color (district paint).
					(mat as StandardMaterial3D).vertex_color_use_as_albedo = true
	return mesh


## One of four leafy shrubs (0.9 to 1.7 m), base at the origin. Instance colors tint the leaves.
static func model_shrub(variant: int) -> Mesh:
	var offsets: Array[Vector3] = [Vector3(-1.55, -0.01, -0.02), Vector3(0.0, -0.01, -0.02), Vector3(1.56, -0.01, -0.01), Vector3(3.26, 0.0, -0.01)]
	var v := clampi(variant, 0, 3)
	var mesh := model_mesh(MODEL_DIR + "prop_shrub.glb", ["shrub_02_" + "abcd"[v]], [], _shift(-offsets[v]))
	for i in mesh.get_surface_count():
		var mat := mesh.surface_get_material(i)
		if mat is StandardMaterial3D:
			(mat as StandardMaterial3D).vertex_color_use_as_albedo = true
	return mesh


## Round manhole cover with its frame, 0.7 m across, the frame top 0.04 m above the origin.
static func model_manhole() -> Mesh:
	return model_mesh(MODEL_DIR + "prop_manhole.glb")


## Taller jersey barrier variant, 1.57 x 1.11 x 0.44 m, base at the origin.
static func model_barrier_tall() -> Mesh:
	return model_mesh(MODEL_DIR + "prop_barrier_b.glb")


## City trees (Poly Haven, CC0, reduced with tools/decimate_tree.py): 0-2 the original island
## and small trees, 3 a fourth broadleaf, 4 the jacaranda. About 5 m tall, base at the origin.
## Leaves use alpha scissor and take the instance color as a tint.
##
## The jacaranda is the one that carries colour. Its canopy is violet rather than green, which
## is why whole blocks can be biased to it (CityChunk._jacaranda_street): a jacaranda boulevard
## in bloom is the most recognisable thing on a Los Angeles street and the strongest single
## splash of colour the city has.
const CITY_TREES := ["tree_a.glb", "tree_b.glb", "tree_c.glb", "tree_d.glb", "tree_jacaranda.glb"]
## Hill trees: conifers up the slopes, dry desert species on the bare ground. A range above a
## coastal basin covered in the same broadleaf street trees as the city below reads as one
## texture stretched over everything.
const HILL_TREES := ["tree_fir.glb", "tree_pine.glb", "tree_quiver.glb", "tree_searsia.glb"]
## Measured height of each model in metres, so placement can ask for a real-world height instead
## of a raw multiplier. Without this the city pool spans 2.6 m to 19.5 m and one 0.9-1.6 roll
## makes tree_d a 2.3 m bush and the jacaranda a 31 m tree with a 40 m canopy, overtopping the
## buildings it is supposed to line. Re-measure with the bbox if a model is ever replaced.
const CITY_TREE_HEIGHT := [5.01, 3.40, 4.61, 2.61, 19.47]
const HILL_TREE_HEIGHT := [14.33, 20.25, 2.72, 3.27]
## Target height range in metres PER SPECIES, not one range shared by all of them. A model
## stretched much past about 1.5x its native size goes sparse and skeletal - the leaf cards are
## spread over a canopy they were never built to fill - so a small ornamental is kept small and
## the jacaranda, which is scanned at 19.5 m, is brought DOWN to the 10-13 m a real one stands.
## The variety in the street comes from the species being genuinely different sizes, which is how
## a real street looks, rather than from stretching one model across the whole range.
const CITY_TREE_TARGET := [
	Vector2(4.5, 7.0), Vector2(3.2, 5.0), Vector2(4.2, 6.5), Vector2(2.6, 4.0), Vector2(9.0, 13.0),
]
const HILL_TREE_TARGET := [
	Vector2(11.0, 17.0), Vector2(14.0, 22.0), Vector2(2.4, 4.0), Vector2(2.8, 4.6),
]


## A sensible random height in metres for one city tree species.
static func city_tree_height(variant: int, rng: RandomNumberGenerator) -> float:
	var r: Vector2 = CITY_TREE_TARGET[clampi(variant, 0, CITY_TREE_TARGET.size() - 1)]
	return rng.randf_range(r.x, r.y)


static func hill_tree_height(variant: int, rng: RandomNumberGenerator) -> float:
	var r: Vector2 = HILL_TREE_TARGET[clampi(variant, 0, HILL_TREE_TARGET.size() - 1)]
	return rng.randf_range(r.x, r.y)


## Uniform scale that makes city tree `variant` stand `target_m` metres tall.
static func city_tree_scale(variant: int, target_m: float) -> float:
	var v := clampi(variant, 0, CITY_TREE_HEIGHT.size() - 1)
	return target_m / maxf(float(CITY_TREE_HEIGHT[v]), 0.1)


static func hill_tree_scale(variant: int, target_m: float) -> float:
	var v := clampi(variant, 0, HILL_TREE_HEIGHT.size() - 1)
	return target_m / maxf(float(HILL_TREE_HEIGHT[v]), 0.1)

## Lavender, at 58% of the canopy. The alpha carries the mix amount.
## A jacaranda is soft lavender-violet, not electric blue: at 0.40/0.27/0.70 and 80% the trees
## came out a vivid ultramarine that read as a bug rather than as blossom. Lighter, less
## saturated, and with enough green left showing to look like a tree in flower.
const JACARANDA_BLOSSOM := Color(0.64, 0.56, 0.88, 0.62)

static func model_tree(variant: int) -> Mesh:
	var v := clampi(variant, 0, CITY_TREES.size() - 1)
	var blossom := JACARANDA_BLOSSOM if CITY_TREES[v] == "tree_jacaranda.glb" else Color.TRANSPARENT
	return _tree_mesh(CITY_TREES[v], blossom)


## One of the hill species; same leaf handling as the city trees.
static func model_hill_tree(variant: int) -> Mesh:
	var v := clampi(variant, 0, HILL_TREES.size() - 1)
	return _tree_mesh(HILL_TREES[v])


## Bushes, tropical plants, flowering ground cover and grass clumps - all CC0 Poly Haven, all
## through the same leaf handling as the trees (alpha-scissor leaves onto the swaying foliage
## shader, everything else double-sided). These exist to put colour and variation at knee height,
## where the city was previously bare lawn between a tree and a building.
const BUSHES := ["bush_a.glb", "bush_b.glb", "bush_c.glb", "bush_sorrel.glb"]
## Tropical foliage: the planting a warm coastal city actually uses in courtyards and by doors.
const PLANTS := ["plant_fern.glb", "plant_pachira.glb", "plant_anthurium.glb",
	"plant_calathea.glb", "plant_nettle.glb"]
## Flowering ground cover, which is where most of the colour comes from: orange gazania and
## ursinia, yellow empodium, purple leipoldtia, periwinkle, dandelion, celandine.
const FLOWERS := ["flower_orange.glb", "flower_ursinia.glb", "flower_yellow.glb",
	"flower_purple.glb", "flower_periwinkle.glb", "flower_dandelion.glb", "flower_celandine.glb"]
const GRASS_CLUMPS := ["grass_bermuda.glb", "grass_medium.glb"]


static func model_bush(variant: int) -> Mesh:
	return _tree_mesh(BUSHES[clampi(variant, 0, BUSHES.size() - 1)])


static func model_plant(variant: int) -> Mesh:
	return _tree_mesh(PLANTS[clampi(variant, 0, PLANTS.size() - 1)])


static func model_flower(variant: int) -> Mesh:
	return _tree_mesh(FLOWERS[clampi(variant, 0, FLOWERS.size() - 1)])


static func model_grass_clump(variant: int) -> Mesh:
	return _tree_mesh(GRASS_CLUMPS[clampi(variant, 0, GRASS_CLUMPS.size() - 1)])


static func _tree_mesh(file: String, blossom: Color = Color.TRANSPARENT) -> Mesh:
	var mesh := model_mesh(MODEL_DIR + file, [], [], Transform3D.IDENTITY, {}, true)
	for i in mesh.get_surface_count():
		var mat := mesh.surface_get_material(i)
		if mat is StandardMaterial3D:
			var sm := mat as StandardMaterial3D
			# Two of the models flag their leaf material OPAQUE in the glTF although the atlas is
			# photographed on black, and Godot imports OPAQUE as TRANSPARENCY_DISABLED, so this test
			# used to skip them: 33% of flower_orange's triangle UV samples and 49% of
			# grass_bermuda's land on texels under 0.07 brightness, and those were drawn as solid
			# black cards. Every other OPAQUE surface across the 26 foliage models measures 0.2% or
			# less - the pine twig and the pachira leaves are OPAQUE too and measure 0.000, their
			# UVs never touch the padding - so this is a two-name exception and not a rule.
			var mislabelled := sm.resource_name == "flower_gazania" or sm.resource_name == "grass_bermuda_01"
			if sm.transparency != BaseMaterial3D.TRANSPARENCY_DISABLED or mislabelled:
				# The leaf cards: onto the swaying shader, which does the scissor itself.
				mesh.surface_set_material(i, foliage_textured(sm, blossom))
				continue
			sm.cull_mode = BaseMaterial3D.CULL_DISABLED
	var proxy := shadow_proxy(mesh)
	if proxy:
		for i in mesh.get_surface_count():
			proxy.surface_set_material(i, mesh.surface_get_material(i))
	return mesh


## Leaf surfaces of a scanned plant onto the swaying cut-out shader (shaders/foliage_tex.gdshader);
## instance-color tinting and double-siding on the woody rest.
## This used to test `transparency == TRANSPARENCY_ALPHA` (enum 1) and flip it to ALPHA_SCISSOR,
## and that test never once fired: Godot imports a glTF BLEND material as
## TRANSPARENCY_ALPHA_DEPTH_PRE_PASS (enum 4), which is what grass_medium_02 and both
## wild_rooibos_bush_twigs and wild_rooibos_bush_leaves carry in the imported scene. So they stayed
## alpha-BLENDED, and their atlases are JPEG with no alpha channel, so every texel came out at
## ALPHA 1.0 and the black background they were photographed on was drawn solid: by triangle area
## 18% of a grass tuft, 35% of the rooibos twigs and 72% of the rooibos leaves sit under 0.07
## brightness, and those two models are most of what covers the hills.
## foliage_tex.gdshader is the only thing here that recovers the cut-out from brightness, so route
## them through it; it multiplies by COLOR.rgb itself, so the instance tint survives, and it also
## gets them the wind sway and the backlight the rest of the planting has.
static func _plant_material(mesh: Mesh) -> Mesh:
	for i in mesh.get_surface_count():
		var mat := mesh.surface_get_material(i)
		if mat is StandardMaterial3D:
			var sm := mat as StandardMaterial3D
			if sm.transparency != BaseMaterial3D.TRANSPARENCY_DISABLED:
				mesh.surface_set_material(i, foliage_textured(sm))
				continue
			sm.vertex_color_use_as_albedo = true
			sm.cull_mode = BaseMaterial3D.CULL_DISABLED
	return mesh


## Hill boulder: 0 is 2.5 x 0.8 m and flat, 1 is 2.5 x 1.9 m and tall. Base at the origin.
static func model_rock(variant: int) -> Mesh:
	return model_mesh(MODEL_DIR + ("rock_b.glb" if variant == 1 else "rock_a.glb"))


## Dry scrub plant, five sizes from 0.25 to 0.55 m (variant 0 biggest). Base at the origin.
static func model_scrub(variant: int) -> Mesh:
	var offsets: Array[float] = [1.6, 1.0, 0.5, 0.1, -0.2]
	var v := clampi(variant, 0, 4)
	return _plant_material(model_mesh(MODEL_DIR + "plant_rooibos.glb", ["wild_rooibos_bush_" + "abcde"[v]], [], _shift(Vector3(-offsets[v], 0.0, 0.0))))


## Grass tuft, five sizes from 0.15 to 0.4 m (variant 4 biggest). Base at the origin.
static func model_grass_tuft(variant: int) -> Mesh:
	var offsets: Array[float] = [0.0, 0.21, 0.49, 0.79, 1.11]
	var v := clampi(variant, 0, 4)
	return _plant_material(model_mesh(MODEL_DIR + "grass_tuft.glb", ["grass_medium_02_" + "abcde"[v]], [], _shift(Vector3(-offsets[v], 0.0, 0.0))))


## Material for the far building boxes: windows from a fixed grid, lit at night (see
## shaders/building_lod.gdshader; instance color = facade, custom = style, lit ratio, seed, plain).
## The one material every far chunk's merged ground wears. Vertex colour carries what each
## surface used to get from its own shader; at LOD range that base colour is all that survived
## anyway. Cached, so two hundred far chunks share one material and one draw each.
## The merged ground of a far chunk: vertex colour for albedo, and its alpha for how much street
## lamp glow the surface gets after dark (shaders/far_ground.gdshader).
static func far_ground_material() -> ShaderMaterial:
	if _cache.has("far_ground_mat"):
		return _cache["far_ground_mat"]
	var mat := ShaderMaterial.new()
	mat.shader = load("res://shaders/far_ground.gdshader")
	_cache["far_ground_mat"] = mat
	return mat


static func building_lod_material() -> ShaderMaterial:
	if _cache.has("building_lod_mat"):
		return _cache["building_lod_mat"]
	var mat := ShaderMaterial.new()
	mat.shader = load("res://shaders/building_lod.gdshader")
	# Forward+ decodes the near buildings' source_color facade but never a MultiMesh instance
	# colour, so the far boxes have to decode theirs or they are drawn up to four times brighter
	# than the same building up close (see the shader). Compatibility decodes neither.
	mat.set_shader_parameter("instance_color_is_srgb", has_reflections())
	_cache["building_lod_mat"] = mat
	return mat


# --- Street detail pieces (see scripts/world/street_detail.gd) ----------------------------------

## Dark gutter strip, 4 m along Z, 0.5 m wide.
static func gutter() -> Mesh:
	return box("gutter", Vector3(0.5, 0.008, 4.0), Color(0.22, 0.22, 0.23))


static func grate() -> Mesh:
	return box("grate", Vector3(0.5, 0.02, 0.9), Color(0.12, 0.12, 0.13))


## White stop line, 1 m along X (scaled to the lane), 0.45 m deep.
static func stop_line() -> Mesh:
	return box("stop_line", Vector3(1.0, 0.012, 0.45), Color(0.95, 0.95, 0.92))


## Unit asphalt patch (scaled per instance), takes the instance color.
static func patch() -> Mesh:
	return box("patch", Vector3(1.0, 0.006, 1.0), Color(0.5, 0.5, 0.52))


## Flat painted arrow pointing -Z: shaft plus head, 3.4 m long.
static func arrow_straight() -> Mesh:
	return _flat_polygon("arrow_straight", PackedVector2Array([
		Vector2(-0.18, 1.2), Vector2(0.18, 1.2), Vector2(0.18, -0.6), Vector2(0.6, -0.6), Vector2(0.0, -2.2), Vector2(-0.6, -0.6), Vector2(-0.18, -0.6),
	]), Color(0.95, 0.95, 0.92))


## Flat painted left-turn arrow: shaft forward, head bent to -X.
static func arrow_left() -> Mesh:
	return _flat_polygon("arrow_left", PackedVector2Array([
		Vector2(-0.18, 1.2), Vector2(0.18, 1.2), Vector2(0.18, -0.9), Vector2(-0.5, -0.9), Vector2(-0.5, -0.4), Vector2(-1.6, -1.2), Vector2(-0.5, -2.0), Vector2(-0.5, -1.5), Vector2(-0.18, -1.5),
	]), Color(0.95, 0.95, 0.92))


## A flat, upward-facing polygon mesh from XZ points (a painted road marking).
static func _flat_polygon(key: String, points: PackedVector2Array, color: Color) -> Mesh:
	if _cache.has(key):
		return _cache[key]
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var mat: StandardMaterial3D = material(color, 0.7).duplicate()
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	st.set_material(mat)
	var tris := Geometry2D.triangulate_polygon(points)
	for i in range(0, tris.size(), 3):
		# Reverse so the face points up (+Y) with Godot's winding.
		for j in [i + 2, i + 1, i]:
			var q := points[tris[j]]
			st.set_normal(Vector3.UP)
			st.add_vertex(Vector3(q.x, 0.0, q.y))
	var mesh := st.commit()
	_cache[key] = mesh
	return mesh


static func upole() -> Mesh:
	return cylinder("upole", 0.16, 9.0, Color(0.36, 0.28, 0.2), 0.13, 14)


static func crossarm() -> Mesh:
	return box("crossarm", Vector3(2.0, 0.1, 0.1), Color(0.36, 0.28, 0.2))


## Unit cable along Z (scaled per instance).
static func cable() -> Mesh:
	return box("cable", Vector3(0.035, 0.035, 1.0), Color(0.08, 0.08, 0.09))


## The classic inverted-U bike hoop, as one bent round tube rather than three square boxes
## butted together. It stands at the kerb where the player walks past it, and square corners on
## something that is obviously bent pipe is the kind of tell that makes a street read as a
## greybox. 22 points along the bend at 9 sides is under 400 triangles.
static func bike_rack() -> Mesh:
	if _cache.has("bike_rack"):
		return _cache["bike_rack"]
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	st.set_material(material(Color(0.3, 0.3, 0.32), 0.5))
	var path := PackedVector3Array()
	# Up the left leg, round the bend, down the right leg.
	path.append(Vector3(-0.4, 0.0, 0.0))
	path.append(Vector3(-0.4, 0.28, 0.0))
	path.append(Vector3(-0.4, 0.56, 0.0))
	for i in range(0, 13):
		var a: float = PI * float(i) / 12.0
		path.append(Vector3(-0.4 * cos(a), 0.66 + 0.26 * sin(a), 0.0))
	path.append(Vector3(0.4, 0.56, 0.0))
	path.append(Vector3(0.4, 0.28, 0.0))
	path.append(Vector3(0.4, 0.0, 0.0))
	# White in the vertex colour: material() already carries the grey in albedo_color and
	# multiplies the vertex colour into it, so tinting here as well would double the darkness.
	_tube_into(st, path, 0.032, Color.WHITE, 9)
	var mesh := st.commit()
	_cache["bike_rack"] = mesh
	return mesh


## Sweeps a round tube of radius `r` along a polyline. Used for bent pipework (bike hoops,
## handrails) where a box chain shows its corners.
static func _tube_into(st: SurfaceTool, path: PackedVector3Array, r: float, colour: Color, sides: int = 9) -> void:
	if path.size() < 2:
		return
	var up := Vector3.UP
	for i in path.size() - 1:
		var a := path[i]
		var b := path[i + 1]
		var along := (b - a)
		if along.length_squared() < 1e-9:
			continue
		along = along.normalized()
		var ref := up if absf(along.dot(up)) < 0.95 else Vector3.RIGHT
		var u := along.cross(ref).normalized()
		var v := along.cross(u).normalized()
		for k in sides:
			var t0 := TAU * float(k) / float(sides)
			var t1 := TAU * float(k + 1) / float(sides)
			var d0 := u * cos(t0) + v * sin(t0)
			var d1 := u * cos(t1) + v * sin(t1)
			_quad(st, a + d0 * r, a + d1 * r, b + d1 * r, b + d0 * r, colour, d0, d1)


static func news_box() -> Mesh:
	return box("news_box", Vector3(0.45, 1.1, 0.45), Color(1.0, 1.0, 1.0))


static func mailbox() -> Mesh:
	if _cache.has("mailbox"):
		return _cache["mailbox"]
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	st.set_material(material(Color(0.15, 0.32, 0.26), 0.6))
	for part in [[Vector3(0.0, 0.95, 0.0), Vector3(0.55, 0.7, 0.45)], [Vector3(-0.18, 0.3, 0.0), Vector3(0.05, 0.6, 0.05)], [Vector3(0.18, 0.3, 0.0), Vector3(0.05, 0.6, 0.05)]]:
		var bm := BoxMesh.new()
		bm.size = part[1]
		st.append_from(bm, 0, Transform3D(Basis(), part[0]))
	var mesh := st.commit()
	_cache["mailbox"] = mesh
	return mesh


static func bollard() -> Mesh:
	return cylinder("bollard", 0.12, 0.9, Color(0.25, 0.25, 0.27), 0.1, 18)


static func sign_post() -> Mesh:
	return cylinder("sign_post", 0.04, 2.8, Color(0.3, 0.3, 0.32), 0.04, 12)


## Green street-name plate, 1 m wide along X, takes the instance color.
static func sign_plate() -> Mesh:
	return box("sign_plate", Vector3(1.0, 0.24, 0.03), Color(1.0, 1.0, 1.0))


static func bus_sign() -> Mesh:
	if _cache.has("bus_sign"):
		return _cache["bus_sign"]
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	st.set_material(material(Color(0.1, 0.35, 0.7), 0.6))
	var bm := BoxMesh.new()
	bm.size = Vector3(0.5, 0.5, 0.03)
	st.append_from(bm, 0, Transform3D())
	var mesh := st.commit()
	var tm := text_mesh("BUS", 0.16)
	var st2 := SurfaceTool.new()
	st2.begin(Mesh.PRIMITIVE_TRIANGLES)
	st2.set_material(material(Color.WHITE, 0.6))
	st2.append_from(tm, 0, Transform3D(Basis(), Vector3(0.0, 0.0, 0.03)))
	st2.commit(mesh)
	_cache["bus_sign"] = mesh
	return mesh


static func shelter_post() -> Mesh:
	return box("shelter_post", Vector3(0.1, 2.5, 0.1), Color(0.25, 0.25, 0.27))


static func shelter_roof() -> Mesh:
	return box("shelter_roof", Vector3(4.2, 0.08, 1.8), Color(0.25, 0.25, 0.27))


static func shelter_glass() -> Mesh:
	if _cache.has("shelter_glass"):
		return _cache["shelter_glass"]
	var mesh := BoxMesh.new()
	mesh.size = Vector3(3.8, 2.3, 0.04)
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.6, 0.75, 0.85, 0.35)
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.roughness = 0.1
	mat.metallic = 0.3
	mesh.material = mat
	_cache["shelter_glass"] = mesh
	return mesh


## 3D text as a mesh, centered, white, `height` meters tall (cached per text and size).
static func text_mesh(text: String, height: float = 0.18) -> Mesh:
	var key := "text_%s_%.2f" % [text, height]
	if _cache.has(key):
		return _cache[key]
	var tm := TextMesh.new()
	tm.text = text
	tm.font_size = 48
	tm.pixel_size = height / 48.0
	tm.depth = 0.01
	tm.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	tm.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	tm.material = material(Color.WHITE, 0.6)
	_cache[key] = tm
	return tm


## Dark tinted storefront glass (shared).
static func storefront_glass() -> StandardMaterial3D:
	if _cache.has("storefront_glass"):
		return _cache["storefront_glass"]
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.25, 0.32, 0.38, 0.75)
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.roughness = 0.08
	mat.metallic = 0.6
	_cache["storefront_glass"] = mat
	return mat


## Gas pump: a cabinet with a lighter top, centered 0.9 m up. Takes the instance color.
static func gas_pump() -> Mesh:
	if _cache.has("gas_pump"):
		return _cache["gas_pump"]
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	st.set_material(material(Color(0.9, 0.9, 0.9), 0.5))
	for part in [[Vector3(0.0, 0.0, 0.0), Vector3(0.55, 1.8, 0.9)], [Vector3(0.0, 0.95, 0.0), Vector3(0.6, 0.1, 0.95)], [Vector3(0.3, 0.2, 0.3), Vector3(0.08, 0.5, 0.12)]]:
		var bm := BoxMesh.new()
		bm.size = part[1]
		st.append_from(bm, 0, Transform3D(Basis(), part[0]))
	var mesh := st.commit()
	_cache["gas_pump"] = mesh
	return mesh


static func ocean_material() -> ShaderMaterial:
	if _cache.has("ocean_mat"):
		return _cache["ocean_mat"]
	var mat := ShaderMaterial.new()
	mat.shader = load("res://shaders/ocean.gdshader")
	_cache["ocean_mat"] = mat
	return mat


## --- Encampment kit ------------------------------------------------------------------------
## The tents, tarps, carts and belongings of a sidewalk encampment, modelled in Blender by
## tools/encampment_kit.py (one node per piece in encampment_kit.glb, placed by Encampment). How
## they are built is in that script's header; how they wear (bleach, grime, stains) is in
## shaders/encampment.gdshaderinc.
const ENCAMPMENT_KIT := MODEL_DIR + "encampment_kit.glb"
## Per kit material (the Blender material name): texture set ("" for none), metres per tile,
## where the colour comes from (0 the instance colour, 1 `base`), `mul` (a darker panel of the
## instance colour), roughness, metallic, how much of the texture shows, ground grime, stains,
## sun bleaching, and whether it is a sheet seen from both sides. The texture means are the
## linear and raw sRGB luminance of each set's Color map, so the texture is detail only and the
## tint is the colour.
const CAMP_MATERIALS := {
	"camp_nylon": {"set": "camp_nylon", "tile": 0.35, "tint": 0, "rough": 0.62, "detail": 1.0, "grime": 0.5, "stains": 0.35, "bleach": 0.6, "two_side": true},
	"camp_door": {"set": "camp_nylon", "tile": 0.35, "tint": 0, "mul": 0.72, "rough": 0.62, "detail": 1.0, "grime": 0.5, "stains": 0.3, "bleach": 0.6, "two_side": true},
	"camp_tub": {"set": "", "tint": 1, "base": Color(0.10, 0.10, 0.11), "rough": 0.55, "grime": 0.35, "two_side": true},
	"camp_pole": {"set": "", "tint": 1, "base": Color(0.46, 0.47, 0.49), "rough": 0.35, "metal": 0.85, "grime": 0.2},
	"camp_tarp": {"set": "camp_tarp", "tile": 0.5, "tint": 0, "rough": 0.5, "detail": 0.8, "grime": 0.45, "stains": 0.4, "bleach": 0.5, "two_side": true},
	"camp_rope": {"set": "", "tint": 1, "base": Color(0.55, 0.50, 0.40), "rough": 0.9, "grime": 0.3},
	"camp_stick": {"set": "", "tint": 1, "base": Color(0.40, 0.30, 0.19), "rough": 0.8, "grime": 0.4},
	"camp_chrome": {"set": "", "tint": 1, "base": Color(0.62, 0.63, 0.64), "rough": 0.32, "metal": 0.95, "grime": 0.3, "stains": 0.25},
	"camp_plastic": {"set": "", "tint": 1, "base": Color(0.52, 0.09, 0.07), "rough": 0.5, "grime": 0.3},
	"camp_rubber": {"set": "", "tint": 1, "base": Color(0.045, 0.045, 0.048), "rough": 0.85, "grime": 0.25},
	"camp_bag": {"set": "camp_plastic", "tile": 0.6, "tint": 0, "rough": 0.26, "detail": 0.25, "grime": 0.35, "stains": 0.15, "bleach": 0.1, "two_side": true},
	"camp_canvas": {"set": "camp_nylon", "tile": 0.3, "tint": 0, "rough": 0.85, "detail": 0.8, "grime": 0.55, "stains": 0.4, "bleach": 0.35},
	"camp_mattress": {"set": "camp_ticking", "tile": 0.45, "tint": 0, "rough": 0.9, "detail": 0.9, "grime": 0.6, "stains": 0.7, "bleach": 0.2},
	"camp_cardboard": {"set": "camp_cardboard", "tile": 0.9, "tint": 1, "base": Color(0.50, 0.38, 0.24), "rough": 0.9, "detail": 1.0, "grime": 0.55, "stains": 0.6, "two_side": true},
	"camp_quilt": {"set": "camp_wool", "tile": 0.4, "tint": 0, "rough": 0.92, "detail": 0.9, "grime": 0.45, "stains": 0.45, "bleach": 0.3, "two_side": true},
	"camp_frame": {"set": "", "tint": 0, "rough": 0.4, "metal": 0.35, "grime": 0.35, "stains": 0.3, "bleach": 0.4},
	"camp_saddle": {"set": "", "tint": 1, "base": Color(0.05, 0.05, 0.05), "rough": 0.6, "grime": 0.2},
}
const CAMP_TEXTURE_MEAN := {
	"camp_nylon": [0.905, 0.956], "camp_tarp": [0.219, 0.362], "camp_cardboard": [0.301, 0.571],
	"camp_ticking": [0.108, 0.327], "camp_wool": [0.171, 0.449], "camp_plastic": [0.002, 0.030],
}
## Every kit piece, for the loading screen to warm and the smoke test to check.
const CAMP_PIECES := ["tent_dome", "tent_pop", "tarp_canopy", "tarp_mound", "cart", "bag_trash",
	"bag_duffel", "bags_pile", "mattress", "bedding", "cardboard", "box", "chair", "bicycle",
	"bike_wheel", "bike_frame"]


## One encampment piece ("tent_dome", "cart", "bicycle"...) as a mesh wearing the camp materials,
## through model_mesh() (LODs, its TRI_BUDGET, and a shadow proxy: the camp shader moves no
## vertices, so a proxy's shadow is the piece's own).
static func encampment(piece: String) -> Mesh:
	var key := "encampment_" + piece
	if _cache.has(key):
		return _cache[key]
	var mesh := model_mesh(ENCAMPMENT_KIT, PackedStringArray(["camp_" + piece]), [], Transform3D.IDENTITY, {}, true)
	for s in mesh.get_surface_count():
		var src := mesh.surface_get_material(s)
		var mat_name := src.resource_name if src else ""
		mesh.surface_set_material(s, camp_material(mat_name if CAMP_MATERIALS.has(mat_name) else "camp_nylon"))
	_cache[key] = mesh
	return mesh


static func camp_material(mat_name: String) -> ShaderMaterial:
	var key := "camp_mat_" + mat_name
	if _cache.has(key):
		return _cache[key]
	var spec: Dictionary = CAMP_MATERIALS[mat_name]
	var mat := ShaderMaterial.new()
	mat.shader = load("res://shaders/encampment_2side.gdshader" if spec.get("two_side", false) else "res://shaders/encampment.gdshader")
	var set_key: String = spec.set
	var albedo := texture(set_key, "Color") if set_key != "" else null
	mat.set_shader_parameter("use_textures", albedo != null)
	if albedo:
		mat.set_shader_parameter("albedo_tex", albedo)
		mat.set_shader_parameter("normal_tex", texture(set_key, "NormalGL"))
		mat.set_shader_parameter("rough_tex", texture(set_key, "Roughness"))
		var mean: Array = CAMP_TEXTURE_MEAN.get(set_key, [0.25, 0.5])
		mat.set_shader_parameter("tex_mean_linear", mean[0])
		mat.set_shader_parameter("tex_mean_srgb", mean[1])
		mat.set_shader_parameter("tile_m", spec.get("tile", 0.6))
	mat.set_shader_parameter("tint_source", spec.tint)
	mat.set_shader_parameter("base_tint", spec.get("base", Color(0.5, 0.5, 0.5)))
	mat.set_shader_parameter("tint_mul", spec.get("mul", 1.0))
	mat.set_shader_parameter("roughness", spec.rough)
	mat.set_shader_parameter("metallic", spec.get("metal", 0.0))
	mat.set_shader_parameter("detail", spec.get("detail", 0.8))
	mat.set_shader_parameter("grime", spec.get("grime", 0.4))
	mat.set_shader_parameter("stains", spec.get("stains", 0.0))
	mat.set_shader_parameter("bleach", spec.get("bleach", 0.0))
	_cache[key] = mat
	return mat


## Every camp piece and material, for the loading screen to warm.
static func camp_materials() -> Array:
	for piece: String in CAMP_PIECES:
		encampment(piece)
	var out: Array = []
	for mat_name: String in CAMP_MATERIALS:
		out.append(camp_material(mat_name))
	return out


## Wet streets: lowers the roughness of every cached road and sidewalk material (0 dry, 1 soaked).
static var _wetness: float = -1.0
static func set_wetness(w: float) -> void:
	if absf(w - _wetness) < 0.01:
		return
	_wetness = w
	# Road surfaces read it from a global instead of being walked one material at a time.
	RenderingServer.global_shader_parameter_set("road_wetness", w)
	for key in _cache:
		var k: String = key
		if k.begins_with("pbr_asphalt") or k.begins_with("pbr_paving") or k.begins_with("pbr_sidewalk") or k.begins_with("pbr_pavers") or k.begins_with("pbr_concrete"):
			var mat = _cache[key]
			if mat is StandardMaterial3D:
				(mat as StandardMaterial3D).roughness = lerpf(1.0, 0.25, w)
				(mat as StandardMaterial3D).metallic_specular = lerpf(0.5, 0.9, w)


## Unit window frame in the XY plane (outer edge 1 x 1, bars 7 percent thick, depth 0..1 along
## +Z, scaled per instance to the window size and 0.1 m). With `sill`, a ledge under it.
static func window_frame(sill: bool) -> Mesh:
	var key := "window_frame_sill" if sill else "window_frame"
	if _cache.has(key):
		return _cache[key]
	# Four flat bars (8 triangles) a few centimeters proud of the wall, facing +Z; a thin box
	# ledge below when a sill is wanted. Flat quads, not boxes: downtown draws hundreds of
	# thousands of these.
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	st.set_material(material(Color.WHITE, 0.55))
	var t := 0.07
	var bars := [
		[Vector3(-0.5 + t * 0.5, 0.0, 0.4), Vector2(t, 1.0)],
		[Vector3(0.5 - t * 0.5, 0.0, 0.4), Vector2(t, 1.0)],
		[Vector3(0.0, 0.5 - t * 0.5, 0.4), Vector2(1.0 - 2.0 * t, t)],
		[Vector3(0.0, -0.5 + t * 0.5, 0.4), Vector2(1.0 - 2.0 * t, t)],
	]
	for bar in bars:
		var quad := QuadMesh.new()
		quad.size = bar[1]
		st.append_from(quad, 0, Transform3D(Basis(), bar[0]))
	if sill:
		var bm := BoxMesh.new()
		bm.size = Vector3(1.12, 0.08, 1.6)
		st.append_from(bm, 0, Transform3D(Basis(), Vector3(0.0, -0.54, 0.8)))
	var mesh := st.commit()
	_cache[key] = mesh
	return mesh


## --- Facade detail kit ---------------------------------------------------------------------
## Real moulded geometry for the buildings near the camera, modelled in Blender by
## tools/facade_kit.py (one node per piece in facade_kit.glb) and placed by Building from its
## seed. How the pieces are built and why is in that script's header; how they bend to fit a
## wall, a window or a shop is in shaders/facade_kit.gdshaderinc.
const FACADE_KIT := MODEL_DIR + "facade_kit.glb"
## Per kit material (the Blender material name): texture set, metres per tile, where the colour
## comes from (0 the instance colour, 1 `base`, 2 an ironwork paint picked per instance), and the
## surface. Texture means are the linear / raw sRGB averages of each set's Color map (measured
## with the command in Building.WALL_TEXTURE_MEAN's comment), so the texture is detail and the
## tint is the colour.
const KIT_MATERIALS := {
	# `ao` is how much of the occlusion Blender baked into UV2 to use. None on the ironwork: its
	# bars are single rings of vertices at each end, buried in the rail they meet, so a baked
	# vertex there reads fully occluded and the whole bar came out black between them.
	"kit_stone_run": {"set": "concrete", "tile": 1.8, "tint": 0, "rough": 0.80, "detail": 0.55, "ao": 0.85, "mitre": true},
	"kit_stone": {"set": "concrete", "tile": 1.8, "tint": 0, "rough": 0.80, "detail": 0.55, "ao": 0.85},
	"kit_paint": {"set": "metal_painted", "tile": 0.9, "tint": 0, "rough": 0.52, "metal": 0.12, "detail": 0.55, "ao": 0.6},
	"kit_iron": {"set": "metal_painted", "tile": 0.8, "tint": 2, "rough": 0.48, "metal": 0.30, "detail": 0.45, "ao": 0.0},
	"kit_dark": {"set": "metal_painted", "tile": 0.8, "tint": 1, "base": Color(0.07, 0.07, 0.075), "rough": 0.62, "metal": 0.25, "detail": 0.30, "ao": 0.5},
	"kit_fabric": {"set": "fabric", "tile": 0.45, "tint": 0, "rough": 0.93, "detail": 0.65, "ao": 0.7, "two_side": true, "stripes": true},
	"kit_wood": {"set": "planks", "tile": 1.6, "tint": 1, "base": Color(0.58, 0.50, 0.42), "rough": 0.90, "detail": 0.9, "ao": 0.5, "swap_uv": true},
}
const KIT_TEXTURE_MEAN := {
	"concrete": [Color(0.482, 0.482, 0.482), Color(0.723, 0.723, 0.723)],
	"metal_painted": [Color(0.746, 0.712, 0.715), Color(0.875, 0.855, 0.857)],
	"fabric": [Color(0.493, 0.493, 0.493), Color(0.729, 0.729, 0.729)],
	"planks": [Color(0.101, 0.079, 0.062), Color(0.349, 0.310, 0.273)],
}


## One kit piece ("cornice_classic", "surround_stucco", "fe_stair_l"...) as a mesh wearing the
## kit materials. Goes through model_mesh() like every other model, so it gets LODs and its
## TRI_BUDGET, but with no shadow proxy: the proxy would keep the glTF's plain materials, and
## without the kit shader's slicing a window's shadow would be cast by a 1 m window.
static func facade_kit(piece: String) -> Mesh:
	var key := "facade_kit_" + piece
	if _cache.has(key):
		return _cache[key]
	var mesh := model_mesh(FACADE_KIT, PackedStringArray(["kit_" + piece]), [], Transform3D.IDENTITY, {}, false)
	for s in mesh.get_surface_count():
		var src := mesh.surface_get_material(s)
		var mat_name := src.resource_name if src else ""
		mesh.surface_set_material(s, kit_material(mat_name if KIT_MATERIALS.has(mat_name) else "kit_stone"))
	_cache[key] = mesh
	return mesh


## Every kit piece loaded and every kit material, for the loading screen to warm.
const KIT_PIECES := ["cornice_classic", "cornice_bracket", "cornice_simple", "coping", "surround_brick_a",
	"surround_brick_b", "surround_stucco", "ac_window", "awning", "balcony", "fe_stair_l",
	"fe_stair_r", "fe_bottom", "water_tank", "vent_mushroom", "vent_turbine", "hvac"]


static func kit_materials() -> Array:
	for piece: String in KIT_PIECES:
		facade_kit(piece)
	var out: Array = []
	for mat_name: String in KIT_MATERIALS:
		out.append(kit_material(mat_name))
	return out


static func kit_material(mat_name: String) -> ShaderMaterial:
	var key := "kit_mat_" + mat_name
	if _cache.has(key):
		return _cache[key]
	var spec: Dictionary = KIT_MATERIALS[mat_name]
	var mat := ShaderMaterial.new()
	mat.shader = load("res://shaders/facade_kit_2side.gdshader" if spec.get("two_side", false) else "res://shaders/facade_kit.gdshader")
	var set_key: String = spec.set
	var albedo := texture(set_key, "Color")
	mat.set_shader_parameter("use_textures", albedo != null)
	if albedo:
		mat.set_shader_parameter("albedo_tex", albedo)
		mat.set_shader_parameter("normal_tex", texture(set_key, "NormalGL"))
		mat.set_shader_parameter("rough_tex", texture(set_key, "Roughness"))
	var mean: Array = KIT_TEXTURE_MEAN.get(set_key, [Color(0.5, 0.5, 0.5), Color(0.73, 0.73, 0.73)])
	mat.set_shader_parameter("tex_mean_linear", mean[0])
	mat.set_shader_parameter("tex_mean_srgb", mean[1])
	mat.set_shader_parameter("tile_m", spec.tile)
	mat.set_shader_parameter("tint_source", spec.tint)
	mat.set_shader_parameter("base_tint", spec.get("base", Color(0.5, 0.5, 0.5)))
	mat.set_shader_parameter("roughness", spec.rough)
	mat.set_shader_parameter("metallic", spec.get("metal", 0.0))
	mat.set_shader_parameter("detail", spec.detail)
	mat.set_shader_parameter("ao_strength", spec.get("ao", 0.8))
	mat.set_shader_parameter("swap_uv", spec.get("swap_uv", false))
	mat.set_shader_parameter("mitre", spec.get("mitre", false))
	mat.set_shader_parameter("slice", not spec.get("mitre", false))
	mat.set_shader_parameter("stripes", spec.get("stripes", false))
	_cache[key] = mat
	return mat


## --- Traffic signals -------------------------------------------------------------------------
## Mast-arm poles, arms, vehicle and pedestrian heads, push buttons and the controller cabinet,
## modelled by tools/make_signals.py (one node per piece in traffic_signal.glb, dimensions in its
## header) and placed by CityChunk._add_signal_corner(). The lenses are one shared material on
## shaders/traffic_signal.gdshader, which lights each lamp from its instance's custom data and
## the `signal_clock` global (TrafficSignals), so every head in the city is a MultiMesh instance
## and nothing ticks per signal.
const SIGNAL_MODEL := MODEL_DIR + "traffic_signal.glb"
## Per signal material (the Blender name): texture set (triplanar, metres per tile) or none, the
## colour it is tinted to, roughness and metallic.
const SIGNAL_MATERIALS := {
	"sig_steel": {"set": "metal_painted", "tile": 0.7, "color": Color(0.64, 0.65, 0.66), "rough": 0.55, "metal": 0.45},
	"sig_steel_dark": {"set": "metal_painted", "tile": 0.5, "color": Color(0.21, 0.21, 0.22), "rough": 0.5, "metal": 0.4},
	"sig_housing": {"set": "metal_painted", "tile": 0.45, "color": Color(0.045, 0.047, 0.044), "rough": 0.42, "metal": 0.0},
	"sig_reflect": {"set": "", "color": Color(0.92, 0.68, 0.05), "rough": 0.42, "metal": 0.0},
	"sig_sign": {"set": "", "color": Color(0.86, 0.86, 0.84), "rough": 0.5, "metal": 0.0},
	"sig_cabinet": {"set": "metal_painted", "tile": 0.8, "color": Color(0.70, 0.72, 0.67), "rough": 0.5, "metal": 0.25},
	"sig_concrete": {"set": "concrete", "tile": 1.6, "color": Color(1.2, 1.18, 1.12), "rough": 1.0, "metal": 0.0},
}
## The model's dimensions the placing code builds on (tools/make_signals.py; the smoke test
## checks them against the loaded meshes' bounds): the arm collar's height on the pole, the arm's
## unscaled length, how far a side-mount bracket reaches, the pole's height.
const SIGNAL_ARM_Y := 6.55
const SIGNAL_ARM_LENGTH := 8.0
const SIGNAL_BRACKET_REACH := 0.55
const SIGNAL_POLE_HEIGHT := 7.6


## One signal piece ("sig_pole", "sig_head"...) wearing the signal materials, or an empty mesh
## when the model is missing (CityChunk then builds the old primitive signal).
static func signal_part(piece: String) -> Mesh:
	var key := "signal_part_" + piece
	if _cache.has(key):
		return _cache[key]
	var mesh := model_mesh(SIGNAL_MODEL, PackedStringArray([piece]), [], Transform3D.IDENTITY, {}, true)
	for s in mesh.get_surface_count():
		var src := mesh.surface_get_material(s)
		mesh.surface_set_material(s, signal_material(src.resource_name if src else ""))
	_cache[key] = mesh
	return mesh


static func signal_material(mat_name: String) -> Material:
	if mat_name == "sig_lens":
		return signal_lens_material()
	var key := "signal_mat_" + mat_name
	if _cache.has(key):
		return _cache[key]
	var spec: Dictionary = SIGNAL_MATERIALS.get(mat_name, SIGNAL_MATERIALS["sig_steel"])
	var mat := StandardMaterial3D.new()
	mat.albedo_color = spec.color
	mat.roughness = spec.rough
	mat.metallic = spec.metal
	var set_key: String = spec.set
	if set_key != "":
		mat.albedo_texture = texture(set_key, "Color")
		var normal := texture(set_key, "NormalGL")
		if normal:
			mat.normal_enabled = true
			mat.normal_texture = normal
			mat.normal_scale = 0.5
		mat.uv1_triplanar = true
		mat.uv1_world_triplanar = true
		mat.uv1_scale = Vector3.ONE / float(spec.tile)
		mat.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS_ANISOTROPIC
	_cache[key] = mat
	return mat


## The lens material every head shares. The cycle's four numbers come from TrafficSignals here,
## so the shader never carries a copy of its own.
static func signal_lens_material() -> ShaderMaterial:
	if _cache.has("signal_lens_mat"):
		return _cache["signal_lens_mat"]
	var mat := ShaderMaterial.new()
	mat.shader = load("res://shaders/traffic_signal.gdshader")
	mat.set_shader_parameter("timing", Vector4(TrafficSignals.GREEN, TrafficSignals.AMBER, TrafficSignals.ALL_RED, TrafficSignals.WALK_TIME))
	_cache["signal_lens_mat"] = mat
	return mat


## Rooftop air conditioning unit (Poly Haven exterior_aircon_unit), 0.8 x 0.93 x 0.4 m, bottom
## at the origin. Clean or rusted.
static func model_ac(rusted: bool) -> Mesh:
	if rusted:
		return model_mesh(MODEL_DIR + "prop_ac.glb", ["rusted"], [], _shift(Vector3(-0.5, 0.32, 0.0)))
	return model_mesh(MODEL_DIR + "prop_ac.glb", [], ["rusted"], _shift(Vector3(0.5, 0.32, 0.0)))


# --- Car wheels --------------------------------------------------------------------------
#
# A wheel is the highest realism-per-triangle part of a car: it is round, so the silhouette is
# unforgiving; it is always in frame; and it is the part a viewer has seen ten thousand times
# in real life, so any error in it is instantly legible. Everything here is generated from
# parameters and cached per style and size, so a car park of a hundred and fifty cars shares a
# handful of meshes.

## The material classes one wheel mesh uses. The class travels in the vertex UV
## (u = (slot + 0.5) / WHEEL_SLOTS, v = 0.5) and is read back out of two WHEEL_SLOTS x 1 lookup
## textures - albedo in one, metallic in the other's red and roughness in its green - so rubber,
## polished rim, steel disc and painted caliper each get their own metallic and roughness while
## the whole wheel stays ONE surface and ONE draw call. The obvious alternative, one surface of
## rubber and one of metal, doubles the draw calls of every car in the city for nothing, and at
## the caps in CityStreamer that is hundreds of calls. Vertex colour is left free for shading
## (the dark inside the barrel, the bright crest of a spoke), which is what stops the wheel
## reading as flat-shaded plastic.
enum WheelSlot {RUBBER, LETTER, FACE, BARREL, DISC, CALIPER, CAP, DARK}
const WHEEL_SLOTS := 8

## Rim finish + caliper colour. Weighted by repetition the way Vehicle.PAINTS is: a real car
## park is mostly silver and dark alloys, with the odd polished, bronze or gloss-black set.
##
## `face` is a METAL's reflectance, not a paint colour, so cast aluminium belongs near 0.9 and
## not near 0.5: at metallic 1.0 there is no diffuse term at all and the albedo IS the whole of
## what the wheel reflects. The first pass used paint-like values and every rim in the city came
## out charcoal. The two finishes that are really paint over metal - gloss black and the dark
## alloy - drop their metallic instead of darkening the reflectance.
## A caliper lives in a cavity that gets almost no direct light, so its COLOUR is all it has to
## separate it from the dust shield and the barrel wall behind it. The plain ones are therefore
## a light cast-alloy grey (0.44-0.50), not the near-black a real caliper often is: at 0.26 the
## caliper was geometrically present and visually absent, which is the same as not modelling it.
const WHEEL_KITS := [
	{"face": Color(0.90, 0.91, 0.92), "metal": 1.0, "rough": 0.30, "cal": Color(0.47, 0.48, 0.50), "cal_metal": 0.45, "cal_rough": 0.45},
	{"face": Color(0.90, 0.91, 0.92), "metal": 1.0, "rough": 0.30, "cal": Color(0.47, 0.48, 0.50), "cal_metal": 0.45, "cal_rough": 0.45},
	{"face": Color(0.42, 0.43, 0.46), "metal": 0.75, "rough": 0.38, "cal": Color(0.44, 0.45, 0.47), "cal_metal": 0.45, "cal_rough": 0.47},
	{"face": Color(0.42, 0.43, 0.46), "metal": 0.75, "rough": 0.38, "cal": Color(0.66, 0.12, 0.09), "cal_metal": 0.12, "cal_rough": 0.34},
	{"face": Color(0.95, 0.96, 0.97), "metal": 1.0, "rough": 0.13, "cal": Color(0.20, 0.30, 0.62), "cal_metal": 0.14, "cal_rough": 0.34},
	{"face": Color(0.085, 0.085, 0.095), "metal": 0.15, "rough": 0.17, "cal": Color(0.78, 0.54, 0.07), "cal_metal": 0.15, "cal_rough": 0.32},
	{"face": Color(0.80, 0.58, 0.32), "metal": 1.0, "rough": 0.34, "cal": Color(0.44, 0.45, 0.47), "cal_metal": 0.45, "cal_rough": 0.47},
]

## Spoke patterns, one per WheelStyle. `n` is the spoke count; `hub` / `mid` / `rim` are the
## spoke's angular half-width at the hub, the waist and the rim as fractions of the half-pitch
## (1.0 would touch its neighbour, so `hub` near 1 is what melts the spokes into a hub disc);
## `twist` sweeps the spoke round as it goes out (a turbine); `ring` lays a concentric band over
## the spokes at that fraction of the rim radius (a mesh wheel); `dish` is how far the hub sits
## behind the rim edge, in half-widths - this is the number that makes the rim a dish rather
## than a plate; `rim_ratio` is the rim diameter over the tyre diameter (a 225/45R18 is 0.71).
const WHEEL_FACES := [
	{"n": 5, "hub": 0.92, "mid": 0.42, "rim": 0.74, "twist": 0.00, "ring": 0.0, "dish": 0.34, "rim_ratio": 0.735},
	{"n": 10, "hub": 0.86, "mid": 0.36, "rim": 0.60, "twist": 0.00, "ring": 0.0, "dish": 0.30, "rim_ratio": 0.750},
	{"n": 12, "hub": 0.76, "mid": 0.30, "rim": 0.62, "twist": 0.12, "ring": 0.62, "dish": 0.36, "rim_ratio": 0.720},
	{"n": 6, "hub": 0.97, "mid": 0.80, "rim": 0.93, "twist": 0.00, "ring": 0.0, "dish": 0.22, "rim_ratio": 0.680},
	{"n": 9, "hub": 0.90, "mid": 0.44, "rim": 0.68, "twist": 0.30, "ring": 0.0, "dish": 0.33, "rim_ratio": 0.745},
]


## True when the renderer can actually light a metal - i.e. when there is a radiance map and
## reflection probes behind BaseMaterial3D's metallic term. Forward+ can; the Compatibility
## renderer, which is what the web build and every opengl3 screenshot tool runs, cannot, and a
## metal there comes back black. The RenderingDevice is the honest test: Compatibility is the
## one renderer that does not have one, and unlike OS.has_feature("web") it also catches a
## desktop that fell back to OpenGL and the headless screenshot tools.
static func has_reflections() -> bool:
	if _cache.has("has_refl"):
		return _cache["has_refl"]
	var yes := RenderingServer.get_rendering_device() != null
	_cache["has_refl"] = yes
	return yes


## The wheel shader. It belongs in shaders/wheel.gdshader and is only inline because this task
## was allowed to touch two script files; move it out when there is a chance to.
##
## Eight material classes, one surface, one draw call. The class travels in UV.x and the vertex
## colour carries the shading term, so the meshes stay shared between cars while the finish
## comes off the material. The obvious alternative, one surface of rubber and one of metal,
## doubles the draw calls of every car in the city, and at the caps in CityStreamer that is
## hundreds of calls.
##
## The classes are uniforms rather than the two 8 x 1 lookup textures this started as. That is
## not the bug fix - the bug was elsewhere, see below - but a branch that is coherent across a
## whole spoke is cheaper than two texture fetches per wheel pixel, it cannot be filtered or
## mipped into the wrong class, and the Compatibility fallback below is then something you can
## read off the material instead of out of an image.
##
## WHY THE RIMS WERE BLACK, since it was not the metal: the hand-written vertex normals were
## inverted, and so was the winding _wq() derived from them. Measured with
## tools/glshot/wheel_shot.gd --mode=styles_normals, which paints the world normal into the
## colour channels: every revolved surface and every spoke face pointed AWAY from the camera, so
## the whole wheel was lit by ambient alone whatever its albedo said, and the flat surfaces that
## close the wheel - hub disc, centre cap, dust shield, brake disc - were culled outright, which
## is why a car had a body-coloured hole where its hub should be. The fix is in _wq() and in
## car_wheel()'s generate_normals(). The Compatibility fallback is still right and still needed,
## but on its own it moved the rim from byte 81 to byte 81; the normals moved it to 231.
##
## Shader code uses // comments: a ## line is a syntax error and Godot silently falls back to a
## blank white material (CLAUDE.md).
const WHEEL_SHADER := """
shader_type spatial;
render_mode cull_back, diffuse_burley, specular_schlick_ggx;

// Albedo per material class. Plain vec3, not source_color: these are set from Vector3s that
// are already linear reflectances, and letting Godot sRGB-convert them again is how a 0.90
// aluminium turns into a 0.78 one.
uniform vec3 c_rubber = vec3(0.05);
uniform vec3 c_letter = vec3(0.12);
uniform vec3 c_face = vec3(0.90);
uniform vec3 c_barrel = vec3(0.54);
uniform vec3 c_disc = vec3(0.60);
uniform vec3 c_caliper = vec3(0.45);
uniform vec3 c_cap = vec3(0.92);
uniform vec3 c_dark = vec3(0.10);
// x metallic, y roughness, in the same order.
uniform vec2 m_rubber = vec2(0.0, 0.95);
uniform vec2 m_letter = vec2(0.0, 0.62);
uniform vec2 m_face = vec2(1.0, 0.30);
uniform vec2 m_barrel = vec2(1.0, 0.56);
uniform vec2 m_disc = vec2(0.35, 0.42);
uniform vec2 m_caliper = vec2(0.45, 0.45);
uniform vec2 m_cap = vec2(1.0, 0.22);
uniform vec2 m_dark = vec2(0.10, 0.85);

// How much of the vertex shading term is held back from the albedo. The mesh's vertex colours
// run down to 0.30 in the barrel and the dust shield and 0.56 on a spoke flank; they are there
// to fake the occlusion of a cavity, and the renderer shades and shadows the same geometry
// itself, so at full strength the two multiply together and the cavities go to pitch. A fifth
// held back keeps the modelled shading legible without crushing it. Check it with
// tools/glshot/wheel_vertex_probe.gd (the colours as authored) and wheel_shot.gd
// --mode=styles_debug (class and shade painted into the colour channels).
uniform float shade_lift = 0.20;

void fragment() {
	int slot = int(clamp(UV.x * 8.0, 0.0, 7.999));
	vec3 shade = mix(vec3(1.0), COLOR.rgb, 1.0 - shade_lift);
	vec3 alb = c_dark;
	vec2 mr = m_dark;
	if (slot == 0) { alb = c_rubber; mr = m_rubber; }
	else if (slot == 1) { alb = c_letter; mr = m_letter; }
	else if (slot == 2) { alb = c_face; mr = m_face; }
	else if (slot == 3) { alb = c_barrel; mr = m_barrel; }
	else if (slot == 4) { alb = c_disc; mr = m_disc; }
	else if (slot == 5) { alb = c_caliper; mr = m_caliper; }
	else if (slot == 6) { alb = c_cap; mr = m_cap; }
	ALBEDO = alb * shade;
	METALLIC = mr.x;
	ROUGHNESS = mr.y;
}
"""
## The uniform suffixes, in WheelSlot order.
const WHEEL_UNIFORMS := ["rubber", "letter", "face", "barrel", "disc", "caliper", "cap", "dark"]


## The shared material for one wheel kit. Set it as `material_override` on the wheel and the
## caliper: the meshes are cached per size and style and shared between cars, so the finish
## cannot live on the mesh.
## `force_metal` keeps the Forward+ metal path on a renderer that cannot light it. Nothing in
## the game passes it; tools/glshot/wheel_shot.gd does, so the two paths can be rendered side by
## side under the same software GL and the fallback can be shown to do something.
static func wheel_material(kit: int, force_metal: bool = false) -> ShaderMaterial:
	var key := "wheel_mat_%d%s" % [kit, "_m" if force_metal else ""]
	if _cache.has(key):
		return _cache[key]
	var k: Dictionary = WHEEL_KITS[posmod(kit, WHEEL_KITS.size())]
	var face: Color = k.face
	var cal: Color = k.cal
	# Albedo per slot. Rubber is 0.05, not 0.0: a real tyre is the darkest thing on a car but it
	# is not black, and at 0.0 it takes no bounce light at all and reads as a hole.
	# DISC is a brake rotor: cast iron polished to a mirror by the pads where they sweep, so the
	# friction band is one of the BRIGHTEST things on the car, not a dark grey washer. It is
	# deliberately far from the dust shield behind it (0.10) - the two used to sit within a few
	# hundredths of each other and the whole cavity read as one dark mass.
	var albedo := [
		Color(0.052, 0.052, 0.056), Color(0.115, 0.115, 0.120), face, face * 0.60,
		Color(0.60, 0.59, 0.57), cal, face.lerp(Color.WHITE, 0.12), Color(0.100, 0.100, 0.105),
	]
	# x = metallic, y = roughness.
	var mr := [
		Vector2(0.0, 0.95), Vector2(0.0, 0.62), Vector2(k.metal, k.rough),
		Vector2(k.metal, minf(float(k.rough) + 0.26, 1.0)), Vector2(0.35, 0.42),
		Vector2(k.cal_metal, k.cal_rough), Vector2(k.metal, float(k.rough) * 0.75),
		Vector2(0.10, 0.85),
	]
	# --- The Compatibility renderer, which IS the shipped web build --------------------------
	#
	# A metal has no diffuse term at all: every photon it sends back is a reflection of its
	# surroundings. Forward+ has a radiance map of the sky and real reflection probes to supply
	# those, so a 0.90-reflectance rim reads as aluminium. Compatibility has neither worth the
	# name, so the same rim reads as a black disc whatever its albedo says - which is what every
	# wheel in the web build and in every opengl3 screenshot was doing.
	#
	# So on that renderer the finish is re-expressed as paint over metal: most of the reflectance
	# is moved into a diffuse albedo (gamma-corrected, because the reflectance value is linear
	# and a diffuse surface lit by one sun lands about there), the metallic term is cut to a
	# sheen, and the roughness is pulled up so the specular lobe that is left spreads out instead
	# of hunting for a highlight that is not in the environment. Forward+ is untouched.
	if not has_reflections() and not force_metal:
		for i in albedo.size():
			var m: float = (mr[i] as Vector2).x
			if m <= 0.02:
				continue
			var c: Color = albedo[i]
			# The rim keeps its hue (bronze stays bronze); only the level moves.
			albedo[i] = Color(pow(c.r, 0.62), pow(c.g, 0.62), pow(c.b, 0.62)).lerp(c, 1.0 - m)
			mr[i] = Vector2(m * 0.22, lerpf((mr[i] as Vector2).y, 0.55, 0.55 * m))
	if not _cache.has("wheel_shader"):
		var sh := Shader.new()
		sh.code = WHEEL_SHADER
		_cache["wheel_shader"] = sh
	var mat := ShaderMaterial.new()
	mat.shader = _cache["wheel_shader"]
	for i in WHEEL_SLOTS:
		var c: Color = albedo[i]
		mat.set_shader_parameter("c_" + WHEEL_UNIFORMS[i], Vector3(c.r, c.g, c.b))
		mat.set_shader_parameter("m_" + WHEEL_UNIFORMS[i], mr[i])
	_cache[key] = mat
	return mat


## One vertex of a wheel: position, normal, shading colour and material slot.
static func _wv(st: SurfaceTool, p: Vector3, n: Vector3, shade: float, slot: int) -> void:
	st.set_color(Color(shade, shade, shade))
	st.set_uv(Vector2((float(slot) + 0.5) / float(WHEEL_SLOTS), 0.5))
	st.set_normal(n)
	st.add_vertex(p)


## A quad with per-corner normals, wound so that it faces the way its normals point. Godot culls
## back faces, and a quad wound the wrong way round simply is not there - which looks exactly
## like a missing mesh and is the trap the freeway deck fell into twice. Letting the normal pick
## the winding removes the whole class of bug from geometry this fiddly.
static func _wq(st: SurfaceTool, a: Vector3, b: Vector3, c: Vector3, d: Vector3,
		na: Vector3, nb: Vector3, nc: Vector3, nd: Vector3, shade: float, slot: int) -> void:
	# > 0.0, not < 0.0. Godot's front face is the one whose vertices wind CLOCKWISE, which is the
	# opposite of the right-hand rule this test reads like - the same trap the freeway deck fell
	# into twice (CLAUDE.md). With the comparison the other way round every surface here was
	# built back to front: the tyre showed the inside of its far wall, and the flat ones that
	# close the wheel - the hub disc, the centre cap, the dust shield, the brake disc - were
	# culled outright, so you looked through the middle of the wheel and out at the bodywork
	# behind it. On the car that is a red hole where the hub should be.
	var order: Array = [[a, na], [b, nb], [c, nc], [a, na], [c, nc], [d, nd]]
	if (b - a).cross(c - a).dot(na + nb + nc + nd) > 0.0:
		order = [[a, na], [d, nd], [c, nc], [a, na], [c, nc], [b, nb]]
	for pair: Array in order:
		_wv(st, pair[0], pair[1], shade, slot)


## A flat-shaded quad. `hint` is roughly which way the face should look; the corners decide the
## exact normal, so a tread block or a spoke flank lights by its own angle.
static func _wqf(st: SurfaceTool, a: Vector3, b: Vector3, c: Vector3, d: Vector3,
		hint: Vector3, shade: float, slot: int) -> void:
	var n := (b - a).cross(c - a)
	if n.length_squared() < 1e-14:
		n = (c - a).cross(d - a)
	if n.length_squared() < 1e-14:
		return
	n = n.normalized()
	if n.dot(hint) < 0.0:
		n = -n
	_wq(st, a, b, c, d, n, n, n, n, shade, slot)


## A point on a surface of revolution about X: `x` along the axle, `r` out from it.
static func _wp(x: float, r: float, a: float) -> Vector3:
	return Vector3(x, r * cos(a), r * sin(a))


## The outward normal of a revolved band, from the profile step (dx, dr).
static func _wn2(dx: float, dr: float) -> Vector2:
	var n := Vector2(dr, -dx)
	return n.normalized() if n.length_squared() > 1e-14 else Vector2(0.0, 1.0)


## The tread pattern: how far a profile row's radius is pulled in at circumferential step `j`.
## `mod` 0 is a plain band, 1 is a shoulder lug (deep, one in four, so the shoulder scallops -
## the single most legible tread cue in silhouette) and 10 + k is crown rib k, staggered by rib
## so the lateral grooves do not line up into one ladder all the way across the tread.
static func _wheel_tread(mod: int, j: int, r: float) -> float:
	if mod <= 0:
		return 0.0
	if mod == 1:
		return -r * 0.017 if (j + 1) % 4 == 0 else 0.0
	return -r * 0.009 if (j + (mod - 10)) % 4 == 3 else 0.0


## Revolves a profile about the X axis. `prof` rows are [x, r, slot, shade] with an optional
## fifth tread-pattern entry (see _wheel_tread). The profile is walked in order and the winding
## derived from it, so a sidewall that bulges outboard and a crown that runs inboard both come
## out facing the right way. `inward` turns the surface inside out, which is how the inside of
## the rim barrel - the part you see through the spokes - is built without a second shell.
static func _wheel_revolve(st: SurfaceTool, prof: Array, seg: int, inward: bool = false) -> void:
	var rows := prof.size() - 1
	if rows < 1:
		return
	var n2 := PackedVector2Array()
	n2.resize(rows)
	for k in rows:
		n2[k] = _wn2(float(prof[k + 1][0]) - float(prof[k][0]), float(prof[k + 1][1]) - float(prof[k][1]))
	# Smooth along the profile except across a crease: a groove wall meeting the tread at ninety
	# degrees has to stay hard or the tread melts into a ripple.
	var na := n2.duplicate()
	var nb := n2.duplicate()
	for k in rows:
		if k > 0 and n2[k].dot(n2[k - 1]) > 0.55:
			na[k] = (n2[k] + n2[k - 1]).normalized()
		if k < rows - 1 and n2[k].dot(n2[k + 1]) > 0.55:
			nb[k] = (n2[k] + n2[k + 1]).normalized()
	var flip := -1.0 if inward else 1.0
	for k in rows:
		var x0 := float(prof[k][0])
		var r0 := float(prof[k][1])
		var x1 := float(prof[k + 1][0])
		var r1 := float(prof[k + 1][1])
		var slot := int(prof[k][2])
		var shade := (float(prof[k][3]) + float(prof[k + 1][3])) * 0.5
		var m0 := int(prof[k][4]) if prof[k].size() > 4 else 0
		var m1 := int(prof[k + 1][4]) if prof[k + 1].size() > 4 else 0
		for j in seg:
			var a0 := TAU * float(j) / float(seg)
			var a1 := TAU * float(j + 1) / float(seg)
			var d0j := _wheel_tread(m0, j, r0)
			var d0k := _wheel_tread(m0, j + 1, r0)
			var d1j := _wheel_tread(m1, j, r1)
			var d1k := _wheel_tread(m1, j + 1, r1)
			var p00 := _wp(x0, r0 + d0j, a0)
			var p10 := _wp(x1, r1 + d1j, a0)
			var p11 := _wp(x1, r1 + d1k, a1)
			var p01 := _wp(x0, r0 + d0k, a1)
			if m0 != 0 or m1 != 0:
				# A tread block face has to light by its own angle, so let the corners set the
				# normal; the profile normal knows nothing about the step out of the groove.
				_wqf(st, p00, p10, p11, p01, _wp(0.0, 1.0, a0) * flip, shade, slot)
				continue
			var m00 := Vector3(na[k].x, na[k].y * cos(a0), na[k].y * sin(a0)) * flip
			var m01 := Vector3(na[k].x, na[k].y * cos(a1), na[k].y * sin(a1)) * flip
			var m10 := Vector3(nb[k].x, nb[k].y * cos(a0), nb[k].y * sin(a0)) * flip
			var m11 := Vector3(nb[k].x, nb[k].y * cos(a1), nb[k].y * sin(a1)) * flip
			_wq(st, p00, p10, p11, p01, m00, m10, m11, m01, shade, slot)


## One car wheel, axle along X, outboard face toward +X, centred on the hub. `radius` is the
## overall tyre radius and `width` the widest point of the tyre (the sidewall bulge, not the
## tread). `near` builds the close-up mesh; false builds the far LOD, which Vehicle swaps in
## past wheel_lod_distance - the city runs a hundred and fifty traffic cars and the far mesh is
## what makes that affordable.
static func car_wheel(style: int, radius: float, width: float, near: bool) -> Mesh:
	var key := "cw_%d_%d_%d_%d" % [style, roundi(radius * 500.0), roundi(width * 500.0), int(near)]
	if _cache.has(key):
		return _cache[key]
	var face: Dictionary = WHEEL_FACES[posmod(style, WHEEL_FACES.size())]
	var rim_r := radius * float(face.rim_ratio)
	var hw := width * 0.5
	# 96 is not vanity. It sets the silhouette of a circle the player stands next to, and it
	# also sets the tread: the lateral block pattern runs on a four-segment period, so 96 gives
	# twenty-four blocks round a 2.2 m circumference - one every nine centimetres. At 72 they
	# were twelve centimetres apart and the tread read as a tractor tyre. The count therefore
	# has to stay a multiple of four or the pattern does not close round the ring.
	var seg := 96 if near else 20
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	_wheel_tyre(st, radius, rim_r, hw, seg, near)
	_wheel_barrel(st, rim_r, hw, seg, near)
	_wheel_brake(st, rim_r, hw, near)
	_wheel_face(st, face, rim_r, hw, near)
	# Indexed, not a raw triangle soup. A near wheel is eleven thousand triangles and the city
	# ends up holding one per style and size; welding the shared vertices roughly halves what
	# that costs in memory and gives the GPU a post-transform cache to work with.
	st.index()
	# And then the normals are REGENERATED from the welded topology. The hand-written ones were
	# inverted: measured with tools/glshot/wheel_shot.gd --mode=styles_normals, which paints the
	# world normal into the colour channels, every revolved surface and every spoke face came
	# out pointing away from the camera, so the whole wheel was lit by ambient alone and read as
	# gloss black however bright its albedo was. That is the whole of the "the rims are near
	# black" report, and it is not the metal.
	#
	# Godot's own winding convention is the one thing here that cannot be got wrong, so let it
	# decide: generate_normals() derives the normal from the winding of the triangles that were
	# actually emitted. The authored normals are still what decides WELDING, and so which edges
	# stay hard (a groove wall meeting the tread) and which smooth out (the barrel, the tyre
	# round its circumference) - the smoothing survives, only the sign changes.
	st.generate_normals()
	var mesh := st.commit()
	_cache[key] = mesh
	return mesh


## The brake caliper, as its own mesh. It is separate because it must NOT spin with the wheel:
## a caliper is bolted to the upright, and one going round with the rim is the tell that the
## whole assembly is a single spinning cylinder. It is also tiny and only drawn up close, so it
## costs almost nothing. Same material as the wheel.
static func car_caliper(style: int, radius: float, width: float) -> Mesh:
	var key := "ccal_%d_%d_%d" % [style, roundi(radius * 500.0), roundi(width * 500.0)]
	if _cache.has(key):
		return _cache[key]
	var face: Dictionary = WHEEL_FACES[posmod(style, WHEEL_FACES.size())]
	var rim_r := radius * float(face.rim_ratio)
	var hw := width * 0.5
	var br := rim_r * 0.76
	var thick := rim_r * 0.105
	var x_out := -hw * 0.02 + thick * 0.85
	var x_in := -hw * 0.02 - thick * 1.85
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	# A block straddling the disc at the top. The top is deliberate: the wheel mesh is turned
	# round by PI for the left-hand side of the car, so anything off-centre would sit at the
	# front on one side and the back on the other. At top dead centre it mirrors correctly.
	var span := 0.50
	var steps := 9
	var r_in := br * 0.68
	var r_out := br + rim_r * 0.055
	var prev: Array = []
	for i in steps + 1:
		var a := -span + 2.0 * span * float(i) / float(steps)
		# The body swells in the middle, where the pistons are.
		var bulge := 1.0 + 0.10 * sin(PI * float(i) / float(steps))
		var ro := r_out * bulge
		var ring: Array = [
			_wp(x_out, ro, a), _wp(x_out, r_in, a), _wp(x_in, r_in, a), _wp(x_in, ro, a),
		]
		if not prev.is_empty():
			var mid := _wp(0.0, 1.0, a)
			_wqf(st, prev[0], ring[0], ring[3], prev[3], mid, 1.0, WheelSlot.CALIPER)          # outer
			_wqf(st, prev[1], ring[1], ring[2], prev[2], -mid, 0.42, WheelSlot.DARK)           # inner
			_wqf(st, prev[0], ring[0], ring[1], prev[1], Vector3.RIGHT, 0.86, WheelSlot.CALIPER)  # outboard cheek
			_wqf(st, prev[3], ring[3], ring[2], prev[2], Vector3.LEFT, 0.62, WheelSlot.CALIPER)   # inboard cheek
		else:
			_wqf(st, ring[0], ring[1], ring[2], ring[3], _wp(0.0, 1.0, a).cross(Vector3.RIGHT), 0.70, WheelSlot.CALIPER)
		prev = ring
	_wqf(st, prev[0], prev[1], prev[2], prev[3], _wp(0.0, 1.0, span).cross(Vector3.LEFT), 0.70, WheelSlot.CALIPER)
	# Two mounting bosses on the inboard cheek: a caliper is a casting with lugs, and the pair
	# of bumps is what stops the block reading as a box someone left on the disc.
	for s: float in [-0.30, 0.30]:
		var a := s
		var c := _wp(x_in - thick * 0.45, (r_in + r_out) * 0.5, a)
		_box_wheel(st, c, Vector3(thick * 0.9, rim_r * 0.10, rim_r * 0.10), a, 0.55, WheelSlot.CALIPER)
	st.index()
	st.generate_normals()
	var mesh := st.commit()
	_cache[key] = mesh
	return mesh


## A little box lying along the axle at angle `a` round the wheel, used for caliper lugs and
## lug nuts. `size` is (along X, radial, tangential).
static func _box_wheel(st: SurfaceTool, centre: Vector3, size: Vector3, a: float, shade: float, slot: int) -> void:
	var rad := _wp(0.0, 1.0, a)
	var tan := Vector3(0.0, -sin(a), cos(a))
	var ax := Vector3.RIGHT
	var corners: Array = []
	for sx: float in [1.0, -1.0]:
		for sr: float in [1.0, -1.0]:
			for stn: float in [1.0, -1.0]:
				corners.append(centre + ax * (sx * size.x * 0.5) + rad * (sr * size.y * 0.5) + tan * (stn * size.z * 0.5))
	# corners: 0 +x+r+t 1 +x+r-t 2 +x-r+t 3 +x-r-t 4 -x+r+t 5 -x+r-t 6 -x-r+t 7 -x-r-t
	_wqf(st, corners[0], corners[1], corners[3], corners[2], ax, shade, slot)
	_wqf(st, corners[4], corners[5], corners[7], corners[6], -ax, shade * 0.8, slot)
	_wqf(st, corners[0], corners[1], corners[5], corners[4], rad, shade * 1.05, slot)
	_wqf(st, corners[2], corners[3], corners[7], corners[6], -rad, shade * 0.7, slot)
	_wqf(st, corners[0], corners[2], corners[6], corners[4], tan, shade * 0.9, slot)
	_wqf(st, corners[1], corners[3], corners[7], corners[5], -tan, shade * 0.9, slot)


## The tyre. A tyre is NOT a cylinder, which is exactly what made the old wheel read as a disc:
## it swells where it leaves the rim (the widest point of a car's wheel is the sidewall, not the
## tread), rounds over at the shoulder, and only then runs flat across the crown. On top of that
## it carries four circumferential grooves cut into the profile and, at `detail`, a lateral
## block pattern driven off the tread modulation in _wheel_revolve.
##
## Geometry, not a normal map, for the grooves: the grooves are in the profile, so they cost
## three extra rows out of thirty-odd and NOTHING per car (the mesh is shared), where a tread
## normal map costs a texture fetch on every wheel pixel in the city plus a tangent per vertex,
## and still leaves the shoulder silhouette smooth. Measured on the near mesh the whole tread
## pattern - grooves, ribs and shoulder lugs - is about 2.4k of the 12k triangles.
static func _wheel_tyre(st: SurfaceTool, r_out: float, rim_r: float, hw: float, seg: int, detail: bool) -> void:
	var sw := r_out - rim_r                     # sidewall height
	var bead := rim_r + r_out * 0.055
	var crown_x := 0.715
	var crown := func(xf: float) -> float:
		# The tread is crowned, not flat: a tyre stands on the middle of its tread.
		return r_out - r_out * 0.012 * pow(absf(xf) / crown_x, 2.0)
	# [x in half-widths, radius, slot, shade, tread pattern]
	var prof: Array = [
		[0.885, bead, WheelSlot.RUBBER, 0.58, 0],
		[0.945, rim_r + sw * 0.17, WheelSlot.RUBBER, 0.76, 0],
		[1.000, rim_r + sw * 0.36, WheelSlot.RUBBER, 0.98, 0],   # the sidewall bulge
		[0.975, rim_r + sw * 0.52, WheelSlot.LETTER, 1.00, 0],   # moulded lettering band
		[0.930, rim_r + sw * 0.68, WheelSlot.LETTER, 0.90, 0],
		[0.875, rim_r + sw * 0.84, WheelSlot.RUBBER, 0.82, 0],
		[0.855, r_out * 0.962, WheelSlot.RUBBER, 0.74, 1],       # shoulder, scalloped by lugs
		[0.795, r_out * 0.990, WheelSlot.RUBBER, 0.84, 1],
		[crown_x, crown.call(crown_x), WheelSlot.RUBBER, 0.94, 10],
	]
	if detail:
		var gd := r_out * 0.028
		var gw := 0.075
		var rib := 0
		for g: float in [0.505, 0.170, -0.170, -0.505]:
			prof.append([g + gw, crown.call(g + gw), WheelSlot.RUBBER, 0.94, 10 + rib])
			prof.append([g + gw * 0.55, crown.call(g) - gd, WheelSlot.RUBBER, 0.40, 0])
			prof.append([g - gw * 0.55, crown.call(g) - gd, WheelSlot.RUBBER, 0.40, 0])
			rib += 1
			prof.append([g - gw, crown.call(g - gw), WheelSlot.RUBBER, 0.94, 10 + rib])
		prof.append([-crown_x, crown.call(-crown_x), WheelSlot.RUBBER, 0.94, 10 + rib])
	else:
		prof.append([-crown_x, crown.call(-crown_x), WheelSlot.RUBBER, 0.94, 0])
	# The inboard half mirrors the outboard one. No lettering on the inside: nobody ever sees it
	# and it would only cost a slot change.
	for i in range(7, -1, -1):
		var e: Array = prof[i]
		var slot: int = e[2]
		prof.append([-float(e[0]), e[1], WheelSlot.RUBBER if slot == WheelSlot.LETTER else slot, e[3], e[4]])
	for row: Array in prof:
		row[0] = float(row[0]) * hw
	_wheel_revolve(st, prof, seg)


## The rim barrel: a real lip at each edge, a bead seat, a drop centre and the inside of the
## well, which is what you actually look at through the spokes. Only the flange rings get an
## outer skin - everything between them is under the tyre and would be paying for geometry
## nobody can see.
static func _wheel_barrel(st: SurfaceTool, rim_r: float, hw: float, seg: int, detail: bool) -> void:
	var lip := rim_r * 0.055
	var well := rim_r * 0.20
	var shell := rim_r * 0.038
	# [x in half-widths, radius]
	var outline: Array = [
		[0.900, rim_r + lip], [0.845, rim_r + lip], [0.815, rim_r + rim_r * 0.010],
		[0.560, rim_r - rim_r * 0.028], [0.120, rim_r - well],
		[-0.380, rim_r - rim_r * 0.045], [-0.800, rim_r + rim_r * 0.010], [-0.870, rim_r + lip],
	]
	if not detail:
		outline = [[0.900, rim_r + lip], [0.120, rim_r - well * 0.6], [-0.870, rim_r + lip]]
	var inner: Array = []
	for i in outline.size():
		var row: Array = outline[i]
		# Deeper in the well is darker: it is a cavity, and a cavity that lights as brightly as
		# the face is the thing that makes a modelled rim look like a printed disc.
		var t := float(i) / float(maxf(outline.size() - 1, 1))
		var dark := 0.62 - 0.26 * sin(PI * t)
		inner.append([float(row[0]) * hw, float(row[1]) - shell, WheelSlot.BARREL, dark])
	_wheel_revolve(st, inner, seg, true)
	# Outer skin of the two flanges only.
	var lip_out: Array = [
		[float(outline[0][0]) * hw, float(outline[0][1]), WheelSlot.FACE, 1.0],
		[float(outline[1][0]) * hw, float(outline[1][1]), WheelSlot.FACE, 0.92],
		[float(outline[2][0]) * hw, float(outline[2][1]), WheelSlot.FACE, 0.70],
	]
	if detail:
		_wheel_revolve(st, lip_out, seg)
		var n := outline.size()
		_wheel_revolve(st, [
			[float(outline[n - 3][0]) * hw, float(outline[n - 3][1]), WheelSlot.BARREL, 0.55],
			[float(outline[n - 2][0]) * hw, float(outline[n - 2][1]), WheelSlot.BARREL, 0.62],
			[float(outline[n - 1][0]) * hw, float(outline[n - 1][1]), WheelSlot.FACE, 0.80],
		], seg)
	else:
		_wheel_revolve(st, lip_out, seg)
	# The edge of each flange, so the lip has thickness instead of being a knife.
	for i: int in [0, outline.size() - 1]:
		var x := float(outline[i][0]) * hw
		var r := float(outline[i][1])
		# inward flips the normal, and the outboard flange edge is the one that has to look
		# back at the camera along +X.
		_wheel_revolve(st, [[x, r, WheelSlot.FACE, 0.95], [x, r - shell, WheelSlot.FACE, 0.75]],
				seg, i == 0)


## The brake disc, seen through the spokes. This is the detail that most separates a modelled
## wheel from a toy one and it is nearly free: a ring, an edge and a bell. At `detail` the
## friction band also carries slots - every third segment stepped in by a millimetre - which is
## what makes it read as a disc rather than a grey washer.
static func _wheel_brake(st: SurfaceTool, rim_r: float, hw: float, detail: bool) -> void:
	var seg := 44 if detail else 14
	var br := rim_r * 0.76
	var hat_r := rim_r * 0.30
	var thick := rim_r * 0.105
	var x0 := -hw * 0.02
	var x1 := x0 - thick
	var band := br * 0.78
	# Outboard face: the bell, then the friction band, then a lip at the outside edge.
	var slot_depth := thick * 0.10 if detail else 0.0
	for j in seg:
		var a0 := TAU * float(j) / float(seg)
		var a1 := TAU * float(j + 1) / float(seg)
		var cut := slot_depth if j % 3 == 0 else 0.0
		var rings: Array = [
			[hat_r, x0 + thick * 0.55, 0.42], [hat_r * 1.22, x0, 0.50],
			[band, x0 - cut, 0.92], [br, x0 - cut, 0.86],
		]
		for k in rings.size() - 1:
			var ra: float = rings[k][0]
			var rb: float = rings[k + 1][0]
			var xa: float = rings[k][1]
			var xb: float = rings[k + 1][1]
			var shade := (float(rings[k][2]) + float(rings[k + 1][2])) * 0.5
			_wqf(st, _wp(xa, ra, a0), _wp(xb, rb, a0), _wp(xb, rb, a1), _wp(xa, ra, a1),
					Vector3.RIGHT, shade, WheelSlot.DISC)
	# Edge and inboard face.
	_wheel_revolve(st, [[x0, br, WheelSlot.DISC, 0.80], [x1, br, WheelSlot.DISC, 0.66]], seg)
	_wheel_revolve(st, [[x1, br, WheelSlot.DISC, 0.60], [x1, hat_r, WheelSlot.DISC, 0.36]], seg)
	# The bell, closing the centre of the wheel so you cannot see straight through the hub.
	_wheel_revolve(st, [[x0 + thick * 0.55, hat_r, WheelSlot.DARK, 0.40],
			[hw * 0.30, hat_r * 0.92, WheelSlot.DARK, 0.30]], seg)


## The rim face: the spokes, the dish they sit in, the centre cap and the lug nuts. A rim is a
## dish, not a plate - the hub sits `dish` half-widths behind the rim edge and the spokes sweep
## out and forward to meet the barrel, so there is real depth between the face and the lip and
## real shadow between the spokes. A flat face is the other half of why the old wheel read as a
## disc.
static func _wheel_face(st: SurfaceTool, face: Dictionary, rim_r: float, hw: float, detail: bool) -> void:
	var n: int = int(face.n)
	var hp := PI / float(n)
	var hub_r := rim_r * 0.30
	var x_rim := hw * 0.66
	var x_hub := x_rim - hw * float(face.dish)
	var stations := 14 if detail else 4
	var across := 4 if detail else 1
	var crown := hw * 0.055
	var twist := float(face.twist)
	var at := func(t: float) -> Vector4:
		# x, radius, half-angle, depth
		var r := lerpf(hub_r, rim_r + rim_r * 0.02, t)
		var x := x_hub + (x_rim - x_hub) * smoothstep(0.0, 1.0, t)
		var h := hp * (float(face.mid) + (float(face.hub) - float(face.mid)) * pow(1.0 - t, 2.4)
				+ (float(face.rim) - float(face.mid)) * pow(t, 3.2))
		return Vector4(x, r, h, hw * lerpf(0.34, 0.14, t))
	var point := func(t: float, u: float, base: float) -> Vector3:
		var s: Vector4 = at.call(t)
		return _wp(s.x - crown * u * u, s.y, base + twist * t + s.z * u)
	for i in n:
		var base := TAU * float(i) / float(n)
		for k in stations:
			var t0 := float(k) / float(stations)
			var t1 := float(k + 1) / float(stations)
			var s0: Vector4 = at.call(t0)
			var s1: Vector4 = at.call(t1)
			for c in across:
				var u0 := -1.0 + 2.0 * float(c) / float(across)
				var u1 := -1.0 + 2.0 * float(c + 1) / float(across)
				var p00: Vector3 = point.call(t0, u0, base)
				var p10: Vector3 = point.call(t1, u0, base)
				var p11: Vector3 = point.call(t1, u1, base)
				var p01: Vector3 = point.call(t0, u1, base)
				# Brighter along the crest of the spoke, darker at its edges: that gradient is
				# what gives a spoke its roundness without a normal map.
				var lit := 1.0 - 0.14 * absf((u0 + u1) * 0.5)
				_wqf(st, p00, p10, p11, p01, Vector3.RIGHT, lit, WheelSlot.FACE)
			# Flanks, which is where the dish's shadow lives, and a back so the spoke is solid
			# when you look at the wheel from an angle.
			for side: float in [-1.0, 1.0]:
				var f0: Vector3 = point.call(t0, side, base)
				var f1: Vector3 = point.call(t1, side, base)
				var b0 := f0 - Vector3(s0.w, 0.0, 0.0)
				var b1 := f1 - Vector3(s1.w, 0.0, 0.0)
				# The flank looks sideways round the wheel, which is the radial direction
				# turned a quarter turn about the axle.
				var out := Vector3(0.0, f0.y, f0.z).cross(Vector3.RIGHT).normalized() * side
				_wqf(st, f0, f1, b1, b0, out, 0.56, WheelSlot.FACE)
			if detail:
				var g0: Vector3 = point.call(t0, -1.0, base) - Vector3(s0.w, 0.0, 0.0)
				var g1: Vector3 = point.call(t1, -1.0, base) - Vector3(s1.w, 0.0, 0.0)
				var h0: Vector3 = point.call(t0, 1.0, base) - Vector3(s0.w, 0.0, 0.0)
				var h1: Vector3 = point.call(t1, 1.0, base) - Vector3(s1.w, 0.0, 0.0)
				_wqf(st, g0, g1, h1, h0, Vector3.LEFT, 0.34, WheelSlot.DARK)
	var seg := 36 if detail else 12
	# The hub disc the spokes grow out of. Without it there is an open annulus between where the
	# centre cap ends and where the spokes begin, and you look straight through the middle of
	# the wheel and out the far side of the car.
	_wheel_revolve(st, [
		[x_hub + hw * 0.02, 0.0, WheelSlot.FACE, 0.86],
		[x_hub - hw * 0.01, hub_r * 1.08, WheelSlot.FACE, 0.78],
		[x_hub - hw * 0.18, hub_r * 1.08, WheelSlot.FACE, 0.52],
	], seg)
	# A concentric band laid over the spokes turns a spoke set into a mesh wheel.
	if float(face.ring) > 0.0:
		var rr := rim_r * float(face.ring)
		var t_ring := clampf((rr - hub_r) / maxf(rim_r * 1.02 - hub_r, 0.001), 0.0, 1.0)
		var s: Vector4 = at.call(t_ring)
		var xr := s.x + hw * 0.035
		var w := rim_r * 0.055
		_wheel_revolve(st, [
			[xr, rr - w, WheelSlot.FACE, 0.88], [xr, rr + w, WheelSlot.FACE, 0.94],
			[xr - hw * 0.10, rr + w, WheelSlot.FACE, 0.70],
			[xr - hw * 0.10, rr - w, WheelSlot.FACE, 0.60],
			[xr, rr - w, WheelSlot.FACE, 0.88],
		], seg)
	# A dust shield closing the back of the wheel. Without it you look straight through the ring
	# between the brake disc and the barrel and out the other side of the wheel arch, which on a
	# car is bodywork in body colour - a red car with a red hole in the middle of its wheel.
	# It is built at BOTH levels: the far mesh covers 30 m to 85 m, which is where most of the
	# cars you ever see are, and an open annulus there is the same hole at a smaller size.
	# It sits well INBOARD of the brake disc (which ends at -thick, about -0.10 half-widths) on
	# purpose: when the two were a couple of hundredths apart the disc had a black wall directly
	# behind it and the whole cavity read as one dark mass with no disc in it.
	_wheel_revolve(st, [
		[-hw * 0.52, rim_r * 0.20, WheelSlot.DARK, 0.34],
		[-hw * 0.52, rim_r * 0.99, WheelSlot.DARK, 0.26],
	], seg)
	# Centre cap: a shallow dome standing proud of the hub, with a skirt down to the face.
	var cap_r := hub_r * 0.72
	var cap_x := x_hub + hw * 0.16
	var dome: Array = []
	var rings := 5 if detail else 2
	for i in rings + 1:
		var t := float(i) / float(rings)
		dome.append([cap_x - hw * 0.20 * t * t, cap_r * t, WheelSlot.CAP, 1.0 - 0.10 * t])
	dome.append([x_hub, cap_r, WheelSlot.CAP, 0.66])
	_wheel_revolve(st, dome, seg)
	if not detail:
		return
	# Lug nuts on a bolt circle. Five small hexagonal bosses, and they read from further away
	# than anything else this size because everyone knows how many a wheel has.
	var lug_t := clampf((hub_r * 1.30 - hub_r) / maxf(rim_r * 1.02 - hub_r, 0.001), 0.06, 0.4)
	var ls: Vector4 = at.call(lug_t)
	for i in 5:
		var a := TAU * (float(i) + 0.5) / 5.0
		var c := _wp(ls.x + hw * 0.05, hub_r * 1.34, a)
		_box_wheel(st, c, Vector3(hw * 0.11, rim_r * 0.075, rim_r * 0.075), a, 0.80, WheelSlot.CAP)


## NOTE: the glTF importer also builds a positions-only SHADOW MESH for every car, and
## rebuilding the mesh through ImporterMesh throws it away, so a tucked body pays a little more
## in the shadow pass than an untouched one. A hand-built replacement (an ArrayMesh with only
## ARRAY_VERTEX and ARRAY_INDEX, assigned to `shadow_mesh`) was tried and taken back out: with
## it, a city render on the Compatibility renderer segfaults inside the renderer at a downtown
## camera, with no GDScript frame in the backtrace, and without it the same camera renders. The
## engine expects a shadow mesh built by its own create_shadow_mesh(), which is not exposed to
## GDScript. Do not put it back without a city render to prove it.


## Tucks the wheels baked into a car body model away inside the generated wheel that is drawn
## over them, and hands back one mesh with the same surfaces and the same draw-call count.
##
## The body models carry their wheels baked into the bodywork - on the four Meshy cars as part
## of the single painted surface, so they come out in body colour, which is why a red car had
## red wheels. A generated wheel cannot simply be laid over one of those: a dished rim's face
## sits further INBOARD than the modelled wheel's face does, so the old wheel draws in front of
## the new spokes whatever size the new wheel is.
##
## The first version of this cut the modelled wheel out into a SECOND MeshInstance3D that drew
## only past the distance where the generated wheels stop. That is one extra draw call and one
## extra object on every model car in the city, for ever, and at eighty-five metres a wheel is
## seven pixels - so it bought nothing and was measurably the largest part of what the wheels
## cost (+153 draws at a street camera with 444 cars in the scene). Shrinking the triangles in
## place instead keeps them in the body's own surface: no extra draw, no extra object, the arch
## is still not an empty hole at distance, and up close the shrunken wheel is hidden behind the
## generated brake disc, which is a solid plate out to 0.76 of the rim radius.
##
## The vertices a wheel triangle uses are COPIED before they are moved. They are shared with the
## arch lip and the sill around them, and moving them in place would drag the bodywork in after
## the wheel.
##
## `to_body` maps the mesh's own space into Vehicle body space (where WHEEL_POSE lives) and
## `cuts` is a list of [hub: Vector3, radius, half_width_inboard, half_width_outboard]. A
## triangle is a wheel triangle if its centre lies inside one of those cylinders about the axle.
## The arch lip survives because an arch is cut to CLEAR the tyre and so is always a few
## centimetres outside the cut radius; the sills and the floor survive because they are most of
## a wheelbase away from the hub in z, and because the narrow cylinder that reaches out past the
## tyre's own section to catch the modelled hub cap reaches OUTBOARD only - reaching inboard as
## well is what ate a piece of the pickup's step panel.
##
## `radial` and `axial` scale what is left about the hub and `inset` moves it inboard, in metres.
## The mesh is rebuilt through ImporterMesh with generate_lods(25, 60) - the same numbers the
## glTF importer itself uses, so the LOD chain is equivalent to the one it replaces - and the
## shadow mesh is rebuilt too, because that is NOT automatic and losing it doubles what every
## car costs in the shadow pass.
static func tuck_body_wheels(mesh: Mesh, key: String, to_body: Transform3D, cuts: Array,
		radial: float, axial: float, inset: float) -> Mesh:
	if _cache.has(key):
		return _cache[key]
	var im := ImporterMesh.new()
	var touched := false
	for s in mesh.get_surface_count():
		var arrays := mesh.surface_get_arrays(s)
		var verts: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
		var idx: PackedInt32Array = arrays[Mesh.ARRAY_INDEX]
		var mat := mesh.surface_get_material(s)
		var sname := "s%d" % s
		if mat != null and String(mat.resource_name) != "":
			sname = String(mat.resource_name)
		if idx.is_empty() or verts.is_empty():
			im.add_surface(Mesh.PRIMITIVE_TRIANGLES, arrays, [], {}, mat, sname)
			continue
		var from_body := to_body.affine_inverse()
		var pos := PackedVector3Array()
		pos.resize(verts.size())
		for i in verts.size():
			pos[i] = to_body * verts[i]
		# Which cut (if any) owns each triangle, and through it each of its vertices. Both are
		# needed: the vertex map says which hub a copy is pulled into, and the TRIANGLE map says
		# which triangles may use the copies. Remapping every index that points at an owned
		# vertex instead would drag the arch lip and the sill in after the wheel, which is the
		# whole reason the vertices are copied rather than moved.
		var owner := PackedInt32Array()
		owner.resize(verts.size())
		owner.fill(-1)
		var tri := PackedInt32Array()
		tri.resize(idx.size() / 3)
		tri.fill(-1)
		var hit := false
		for t in idx.size() / 3:
			var a := idx[t * 3]
			var b := idx[t * 3 + 1]
			var c := idx[t * 3 + 2]
			var mid := (pos[a] + pos[b] + pos[c]) / 3.0
			for ci in cuts.size():
				var cut: Array = cuts[ci]
				var hub: Vector3 = cut[0]
				# Outboard is away from the car's centreline, which is the direction the hub
				# itself lies in.
				var dx := (mid.x - hub.x) * signf(hub.x if absf(hub.x) > 0.001 else 1.0)
				if dx > float(cut[3]) or dx < -float(cut[2]):
					continue
				if Vector2(mid.y - hub.y, mid.z - hub.z).length() >= float(cut[1]):
					continue
				owner[a] = ci
				owner[b] = ci
				owner[c] = ci
				tri[t] = ci
				hit = true
				break
		if not hit:
			im.add_surface(Mesh.PRIMITIVE_TRIANGLES, arrays, [], {}, mat, sname)
			continue
		touched = true
		# One copy per wheel vertex, appended past the end, moved into the hub. Every other
		# array is copied straight across so the new vertices keep their normals and UVs.
		var remap := PackedInt32Array()
		remap.resize(verts.size())
		remap.fill(-1)
		var extra: Array[int] = []
		for i in verts.size():
			if owner[i] >= 0:
				remap[i] = verts.size() + extra.size()
				extra.append(i)
		var out := arrays.duplicate()
		var nv := verts.duplicate()
		for src in extra:
			var cut: Array = cuts[owner[src]]
			var hub: Vector3 = cut[0]
			var side := signf(hub.x if absf(hub.x) > 0.001 else 1.0)
			var p := pos[src]
			var q := Vector3(
					hub.x + (p.x - hub.x) * axial - side * inset,
					hub.y + (p.y - hub.y) * radial,
					hub.z + (p.z - hub.z) * radial)
			nv.append(from_body * q)
		out[Mesh.ARRAY_VERTEX] = nv
		for aid in [Mesh.ARRAY_NORMAL, Mesh.ARRAY_TANGENT, Mesh.ARRAY_COLOR, Mesh.ARRAY_TEX_UV,
				Mesh.ARRAY_TEX_UV2, Mesh.ARRAY_BONES, Mesh.ARRAY_WEIGHTS]:
			out[aid] = _append_rows(arrays[aid], extra)
		var ni := idx.duplicate()
		for t in tri.size():
			if tri[t] < 0:
				continue
			for k in 3:
				ni[t * 3 + k] = remap[ni[t * 3 + k]]
		out[Mesh.ARRAY_INDEX] = ni
		if OS.get_environment("TUCK_DEBUG") != "":
			print("TUCK %s surf %d: %d/%d triangles tucked, %d vertices copied" % [
					key, s, extra.size(), idx.size() / 3, extra.size()])
		im.add_surface(Mesh.PRIMITIVE_TRIANGLES, out, [], {}, mat, sname)
	var result: Mesh = mesh
	if OS.get_environment("TUCK_DEBUG") != "" and not touched:
		print("TUCK %s: NOTHING MATCHED (%d surfaces)" % [key, mesh.get_surface_count()])
	if touched and im.get_surface_count() > 0:
		im.generate_lods(25.0, 60.0, [])
		var am := im.get_mesh()
		if am != null:
			result = am
	_cache[key] = result
	return result


## Copies a vertex-attribute array and appends the rows named in `rows` to the end of it, so a
## duplicated vertex carries the same normal, tangent, colour and UVs as the one it came from.
## Tangents and bone/weight arrays are four entries per vertex, everything else one.
static func _append_rows(src: Variant, rows: Array[int]) -> Variant:
	if src == null:
		return null
	if src is PackedVector3Array:
		var a: PackedVector3Array = (src as PackedVector3Array).duplicate()
		for i in rows:
			a.append(a[i])
		return a
	if src is PackedVector2Array:
		var b: PackedVector2Array = (src as PackedVector2Array).duplicate()
		for i in rows:
			b.append(b[i])
		return b
	if src is PackedColorArray:
		var c: PackedColorArray = (src as PackedColorArray).duplicate()
		for i in rows:
			c.append(c[i])
		return c
	if src is PackedFloat32Array:
		var d: PackedFloat32Array = (src as PackedFloat32Array).duplicate()
		var stride := 4
		for i in rows:
			for k in stride:
				d.append(d[i * stride + k])
		return d
	if src is PackedInt32Array:
		var e: PackedInt32Array = (src as PackedInt32Array).duplicate()
		var stride2 := 4
		for i in rows:
			for k in stride2:
				e.append(e[i * stride2 + k])
		return e
	return src


