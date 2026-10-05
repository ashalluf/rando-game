class_name StreetFurniture
extends RefCounted
## The pavement furniture Los Angeles actually has, built in code at real size (2026-10-05, fleet
## task "street-furniture"; docs/HANDOFF.md, the street furniture section):
##
## * the squat LA wet-barrel FIRE HYDRANT (a bolted flange, a short barrel, the bonnet with its
##   pentagon nut, a 4" pumper outlet to the street and two 2.5" hose outlets, capped and chained),
##   yellow, silver or a faded white-yellow, chipped and rusting when old;
## * the single-space smart PARKING METER (post on a bolted plate, the grey head with its domed
##   top, display, keypad, card and coin slots, a "pay by app" label and the solar cell) and,
##   one meter in PAY_STATION_SHARE, the PAY STATION (cabinet on a plinth, screen, keypad, card
##   reader, receipt slot, the instruction panel, a solar panel on its mast);
## * the BUS BENCH with a painted ad back beside a third of the bus shelters: cast concrete ends,
##   seat and back rest, the ad (an invented realtor, injury lawyer, bail bonds, dentist, taco
##   stand or "your ad here", 555 numbers; tools/make_bench_ads.py) painted on both faces;
## * the perforated METAL-MESH downtown bin (a TrashCan's mesh downtown and midtown: perforated
##   steel wall you see the liner through, straps, a rain bonnet on four posts);
## * the galvanised inverted-U BIKE RACK on bolted flanges;
## * the precast concrete KERB PLANTER with soil and a shrub.
##
## Every mesh is code at real size (metres, base at the origin, front toward -Z) on ONE shader,
## shaders/street_furniture.gdshader: what a vertex is rides in COLOR.a (`K_*` / 16), its own
## colour in COLOR.rgb (sRGB), UV in metres on the surface (a label or the ad: 0..1 over it).
## Per instance, INSTANCE_CUSTOM is the paint (rgb, sRGB) and the wear (a); the bench's is the
## ad (r * 16) and the wear. Each mesh gets generated LODs and a lighter shadow twin
## (PropFactory._build_shadow_proxy()), so a batch per kind a chunk stays cheap.
##
## Placement is where StreetDetail and CityChunk already put the old pieces: the same calls, ids,
## rolls and collision; only the meshes change (and the hydrant's yaw, which now faces its pumper
## to the street with the rolled spin still drawn). The new pieces - pay stations, the stop
## benches - are hashes of seed + place, never a chunk or block rng; the benches are props with ids
## of their own (`ad_bench_<n>`), so no other prop's id moves. The residential carts are KerbBins'
## (scripts/world/kerb_bins.gd), not ours. STREET_FURNITURE=0 in the environment is the A/B (the
## old meshes everywhere, no pay stations, no stop benches).

## Kinds (COLOR.a = (kind + 0.5) / 16), mirrored by the shader's K_* constants.
const K_PAINT := 0      # cast iron / steel in the instance's paint, chipped and rusting with wear
const K_PAINT_V := 1    # steel in the vertex colour's paint
const K_GALV := 2       # hot-dip galvanised steel
const K_STEEL := 3      # brushed stainless
const K_RUBBER := 4     # rubber and black plastic, vertex colour
const K_CONCRETE := 5   # cast concrete, vertex colour
const K_PERF := 6       # perforated steel in the instance's paint (holes cut by the shader)
const K_LINER := 7      # black bin liner
const K_HDPE := 8       # moulded plastic in the instance's paint
const K_AD := 9         # the bench ad (UV 0..1 over the face)
const K_SCREEN := 10    # LCD display (UV 0..1)
const K_SOIL := 11      # mulch and soil
const K_LABEL := 12     # printed label (UV 0..1; UV2.x the label id)
const K_SOLAR := 13     # solar cell
const K_GLASS := 14     # dark glazing
const K_BRASS := 15     # brass

## Labels (UV2.x) the shader prints.
const L_METER := 0.0
const L_PAYSTATION := 1.0
const L_CART := 2.0
const L_HYDRANT := 3.0

## How many ads the atlas holds (tools/make_bench_ads.py's ADS).
const BENCH_ADS := 8
## Share of metered spaces that are a pay station instead of a meter head.
const PAY_STATION_SHARE := 0.18
## Share of bus shelters that also have a concrete ad bench beside them.
const STOP_BENCH_SHARE := 0.34
## Where it stands from the shelter's spot: this far along the kerb (away from the stop's sign),
## and as far in as the shelter's own bench (behind StreetErrands' queue at the kerb).
const STOP_BENCH_ALONG := 4.2

## LA hydrant paints (sRGB) and their odds: mostly the yellow, some silver, a few faded.
const HYDRANT_PAINTS := [Color(0.80, 0.62, 0.11), Color(0.82, 0.64, 0.10), Color(0.78, 0.6, 0.12), Color(0.70, 0.71, 0.70), Color(0.90, 0.82, 0.52)]
## Meter head paints: the city's dark grey and a silver.
const METER_PAINTS := [Color(0.30, 0.32, 0.34), Color(0.52, 0.54, 0.55), Color(0.24, 0.25, 0.27)]
## Mesh bin paints: black and a deep green.
const BIN_PAINTS := [Color(0.07, 0.075, 0.08), Color(0.08, 0.17, 0.12)]
## Districts where TrashCans are the downtown mesh bin (CityPlan.District order).
const BIN_MESH_DISTRICTS := [CityPlan.District.DOWNTOWN, CityPlan.District.MIDTOWN, CityPlan.District.CAMPUS]
## Draw distances (m).
const SMALL_DRAW_DISTANCE := 140.0

## Off: the old meshes everywhere, no pay stations, no stop benches (the A/B).
static var enabled: bool = OS.get_environment("STREET_FURNITURE") != "0"

static var _meshes: Dictionary = {}
static var _material: ShaderMaterial


# --- Entry points ------------------------------------------------------------------------------

## The hydrant's instances for CityChunk._build_sidewalk_props: `spin` is the rolled yaw (kept
## for an old mesh), `inward` the pavement's way in from the kerb; the new one faces its pumper
## outlet to the street.
static func hydrant_instances(seed: int, aged: bool, spin: float, at: Vector3, inward: Vector2) -> Array:
	if not enabled:
		return [["hydrant_aged" if aged else "hydrant", PropFactory.model_hydrant(aged), Transform3D(Basis(Vector3.UP, spin), at)]]
	var h := _h01([seed, "hydrant", roundi(at.x * 10.0), roundi(at.z * 10.0)])
	var paint: Color = HYDRANT_PAINTS[int(h * HYDRANT_PAINTS.size()) % HYDRANT_PAINTS.size()]
	var wear := (0.55 + 0.4 * _fr(h * 7.31)) if aged else 0.12 * _fr(h * 3.7)
	# The pumper (local -Z) to the street: the street is -inward.
	var yaw := atan2(inward.x, inward.y) + (_fr(h * 13.1) - 0.5) * 0.5
	return [["hydrant_aged" if aged else "hydrant", hydrant(), Transform3D(Basis(Vector3.UP, yaw), at), Color.WHITE, Color(paint.r, paint.g, paint.b, wear)]]


## A metered space's instance for StreetDetail._parking_meters (a meter head, or a pay station).
static func meter_instance(seed: int, at: Vector3, yaw: float, old_mesh: Mesh) -> Array:
	if not enabled:
		return ["meter", old_mesh, Transform3D(Basis(Vector3.UP, yaw), at)]
	var h := _h01([seed, "meter", roundi(at.x * 10.0), roundi(at.z * 10.0)])
	var wear := 0.1 + 0.5 * _fr(h * 5.13)
	if h < PAY_STATION_SHARE:
		var p: Color = Color(0.16, 0.17, 0.18) if _fr(h * 9.7) < 0.6 else Color(0.42, 0.44, 0.45)
		return ["pay_station", pay_station(), Transform3D(Basis(Vector3.UP, yaw), at), Color.WHITE, Color(p.r, p.g, p.b, wear)]
	var paint: Color = METER_PAINTS[int(_fr(h * 3.3) * METER_PAINTS.size()) % METER_PAINTS.size()]
	return ["meter", meter(), Transform3D(Basis(Vector3.UP, yaw), at), Color.WHITE, Color(paint.r, paint.g, paint.b, wear)]


