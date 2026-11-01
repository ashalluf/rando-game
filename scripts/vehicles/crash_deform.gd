class_name CrashDeform
extends Node
## What a crash does to a car's shape (owner, wave 3: "GTA's cars crumple; make crashes read").
## CarDamage's dents push a patch of skin in; this is the structure giving way behind it, made
## the first time a crash (or a big blast) is hard enough (CarDamage.crumple(), a child of the
## car's CarDamage, so an undamaged car still has none of it):
##   * CRUMPLE ZONES: a crush from the contact point into the car along the velocity change,
##     the front of the zone pushed back `depth_per_dv` metres per m/s past the threshold, the
##     metal behind it folding up like an accordion (ridges across the push, the paint cracked
##     and flaking along them), a bonnet or boot lid crushed from its end tenting UP, a roof
##     landed on caved in. Up to CRUMPLE_CAP zones a car; a hit near an old zone the same way
##     deepens it (to `max_crush`).
##   * PANELS: a bonnet sprung off its catch (its front up a few centimetres), a boot lid ajar,
##     a bumper torn off one corner and hanging to the road, a door sprung ajar and drooping on
##     its hinges (the car-cabins door rig, CarInterior.jam(), where the car has one).
##   * WHEELS: a wheel near a hard hit knocked out of line (camber and pushed in; visual).
##   * SCRAPES: a band along the contact, scuffed and scored to primer and bare steel, the way
##     the car was sliding.
##   * SHARDS on the road (CrashLitter): glass and lamp lens, bumper plastic, paint flecks.
## All of it is uniforms in the body model's own mesh space (car_crumple.gdshaderinc), worn by
## the damaged paint, glass and lamps and by the trim / chrome / far-twin parts, which move onto
## car_part_damage.gdshader with the first crumple so a grille or a bumper rides the crushed nose.
## `CRASH_DEFORM=0` in the environment turns all of it off (the A/B: the old dents only).

static var enabled: bool = OS.get_environment("CRASH_DEFORM") != "0"

const CRUMPLE_CAP := 6
const SCRAPE_CAP := 8
const PANEL_CAP := 4
const PART_SHADER := preload("res://shaders/car_part_damage.gdshader")
const DETAIL_SHADER := preload("res://shaders/car_detail_damage.gdshader")
enum Lid { BONNET, BOOT, BUMPER_FRONT, BUMPER_REAR }

@export_group("Crumple")
## A crash past this (m/s over Vehicle.crash_min_dv) crumples the body.
@export var min_over: float = 1.5
## Metres of crush per m/s past min_over (a 60 km/h head-on into a wall: about half a metre).
@export var depth_per_dv: float = 0.062
## The deepest one hit crushes (m), and a zone however many hits it takes (m).
@export var max_hit_depth: float = 0.7
@export var max_crush: float = 0.9
## How deep into the car a crush reaches: base + gain x the crush (m), at most this share of the
## car's extent along the push.
@export var reach_base: float = 0.42
@export var reach_gain: float = 1.6
@export var reach_share: float = 0.46
## The zone's half width across the push: base + gain x the crush (m).
@export var radius_base: float = 0.62
@export var radius_gain: float = 1.25
## A door is weaker than a crumple zone: a side hit crushes this much more.
@export var side_gain: float = 1.4
## The folds' spacing (m) and how much a bonnet / boot lid tents up (share of the crush).
@export var fold_pitch: float = 0.2
@export var tent: float = 0.32
## A blast this strong at the car (falloff) crushes the side facing it this deep at full.
@export var blast_from: float = 0.55
@export var blast_depth: float = 0.32

@export_group("Panels")
## The front (rear) crush past which the bonnet (boot lid) springs and a bumper tears off a corner.
@export var bonnet_at: float = 0.16
@export var bumper_at: float = 0.3
## How far the bonnet's front edge lifts (rad, at most).
@export var bonnet_angle: float = 0.12
## A side crash this hard (m/s over) springs the door there (the cabin rig).
@export var door_at: float = 3.0

@export_group("Wheels")
## A crash this hard within `wheel_reach` of a wheel knocks it out of line, by up to
## `max_camber` radians.
@export var wheel_at: float = 3.0
@export var wheel_reach: float = 1.0
@export var max_camber: float = 0.24

@export_group("Shards")
## Shards a broken lamp, a pane falling out and a crumple leave on the road.
@export var lamp_shards: int = 22
@export var pane_shards: int = 70
@export var plastic_shards: int = 10

