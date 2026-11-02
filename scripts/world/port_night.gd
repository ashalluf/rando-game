class_name PortNight
extends RefCounted
## The container terminal at night (wave 7 refcam `port_night` in tools/refcams/cameras_w7.json,
## docs/HANDOFF.md "The container terminal at 22:00"). What the view from the quay gave away:
##   - a "floodlit" terminal lit by the moon: the high masts and the cranes' portal lamps only laid
##     a faint additive pool on the concrete, so every box, crane leg and the ship's hull stood
##     blue-black against a blue-black yard. Now container.gdshader and port_steel.gdshader add the
##     floods' light to what they draw (`shaders/port_flood.gdshaderinc`): every source in
##     `sources()` - each port chunk's high mast, each quay crane's portal lamps, a working crane's
##     boom lamps over the ship - lights the faces turned to it by an inverse-square-ish falloff,
##     TRUE world (origin_shift), the same in FULL and LOD chunks, on both renderers, nothing on the
##     CPU per frame. The yard's pools are stronger and whiter (`POOL_STRENGTH`);
##   - lamps that were flat beige squares: each crane's portal lamps and each mast head get a
##     NightAtmos halo (`halo_parts()`, in the chunk's batch);
##   - the deckhouse windows were a chunky grid of half-lit squares: port_steel part 9 draws framed
##     windows a little smaller, fewer lit, in a few tones (`port_night` on the material).
## PORT_NIGHT=0 is the A/B: every shader block it adds is behind `port_night`, which stays 0, no
## halo is added and the pools keep their old strength.

static var enabled: bool = OS.get_environment("PORT_NIGHT") != "0"

## The most sources the shaders take (the default seed's terminal has 30 port chunks and 10 quay cranes: 53).
const MAX_SOURCES := 64
## A high mast's head (metres over the yard) and how far its light reaches (metres).
const MAST_Y := 33.0
const MAST_REACH := 105.0
## A crane's portal lamps (under the portal beams over both rails) and the boom lamps a working
## crane shines into the ship's bay.
const CRANE_LAMP_Y := 40.8
const CRANE_REACH := 80.0
const BOOM_REACH := 70.0
## The floods' colour (sRGB: a warm 4000 K LED) and strength on a face turned to them.
const TINT := Color(1.0, 0.88, 0.7)
const GAIN := 0.8
## The most a face takes from all the floods together (port_flood.gdshaderinc's flood_cap).
const CAP := 1.1
## The yard's additive pools (were 0.5, falloff 1.5).
const POOL_STRENGTH := 0.85
const POOL_FALLOFF := 1.25
## The quay's apron (42 m deep, the cranes' lanes): two rows of pools along it, `APRON_STEP` apart,
## `APRON_POOL` across, at these depths back from the quay edge (the cranes' and masts' pools only
## reached a strip of it, and the camera's foreground was an unlit plain).
const APRON_ROWS := [11.0, 30.0]
const APRON_STEP := 24.0
const APRON_POOL := 60.0
## The apron pools overlap into one wash: weaker each and flat-topped.
const APRON_STRENGTH := 0.5
const APRON_FALLOFF := 0.7
## Halo sizes (metres) on a crane's portal lamps and a mast head.
const CRANE_HALO := 1.6
const MAST_HALO := 2.6


static var _cache: Dictionary = {}


## The yard pool's mesh with PortNight on (PropFactory's, then marked `display_add`: on Forward+ an
## additive pool this broad and strong adds in linear HDR and draws a flat white disc on the Mac).
static func pool_mesh() -> Mesh:
	var mesh := PropFactory.light_pool(Color(1.0, 0.9, 0.74), pool_strength(), pool_falloff())
	if enabled:
		(mesh.material as ShaderMaterial).set_shader_parameter("display_add", true)
	return mesh


## The pool's strength and falloff for PortKit's yard pools (`_add_port_pool`).
static func pool_strength() -> float:
	return POOL_STRENGTH if enabled else 0.5


static func pool_falloff() -> float:
	return POOL_FALLOFF if enabled else 1.5