## A bike hoop's mesh (StreetDetail).
static func rack_mesh() -> Mesh:
	return bike_rack() if enabled else PropFactory.bike_rack()


static func rack_custom(seed: int, at: Vector3) -> Color:
	return Color(0.0, 0.0, 0.0, 0.2 + 0.6 * _h01([seed, "rack", roundi(at.x * 10.0), roundi(at.z * 10.0)]))


## A kerb planter's instances (CityChunk._build_clutter): the box, soil and its planting.
static func planter_instances(seed: int, xf: Transform3D) -> Array:
	if not enabled:
		return [["planter", PropFactory.model_planter(), xf]]
	var h := _h01([seed, "planter", roundi(xf.origin.x * 10.0), roundi(xf.origin.z * 10.0)])
	var out := [["planter", planter(), xf, Color.WHITE, Color(0.0, 0.0, 0.0, 0.2 + 0.6 * _fr(h * 11.3))]]
	out.append_array(planting(int(h * PLANTER_PLANTS) % PLANTER_PLANTS, xf, h))
	return out


## How many plantings a planter can have (planter_plant()).
const PLANTER_PLANTS := 5


## A planter's planting, laid in the soil by its own position: ClimbingPlants' accent plants (the
## agave, aloe, red-hot poker, lavender and lantana of LA's drought-tolerant beds) on their own
## shader and atlas, one batch per planting a chunk.
static func planting(pick: int, xf: Transform3D, _h: float) -> Array:
	return [["planter_plant%d" % pick, planter_plant(pick), Transform3D(xf.basis, xf.origin + xf.basis * Vector3(0.0, 0.43, 0.0))]]


static func planter_plant(pick: int) -> Mesh:
	var key := "planter_plant%d" % pick
	if _meshes.has(key):
		return _meshes[key]
	var acc := ClimbingPlants.Acc.new()
	acc.fade = 90.0
	var rng := RandomNumberGenerator.new()
	rng.seed = hash(["planter_plant", pick])
	match pick:
		0:
			ClimbingPlants._rosette(acc, Vector3(0.0, 0.0, 0.0), rng, 20, 0.36, 0.13, ClimbingPlants.C_AGAVE[0], 0.4, 1.3)
			for x in [-0.34, 0.34]:
				ClimbingPlants._rosette(acc, Vector3(x, 0.0, 0.03), rng, 13, 0.17, 0.065, ClimbingPlants.C_ALOE, 0.75, 1.45)
		1:
			for x in [-0.3, 0.0, 0.3]:
				ClimbingPlants._rosette(acc, Vector3(x, 0.0, rng.randf_range(-0.05, 0.05)), rng, 15, 0.22, 0.075, ClimbingPlants.C_ALOE, 0.75, 1.45)
		2:
			for x in [-0.3, 0.0, 0.3]:
				ClimbingPlants._clump(acc, Vector3(x, 0.0, rng.randf_range(-0.04, 0.04)), rng, ClimbingPlants.C_LAVENDER, rng.randf_range(0.36, 0.44), rng.randf_range(0.36, 0.46), 3)
		3:
			for x in [-0.22, 0.22]:
				ClimbingPlants._mound(acc, Vector3(x, 0.0, 0.0), rng, ClimbingPlants.C_LANTANA[int(x > 0.0)], 0.36)
		_:
			ClimbingPlants._clump(acc, Vector3(0.0, 0.0, 0.0), rng, ClimbingPlants.C_STRAPS, 0.5, 0.42, 3)
			for k in 4:
				ClimbingPlants._cross(acc, Vector3(rng.randf_range(-0.12, 0.12), 0.0, rng.randf_range(-0.08, 0.08)), rng, ClimbingPlants.C_POKER, 0.16, rng.randf_range(0.6, 0.8), 2, 1.0)
			for x in [-0.32, 0.32]:
				ClimbingPlants._clump(acc, Vector3(x, 0.0, 0.0), rng, ClimbingPlants.C_LAVENDER, 0.28, 0.32, 3)
	var mesh := acc.mesh(ClimbingPlants.material())
	_meshes[key] = mesh
	return mesh


## Which mesh a TrashCan wears in this district: 1 the downtown mesh bin, 0 the old can.
static func bin_style(district: int) -> int:
	return 1 if enabled and BIN_MESH_DISTRICTS.has(district) else 0


static func bin_custom(at: Vector3) -> Color:
	var h := _h01(["bin", roundi(at.x * 10.0), roundi(at.z * 10.0)])
	var p: Color = BIN_PAINTS[int(h * 2.0) % 2]
	return Color(p.r, p.g, p.b, 0.15 + 0.6 * _fr(h * 7.7))


## A concrete bench with a painted ad beside a third of the bus shelters (StreetDetail.
## _bus_shelter): `at` the shelter's spot, `back` its way in, `along` toward the stop's sign, `yaw`
## as the shelter's (its local -Z toward the buildings). A prop with an id of its own and two seats
## for CrowdLife; kept off whatever stands there already.
static func add_stop_bench(chunk: CityChunk, at: Vector3, back: Vector3, along: Vector3, yaw: float) -> void:
	if not enabled or chunk.level != CityChunk.Level.FULL:
		return
	if _h01([chunk.plan.seed, "stop_bench", roundi(at.x), roundi(at.z)]) >= STOP_BENCH_SHARE:
		return
	var pos := at + back * 0.55 - along * STOP_BENCH_ALONG
	if _blocked(_obstacles(chunk), Vector2(pos.x, pos.z), 1.0):
		return
	var xf := Transform3D(Basis(Vector3.UP, yaw + PI), pos)
	_own_prop(chunk, "ad_bench", pos, Color(0.66, 0.65, 0.62), [ad_bench_instance(chunk.plan.seed, xf)],
		[[Vector3(1.9, 1.1, 0.6), pos + Vector3(0.0, 0.55, 0.0), yaw]])
	if not chunk.prop_records.is_empty() and chunk.prop_records.back().kind == "ad_bench":
		CrowdLife.add_seat(chunk, pos + Vector3(0.0, chunk._gy(pos.x, pos.z), 0.0), yaw + PI, chunk.prop_records.back())


static func ad_bench_instance(seed: int, xf: Transform3D) -> Array:
	var h := _h01([seed, "bench_ad", roundi(xf.origin.x), roundi(xf.origin.z)])
	var ad := int(h * BENCH_ADS) % BENCH_ADS
	return ["ad_bench", ad_bench(), xf, Color.WHITE, Color((float(ad) + 0.5) / 16.0, 0.0, 0.0, 0.15 + 0.6 * _fr(h * 13.7))]


## Points (x, z, radius) of what stands on the pavement already: props and tree grates.
static func _obstacles(chunk: CityChunk) -> Array:
	var out := []
	for r: Dictionary in chunk.prop_records:
		var p: Vector3 = r.position
		out.append(Vector3(p.x, p.z, 0.6))
	var data: Dictionary = chunk._batch.data()
	for key: String in ["tree_grate", "bush", "palm_0", "palm_1", "palm_2"]:
		if data.has(key):
			for x: Transform3D in data[key].xforms:
				out.append(Vector3(x.origin.x, x.origin.z, 1.0))
	return out


static func _blocked(keep: Array, p: Vector2, r: float) -> bool:
	for o: Vector3 in keep:
		var dx := o.x - p.x
		var dz := o.y - p.y
		var rr := o.z + r
		if dx * dx + dz * dz < rr * rr:
			return true
	return false


