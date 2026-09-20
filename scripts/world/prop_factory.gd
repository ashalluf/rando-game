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
static func pbr(set_key: String, scale_m: float = 4.0, tint: Color = Color.WHITE, roughness_scale: float = 1.0) -> StandardMaterial3D:
	var key := "pbr_%s_%.2f_%d_%.2f" % [set_key, scale_m, tint.to_rgba32(), roughness_scale]
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
	mat.uv1_triplanar = true
	mat.uv1_world_triplanar = true
	mat.uv1_scale = Vector3.ONE / scale_m
	mat.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS_ANISOTROPIC
	_cache[key] = mat
	return mat


## Worn asphalt for road surfaces (see shaders/road.gdshader). Cached per set, scale, tint and
## seed, so every road in a chunk shares one material.
static func road(set_key: String, scale_m: float, tint: Color, seed_value: int, joints: float = 0.0, wear: float = 1.0) -> ShaderMaterial:
	var key := "road_%s_%.2f_%d_%d_%.2f_%.2f" % [set_key, scale_m, tint.to_rgba32(), seed_value, joints, wear]
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


static func cylinder(key: String, radius: float, height: float, color: Color, top_radius: float = -1.0, segments: int = 8) -> Mesh:
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
	return cylinder("trunk", 0.18, 2.2, Color(0.42, 0.30, 0.18), 0.14, 6)


static func canopy_round() -> Mesh:
	if _cache.has("canopy_round"):
		return _cache["canopy_round"]
	var mesh := SphereMesh.new()
	mesh.radius = 1.6
	mesh.height = 3.2
	mesh.radial_segments = 8
	mesh.rings = 5
	mesh.material = material(Color(0.32, 0.58, 0.28))
	_cache["canopy_round"] = mesh
	return mesh


static func canopy_cone() -> Mesh:
	return cylinder("canopy_cone", 1.5, 4.0, Color(0.20, 0.45, 0.24), 0.0, 7)


static func lamp_pole() -> Mesh:
	return cylinder("lamp_pole", 0.09, 6.0, Color(0.28, 0.29, 0.32), 0.07, 6)


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
const GRASS_BLADES := 5
const GRASS_SEGMENTS := 3
const GRASS_HEIGHT := 0.34
const GRASS_WIDTH := 0.016


static func grass_blade() -> Mesh:
	if _cache.has("grass_blade"):
		return _cache["grass_blade"]
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var rng := RandomNumberGenerator.new()
	rng.seed = 90210
	for b in GRASS_BLADES:
		var yaw := TAU * (float(b) / GRASS_BLADES) + rng.randf_range(-0.35, 0.35)
		var dir := Vector3(sin(yaw), 0.0, cos(yaw))
		var side := Vector3(dir.z, 0.0, -dir.x)
		var height := GRASS_HEIGHT * rng.randf_range(0.45, 1.3)
		var width := GRASS_WIDTH * rng.randf_range(0.8, 1.2)
		# How far the tip leans away from vertical, and where the blade starts.
		var lean := rng.randf_range(0.28, 0.72) * height
		var root := dir * rng.randf_range(0.0, 0.05)
		for seg in GRASS_SEGMENTS:
			var t0 := float(seg) / GRASS_SEGMENTS
			var t1 := float(seg + 1) / GRASS_SEGMENTS
			# Quadratic bend: the blade is upright at the root and arcs over near the tip.
			var p0 := root + Vector3(0.0, height * t0, 0.0) + dir * (lean * t0 * t0)
			var p1 := root + Vector3(0.0, height * t1, 0.0) + dir * (lean * t1 * t1)
			var w0 := width * (1.0 - t0 * 0.85)
			var w1 := width * (1.0 - t1 * 0.85)
			# Face normal, then bent toward up so the tuft lights as one soft surface.
			var along := (p1 - p0).normalized()
			var face := side.cross(along).normalized()
			var n := face.lerp(Vector3.UP, 0.65).normalized()
			var a := p0 - side * w0
			var b2 := p0 + side * w0
			var c := p1 + side * w1
			var d := p1 - side * w1
			for v: Array in [[a, 0.0, t0], [b2, 1.0, t0], [c, 1.0, t1], [a, 0.0, t0], [c, 1.0, t1], [d, 0.0, t1]]:
				st.set_normal(n)
				st.set_uv(Vector2(v[1], v[2]))
				st.add_vertex(v[0])
	var mesh := st.commit()
	var mat := ShaderMaterial.new()
	mat.shader = load("res://shaders/grass.gdshader")
	mesh.surface_set_material(0, mat)
	_cache["grass_blade"] = mesh
	return mesh


