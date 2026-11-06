class_name AnchoredShip
extends AnimatableBody3D
## A container ship riding at anchor in the roads off the port (OceanTraffic): the moored ship's
## own hull and house (PortKit.ship_mesh(), the bow toward -X) with a deck load of containers in
## their liveries, her bow into the wind and swinging slowly round her anchor, and lit at night
## like the real ones - the anchor lights fore and aft, a row of deck floods along the lashing
## bridges, the house's lit windows. A body on the world layer (mask 0) you can land on or shoot:
## rounds spark off her steel ("rail_vehicle"), she is far too big to sink.

const HIT_LAYER := 1
## Metres of the hull's length either side of the anchor the bow swings round (the scope).
const SWING := 0.14
## Seconds of one slow swing round the anchor.
const SWING_PERIOD := 720.0

var anchor_xz: Vector2 = Vector2.ZERO
var heading0: float = 0.0
var phase: float = 0.0
var world_pos: Vector3 = Vector3.ZERO
var yaw: float = 0.0
var _t: float = 0.0

static var _light_shader: Shader


func _init() -> void:
	sync_to_physics = false
	collision_layer = HIT_LAYER
	collision_mask = 0


## Builds her at `at` (TRUE world XZ), bow toward `bow` (unit XZ), her deck load from `sd`.
func setup(at: Vector2, bow: Vector2, sd: int) -> void:
	add_to_group("rail_vehicle")
	add_to_group("anchored_ship")
	anchor_xz = at
	heading0 = atan2(bow.y, -bow.x)
	var rng := RandomNumberGenerator.new()
	rng.seed = sd
	phase = rng.randf() * TAU
	var hull := MeshInstance3D.new()
	hull.name = "Hull"
	hull.mesh = PortKit.ship_mesh()
	hull.visibility_range_end = 11500.0
	add_child(hull)
	# The deck load: the landmark ship's stacks (PortKit's boxes in their liveries), 2-5 high.
	var batch := MultiMeshBatch.new()
	for i in 10:
		var x := -70.0 + i * 14.0
		for row in 3:
			var z := (row - 1) * 8.0
			var height := rng.randi_range(2, 5)
			if rng.randf() < 0.08:
				height = 0
			for h in height:
				var pick: int = rng.randi() % 6
				for k in 3:
					var livery: int = PortKit.COLOR_TO_LIVERY[pick] if rng.randf() < 0.7 else rng.randi() % PortKit.LIVERY_COUNT
					var look := PortKit.container_look(livery, rng)
					var centre := Vector3(x, 9.0 + PortKit.H_STD * (h + 0.5), z + (k - 1) * (PortKit.W + 0.05))
					batch.add("container", PropFactory.container(), PortKit.container_xform(centre, true, false, rng.randf() < 0.5), look[0], look[1])
	batch.build(self)
	for n in find_children("*", "GeometryInstance3D", true, false):
		(n as GeometryInstance3D).visibility_range_end = 9000.0
	_shape(Vector3(180.0, 12.0, 30.0), Vector3(0.0, 2.0, 0.0))
	_shape(Vector3(130.0, 12.0, 24.0), Vector3(-5.0, 14.0, 0.0))
	_shape(Vector3(12.0, 21.0, 22.0), Vector3(78.0, PortKit.SHIP_DECK_Y + 10.5, 0.0))
	_build_lights()
	world_pos = Vector3(at.x, 0.0, at.y)
	_pose(0.0)


func _shape(size: Vector3, at: Vector3) -> void:
	var cs := CollisionShape3D.new()
	var b := BoxShape3D.new()
	b.size = size
	cs.shape = b
	cs.position = at
	add_child(cs)


## Swings her a little round the anchor and puts her there (TRUE world -> scene).
func drive(dt: float) -> void:
	_t += dt
	_pose(_t)
	if is_inside_tree():
		global_transform = Transform3D(Basis(Vector3.UP, yaw), WorldState.to_local(world_pos))


func _pose(t: float) -> void:
	var a := sin(t * TAU / SWING_PERIOD + phase) * SWING
	yaw = heading0 + a
	# The anchor is under her bow: she pivots about a point ahead of it.
	var bow := Vector2(-cos(yaw), sin(yaw))
	var pivot := 160.0
	var centre := anchor_xz - bow * pivot + Vector2(-cos(heading0), sin(heading0)) * pivot
	world_pos = Vector3(centre.x, 0.0, centre.y)


func _build_lights() -> void:
	if _light_shader == null:
		_light_shader = load("res://shaders/aircraft_lights.gdshader")
	var specs: Array = []
	var white := Color(1.0, 0.96, 0.88, 1.0)
	var flood := Color(1.0, 0.72, 0.38, 0.8)
	# Anchor lights: forward on the foremast higher than the one aft (COLREGs), all round.
	specs.append([Vector3(-92.0, 24.0, 0.0), white, 1.8, Vector3.ZERO])
	specs.append([Vector3(88.0, 18.0, 0.0), white, 1.8, Vector3.ZERO])
	# The red obstruction light on the house's mast.
	specs.append([Vector3(84.0, PortKit.SHIP_DECK_Y + 27.5, 0.0), Color(1.0, 0.1, 0.06, 1.0), 1.4, Vector3.ZERO])
	# Deck floods along both sides of the stacks, and the house's lit decks.
	for i in 11:
		var x := -77.0 + i * 14.0
		for side: float in [-1.0, 1.0]:
			specs.append([Vector3(x, 12.5, side * 14.6), flood, 1.4, Vector3.ZERO])
	for f in 5:
		for side: float in [-1.0, 1.0]:
			for k in 3:
				specs.append([Vector3(72.0 + float(k) * 5.0, PortKit.SHIP_DECK_Y + 3.0 + float(f) * 3.6, side * 11.2), Color(1.0, 0.86, 0.6, 0.55), 0.9, Vector3(0.0, 0.0, side)])
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var corners := [Vector2(0.0, 0.0), Vector2(1.0, 0.0), Vector2(1.0, 1.0), Vector2(0.0, 1.0)]
	for spec: Array in specs:
		var aimed := (spec[3] as Vector3) != Vector3.ZERO
		var code := 40.0 + (100.0 if aimed else 0.0)
		for c in [0, 1, 2, 0, 2, 3]:
			st.set_color(spec[1])
			st.set_uv(corners[c])
			st.set_uv2(Vector2(spec[2], code))
			st.set_normal(spec[3] if aimed else Vector3.UP)
			st.add_vertex(spec[0])
	var mesh := st.commit()
	var lm := ShaderMaterial.new()
	lm.shader = _light_shader
	lm.set_shader_parameter("field_day", 0.0)
	mesh.surface_set_material(0, lm)
	var mi := MeshInstance3D.new()
	mi.name = "Lights"
	mi.mesh = mesh
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mi.custom_aabb = AABB(Vector3(-120.0, -10.0, -40.0), Vector3(240.0, 60.0, 80.0))
	mi.extra_cull_margin = 16000.0
	add_child(mi)