var dmg: CarDamage
var car: Vehicle

var _crumples := PackedVector4Array()
var _crumple_push := PackedVector4Array()
var _crumple_shape := PackedVector4Array()
## Body-space copies, for merging hits and the panels' rules: [contact, dir, depth (m)].
var _zones: Array = []
var _scrapes := PackedVector4Array()
var _scrape_dir := PackedVector4Array()
var _scrape_next: int = 0
## Per Lid, the angle it is turned (rad), 0 = shut.
var _panel_angle: Array[float] = [0.0, 0.0, 0.0, 0.0]
var _panel_data: Array = [{}, {}, {}, {}]
var _part_mats: Array[ShaderMaterial] = []
var _detail_mats: Array[ShaderMaterial] = []
var _parts_done: bool = false
## Wheel rig nodes knocked: node -> [rotation, position] before.
var _wheel_was: Dictionary = {}
## The hits that crumpled (tests).
var crumples_made: int = 0


func attach(to: CarDamage) -> void:
	dmg = to
	car = to.car
	name = "Crumple"


static func applies(c: Vehicle) -> bool:
	return enabled and c != null and c._has_model and not (c is Aircraft) and not (c is Motorcycle)


# --- Hits ------------------------------------------------------------------------------------------

## A crash: `body_at` the contact on the car's box, `push_body` the velocity change (body space,
## unit), `over` m/s past the threshold, `world_at` the scene point.
func crash(body_at: Vector3, push_body: Vector3, over: float, world_at: Vector3) -> void:
	if over < min_over:
		_scrape(body_at, push_body, over)
		return
	var depth := minf(depth_per_dv * (over - min_over * 0.5), max_hit_depth)
	var zone := _crumple(body_at, push_body, depth)
	_scrape(body_at, push_body, over)
	_panels(body_at, push_body, over)
	_wheels(body_at, push_body, over)
	CrashLitter.scatter(car, world_at, car.linear_velocity, CrashLitter.Kind.PLASTIC,
			int(plastic_shards * clampf(depth / 0.4, 0.3, 1.5)))
	CrashLitter.scatter(car, world_at, car.linear_velocity, CrashLitter.Kind.PAINT,
			int(8.0 * clampf(depth / 0.4, 0.3, 1.5)), car.paint)
	if zone >= 0:
		crumples_made += 1
	if CrashBreakup.applies(car):
		dmg.breakup().crash(body_at, push_body, over, world_at)


## A blast's side of the car caved in (only past `blast_from`).
func blast(body_near: Vector3, push_body: Vector3, falloff: float) -> void:
	if falloff < blast_from:
		return
	_crumple(body_near, push_body, blast_depth * clampf((falloff - blast_from) / (1.0 - blast_from), 0.25, 1.0))
	_panels(body_near, push_body, 4.0 + falloff * 6.0)
	crumples_made += 1