## CityChunk._add_prop without the chunk's prop counter: the same record, its own id sequence.
static func _own_prop(chunk: CityChunk, kind: String, at: Vector3, color: Color, instances: Array, shapes: Array) -> void:
	var count: int = chunk.get_meta("furniture_props", 0)
	chunk.set_meta("furniture_props", count + 1)
	var id := "%s_%d" % [kind, count]
	if WorldState.is_destroyed(chunk.key, id):
		return
	var g: float = chunk._gy(at.x, at.z)
	var record := {"id": id, "kind": kind, "position": at + Vector3(0.0, g, 0.0), "color": color, "health": 18.0, "instances": [], "shapes": [], "dead": false}
	for inst in instances:
		var index: int = chunk._batch.add(inst[0], inst[1], inst[2], inst[3] if inst.size() > 3 else Color.WHITE, inst[4] if inst.size() > 4 else Color.BLACK)
		record.instances.append([inst[0], index])
	for s in shapes:
		var shape: CollisionShape3D = chunk._add_shape(s[0], s[1] + Vector3(0.0, g, 0.0), s[2])
		if shape:
			shape.set_meta("prop", record)
			record.shapes.append(shape)
	chunk.prop_records.append(record)


# --- The meshes ------------------------------------------------------------------------------

## Builds every mesh now (the loading screen), so no chunk step pays for one; returns the
## materials to draw once through a MultiMesh.
static func warm() -> Array:
	if not enabled:
		return []
	hydrant()
	meter()
	pay_station()
	ad_bench()
	mesh_bin()
	bike_rack()
	planter()
	for i in PLANTER_PLANTS:
		planter_plant(i)
	return [material()]


static func material() -> ShaderMaterial:
	if _material == null:
		_material = ShaderMaterial.new()
		_material.shader = load("res://shaders/street_furniture.gdshader")
		var ads := "res://assets/textures/street_furniture/bench_ads.jpg"
		if ResourceLoader.exists(ads):
			_material.set_shader_parameter("ad_atlas", load(ads))
		_material.set_shader_parameter("ad_rows", float(BENCH_ADS))
	return _material


static func hydrant() -> Mesh:
	if _meshes.has("hydrant"):
		return _meshes.hydrant
	var g := Geo.new()
	var paint := Color.WHITE
	# Flange on the pavement, with its eight bolts.
	g.lathe(Vector3.ZERO, Basis(), [Vector2(0.0, 0.0), Vector2(0.168, 0.0), Vector2(0.168, 0.028), Vector2(0.15, 0.04), Vector2(0.118, 0.052)], 28, paint, K_PAINT, false)
	for i in 8:
		var a := TAU * (float(i) + 0.5) / 8.0
		g.lathe(Vector3(cos(a) * 0.146, 0.04, sin(a) * 0.146), Basis(), [Vector2(0.0, 0.0), Vector2(0.013, 0.0), Vector2(0.013, 0.011), Vector2(0.0, 0.014)], 6, paint, K_PAINT, false)
	# The barrel, a little swelled, the upper band and the bonnet.
	g.lathe(Vector3.ZERO, Basis(), [Vector2(0.112, 0.05), Vector2(0.116, 0.16), Vector2(0.116, 0.30), Vector2(0.112, 0.40), Vector2(0.132, 0.405), Vector2(0.134, 0.445), Vector2(0.124, 0.452), Vector2(0.118, 0.49), Vector2(0.098, 0.535), Vector2(0.066, 0.566), Vector2(0.036, 0.578), Vector2(0.0, 0.58)], 28, paint, K_PAINT, true)
	# The operating nut: a pentagon on a round base.
	g.lathe(Vector3(0.0, 0.575, 0.0), Basis(), [Vector2(0.0, 0.0), Vector2(0.034, 0.0), Vector2(0.034, 0.012), Vector2(0.0, 0.012)], 14, paint, K_PAINT, false)
	g.lathe(Vector3(0.0, 0.586, 0.0), Basis(), [Vector2(0.0, 0.0), Vector2(0.026, 0.0), Vector2(0.026, 0.03), Vector2(0.0, 0.033)], 5, paint, K_PAINT, false)
	# Outlets: the pumper to -Z, the two hose outlets at +-100 degrees off it.
	var outlets := [[0.0, 0.30, 0.062, 0.071, 0.024], [deg_to_rad(100.0), 0.355, 0.044, 0.052, 0.019], [deg_to_rad(-100.0), 0.355, 0.044, 0.052, 0.019]]
	for o in outlets:
		var a: float = o[0]
		var y: float = o[1]
		var r: float = o[2]
		var rc: float = o[3]
		var nut: float = o[4]
		var out := Vector3(-sin(a), 0.0, -cos(a))
		# The lathe's axis (its local +Y) along `out`.
		var b := _axis_basis(out)
		var base := Vector3(0.0, y, 0.0)
		g.lathe(base + out * 0.085, b, [Vector2(0.0, 0.0), Vector2(r + 0.026, 0.0), Vector2(r + 0.026, 0.02), Vector2(r + 0.006, 0.03), Vector2(r, 0.05), Vector2(r, 0.085), Vector2(r + 0.006, 0.09), Vector2(r + 0.006, 0.098)], 20, paint, K_PAINT, true)
		g.lathe(base + out * 0.18, b, [Vector2(0.0, 0.0), Vector2(rc, 0.0), Vector2(rc, 0.034), Vector2(rc - 0.008, 0.042), Vector2(0.0, 0.042)], 20, paint, K_PAINT, false)
		# The cap's ribs (grip lugs) and its pentagon nut.
		for k in 6:
			var ang := TAU * float(k) / 6.0
			var rb := _axis_basis(out)
			var side := rb * Vector3(cos(ang), 0.0, sin(ang))
			g.box(base + out * 0.197 + side * (rc + 0.004), rb * Basis(Vector3.UP, -ang), Vector3(0.008, 0.03, 0.01), paint, K_PAINT)
		g.lathe(base + out * 0.222, b, [Vector2(0.0, 0.0), Vector2(nut, 0.0), Vector2(nut, 0.022), Vector2(0.0, 0.024)], 5, paint, K_PAINT, false)
		# The chain from the cap's lug down to an eye on the barrel.
		var lug := base + out * 0.20 + Vector3(0.0, -rc * 0.7, 0.0)
		var eye := Vector3(0.0, y - 0.09, 0.0) + out * 0.118
		var chain := PackedVector3Array()
		for k in 7:
			var f := float(k) / 6.0
			chain.append(lug.lerp(eye, f) + Vector3(0.0, -0.03 * sin(f * PI), 0.0))
		g.tube(chain, 0.0045, 5, Color(0.55, 0.55, 0.53), K_STEEL)
	# Stem bosses over the hose outlets (a wet barrel's own valves) and the stencilled tag.
	for a in [deg_to_rad(100.0), deg_to_rad(-100.0)]:
		var out := Vector3(-sin(a), 0.0, -cos(a))
		g.lathe(Vector3(0.0, 0.43, 0.0) + out * 0.118, _axis_basis(out), [Vector2(0.0, 0.0), Vector2(0.026, 0.0), Vector2(0.026, 0.03), Vector2(0.018, 0.04), Vector2(0.0, 0.04)], 10, paint, K_PAINT, false)
		g.lathe(Vector3(0.0, 0.43, 0.0) + out * 0.158, _axis_basis(out), [Vector2(0.0, 0.0), Vector2(0.016, 0.0), Vector2(0.016, 0.018), Vector2(0.0, 0.02)], 5, paint, K_PAINT, false)
	g.label_curved(Vector3.ZERO, 0.1175, PI * 0.5, 0.07, 0.19, 0.25, L_HYDRANT)
	return _finish("hydrant", g)