static func bush() -> Mesh:
	if _cache.has("bush"):
		return _cache["bush"]
	var mesh := SphereMesh.new()
	mesh.radius = 0.9
	mesh.height = 1.4
	mesh.radial_segments = 7
	mesh.rings = 4
	mesh.material = material(Color(0.30, 0.52, 0.26))
	_cache["bush"] = mesh
	return mesh


static func bench() -> Mesh:
	return box("bench", Vector3(1.8, 0.1, 0.5), Color(0.5, 0.36, 0.22))


static func bench_legs() -> Mesh:
	return box("bench_legs", Vector3(1.6, 0.45, 0.4), Color(0.25, 0.25, 0.27))


static func hydrant() -> Mesh:
	return cylinder("hydrant", 0.16, 0.8, Color(0.85, 0.15, 0.12), 0.12, 6)


## Center-line piece; white so the instance color picks yellow or white.
static func dash() -> Mesh:
	return box("dash", Vector3(0.16, 0.02, 3.0), Color(1.0, 1.0, 1.0))


static func stripe() -> Mesh:
	return box("stripe", Vector3(0.6, 0.02, 3.0), Color(0.95, 0.95, 0.92))


static func sign_pole() -> Mesh:
	return cylinder("sign_pole", 0.05, 2.6, Color(0.5, 0.5, 0.52), -1.0, 6)


static func stop_sign() -> Mesh:
	return cylinder("stop_sign", 0.45, 0.05, Color(0.8, 0.12, 0.1), -1.0, 8)


static func signal_pole() -> Mesh:
	return cylinder("signal_pole", 0.12, 6.5, Color(0.2, 0.2, 0.22), 0.1, 6)


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
	mesh.radial_segments = 6
	mesh.rings = 3
	mesh.material = material(color, 0.5, true)
	_cache[key] = mesh
	return mesh


static func trash_can_mesh() -> Mesh:
	return cylinder("trash_can", 0.35, 1.0, Color(0.25, 0.35, 0.3), -1.0, 8)


## A whole palm tree as one mesh: a curved tapering trunk with a ridged bark profile, a crown of
## drooping fronds built from real leaflets, a skirt of dead fronds and a few coconuts. Three
## seeded variants. Owner, 2026-09-20: "it's Cali, put palm trees" - the old palm was a cylinder
## with three flat boxes stuck on top, which is the least convincing thing in the game.
##
## It is one mesh with vertex colours rather than several, so a street of palms is one MultiMesh
## draw. Frond leaflets are single-sided quads, so the material disables backface culling.
## Six, not three: a promenade lined with palms at even spacing shows the repeat immediately,
## and each variant is one cached mesh of about 1.9k triangles.
const PALM_VARIANTS := 6


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
	var lean_dir := Vector3(cos(rng.randf() * TAU), 0.0, sin(rng.randf() * TAU))
	var lean := rng.randf_range(0.4, 1.5)
	# Enough rings and sides to carry the diamond pattern below without reading as a checkerboard.
	var segments := 22
	var sides := 10
	# Grey-tan, not chocolate: a Washingtonia trunk is the colour of dry rope.
	var bark := Color(0.46, 0.41, 0.33)

	var centre := func(t: float) -> Vector3:
		return Vector3(0.0, height * t, 0.0) + lean_dir * (lean * t * t)

	for i in segments:
		var t0 := float(i) / segments
		var t1 := float(i + 1) / segments
		var c0: Vector3 = centre.call(t0)
		var c1: Vector3 = centre.call(t1)
		# Taper toward the crown, with a slight swell at the base and a ring ridge per segment.
		var r0 := lerpf(0.30, 0.13, t0) * (1.0 + 0.30 * exp(-t0 * 9.0)) * (1.0 + (0.045 if i % 2 == 0 else -0.045))
		var r1 := lerpf(0.30, 0.13, t1) * (1.0 + 0.30 * exp(-t1 * 9.0)) * (1.0 + (0.045 if (i + 1) % 2 == 0 else -0.045))
		var shade0 := bark * (0.90 + 0.16 * float(i % 3) / 2.0)
		for k in sides:
			var a0 := TAU * k / sides
			var a1 := TAU * (k + 1) / sides
			var d0 := Vector3(cos(a0), 0.0, sin(a0))
			var d1 := Vector3(cos(a1), 0.0, sin(a1))
			# The criss-cross of old frond bases. A palm trunk is not a smooth pole: it is a
			# lattice of cut stubs in a diamond lattice, and at street level that pattern is
			# the thing that tells you which tree you are standing under.
			var lattice := 1.0 if (i + k) % 2 == 0 else 0.76
			# The pattern wears away toward the base, where the trunk has gone smooth and grey.
			lattice = lerpf(1.0, lattice, smoothstep(0.08, 0.35, t0))
			_quad(st, c0 + d0 * r0, c0 + d1 * r0, c1 + d1 * r1, c1 + d0 * r1, shade0 * lattice, d0, d1)

	var top: Vector3 = centre.call(1.0)
	var fronds := rng.randi_range(11, 15)
	for f in fronds:
		var yaw := TAU * f / fronds + rng.randf_range(-0.16, 0.16)
		_palm_frond(st, top, yaw, rng.randf_range(3.6, 5.4), rng.randf_range(0.1, 0.8), rng, false)
	# A skirt of dead fronds hanging under the crown.
	for f in rng.randi_range(3, 6):
		var yaw := rng.randf_range(0.0, TAU)
		_palm_frond(st, top + Vector3(0.0, -0.25, 0.0), yaw, rng.randf_range(2.0, 3.0), -1.25, rng, true)
	# Coconuts clustered under the crown.
	for c in rng.randi_range(3, 6):
		var a := rng.randf_range(0.0, TAU)
		var at := top + Vector3(cos(a), 0.0, sin(a)) * rng.randf_range(0.15, 0.45) + Vector3(0.0, -0.35, 0.0)
		_ico(st, at, rng.randf_range(0.14, 0.2), Color(0.40, 0.30, 0.17))

	# No generate_normals() here. Flat per-triangle normals are what made the crown read as a
	# folded paper fan: every leaflet caught the light at its own angle, so the canopy was a
	# mess of bright and black shards. Every part sets its own smooth normal instead, the same
	# trick the grass blades use.
	var mesh := st.commit()
	var mat := StandardMaterial3D.new()
	mat.vertex_color_use_as_albedo = true
	mat.roughness = 0.82
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	mesh.surface_set_material(0, mat)
	_cache[key] = mesh
	return mesh