## Every port block's (ix, iz) on `plan`: the blocks whose centre MacroMap calls PORT (what makes a
## chunk build _port_steps()).
static func port_blocks(plan: CityPlan) -> Array[Vector2i]:
	var out: Array[Vector2i] = []
	if plan == null or plan.macro == null:
		return out
	var pr: Rect2 = plan.macro.port_rect
	var a: Vector2i = plan.block_index_at(pr.position + Vector2(1.0, 1.0))
	var b: Vector2i = plan.block_index_at(pr.end - Vector2(1.0, 1.0))
	for iz in range(a.y - 1, b.y + 2):
		for ix in range(a.x - 1, b.x + 2):
			var rect: Rect2 = plan.block(ix, iz).rect
			if plan.zone_at(rect.get_center()) == MacroMap.Zone.PORT:
				out.append(Vector2i(ix, iz))
	return out


## One port block's lamps (TRUE world, before the relief lift): its mast's foot and its quay
## cranes' bases with whether each works the ship. The chunks build their masts and cranes from the
## same numbers (CityChunk._port_kit / _build_quay).
static func block_lamps(plan: CityPlan, ix: int, iz: int) -> Dictionary:
	var macro: MacroMap = plan.macro
	var area := plan.owned_rect(ix, iz)
	var out := {"mast": Vector3(area.position.x + 3.0, CityChunk.PORT_YARD_TOP, area.position.y + 2.2), "cranes": []}
	var c := area.get_center()
	if macro.zone_at(Vector2(c.x, area.end.y + 30.0)) != MacroMap.Zone.OCEAN or PortLife.is_gate(plan, ix, iz):
		return out
	var ship := PortLife.ship_anchor()
	var qz := area.end.y
	var crane_z := qz - PortKit.STS_QUAY_SETBACK - PortKit.STS_GAUGE * 0.5
	for k in 2:
		var x := area.position.x + area.size.x * (0.25 + 0.5 * k)
		if macro.zone_at(Vector2(x, qz + 30.0)) != MacroMap.Zone.OCEAN:
			continue
		var working := ship.x < INF and absf(x - ship.x) < 95.0
		if working and PortLife.enabled:
			x = PortLife.bay_x(x)
		(out.cranes as Array).append([Vector3(x, CityChunk.PORT_YARD_TOP, crane_z), working])
	return out


## Where the floods are (TRUE world x, y, z; w the reach in metres), pure and cached per plan.
static func sources(plan: CityPlan) -> Array[Vector4]:
	if plan == null:
		return []
	var key := plan.get_instance_id()
	if _cache.has(key):
		return _cache[key]
	var out: Array[Vector4] = []
	var ship := PortLife.ship_anchor()
	for b: Vector2i in port_blocks(plan):
		var lift := plan.macro.relief_at(plan.owned_rect(b.x, b.y).get_center())
		var lamps := block_lamps(plan, b.x, b.y)
		var m: Vector3 = lamps.mast
		out.append(Vector4(m.x, m.y + lift + MAST_Y, m.z, MAST_REACH))
		for cr: Array in lamps.cranes:
			var base: Vector3 = cr[0]
			for sz: float in [-1.0, 1.0]:
				out.append(Vector4(base.x, base.y + lift + CRANE_LAMP_Y, base.z + sz * PortKit.STS_GAUGE * 0.5, CRANE_REACH))
			if cr[1]:
				out.append(Vector4(base.x, base.y + lift + CRANE_LAMP_Y, ship.y, BOOM_REACH))
	if out.size() > MAX_SOURCES:
		out.resize(MAX_SOURCES)
	_cache[key] = out
	return out


## A port chunk's part (one hook in CityChunk._port_kit, every level but the capture): the floods
## handed to the materials, and the halos on its mast head and its cranes' portal lamps.
static func dress(ch: CityChunk, ix: int, iz: int) -> void:
	ensure(ch.plan)
	if not enabled or ch.capturing:
		return
	# Lifted the way the port's own pieces are (CityChunk._port_run: the relief at the chunk's
	# centre, as the yard slab is): lifted by the relief where each stands, the apron's pools lay
	# under the slab near the quay, where the ground falls toward the bay.
	ch._port_run(_dress.bind(ch, ix, iz))


