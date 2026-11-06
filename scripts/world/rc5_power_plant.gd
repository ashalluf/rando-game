class_name RcPowerPlant
extends RefCounted
## The power plant at dusk (wave 8 refcam `power_plant_dusk` in tools/refcams/cameras_w8.json,
## docs/HANDOFF.md "The power plant at dusk from the beach"). Seen from the wet sand north of it at
## 18:50 the plant read as a pasted cut-out: the halls' window bands were flat cream slabs that
## z-fought with the wall behind them (7 cm proud, under the depth buffer's step at 200 m), its
## lamps lit nothing - the walls stood unlit and moon-grey with tiny warm dots on them - and the
## stacks' aviation lights were pin-pricks. Here:
##  - the glazing stands GLASS_OUT proud (in front of the pilasters' faces, behind their fronts)
##    with a head and a sill, and power_plant.gdshader draws it as bays of panes, lit or not,
##    fluorescent or sodium, the crane girder and machinery behind it (pp_window());
##  - `sources()` (pure: the layout's halls, stair towers, masts and the eave floods this adds)
##    go to the shared material, and the shader's pp_flood() lights every wall, stack and piece of
##    steel round them after dark (shaders/rc5_power_plant.gdshaderinc; flood_at() its copy);
##  - eave floods on the boiler house and the turbine hall, a flood at each stack's foot aimed up
##    the shaft (`stack_floods`), and bigger, brighter aviation lights with the middle ring visible.
## RC5_POWER_PLANT=0 in the environment is the A/B (the plant exactly as it was).

static func _static_init() -> void: LoadPulse.compiled()  # a boot frame: docs/HANDOFF.md "The boot compile"

static var enabled: bool = OS.get_environment("RC5_POWER_PLANT") != "0"

## How far the window bands stand off the cladding (was 0.03: 7 cm at 200 m z-fought).
const GLASS_OUT := 0.24
## A wall pack's reach (negative in the shader's table: light all round it, below it).
const PACK_REACH := 15.0
## A landing lamp's reach.
const LANDING_REACH := 9.0
## The yard masts' reach (aimed down; their heads are 18 m up).
const MAST_REACH := 60.0
## The eave floods: every so many metres along a long wall, the reach.
const EAVE_EVERY := 22.0
const EAVE_REACH := 34.0
## The floods at a stack's foot, aimed up the shaft: how far out, their reach.
const STACK_FLOOD_OUT := 9.0
const STACK_FLOOD_REACH := 85.0
## The stacks' aviation lights: their size and HDR (aircraft_lights.gdshader's hdr, 2.5 before).
const LIGHT_SIZE_GAIN_ON := 1.6
const LIGHT_HDR := 4.0
static var LIGHT_SIZE_GAIN: float = LIGHT_SIZE_GAIN_ON if enabled else 1.0
## A wall pack's pool on the ground: how far out from the wall, its size.
const POOL_OUT := 3.2
const POOL_SIZE := 11.0
const TINT := Color(1.0, 0.86, 0.66)
const GAIN := 0.85
const CAP := 1.0
const MAX_SOURCES := 64

static var _applied: Dictionary = {}


static func glass_out(old: float) -> float:
	return GLASS_OUT if enabled else old


## The wall packs of a hall (PowerPlantKit.hall()'s rule): local offsets from its centre.
static func hall_packs(sz: Vector3) -> Array[Vector3]:
	var out: Array[Vector3] = []
	var nb := int(sz.z / 7.5)
	for i in range(1, nb, 2):
		var z := -sz.z * 0.5 + sz.z * float(i) / float(nb)
		for sx: float in [-1.0, 1.0]:
			out.append(Vector3(sx * (sz.x * 0.5 + 0.35), 7.5, z))
	return out


## The eave floods of a long wall (this pass's): local offsets, on both long sides.
static func eave_floods(sz: Vector3, y: float) -> Array[Vector3]:
	var out: Array[Vector3] = []
	var n := maxi(1, int(sz.z / EAVE_EVERY))
	for i in n:
		var z := -sz.z * 0.5 + sz.z * (float(i) + 0.5) / float(n)
		for sx: float in [-1.0, 1.0]:
			out.append(Vector3(sx * (sz.x * 0.5 + 0.9), y, z))
	return out


