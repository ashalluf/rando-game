class_name RiverNight
## The LA River at night (wave 7 refcam `river_night`, docs/HANDOFF.md "The LA River at night"):
## what the channel's own bridges do to it after dark. Every street bridge a chunk builds hands
## its frame here (`note()`, one line in RiverBridges.jobs()), and the river's two shared
## materials get the nearest bridges' frames as uniform arrays (TRUE world; the shaders add
## `origin_shift`):
## - river_concrete.gdshader: the 6th St ribbon's arches washed by their own LEDs (the whole rib,
##   not a strip under it), and under-deck fixtures throwing pools on the bed, the piers' feet and
##   the banks under every bridge (`rn_light()`);
## - river_water.gdshader: the low flow mirrors the bridges (`rn_mirror()`): the lit ribs and
##   their LED lines, the deck's fascia with its fixtures and lamp heads, the piers - stretched by
##   the riffles' own normals, cut where the bank stands in the way.
## All of it is behind `lamp_factor` (nothing by day: day is bit-identical) and the `river_night`
## global (`RIVER_NIGHT=0` is the A/B).

## The arrays' size in the shaders (rn_a ... rn_e[MAX]).
const MAX := 6
## Bridge kinds as the shaders read them (rn_b.w).
const K_RIBBON := 0.0
const K_ARCH := 1.0
const K_GIRDER := 2.0
## Under-deck fixtures: how far in from each fascia they hang, under the soffit (metres).
const FIX_IN := 1.6
const FIX_DROP := 0.35

static var _bridges := {}
static var _applied := false
static var _pushed_key := ""
## Keys by when their chunk last built them: the last MAX are the ones round the player.
static var _order: Array[String] = []


static func enabled() -> bool:
	return OS.get_environment("RIVER_NIGHT") != "0"


static func apply() -> void:
	if _applied:
		return
	_applied = true
	RenderingServer.global_shader_parameter_set("river_night", 1.0 if enabled() else 0.0)


## A bridge's record from RiverBridges' frame `f` (pure: the frame's numbers only). Keys: o, u
## (Vector2, TRUE world), half, deck, thick, kind, stops (4 t: the ribbon's span ends, else
## t0 / the bed's edges / t1), t0, t1, rise, lean.
static func record(f: Dictionary, kind: int, deck: float) -> Dictionary:
	var piers: Array = f.piers
	var tb: Vector2 = f.tb
	var k := K_GIRDER
	var thick := 1.7
	var stops := [float(f.t0), tb.x, tb.y, float(f.t1)]
	if kind == LaRiver.Bridge.RIBBON:
		k = K_RIBBON
		thick = RiverBridges.RIBBON_THICK
		stops = [float(f.t0) + 0.5, float(piers[0]), float(piers[1]), float(f.t1) - 0.5]
	elif kind == LaRiver.Bridge.ARCH:
		k = K_ARCH
		thick = RiverBridges.ARCH_THICK
	return {"o": f.o, "u": f.u, "half": float(f.half), "deck": deck, "thick": thick, "kind": k,
		"stops": stops, "t0": float(f.t0), "t1": float(f.t1), "tb": tb,
		"rise": RiverBridges.RIBBON_RISE, "lean": RiverBridges.RIBBON_LEAN, "piers": piers}


## Called by RiverBridges.jobs() with the frame it builds from (both levels). Rail bridges carry
## no street lights and are not noted.
static func note(f: Dictionary, kind: int, deck: float) -> void:
	if not enabled():
		return
	var key := "%d:%d" % [int(f.br.axis), int(f.br.index)]
	var known := _bridges.has(key)
	if known and _order.size() > 0 and _order[-1] == key:
		return
	if not known:
		_bridges[key] = record(f, kind, deck)
	_order.erase(key)
	_order.append(key)
	push()