## Adds (or deepens) a crumple zone; returns its index or -1.
func _crumple(body_at: Vector3, dir_body: Vector3, depth: float) -> int:
	if depth < 0.02:
		return -1
	var dir := dir_body.normalized()
	if absf(dir.x) > 0.6:
		depth *= side_gain
	var extent := absf(dir.x) * dmg._width + absf(dir.z) * dmg._len + absf(dir.y) * (dmg._top - dmg._ride)
	var reach_cap := maxf(reach_share * extent, 0.3)
	# The same way near an old zone: that zone goes deeper.
	var k := -1
	for i in _zones.size():
		var z: Array = _zones[i]
		var r := radius_base + radius_gain * float(z[2])
		if (z[0] as Vector3).distance_to(body_at) < r * 0.6 and (z[1] as Vector3).dot(dir) > 0.6:
			k = i
			break
	var total := depth
	var at := body_at
	if k >= 0:
		var z: Array = _zones[k]
		total = minf(float(z[2]) + depth * 0.75, max_crush)
		at = (z[0] as Vector3).lerp(body_at, 0.3)
		dir = ((z[1] as Vector3) * float(z[2]) + dir * depth).normalized()
	total = minf(total, reach_cap / 1.35)
	var reach := clampf(reach_base + reach_gain * total, 0.3, reach_cap)
	var radius := radius_base + radius_gain * total
	if absf(dir.y) > 0.6:
		# A roof comes down whole: the pillars fold under it, edge to edge.
		radius = maxf(radius, dmg._width * 0.5 + 0.9)
	var seed := float(absi(hash([crumples_made, int(at.x * 100.0), int(at.z * 100.0), int(at.y * 100.0)])) % 997) / 997.0
	var to_mesh := dmg._to_mesh
	var ms := dmg._mesh_scale
	var p := to_mesh * at
	var push := (to_mesh.basis * dir).normalized() * total / ms
	var lengthwise := absf(dir.z) > 0.6
	var c := Vector4(p.x, p.y, p.z, radius / ms)
	var cp := Vector4(push.x, push.y, push.z, seed)
	var cs := Vector4(reach / ms, (fold_pitch + 0.06 * seed) / ms, tent if lengthwise else tent * 0.25, 0.0)
	if k < 0:
		if _zones.size() < CRUMPLE_CAP:
			k = _zones.size()
			_zones.append([])
			_crumples.append(c)
			_crumple_push.append(cp)
			_crumple_shape.append(cs)
		else:
			# Replace the shallowest.
			k = 0
			for i in _zones.size():
				if float(_zones[i][2]) < float(_zones[k][2]):
					k = i
	_zones[k] = [at, dir, total]
	if absf(dir.z) > 0.6:
		_wheels_back(signf(at.z), total)
	_crumples[k] = c
	_crumple_push[k] = cp
	_crumple_shape[k] = cs
	_ensure_materials()
	dmg._mark_dirty()
	return k


## The crush reaching the car's end `sign` (-1 the nose, +1 the tail) along the length (m).
func crush_at_end(sign: float) -> float:
	var best := 0.0
	for z: Array in _zones:
		var dir: Vector3 = z[1]
		var at: Vector3 = z[0]
		if at.z * sign > dmg._len * 0.28 and dir.z * -sign > 0.45:
			best = maxf(best, float(z[2]))
	return best


# --- Panels -----------------------------------------------------------------------------------------

func _panels(body_at: Vector3, push_body: Vector3, over: float) -> void:
	var big := BigVehicles.is_big(car.body_type)
	var mid := CarDamage.MID_ENGINE.has(car.body_type)
	for end: float in [-1.0, 1.0]:
		var crush := crush_at_end(end)
		if crush <= 0.0:
			continue
		var lid := Lid.BONNET if end < 0.0 else Lid.BOOT
		if not big and not (mid and end < 0.0) and crush > bonnet_at:
			_set_panel(lid, clampf(0.035 + (crush - bonnet_at) * 0.25, 0.0, bonnet_angle * (1.0 if end < 0.0 else 0.7)), 0.0)
		if crush > bumper_at or (over > 6.0 and absf(body_at.x) > dmg._width * 0.22 and body_at.z * end > dmg._len * 0.3):
			var side := signf(body_at.x) if absf(body_at.x) > 0.05 else (1.0 if (crumples_made % 2) == 0 else -1.0)
			_set_panel(Lid.BUMPER_FRONT if end < 0.0 else Lid.BUMPER_REAR, 1.0, side)
	# A side hit on the doors springs the one there (the cabin rig, where the car has one).
	if absf(push_body.x) > 0.6 and absf(body_at.z) < dmg._len * 0.28 and over > door_at:
		var rig := CarInteriors.rig_of(car)
		if rig != null:
			rig.jam(signf(body_at.x), clampf(0.05 + over * 0.012, 0.05, 0.22), clampf(0.01 + over * 0.004, 0.0, 0.07))