static func meter() -> Mesh:
	if _meshes.has("meter"):
		return _meshes.meter
	var g := Geo.new()
	var post := Color(0.12, 0.125, 0.13)
	var paint := Color.WHITE
	# Base plate, bolts, the post and its collar.
	g.box(Vector3(0.0, 0.006, 0.0), Basis(), Vector3(0.16, 0.012, 0.16), post, K_PAINT_V)
	for i in 4:
		var sx := 1.0 if i % 2 == 0 else -1.0
		var sz := 1.0 if i < 2 else -1.0
		g.lathe(Vector3(sx * 0.058, 0.012, sz * 0.058), Basis(), [Vector2(0.0, 0.0), Vector2(0.011, 0.0), Vector2(0.011, 0.008), Vector2(0.0, 0.01)], 6, Color(0.5, 0.5, 0.5), K_GALV, false)
	g.lathe(Vector3.ZERO, Basis(), [Vector2(0.0, 0.012), Vector2(0.044, 0.012), Vector2(0.044, 0.05), Vector2(0.038, 0.06), Vector2(0.038, 1.0), Vector2(0.05, 1.005), Vector2(0.05, 1.07), Vector2(0.0, 1.07)], 14, post, K_PAINT_V, true)
	# The head: a housing with a domed top.
	var hw := 0.2
	var hd := 0.165
	g.cbox(Vector3(0.0, 1.07, 0.0), Basis(), Vector3(hw, 0.27, hd), 0.018, paint, K_PAINT)
	# The dome: a half cylinder along x.
	g.lathe(Vector3(-hw * 0.5, 1.34, 0.0), Basis(Vector3(0, 0, 1), -PI * 0.5), [Vector2(0.0, 0.0), Vector2(hd * 0.5, 0.0), Vector2(hd * 0.5, hw), Vector2(0.0, hw)], 18, paint, K_PAINT, true, PI, PI * 0.5)
	# The front: a darker bezel, the display, the keypad, the card and coin slots, the label.
	var f := -hd * 0.5 - 0.004
	g.box(Vector3(0.0, 1.27, f + 0.002), Basis(), Vector3(0.16, 0.11, 0.008), Color(0.05, 0.05, 0.055), K_RUBBER)
	g.panel(Vector3(0.0, 1.275, f - 0.003), Vector2(0.12, 0.065), Vector3(0, 0, -1), K_SCREEN, Color.WHITE, 0.0)
	for i in 4:
		g.box(Vector3(-0.045 + 0.03 * float(i), 1.205, f + 0.001), Basis(), Vector3(0.022, 0.016, 0.012), Color(0.14, 0.42, 0.62) if i == 3 else Color(0.08, 0.08, 0.085), K_RUBBER)
	g.box(Vector3(0.05, 1.165, f + 0.001), Basis(), Vector3(0.05, 0.022, 0.014), Color(0.03, 0.03, 0.03), K_RUBBER)
	g.box(Vector3(-0.045, 1.165, f + 0.001), Basis(), Vector3(0.012, 0.03, 0.012), Color(0.62, 0.6, 0.55), K_STEEL)
	g.panel(Vector3(0.0, 1.115, f - 0.001), Vector2(0.15, 0.05), Vector3(0, 0, -1), K_LABEL, Color.WHITE, L_METER)
	# The solar cell on the dome, tilted to the sky.
	g.box(Vector3(0.0, 1.425, 0.01), Basis(Vector3.RIGHT, -0.5), Vector3(0.15, 0.012, 0.1), Color(0.1, 0.1, 0.1), K_PAINT_V)
	g.panel(Vector3(0.0, 1.4315, 0.0068), Vector2(0.135, 0.085), Basis(Vector3.RIGHT, -0.5) * Vector3.UP, K_SOLAR, Color.WHITE, 0.0, Basis(Vector3.RIGHT, -0.5) * Vector3(0, 0, -1))
	# The back: a door with a lock.
	g.box(Vector3(0.0, 1.2, hd * 0.5 + 0.002), Basis(), Vector3(0.15, 0.2, 0.006), paint, K_PAINT)
	g.lathe(Vector3(0.0, 1.25, hd * 0.5 + 0.005), _axis_basis(Vector3(0, 0, 1)), [Vector2(0.0, 0.0), Vector2(0.011, 0.0), Vector2(0.011, 0.01), Vector2(0.0, 0.01)], 10, Color(0.7, 0.68, 0.6), K_BRASS, false)
	return _finish("meter", g)


static func pay_station() -> Mesh:
	if _meshes.has("pay_station"):
		return _meshes.pay_station
	var g := Geo.new()
	var paint := Color.WHITE
	var conc := Color(0.66, 0.65, 0.62)
	g.cbox(Vector3(0.0, 0.0, 0.0), Basis(), Vector3(0.52, 0.06, 0.42), 0.012, conc, K_CONCRETE)
	# The cabinet, with a sloped head.
	g.cbox(Vector3(0.0, 0.06, 0.0), Basis(), Vector3(0.42, 1.12, 0.3), 0.02, paint, K_PAINT)
	var head := PackedVector2Array([Vector2(-0.15, 0.0), Vector2(0.15, 0.0), Vector2(0.15, 0.46), Vector2(-0.15, 0.36)])
	g.extrude(head, 0.42, Vector3(-0.21, 1.18, 0.0), _profile_basis(), paint, K_PAINT)
	# Front (-Z): the screen in its bezel, keypad, card reader, coin slot, receipt slot.
	var f := -0.15
	g.box(Vector3(0.0, 1.4, f - 0.01), Basis(Vector3.RIGHT, 0.0), Vector3(0.3, 0.2, 0.012), Color(0.05, 0.05, 0.05), K_RUBBER)
	g.panel(Vector3(0.0, 1.405, f - 0.017), Vector2(0.2, 0.14), Vector3(0, 0, -1), K_SCREEN, Color.WHITE, 1.0)
	for row in 4:
		for col in 3:
			g.box(Vector3(-0.045 + 0.045 * float(col), 1.24 - 0.04 * float(row), f - 0.006), Basis(), Vector3(0.034, 0.028, 0.012), Color(0.62, 0.63, 0.64), K_STEEL)
	g.box(Vector3(0.12, 1.2, f - 0.02), Basis(), Vector3(0.09, 0.12, 0.04), Color(0.06, 0.06, 0.06), K_RUBBER)
	g.box(Vector3(0.12, 1.2, f - 0.041), Basis(), Vector3(0.07, 0.006, 0.004), Color(0.25, 0.75, 0.3), K_SCREEN)
	g.box(Vector3(-0.13, 1.18, f - 0.008), Basis(), Vector3(0.05, 0.08, 0.016), Color(0.62, 0.6, 0.56), K_STEEL)
	g.box(Vector3(0.0, 1.07, f - 0.012), Basis(), Vector3(0.12, 0.02, 0.024), Color(0.05, 0.05, 0.05), K_RUBBER)
	g.panel(Vector3(0.0, 0.8, f - 0.001), Vector2(0.32, 0.4), Vector3(0, 0, -1), K_LABEL, Color.WHITE, L_PAYSTATION)
	# Lower door seam and lock.
	g.box(Vector3(0.0, 0.53, f - 0.001), Basis(), Vector3(0.36, 0.006, 0.004), Color(0.04, 0.04, 0.04), K_RUBBER)
	g.lathe(Vector3(0.15, 0.4, f - 0.001), _axis_basis(Vector3(0, 0, -1)), [Vector2(0.0, 0.0), Vector2(0.013, 0.0), Vector2(0.013, 0.012), Vector2(0.0, 0.012)], 10, Color(0.7, 0.68, 0.6), K_BRASS, false)
	# The solar panel on its mast.
	g.lathe(Vector3(0.0, 1.6, 0.06), Basis(), [Vector2(0.0, 0.0), Vector2(0.025, 0.0), Vector2(0.025, 0.42), Vector2(0.0, 0.42)], 10, Color(0.15, 0.15, 0.16), K_PAINT_V, true)
	var tilt := Basis(Vector3.RIGHT, -0.55)
	g.box(Vector3(0.0, 2.03, 0.06), tilt, Vector3(0.5, 0.025, 0.34), Color(0.18, 0.18, 0.19), K_PAINT_V)
	g.panel(Vector3(0.0, 2.03, 0.06) + tilt * Vector3(0.0, 0.0135, 0.0), Vector2(0.47, 0.31), tilt * Vector3.UP, K_SOLAR, Color.WHITE, 0.0, tilt * Vector3(0, 0, -1))
	# A blue "P" plate on the mast.
	g.box(Vector3(0.0, 1.78, 0.03), Basis(), Vector3(0.2, 0.2, 0.01), Color(0.1, 0.3, 0.66), K_PAINT_V)
	g.panel(Vector3(0.0, 1.78, 0.024), Vector2(0.18, 0.18), Vector3(0, 0, -1), K_LABEL, Color.WHITE, L_PAYSTATION + 4.0)
	return _finish("pay_station", g)