## One frond: a rachis arcing out and drooping, with a leaflet on each side at every step.
## `rise` lifts the frond before it droops; dead fronds hang almost straight down and go brown.
static func _palm_frond(st: SurfaceTool, base: Vector3, yaw: float, reach: float, rise: float, rng: RandomNumberGenerator, dead: bool) -> void:
	var out := Vector3(cos(yaw), 0.0, sin(yaw))
	var side := Vector3(-out.z, 0.0, out.x)
	# Twice as many, half as wide. A real frond carries dozens of narrow segments; at 14 steps
	# each leaflet was a hand-sized triangle and the frond read as a saw blade.
	var steps := 26
	var droop := reach * (1.5 if dead else 0.9)
	# Palm fronds are a dusty, yellow-grey green, not the vivid green of a lawn, and the tone
	# runs from dark near the rachis to bleached at the tips.
	var green := Color(0.19, 0.30, 0.13).lerp(Color(0.41, 0.49, 0.22), rng.randf())
	var colour := Color(0.46, 0.37, 0.20) if dead else green
	var rachis := func(t: float) -> Vector3:
		return base + out * (reach * t) + Vector3(0.0, rise * t - droop * t * t, 0.0)
	for i in steps:
		var t0 := float(i) / steps
		var t1 := float(i + 1) / steps
		var p0: Vector3 = rachis.call(t0)
		var p1: Vector3 = rachis.call(t1)
		# Each leaflet is its own pointed blade sweeping back and down off the rib, so the frond
		# reads as feathered with daylight between the leaves. A continuous strip along both
		# sides just makes a solid green fan, which is what the first attempt looked like.
		var span := (sin(t0 * PI) * reach * 0.30 + 0.05) * rng.randf_range(0.72, 1.22)
		# Outer leaflets hang further, the way a Washingtonia's do.
		var hang := span * (0.48 + 0.75 * t0)
		var tone := colour * (0.74 + 0.46 * t0) * rng.randf_range(0.92, 1.08)
		for dir: float in [1.0, -1.0]:
			var tip := p0 + side * (span * dir) - out * (span * 0.34) + Vector3(0.0, -hang, 0.0)
			# One smooth normal for the whole leaflet, leaning up and a little outward, so the
			# crown lights as one soft mass instead of a pile of lit facets.
			var nrm := (Vector3.UP * 1.6 + out * 0.5 + side * (dir * 0.35)).normalized()
			for v: Vector3 in [p0, p1, tip]:
				st.set_color(tone if v != tip else tone * 0.86)
				st.set_uv(Vector2.ZERO)
				st.set_normal(nrm)
				st.add_vertex(v)
		# The rib itself, so the frond still reads when seen edge-on.
		var rib_n := (Vector3.UP + out * 0.3).normalized()
		_quad(st, p0, p1, p1 + Vector3(0.0, -0.045, 0.0), p0 + Vector3(0.0, -0.045, 0.0), colour * 0.58, rib_n, rib_n)


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