## Turns panel `which` (Lid) to `amount`: an angle (rad) for a lid, 1 for a hanging bumper
## (`side` the corner torn loose: +1 body +x).
func _set_panel(which: int, amount: float, side: float) -> void:
	var len := dmg._len
	var hw := dmg._width * 0.5
	var ride := dmg._ride
	var top := dmg._top
	var road := float(car._dims().get("road", ride - 0.12))
	var d := {}
	match which:
		Lid.BONNET, Lid.BOOT:
			var end := -1.0 if which == Lid.BONNET else 1.0
			var screen := _screen_foot(end)
			var hinge_z: float = screen.x
			var lid_y: float = screen.y
			var z0 := end * len * 0.5
			var c := Vector3(0.0, (lid_y - 0.13 + top) * 0.5, (z0 + hinge_z) * 0.5)
			d.c = c
			d.u = Vector3(hw - 0.1, 0.0, 0.0)
			d.v = Vector3(0.0, (top - (lid_y - 0.13)) * 0.5, 0.0)
			d.w = Vector3(0.0, 0.0, absf(z0 - hinge_z) * 0.5 + 0.05)
			d.m = 0.09
			d.pivot = Vector3(0.0, lid_y, hinge_z)
			# The end rises: about +x for the nose (-z), -x for the tail.
			d.axis = Vector3.RIGHT * (-end)
			amount = maxf(amount, _panel_angle[which])
		_:
			var end := -1.0 if which == Lid.BUMPER_FRONT else 1.0
			if _panel_angle[which] > 0.0:
				return
			var y0 := ride - 0.04
			var y1 := ride + (top - ride) * 0.36
			var z0 := end * (len * 0.5 + 0.06)
			var z1 := end * (len * 0.5 - 0.34)
			d.c = Vector3(0.0, (y0 + y1) * 0.5, (z0 + z1) * 0.5)
			d.u = Vector3(hw + 0.06, 0.0, 0.0)
			d.v = Vector3(0.0, (y1 - y0) * 0.5, 0.0)
			d.w = Vector3(0.0, 0.0, absf(z0 - z1) * 0.5)
			d.m = 0.04
			# Held at the other corner: the torn one swings down to the road.
			d.pivot = Vector3(-side * hw, (y0 + y1) * 0.5, (z0 + z1) * 0.5)
			var drop := maxf((y0 + y1) * 0.5 - road, 0.05)
			# About +z (body), a positive angle lifts +x: the torn side (+side) drops.
			d.axis = Vector3.BACK
			amount = -side * atan2(drop, hw * 2.0)
	_panel_angle[which] = amount
	_panel_data[which] = d
	_ensure_materials()
	dmg._mark_dirty()


## Where the bonnet (end -1) or the boot lid (+1) is hinged: (body z, body y) at the foot of the
## windscreen / rear screen, from the car's measured glass; a share of the car where there is none.
func _screen_foot(end: float) -> Vector2:
	var inv := dmg._to_mesh.affine_inverse()
	var best := Vector2(end * dmg._len * (0.5 - 0.3), dmg._ride + (dmg._top - dmg._ride) * 0.55)
	var found := false
	for pane: Array in dmg._panes:
		if int(pane[3]) == CarCabin.KIND_LAMP:
			continue
		var n: Vector3 = (inv.basis * (pane[2] as Vector3)).normalized()
		if n.z * end < 0.35:
			continue
		var a: Vector3 = inv * (pane[0] as Vector3)
		var b: Vector3 = inv * (pane[1] as Vector3)
		var lo := a.min(b)
		var hi := a.max(b)
		var foot_z := lo.z if end < 0.0 else hi.z
		if not found or foot_z * end > best.x * end:
			best = Vector2(foot_z - end * 0.04, lo.y - 0.02)
			found = true
	return best


# --- Wheels -----------------------------------------------------------------------------------------

func _wheels(body_at: Vector3, push_body: Vector3, over: float) -> void:
	if over < wheel_at:
		return
	for rig: Array in car._wheel_rigs:
		var node := rig[0] as Node3D
		if node == null or not is_instance_valid(node):
			continue
		var wp := node.position
		var dist := Vector2(wp.x - body_at.x, wp.z - body_at.z).length()
		if dist > wheel_reach:
			continue
		if not _wheel_was.has(node):
			_wheel_was[node] = [node.rotation, node.position]
		var k := clampf((over - wheel_at) / 8.0 + 0.25, 0.0, 1.0) * (1.0 - dist / wheel_reach * 0.5)
		var side := signf(wp.x)
		var cam: float
		if absf(push_body.x) > 0.5:
			# Hit from the side: the top of the wheel leans the way it was pushed.
			cam = -signf(push_body.x) * max_camber * k
		else:
			# Hit at the end: it splays out at the top.
			cam = -side * max_camber * k * 0.8
		node.rotation.z = clampf(node.rotation.z + cam, -max_camber, max_camber)
		node.rotation.x = clampf(node.rotation.x + push_body.z * 0.08 * k, -0.12, 0.12)
		node.position.x -= side * 0.05 * k * maxf(absf(push_body.x), 0.3)