## The bus bench: 1.86 m long, seat at 0.45 m, facing -Z, the ad on the back rest's two faces.
static func ad_bench() -> Mesh:
	if _meshes.has("ad_bench"):
		return _meshes.ad_bench
	var g := Geo.new()
	var conc := Color(0.71, 0.70, 0.67)
	# The two ends: an L in profile (z, y), 0.12 m thick, extruded along x.
	var lean := 0.17
	var end := PackedVector2Array([Vector2(-0.24, 0.0), Vector2(0.24, 0.0), Vector2(0.27 + lean, 1.06), Vector2(0.16 + lean, 1.06), Vector2(0.12, 0.43), Vector2(-0.24, 0.39)])
	for sx in [-0.85, 0.85]:
		g.extrude(end, 0.12, Vector3(sx - 0.06, 0.0, 0.0), _profile_basis(), conc, K_CONCRETE)
	# The seat slab, its edges rounded over (a profile in (z, y) run the bench's length).
	g.extrude(_rrect(0.46, 0.068, 0.026, 3), 1.86, Vector3(-0.93, 0.424, -0.03), _profile_basis(), conc, K_CONCRETE)
	# The back rest, leaning back on the ends, its edges rounded too.
	var tilt := atan2(lean, 0.63)
	var back_basis := Basis(Vector3.RIGHT, tilt)
	var bc := Vector3(0.0, 0.79, 0.15 + lean * 0.58)
	var prof := PackedVector2Array()
	for q in _rrect(0.075, 0.58, 0.022, 3):
		prof.append(Vector2(q.x * cos(tilt) + q.y * sin(tilt), -q.x * sin(tilt) + q.y * cos(tilt)))
	g.extrude(prof, 1.84, Vector3(-0.92, bc.y, bc.z), _profile_basis(), conc, K_CONCRETE)
	# Bolt heads where the back rest meets each end.
	for sx in [-0.86, 0.86]:
		for dy in [-0.14, 0.14]:
			var bp := bc + back_basis * Vector3(0.0, dy, 0.0)
			g.lathe(Vector3(sx + signf(sx) * 0.06, bp.y, bp.z), Basis(Vector3(0, 0, 1), -PI * 0.5 * signf(sx)), [Vector2(0.0, 0.0), Vector2(0.016, 0.0), Vector2(0.016, 0.008), Vector2(0.0, 0.01)], 6, Color(0.4, 0.38, 0.35), K_GALV, false)
	var front := back_basis * Vector3(0, 0, -1)
	g.panel(bc + back_basis * Vector3(0.0, 0.0, -0.0385), Vector2(1.76, 0.52), front, K_AD, Color.WHITE, 0.0, back_basis * Vector3.UP)
	g.panel(bc + back_basis * Vector3(0.0, 0.0, 0.0385), Vector2(1.76, 0.52), -front, K_AD, Color.WHITE, 1.0, back_basis * Vector3.UP)
	return _finish("ad_bench", g)


## The downtown perforated bin: 0.62 m across, 1.0 m tall, base at the origin.
static func mesh_bin() -> Mesh:
	if _meshes.has("mesh_bin"):
		return _meshes.mesh_bin
	var g := Geo.new()
	var paint := Color.WHITE
	var r := 0.3
	# Base ring and feet.
	g.lathe(Vector3.ZERO, Basis(), [Vector2(0.0, 0.012), Vector2(r + 0.01, 0.012), Vector2(r + 0.01, 0.07), Vector2(r - 0.004, 0.075), Vector2(0.0, 0.075)], 32, paint, K_PAINT, false)
	for i in 4:
		var a := TAU * (float(i) + 0.5) / 4.0
		g.box(Vector3(cos(a) * (r - 0.03), 0.006, sin(a) * (r - 0.03)), Basis(Vector3.UP, -a), Vector3(0.08, 0.012, 0.05), Color(0.05, 0.05, 0.05), K_RUBBER)
	# The perforated wall, both faces (the holes line up), and the liner inside it.
	g.lathe(Vector3.ZERO, Basis(), [Vector2(r, 0.075), Vector2(r, 0.8)], 40, paint, K_PERF, true)
	g.lathe(Vector3.ZERO, Basis(), [Vector2(r - 0.003, 0.8), Vector2(r - 0.003, 0.075)], 40, paint, K_PERF, true)
	g.lathe(Vector3.ZERO, Basis(), [Vector2(0.0, 0.09), Vector2(r - 0.04, 0.09), Vector2(r - 0.032, 0.3), Vector2(r - 0.03, 0.6), Vector2(r - 0.028, 0.8), Vector2(r - 0.01, 0.862), Vector2(r + 0.004, 0.873), Vector2(r + 0.019, 0.863), Vector2(r + 0.021, 0.83)], 24, Color(0.05, 0.05, 0.055), K_LINER, true)
	# Its other face: the inside of the bag and the fold's top over the rim, down to the rubbish.
	g.lathe(Vector3.ZERO, Basis(), [Vector2(r + 0.021, 0.83), Vector2(r + 0.019, 0.863), Vector2(r + 0.004, 0.873), Vector2(r - 0.01, 0.862), Vector2(r - 0.028, 0.8), Vector2(r - 0.034, 0.6), Vector2(r - 0.038, 0.45), Vector2(0.0, 0.45)], 24, Color(0.035, 0.035, 0.04), K_LINER, true)
	# Straps up the wall.
	for i in 4:
		var a := TAU * float(i) / 4.0
		var out := Vector3(cos(a), 0.0, sin(a))
		g.box(out * (r + 0.005) + Vector3(0.0, 0.44, 0.0), Basis(Vector3.UP, -a + PI * 0.5), Vector3(0.04, 0.74, 0.01), paint, K_PAINT)
	# The rim, four posts and the rain bonnet over the opening.
	g.lathe(Vector3.ZERO, Basis(), [Vector2(r - 0.004, 0.8), Vector2(r + 0.012, 0.8), Vector2(r + 0.012, 0.86), Vector2(r - 0.01, 0.86)], 40, paint, K_PAINT, false)
	for i in 4:
		var a := TAU * (float(i) + 0.5) / 4.0
		g.box(Vector3(cos(a) * (r + 0.002), 0.915, sin(a) * (r + 0.002)), Basis(Vector3.UP, -a), Vector3(0.018, 0.11, 0.04), paint, K_PAINT)
	g.lathe(Vector3.ZERO, Basis(), [Vector2(r + 0.03, 0.965), Vector2(r + 0.03, 0.985), Vector2(r - 0.02, 1.01), Vector2(r * 0.6, 1.045), Vector2(0.0, 1.055)], 40, paint, K_PAINT, true)
	g.lathe(Vector3.ZERO, Basis(), [Vector2(0.0, 0.965), Vector2(r + 0.03, 0.965)], 40, paint, K_PAINT, false)
	return _finish("mesh_bin", g)