## The uniform arrays (vec4 x MAX each) for `recs` (the first MAX): a = o.x, o.z, u.x, u.z;
## b = half, deck, thick, kind; c = stops; d = t0, t1, rise, lean; e = the bed's edges (t), the
## piers (t).
static func arrays(recs: Array) -> Dictionary:
	var a := PackedVector4Array()
	var b := PackedVector4Array()
	var c := PackedVector4Array()
	var d := PackedVector4Array()
	var e := PackedVector4Array()
	for i in MAX:
		if i < recs.size():
			var r: Dictionary = recs[i]
			var o: Vector2 = r.o
			var u: Vector2 = r.u
			var st: Array = r.stops
			var tb: Vector2 = r.tb
			var pr: Array = r.piers
			a.append(Vector4(o.x, o.y, u.x, u.y))
			b.append(Vector4(r.half, r.deck, r.thick, r.kind))
			c.append(Vector4(st[0], st[1], st[2], st[3]))
			d.append(Vector4(r.t0, r.t1, r.rise, r.lean))
			e.append(Vector4(tb.x, tb.y, float(pr[0]), float(pr[1])))
		else:
			for arr: PackedVector4Array in [a, b, c, d, e]:
				arr.append(Vector4.ZERO)
	return {"rn_a": a, "rn_b": b, "rn_c": c, "rn_d": d, "rn_e": e, "rn_count": mini(recs.size(), MAX)}


## Hands the bridges to both materials: the last MAX whose chunks built (the chunks build round
## the player, so these are the bridges he can see).
static func push() -> void:
	var recs: Array = []
	for i in range(maxi(0, _order.size() - MAX), _order.size()):
		recs.append(_bridges[_order[i]])
	var keyed := ",".join(_order.slice(maxi(0, _order.size() - MAX)))
	if keyed == _pushed_key:
		return
	_pushed_key = keyed
	var arr := arrays(recs)
	for m: ShaderMaterial in [RiverBuild.concrete_material(), RiverBuild.water_material()]:
		for k: String in arr:
			m.set_shader_parameter(k, arr[k])


## The ribbon's rib centre line at bridge t on side `sg` (the shader's rn_rib(), change both):
## Vector2(a across, y up), or Vector2.INF outside every span.
static func rib_at(r: Dictionary, t: float, sg: float) -> Vector2:
	var st: Array = r.stops
	for k in 3:
		var ta: float = st[k]
		var tz: float = st[k + 1]
		if t >= ta and t <= tz:
			var e := 2.0 * (t - ta) / (tz - ta) - 1.0
			var h: float = float(r.rise) * pow(maxf(1.0 - e * e, 0.0), 0.7)
			return Vector2(sg * (float(r.half) + 0.4 + h * float(r.lean)), float(r.deck) + 0.2 + h)
	return Vector2.INF


## The fixtures under a bridge's deck (FULL, a RiverBridges job): a galvanised housing hung under
## the soffit at each place rn_light() puts a downlight, its lens on the lamp material (lit after
## dark in the bridge's colour). The same positions as the shader's (FIX_IN, FIX_DROP, PITCH).
const PITCH := 8.0


static func fixture_ts(f: Dictionary) -> Array[float]:
	var tb: Vector2 = f.tb
	var t0 := tb.x - 2.0
	var t1 := tb.y + 2.0
	var out: Array[float] = []
	var n := int(floor((t1 - t0) / PITCH))
	for k in n + 1:
		out.append(t0 + k * PITCH)
	return out


static func fixtures(f: Dictionary) -> void:
	var b: RiverBuild = f.b
	var kind := int((f.br as Dictionary).kind)
	var thick := RiverBridges.RIBBON_THICK if kind == LaRiver.Bridge.RIBBON else (RiverBridges.ARCH_THICK if kind == LaRiver.Bridge.ARCH else 1.7)
	var col := RiverBridges.LED if kind == LaRiver.Bridge.RIBBON else RiverBridges.LANTERN
	var half: float = f.half
	var u: Vector2 = f.u
	var basis := Basis(Vector3.UP, atan2(-u.x, -u.y))
	for t in fixture_ts(f):
		for sg: float in [-1.0, 1.0]:
			var a := sg * (half - FIX_IN)
			var y := RiverBridges._deck_y(f, t) - thick
			var c := RiverBridges._p(f, t, a, y - FIX_DROP * 0.5)
			Industrial._wbox(b.ch, Transform3D(basis, c), Vector3(0.5, FIX_DROP, 0.36), IndustrialKit.K_GALV, Color(0.5, 0.51, 0.52))
			var lens := RiverBridges._p(f, t, a, y - FIX_DROP - 0.01)
			var du := RiverBridges._u3(f, 0.2)
			var dq := RiverBridges._q3(f, 0.14)
			b.quad("lamp", lens + du + dq, lens - du + dq, lens - du - dq, lens + du - dq, Vector3.DOWN, col,
				Vector2.ZERO, Vector2.ZERO, Vector2.ZERO, Vector2.ZERO, Vector2.ZERO, Vector2.ZERO, Vector2.ZERO, Vector2.ZERO, false)
