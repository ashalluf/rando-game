class_name LightRailTrain
extends Node3D
## One Coral Line train in full detail near the player (LightRailSystem keeps a small pool of
## these; far ones are boxes): two articulated cars (CARS), each two sections of the Blender model
## (tools/make_light_rail.py) back to back on three bogies, coupled cab to cab. Nothing here is
## ticked from its own state: `pose(state)` puts every section, bogie and door where the
## timetable says the train is (LightRail.trains_at(clock)), so a train is the same wherever the
## player comes upon it.
##
## Each section is an AnimatableBody3D on the props layer (mask 0), so the player and the cars run
## into it as into a wall, bullets, pellets and blasts hit it (take_hit(): it keeps running; the
## sparks, the metal ping and the holes are the weapons' own - WeaponFX.classify() calls the
## "rail_vehicle" group metal), and LightRailSystem knocks down whoever stands in front of it.
## Lamps: the leading cab's headlights and destination display are lit, the trailing cab's tail
## lights, the coupled cabs' nothing; the windows trace their saloon (lrv_glass.gdshader), lit
## after dark; the doors on the platform side (the train's left: right-hand running past island
## platforms) slide open while it dwells.

const MODEL := "res://assets/models/light_rail_car.glb"
const SECTION_HALF := 6.75
const CAB_BOGIE := 4.3
## Door leaves: how far a leaf slides open and how far it plugs out first.
const DOOR_SLIDE := 0.66
const DOOR_PLUG := 0.06
## The headlight a lead cab throws at night (Forward+ only).
const HEADLIGHT_RANGE := 70.0

static var _scene: PackedScene
static var _glass_mat: ShaderMaterial
static var _interior_mats: Dictionary = {}
static var _lamp_mats: Dictionary = {}

var line: LightRail
var id := -1
## The sections in consist order from the front: car 0 A (nose forward), car 0 B, car 1 A, car 1 B.
var sections: Array[RailSection] = []
var _bogies: Array = []
var _doors: Array = []
var _bodies: Array[MeshInstance3D] = []
var _merged_doors: Array = []
var _interiors: Array = []
var _doors_shown := -1
var _sign: Label3D
var _rear_sign: Label3D
var _headlight: SpotLight3D
var _roll: AudioStreamPlayer3D
var _roll_db := 0.0
var front_s := 0.0
var dir := 1
var speed := 0.0
var doors_open := 0.0
var destination := ""


static func available() -> bool:
	return ResourceLoader.exists(MODEL)


func setup(l: LightRail) -> void:
	line = l
	name = "LightRailTrain"
	if _scene == null:
		_scene = load(MODEL)
	for k in LightRail.CARS * 2:
		var body := RailSection.new()
		body.name = "Section%d" % k
		body.collision_layer = 4
		body.collision_mask = 0
		body.sync_to_physics = false
		body.add_to_group("rail_vehicle")
		var cs := CollisionShape3D.new()
		var bx := BoxShape3D.new()
		bx.size = Vector3(2.7, 3.0, 13.3)
		cs.shape = bx
		cs.position = Vector3(0.0, 2.0, 0.0)
		body.add_child(cs)
		var inst: Node3D = _scene.instantiate()
		body.add_child(inst)
		add_child(body)
		sections.append(body)
		_dress(inst, k)
	if CarLights.supported():
		_headlight = SpotLight3D.new()
		_headlight.spot_range = HEADLIGHT_RANGE
		_headlight.spot_angle = 24.0
		_headlight.light_energy = 0.0
		_headlight.shadow_enabled = false
		_headlight.light_color = Color(1.0, 0.95, 0.86)
		sections[0].add_child(_headlight)
		_headlight.position = Vector3(0.0, 1.0, -SECTION_HALF - 0.3)
	_roll = Sfx.loop_player("rail_roll", 0.0)
	if _roll:
		_roll_db = _roll.volume_db
		sections[1].add_child(_roll)
		_roll.position = Vector3(0.0, 0.8, 0.0)
		_roll.unit_size = 14.0
		_roll.play()


