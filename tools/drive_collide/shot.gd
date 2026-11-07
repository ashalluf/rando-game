extends "res://tools/drive_collide/probe.gd"
## Stills of the probe's scenes (opengl3 + Xvfb; the deck is a grey slab under a sun): a frame
## strip of one scenario from a fixed chase-ish camera, saved as OUT_<scenario>_<n>.png.
##   xvfb-run -a godot --rendering-driver opengl3 --path . res://tools/drive_collide/shot.tscn
## SCEN=offset|wall50 (one), OUT=build/drive_collide/after, TIMES=0.0,0.5,1.0,1.6 (s from the start),
## DRIVE_IMPACTS=0 the before.

var _cam: Camera3D
var _times: PackedFloat64Array = []
var _out := ""
var _label := ""


func _ready() -> void:
	_out = OS.get_environment("OUT") if OS.get_environment("OUT") != "" else "build/drive_collide/shot"
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("res://").path_join(_out.get_base_dir()))
	for t in (OS.get_environment("TIMES") if OS.get_environment("TIMES") != "" else "0.9,1.3,1.7,2.4").split(","):
		_times.append(float(t))
	var sun := DirectionalLight3D.new()
	sun.rotation = Vector3(deg_to_rad(-50), deg_to_rad(-30), 0)
	sun.shadow_enabled = true
	add_child(sun)
	var env := WorldEnvironment.new()
	env.environment = Environment.new()
	env.environment.background_mode = Environment.BG_COLOR
	env.environment.background_color = Color(0.55, 0.65, 0.8)
	env.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.environment.ambient_light_color = Color(0.6, 0.62, 0.66)
	env.environment.ambient_light_energy = 0.6
	add_child(env)
	_cam = Camera3D.new()
	_cam.fov = 55.0
	add_child(_cam)
	_cam.current = true
	_deck = _static_box(Vector3(800, 1, 800), Vector3(0, -0.5, 0))
	var deck_mesh := MeshInstance3D.new()
	var pm := PlaneMesh.new()
	pm.size = Vector2(400, 400)
	deck_mesh.mesh = pm
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.32, 0.32, 0.33)
	deck_mesh.material_override = mat
	add_child(deck_mesh)
	await get_tree().physics_frame
	_label = OS.get_environment("SCEN") if OS.get_environment("SCEN") != "" else "offset"
	await call("_s_" + _label)
	get_tree().quit()


func _static_box(size: Vector3, at: Vector3, yaw: float = 0.0) -> StaticBody3D:
	var b := super._static_box(size, at, yaw)
	if size.x < 400.0:
		var mi := MeshInstance3D.new()
		var bm := BoxMesh.new()
		bm.size = size
		mi.mesh = bm
		var mat := StandardMaterial3D.new()
		mat.albedo_color = Color(0.72, 0.7, 0.66)
		mi.material_override = mat
		b.add_child(mi)
	return b


## The probe's run, saving a frame at each of TIMES (game seconds from the start).
func _run(car: Vehicle, seconds: float) -> Dictionary:
	_cam.global_position = car.global_position + Vector3(8.0, 4.5, -6.0)
	_cam.look_at(car.global_position + Vector3(-1.0, 0, -22.0))
	var t := 0.0
	var k := 0
	var minv := INF
	while t < seconds:
		if k < _times.size() and t >= _times[k]:
			await RenderingServer.frame_post_draw
			var img := get_viewport().get_texture().get_image()
			img.save_png(ProjectSettings.globalize_path("res://").path_join("%s_%s_%d.png" % [_out, _label, k]))
			k += 1
		await get_tree().physics_frame
		t += 1.0 / Engine.physics_ticks_per_second
		var v := car.linear_velocity
		minv = minf(minv, Vector3(v.x, 0, v.z).length())
	return {"min": minv, "end": Vector3(car.linear_velocity.x, 0, car.linear_velocity.z).length(), "peak_dv": 0.0}