## A cheap faceted blob (coconuts, fruit): an octahedron.
static func _ico(st: SurfaceTool, at: Vector3, r: float, colour: Color) -> void:
	var px := at + Vector3(r, 0, 0)
	var nx := at + Vector3(-r, 0, 0)
	var py := at + Vector3(0, r, 0)
	var ny := at + Vector3(0, -r, 0)
	var pz := at + Vector3(0, 0, r)
	var nz := at + Vector3(0, 0, -r)
	for tri: Array in [[py, px, pz], [py, pz, nx], [py, nx, nz], [py, nz, px],
			[ny, pz, px], [ny, nx, pz], [ny, nz, nx], [ny, px, nz]]:
		for v: Vector3 in tri:
			st.set_color(colour)
			st.set_uv(Vector2.ZERO)
			st.set_normal((v - at).normalized())
			st.add_vertex(v)


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
	# Top rail and a kick rail.
	_box_into(st, Vector3(0.0, 0.98, 0.98), Vector3(1.02, 0.045, 0.05), metal)
	_box_into(st, Vector3(0.0, 0.30, 0.98), Vector3(1.0, 0.025, 0.03), metal)
	# Returns along the sides.
	for sx: float in [-0.5, 0.5]:
		_box_into(st, Vector3(sx, 0.98, 0.5), Vector3(0.04, 0.045, 1.0), metal)
		_box_into(st, Vector3(sx, 0.55, 0.5), Vector3(0.03, 0.9, 0.03), metal)
	# Uprights across the front.
	for i in 9:
		var x := -0.46 + float(i) * 0.115
		_box_into(st, Vector3(x, 0.55, 0.98), Vector3(0.014, 0.9, 0.022), metal)
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
	var slats := 11
	for i in slats:
		var z := lerpf(0.06, 0.94, float(i) / float(slats - 1))
		_box_into(st, Vector3(0.0, 0.0, z), Vector3(1.0, 0.035, 0.045), iron)
	# Two cross bearers under the grating.
	for bz: float in [0.18, 0.82]:
		_box_into(st, Vector3(0.0, -0.04, bz), Vector3(1.0, 0.05, 0.05), iron)
	# Railing: top rail, mid rail, uprights, and the two end posts.
	_box_into(st, Vector3(0.0, 0.44, 0.98), Vector3(1.0, 0.035, 0.035), iron)
	_box_into(st, Vector3(0.0, 0.24, 0.98), Vector3(1.0, 0.025, 0.025), iron)
	for i in 8:
		var x := -0.44 + float(i) * 0.125
		_box_into(st, Vector3(x, 0.24, 0.98), Vector3(0.018, 0.44, 0.018), iron)
	for sx: float in [-0.49, 0.49]:
		# End posts are frames, not plates: uprights plus rails, so daylight passes through the
		# sides too.
		_box_into(st, Vector3(sx, 0.24, 0.06), Vector3(0.035, 0.46, 0.035), rust)
		_box_into(st, Vector3(sx, 0.24, 0.94), Vector3(0.035, 0.46, 0.035), rust)
		_box_into(st, Vector3(sx, 0.44, 0.5), Vector3(0.03, 0.03, 0.9), rust)
		_box_into(st, Vector3(sx, 0.24, 0.5), Vector3(0.022, 0.022, 0.9), rust)
	# Stair down to the floor below, sloped across the bay.
	var steps := 7
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


static func palm_trunk() -> Mesh:
	return cylinder("palm_trunk", 0.22, 7.0, Color(0.55, 0.42, 0.28), 0.14, 7)


static func palm_frond() -> Mesh:
	return box("palm_frond", Vector3(0.5, 0.06, 3.2), Color(0.30, 0.62, 0.30))