## Which end a section is: 0 the leading cab, 1 the trailing cab, 2 a coupled cab.
func _role(k: int) -> int:
	if k == 0:
		return 0
	if k == LightRail.CARS * 2 - 1:
		return 1
	return 2


func _dress(inst: Node3D, k: int) -> void:
	var role := _role(k)
	var b_section := k % 2 == 1
	# A pantograph on one section a car, at the ends that swap places when the train turns round
	# (car 0's A and the last car's B), so the swap at a terminus is invisible.
	var panto := inst.get_node_or_null("Pantograph") as Node3D
	if panto:
		panto.visible = (k == 0) or (k == LightRail.CARS * 2 - 1)
	var bellows := inst.get_node_or_null("Bellows") as Node3D
	if bellows:
		bellows.visible = not b_section
		bellows.position = Vector3(0.0, 0.0, SECTION_HALF)
	var bogie := inst.get_node_or_null("Bogie") as Node3D
	var list: Array = []
	if bogie is MeshInstance3D:
		_set_slots(bogie as MeshInstance3D, role)
	if bogie:
		bogie.position = Vector3(0.0, 0.0, -CAB_BOGIE)
		list.append([bogie, false])
		if not b_section:
			var art := bogie.duplicate() as Node3D
			inst.add_child(art)
			art.position = Vector3(0.0, 0.0, SECTION_HALF)
			list.append([art, true])
	_bogies.append(list)
	var body := inst.get_node_or_null("Body") as MeshInstance3D
	if body:
		_bodies.append(body)
		_set_slots(body, role)
	var interior := inst.get_node_or_null("Interior") as MeshInstance3D
	if interior:
		_set_slots(interior, role)
	for part in ["Pantograph", "Bellows"]:
		var pm := inst.get_node_or_null(part) as MeshInstance3D
		if pm:
			_set_slots(pm, role)
	# Doors on the platform side: the train's left is an A section's model left (L) and a B
	# section's model right (R).
	var side := "R" if b_section else "L"
	var leaves: Array = []
	for n in 2:
		for leaf in ["A", "B"]:
			var d := inst.get_node_or_null("Door_%s_%d_%s" % [side, n, leaf]) as Node3D
			if d:
				leaves.append([d, d.position, 1.0 if leaf == "A" else -1.0])
	for s2 in ["L", "R"]:
		for n in 2:
			for leaf in ["A", "B"]:
				var d := inst.get_node_or_null("Door_%s_%d_%s" % [s2, n, leaf]) as MeshInstance3D
				if d:
					_set_slots(d, role)
					d.visible = false
		var merged := inst.get_node_or_null("Doors" + s2) as MeshInstance3D
		if merged:
			_set_slots(merged, role)
	_doors.append(leaves)
	# Shut, a side's doors are its one merged mesh; the platform side swaps to its four leaves
	# while they open (_show_doors()).
	_merged_doors.append(inst.get_node_or_null("Doors" + side))
	_interiors.append(interior)
	# Only the body casts: doors, bogies, the pantograph and the bellows are inside its shadow or
	# too thin to matter, and every caster is a draw per shadow cascade.
	for n in inst.get_children():
		if n is GeometryInstance3D and n.name != "Body":
			(n as GeometryInstance3D).cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	# Destination displays: the lead cab names where it is going, the rear cab the line.
	if role != 2:
		var label := Label3D.new()
		label.font_size = 64
		label.pixel_size = 0.0028
		label.outline_size = 0
		label.modulate = Color(1.0, 0.62, 0.18)
		label.shaded = false
		label.double_sided = false
		label.no_depth_test = false
		label.position = Vector3(0.0, 3.0, -6.335)
		label.rotation = Vector3(0.0, PI, 0.0)
		label.text = LightRail.LINE_LETTER
		inst.add_child(label)
		if role == 0:
			_sign = label
		else:
			_rear_sign = label