## The galvanised inverted-U hoop, 0.6 m wide and 0.9 m tall, on two bolted flanges; its plane is
## local XY (StreetDetail's row stands along the kerb).
static func bike_rack() -> Mesh:
	if _meshes.has("bike_rack"):
		return _meshes.bike_rack
	var g := Geo.new()
	var steel := Color(0.78, 0.79, 0.8)
	var w := 0.3
	var pr := 0.18
	var path := PackedVector3Array()
	path.append(Vector3(-w, 0.008, 0.0))
	path.append(Vector3(-w, 0.36, 0.0))
	path.append(Vector3(-w, 0.9 - pr - 0.024, 0.0))
	# Round the two corners (radius pr) and across the top.
	for i in range(0, 9):
		var a := PI * 0.5 * float(i) / 8.0
		path.append(Vector3(-w + pr - pr * cos(a), 0.9 - 0.024 - pr + pr * sin(a), 0.0))
	for i in range(0, 9):
		var a := PI * 0.5 + PI * 0.5 * float(i) / 8.0
		path.append(Vector3(w - pr - pr * cos(a), 0.9 - 0.024 - pr + pr * sin(a), 0.0))
	path.append(Vector3(w, 0.36, 0.0))
	path.append(Vector3(w, 0.008, 0.0))
	g.tube(path, 0.024, 10, steel, K_GALV)
	# End caps welded on, the flanges and their anchor bolts.
	for sx in [-w, w]:
		g.lathe(Vector3(sx, 0.0, 0.0), Basis(), [Vector2(0.0, 0.0), Vector2(0.07, 0.0), Vector2(0.07, 0.008), Vector2(0.03, 0.012), Vector2(0.0, 0.012)], 16, steel, K_GALV, false)
		for k in 3:
			var a := TAU * float(k) / 3.0 + 0.4
			g.lathe(Vector3(sx + cos(a) * 0.05, 0.008, sin(a) * 0.05), Basis(), [Vector2(0.0, 0.0), Vector2(0.01, 0.0), Vector2(0.01, 0.01), Vector2(0.0, 0.012)], 6, steel, K_GALV, false)
	return _finish("bike_rack", g)


## The precast kerb planter: 1.0 x 0.5 m, 0.48 m tall, soil 5 cm under the rim.
static func planter() -> Mesh:
	if _meshes.has("planter"):
		return _meshes.planter
	var g := Geo.new()
	var conc := Color(0.72, 0.71, 0.68)
	var foot := _rrect(0.92, 0.42, 0.02, 2)
	var body := _rrect(0.98, 0.48, 0.03, 2)
	var rim := _rrect(1.02, 0.52, 0.03, 2)
	var inner := _rrect(0.88, 0.38, 0.02, 2)
	g.loft(foot, 0.0, Vector3.ZERO, foot, 0.04, Vector3.ZERO, conc, K_CONCRETE)
	g.loft(foot, 0.04, Vector3.ZERO, body, 0.06, Vector3.ZERO, conc, K_CONCRETE)
	g.loft(body, 0.06, Vector3.ZERO, body, 0.4, Vector3.ZERO, conc, K_CONCRETE)
	g.loft(body, 0.4, Vector3.ZERO, rim, 0.415, Vector3.ZERO, conc, K_CONCRETE)
	g.loft(rim, 0.415, Vector3.ZERO, rim, 0.47, Vector3.ZERO, conc, K_CONCRETE)
	g.loft(rim, 0.47, Vector3.ZERO, inner, 0.48, Vector3.ZERO, conc, K_CONCRETE)
	g.loft(inner, 0.48, Vector3.ZERO, inner, 0.43, Vector3.ZERO, conc, K_CONCRETE, true)
	g.cap(inner, 0.43, Vector3.ZERO, true, Color(0.2, 0.15, 0.11), K_SOIL)
	# A reveal line round the body.
	g.loft(_rrect(0.985, 0.485, 0.03, 2), 0.2, Vector3.ZERO, _rrect(0.985, 0.485, 0.03, 2), 0.215, Vector3.ZERO, Color(0.8, 0.8, 0.8), K_CONCRETE)
	return _finish("planter", g)


# --- Building helpers ------------------------------------------------------------------------

static func _finish(key: String, g: Geo) -> Mesh:
	var im := ImporterMesh.new()
	im.add_surface(Mesh.PRIMITIVE_TRIANGLES, g.arrays(), [], {}, material(), key)
	im.generate_lods(25.0, 60.0, [])
	var mesh: ArrayMesh = im.get_mesh()
	PropFactory._build_shadow_proxy(im, mesh)
	_meshes[key] = mesh
	return mesh


## A basis whose +Y is `dir`.
static func _axis_basis(dir: Vector3) -> Basis:
	var y := dir.normalized()
	var ref := Vector3.UP if absf(y.dot(Vector3.UP)) < 0.95 else Vector3.RIGHT
	var x := ref.cross(y).normalized()
	var z := x.cross(y).normalized()
	return Basis(x, y, z)


## Maps a profile drawn in (z, y) and extruded along +x.
static func _profile_basis() -> Basis:
	return Basis(Vector3(0, 0, 1), Vector3(0, 1, 0), Vector3(1, 0, 0))


## A rounded rectangle w x d (x, z), corner radius r, `seg` segments a corner, counter-clockwise
## seen from above (+Y), starting at +x.
static func _rrect(w: float, d: float, r: float, seg: int) -> PackedVector2Array:
	var out := PackedVector2Array()
	var cx := w * 0.5 - r
	var cz := d * 0.5 - r
	var centres := [Vector2(cx, cz), Vector2(-cx, cz), Vector2(-cx, -cz), Vector2(cx, -cz)]
	for c in 4:
		for i in seg + 1:
			var a := PI * 0.5 * float(c) + PI * 0.5 * float(i) / float(seg)
			out.append(centres[c] + Vector2(cos(a), sin(a)) * r)
	return out


static func _fr(x: float) -> float:
	return x - floorf(x)


static func _h01(parts: Array) -> float:
	return float(absi(hash(parts)) % 100003) * (1.0 / 100003.0)