## Every lamp of the plant that lights it: Vector4(true world xyz, reach; negative a wall pack).
static func sources(plan: CityPlan) -> Array[Vector4]:
	var out: Array[Vector4] = []
	var lay := PowerPlant.layout(plan)
	if lay.is_empty() or not bool(lay.ok):
		return out
	var base_y := PowerPlant.BASE_Y
	# The stacks first (the eye lands on them), then the walls nearest the beach.
	for s: Vector3 in lay.stacks:
		if s.y < 60.0:
			continue
		var g := base_y + plan.macro.relief_at(Vector2(s.x, s.z))
		for k in 2:
			var a := PI * 0.75 + PI * float(k)
			out.append(Vector4(s.x + cos(a) * STACK_FLOOD_OUT, g + 1.0, s.z + sin(a) * STACK_FLOOD_OUT, STACK_FLOOD_REACH + 1000.0))
	for p: Vector2 in lay.lamps:
		out.append(Vector4(p.x, base_y + plan.macro.relief_at(p) + 18.0, p.y + 1.0, MAST_REACH))
	for p: Dictionary in lay.pieces:
		var kind := String(p.kind)
		var c: Vector2 = p.c
		var g := base_y + plan.macro.relief_at(c)
		var o := Vector3(c.x, g, c.y)
		var sz: Vector3 = p.size
		if kind == "turbine_hall" or kind == "st_hall":
			for q: Vector3 in hall_packs(sz):
				out.append(Vector4(o.x + q.x, o.y + q.y, o.z + q.z, -PACK_REACH))
			for q: Vector3 in eave_floods(sz, sz.y - 1.4):
				out.append(Vector4(o.x + q.x, o.y + q.y, o.z + q.z, EAVE_REACH))
		elif kind == "boiler_house":
			for q: Vector3 in eave_floods(sz, sz.y - 1.0):
				out.append(Vector4(o.x + q.x, o.y + q.y, o.z + q.z, EAVE_REACH * 1.3))
			# The stair tower's landing lamps (PowerPlantKit.stair_tower(): every 6 m).
			var st := o + Vector3(sz.x * 0.25 + 2.95, 0.0, -sz.z * 0.5 - 3.2)
			var n := int((sz.y + 2.0) / 6.0)
			for i in range(0, n, 2):
				out.append(Vector4(st.x, st.y + float(i + 1) * 6.0 + 2.2, st.z, -LANDING_REACH))
	if out.size() > MAX_SOURCES:
		out.resize(MAX_SOURCES)
	return out


## The ground pools under the halls' wall packs: Vector4(x, 0, z true world, size in metres).
static func pack_pools(plan: CityPlan) -> Array[Vector4]:
	var out: Array[Vector4] = []
	var lay := PowerPlant.layout(plan)
	if lay.is_empty() or not bool(lay.ok):
		return out
	for p: Dictionary in lay.pieces:
		if String(p.kind) != "turbine_hall" and String(p.kind) != "st_hall":
			continue
		var c: Vector2 = p.c
		for q: Vector3 in hall_packs(p.size):
			out.append(Vector4(c.x + q.x + signf(q.x) * POOL_OUT, 0.0, c.y + q.z, POOL_SIZE))
	return out


## pp_flood() in GDScript (rc5_power_plant.gdshaderinc; change both).
static func flood_at(src: Array[Vector4], p: Vector3, n: Vector3) -> float:
	var fl := 0.0
	for s: Vector4 in src:
		var d := Vector3(s.x, s.y, s.z) - p
		var up := s.w > 500.0
		var reach := s.w - 1000.0 if up else absf(s.w)
		var dist2 := d.length_squared()
		if dist2 >= reach * reach:
			continue
		var dist := sqrt(dist2)
		var dn := d / maxf(dist, 0.01)
		var facing := clampf(n.dot(dn), 0.0, 1.0)
		if up:
			var h := reach * 0.45
			var fall := 1.0 / (1.0 + dist2 / (h * h)) * (1.0 - smoothstep(reach * 0.55, reach, dist))
			fl += fall * smoothstep(0.0, 0.35, -dn.y) * (0.15 + 0.85 * facing)
		elif s.w < 0.0:
			var h := reach * 0.22
			var fall := 1.0 / (1.0 + dist2 / (h * h)) * (1.0 - smoothstep(reach * 0.5, reach, dist))
			fl += fall * smoothstep(-0.25, 0.35, dn.y) * (0.45 + 0.55 * facing)
		else:
			var h := reach * 0.3
			var fall := 1.0 / (1.0 + dist2 / (h * h)) * (1.0 - smoothstep(reach * 0.6, reach, dist))
			fl += fall * smoothstep(0.0, 0.3, dn.y) * (0.2 + 0.8 * facing)
	return minf(fl, CAP)


## Hands the sources to the plant's shared material (once per plan; the material is shared).
static func apply(plan: CityPlan) -> void:
	var m := PowerPlantKit.material()
	if not enabled:
		m.set_shader_parameter("rc5", 0.0)
		return
	var key := plan.get_instance_id()
	if _applied.get(m.get_instance_id(), -1) == key:
		return
	_applied[m.get_instance_id()] = key
	var src := sources(plan)
	var arr := PackedVector4Array()
	arr.resize(MAX_SOURCES)
	for i in src.size():
		arr[i] = src[i]
	m.set_shader_parameter("rc5", 1.0)
	m.set_shader_parameter("pp_src", arr)
	m.set_shader_parameter("pp_src_count", src.size())
	m.set_shader_parameter("pp_tint", Vector3(TINT.r, TINT.g, TINT.b))
	m.set_shader_parameter("pp_gain", GAIN)
	m.set_shader_parameter("pp_cap", CAP)
