class_name HeliPads
extends RefCounted
## Where the player finds a helicopter to fly (FlyableHeli): a HeliSpot on every pad that has one.
##   - ROOFTOPS: every pad Rooftops parks a helicopter on (HELI_SHARE of the tower pads), its merged
##     mesh the stand-in a real body replaces when the player comes near (rooftop());
##   - the downtown landmark towers' pads (Rooftops.landmark_helipad): half of them, by a hash of
##     the pad, carry a news or private helicopter (landmark());
##   - the HOSPITAL's tower pad: an air ambulance (hospital());
##   - the POLICE HQ (and an air-support third of the other stations): a raised pad on the roof
##     (Rooftops' pad kit) with a police helicopter (station_pad(), police_hq());
##   - the AIRPORT's heliport: painted pads on the east apron, a news and a private helicopter
##     (airport_chunk(), airport_pads()).
## Every pick is a hash of the place, never a chunk or Building rng. HELI_FLYABLE=0 turns it all
## off (`enabled`): no spots, no pads added.
## HeliSpot and FlyableHeli use the autoloads, so they are loaded by path here, never named: this
## file is reached from Rooftops and Airport, which --script tools compile before the autoloads.

static var enabled: bool = OS.get_environment("HELI_FLYABLE") != "0"
const SPOT_SCRIPT := "res://scripts/vehicles/heli_spot.gd"

## The heliport on the east apron, by the hangars (TRUE world XZ, pad centres), and each pad's side (m).
const AIRPORT_PADS := [Vector2(-120.0, 755.0), Vector2(-90.0, 755.0)]
const AIRPORT_PAD := 20.0
## The police HQ's roof pad: deck size (m) at most, and how far it is kept in from the parapet.
const HQ_DECK := 16.0
const HQ_INSET := 3.0
## Share of the ordinary police stations with a roof pad and a helicopter (air support).
const AIR_SUPPORT_SHARE := 0.34

## FlyableHeli.Livery's values (ints here: the classes refer to each other).
const PRIVATE := 0
const POLICE := 1
const NEWS := 2
const MEDICAL := 3

static var _pad_mesh: ArrayMesh


static func airport_pads() -> Array:
	return AIRPORT_PADS


## Rooftops parked a helicopter (its stand-in mesh or nodes) on a tower's pad at `xf` (in `b`'s
## frame).
static func rooftop(b: Node3D, xf: Transform3D, livery: int, stand_in: Node3D) -> void:
	if not enabled or b == null:
		return
	var spot: Variant = _new_spot()
	spot.name = "HeliSpot"
	spot.transform = xf
	spot.livery = PRIVATE
	spot.colors = Rooftops.HELI_LIVERIES[livery % Rooftops.HELI_LIVERIES.size()]
	spot.stand_in = stand_in
	b.add_child(spot)


## A landmark tower's pad (deck top at `deck_top` in `parent`'s frame, turned `turn` quarters):
## half of them, by a hash of where the pad is, get a helicopter.
static func landmark(parent: Node3D, deck_top: Vector3, turn: int) -> void:
	if not enabled or parent == null:
		return
	var h := hash([roundi(deck_top.x), roundi(deck_top.z), "heli_pad"])
	if h % 2 != 0:
		return
	var spot: Variant = _new_spot()
	spot.name = "HeliSpot"
	spot.transform = Transform3D(Basis(Vector3.UP, -PI * 0.5 * float(turn) + PI * 0.25), deck_top)
	spot.livery = NEWS if (h / 2) % 3 == 0 else PRIVATE
	spot.colors = Rooftops.HELI_LIVERIES[(h / 6) % Rooftops.HELI_LIVERIES.size()]
	spot.eager = true
	parent.add_child(spot)


## The hospital's air ambulance, on its tower pad (`at` the deck's centre top in `node`'s frame,
## `nose` the way it faces).
static func hospital(node: Node3D, at: Vector3, nose: Vector3) -> void:
	if not enabled or node == null:
		return
	var spot: Variant = _new_spot()
	spot.name = "HeliSpot"
	spot.transform = Transform3D(Basis(Vector3.UP, atan2(-nose.x, -nose.z)), at)
	spot.livery = MEDICAL
	spot.eager = true
	node.add_child(spot)


## Whether a police station's roof carries a pad: the headquarters always, and an air-support
## share of the others by a hash of the station (`AIR_SUPPORT_SHARE`).
static func station_pad(hq: bool, key: Variant) -> bool:
	return enabled and (hq or float(hash([key, "heli"]) % 1000) / 1000.0 < AIR_SUPPORT_SHARE)


