extends SceneTree
## Palm crowns in motion (palm-shimmer): a street lined with the six palm variants on both
## kerbs out to 300 m, built through MultiMeshBatch like a city chunk (the palm ladder's LOD bias
## and the shadow twin included), lit like the street at noon, golden hour or a rainy day, and a
## frame strip of a slow pan saved for tools/specular_aliasing/strip.py's measure / compare.
## Seconds a strip on opengl3, a few minutes on lavapipe Forward+.
##
##   OUT=build/palm/a xvfb-run -a -s "-screen 0 1280x720x24" godot --rendering-driver opengl3 \
##     --audio-driver Dummy --path . --script tools/palm_shimmer/palm_strip.gd --resolution 1280x720
##   python3 tools/specular_aliasing/strip.py measure build/palm/a
##   (Forward+: --rendering-driver vulkan with VK_ICD_FILENAMES=/usr/share/vulkan/icd.d/lvp_icd.json)
##
## Env: OUT (a directory: f.png, f_1.png, ... and ss.txt), VIEW=street | mid | up | far (where
## the camera stands), LIGHT=noon | golden | rain, FRAMES=n strip length (default 10),
## STEP=yaw degrees a frame (default 0.02), SS=1|4 jittered renders a frame (4: what TAA
## integrates; strip.py averages them), WARM=n frames before the first (default 12), TAA=1 the
## root viewport's TAA (Forward+), WIND=n, and any A/B switch (PALM_SHIMMER=0, SPECULAR_AA=0 ...).
## TIME is held (time_rollover_secs) so only the camera moves.

const VIEWS := {
	# [eye, look-at, fov]
	"street": [Vector3(1.5, 1.7, 0.0), Vector3(-1.0, 7.5, -60.0), 60.0],
	"mid": [Vector3(0.0, 1.7, 40.0), Vector3(0.0, 10.0, -60.0), 40.0],
	"up": [Vector3(5.0, 1.6, -26.0), Vector3(7.5, 13.0, -38.0), 62.0],
	"far": [Vector3(0.0, 2.0, 120.0), Vector3(0.0, 9.0, -80.0), 28.0],
}
const SS_GRID := {1: [Vector2.ZERO], 4: [Vector2(-0.125, -0.375), Vector2(0.375, -0.125), Vector2(0.125, 0.375), Vector2(-0.375, 0.125)]}