## Shared materials by the model's slot names: glass traced, the interior lit, the lamps by role.
func _set_slots(mi: MeshInstance3D, role: int) -> void:
	var mesh := mi.mesh
	if mesh == null:
		return
	for i in mesh.get_surface_count():
		var mat := mesh.surface_get_material(i)
		var nm := mat.resource_name if mat else ""
		match nm:
			"glass", "door_glass":
				mi.set_surface_override_material(i, glass_material())
			"body":
				mi.set_surface_override_material(i, body_material())
			"interior":
				mi.set_surface_override_material(i, interior_material())
			"lamp_head":
				mi.set_surface_override_material(i, lamp_material("head", role == 0))
			"lamp_tail":
				mi.set_surface_override_material(i, lamp_material("tail", role == 1))
			"sign":
				mi.set_surface_override_material(i, lamp_material("sign", false))


static func glass_material() -> ShaderMaterial:
	if _glass_mat == null:
		_glass_mat = ShaderMaterial.new()
		_glass_mat.shader = load("res://shaders/lrv_glass.gdshader")
	return _glass_mat


static func interior_material() -> ShaderMaterial:
	if not _interior_mats.has("interior"):
		var m := ShaderMaterial.new()
		m.shader = load("res://shaders/lrv_interior.gdshader")
		_interior_mats["interior"] = m
	return _interior_mats["interior"]


## Every painted, rubber and metal part: one material, its colours in the vertex colour.
static func body_material() -> ShaderMaterial:
	if not _interior_mats.has("body"):
		var m := ShaderMaterial.new()
		m.shader = load("res://shaders/lrv_body.gdshader")
		_interior_mats["body"] = m
	return _interior_mats["body"]


static func lamp_material(kind: String, on: bool) -> StandardMaterial3D:
	var key := "%s_%s" % [kind, on]
	if not _lamp_mats.has(key):
		var m := StandardMaterial3D.new()
		m.roughness = 0.15
		match kind:
			"head":
				m.albedo_color = Color(0.9, 0.92, 0.95) if on else Color(0.35, 0.36, 0.38)
				if on:
					m.emission_enabled = true
					m.emission = Color(1.0, 0.96, 0.88)
					m.emission_energy_multiplier = 5.0
			"tail":
				m.albedo_color = Color(0.5, 0.02, 0.02) if on else Color(0.18, 0.03, 0.03)
				if on:
					m.emission_enabled = true
					m.emission = Color(1.0, 0.05, 0.03)
					m.emission_energy_multiplier = 4.0
			_:
				m.albedo_color = Color(0.015, 0.015, 0.015)
		_lamp_mats[key] = m
	return _lamp_mats[key]