## The mesh writer: positions, normals, colours (rgb paint, a kind), UV (metres or 0..1) and UV2
## (x: label id or side, y: 0).
class Geo extends RefCounted:
	var v := PackedVector3Array()
	var n := PackedVector3Array()
	var c := PackedColorArray()
	var uv := PackedVector2Array()
	var uv2 := PackedVector2Array()
	var idx := PackedInt32Array()

	func arrays() -> Array:
		var a := []
		a.resize(Mesh.ARRAY_MAX)
		a[Mesh.ARRAY_VERTEX] = v
		a[Mesh.ARRAY_NORMAL] = n
		a[Mesh.ARRAY_COLOR] = c
		a[Mesh.ARRAY_TEX_UV] = uv
		a[Mesh.ARRAY_TEX_UV2] = uv2
		a[Mesh.ARRAY_INDEX] = idx
		return a

	func vert(p: Vector3, nn: Vector3, col: Color, kind: int, t: Vector2, t2: Vector2 = Vector2.ZERO) -> int:
		v.append(p)
		n.append(nn.normalized())
		c.append(Color(col.r, col.g, col.b, (float(kind) + 0.5) / 16.0))
		uv.append(t)
		uv2.append(t2)
		return v.size() - 1

	## A triangle of existing vertices, wound so its front faces `facing` (Godot: clockwise from
	## the front).
	func tri(a: int, b: int, cc: int, facing: Vector3) -> void:
		var fn := (v[b] - v[a]).cross(v[cc] - v[a])
		if fn.dot(facing) > 0.0:
			idx.append_array([a, cc, b])
		else:
			idx.append_array([a, b, cc])

	func quad(p0: Vector3, p1: Vector3, p2: Vector3, p3: Vector3, nn: Vector3, col: Color, kind: int, t0: Vector2, t1: Vector2, t2: Vector2, t3: Vector2, u2: Vector2 = Vector2.ZERO) -> void:
		var a := vert(p0, nn, col, kind, t0, u2)
		var b := vert(p1, nn, col, kind, t1, u2)
		var cc := vert(p2, nn, col, kind, t2, u2)
		var d := vert(p3, nn, col, kind, t3, u2)
		tri(a, b, cc, nn)
		tri(a, cc, d, nn)

	## A box centred at `centre` (size along the basis axes), UV in metres per face.
	func box(centre: Vector3, b: Basis, size: Vector3, col: Color, kind: int) -> void:
		var h := size * 0.5
		var faces := [[Vector3.RIGHT, Vector3.UP, Vector3.BACK], [Vector3.LEFT, Vector3.UP, Vector3.FORWARD], [Vector3.UP, Vector3.BACK, Vector3.RIGHT], [Vector3.DOWN, Vector3.FORWARD, Vector3.RIGHT], [Vector3.BACK, Vector3.UP, Vector3.LEFT], [Vector3.FORWARD, Vector3.UP, Vector3.RIGHT]]
		for f in faces:
			var nn: Vector3 = f[0]
			var up: Vector3 = f[1]
			var side: Vector3 = f[2]
			var cn := nn * h
			var hu := absf(up.dot(h))
			var hs := absf(side.dot(h))
			var corners := [cn - side * hs - up * hu, cn + side * hs - up * hu, cn + side * hs + up * hu, cn - side * hs + up * hu]
			var pw := []
			for k in 4:
				pw.append(centre + b * corners[k])
			quad(pw[0], pw[1], pw[2], pw[3], b * nn, col, kind, Vector2(0.0, 0.0), Vector2(hs * 2.0, 0.0), Vector2(hs * 2.0, hu * 2.0), Vector2(0.0, hu * 2.0))

	## A box standing on `base` (its bottom centre) with its vertical edges chamfered by `ch`.
	func cbox(base: Vector3, b: Basis, size: Vector3, ch: float, col: Color, kind: int) -> void:
		var hx := size.x * 0.5
		var hz := size.z * 0.5
		var o := PackedVector2Array([Vector2(hx, -hz + ch), Vector2(hx, hz - ch), Vector2(hx - ch, hz), Vector2(-hx + ch, hz), Vector2(-hx, hz - ch), Vector2(-hx, -hz + ch), Vector2(-hx + ch, -hz), Vector2(hx - ch, -hz)])
		prism(o, base, b, size.y, col, kind)

	## A vertical prism: outline (x, z) counter-clockwise seen from above, from base.y to + height.
	func prism(o: PackedVector2Array, base: Vector3, b: Basis, height: float, col: Color, kind: int) -> void:
		var run := 0.0
		for i in o.size():
			var p := o[i]
			var q := o[(i + 1) % o.size()]
			var e := q - p
			var nn := b * Vector3(e.y, 0.0, -e.x).normalized()
			var l := e.length()
			quad(base + b * Vector3(p.x, 0.0, p.y), base + b * Vector3(q.x, 0.0, q.y), base + b * Vector3(q.x, height, q.y), base + b * Vector3(p.x, height, p.y), nn, col, kind, Vector2(run, 0.0), Vector2(run + l, 0.0), Vector2(run + l, height), Vector2(run, height))
			run += l
		_fan(o, base + b * Vector3(0.0, height, 0.0), b, b * Vector3.UP, col, kind)
		_fan(o, base, b, b * Vector3.DOWN, col, kind)

	func _fan(o: PackedVector2Array, at: Vector3, b: Basis, nn: Vector3, col: Color, kind: int) -> void:
		var centre := Vector2.ZERO
		for p in o:
			centre += p
		centre /= float(o.size())
		var ci := vert(at + b * Vector3(centre.x, 0.0, centre.y), nn, col, kind, centre)
		var first := v.size()
		for p in o:
			vert(at + b * Vector3(p.x, 0.0, p.y), nn, col, kind, p)
		for i in o.size():
			tri(ci, first + i, first + (i + 1) % o.size(), nn)

	## An outline in a plane (u, v) extruded `depth` along the frame's w: the frame is `b` (its
	## x is u, y is v, z is w) at `origin`.
	func extrude(o: PackedVector2Array, depth: float, origin: Vector3, b: Basis, col: Color, kind: int) -> void:
		var area := 0.0
		for i in o.size():
			var p := o[i]
			var q := o[(i + 1) % o.size()]
			area += p.x * q.y - q.x * p.y
		var s := 1.0 if area > 0.0 else -1.0
		var run := 0.0
		for i in o.size():
			var p := o[i]
			var q := o[(i + 1) % o.size()]
			var e := q - p
			var nn := b * Vector3(e.y * s, -e.x * s, 0.0).normalized()
			var l := e.length()
			quad(origin + b * Vector3(p.x, p.y, 0.0), origin + b * Vector3(q.x, q.y, 0.0), origin + b * Vector3(q.x, q.y, depth), origin + b * Vector3(p.x, p.y, depth), nn, col, kind, Vector2(run, 0.0), Vector2(run + l, 0.0), Vector2(run + l, depth), Vector2(run, depth))
			run += l
		for side in 2:
			var nn := b * Vector3(0.0, 0.0, -1.0 if side == 0 else 1.0)
			var first := v.size()
			for p in o:
				vert(origin + b * Vector3(p.x, p.y, depth * float(side)), nn, col, kind, p)
			var tris := Geometry2D.triangulate_polygon(o)
			for i in range(0, tris.size(), 3):
				tri(first + tris[i], first + tris[i + 1], first + tris[i + 2], nn)

	## Revolves `profile` (r, y) about the frame's +Y at `origin`; smooth normals round and along
	## when `smooth`, flat bands otherwise. `sweep` < TAU leaves an open arc (a dome's half).
	func lathe(origin: Vector3, b: Basis, profile: Array, sides: int, col: Color, kind: int, smooth: bool, sweep: float = TAU, start: float = 0.0) -> void:
		var closed := sweep >= TAU - 0.001
		if sides <= 8 and closed:
			_facets(origin, b, profile, sides, col, kind)
			return
		var cols := sides + (0 if closed else 1)
		for i in profile.size() - 1:
			var p0: Vector2 = profile[i]
			var p1: Vector2 = profile[i + 1]
			if p0.distance_to(p1) < 1e-6:
				continue
			var e := p1 - p0
			# Outward normal of the segment in the (r, y) half plane.
			var sn := Vector2(e.y, -e.x).normalized()
			var n0 := sn
			var n1 := sn
			if smooth:
				if i > 0:
					var ep: Vector2 = p0 - profile[i - 1]
					var spn := Vector2(ep.y, -ep.x).normalized()
					if spn.dot(sn) > 0.6:
						n0 = (spn + sn).normalized()
				if i < profile.size() - 2:
					var en: Vector2 = profile[i + 2] - p1
					var snn := Vector2(en.y, -en.x).normalized()
					if snn.dot(sn) > 0.6:
						n1 = (snn + sn).normalized()
			var row0 := v.size()
			for k in cols + (1 if closed else 0):
				var a := start + sweep * float(k) / float(sides)
				var dir := Vector3(cos(a), 0.0, sin(a))
				var nn0 := b * (dir * n0.x + Vector3.UP * n0.y)
				var nn1 := b * (dir * n1.x + Vector3.UP * n1.y)
				if not smooth:
					var am := a
					nn0 = b * (Vector3(cos(am), 0.0, sin(am)) * sn.x + Vector3.UP * sn.y)
					nn1 = nn0
				var u := a * maxf(maxf(p0.x, p1.x), 0.01)
				vert(origin + b * (dir * p0.x + Vector3.UP * p0.y), nn0, col, kind, Vector2(u, p0.y))
				vert(origin + b * (dir * p1.x + Vector3.UP * p1.y), nn1, col, kind, Vector2(u, p1.y))
			var count := cols + (1 if closed else 0)
			for k in count - 1:
				var a0 := row0 + k * 2
				var a1 := row0 + (k + 1) * 2
				var am := start + sweep * (float(k) + 0.5) / float(sides)
				var facing := b * (Vector3(cos(am), 0.0, sin(am)) * sn.x + Vector3.UP * sn.y)
				tri(a0, a1, a1 + 1, facing)
				tri(a0, a1 + 1, a0 + 1, facing)

	## A lathe with few sides as flat facets (nuts, bolt heads): one face per side per band.
	func _facets(origin: Vector3, b: Basis, profile: Array, sides: int, col: Color, kind: int) -> void:
		for i in profile.size() - 1:
			var p0: Vector2 = profile[i]
			var p1: Vector2 = profile[i + 1]
			if p0.distance_to(p1) < 1e-6:
				continue
			for k in sides:
				var a0 := TAU * float(k) / float(sides)
				var a1 := TAU * float(k + 1) / float(sides)
				var d0 := Vector3(cos(a0), 0.0, sin(a0))
				var d1 := Vector3(cos(a1), 0.0, sin(a1))
				var q00 := origin + b * (d0 * p0.x + Vector3.UP * p0.y)
				var q01 := origin + b * (d1 * p0.x + Vector3.UP * p0.y)
				var q11 := origin + b * (d1 * p1.x + Vector3.UP * p1.y)
				var q10 := origin + b * (d0 * p1.x + Vector3.UP * p1.y)
				var fn := (q01 - q00).cross(q10 - q00)
				if fn.length_squared() < 1e-14:
					fn = (q11 - q10).cross(q00 - q10)
				var mid := ((d0 + d1) * 0.5 * (p0.x + p1.x) * 0.5)
				var outward := b * (mid.normalized() * (p1.y - p0.y) + Vector3.UP * (p0.x - p1.x))
				if outward.length_squared() < 1e-12:
					outward = b * mid
				var nn := fn.normalized()
				if nn.dot(outward) < 0.0:
					nn = -nn
				var w := (p0.x + p1.x) * 0.5 * TAU / float(sides)
				quad(q00, q01, q11, q10, nn, col, kind, Vector2(0.0, p0.y), Vector2(w, p0.y), Vector2(w, p1.y), Vector2(0.0, p1.y))

	## A round tube along `path`, frames carried along by parallel transport (no twist).
	func tube(path: PackedVector3Array, r: float, sides: int, col: Color, kind: int) -> void:
		if path.size() < 2:
			return
		var t0 := (path[1] - path[0]).normalized()
		var ref := Vector3.UP if absf(t0.dot(Vector3.UP)) < 0.95 else Vector3.RIGHT
		var nrm := t0.cross(ref).normalized()
		var rows := []
		var run := 0.0
		for i in path.size():
			var t: Vector3
			if i == 0:
				t = path[1] - path[0]
			elif i == path.size() - 1:
				t = path[i] - path[i - 1]
			else:
				t = (path[i + 1] - path[i]).normalized() + (path[i] - path[i - 1]).normalized()
			t = t.normalized()
			nrm = (nrm - t * nrm.dot(t)).normalized()
			var bin := t.cross(nrm).normalized()
			if i > 0:
				run += path[i].distance_to(path[i - 1])
			var row := v.size()
			for k in sides + 1:
				var a := TAU * float(k) / float(sides)
				var d := nrm * cos(a) + bin * sin(a)
				vert(path[i] + d * r, d, col, kind, Vector2(a * r, run))
			rows.append(row)
		for i in path.size() - 1:
			for k in sides:
				var a: int = rows[i] + k
				var b2: int = rows[i + 1] + k
				var facing := (v[a] + v[a + 1] + v[b2] - path[i] * 2.0 - path[i + 1]).normalized()
				tri(a, b2, b2 + 1, facing)
				tri(a, b2 + 1, a + 1, facing)

	## A flat rectangle (size along `up`'s side and `up`) at `centre` facing `nn`, UV 0..1 (v
	## down), UV2.x = `tag` (the label id or the ad's side). `up` defaults to world up (or -Z when
	## the panel faces up).
	func panel(centre: Vector3, size: Vector2, nn: Vector3, kind: int, col: Color, tag: float, up: Vector3 = Vector3.ZERO) -> void:
		var f := nn.normalized()
		var u := up
		if u == Vector3.ZERO:
			u = Vector3.UP if absf(f.dot(Vector3.UP)) < 0.9 else Vector3.FORWARD
		u = (u - f * u.dot(f)).normalized()
		# Right as seen from the front.
		var right := u.cross(f).normalized()
		var hx := right * size.x * 0.5
		var hy := u * size.y * 0.5
		var t2 := Vector2(tag, 0.0)
		quad(centre - hx + hy, centre + hx + hy, centre + hx - hy, centre - hx - hy, f, col, kind, Vector2(0.0, 0.0), Vector2(1.0, 0.0), Vector2(1.0, 1.0), Vector2(0.0, 1.0), t2)

	## A label wrapped round a cylinder of radius r about +Y at `origin`: centred at angle `a`
	## (0 = +X, toward +Z), `w` wide, from y0 to y1.
	func label_curved(origin: Vector3, r: float, a: float, w: float, y0: float, y1: float, tag: float) -> void:
		var span := w / r
		var seg := 6
		for k in seg:
			var a0 := a - span * 0.5 + span * float(k) / float(seg)
			var a1 := a - span * 0.5 + span * float(k + 1) / float(seg)
			var d0 := Vector3(cos(a0), 0.0, sin(a0))
			var d1 := Vector3(cos(a1), 0.0, sin(a1))
			var u0 := float(k) / float(seg)
			var u1 := float(k + 1) / float(seg)
			var p00 := vert(origin + d0 * r + Vector3(0, y1, 0), d0, Color.WHITE, StreetFurniture.K_LABEL, Vector2(1.0 - u0, 0.0), Vector2(tag, 0.0))
			var p01 := vert(origin + d1 * r + Vector3(0, y1, 0), d1, Color.WHITE, StreetFurniture.K_LABEL, Vector2(1.0 - u1, 0.0), Vector2(tag, 0.0))
			var p11 := vert(origin + d1 * r + Vector3(0, y0, 0), d1, Color.WHITE, StreetFurniture.K_LABEL, Vector2(1.0 - u1, 1.0), Vector2(tag, 0.0))
			var p10 := vert(origin + d0 * r + Vector3(0, y0, 0), d0, Color.WHITE, StreetFurniture.K_LABEL, Vector2(1.0 - u0, 1.0), Vector2(tag, 0.0))
			var dm := (d0 + d1).normalized()
			tri(p00, p01, p11, dm)
			tri(p00, p11, p10, dm)

	## Walls between two outlines (same vertex count, counter-clockwise from above) at heights
	## ya and yb, each offset in xz by its Vector3; smooth normals round the outline.
	func loft(oa: PackedVector2Array, ya: float, offa: Vector3, ob: PackedVector2Array, yb: float, offb: Vector3, col: Color, kind: int, inside: bool = false) -> void:
		var m := oa.size()
		var first := v.size()
		var run := 0.0
		for i in m + 1:
			var k := i % m
			var pa := oa[k]
			var pb := ob[k]
			var prev := oa[(k - 1 + m) % m]
			var nxt := oa[(k + 1) % m]
			var e := (nxt - prev).normalized()
			var out2 := Vector2(e.y, -e.x)
			var rise := Vector3(pb.x - pa.x + offb.x - offa.x, yb - ya, pb.y - pa.y + offb.z - offa.z)
			var outward := Vector3(out2.x, 0.0, out2.y)
			var nn := outward
			if rise.length() > 1e-5:
				var tangent := Vector3(e.x, 0.0, e.y)
				nn = rise.cross(tangent).normalized()
				if nn.dot(outward) < 0.0:
					nn = -nn
				if absf(yb - ya) < 1e-5:
					nn = Vector3.UP if pb.length() < pa.length() else Vector3.DOWN
			if inside:
				nn = -nn
			if i > 0:
				run += oa[k].distance_to(oa[i - 1])
			vert(Vector3(pa.x, ya, pa.y) + offa, nn, col, kind, Vector2(run, ya))
			vert(Vector3(pb.x, yb, pb.y) + offb, nn, col, kind, Vector2(run, yb))
		for i in m:
			var a := first + i * 2
			var b2 := first + (i + 1) * 2
			var facing := (n[a] + n[b2]).normalized()
			tri(a, b2, b2 + 1, facing)
			tri(a, b2 + 1, a + 1, facing)

	## A flat cap over an outline at height y (up or down).
	func cap(o: PackedVector2Array, y: float, off: Vector3, up: bool, col: Color, kind: int) -> void:
		_fan(o, Vector3(off.x, y, off.z), Basis(), Vector3.UP if up else Vector3.DOWN, col, kind)