func _initialize() -> void:
	ProjectSettings.set_setting("rendering/limits/time/time_rollover_secs", 0.000001)
	seed(4242)
	var light := OS.get_environment("LIGHT") if OS.get_environment("LIGHT") != "" else "noon"
	var stage := Node3D.new()
	get_root().add_child(stage)
	if OS.get_environment("TAA") == "1":
		get_root().use_taa = true
	var env := WorldEnvironment.new()
	var e := Environment.new()
	var sky := Sky.new()
	var sm := ProceduralSkyMaterial.new()
	match light:
		"golden":
			sm.sky_top_color = Color(0.25, 0.36, 0.58)
			sm.sky_horizon_color = Color(0.95, 0.66, 0.42)
		"rain":
			sm.sky_top_color = Color(0.36, 0.38, 0.41)
			sm.sky_horizon_color = Color(0.55, 0.57, 0.59)
		_:
			sm.sky_top_color = Color(0.28, 0.45, 0.72)
			sm.sky_horizon_color = Color(0.72, 0.77, 0.82)
	sm.ground_horizon_color = Color(0.5, 0.48, 0.45)
	sm.ground_bottom_color = Color(0.2, 0.19, 0.18)
	sky.sky_material = sm
	e.sky = sky
	e.background_mode = Environment.BG_SKY
	e.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	e.ambient_light_energy = 0.55 if light != "rain" else 0.9
	e.tonemap_mode = Environment.TONE_MAPPER_AGX
	e.tonemap_exposure = 0.9
	env.environment = e
	stage.add_child(env)
	var wind := float(OS.get_environment("WIND")) if OS.get_environment("WIND") != "" else 1.0
	RenderingServer.global_shader_parameter_set("wind_factor", wind)
	RenderingServer.global_shader_parameter_set("road_wetness", 0.8 if light == "rain" else 0.0)
	var sun := DirectionalLight3D.new()
	match light:
		"golden":
			sun.rotation_degrees = Vector3(-9.0, 165.0, 0.0)
			sun.light_color = Color(1.0, 0.72, 0.45)
			sun.light_energy = 1.6
		"rain":
			sun.rotation_degrees = Vector3(-60.0, 30.0, 0.0)
			sun.light_energy = 0.45
		_:
			sun.rotation_degrees = Vector3(-58.0, 25.0, 0.0)
			sun.light_energy = 1.5
	# The city's sun (city.tscn): four splits to 400 m, blended.
	sun.shadow_enabled = true
	sun.shadow_blur = 0.9
	sun.directional_shadow_mode = DirectionalLight3D.SHADOW_PARALLEL_4_SPLITS
	sun.directional_shadow_split_1 = 0.055
	sun.directional_shadow_split_2 = 0.16
	sun.directional_shadow_split_3 = 0.42
	sun.directional_shadow_blend_splits = true
	sun.directional_shadow_max_distance = 400.0
	if light == "rain":
		sun.shadow_opacity = 0.35
	stage.add_child(sun)
	RenderingServer.global_shader_parameter_set("sun_direction", sun.transform.basis.z)
	RenderingServer.global_shader_parameter_set("sky_tint", sm.sky_horizon_color)
	RenderingServer.global_shader_parameter_set("tree_sun", Vector3(1.0, 0.95, 0.88) * sun.light_energy)
	# Road and pavements down -Z.
	_box(stage, Vector3(14.0, 0.02, 700.0), Vector3(0.0, -0.01, -200.0), _mat(Color(0.12, 0.12, 0.125), 0.85))
	for s: float in [-1.0, 1.0]:
		_box(stage, Vector3(6.0, 0.15, 700.0), Vector3(s * 10.0, 0.075, -200.0), _mat(Color(0.52, 0.5, 0.47), 0.9))
		_box(stage, Vector3(2.0, 14.0, 700.0), Vector3(s * 19.0, 7.0, -200.0), _mat(Color(0.62, 0.56, 0.5), 0.92))
	var pf: GDScript = load("res://scripts/world/prop_factory.gd")
	var mb: GDScript = load("res://scripts/util/multimesh_batch.gd")
	var batch: RefCounted = mb.new()
	var k := 0
	for z in range(60, -320, -12):
		for s: float in [-1.0, 1.0]:
			var v := (k * 5 + (3 if s > 0.0 else 0)) % 6
			var lean: float = pf.call("palm_lean", v)
			# Lean toward the road, as CityChunk turns them.
			var yaw := -lean + (PI * 0.5 if s < 0.0 else -PI * 0.5)
			var sc := 0.85 + 0.3 * fposmod(float(k) * 0.618, 1.0)
			var xf := Transform3D(Basis(Vector3.UP, yaw).scaled(Vector3(sc, sc, sc)), Vector3(s * 8.4, 0.15, float(z)))
			batch.call("add", "palm_%d" % v, pf.call("palm", v), xf)
			k += 1
	batch.call("build", stage)
	var view := OS.get_environment("VIEW") if OS.get_environment("VIEW") != "" else "street"
	var d: Array = VIEWS[view]
	var cam := Camera3D.new()
	cam.far = 1500.0
	cam.fov = d[2]
	stage.add_child(cam)
	cam.look_at_from_position(d[0], d[1], Vector3.UP)
	cam.make_current()
	var base := cam.transform
	var out := OS.get_environment("OUT") if OS.get_environment("OUT") != "" else "build/palm_strip"
	DirAccess.make_dir_recursive_absolute(out)
	var frames := int(OS.get_environment("FRAMES")) if OS.get_environment("FRAMES") != "" else 10
	var step := float(OS.get_environment("STEP")) if OS.get_environment("STEP") != "" else 0.02
	var ss := int(OS.get_environment("SS")) if OS.get_environment("SS") != "" else 1
	var warm := int(OS.get_environment("WARM")) if OS.get_environment("WARM") != "" else 12
	var hold := int(OS.get_environment("HOLD")) if OS.get_environment("HOLD") != "" else 2
	var fa := FileAccess.open(out + "/ss.txt", FileAccess.WRITE)
	fa.store_string(str(ss))
	fa.close()
	var res_h := float(get_root().get_visible_rect().size.y)
	var px := deg_to_rad(cam.fov) / res_h
	var n := 0
	for f in frames:
		for j: Vector2 in SS_GRID[ss]:
			var yaw := deg_to_rad(step * float(f)) - j.x * px
			cam.transform = base * Transform3D(Basis(Vector3.UP, yaw) * Basis(Vector3.RIGHT, -j.y * px), Vector3.ZERO)
			for i in (warm if n == 0 else hold):
				await process_frame
			var img := get_root().get_texture().get_image()
			img.save_png("%s/%s.png" % [out, "f" if n == 0 else "f_%d" % n])
			n += 1
	print("SAVED %d frames to %s" % [n, out])
	quit()


func _mat(c: Color, rough: float) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = c
	m.roughness = rough
	return m


func _box(stage: Node3D, size: Vector3, at: Vector3, mat: Material) -> void:
	var mi := MeshInstance3D.new()
	var b := BoxMesh.new()
	b.size = size
	mi.mesh = b
	mi.position = at
	mi.material_override = mat
	stage.add_child(mi)