## A crush deep into an end pushes that axle's wheels back into the arches and splays them.
func _wheels_back(end: float, crush: float) -> void:
	var overhang := 0.0
	for rig: Array in car._wheel_rigs:
		var node := rig[0] as Node3D
		if node != null and signf(node.position.z) == end:
			overhang = maxf(overhang, dmg._len * 0.5 - absf(node.position.z))
	var into := crush - overhang * 0.55
	if into <= 0.0:
		return
	for rig: Array in car._wheel_rigs:
		var node := rig[0] as Node3D
		if node == null or not is_instance_valid(node) or signf(node.position.z) != end:
			continue
		if not _wheel_was.has(node):
			_wheel_was[node] = [node.rotation, node.position]
		var was: Vector3 = _wheel_was[node][1]
		node.position.z = was.z - end * minf(into * 0.7, 0.35)
		node.rotation.z = clampf(-signf(was.x) * minf(into * 0.5, max_camber), -max_camber, max_camber)


# --- Scrapes -----------------------------------------------------------------------------------------

## A scrape along the contact, the way the car was sliding over it.
func _scrape(body_at: Vector3, push_body: Vector3, over: float) -> void:
	var n := _face_normal(body_at)
	var v: Vector3 = car.global_basis.inverse() * car.linear_velocity
	var slide := v - n * v.dot(n)
	if slide.length() < 1.5:
		slide = push_body - n * push_body.dot(n)
		if slide.length() < 0.25:
			return
		slide = slide.normalized() * 1.5
	var u := slide.normalized()
	var length := clampf(0.45 + slide.length() * 0.06 + over * 0.05, 0.4, 2.4)
	var half_w := clampf(0.05 + over * 0.012, 0.05, 0.16)
	var start := body_at - u * length * 0.55
	var to_mesh := dmg._to_mesh
	var ms := dmg._mesh_scale
	var p := to_mesh * start
	var dv := (to_mesh.basis * u).normalized() * length / ms
	var seed := float(absi(hash([_scrape_next, int(body_at.x * 50.0), int(body_at.z * 50.0)])) % 991) / 991.0 * 10.0
	var a := Vector4(p.x, p.y, p.z, half_w / ms)
	var b := Vector4(dv.x, dv.y, dv.z, seed)
	if _scrapes.size() < SCRAPE_CAP:
		_scrapes.append(a)
		_scrape_dir.append(b)
	else:
		_scrapes[_scrape_next] = a
		_scrape_dir[_scrape_next] = b
		_scrape_next = (_scrape_next + 1) % SCRAPE_CAP
	dmg._ensure_paint()
	dmg._mark_dirty()


## The outward normal of the car's box face `p` (body space) lies on.
func _face_normal(p: Vector3) -> Vector3:
	var ext := Vector3(dmg._width * 0.5, (dmg._top - dmg._ride) * 0.5, dmg._len * 0.5)
	var c := Vector3(0.0, (dmg._top + dmg._ride) * 0.5, 0.0)
	var d := p - c
	var best := 0
	var score := -INF
	for a in 3:
		var s := absf(d[a]) / maxf(ext[a], 0.01)
		if s > score:
			score = s
			best = a
	var n := Vector3.ZERO
	n[best] = signf(d[best]) if absf(d[best]) > 1e-4 else 1.0
	return n


# --- Shards from breaking glass and lamps (CarDamage hooks) --------------------------------------------

## A pane fell out (CarDamage._set_pane): its tempered cubes on the road under it.
func pane_fell(world_c: Vector3, lamp: bool) -> void:
	CrashLitter.scatter(car, world_c, car.linear_velocity, CrashLitter.Kind.LENS_CLEAR if lamp else CrashLitter.Kind.GLASS,
			lamp_shards if lamp else pane_shards)


## Lamps broke (CarDamage._break_lamps, bits of CarDamage.LAMP_*).
func lamps_broke(bits: int) -> void:
	var x := dmg._width * 0.5 - 0.3
	var y := dmg._ride + (dmg._top - dmg._ride) * 0.45
	for e: Array in [[CarDamage.LAMP_HEAD_L, -x, -1.0], [CarDamage.LAMP_HEAD_R, x, -1.0], [CarDamage.LAMP_TAIL_L, -x, 1.0], [CarDamage.LAMP_TAIL_R, x, 1.0]]:
		if bits & int(e[0]) == 0:
			continue
		var tail := float(e[2]) > 0.0
		var at := car.global_transform * Vector3(float(e[1]), y, float(e[2]) * dmg._len * 0.5)
		var kind := CrashLitter.Kind.LENS_RED if tail else CrashLitter.Kind.LENS_CLEAR
		CrashLitter.scatter(car, at, car.linear_velocity, kind, lamp_shards)
		# An indicator's amber in with it.
		CrashLitter.scatter(car, at, car.linear_velocity, CrashLitter.Kind.LENS_AMBER, lamp_shards / 4)


