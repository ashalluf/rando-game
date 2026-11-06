class_name TacoTruckNight
extends RefCounted
## The taco truck at night, eye level in its queue (fleet wave 8, refcam5 `taco_truck_night` in
## tools/refcams/cameras_w8.json; docs/HANDOFF.md "The taco truck at 23:00"). What the before
## frame gave away, and what this does about each (all from StreetVendors' hooks):
##
## - **Nobody there.** At 23:00 the queue spots stayed empty (walkers are few that late and only
##   `QUEUE_SHARE` of the ones passing stop), and the cook stood 0.9 m behind the serving window,
##   hidden by the jamb from anywhere but square on. A truck now brings its REGULARS: 1-3 people
##   (by the hour and a hash of the truck) waiting at its queue spots (`TacoCustomer`, in the crowd
##   cap like anyone, the spots marked taken), and the cook stands at the counter (`COOK_X`).
## - **The menu board was a white sheet.** The lightbox burned at 2.4 x a near-white face and AgX
##   took it to a flat white card the lettering could barely hold. It burns at `MENU_GLOW` now.
## - **A truck parked in a bike lane** among the delineator posts (Micromobility takes the parking
##   lane for its lane): a face whose stretch carries a bike lane gets no truck (`truck_blocked()`,
##   asked after the truck's roll, so nothing else moves).
## - **A truck parked in a BUS ZONE** on its red kerb, under the stop's plate: a truck whose
##   stretch is a stop's kerb zone is not there either (`truck_in_stop()`, after its roll too).
## - **A dead box at night.** No running lights, no steam off the stack: the truck now carries
##   amber clearance lamps over the cab, red ones at the rear and lit tail lamps (vendor shader
##   code 19, `MARKER_*`), and a plume of steam rising off the extractor stack lit warm from below
##   (`shaders/taco_steam.gdshader`, one mesh a truck, FULL chunks only).
##
## `RC5_TACO=0` is the A/B (the truck as it was).

## Off: the truck as before (the A/B).
static var enabled: bool = OS.get_environment("RC5_TACO") != "0"

## Where the cook stands in the truck (local x; the serving window is at x 1.18, the old spot 0.3).
const COOK_X := 0.62
## How many regulars wait at a truck, by the hour: [from, to, count]; the first match wins, and a
## hash of the truck takes one off half the time (never below one at night).
const REGULARS := [[21.0, 24.0, 3], [0.0, 1.5, 3], [17.5, 21.0, 2], [1.5, 4.0, 1]]
const MAX_REGULARS := 3
## The menu lightbox's night glow (was the shader's 2.4).
const MENU_GLOW := 1.05
## The lit kitchen through the window at night (was 3.2: a white sheet behind the cook).
const INTERIOR_GLOW := 1.7
## The clearance and tail lamps' glow, night and day (vendor shader code 19).
const MARKER_NIGHT := 3.2
const MARKER_DAY := 0.25
## Steam off the stack: draws to this (m).
const STEAM_DRAW := 140.0

static var _steam_mesh: ArrayMesh = null
static var _steam_material: ShaderMaterial = null


## Whether a truck on face `e` (1: +z, 3: +x) of block (ix, iz) would stand in a bike lane.
static func truck_blocked(plan: CityPlan, ix: int, iz: int, e: int) -> bool:
	if not enabled or not Micromobility.enabled:
		return false
	if e == 3:
		return Micromobility.lane_on(plan, CityPlan.AXIS_X, ix + 1, iz)
	return Micromobility.lane_on(plan, CityPlan.AXIS_Z, iz + 1, ix)


## Whether a truck at `t` metres along face `e` of block (ix, iz) would stand in a bus stop's
## kerb zone (the red kerb and the BUS ZONE plate: BigVehicles.in_stop_zone, which the parked cars
## keep out of too). Its middle and both ends are asked.
static func truck_in_stop(plan: CityPlan, ix: int, iz: int, e: int, rect: Rect2, t: float) -> bool:
	if not enabled:
		return false
	var edge: Array = CityChunk._sidewalk_edges(rect)[e]
	var a: Vector2 = edge[0]
	var dir := ((edge[1] as Vector2) - a).normalized()
	var lane: float
	if e == 3:
		lane = plan.road_pos(CityPlan.AXIS_X, ix + 1) - CityPlan.parking_offset(plan.road_width(CityPlan.AXIS_X, ix + 1))
	else:
		lane = plan.road_pos(CityPlan.AXIS_Z, iz + 1) - CityPlan.parking_offset(plan.road_width(CityPlan.AXIS_Z, iz + 1))
	for d: float in [-StreetVendors.TRUCK_HALF, 0.0, StreetVendors.TRUCK_HALF]:
		var kerb := a + dir * (t + d)
		var c := Vector2(lane, kerb.y) if e == 3 else Vector2(kerb.x, lane)
		if BigVehicles.in_stop_zone(plan, c):
			return true
	return false


## How many people wait at this truck at `hour` (`id` the vendor's own id).
static func regular_count(plan_seed: int, id: String, hour: float) -> int:
	if not enabled:
		return 0
	var h := fposmod(hour, 24.0)
	var n := 0
	for r: Array in REGULARS:
		if h >= float(r[0]) and h < float(r[1]):
			n = int(r[2])
			break
	if n > 1 and absi(hash([plan_seed, id, "taco_regulars"])) % 2 == 0:
		n -= 1
	return n