## A raised pad (Rooftops' kit) on the police headquarters' roof with a police helicopter:
## `node` the station's node, `centre` the roof's centre at its top in that frame, `size` the
## roof (along local x, z).
static func police_hq(node: Node3D, centre: Vector3, size: Vector2) -> void:
	if not enabled or not Rooftops.enabled or node == null:
		return
	var deck := floorf(minf(HQ_DECK, minf(size.x, size.y) - HQ_INSET * 2.0))
	if deck < Rooftops.PAD_MIN:
		return
	var statics := StaticBody3D.new()
	statics.name = "HeliPadBody"
	statics.collision_layer = 1
	statics.collision_mask = 0
	node.add_child(statics)
	Rooftops.landmark_helipad(node, centre, [Vector3.ZERO, deck, 0], statics, false)
	var spot: Variant = _new_spot()
	spot.name = "HeliSpot"
	spot.transform = Transform3D(Basis(Vector3.UP, PI * 0.25), centre + Vector3(0.0, Rooftops.PAD_RISE, 0.0))
	spot.livery = POLICE
	spot.eager = true
	node.add_child(spot)


## The airport heliport's pads that fall in a FULL airport chunk: the painted touchdown square,
## its circle and H, and a helicopter on each.
static func airport_chunk(ch: CityChunk, area: Rect2, macro: MacroMap) -> void:
	if not enabled or ch.level != CityChunk.Level.FULL or ch.capturing:
		return
	for i in AIRPORT_PADS.size():
		var p: Vector2 = AIRPORT_PADS[i]
		if not area.has_point(p):
			continue
		var top := macro.tarmac_top
		var mi := MeshInstance3D.new()
		mi.name = "Heliport%d" % i
		mi.mesh = pad_mesh()
		mi.position = Vector3(p.x, top + 0.004, p.y)
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		mi.visibility_range_end = 900.0
		ch.add_child(mi)
		var spot: Variant = _new_spot()
		spot.name = "HeliSpot"
		# Collision under the apron is a box with its top at 0.1 (Airport.build_chunk).
		spot.transform = Transform3D(Basis(Vector3.UP, PI * 0.5), Vector3(p.x, maxf(top, 0.1), p.y))
		spot.livery = NEWS if i == 0 else PRIVATE
		spot.colors = Rooftops.HELI_LIVERIES[1]
		spot.eager = true
		ch.add_child(spot)


## A ground pad's paint (one mesh, cached): a darker concrete square with a yellow border, a
## white aiming circle and the H, flat on the apron (vertex colours, one material).
static func pad_mesh() -> ArrayMesh:
	if _pad_mesh != null:
		return _pad_mesh
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	st.set_normal(Vector3.UP)
	var half := AIRPORT_PAD * 0.5
	var concrete := Color(0.43, 0.43, 0.42)
	var yellow := Color(0.95, 0.72, 0.12)
	var white := Color(0.93, 0.93, 0.9)
	_rect(st, Vector2(-half, -half), Vector2(half, half), 0.0, concrete)
	for e in 4:
		var w := 0.45
		var a: Vector2
		var b: Vector2
		match e:
			0: a = Vector2(-half, -half); b = Vector2(half, -half + w)
			1: a = Vector2(-half, half - w); b = Vector2(half, half)
			2: a = Vector2(-half, -half); b = Vector2(-half + w, half)
			_: a = Vector2(half - w, -half); b = Vector2(half, half)
		_rect(st, a, b, 0.002, yellow)
	var r1 := half * 0.78
	var r0 := r1 - 0.5
	var n := 48
	for k in n:
		var a0 := TAU * float(k) / float(n)
		var a1 := TAU * float(k + 1) / float(n)
		var p00 := Vector3(cos(a0) * r0, 0.003, sin(a0) * r0)
		var p01 := Vector3(cos(a0) * r1, 0.003, sin(a0) * r1)
		var p10 := Vector3(cos(a1) * r0, 0.003, sin(a1) * r0)
		var p11 := Vector3(cos(a1) * r1, 0.003, sin(a1) * r1)
		for q: Vector3 in [p00, p11, p01, p00, p10, p11]:
			st.set_color(white)
			st.add_vertex(q)
	var hh := half * 0.5
	var hw := half * 0.3
	_rect(st, Vector2(-hw, -hh), Vector2(-hw + 0.8, hh), 0.004, white)
	_rect(st, Vector2(hw - 0.8, -hh), Vector2(hw, hh), 0.004, white)
	_rect(st, Vector2(-hw, -0.4), Vector2(hw, 0.4), 0.004, white)
	var mat := StandardMaterial3D.new()
	mat.vertex_color_use_as_albedo = true
	mat.roughness = 0.85
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	st.set_material(mat)
	_pad_mesh = st.commit()
	return _pad_mesh


## A flat rect facing up, wound so its front faces up (counter-clockwise seen from above).
static func _rect(st: SurfaceTool, a: Vector2, b: Vector2, y: float, col: Color) -> void:
	var p00 := Vector3(a.x, y, a.y)
	var p10 := Vector3(b.x, y, a.y)
	var p11 := Vector3(b.x, y, b.y)
	var p01 := Vector3(a.x, y, b.y)
	for q: Vector3 in [p00, p11, p10, p00, p01, p11]:
		st.set_color(col)
		st.add_vertex(q)


static func _new_spot() -> Node3D:
	return (load(SPOT_SCRIPT) as GDScript).new() as Node3D