# --- Materials and uniforms ---------------------------------------------------------------------------

## The paint, glass and lamps onto their damage shaders and the trim, chrome and far parts onto
## car_part_damage.gdshader, so every part of the body moves together.
func _ensure_materials() -> void:
	dmg._ensure_paint()
	dmg._ensure_glass()
	dmg._ensure_lamps()
	if _parts_done:
		return
	_parts_done = true
	for m in car._body_meshes:
		if not is_instance_valid(m) or m.mesh == null:
			continue
		var nm := String(m.name)
		if nm.begins_with("door_") or nm.begins_with("rig_") or nm.contains("_trailer"):
			continue
		var far := nm.ends_with("_far")
		if m != dmg._mesh and not far:
			continue
		for si in m.mesh.get_surface_count():
			var src := m.mesh.surface_get_material(si) as StandardMaterial3D
			if src == null:
				continue
			var slot := String(src.resource_name)
			var cur := m.get_surface_override_material(si)
			if far and slot == "parts":
				dmg._swap(m, si, _part_material(null, true))
			elif not far and slot in ["trim", "chrome", "ladder"]:
				var std := cur as StandardMaterial3D if cur is StandardMaterial3D else src
				dmg._swap(m, si, _part_material(std, false))
	var det := car.get_node_or_null("CarDetail") as MeshInstance3D
	if det != null:
		detail(car, det)


## The car's plates and badges (CarDetail, built when the car first comes near) onto a copy of
## their material that moves with the crush, once the car has crumpled.
static func detail(c: Vehicle, mi: MeshInstance3D) -> void:
	if c._damage == null or not is_instance_valid(c._damage) or c._damage._crumple == null:
		return
	var cd := c._damage._crumple
	if mi.has_meta("crash_mat"):
		return
	var src := mi.material_override as ShaderMaterial
	var m := ShaderMaterial.new()
	m.shader = DETAIL_SHADER
	if src != null:
		for u in ["plate_lamp", "chrome_metal"]:
			m.set_shader_parameter(u, src.get_shader_parameter(u))
	var xf := cd.dmg._to_mesh
	m.set_shader_parameter("to_mesh", Projection(xf))
	m.set_shader_parameter("from_mesh", Projection(xf.affine_inverse()))
	mi.set_meta("crash_mat", m)
	mi.material_override = m
	cd._detail_mats.append(m)
	cd.push()


func _part_material(src: StandardMaterial3D, far: bool) -> ShaderMaterial:
	var m := ShaderMaterial.new()
	m.shader = PART_SHADER
	m.set_shader_parameter("far", far)
	if src != null:
		m.set_shader_parameter("part_albedo", Color(src.albedo_color.r, src.albedo_color.g, src.albedo_color.b))
		m.set_shader_parameter("part_roughness", src.roughness)
		m.set_shader_parameter("part_metallic", src.metallic)
		m.set_shader_parameter("part_specular", src.metallic_specular)
		m.set_shader_parameter("use_vcol", src.vertex_color_use_as_albedo)
		if src.albedo_texture != null:
			m.set_shader_parameter("part_tex", src.albedo_texture)
			m.set_shader_parameter("has_tex", true)
	_part_mats.append(m)
	return m


## Every material that draws part of the body, for the uniforms.
func _materials() -> Array:
	var out: Array = []
	if dmg._paint != null:
		out.append(dmg._paint)
	if dmg._glass != null:
		out.append(dmg._glass)
	out.append_array(dmg._lamp_mats)
	out.append_array(_part_mats)
	out.append_array(_detail_mats)
	return out