static func coconut() -> Mesh:
	if _cache.has("coconut"):
		return _cache["coconut"]
	var mesh := SphereMesh.new()
	mesh.radius = 0.5
	mesh.height = 1.0
	mesh.radial_segments = 6
	mesh.rings = 3
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
static func model_mesh(path: String, include: PackedStringArray = [], exclude: PackedStringArray = [], xform: Transform3D = Transform3D.IDENTITY, overrides: Dictionary = {}) -> Mesh:
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
			mesh = importer.get_mesh()
		root.free()
	else:
		push_warning("PropFactory: missing model " + path)
	_cache[key] = mesh
	return mesh


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


## A real tree (Poly Haven, reduced with tools/decimate_tree.py): 0 island tree, 1 second island
## tree, 2 small tree. About 5 m tall, base at the origin. Leaves use alpha scissor and take the
## instance color as a tint.
static func model_tree(variant: int) -> Mesh:
	var files: PackedStringArray = ["tree_a.glb", "tree_b.glb", "tree_c.glb"]
	var v := clampi(variant, 0, files.size() - 1)
	var mesh := model_mesh(MODEL_DIR + files[v])
	for i in mesh.get_surface_count():
		var mat := mesh.surface_get_material(i)
		if mat is StandardMaterial3D:
			var sm := mat as StandardMaterial3D
			if sm.transparency == BaseMaterial3D.TRANSPARENCY_ALPHA:
				sm.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA_SCISSOR
				sm.alpha_scissor_threshold = 0.45
				sm.vertex_color_use_as_albedo = true
			sm.cull_mode = BaseMaterial3D.CULL_DISABLED
	return mesh


## Enables alpha scissor (instead of blending) and instance-color tinting on a plant mesh.
static func _plant_material(mesh: Mesh) -> Mesh:
	for i in mesh.get_surface_count():
		var mat := mesh.surface_get_material(i)
		if mat is StandardMaterial3D:
			var sm := mat as StandardMaterial3D
			if sm.transparency == BaseMaterial3D.TRANSPARENCY_ALPHA:
				sm.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA_SCISSOR
				sm.alpha_scissor_threshold = 0.45
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
static func building_lod_material() -> ShaderMaterial:
	if _cache.has("building_lod_mat"):
		return _cache["building_lod_mat"]
	var mat := ShaderMaterial.new()
	mat.shader = load("res://shaders/building_lod.gdshader")
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
	return cylinder("upole", 0.16, 9.0, Color(0.36, 0.28, 0.2), 0.13, 8)


static func crossarm() -> Mesh:
	return box("crossarm", Vector3(2.0, 0.1, 0.1), Color(0.36, 0.28, 0.2))


## Unit cable along Z (scaled per instance).
static func cable() -> Mesh:
	return box("cable", Vector3(0.035, 0.035, 1.0), Color(0.08, 0.08, 0.09))


static func bike_rack() -> Mesh:
	if _cache.has("bike_rack"):
		return _cache["bike_rack"]
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	st.set_material(material(Color(0.3, 0.3, 0.32), 0.5))
	# An inverted U from three tubes.
	for part in [[Vector3(-0.4, 0.45, 0.0), Vector3(0.06, 0.9, 0.06)], [Vector3(0.4, 0.45, 0.0), Vector3(0.06, 0.9, 0.06)], [Vector3(0.0, 0.88, 0.0), Vector3(0.86, 0.06, 0.06)]]:
		var bm := BoxMesh.new()
		bm.size = part[1]
		st.append_from(bm, 0, Transform3D(Basis(), part[0]))
	var mesh := st.commit()
	_cache["bike_rack"] = mesh
	return mesh


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
	return cylinder("bollard", 0.12, 0.9, Color(0.25, 0.25, 0.27), 0.1, 10)


static func sign_post() -> Mesh:
	return cylinder("sign_post", 0.04, 2.8, Color(0.3, 0.3, 0.32), 0.04, 8)


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


## Rooftop air conditioning unit (Poly Haven exterior_aircon_unit), 0.8 x 0.93 x 0.4 m, bottom
## at the origin. Clean or rusted.
static func model_ac(rusted: bool) -> Mesh:
	if rusted:
		return model_mesh(MODEL_DIR + "prop_ac.glb", ["rusted"], [], _shift(Vector3(-0.5, 0.32, 0.0)))
	return model_mesh(MODEL_DIR + "prop_ac.glb", [], ["rusted"], _shift(Vector3(0.5, 0.32, 0.0)))