## The regulars' entries for StreetVendors' people list: one per queue spot, the front ones first
## (the spots are appended front pair then back pair, see StreetVendors._place_truck).
static func regulars(plan_seed: int, v: Dictionary, hour: float, queue_from: int, queue: Array, rect: Rect2, record: Dictionary) -> Array:
	var out: Array = []
	var n := mini(regular_count(plan_seed, String(v.id), hour), queue.size() - queue_from)
	for k in n:
		var q: Dictionary = queue[queue_from + k]
		out.append({"at": q.p, "yaw": float(q.yaw), "truck": false, "floor": 0.0, "customer": true,
			"queue": queue_from + k, "seed": hash([plan_seed, String(v.id), "taco_regular", k, rect.position]),
			"record": record, "rect": rect})
	return out


## The steam plume over the extractor stack (truck frame (-0.35, TYT + 0.5, 1.6)).
static func add_steam(chunk: CityChunk, xf: Transform3D, seed_value: float) -> void:
	if not enabled or chunk.level != CityChunk.Level.FULL:
		return
	var mi := MeshInstance3D.new()
	mi.name = "TacoSteam"
	mi.mesh = steam_mesh()
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mi.visibility_range_end = STEAM_DRAW
	var at := xf * Vector3(-0.35, StreetVendors.TYT + 0.5, 1.6)
	mi.position = at + Vector3(0.0, chunk._gy(at.x, at.z), 0.0)
	mi.material_override = steam_material()
	mi.set_meta("taco_seed", seed_value)
	chunk.add_child(mi)


static func steam_material() -> ShaderMaterial:
	if _steam_material == null:
		_steam_material = ShaderMaterial.new()
		_steam_material.shader = load("res://shaders/taco_steam.gdshader")
		_steam_material.set_shader_parameter("puff", WeaponFX.puff_texture())
	return _steam_material


## Twelve camera-facing quads that taco_steam.gdshader places from TIME (UV2.x the slot).
static func steam_mesh() -> ArrayMesh:
	if _steam_mesh != null:
		return _steam_mesh
	var n := 12
	var verts := PackedVector3Array()
	var uvs := PackedVector2Array()
	var uv2s := PackedVector2Array()
	var idx := PackedInt32Array()
	for i in n:
		var base := verts.size()
		for c: Vector2 in [Vector2(0, 0), Vector2(1, 0), Vector2(1, 1), Vector2(0, 1)]:
			verts.append(Vector3.ZERO)
			uvs.append(c)
			uv2s.append(Vector2(float(i) / float(n), 0.0))
		idx.append_array([base, base + 1, base + 2, base, base + 2, base + 3])
	var arr := []
	arr.resize(Mesh.ARRAY_MAX)
	arr[Mesh.ARRAY_VERTEX] = verts
	arr[Mesh.ARRAY_TEX_UV] = uvs
	arr[Mesh.ARRAY_TEX_UV2] = uv2s
	arr[Mesh.ARRAY_INDEX] = idx
	_steam_mesh = ArrayMesh.new()
	_steam_mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arr)
	_steam_mesh.custom_aabb = AABB(Vector3(-3.0, -0.5, -3.0), Vector3(6.0, 6.0, 6.0))
	return _steam_mesh


## Running lights on the truck mesh (StreetVendors.truck()): amber clearance lamps and three ID
## lamps over the cab, red ones at the rear roof corners, and the tail lamps lit (code 19).
static func marker_lamps(st: SurfaceTool) -> void:
	if not enabled:
		return
	var amber := Color(1.0, 0.55, 0.08, 0.95)
	var red := Color(0.95, 0.06, 0.03, 0.95)
	var rm := Vector2(0.2, 0.0)
	var tw := StreetVendors.TW
	var top := StreetVendors.TYT
	var z0 := StreetVendors.TZ0
	var z1 := StreetVendors.TZ1
	for s: float in [-1.0, 1.0]:
		StreetVendors._box(st, Vector3(s * (tw - 0.08), top + 0.035, z0 - 0.01), Vector3(0.09, 0.05, 0.04), 0.01, amber, rm)
		StreetVendors._box(st, Vector3(s * (tw - 0.08), top + 0.035, z1 + 0.01), Vector3(0.09, 0.05, 0.04), 0.01, red, rm)
		# Side markers halfway down the box.
		StreetVendors._box(st, Vector3(s * (tw + 0.01), 1.05, (z0 + z1) * 0.5), Vector3(0.03, 0.05, 0.1), 0.006, amber, rm)
		# The tail lamps, lit (in front of the old dark lenses).
		StreetVendors._box(st, Vector3(s * (tw - 0.12), 1.15, z1 + 0.034), Vector3(0.12, 0.26, 0.012), 0.004, red, rm)
	for k in 3:
		StreetVendors._box(st, Vector3((k - 1) * 0.22, top + 0.035, z0 - 0.01), Vector3(0.08, 0.05, 0.04), 0.01, amber, rm)