static func _dress(ch: CityChunk, ix: int, iz: int) -> void:
	var lamps := block_lamps(ch.plan, ix, iz)
	if NightAtmos.enabled:
		NightAtmos.ensure(ch.get_parent())
		var parts: Array = mast_halo(lamps.mast)
		for cr: Array in lamps.cranes:
			parts.append_array(crane_halos(cr[0]))
		for p: Array in parts:
			ch._batch.add(p[0], p[1], p[2], p[3], p[4])
		NightAtmos.finish_batch(ch._batch)
	# The apron's pools (a quay chunk with cranes).
	if (lamps.cranes as Array).is_empty():
		return
	var area := ch.plan.owned_rect(ix, iz)
	var mesh := PropFactory.light_pool(Color(1.0, 0.9, 0.74), APRON_STRENGTH, APRON_FALLOFF)
	(mesh.material as ShaderMaterial).set_shader_parameter("display_add", true)
	for back: float in APRON_ROWS:
		var x := area.position.x + APRON_STEP * 0.5
		while x < area.end.x:
			var xf := Transform3D(Basis(Vector3.RIGHT, -PI * 0.5).scaled(Vector3(APRON_POOL, 1.0, APRON_POOL)), Vector3(x, CityChunk.PORT_YARD_TOP + 0.07, area.end.y - back))
			ch._batch.add("port_apron_pool", mesh, xf)
			x += APRON_STEP
	ch._batch.set_no_shadow("port_apron_pool")


static var _applied_for: int = 0


## Hands both port materials the floods (once per plan; every port chunk's build calls it).
static func ensure(plan: CityPlan) -> void:
	if plan == null or _applied_for == plan.get_instance_id():
		return
	apply(plan)


static func apply(plan: CityPlan) -> void:
	if plan != null:
		_applied_for = plan.get_instance_id()
	var on := 1.0 if enabled else 0.0
	var mats: Array[ShaderMaterial] = [PortKit.container_material(), PortKit.steel_material()]
	var arr := PackedVector4Array()
	arr.resize(MAX_SOURCES)
	var src := sources(plan) if enabled else ([] as Array[Vector4])
	for i in src.size():
		arr[i] = src[i]
	for m in mats:
		m.set_shader_parameter("port_night", on)
		m.set_shader_parameter("flood_src", arr)
		m.set_shader_parameter("flood_count", src.size())
		m.set_shader_parameter("flood_tint", Vector3(TINT.r, TINT.g, TINT.b))
		m.set_shader_parameter("flood_gain", GAIN)
		m.set_shader_parameter("flood_cap", CAP)


## The light a point gets from the floods (GDScript copy of port_flood() in
## shaders/port_flood.gdshaderinc; change both): `p` TRUE world, `n` the face's normal.
static func flood_at(src: Array[Vector4], p: Vector3, n: Vector3) -> float:
	var fl := 0.0
	for s: Vector4 in src:
		var d := Vector3(s.x, s.y, s.z) - p
		var reach := s.w
		var dist2 := d.length_squared()
		if dist2 >= reach * reach:
			continue
		var dist := sqrt(dist2)
		var h := reach * 0.32
		var fall := 1.0 / (1.0 + dist2 / (h * h))
		fall *= 1.0 - smoothstep(reach * 0.6, reach, dist)
		var facing := clampf(n.dot(d / maxf(dist, 0.01)), 0.0, 1.0)
		var cone := smoothstep(0.0, 0.3, d.y / maxf(dist, 0.01))
		fl += fall * cone * (0.25 + 0.75 * facing)
	return fl


## The halos on a crane's four portal lamps (crane frame `base`, chunk-local before the relief),
## in the chunk batch's format ([key, mesh, xform, colour, custom]). Empty with the A/B off.
static func crane_halos(base: Vector3) -> Array:
	if not enabled or not NightAtmos.enabled:
		return []
	var out: Array = []
	var gz := PortKit.STS_GAUGE * 0.5
	var y := PortKit.STS_PORTAL_Y - 3.5
	for sz: float in [-1.0, 1.0]:
		for fx: float in [-5.0, 5.0]:
			out.append([NightAtmos.HALO_KEY, NightAtmos.halo_mesh(), Transform3D(Basis.from_scale(Vector3.ONE * CRANE_HALO), base + Vector3(fx, y, sz * gz)), TINT, Color(1.0, 0.0, 0.0, 0.0)])
	return out


## The halo round a high mast's ring of floodlights (`at` the mast's foot).
static func mast_halo(at: Vector3) -> Array:
	if not enabled or not NightAtmos.enabled:
		return []
	return [[NightAtmos.HALO_KEY, NightAtmos.halo_mesh(), Transform3D(Basis.from_scale(Vector3.ONE * MAST_HALO), at + Vector3(0.0, PortKit.MAST_H - 1.1, 0.0)), TINT, Color(1.0, 0.0, 0.0, 0.0)]]