## Puts the train where `state` (one of LightRail.trains_at()) says, true world.
func pose(state: Dictionary, lamp: float) -> void:
	front_s = float(state.s)
	dir = int(state.dir)
	speed = float(state.v)
	doors_open = float(state.doors)
	for k in sections.size():
		var car := k / 2
		var x0 := float(car) * (LightRail.CAR_LENGTH + LightRail.COUPLER)
		var b_section := k % 2 == 1
		var cab_x := x0 + (LightRail.CAR_LENGTH - (SECTION_HALF - CAB_BOGIE)) if b_section else x0 + (SECTION_HALF - CAB_BOGIE)
		var art_x := x0 + SECTION_HALF * 2.0
		var world := section_world(line, front_s, dir, k)
		if world == Transform3D():
			continue
		var basis := world.basis
		var f := -basis.z
		var body := sections[k]
		body.global_transform = Transform3D(basis, WorldState.to_local(world.origin))
		# Hidden (and not solid) once wholly in the tunnel past the portal's bore.
		var centre_s := _along((cab_x + art_x) * 0.5)
		var buried := centre_s < line.mouth_s - 10.0
		body.visible = not buried
		body.process_mode = Node.PROCESS_MODE_DISABLED if buried else Node.PROCESS_MODE_INHERIT
		# Bogies turn under the body to follow the track.
		for entry: Array in _bogies[k]:
			var bg: Node3D = entry[0]
			var at_x := art_x if bool(entry[1]) else cab_x
			var smp := line.sample(_along(at_x))
			var d2: Vector2 = smp.dir
			var ld := basis.inverse() * Vector3(d2.x, 0.0, d2.y)
			var yaw := atan2(-ld.x, -ld.z)
			# A bogie is symmetric: turn it the short way.
			if yaw > PI * 0.5:
				yaw -= PI
			elif yaw < -PI * 0.5:
				yaw += PI
			bg.rotation = Vector3(0.0, yaw, 0.0)
		# Doors.
		var o := clampf(doors_open, 0.0, 1.0)
		var show := 1 if o > 0.0 else 0
		if show != _doors_shown:
			var m := _merged_doors[k] as Node3D
			if m:
				m.visible = show == 0
			for leaf: Array in _doors[k]:
				(leaf[0] as Node3D).visible = show == 1
			var inner := _interiors[k] as Node3D
			if inner:
				inner.visible = show == 1
		var plug := minf(o * 4.0, 1.0) * DOOR_PLUG
		var slide := clampf((o - 0.2) / 0.8, 0.0, 1.0) * DOOR_SLIDE
		for leaf: Array in _doors[k]:
			var node: Node3D = leaf[0]
			var closed: Vector3 = leaf[1]
			var way: float = leaf[2]
			node.position = closed + Vector3(signf(closed.x) * plug, 0.0, way * slide)
	_doors_shown = 1 if doors_open > 0.0 else 0
	if _headlight:
		_headlight.light_energy = 2.6 * clampf(lamp, 0.0, 1.0)
		_headlight.visible = lamp > 0.05 and sections[0].visible
	if _roll:
		_roll.volume_db = _roll_db + linear_to_db(clampf(speed / 18.0, 0.02, 1.0)) - 4.0
		_roll.pitch_scale = clampf(0.75 + speed / 40.0, 0.7, 1.4)


## Where the open doors are (TRUE world XZ, a little out on the platform side): one point per
## door pair on the platform side of every visible section.
func door_points() -> Array[Vector2]:
	var out: Array[Vector2] = []
	for k in sections.size():
		var body := sections[k]
		if not body.visible:
			continue
		var leaves: Array = _doors[k]
		for i in range(0, leaves.size() - 1, 2):
			var a: Vector3 = leaves[i][1]
			var b: Vector3 = leaves[i + 1][1]
			var c := (a + b) * 0.5
			# Half a metre out of the doorway onto the platform.
			c.x += signf(c.x) * 0.6
			var inst := body.get_child(1) as Node3D
			var g := inst.global_transform * c
			var w := WorldState.to_world(g)
			out.append(Vector2(w.x, w.z))
	return out


func _along(x: float) -> float:
	return front_s - float(dir) * x


## Section k of a train whose nose is at `s_front` running `dir`, in TRUE world: its model frame
## (nose toward -Z) laid on its two bogie pivots on track `dir` (right-hand running). Identity
## when the bogies coincide.
static func section_world(l: LightRail, s_front: float, d: int, k: int) -> Transform3D:
	var car := k / 2
	var x0 := float(car) * (LightRail.CAR_LENGTH + LightRail.COUPLER)
	var b_section := k % 2 == 1
	var cab_x := x0 + (LightRail.CAR_LENGTH - (SECTION_HALF - CAB_BOGIE)) if b_section else x0 + (SECTION_HALF - CAB_BOGIE)
	var art_x := x0 + SECTION_HALF * 2.0
	var pc := l.track_point(s_front - float(d) * cab_x, d)
	var pa := l.track_point(s_front - float(d) * art_x, d)
	var f := pc - pa
	if f.length() < 0.01:
		return Transform3D()
	var origin := pa + f * (SECTION_HALF / (SECTION_HALF + CAB_BOGIE))
	return Transform3D(Basis.looking_at(f.normalized(), Vector3.UP), origin)


func set_destination(text: String) -> void:
	if destination == text:
		return
	destination = text
	if _sign:
		_sign.text = "%s  %s" % [LightRail.LINE_LETTER, text]