## The crash into the uniforms (from CarDamage._push, once a frame).
func push() -> void:
	var pc := 0
	var c := PackedVector4Array()
	var u := PackedVector4Array()
	var v := PackedVector4Array()
	var w := PackedVector4Array()
	var pv := PackedVector4Array()
	var ax := PackedVector4Array()
	var to_mesh := dmg._to_mesh
	var ms := dmg._mesh_scale
	for i in PANEL_CAP:
		var a: float = _panel_angle[i]
		if absf(a) < 1e-4:
			continue
		var d: Dictionary = _panel_data[i]
		var cc: Vector3 = to_mesh * (d.c as Vector3)
		c.append(Vector4(cc.x, cc.y, cc.z, float(d.m) / ms))
		# (A packed array is a value: each appended by name, never through a list of them.)
		var eu: Vector3 = to_mesh.basis * (d.u as Vector3)
		var ev: Vector3 = to_mesh.basis * (d.v as Vector3)
		var ew: Vector3 = to_mesh.basis * (d.w as Vector3)
		u.append(Vector4(eu.x, eu.y, eu.z, 0.0))
		v.append(Vector4(ev.x, ev.y, ev.z, 0.0))
		w.append(Vector4(ew.x, ew.y, ew.z, 0.0))
		var pp: Vector3 = to_mesh * (d.pivot as Vector3)
		pv.append(Vector4(pp.x, pp.y, pp.z, a))
		var aa: Vector3 = (to_mesh.basis * (d.axis as Vector3)).normalized()
		ax.append(Vector4(aa.x, aa.y, aa.z, 0.0))
		pc += 1
	if OS.get_environment("CRASH_DEBUG") != "":
		print("CRASH %s zones %s panels %s scrapes %d mats %d" % [car.name, str(_zones), str(_panel_angle), _scrapes.size(), _materials().size()])
	# A packed array set for one surface is copied into the material: arrays built once a push.
	var up := (to_mesh.basis * Vector3.UP).normalized()
	for m: ShaderMaterial in _materials():
		m.set_shader_parameter("crumple_count", _crumples.size())
		if not _crumples.is_empty():
			m.set_shader_parameter("crumples", _crumples)
			m.set_shader_parameter("crumple_push", _crumple_push)
			m.set_shader_parameter("crumple_shape", _crumple_shape)
		m.set_shader_parameter("crumple_up", up)
		m.set_shader_parameter("panel_count", pc)
		if pc > 0:
			m.set_shader_parameter("panel_c", c)
			m.set_shader_parameter("panel_u", u)
			m.set_shader_parameter("panel_v", v)
			m.set_shader_parameter("panel_w", w)
			m.set_shader_parameter("panel_pivot", pv)
			m.set_shader_parameter("panel_axis", ax)
	if dmg._paint != null:
		dmg._paint.set_shader_parameter("scrape_count", _scrapes.size())
		if not _scrapes.is_empty():
			dmg._paint.set_shader_parameter("scrapes", _scrapes)
			dmg._paint.set_shader_parameter("scrape_dir", _scrape_dir)


## Puts the wheels back (a cruiser going back into the police pool; CarDamage.restore()).
func reset() -> void:
	for node: Variant in _wheel_was.keys():
		if is_instance_valid(node):
			(node as Node3D).rotation = _wheel_was[node][0]
			(node as Node3D).position.x = (_wheel_was[node][1] as Vector3).x
			(node as Node3D).position.z = (_wheel_was[node][1] as Vector3).z
	_wheel_was.clear()
	var det := car.get_node_or_null("CarDetail") as MeshInstance3D if car != null else null
	if det != null and det.has_meta("crash_mat"):
		det.remove_meta("crash_mat")
		det.material_override = CarDetail.material(car.lights_running())
	_detail_mats.clear()


## Where the crushes moved a mesh-space rest point: the shader's cr_move less its folds, tents
## and panels (the checks).
func move_point(p: Vector3, n: Vector3) -> Vector3:
	var q := p
	for i in _crumples.size():
		var push := Vector3(_crumple_push[i].x, _crumple_push[i].y, _crumple_push[i].z)
		var depth := push.length()
		if depth < 1e-4:
			continue
		var dir := push / depth
		var rel := p - Vector3(_crumples[i].x, _crumples[i].y, _crumples[i].z)
		var s := rel.dot(dir)
		var reach := maxf(_crumple_shape[i].x, depth * 1.3)
		if s > reach:
			continue
		var r := maxf(_crumples[i].w, 0.05)
		var lat := rel - dir * s
		var lr := lat.length() / r
		if lr >= 1.0:
			continue
		var wl := 1.0 - smoothstep(0.35, 1.0, lr)
		var k := clampf(1.0 - s / reach, 0.0, 1.0)
		q += dir * depth * k * k * (3.0 - 2.0 * k) * wl
	return q
