class_name Rc4Canals
## Marisol Canals by day from a footbridge (refcam `canals_day`, tools/refcams/cameras_w7.json;
## docs/HANDOFF.md "The canals by day from a footbridge"). What gave the 11:00 view away, each behind
## one switch (`RC4_CANALS=0` is the A/B: the canals exactly as before):
##
## - THE WATER read as a cyan swimming pool: on Compatibility the engine reflected the sky on top of
##   the shader's own mirror (which already carries the sky, the houses and the sun), so every
##   mirrored house was washed out. canal_water.gdshader's `rc4` turns the engine's specular off
##   there, calms the ruffle to a glassy mirror and makes the body murky green-brown.

## The whole pass (`RC4_CANALS=0` turns it off).
static var enabled: bool = OS.get_environment("RC4_CANALS") != "0"


## The canal water material's switch.
static func water(m: ShaderMaterial) -> void:
	m.set_shader_parameter("rc4", 1.0 if enabled else 0.0)


## The ground lift at `p` for a canal piece that used to be built without it (the coping's water
## face, the end walls, their railings, the garden fences); 0 with the pass off (the old build).
static func lift(ch: CityChunk, p: Vector2) -> float:
	return ch._gy(p.x, p.y) if enabled else 0.0


## Where the coping's water face stops: the old 5 cm under the bank top left a slot between the
## face and the bank's top row that showed the void as a dark strip down every canal; the face now
## runs down past that row, a real retaining edge's depth.
static func cope_foot() -> float:
	if not enabled:
		return Canals.BANK_TOP_Y - 0.05
	return Canals.bank_y(Canals.COPE_IN - 0.4) - 0.08


## - THE BOATS: one lot in eight had a boat tied to its bank; a canal like this is lined with them.
const BANK_BOAT_ODDS := 0.42


static func bank_boat_odds() -> float:
	return BANK_BOAT_ODDS if enabled else Canals.BANK_BOAT_ODDS


## - THE BANKS were a thin clean lawn strip with a stripe of bare mud and the odd twig: the gardens
##   spill down a real canal's banks. More reed clumps at the waterline, shrubs in drifts and a
##   flowering ground cover spilling under the coping; its own stream after the old rolls (nothing
##   the bank placed before moves).
const REEDS_PER_M := 0.9
const SHRUBS_PER_M := 0.32
const FLOWERS_PER_M := 0.45


static func bank_planting(ch: CityChunk, c: Dictionary, ci: int, sgn: float, part: Rect2, length: float, reed: Mesh, reed_key: String) -> void:
	if not enabled:
		return
	var ps := ch.plan.seed
	var rng := RandomNumberGenerator.new()
	rng.seed = hash([ps, "rc4_canal_bank", ci, int(sgn), int(part.position.x), int(part.position.y)])
	var flower := absi(hash([ps, "rc4_canal_flower", ci])) % PropFactory.FLOWERS.size()
	var fkey := "flower_%d" % flower
	var fmesh := PropFactory.model_flower(flower)
	# Drifts: the planting thick in some stretches and thin in others.
	var drift := func(along: float, salt: float) -> float:
		return sin(along * 0.17 + salt) * 0.35 + sin(along * 0.053 + salt * 2.3) * 0.35 + 0.55
	for k in int(length * REEDS_PER_M):
		var along := rng.randf() * length
		var o := rng.randf_range(Canals.BED_HALF + 0.9, Canals.BED_HALF + 2.0)
		var sc := rng.randf_range(0.8, 1.6)
		var yaw := rng.randf() * TAU
		var tall := rng.randf_range(1.5, 2.4)
		var col := Color(rng.randf_range(0.7, 0.92), rng.randf_range(0.9, 1.05), rng.randf_range(0.6, 0.78))
		if rng.randf() > drift.call(along, float(ci) * 1.3 + sgn):
			continue
		var p := Canals._side_point(c, part, along, o * sgn)
		ch._batch.add(reed_key, reed, Transform3D(Basis(Vector3.UP, yaw).scaled(Vector3(sc, sc * tall, sc)), Vector3(p.x, Canals.bank_y(o) - 0.05, p.y)), col)
	for k in int(length * SHRUBS_PER_M):
		var along := rng.randf() * length
		var o := rng.randf_range(Canals.COPE_IN - 1.6, Canals.COPE_IN - 0.35)
		var v := rng.randi() % 4
		var sc := rng.randf_range(0.6, 1.05)
		var yaw := rng.randf() * TAU
		if rng.randf() > drift.call(along, float(ci) * 2.1 - sgn):
			continue
		var p := Canals._side_point(c, part, along, o * sgn)
		ch._batch.add("shrub_%d" % v, PropFactory.model_shrub(v), Transform3D(Basis(Vector3.UP, yaw).scaled(Vector3(sc, sc, sc)), Vector3(p.x, Canals.bank_y(o) - 0.04, p.y)), Color(0.82, 0.95, 0.82))
	for k in int(length * FLOWERS_PER_M):
		var along := rng.randf() * length
		var o := rng.randf_range(Canals.COPE_IN - 0.9, Canals.COPE_IN - 0.15)
		var sc := rng.randf_range(0.8, 1.3)
		var yaw := rng.randf() * TAU
		if rng.randf() > drift.call(along, float(ci) * 0.7 + sgn * 3.0):
			continue
		var p := Canals._side_point(c, part, along, o * sgn)
		ch._batch.add(fkey, fmesh, Transform3D(Basis(Vector3.UP, yaw).scaled(Vector3(sc, sc, sc)), Vector3(p.x, Canals.bank_y(o) - 0.02, p.y)), Color(1, 1, 1))
	ch._batch.set_draw_distance(fkey, Canals.PLANT_DRAW)
	ch._batch.set_no_shadow(fkey)


## - THE BRIDGE RAILINGS were flat vertex-coloured white with no surface at all: at a bridge they
##   fill the bottom of the frame. A painted finish with a fine grain (WhitePlaster02), the
##   paint a warm off-white.
static func rail_material() -> Material:
	var m := (PropFactory.pbr("plaster_white", 1.2, Color(1.12, 1.11, 1.07)) as StandardMaterial3D).duplicate() as StandardMaterial3D
	m.vertex_color_use_as_albedo = true
	m.vertex_color_is_srgb = true
	m.metallic = 0.05
	m.roughness = 0.5
	return m
