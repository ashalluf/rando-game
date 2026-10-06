extends Node
## Stills of the river without the whole city (like tools/glshot/block_shot.gd: the FULL chunks round
## each eye, lit by the city scene's own environment and sun), plus a car staged on an access ramp:
##
##   OUT=/tmp/r.png CAR=1 RAMP=1 RAMP_T=0.45 LIBGL_ALWAYS_SOFTWARE=1 flock -o /tmp/rando_render_gl.lock \
##     xvfb-run -a -s "-screen 0 1280x720x24" godot --rendering-driver opengl3 --display-driver x11 \
##     --audio-driver Dummy --path . res://tools/la_river/river_shot.tscn --resolution 1280x720
##
## CAR=1 puts a sedan on ramp RAMP (index into LaRiver.ramps(), default 1) RAMP_T of the way down it
## (default 0.45), nose down the ramp, rolling at CAR_SPEED m/s (default 6), and frames it from the
## bank road above unless EYE is given (EYE=x,y,z,yaw,pitch; y ABSOLUTE here). FRAMES (default 14)
## frames run before the shot (the car rolls on down meanwhile). FOV, OUT, BLOCKS as block_shot.

func _ready() -> void:
	await get_tree().process_frame
	var city: Node = (load("res://scenes/levels/city.tscn") as PackedScene).instantiate()
	var plan := CityPlan.new()
	plan.seed = city.world_seed
	plan.block_size_range = city.block_size_range
	plan.street_width = city.street_width
	plan.avenue_width = city.avenue_width
	plan.sidewalk_width = city.sidewalk_width
	plan.downtown_radius = city.downtown_radius
	plan.midtown_radius = city.midtown_radius
	plan.macro = MacroMap.new()
	plan.macro.seed = city.world_seed
	plan.macro.setup()
	for keep in ["WorldEnvironment", "Sun"]:
		var n: Node = city.get_node_or_null(keep)
		if n:
			city.remove_child(n)
			n.owner = null
			add_child(n)
	var sun := get_node_or_null("Sun") as DirectionalLight3D
	if sun:
		sun.rotation_degrees = city.get("sun_rotation_degrees")
		RenderingServer.global_shader_parameter_set("sun_direction", sun.global_basis.z)
	var style: Dictionary = city.chunk_style()
	var rv: LaRiver = plan.macro.river
	var ramps := rv.ramps(plan)
	var r: Dictionary = ramps[int(OS.get_environment("RAMP")) if OS.get_environment("RAMP") != "" else 1]
	var t := float(OS.get_environment("RAMP_T")) if OS.get_environment("RAMP_T") != "" else 0.45
	var s0: float = r.s0
	var s1: float = r.s1
	var sg: float = r.side
	var ramp_at := func(tt: float) -> Vector3:
		var s := lerpf(s0, s1, tt)
		var e := tt * tt * (3.0 - 2.0 * tt) * 0.25 + tt * 0.75
		var top := rv.top_at(s)
		var toe := rv.toe_at(s)
		var y := lerpf(top + CityChunk.ROAD_TOP, toe + 0.02, e)
		var outer := clampf(rv.bed_half(s) + (y - toe) * LaRiver.SLOPE, rv.bed_half(s), rv.top_half(s))
		var p := rv.point(s, sg * (outer - LaRiver.RAMP_WIDTH * 0.5))
		return Vector3(p.x, y, p.y)
	var car_at: Vector3 = ramp_at.call(t)
	var ahead: Vector3 = ramp_at.call(minf(t + 0.08, 1.0))
	var fwd := (ahead - car_at).normalized()
	var eye := OS.get_environment("EYE")
	var cam := Camera3D.new()
	cam.fov = float(OS.get_environment("FOV")) if OS.get_environment("FOV") != "" else 55.0
	cam.far = 4000.0
	add_child(cam)
	cam.make_current()
	var cam_xf: Transform3D
	if eye != "":
		var p: PackedStringArray = eye.split(",")
		cam_xf = Transform3D(Basis.from_euler(Vector3(deg_to_rad(p[4].to_float()), deg_to_rad(p[3].to_float()), 0.0)), Vector3(p[0].to_float(), p[1].to_float(), p[2].to_float()))
	else:
		# From the bank road above and behind the car, looking down the ramp at it.
		var back: Vector3 = ramp_at.call(maxf(t - 0.35, 0.0))
		var side := Vector3(-fwd.z, 0.0, fwd.x).normalized()
		var from := back - fwd * 6.0 + Vector3.UP * 5.5 - side * sg * 3.0
		cam_xf = Transform3D(Basis.looking_at(car_at - from, Vector3.UP), from)
	var blocks := int(OS.get_environment("BLOCKS")) if OS.get_environment("BLOCKS") != "" else 1
	var home: Vector2i = plan.block_index_at(Vector2(car_at.x, car_at.z))
	var chunk_script: GDScript = load("res://scripts/world/city_chunk.gd")
	for dz in range(-blocks, blocks + 1):
		for dx in range(-blocks, blocks + 1):
			var ch = chunk_script.new()
			ch.plan = plan
			ch.ix = home.x + dx
			ch.iz = home.y + dz
			ch.level = 0
			ch.style = style
			add_child(ch)
			ch.build()
	cam.global_transform = cam_xf
	if OS.get_environment("CAR") == "1":
		var car := Vehicle.new()
		car.setup(Vehicle.BodyType.SEDAN, Color(0.62, 0.05, 0.04), Vehicle.Addon.NONE)
		add_child(car)
		car.global_transform = Transform3D(Basis.looking_at(fwd, Vector3.UP), car_at + Vector3.UP * 0.9)
		var spd := float(OS.get_environment("CAR_SPEED")) if OS.get_environment("CAR_SPEED") != "" else 6.0
		car.linear_velocity = fwd * spd
		print("car at ", car_at, " heading ", fwd)
	for i in (int(OS.get_environment("FRAMES")) if OS.get_environment("FRAMES") != "" else 14):
		await get_tree().process_frame
	var out := OS.get_environment("OUT") if OS.get_environment("OUT") != "" else "river.png"
	get_viewport().get_texture().get_image().save_png(out)
	print("saved ", out)
	city.free()
	get_tree().quit()
