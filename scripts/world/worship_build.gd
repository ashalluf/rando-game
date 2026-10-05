class_name WorshipBuild
extends RefCounted
## The places of worship themselves (see Worship for where they stand). Everything is built in the
## site's frame - x along the street (centred), +z out toward it (the street edge at z 0, the back
## of the site at z = -D), y up from the pavement - into ONE LandmarkGeo mesh per building (a
## surface per material, on the landmark shaders: plaster, stone and concrete on landmark_facade,
## FLOODLIT after dark; clay and slate on clay_roof) plus the windows on worship_glass.gdshader,
## which glow from inside after dark. Real sizes: a Mission nave is 13 m wide and 9.5 m to the
## eaves under a 20 m bell tower; a Greek-revival portico's columns are 8.6 m.
##
## Walls with openings are cut exactly (`wall()`): a rectangular face less its holes - arches,
## circles, rectangles - in vertical strips, with the reveals traced round each hole through the
## wall's thickness, so an arcade is open, a belfry shows its bell, a door is recessed.
##
## `plan_of()` is pure (the masses as far boxes, the top, the occluders), so the LOD chunks and
## the far city draw what the FULL chunk builds.

const KEEP := 0.02

static var _mats: Dictionary = {}


# --- The plan (pure) --------------------------------------------------------------------------------

## The numbers of site `s` (Worship._site + kind + seed): every builder reads its dimensions from
## here, and the far boxes come from the same numbers.
static func plan_of(s: Dictionary) -> Dictionary:
	var L: float = s.L
	var D: float = s.D
	var sd: int = s.seed
	var p := {"L": L, "D": D, "kind": int(s.kind), "far": [], "occluders": [], "seed": sd}
	match int(s.kind):
		Worship.Kind.MISSION:
			var W := 13.0
			var nl := clampf(D - 16.0, 22.0, 34.0)
			var fz := clampf((D - nl) * 0.45, 7.0, 12.0)
			# Tower on the left of the front, the arcade on the right: centre the whole group.
			var group := 5.0 + W + 4.4
			var xc := clampf(-group * 0.5 + 5.0 + W * 0.5, -L * 0.5 + 5.6 + W * 0.5, L * 0.5 - 4.6 - W * 0.5)
			p.merge({"W": W, "NL": nl, "fz": fz, "xc": xc, "H": 9.5, "tower": 5.6, "tower_h": 19.5, "arcade": 4.2, "top": 24.0})
			var z0 := -fz - nl * 0.5
			p.far.append([Vector3(xc, 4.75, z0), Vector3(W, 9.5, nl), Color(0.86, 0.82, 0.74)])
			p.far.append(["roof", Vector3(xc, 9.5, z0), nl + 0.4, W + 1.2, 3.3, true, Color(0.55, 0.30, 0.20)])
			p.far.append([Vector3(xc - W * 0.5 - 2.2, 9.75, -fz - 2.8), Vector3(5.6, 19.5, 5.6), Color(0.88, 0.84, 0.76)])
			p.far.append([Vector3(xc + W * 0.5 + 2.1, 2.5, z0), Vector3(4.2, 5.0, nl), Color(0.80, 0.74, 0.64)])
			p.occluders.append([Vector3(xc, 4.5, z0), Vector3(W - 1.0, 8.5, nl - 1.0)])
		Worship.Kind.MODERN:
			var W := 16.0
			var nl := clampf(D - 14.0, 22.0, 30.0)
			var fz := clampf((D - nl) * 0.5, 7.0, 11.0)
			var xc := clampf(-2.0, -L * 0.5 + W * 0.5 + 1.0, L * 0.5 - W * 0.5 - 6.0)
			p.merge({"W": W, "NL": nl, "fz": fz, "xc": xc, "wall": 3.4, "ridge": 17.0, "camp_h": 26.0, "top": 28.0})
			var z0 := -fz - nl * 0.5
			p.far.append([Vector3(xc, 1.7, z0), Vector3(W, 3.4, nl), Color(0.70, 0.69, 0.66)])
			p.far.append(["roof", Vector3(xc, 2.8, z0), nl + 2.0, W + 2.4, 12.0, true, Color(0.24, 0.25, 0.27)])
			p.far.append([Vector3(xc + W * 0.5 + 4.5, 13.0, -fz + 1.0), Vector3(3.0, 26.0, 6.0), Color(0.74, 0.73, 0.70)])
			p.occluders.append([Vector3(xc, 1.6, z0), Vector3(W - 1.0, 3.0, nl - 1.0)])
		Worship.Kind.STOREFRONT:
			var W := L - 0.4
			var bd := clampf(D - 2.0, 12.0, 20.0)
			p.merge({"W": W, "BD": bd, "H": 5.4, "top": 7.0})
			p.far.append([Vector3(0.0, 2.9, -bd * 0.5), Vector3(W, 5.8, bd), Color(0.80, 0.74, 0.64)])
			p.occluders.append([Vector3(0.0, 2.6, -bd * 0.5), Vector3(W - 0.8, 5.0, bd - 0.8)])
		Worship.Kind.GREEK:
			var W := 15.0
			var nl := clampf(D - 18.0, 20.0, 28.0)
			var fz := clampf((D - nl - 6.0) * 0.5, 7.0, 11.0)
			var brick := Worship.h01([sd, "brick"]) < 0.5
			p.merge({"W": W, "NL": nl, "fz": fz, "xc": 0.0, "H": 10.0, "portico": 6.0, "pod": 1.1, "brick": brick, "top": 34.0})
			var z0 := -fz - 6.0 - nl * 0.5
			var body_col := Color(0.55, 0.28, 0.22) if brick else Color(0.90, 0.89, 0.86)
			p.far.append([Vector3(0.0, 5.5, z0), Vector3(W, 11.0, nl), body_col])
			p.far.append(["roof", Vector3(0.0, 12.5, z0 + 3.0), nl + 6.6, W + 1.0, 3.1, true, Color(0.30, 0.31, 0.33)])
			p.far.append([Vector3(0.0, 5.5, -fz - 3.0), Vector3(W, 11.0, 6.0), Color(0.92, 0.91, 0.88)])
			p.far.append([Vector3(0.0, 21.0, -fz - 8.5), Vector3(4.2, 9.0, 4.2), Color(0.93, 0.93, 0.90)])
			p.far.append([Vector3(0.0, 29.5, -fz - 8.5), Vector3(1.6, 8.0, 1.6), Color(0.93, 0.93, 0.90)])
			p.occluders.append([Vector3(0.0, 5.0, z0), Vector3(W - 1.0, 9.0, nl - 1.0)])
		Worship.Kind.TEMPLE:
			var W := clampf(L - 16.0, 16.0, 20.0)
			var HD := 14.0
			var fz := clampf(D - HD - 8.0, 12.0, 22.0)
			p.merge({"W": W, "HD": HD, "fz": fz, "xc": 0.0, "pod": 1.2, "eave": 6.4, "ridge": 12.5, "top": 14.0})
			var z0 := -fz - HD * 0.5
			p.far.append([Vector3(0.0, 3.4, z0), Vector3(W, 6.8, HD), Color(0.86, 0.84, 0.78)])
			p.far.append(["roof", Vector3(0.0, 6.4, z0), W + 3.2, HD + 3.2, 6.1, false, Color(0.20, 0.22, 0.22)])
			p.occluders.append([Vector3(0.0, 3.5, z0), Vector3(W - 2.0, 5.0, HD - 2.0)])
		_:
			var W := 20.0
			var bd := clampf(D - 14.0, 18.0, 24.0)
			var fz := clampf((D - bd) * 0.55, 7.0, 12.0)
			p.merge({"W": W, "BD": bd, "fz": fz, "xc": 0.0, "H": 13.0, "towers": 4.6, "tower_h": 18.5, "top": 24.0})
			var z0 := -fz - bd * 0.5
			p.far.append([Vector3(0.0, 6.5, z0), Vector3(W, 13.0, bd), Color(0.84, 0.78, 0.66)])
			for sx: float in [-1.0, 1.0]:
				p.far.append([Vector3(sx * (W * 0.5 - 2.3), 9.25, -fz - 2.3), Vector3(4.6, 18.5, 4.6), Color(0.84, 0.78, 0.66)])
			p.occluders.append([Vector3(0.0, 6.0, z0), Vector3(W - 1.0, 12.0, bd - 1.0)])
	return p


# --- Entry ---------------------------------------------------------------------------------------------

static func build(ch: CityChunk, node: Node3D, body: StaticBody3D, s: Dictionary, p: Dictionary) -> void:
	var g := LandmarkGeo.new()
	_use_mats(g, p)
	var ctx := {"ch": ch, "node": node, "body": body, "s": s, "p": p, "g": g, "xf": node.transform,
		"pools": [], "lights": [], "paved": [], "trees": [], "text": []}
	match int(p.kind):
		Worship.Kind.MISSION:
			_mission(ctx)
		Worship.Kind.MODERN:
			_modern(ctx)
		Worship.Kind.STOREFRONT:
			_storefront(ctx)
		Worship.Kind.GREEK:
			_greek(ctx)
		Worship.Kind.TEMPLE:
			_temple(ctx)
		_:
			_synagogue(ctx)
	if int(p.kind) != Worship.Kind.STOREFRONT:
		_grounds(ctx)
	g.commit(node, "Building")
	_finish(ctx)


# --- Materials -----------------------------------------------------------------------------------------

static func _use_mats(g: LandmarkGeo, p: Dictionary) -> void:
	var flood := {"flood_strength": 0.85, "flood_reach": 8.0, "flood_floor": 0.18, "flood_spacing": 4.5, "grime": 0.3, "night_self": 0.02}
	g.use("stucco", LandmarkMats.facade("wor_stucco", "plaster_white", 3.0, _with(flood, {"tint": Color(0.80, 0.77, 0.70), "texture_contrast": 1.4, "grime": 0.45})))
	g.use("stucco_warm", LandmarkMats.facade("wor_stucco_warm", "plaster_beige", 3.0, _with(flood, {"tint": Color(0.92, 0.84, 0.72)})))
	g.use("stone", LandmarkMats.facade("wor_stone", "plaster_beige", 3.0, _with(flood, {"tint": Color(0.86, 0.80, 0.68),
		"joint_spacing": Vector2(1.2, 0.6), "joint_width": 0.012, "joint_dark": 0.3})))
	g.use("trim", LandmarkMats.facade("wor_trim", "plaster_white", 2.0, _with(flood, {"tint": Color(0.84, 0.82, 0.77), "grime": 0.2})))
	g.use("concrete", LandmarkMats.facade("wor_concrete", "concrete_layers", 2.5, _with(flood, {"tint": Color(0.78, 0.77, 0.74),
		"joint_spacing": Vector2(2.4, 0.15), "joint_width": 0.01, "joint_dark": 0.18, "flood_reach": 14.0})))
	g.use("brick", LandmarkMats.facade("wor_brick", "brick_red", 2.4, _with(flood, {"tint": Color(0.95, 0.86, 0.80)})))
	g.use("granite", LandmarkMats.facade("wor_granite", "concrete_cracked", 2.0, {"tint": Color(0.58, 0.58, 0.57),
		"joint_spacing": Vector2(0.9, 0.45), "joint_width": 0.012, "joint_dark": 0.35}))
	g.use("clay", LandmarkMats.clay("wor_clay", {"tile_color": Color(0.64, 0.33, 0.20)}))
	g.use("slate", LandmarkMats.clay("wor_slate", {"tile_color": Color(0.22, 0.23, 0.25), "pitch": 0.3, "course": 0.24, "depth": 0.35}))
	g.use("temple_tile", LandmarkMats.clay("wor_ttile", {"tile_color": Color(0.17, 0.19, 0.19), "pitch": 0.32, "course": 0.30, "depth": 1.1}))
	g.use("metal_roof", LandmarkMats.plain("wor_seam", Color(0.30, 0.31, 0.33), 0.45, 0.7))
	g.use("wood", LandmarkMats.plain("wor_wood", Color(0.36, 0.22, 0.12), 0.55))
	g.use("timber", LandmarkMats.plain("wor_timber", Color(0.30, 0.20, 0.12), 0.8))
	g.use("lacquer", LandmarkMats.plain("wor_lacquer", Color(0.58, 0.08, 0.05), 0.35))
	g.use("paint_white", LandmarkMats.plain("wor_pwhite", Color(0.93, 0.93, 0.90), 0.5))
	g.use("iron", LandmarkMats.plain("wor_iron", Color(0.05, 0.05, 0.05), 0.5, 0.6))
	g.use("bronze", LandmarkMats.plain("wor_bronze", Color(0.42, 0.28, 0.12), 0.35, 0.95))
	g.use("gold", LandmarkMats.plain("wor_gold", Color(0.85, 0.65, 0.28), 0.3, 1.0))
	g.use("dark", LandmarkMats.plain("wor_dark", Color(0.06, 0.06, 0.07), 0.8))
	g.use("glow", _lamp_mat())
	g.use("neon", _neon_mat())
	g.use("glass_stained", _glass(0, int(p.seed) % 4, float(p.seed % 97)))
	g.use("glass_leaded", _glass(1, 0, float(p.seed % 89)))
	g.use("glass_dalle", _glass(2, 3, float(p.seed % 83)))
	g.use("glass_plain", _glass(3, 0, float(p.seed % 79)))
	g.use("lawn", PropFactory.lawn(Color(0.62, 0.74, 0.42), int(p.seed) % 1000, 0.3, 3.0))
	g.use("paving", LandmarkMats.paving("pavers", 3.0, Color(0.9, 0.86, 0.80), int(p.seed) % 1000, 0.9, 0.2))
	g.use("tile_paving", LandmarkMats.paving("pavers", 2.0, Color(0.85, 0.52, 0.38), int(p.seed) % 1000, 0.45, 0.25))
	g.use("gravel", PropFactory.pbr("sand", 2.0, Color(0.78, 0.76, 0.72)))
	g.use("plinth", LandmarkMats.facade("wor_plinth", "concrete", 3.0, {"tint": Color(0.72, 0.71, 0.68)}))


static func _with(a: Dictionary, b: Dictionary) -> Dictionary:
	var out := a.duplicate()
	out.merge(b, true)
	return out


static func _glass(mode: int, palette: int, sd: float) -> ShaderMaterial:
	var k := "glass_%d_%d" % [mode, palette]
	if _mats.has(k):
		return _mats[k]
	var m := ShaderMaterial.new()
	m.shader = load("res://shaders/worship_glass.gdshader")
	m.set_shader_parameter("mode", mode)
	m.set_shader_parameter("palette", palette)
	m.set_shader_parameter("seed", sd)
	m.set_shader_parameter("glow", [2.4, 1.6, 2.6, 1.3][mode])
	_mats[k] = m
	return m


## Lamps and lanterns: dim fittings by day, lit after dark (lamp_factor). Vertex colour tints.
static func _lamp_mat() -> ShaderMaterial:
	if _mats.has("lamp"):
		return _mats.lamp
	var sh := Shader.new()
	sh.code = """shader_type spatial;
#include "res://shaders/color_space.gdshaderinc"
global uniform float lamp_factor;
void fragment() {
	ALBEDO = cs_out(vec3(0.78, 0.74, 0.64) * COLOR.rgb);
	ROUGHNESS = 0.4;
	EMISSION = cs_out(COLOR.rgb * vec3(1.0, 0.84, 0.6) * (0.08 + 3.6 * lamp_factor));
}
"""
	var m := ShaderMaterial.new()
	m.shader = sh
	_mats.lamp = m
	return m


## A storefront church's neon cross: red tube, glowing a little by day, bright after dark.
static func _neon_mat() -> ShaderMaterial:
	if _mats.has("neon"):
		return _mats.neon
	var sh := Shader.new()
	sh.code = """shader_type spatial;
#include "res://shaders/color_space.gdshaderinc"
global uniform float lamp_factor;
void fragment() {
	ALBEDO = cs_out(COLOR.rgb * 0.6);
	ROUGHNESS = 0.3;
	EMISSION = cs_out(COLOR.rgb * (0.6 + 5.0 * lamp_factor));
}
"""
	var m := ShaderMaterial.new()
	m.shader = sh
	_mats.neon = m
	return m


# --- Geometry helpers -------------------------------------------------------------------------------

## A wall: a slab whose outer face starts at `o` (its bottom-left seen from outside), runs along
## `a` (unit, horizontal) for `length`, up from y `o.y` for `height`, facing `n` (unit, horizontal),
## `th` thick (inward). `holes`: [kind, u0, u1, v0, v1, fill] in the face's (u, v) metres (v from
## o.y): kind "rect", "arch" (a rect up to v1 - half its width, then a round head) or "circle"
## (inscribed in the box); fill "" (open: an arcade, a belfry), or a surface key for the pane set
## back `inset` into the reveal. `top` closes the top, `ends` the two ends. UV: u from `u_off`.
static func wall(g: LandmarkGeo, key: String, o: Vector3, a: Vector3, n: Vector3, length: float, height: float, th: float,
		holes: Array = [], top: bool = true, ends: bool = true, u_off: float = 0.0, inset: float = -1.0, reveal_key: String = "") -> void:
	var up := Vector3.UP
	var rk := key if reveal_key == "" else reveal_key
	var at := func(u: float, v: float, t: float) -> Vector3:
		return o + a * u + up * v + n * t
	# Breakpoints: the wall's ends and every hole's samples.
	var us: Array[float] = [0.0, length]
	var hs: Array = []
	for h: Array in holes:
		var info := _hole(h)
		hs.append(info)
		for u: float in info.us:
			us.append(clampf(u, 0.0, length))
	us.sort()
	var clean: Array[float] = []
	for u in us:
		if clean.is_empty() or u - clean.back() > 1e-4:
			clean.append(u)
	for i in clean.size() - 1:
		var ua := clean[i]
		var ub := clean[i + 1]
		var um := (ua + ub) * 0.5
		# The solid intervals of this strip: [0, height] less every hole covering it.
		var cuts: Array = []
		for info: Dictionary in hs:
			if um > float(info.u0) and um < float(info.u1):
				cuts.append([_hlow(info, ua), _hlow(info, ub), _hhigh(info, ua), _hhigh(info, ub)])
		cuts.sort_custom(func(x: Array, y: Array) -> bool: return float(x[0]) + float(x[1]) < float(y[0]) + float(y[1]))
		var la := 0.0
		var lb := 0.0
		for c: Array in cuts:
			_wall_quad(g, key, at, ua, ub, la, lb, c[0], c[1], n, th, u_off)
			la = c[2]
			lb = c[3]
		_wall_quad(g, key, at, ua, ub, la, lb, height, height, n, th, u_off)
	if top:
		g.quad(key, at.call(0.0, height, 0.0), at.call(length, height, 0.0), at.call(length, height, -th), at.call(0.0, height, -th), up,
			Vector2(u_off, 0.0), Vector2(u_off + length, 0.0), Vector2(u_off + length, th), Vector2(u_off, th))
	if ends:
		for e: Array in [[0.0, -a], [length, a]]:
			var u: float = e[0]
			var en: Vector3 = e[1]
			g.quad(key, at.call(u, 0.0, 0.0), at.call(u, height, 0.0), at.call(u, height, -th), at.call(u, 0.0, -th), en,
				Vector2(0.0, o.y), Vector2(0.0, o.y + height), Vector2(th, o.y + height), Vector2(th, o.y))
	# Reveals round each hole, through the thickness, and the panes.
	for info: Dictionary in hs:
		var loop: Array = info.loop
		var m := loop.size()
		var c2: Vector2 = info.c
		for j in m:
			var p0: Vector2 = loop[j]
			var p1: Vector2 = loop[(j + 1) % m]
			if p0.distance_to(p1) < 1e-4:
				continue
			# Inward of the hole is toward its centre: the reveal faces it.
			var mid := (p0 + p1) * 0.5
			var dn := c2 - mid
			var want: Vector3 = (a * dn.x + up * dn.y).normalized()
			if info.kind == "rect" or info.kind == "arch":
				# Straight edges face straight in.
				var e := p1 - p0
				var en2 := Vector2(-e.y, e.x).normalized()
				if en2.dot(dn) < 0.0:
					en2 = -en2
				want = (a * en2.x + up * en2.y).normalized()
			var d0 := p0.distance_to(loop[0])
			g.quad(rk, at.call(p0.x, p0.y, 0.0), at.call(p1.x, p1.y, 0.0), at.call(p1.x, p1.y, -th), at.call(p0.x, p0.y, -th), want,
				Vector2(d0, 0.0), Vector2(d0 + p0.distance_to(p1), 0.0), Vector2(d0 + p0.distance_to(p1), th), Vector2(d0, th))
		var fill: String = info.fill
		if fill != "":
			var t := -th * 0.5 if inset < 0.0 else -inset
			for j in m:
				var p0: Vector2 = loop[j]
				var p1: Vector2 = loop[(j + 1) % m]
				g.tri(fill, at.call(c2.x, c2.y, t), at.call(p0.x, p0.y, t), at.call(p1.x, p1.y, t), n,
					Vector2(c2.x - float(info.u0), c2.y - float(info.v0)), Vector2(p0.x - float(info.u0), p0.y - float(info.v0)),
					Vector2(p1.x - float(info.u0), p1.y - float(info.v0)))


static func _wall_quad(g: LandmarkGeo, key: String, at: Callable, ua: float, ub: float, va0: float, vb0: float, va1: float, vb1: float,
		n: Vector3, th: float, u_off: float) -> void:
	if va1 - va0 < 1e-4 and vb1 - vb0 < 1e-4:
		return
	var p0: Vector3 = at.call(ua, va0, 0.0)
	var p1: Vector3 = at.call(ub, vb0, 0.0)
	var p2: Vector3 = at.call(ub, vb1, 0.0)
	var p3: Vector3 = at.call(ua, va1, 0.0)
	g.quad(key, p0, p1, p2, p3, n, Vector2(u_off + ua, p0.y), Vector2(u_off + ub, p1.y), Vector2(u_off + ub, p2.y), Vector2(u_off + ua, p3.y))
	var q0: Vector3 = at.call(ua, va0, -th)
	var q1: Vector3 = at.call(ub, vb0, -th)
	var q2: Vector3 = at.call(ub, vb1, -th)
	var q3: Vector3 = at.call(ua, va1, -th)
	g.quad(key, q0, q1, q2, q3, -n, Vector2(u_off + ua, q0.y), Vector2(u_off + ub, q1.y), Vector2(u_off + ub, q2.y), Vector2(u_off + ua, q3.y))


## A hole's sampling: its u breakpoints, its outline loop (u, v), centre, kind and fill.
static func _hole(h: Array) -> Dictionary:
	var kind: String = h[0]
	var u0: float = h[1]
	var u1: float = h[2]
	var v0: float = h[3]
	var v1: float = h[4]
	var fill: String = h[5] if h.size() > 5 else ""
	var r := (u1 - u0) * 0.5
	var cu := (u0 + u1) * 0.5
	var info := {"kind": kind, "u0": u0, "u1": u1, "v0": v0, "v1": v1, "fill": fill, "r": r, "cu": cu}
	var us: Array[float] = []
	var loop: Array = []
	var segs := 14
	match kind:
		"rect":
			us = [u0, u1]
			loop = [Vector2(u0, v0), Vector2(u1, v0), Vector2(u1, v1), Vector2(u0, v1)]
			info.c = Vector2(cu, (v0 + v1) * 0.5)
		"arch":
			var spring := v1 - r
			info.spring = spring
			loop = [Vector2(u0, v0), Vector2(u1, v0)]
			for k in segs + 1:
				var t := PI * float(k) / float(segs)
				var p := Vector2(cu + r * cos(t), spring + r * sin(t))
				loop.append(p)
				us.append(p.x)
			info.c = Vector2(cu, (v0 + spring) * 0.5 + r * 0.3)
		_:
			var cv := (v0 + v1) * 0.5
			var rr := minf(r, (v1 - v0) * 0.5)
			info.cv = cv
			info.r = rr
			for k in segs * 2:
				var t := TAU * float(k) / float(segs * 2)
				var p := Vector2(cu + rr * cos(t), cv + rr * sin(t))
				loop.append(p)
				us.append(p.x)
			info.c = Vector2(cu, cv)
	info.us = us
	info.loop = loop
	return info


static func _hlow(info: Dictionary, u: float) -> float:
	if info.kind == "circle":
		var dx := u - float(info.cu)
		return float(info.cv) - sqrt(maxf(float(info.r) * float(info.r) - dx * dx, 0.0))
	return float(info.v0)


static func _hhigh(info: Dictionary, u: float) -> float:
	match String(info.kind):
		"rect":
			return float(info.v1)
		"arch":
			var dx := u - float(info.cu)
			return float(info.spring) + sqrt(maxf(float(info.r) * float(info.r) - dx * dx, 0.0))
	var dx2 := u - float(info.cu)
	return float(info.cv) + sqrt(maxf(float(info.r) * float(info.r) - dx2 * dx2, 0.0))


## A pitched roof over a rectangle centred on `c` (y the eave line), its ridge along local z
## (`along_z`) or x, `span` across the ridge, `length` along it, rising at `pitch` radians,
## overhanging `eave` at the eaves and `rake` at the gable ends. The slopes on `key` (clay_roof
## UV: u along the eave, v up the slope), a fascia and a soffit on `trim_key`, and, if `gables`,
## the two gable triangles on `wall_key`, `wall_th` thick (inset by `gable_in`).
static func gable_roof(g: LandmarkGeo, key: String, trim_key: String, wall_key: String, c: Vector3, span: float, length: float,
		pitch: float, along_z: bool, eave: float = 0.5, rake: float = 0.4, gables: bool = true, gable_in: float = 0.0) -> float:
	var half := span * 0.5
	var rise := tan(pitch) * half
	var ax := Vector3(0, 0, 1) if along_z else Vector3(1, 0, 0)
	var ac := Vector3(1, 0, 0) if along_z else Vector3(0, 0, 1)
	var hl := length * 0.5 + rake
	var top := c + Vector3.UP * rise
	var drop := tan(pitch) * eave
	for side: float in [-1.0, 1.0]:
		var e0 := c + ac * side * (half + eave) - Vector3.UP * drop - ax * hl
		var e1 := c + ac * side * (half + eave) - Vector3.UP * drop + ax * hl
		var r0 := top - ax * hl
		var r1 := top + ax * hl
		var slope_len := (half + eave) / cos(pitch)
		var want := (ac * side * sin(pitch) + Vector3.UP * cos(pitch)).normalized()
		g.quad(key, e0, e1, r1, r0, want, Vector2(0.0, 0.0), Vector2(hl * 2.0, 0.0), Vector2(hl * 2.0, slope_len), Vector2(0.0, slope_len))
		# The underside (soffit) of the slab, 0.18 under it.
		var dn := Vector3.DOWN * 0.18
		g.quad(trim_key, e0 + dn, e1 + dn, r1 + dn, r0 + dn, -want, Vector2(0, e0.y), Vector2(hl * 2.0, e1.y), Vector2(hl * 2.0, r1.y), Vector2(0, r0.y))
		# Fascia along the eave.
		g.quad(trim_key, e0, e1, e1 + dn, e0 + dn, ac * side, Vector2(0, e0.y), Vector2(hl * 2.0, e1.y), Vector2(hl * 2.0, e1.y - 0.18), Vector2(0, e0.y - 0.18))
		# The verges at the gable ends.
		for en: float in [-1.0, 1.0]:
			var a0 := e0 if en < 0.0 else e1
			var a1 := r0 if en < 0.0 else r1
			g.quad(trim_key, a0, a1, a1 + dn, a0 + dn, ax * en, Vector2(0, a0.y), Vector2(slope_len, a1.y), Vector2(slope_len, a1.y - 0.18), Vector2(0, a0.y - 0.18))
	# Ridge cap.
	g.box(trim_key if key != "clay" and key != "temple_tile" else key, top + Vector3.UP * 0.05, (ax * (hl * 2.0) + ac * 0.34 + Vector3.UP * 0.2).abs())
	if gables:
		for en: float in [-1.0, 1.0]:
			var base := c + ax * en * (length * 0.5 - gable_in)
			var p0 := base - ac * half
			var p1 := base + ac * half
			var pt := base + Vector3.UP * rise
			g.tri(wall_key, p0, p1, pt, ax * en, Vector2(0.0, p0.y), Vector2(span, p1.y), Vector2(half, pt.y))
	return rise


## A body of revolution round `c` (the axis vertical): `prof` is [radius, height] from the bottom
## up, smooth-shaded, `segs` round. For domes, bells, finials, lanterns, column bases.
static func lathe(g: LandmarkGeo, key: String, c: Vector3, prof: Array, segs: int = 16, col: Color = Color.WHITE) -> void:
	var m := prof.size()
	var nrm: Array[Vector2] = []
	for i in m:
		var pa: Vector2 = prof[maxi(i - 1, 0)]
		var pb: Vector2 = prof[mini(i + 1, m - 1)]
		var d := pb - pa
		nrm.append(Vector2(d.y, -d.x).normalized() if d.length() > 1e-5 else Vector2(1, 0))
	for i in m - 1:
		var a: Vector2 = prof[i]
		var b: Vector2 = prof[i + 1]
		for k in segs:
			var t0 := TAU * float(k) / float(segs)
			var t1 := TAU * float(k + 1) / float(segs)
			var d0 := Vector3(cos(t0), 0.0, sin(t0))
			var d1 := Vector3(cos(t1), 0.0, sin(t1))
			var na0 := d0 * nrm[i].x + Vector3.UP * nrm[i].y
			var na1 := d1 * nrm[i].x + Vector3.UP * nrm[i].y
			var nb0 := d0 * nrm[i + 1].x + Vector3.UP * nrm[i + 1].y
			var nb1 := d1 * nrm[i + 1].x + Vector3.UP * nrm[i + 1].y
			var v00 := c + d0 * a.x + Vector3.UP * a.y
			var v01 := c + d1 * a.x + Vector3.UP * a.y
			var v10 := c + d0 * b.x + Vector3.UP * b.y
			var v11 := c + d1 * b.x + Vector3.UP * b.y
			var u0 := t0 * maxf(a.x, 0.2)
			var u1 := t1 * maxf(a.x, 0.2)
			if a.x < 1e-4:
				g.tri(key, v00, v11, v10, nb0 + nb1, Vector2(u0, v00.y), Vector2(u1, v11.y), Vector2(u0, v10.y), col, false, na0, nb1, nb0)
			elif b.x < 1e-4:
				g.tri(key, v00, v01, v10, na0 + na1, Vector2(u0, v00.y), Vector2(u1, v01.y), Vector2(u0, v10.y), col, false, na0, na1, nb0)
			else:
				g.quad_n(key, v00, v10, v11, v01, na0, nb0, nb1, na1, Vector2(u0, v00.y), Vector2(u0, v10.y), Vector2(u1, v11.y), Vector2(u1, v01.y), col)


## A classical column at `base`: a square plinth, a moulded base, a shaft with entasis (16 sides,
## 20 for the big ones) and a capital (Doric echinus and abacus).
static func column(g: LandmarkGeo, key: String, base: Vector3, r: float, h: float) -> void:
	var pl := r * 1.25
	g.box(key, base + Vector3(0, 0.12, 0), Vector3(pl * 2.0, 0.24, pl * 2.0))
	var shaft := h - 0.24 - 0.62
	lathe(g, key, base + Vector3(0, 0.24, 0), [Vector2(r * 1.15, 0.0), Vector2(r * 1.15, 0.08), Vector2(r * 1.04, 0.16), Vector2(r, 0.24),
		Vector2(r * 0.99, shaft * 0.33), Vector2(r * 0.93, shaft * 0.7), Vector2(r * 0.84, shaft), Vector2(r * 0.84, shaft + 0.04),
		Vector2(r * 0.9, shaft + 0.1), Vector2(r * 1.12, shaft + 0.3), Vector2(r * 1.18, shaft + 0.36)], 20)
	g.box(key, base + Vector3(0, h - 0.13, 0), Vector3(r * 2.5, 0.26, r * 2.5))


## A cross: an upright and a bar, `h` tall, facing along local z, on `key`.
static func cross(g: LandmarkGeo, key: String, base: Vector3, h: float, t: float = -1.0, yaw: float = 0.0) -> void:
	var w := t if t > 0.0 else h * 0.09
	var b := Basis(Vector3.UP, yaw)
	g.box(key, base + Vector3.UP * h * 0.5, Vector3(w, h, w), Color.WHITE, b)
	g.box(key, base + Vector3.UP * h * 0.72, Vector3(h * 0.58, w, w), Color.WHITE, b)


## A bell hanging from a yoke at `top`, mouth down, `r` at the lip.
static func bell(g: LandmarkGeo, top: Vector3, r: float) -> void:
	var h := r * 1.5
	lathe(g, "bronze", top - Vector3.UP * h, [Vector2(r * 1.02, 0.0), Vector2(r, 0.06 * h), Vector2(r * 0.8, 0.25 * h), Vector2(r * 0.66, 0.55 * h),
		Vector2(r * 0.6, 0.85 * h), Vector2(r * 0.45, h), Vector2(0.0, h * 1.02)], 16)
	g.box("timber", top + Vector3.UP * 0.12, Vector3(r * 3.2, 0.22, 0.22))


## A flat-topped rectangle of ground (local, y), with a skirt down `skirt` m on `skirt_key` so a
## slight slope never shows a gap.
static func ground(g: LandmarkGeo, key: String, r: Rect2, y: float, skirt: float = 0.0, skirt_key: String = "") -> void:
	var a := Vector3(r.position.x, y, r.position.y)
	var b := Vector3(r.end.x, y, r.position.y)
	var c := Vector3(r.end.x, y, r.end.y)
	var d := Vector3(r.position.x, y, r.end.y)
	g.quad(key, a, b, c, d, Vector3.UP, Vector2(a.x, a.z), Vector2(b.x, b.z), Vector2(c.x, c.z), Vector2(d.x, d.z))
	if skirt > 0.0:
		var sk := skirt_key if skirt_key != "" else key
		for e: Array in [[a, b, Vector3.FORWARD], [b, c, Vector3.RIGHT], [c, d, Vector3.BACK], [d, a, Vector3.LEFT]]:
			var p0: Vector3 = e[0]
			var p1: Vector3 = e[1]
			g.quad(sk, p0, p1, p1 - Vector3.UP * skirt, p0 - Vector3.UP * skirt, e[2], Vector2(0, p0.y), Vector2(p0.distance_to(p1), p1.y),
				Vector2(p0.distance_to(p1), p1.y - skirt), Vector2(0, p0.y - skirt))


## Steps up to `h` across `w`, the top step's nose at `front` (local z of the riser line facing +z),
## treads `tread` deep, centred on x `cx`; the top landing runs back to `back_z`.
static func steps(g: LandmarkGeo, key: String, cx: float, w: float, front: float, h: float, back_z: float, tread: float = 0.36) -> void:
	var n := maxi(1, ceili(h / 0.17))
	var rise := h / float(n)
	for i in n:
		var y1 := rise * float(i + 1)
		var z_front := front + tread * float(n - 1 - i)
		var depth := z_front - back_z
		g.box(key, Vector3(cx, y1 * 0.5, z_front - depth * 0.5), Vector3(w, y1, depth))


# --- Grounds ---------------------------------------------------------------------------------------------

## What every place of worship has round it: the lawn less the paths and the building, the path to
## the door, a low wall or fence on the street with a gap at the path, the name board, trees, a
## lamp or two.
static func _grounds(ctx: Dictionary) -> void:
	var g: LandmarkGeo = ctx.g
	var p: Dictionary = ctx.p
	var L: float = p.L
	var D: float = p.D
	var kind: int = p.kind
	var site := Rect2(-L * 0.5 + 0.1, -D + 0.1, L - 0.2, D - 0.2)
	var holes: Array[Rect2] = []
	for r: Rect2 in ctx.paved:
		holes.append(r)
	for r: Rect2 in ctx.get("footprints", []):
		holes.append(r)
	var paved_key := "gravel" if kind == Worship.Kind.TEMPLE else ("tile_paving" if kind == Worship.Kind.MISSION else "paving")
	for r: Rect2 in ctx.paved:
		ground(g, paved_key, r.intersection(site), 0.07, 1.4, "plinth")
	for r: Rect2 in LotFill._minus(site, holes, 0.0):
		if r.size.x > 0.3 and r.size.y > 0.3:
			ground(g, "lawn", r, 0.05, 1.4, "plinth")
	# Under every building a plinth down past the lowest corner of a sloping site.
	for r: Rect2 in ctx.get("footprints", []):
		g.box("plinth", Vector3(r.get_center().x, -0.75, r.get_center().y), Vector3(r.size.x, 1.6, r.size.y))
	# The street edge: a wall or a fence on a plinth, broken at the path.
	var path_w: float = ctx.get("path_w", 3.0)
	var path_x: float = ctx.get("path_x", 0.0)
	var gap0 := path_x - path_w * 0.5
	var gap1 := path_x + path_w * 0.5
	var runs := [[-L * 0.5 + 0.3, gap0], [gap1, L * 0.5 - 0.3]]
	for rn: Array in runs:
		var x0: float = rn[0]
		var x1: float = rn[1]
		if x1 - x0 < 0.5:
			continue
		var cx := (x0 + x1) * 0.5
		var len := x1 - x0
		match kind:
			Worship.Kind.MISSION:
				g.box("stucco", Vector3(cx, 0.5, -0.45), Vector3(len, 1.0, 0.42))
				g.box("clay", Vector3(cx, 1.04, -0.45), Vector3(len + 0.1, 0.1, 0.56))
			Worship.Kind.TEMPLE:
				g.box("granite", Vector3(cx, 0.6, -0.45), Vector3(len, 1.2, 0.5), Color.WHITE, Basis(), 0.04)
				g.box("temple_tile", Vector3(cx, 1.28, -0.45), Vector3(len + 0.1, 0.16, 0.8))
			Worship.Kind.MODERN:
				g.box("concrete", Vector3(cx, 0.35, -0.5), Vector3(len, 0.7, 0.4))
			_:
				g.box("granite" if kind == Worship.Kind.SYNAGOGUE else "brick", Vector3(cx, 0.3, -0.45), Vector3(len, 0.6, 0.4))
				g.box("trim", Vector3(cx, 0.63, -0.45), Vector3(len + 0.04, 0.06, 0.46))
				# Iron railings: a top and bottom rail and pickets every 12 cm.
				g.box("iron", Vector3(cx, 0.78, -0.45), Vector3(len, 0.04, 0.04))
				g.box("iron", Vector3(cx, 1.72, -0.45), Vector3(len, 0.05, 0.05))
				var n := int(len / 0.13)
				for k in n:
					var x := x0 + (float(k) + 0.5) * len / float(n)
					g.box("iron", Vector3(x, 1.22, -0.45), Vector3(0.022, 1.0, 0.022))
					if k % 2 == 0:
						lathe(g, "iron", Vector3(x, 1.74, -0.45), [Vector2(0.03, 0.0), Vector2(0.0, 0.1)], 4)
		LandmarkGeo.shape_box(ctx.body, Vector3(cx, 0.7, -0.45), Vector3(len, 1.4, 0.5))
	# Gate piers either side of the path.
	if kind != Worship.Kind.TEMPLE:
		for gx: float in [gap0 - 0.3, gap1 + 0.3]:
			var pk := "stucco" if kind == Worship.Kind.MISSION else ("concrete" if kind == Worship.Kind.MODERN else "granite")
			g.box(pk, Vector3(gx, 0.85, -0.45), Vector3(0.6, 1.7, 0.6), Color.WHITE, Basis(), 0.03)
			g.box("trim" if kind != Worship.Kind.MISSION else "clay", Vector3(gx, 1.76, -0.45), Vector3(0.72, 0.12, 0.72))
			if kind != Worship.Kind.MODERN:
				g.box("glow", Vector3(gx, 2.02, -0.45), Vector3(0.24, 0.32, 0.24))
				ctx.pools.append([Vector3(gx, 0.08, -0.8), Vector2(4.0, 4.0), 0.7])
	# The name board, by the path, set back from the wall.
	var bx := gap1 + 2.6 if gap1 + 5.2 < L * 0.5 else gap0 - 2.6
	var board_w := 3.4
	var bk := "stucco" if kind == Worship.Kind.MISSION else ("concrete" if kind == Worship.Kind.MODERN else "granite")
	g.box(bk, Vector3(bx, 0.7, -1.6), Vector3(board_w, 1.4, 0.45), Color.WHITE, Basis(), 0.04)
	g.box("dark", Vector3(bx, 0.82, -1.36), Vector3(board_w - 0.4, 0.9, 0.04))
	g.box("glow", Vector3(bx, 1.33, -1.33), Vector3(board_w - 0.4, 0.04, 0.03), Color(0.9, 0.9, 0.9))
	LandmarkGeo.shape_box(ctx.body, Vector3(bx, 0.7, -1.6), Vector3(board_w, 1.4, 0.45))
	ctx.text.append([String(ctx.s.name), Vector3(bx, 1.0, -1.33), 0.17, board_w - 0.6, Color(0.95, 0.92, 0.82)])
	ctx.text.append([_service_line(kind, int(p.seed)), Vector3(bx, 0.62, -1.33), 0.11, board_w - 0.6, Color(0.85, 0.82, 0.7)])
	ctx.pools.append([Vector3(bx, 0.08, -0.2), Vector2(4.5, 3.0), 0.6])
	# Trees in the lawn, by hash, clear of the building, the paths and each other.
	var placed: Array[Vector2] = []
	var want := int(clampf(L * D / 260.0, 3.0, 9.0))
	var feet: Array = ctx.get("footprints", [])
	for t in 40:
		if placed.size() >= want:
			break
		var x := lerpf(-L * 0.5 + 2.5, L * 0.5 - 2.5, Worship.h01([p.seed, t, "tx"]))
		var z := lerpf(-D + 2.5, -2.4, Worship.h01([p.seed, t, "tz"]))
		var q := Vector2(x, z)
		var ok := true
		for r: Rect2 in ctx.paved:
			if r.grow(1.2).has_point(q):
				ok = false
		for r: Rect2 in feet:
			if r.grow(3.5).has_point(q):
				ok = false
		for o: Vector2 in placed:
			if o.distance_to(q) < 6.0:
				ok = false
		if absf(x - bx) < 3.0 and z > -3.5:
			ok = false
		if ok:
			placed.append(q)
			ctx.trees.append(q)


static func _service_line(kind: int, sd: int) -> String:
	var hours := ["9:00", "10:00", "10:30", "11:00", "8:30"]
	var h: String = hours[sd % hours.size()]
	match kind:
		Worship.Kind.MISSION:
			return "MISAS DOMINGO %s  -  SUNDAY MASS 12:00" % h
		Worship.Kind.TEMPLE:
			return "MEDITATION SUNDAY %s  -  ALL WELCOME" % h
		Worship.Kind.SYNAGOGUE:
			return "SHABBAT SERVICES FRIDAY 7:30  -  SATURDAY %s" % h
		Worship.Kind.STOREFRONT:
			return "SERVICIOS DOMINGO %s  -  MIERCOLES 7:00" % h
	return "SUNDAY WORSHIP %s  -  ALL ARE WELCOME" % h


## After the mesh: collision, trees, lamps, pools, lettering.
static func _finish(ctx: Dictionary) -> void:
	var ch: CityChunk = ctx.ch
	var node: Node3D = ctx.node
	var xf: Transform3D = ctx.xf
	var p: Dictionary = ctx.p
	var yaw := xf.basis.get_euler().y
	for q: Vector2 in ctx.trees:
		var at := xf * Vector3(q.x, 0.0, q.y)
		at.y -= ch._gy(at.x, at.z)
		var palm := int(p.kind) == Worship.Kind.MISSION and Worship.h01([p.seed, q.x, "palm"]) < 0.6
		var tint := Color(0.95 + 0.1 * Worship.h01([p.seed, q.x, "ta"]), 1.0, 0.95)
		if palm:
			var v := absi(hash([p.seed, q.x, "pv"])) % PropFactory.PALM_VARIANTS
			var s := 0.85 + 0.3 * Worship.h01([p.seed, q.y, "ps"])
			ch._batch.add("palm_%d" % v, PropFactory.palm(v), Transform3D(Basis(Vector3.UP, Worship.h01([p.seed, q, "py"]) * TAU).scaled(Vector3(s, s, s)), at), tint)
		else:
			var variant := absi(hash([p.seed, q.x, q.y, "tv"])) % PropFactory.CITY_TREES.size()
			var s := PropFactory.city_tree_scale(variant, 7.0 + 4.0 * Worship.h01([p.seed, q, "th"]))
			var variety := Color(Worship.h01([p.seed, q, 1]), Worship.h01([p.seed, q, 2]), Worship.h01([p.seed, q, 3]), 0.6)
			ch._batch.add("tree_%d" % variant, PropFactory.model_tree(variant), Transform3D(Basis(Vector3.UP, Worship.h01([p.seed, q, "ty"]) * TAU).scaled(Vector3(s, s, s)), at), tint, variety)
	for pl: Array in ctx.pools:
		var at: Vector3 = xf * (pl[0] as Vector3)
		at.y -= ch._gy(at.x, at.z)
		var sz: Vector2 = pl[1]
		var pool := Transform3D(Basis(Vector3.UP, yaw) * Basis(Vector3.RIGHT, -PI * 0.5).scaled(Vector3(sz.x, 1.0, sz.y)), at)
		ch._batch.add("wor_pool", PropFactory.light_pool(Color(1.0, 1.0, 1.0), 1.3, 1.6), pool, Color(1.0, 0.84, 0.6, float(pl[2])))
	if not ctx.pools.is_empty():
		ch._batch.set_no_shadow("wor_pool")
	for li: Array in ctx.lights:
		var light := OmniLight3D.new()
		light.position = li[0]
		light.omni_range = float(li[1])
		light.omni_attenuation = 1.3
		light.light_color = Color(1.0, 0.82, 0.58)
		light.light_energy = 0.0
		light.shadow_enabled = false
		light.distance_fade_enabled = true
		light.distance_fade_begin = 80.0
		light.distance_fade_length = 20.0
		light.add_to_group("lamp_light")
		node.add_child(light)
	if not OS.has_feature("web"):
		var k := 0
		for tx: Array in ctx.text:
			var size: float = tx[2]
			var text: String = tx[0]
			# Fit the line to its width: a TextMesh at font size 64 is about 0.62 em a letter.
			var fit := minf(size, float(tx[3]) / maxf(float(text.length()) * 0.62, 1.0))
			var mi := MeshInstance3D.new()
			mi.name = "Text%d" % k
			mi.mesh = BigVehicles.text_mesh(text, fit, tx[4])
			mi.position = tx[1]
			if tx.size() > 5:
				mi.rotation.y = float(tx[5])
			mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			mi.visibility_range_end = 90.0
			node.add_child(mi)
			k += 1
	for bx: Array in ctx.get("shapes", []):
		LandmarkGeo.shape_box(ctx.body, bx[0], bx[1])
	node.set_meta("triangles", LandmarkGeo.committed_triangles)


# --- Mission Revival -----------------------------------------------------------------------------------

static func _mission(ctx: Dictionary) -> void:
	var g: LandmarkGeo = ctx.g
	var p: Dictionary = ctx.p
	var W: float = p.W
	var nl: float = p.NL
	var fz: float = p.fz
	var xc: float = p.xc
	var H: float = p.H
	var th := 0.9
	var zf := -fz
	var zb := -fz - nl
	var x0 := xc - W * 0.5
	var x1 := xc + W * 0.5
	ctx.footprints = [Rect2(x0 - 5.4, zb, W + 5.4 + 4.6, nl)]
	ctx.shapes = [[Vector3(xc, H * 0.5, (zf + zb) * 0.5), Vector3(W, H, nl)]]
	# Side windows: tall round-headed lights between buttresses / arches, 4.2 m apart.
	var bays := maxi(3, int((nl - 4.0) / 4.2))
	var pitch := (nl - 4.0) / float(bays)
	var side_holes: Array = []
	for i in bays:
		var u := 2.0 + pitch * (float(i) + 0.5)
		side_holes.append(["arch", u - 0.65, u + 0.65, 3.6, 7.4, "glass_stained"])
	# Left wall (faces -x), along -z from the front: u runs back.
	wall(g, "stucco", Vector3(x0, 0, zf), Vector3(0, 0, -1), Vector3(-1, 0, 0), nl, H, th, side_holes)
	wall(g, "stucco", Vector3(x1, 0, zb), Vector3(0, 0, 1), Vector3(1, 0, 0), nl, H, th, side_holes)
	# Back wall with its gable.
	wall(g, "stucco", Vector3(x1, 0, zb), Vector3(-1, 0, 0), Vector3(0, 0, -1), W, H, th, [])
	# Buttresses down the left wall (the right has the arcade).
	for i in bays + 1:
		var z := zf - 2.0 - pitch * float(i)
		g.box("stucco", Vector3(x0 - 0.45, 2.6, z), Vector3(0.9, 5.2, 1.0), Color.WHITE, Basis(), 0.05)
		g.box("stucco", Vector3(x0 - 0.25, 6.0, z), Vector3(0.5, 1.6, 1.0), Color.WHITE, Basis(), 0.05)
	# The roof: clay over the nave, the gable at the back, the facade's parapet at the front.
	gable_roof(g, "clay", "timber", "stucco", Vector3(xc, H, (zf + zb) * 0.5), W, nl, deg_to_rad(27.0), true, 0.7, 0.1, false)
	var rise := tan(deg_to_rad(27.0)) * W * 0.5
	g.tri("stucco", Vector3(x0, H, zb - KEEP), Vector3(x1, H, zb - KEEP), Vector3(xc, H + rise, zb - KEEP), Vector3(0, 0, -1),
		Vector2(0, H), Vector2(W, H), Vector2(W * 0.5, H + rise))
	g.tri("stucco", Vector3(x0, H, zb + th), Vector3(x1, H, zb + th), Vector3(xc, H + rise, zb + th), Vector3(0, 0, 1),
		Vector2(0, H), Vector2(W, H), Vector2(W * 0.5, H + rise))
	# The facade: the wall with its door and the window over it, then the curvilinear parapet.
	var fw := W + 0.8
	var fx0 := xc - fw * 0.5
	var door_w := 3.0
	var fh := H + 2.6
	wall(g, "stucco", Vector3(fx0, 0, zf + th), Vector3(1, 0, 0), Vector3(0, 0, 1), fw, fh, th + 0.3,
		[["arch", fw * 0.5 - door_w * 0.5, fw * 0.5 + door_w * 0.5, 0.0, 5.0, "wood"],
		["circle", fw * 0.5 - 1.15, fw * 0.5 + 1.15, 7.0, 9.3, "glass_stained"]], false, true, 0.0, 0.7)
	# The door's surround: a cast-stone moulding round the arch and pilasters each side.
	for sx: float in [-1.0, 1.0]:
		g.box("trim", Vector3(xc + sx * (door_w * 0.5 + 0.35), 2.0, zf + th + 0.08), Vector3(0.45, 4.0, 0.16))
		g.box("trim", Vector3(xc + sx * (fw * 0.5 - 0.35), fh * 0.5, zf + th + 0.1), Vector3(0.7, fh, 0.2))
	for k in 13:
		var t := PI * float(k) / 12.0
		g.box("trim", Vector3(xc + cos(t) * (door_w * 0.5 + 0.35), 3.5 + sin(t) * (door_w * 0.5 + 0.35), zf + th + 0.08),
			Vector3(0.5, 0.45, 0.16), Color.WHITE, Basis(Vector3(0, 0, 1), t))
	# The window's moulded ring.
	for k in 20:
		var t := TAU * float(k) / 20.0
		g.box("trim", Vector3(xc + cos(t) * 1.32, 8.15 + sin(t) * 1.32, zf + th + 0.08), Vector3(0.48, 0.3, 0.16), Color.WHITE, Basis(Vector3(0, 0, 1), t + PI * 0.5))
	# The curvilinear parapet (espadana): scrolls up from the corner piers to a crest with a niche.
	var prof: Array[Vector2] = []
	var hw := fw * 0.5
	var crest := fh + 4.4
	var pts := [Vector2(hw, 0.0), Vector2(hw, 0.6), Vector2(hw - 0.5, 0.6)]
	for k in range(1, 9):
		var t := float(k) / 8.0
		pts.append(Vector2(lerpf(hw - 0.5, hw - 3.0, t), 0.6 + 2.0 * (1.0 - cos(t * PI * 0.5))))
	pts.append(Vector2(hw - 3.0, 3.0))
	pts.append(Vector2(2.2, 3.0))
	for k in range(1, 11):
		var t := PI * 0.5 * float(k) / 10.0
		pts.append(Vector2(2.2 * cos(t), 3.0 + (crest - fh - 3.0) * sin(t)))
	for q: Vector2 in pts:
		prof.append(Vector2(xc + q.x, fh + q.y))
	for k in range(pts.size() - 1, -1, -1):
		var q: Vector2 = pts[k]
		if q.x > 0.01:
			prof.append(Vector2(xc - q.x, fh + q.y))
	_slab_profile(g, "stucco", prof, zf + th + 0.3, zf - 0.3, "trim")
	# A small niche bell in the crest, and the cross on top.
	var nz := zf + 0.1
	wall(g, "stucco", Vector3(xc - 0.9, fh + 2.2, zf + th + 0.32), Vector3(1, 0, 0), Vector3(0, 0, 1), 1.8, 2.0, 0.02,
		[["arch", 0.25, 1.55, 0.2, 1.9, ""]], false, false)
	bell(g, Vector3(xc, fh + 3.85, nz), 0.42)
	cross(g, "iron", Vector3(xc, crest - 0.05, zf + 0.2), 1.6, 0.11)
	# Bell tower at the front left.
	var tw: float = p.tower
	var tc := Vector3(x0 - tw * 0.5 + 0.5, 0, zf - tw * 0.5 + th + 0.3)
	ctx.shapes.append([tc + Vector3(0, 9.0, 0), Vector3(tw, 18.0, tw)])
	ctx.footprints.append(Rect2(tc.x - tw * 0.5, tc.z - tw * 0.5, tw, tw))
	var shaft_h := 12.6
	g.box("stucco", tc + Vector3(0, shaft_h * 0.5, 0), Vector3(tw, shaft_h, tw))
	# Narrow slit windows up the shaft and a clock-sized round light.
	for k in 2:
		g.box("glass_stained", tc + Vector3(0, 4.0 + float(k) * 3.8, tw * 0.5 + KEEP), Vector3(0.4, 1.6, 0.02))
	g.box("trim", tc + Vector3(0, shaft_h + 0.15, 0), Vector3(tw + 0.5, 0.3, tw + 0.5), Color.WHITE, Basis(), 0.04)
	# The belfry: four arched openings, a bell in each, open to the sky.
	var bel0 := shaft_h + 0.3
	var bh := 5.2
	var bt := 0.7
	var bw := tw - 0.6
	var bc := tc + Vector3(0, bel0, 0)
	for f: Array in [[Vector3(-bw * 0.5, 0, bw * 0.5), Vector3(1, 0, 0), Vector3(0, 0, 1)], [Vector3(bw * 0.5, 0, -bw * 0.5), Vector3(-1, 0, 0), Vector3(0, 0, -1)],
			[Vector3(bw * 0.5, 0, bw * 0.5), Vector3(0, 0, -1), Vector3(1, 0, 0)], [Vector3(-bw * 0.5, 0, -bw * 0.5), Vector3(0, 0, 1), Vector3(-1, 0, 0)]]:
		wall(g, "stucco", bc + (f[0] as Vector3), f[1], f[2], bw, bh, bt, [["arch", 0.9, bw - 0.9, 0.9, bh - 0.6, ""]], true, false)
	bell(g, bc + Vector3(0, bh - 0.9, 0), 0.62)
	g.box("trim", bc + Vector3(0, bh + 0.15, 0), Vector3(tw + 0.5, 0.3, tw + 0.5), Color.WHITE, Basis(), 0.04)
	g.box("stucco", bc + Vector3(0, -0.02, 0), Vector3(bw, 0.06, bw))
	# The cap: a tiled dome on a drum, a lantern and the cross.
	var cap := bc + Vector3(0, bh + 0.3, 0)
	lathe(g, "stucco", cap, [Vector2(tw * 0.42, 0.0), Vector2(tw * 0.42, 0.7)], 16)
	lathe(g, "clay", cap + Vector3(0, 0.7, 0), [Vector2(tw * 0.46, 0.0), Vector2(tw * 0.44, 0.5), Vector2(tw * 0.36, 1.3), Vector2(tw * 0.22, 1.9),
		Vector2(0.35, 2.15), Vector2(0.0, 2.2)], 16)
	lathe(g, "trim", cap + Vector3(0, 2.85, 0), [Vector2(0.3, 0.0), Vector2(0.25, 0.4), Vector2(0.12, 0.55), Vector2(0.0, 0.6)], 10)
	cross(g, "iron", cap + Vector3(0, 3.4, 0), 1.6, 0.1)
	ctx.p.top = cap.y + 5.0
	# The arcade (corredor) down the right side: piers and round arches under a shed roof.
	var ad: float = p.arcade
	var ax := x1 + ad
	var arches := maxi(3, int(nl / 3.4))
	var ap := nl / float(arches)
	var a_holes: Array = []
	for i in arches:
		var u := ap * (float(i) + 0.5)
		a_holes.append(["arch", u - ap * 0.5 + 0.38, u + ap * 0.5 - 0.38, 0.0, 3.9, ""])
	wall(g, "stucco", Vector3(ax, 0, zb), Vector3(0, 0, 1), Vector3(1, 0, 0), nl, 4.6, 0.75, a_holes)
	# The arcade's end arches.
	for e: Array in [[zf, 1.0], [zb, -1.0]]:
		var ez: float = e[0]
		var sg: float = e[1]
		wall(g, "stucco", Vector3(x1 + (0.0 if sg > 0.0 else ad), 0, ez), Vector3(sg, 0, 0), Vector3(0, 0, sg), ad, 4.6, 0.75,
			[["arch", 0.5, ad - 0.75, 0.0, 3.9, ""]], true, false)
	# Its shed roof, from the nave wall down over the piers.
	var r0 := Vector3(x1 + KEEP, 6.1, zb - 0.4)
	var r1 := Vector3(x1 + KEEP, 6.1, zf + 0.4)
	var r2 := Vector3(ax + 0.6, 4.7, zf + 0.4)
	var r3 := Vector3(ax + 0.6, 4.7, zb - 0.4)
	var sl := r0.distance_to(r3)
	g.quad("clay", r0, r1, r2, r3, Vector3(0.3, 1, 0).normalized(), Vector2(nl + 0.8, sl), Vector2(0, sl), Vector2(0, 0), Vector2(nl + 0.8, 0))
	g.quad("timber", r0 - Vector3.UP * 0.15, r1 - Vector3.UP * 0.15, r2 - Vector3.UP * 0.15, r3 - Vector3.UP * 0.15, Vector3(-0.3, -1, 0).normalized(),
		Vector2(0, r0.y), Vector2(nl, r1.y), Vector2(nl, r2.y), Vector2(0, r3.y))
	# Exposed rafter ends under it.
	for i in int(nl / 0.8):
		var z := zb + 0.4 + float(i) * 0.8
		g.box("timber", Vector3((x1 + ax) * 0.5 + 0.3, 5.15, z), Vector3(ad + 0.9, 0.16, 0.12), Color.WHITE, Basis(Vector3(0, 0, 1), atan2(1.4, ad)))
	ctx.paved.append(Rect2(x1, zb, ad + 0.8, nl))
	# Lanterns under the arcade and by the door.
	for i in 3:
		var z := lerpf(zf - 2.0, zb + 2.0, float(i) / 2.0)
		g.box("iron", Vector3(x1 + ad * 0.5, 4.2, z), Vector3(0.03, 0.6, 0.03))
		g.box("glow", Vector3(x1 + ad * 0.5, 3.7, z), Vector3(0.28, 0.42, 0.28))
		ctx.pools.append([Vector3(x1 + ad * 0.5, 0.1, z), Vector2(5.0, 5.0), 0.8])
	for sx: float in [-1.0, 1.0]:
		g.box("glow", Vector3(xc + sx * 2.3, 3.0, zf + th + 0.35), Vector3(0.3, 0.5, 0.3))
	ctx.lights.append([Vector3(xc, 4.0, zf + 3.0), 11.0])
	# The forecourt and the path.
	ctx.path_w = 4.0
	ctx.path_x = xc
	ctx.paved.append(Rect2(xc - 2.0, zf + th, 4.0, -zf - th))
	ctx.paved.append(Rect2(xc - W * 0.5 - 0.4, zf + th, W + 0.8 + ad, 4.0))
	ctx.pools.append([Vector3(xc, 0.1, zf + 3.0), Vector2(9.0, 7.0), 0.9])
	ctx.text.append([String(ctx.s.name), Vector3(xc, 5.45, zf + th + 0.32), 0.3, W - 2.0, Color(0.36, 0.24, 0.14)])
	# A low planter of the cross-shaped garden in the forecourt: a cross of paths with a fountain.
	var fx := xc - W * 0.5 - 1.0
	if fx - 4.0 > -p.L * 0.5 + 2.0 and zf + th + 2.0 < -3.0:
		pass


## A vertical profile polygon (x, y in local x and height) extruded between local z `z_front`
## and `z_back`, its outline capped with `cap_key` along the top edges.
static func _slab_profile(g: LandmarkGeo, key: String, prof: Array[Vector2], z_front: float, z_back: float, cap_key: String) -> void:
	var poly := PackedVector2Array(prof)
	var idx := Geometry2D.triangulate_polygon(poly)
	if idx.is_empty():
		var r := poly.duplicate()
		r.reverse()
		poly = r
		idx = Geometry2D.triangulate_polygon(poly)
	for i in range(0, idx.size(), 3):
		var a := poly[idx[i]]
		var b := poly[idx[i + 1]]
		var c := poly[idx[i + 2]]
		g.tri(key, Vector3(a.x, a.y, z_front), Vector3(b.x, b.y, z_front), Vector3(c.x, c.y, z_front), Vector3(0, 0, 1), Vector2(a.x, a.y), Vector2(b.x, b.y), Vector2(c.x, c.y))
		g.tri(key, Vector3(a.x, a.y, z_back), Vector3(b.x, b.y, z_back), Vector3(c.x, c.y, z_back), Vector3(0, 0, -1), Vector2(a.x, a.y), Vector2(b.x, b.y), Vector2(c.x, c.y))
	var n := poly.size()
	var cen := Vector2.ZERO
	for q in poly:
		cen += q
	cen /= float(n)
	var u := 0.0
	for i in n:
		var a := poly[i]
		var b := poly[(i + 1) % n]
		var e := b - a
		if e.length() < 1e-4:
			continue
		var en := Vector2(-e.y, e.x).normalized()
		if en.dot((a + b) * 0.5 - cen) < 0.0:
			en = -en
		# Edges on the bottom line (where it meets the wall) are hidden.
		if en.y < -0.9:
			continue
		var k := cap_key if en.y > 0.3 else key
		g.quad(k, Vector3(a.x, a.y, z_front), Vector3(b.x, b.y, z_front), Vector3(b.x, b.y, z_back), Vector3(a.x, a.y, z_back), Vector3(en.x, en.y, 0),
			Vector2(u, z_front), Vector2(u + e.length(), z_front), Vector2(u + e.length(), z_back), Vector2(u, z_back))
		u += e.length()


# --- Modern concrete -------------------------------------------------------------------------------------

static func _modern(ctx: Dictionary) -> void:
	var g: LandmarkGeo = ctx.g
	var p: Dictionary = ctx.p
	var W: float = p.W
	var nl: float = p.NL
	var fz: float = p.fz
	var xc: float = p.xc
	var wh: float = p.wall
	var zf := -fz
	var zb := -fz - nl
	var x0 := xc - W * 0.5
	var x1 := xc + W * 0.5
	ctx.footprints = [Rect2(x0, zb, W, nl)]
	ctx.shapes = [[Vector3(xc, 4.0, (zf + zb) * 0.5), Vector3(W, 8.0, nl)]]
	# Low board-formed side walls with a band of dalle-de-verre slits.
	var slits: Array = []
	var n := int(nl / 1.6)
	for i in n:
		var u := 0.8 + float(i) * (nl - 1.6) / float(maxi(n - 1, 1))
		slits.append(["rect", u - 0.22, u + 0.22, 0.6, wh - 0.5, "glass_dalle"])
	wall(g, "concrete", Vector3(x0, 0, zf), Vector3(0, 0, -1), Vector3(-1, 0, 0), nl, wh, 0.5, slits)
	wall(g, "concrete", Vector3(x1, 0, zb), Vector3(0, 0, 1), Vector3(1, 0, 0), nl, wh, 0.5, slits)
	# The great roof: two steep standing-seam slopes from the low walls to a ridge high over the
	# altar, the ridge rising from the entrance to the back (a folded tent).
	var pitch_front := atan2(p.ridge - 4.0 - wh, W * 0.5)
	var rh_front: float = p.ridge - 4.0
	var rh_back: float = p.ridge
	var eave := 1.2
	for side: float in [-1.0, 1.0]:
		var e0 := Vector3(xc + side * (W * 0.5 + eave), wh - 0.6, zf + 1.4)
		var e1 := Vector3(xc + side * (W * 0.5 + eave), wh - 0.6, zb - 0.8)
		var r0 := Vector3(xc, rh_front, zf + 1.4)
		var r1 := Vector3(xc, rh_back, zb - 0.8)
		var want := (e0 - r0).cross(r1 - r0)
		if want.y < 0.0:
			want = -want
		g.quad("metal_roof", e0, e1, r1, r0, want, Vector2(0, 0), Vector2(nl, 0), Vector2(nl, 10), Vector2(0, 10))
		g.quad("concrete", e0 - Vector3.UP * 0.3, e1 - Vector3.UP * 0.3, r1 - Vector3.UP * 0.3, r0 - Vector3.UP * 0.3, -want,
			Vector2(0, e0.y), Vector2(nl, e1.y), Vector2(nl, r1.y), Vector2(0, r0.y))
		g.quad("dark", e0, e1, e1 - Vector3.UP * 0.3, e0 - Vector3.UP * 0.3, Vector3(side, 0, 0), Vector2.ZERO, Vector2(nl, 0), Vector2(nl, 0.3), Vector2(0, 0.3))
		# Standing seams: a thin rib every 1.4 m down each slope.
		var seams := int(nl / 1.4)
		for k in seams:
			var t := (float(k) + 0.5) / float(seams)
			var a := e0.lerp(e1, t)
			var b := r0.lerp(r1, t)
			var rib_c := (a + b) * 0.5 + want.normalized() * 0.03
			var dir := (b - a)
			var bas := Basis(dir.cross(want).normalized(), dir.normalized(), want.normalized())
			g.box("metal_roof", rib_c, Vector3(0.04, dir.length(), 0.06), Color.WHITE, bas)
	# The front gable: one wall of coloured glass in a concrete grid, the entrance under it.
	var fg_h := rh_front
	var gz := zf + 1.0
	var gl := Vector3(x0 - eave + 0.3, wh - 0.6, gz)
	# The triangle of glass (two triangles), with a concrete frame along its edges.
	var apex := Vector3(xc, fg_h - 0.4, gz)
	var lft := Vector3(x0 + 0.4, 0.0, gz)
	var rgt := Vector3(x1 - 0.4, 0.0, gz)
	var lft_up := Vector3(x0 + 0.4, wh - 0.4, gz)
	var rgt_up := Vector3(x1 - 0.4, wh - 0.4, gz)
	for q: Array in [[lft, rgt, rgt_up], [lft, rgt_up, lft_up], [lft_up, rgt_up, apex]]:
		var a: Vector3 = q[0]
		var b: Vector3 = q[1]
		var c: Vector3 = q[2]
		g.tri("glass_dalle", a, b, c, Vector3(0, 0, 1), Vector2(a.x - x0, a.y), Vector2(b.x - x0, b.y), Vector2(c.x - x0, c.y))
	for e: Array in [[lft_up, apex], [rgt_up, apex], [lft, lft_up], [rgt, rgt_up]]:
		var a: Vector3 = e[0]
		var b: Vector3 = e[1]
		var d := b - a
		g.box("concrete", (a + b) * 0.5, Vector3(0.5, d.length() + 0.4, 0.6), Color.WHITE, Basis(Vector3(0, 0, 1), atan2(-d.x, d.y)))
	# A concrete cross mullion through the glass.
	g.box("concrete", Vector3(xc, fg_h * 0.45, gz + 0.1), Vector3(0.45, fg_h * 0.8, 0.5))
	g.box("concrete", Vector3(xc, fg_h * 0.55, gz + 0.1), Vector3(3.2, 0.45, 0.5))
	g.quad("glass_dalle", Vector3(x0 + 0.4, 0.0, zb), Vector3(x1 - 0.4, 0.0, zb), Vector3(xc, rh_back - 0.4, zb), Vector3(xc, rh_back - 0.4, zb), Vector3(0, 0, -1),
		Vector2(0, 0), Vector2(W, 0), Vector2(W * 0.5, rh_back), Vector2(W * 0.5, rh_back))
	g.tri("concrete", Vector3(x0, wh - 0.4, zb - 0.02), Vector3(x1, wh - 0.4, zb - 0.02), Vector3(xc, rh_back - 0.3, zb - 0.02), Vector3(0, 0, -1),
		Vector2(0, wh), Vector2(W, wh), Vector2(W * 0.5, rh_back))
	# The entrance canopy: a thin cantilevered slab on two blade walls, the doors under it.
	g.box("concrete", Vector3(xc, 3.1, gz + 3.0), Vector3(9.0, 0.3, 6.0))
	for sx: float in [-1.0, 1.0]:
		g.box("concrete", Vector3(xc + sx * 4.2, 1.5, gz + 3.8), Vector3(0.35, 3.0, 4.0))
	g.box("dark", Vector3(xc, 1.25, gz + 0.06), Vector3(3.6, 2.5, 0.08))
	g.box("bronze", Vector3(xc, 1.25, gz + 0.12), Vector3(0.06, 2.4, 0.06))
	for k in 6:
		g.box("glow", Vector3(xc - 3.0 + float(k) * 1.2, 2.93, gz + 3.0), Vector3(0.3, 0.04, 0.3))
	ctx.pools.append([Vector3(xc, 0.1, gz + 3.0), Vector2(10.0, 8.0), 0.9])
	ctx.lights.append([Vector3(xc, 2.7, gz + 3.0), 10.0])
	ctx.text.append([String(ctx.s.name), Vector3(xc, 3.45, gz + 6.02), 0.32, 8.4, Color(0.9, 0.9, 0.88)])
	# The campanile: a free-standing board-formed slab with a slot through it and a steel cross.
	var cx := clampf(x1 + 4.5, -p.L * 0.5 + 2.0, p.L * 0.5 - 2.0)
	var cz := zf + 2.0
	var chh: float = p.camp_h
	ctx.footprints.append(Rect2(cx - 1.6, cz - 3.1, 3.2, 6.2))
	ctx.shapes.append([Vector3(cx, chh * 0.5, cz), Vector3(3.0, chh, 6.0)])
	var co := Vector3(cx - 1.5, 0, cz + 3.0)
	wall(g, "concrete", co, Vector3(1, 0, 0), Vector3(0, 0, 1), 3.0, chh, 6.0, [["rect", 0.45, 2.55, chh - 8.0, chh - 1.6, ""]], true, true)
	# The slot is cut right through the slab (front to back): a cross hangs in it.
	cross(g, "bronze", Vector3(cx, chh - 7.6, cz), 5.4, 0.3)
	g.box("glow", Vector3(cx, chh - 7.9, cz), Vector3(0.5, 0.06, 0.5))
	ctx.p.top = chh + 1.0
	ctx.path_w = 5.0
	ctx.path_x = xc
	ctx.paved.append(Rect2(xc - 2.5, gz + 0.5, 5.0, -gz - 0.5))
	ctx.paved.append(Rect2(minf(xc - 5.5, cx - 2.6), gz + 0.5, maxf(11.0, cx + 2.6 - (xc - 5.5)), 7.0))


# --- Storefront church ---------------------------------------------------------------------------------

static func _storefront(ctx: Dictionary) -> void:
	var g: LandmarkGeo = ctx.g
	var p: Dictionary = ctx.p
	var W: float = p.W
	var bd: float = p.BD
	var H: float = p.H
	var x0 := -W * 0.5
	var sd: int = p.seed
	var wall_key := "stucco_warm" if sd % 2 == 0 else "stucco"
	ctx.shapes = [[Vector3(0, H * 0.5, -bd * 0.5), Vector3(W, H, bd)]]
	# The shopfront: two plate windows (curtains drawn, lit inside) and the glass door between them.
	var dw := 1.8
	var holes := [["rect", W * 0.5 - dw * 0.5, W * 0.5 + dw * 0.5, 0.0, 2.6, "glass_plain"]]
	var side_w := (W - dw) * 0.5 - 1.2
	if side_w > 1.2:
		holes.append(["rect", 0.7, 0.7 + side_w, 0.5, 3.0, "glass_plain"])
		holes.append(["rect", W - 0.7 - side_w, W - 0.7, 0.5, 3.0, "glass_plain"])
	wall(g, wall_key, Vector3(x0, 0, 0.0), Vector3(1, 0, 0), Vector3(0, 0, 1), W, H, 0.4, holes, true, false, 0.0, 0.2)
	# Storefront framing (aluminium mullions and a kick plate).
	for hh: Array in holes:
		var u0: float = hh[1]
		var u1: float = hh[2]
		var v0: float = hh[3]
		var v1: float = hh[4]
		for u: float in [u0, u1]:
			g.box("bronze", Vector3(x0 + u, (v0 + v1) * 0.5, -0.18), Vector3(0.07, v1 - v0, 0.1))
		g.box("bronze", Vector3(x0 + (u0 + u1) * 0.5, v1 - 0.03, -0.18), Vector3(u1 - u0, 0.07, 0.1))
	# The other walls and the roof.
	wall(g, wall_key, Vector3(x0, 0, -bd), Vector3(0, 0, 1), Vector3(-1, 0, 0), bd, H, 0.3, [], true, false)
	wall(g, wall_key, Vector3(-x0, 0, 0.0), Vector3(0, 0, -1), Vector3(1, 0, 0), bd, H, 0.3, [], true, false)
	wall(g, wall_key, Vector3(-x0, 0, -bd), Vector3(-1, 0, 0), Vector3(0, 0, -1), W, H, 0.3, [], true, false)
	g.box("dark", Vector3(0, H - 0.6, -bd * 0.5), Vector3(W - 0.6, 0.1, bd - 0.6))
	# The sign band over the windows: a painted board with the church's name, and a neon cross.
	g.box("paint_white", Vector3(0, 3.95, 0.12), Vector3(W - 0.6, 1.1, 0.16), Color(0.94, 0.93, 0.9))
	g.box("dark", Vector3(0, 3.95, 0.06), Vector3(W - 0.4, 1.3, 0.06))
	g.box("trim", Vector3(0, H + 0.15, 0.0), Vector3(W + 0.1, 0.3, 0.5))
	var nx := W * 0.5 - 1.1
	var neon_c := Color(1.0, 0.12, 0.10) if sd % 3 != 0 else Color(0.2, 0.55, 1.0)
	g.box("neon", Vector3(nx, 4.0, 0.26), Vector3(0.09, 1.0, 0.09), neon_c)
	g.box("neon", Vector3(nx, 4.18, 0.26), Vector3(0.62, 0.09, 0.09), neon_c)
	# A gooseneck lamp over the door and the hours on the glass.
	g.box("iron", Vector3(0, 3.2, 0.3), Vector3(0.05, 0.05, 0.6))
	g.box("glow", Vector3(0, 3.1, 0.55), Vector3(0.36, 0.12, 0.3))
	ctx.pools.append([Vector3(0, 0.05, 1.6), Vector2(minf(W, 9.0), 4.0), 0.85])
	ctx.lights.append([Vector3(0, 2.8, 1.4), 8.0])
	ctx.text.append([String(ctx.s.name), Vector3(-0.4, 3.95, 0.21), 0.42, W - 3.2, Color(0.12, 0.16, 0.42) if sd % 2 == 0 else Color(0.5, 0.08, 0.06)])
	ctx.text.append([_service_line(Worship.Kind.STOREFRONT, sd), Vector3(0, 2.75, 0.05), 0.08, minf(W - 1.0, 5.0), Color(0.95, 0.95, 0.9)])
	ctx.text.append(["TODOS BIENVENIDOS  -  ALL WELCOME", Vector3(0, 0.25, 0.1), 0.07, minf(W - 1.0, 4.0), Color(0.95, 0.9, 0.7)])
	# The yard behind (what is left of the lot): paving and a fence line, nothing tall.
	if p.D - bd > 2.0:
		ground(g, "paving", Rect2(x0, -p.D + 0.1, W, p.D - bd - 0.2), 0.05, 0.6, "plinth")
	ctx.p.top = H + 1.0


# --- Greek revival ---------------------------------------------------------------------------------------

static func _greek(ctx: Dictionary) -> void:
	var g: LandmarkGeo = ctx.g
	var p: Dictionary = ctx.p
	var W: float = p.W
	var nl: float = p.NL
	var fz: float = p.fz
	var H: float = p.H
	var pod: float = p.pod
	var pd: float = p.portico
	var body_key := "brick" if bool(p.brick) else "stucco"
	var zp := -fz
	var zf := zp - pd
	var zb := zf - nl
	var x0 := -W * 0.5
	ctx.footprints = [Rect2(x0 - 0.3, zb, W + 0.6, nl + pd + 1.0)]
	ctx.shapes = [[Vector3(0, (H + pod) * 0.5, (zf + zb) * 0.5), Vector3(W, H + pod, nl)], [Vector3(0, pod * 0.5, zp - pd * 0.5), Vector3(W, pod, pd)]]
	# The podium under body and portico, and the steps across the front.
	g.box("granite", Vector3(0, pod * 0.5, (zp + zb) * 0.5), Vector3(W + 0.4, pod, zp - zb), Color.WHITE, Basis(), 0.03)
	steps(g, "granite", 0.0, W - 2.0, zp + 0.36 * 6.0, pod, zp - 0.2)
	# Body: tall windows (leaded, warm at night) between pilasters, a water table, a cornice.
	var bays := maxi(3, int(nl / 4.4))
	var bp := nl / float(bays)
	var wins: Array = []
	for i in bays:
		var u := bp * (float(i) + 0.5)
		wins.append(["arch", u - 0.85, u + 0.85, 1.6, 7.8, "glass_leaded"])
	wall(g, body_key, Vector3(x0, pod, zf), Vector3(0, 0, -1), Vector3(-1, 0, 0), nl, H, 0.6, wins, true, false, 0.0, 0.35, "trim")
	wall(g, body_key, Vector3(-x0, pod, zb), Vector3(0, 0, 1), Vector3(1, 0, 0), nl, H, 0.6, wins, true, false, 0.0, 0.35, "trim")
	wall(g, body_key, Vector3(-x0, pod, zb), Vector3(-1, 0, 0), Vector3(0, 0, -1), W, H, 0.6, [], true, true)
	# The front wall inside the portico: the great door and two windows.
	wall(g, body_key, Vector3(x0, pod, zf), Vector3(1, 0, 0), Vector3(0, 0, 1), W, H, 0.6,
		[["rect", W * 0.5 - 1.5, W * 0.5 + 1.5, 0.0, 4.6, "wood"], ["arch", 2.0, 3.6, 1.6, 7.8, "glass_leaded"], ["arch", W - 3.6, W - 2.0, 1.6, 7.8, "glass_leaded"]],
		true, true, 0.0, 0.35, "trim")
	g.box("trim", Vector3(0, pod + 4.9, zf + 0.15), Vector3(4.2, 0.6, 0.3))
	for sx: float in [-1.0, 1.0]:
		g.box("trim", Vector3(sx * 1.75, pod + 2.3, zf + 0.1), Vector3(0.35, 4.6, 0.2))
	for i in bays + 1:
		var z := zf - bp * float(i)
		for sx: float in [-1.0, 1.0]:
			g.box("trim", Vector3(sx * (W * 0.5 + 0.12), pod + H * 0.5, z), Vector3(0.25, H, 0.7))
	g.box("trim", Vector3(0, pod + 0.3, (zf + zb) * 0.5), Vector3(W + 0.3, 0.6, nl + 0.2))
	# Entablature round the body and portico: architrave, frieze, cornice.
	var ent := pod + H
	g.box("trim", Vector3(0, ent + 0.35, (zp + zb) * 0.5), Vector3(W + 0.5, 0.7, zp - zb + 0.3))
	g.box("trim", Vector3(0, ent + 0.95, (zp + zb) * 0.5), Vector3(W + 0.5, 0.5, zp - zb + 0.3))
	g.box("trim", Vector3(0, ent + 1.3, (zp + zb) * 0.5), Vector3(W + 1.2, 0.2, zp - zb + 1.0), Color.WHITE, Basis(), 0.05)
	# Six columns across the portico.
	var cols := 6
	var colh := H
	for i in cols:
		var x := lerpf(x0 + 0.8, -x0 - 0.8, float(i) / float(cols - 1))
		column(g, "trim", Vector3(x, pod, zp - 0.8), 0.48, colh)
	# The roof and the pediment.
	var top_y := ent + 1.4
	var pitch := deg_to_rad(21.0)
	gable_roof(g, "slate", "trim", "trim", Vector3(0, top_y, (zp + zb) * 0.5), W + 1.0, zp - zb + 0.6, pitch, true, 0.15, 0.25, false)
	var rise := tan(pitch) * (W + 1.0) * 0.5
	# Pediment: the tympanum set back, the raking cornices proud of it, an oculus in it.
	var pz := zp + 0.1
	g.tri("trim", Vector3(-W * 0.5, top_y, pz - 0.15), Vector3(W * 0.5, top_y, pz - 0.15), Vector3(0, top_y + rise - 0.3, pz - 0.15), Vector3(0, 0, 1),
		Vector2(0, top_y), Vector2(W, top_y), Vector2(W * 0.5, top_y + rise))
	g.tri("trim", Vector3(-W * 0.5, top_y, zb - 0.2), Vector3(W * 0.5, top_y, zb - 0.2), Vector3(0, top_y + rise - 0.3, zb - 0.2), Vector3(0, 0, -1),
		Vector2(0, top_y), Vector2(W, top_y), Vector2(W * 0.5, top_y + rise))
	for sx: float in [-1.0, 1.0]:
		var a := Vector3(sx * (W * 0.5 + 0.5), top_y, pz + 0.1)
		var b := Vector3(0, top_y + rise + 0.05, pz + 0.1)
		var d := b - a
		g.box("trim", (a + b) * 0.5, Vector3(d.length(), 0.35, 0.6), Color.WHITE, Basis(Vector3(0, 0, 1), atan2(d.y, d.x)), 0.04)
	g.box("glass_leaded", Vector3(0, top_y + rise * 0.4, pz - 0.12), Vector3(1.2, 1.2, 0.02), Color.WHITE, Basis(Vector3(0, 0, 1), PI * 0.25))
	# The steeple: a square base out of the roof, a belfry with louvred arches, an octagonal lantern
	# and the spire, all painted white, a gilt ball and cross on top.
	var sz := zf - 2.6
	var sb := top_y + rise * 0.55
	var s0 := 4.2
	ctx.shapes.append([Vector3(0, sb + 4.5, sz), Vector3(s0, 9.0, s0)])
	g.box("paint_white", Vector3(0, sb + 2.0, sz), Vector3(s0, 4.0 + rise * 0.6, s0))
	g.box("paint_white", Vector3(0, sb + 4.1, sz), Vector3(s0 + 0.4, 0.25, s0 + 0.4), Color.WHITE, Basis(), 0.04)
	var bb := sb + 4.25
	var bw := s0 - 0.6
	for f: Array in [[Vector3(-bw * 0.5, 0, bw * 0.5), Vector3(1, 0, 0), Vector3(0, 0, 1)], [Vector3(bw * 0.5, 0, -bw * 0.5), Vector3(-1, 0, 0), Vector3(0, 0, -1)],
			[Vector3(bw * 0.5, 0, bw * 0.5), Vector3(0, 0, -1), Vector3(1, 0, 0)], [Vector3(-bw * 0.5, 0, -bw * 0.5), Vector3(0, 0, 1), Vector3(-1, 0, 0)]]:
		wall(g, "paint_white", Vector3(0, bb, sz) + (f[0] as Vector3), f[1], f[2], bw, 3.6, 0.3, [["arch", 0.7, bw - 0.7, 0.4, 3.1, "dark"]], true, false, 0.0, 0.25)
	for sx: float in [-1.0, 1.0]:
		for sz2: float in [-1.0, 1.0]:
			g.box("paint_white", Vector3(sx * bw * 0.5, bb + 1.8, sz + sz2 * bw * 0.5), Vector3(0.45, 3.6, 0.45))
	g.box("paint_white", Vector3(0, bb + 3.75, sz), Vector3(bw + 0.6, 0.3, bw + 0.6), Color.WHITE, Basis(), 0.05)
	var lt := bb + 3.9
	lathe(g, "paint_white", Vector3(0, lt, sz), [Vector2(1.35, 0.0), Vector2(1.35, 2.2), Vector2(1.5, 2.3), Vector2(1.5, 2.5), Vector2(1.2, 2.5)], 8)
	lathe(g, "paint_white", Vector3(0, lt + 2.5, sz), [Vector2(1.2, 0.0), Vector2(0.9, 2.5), Vector2(0.5, 5.5), Vector2(0.12, 8.0), Vector2(0.0, 8.2)], 8)
	lathe(g, "gold", Vector3(0, lt + 10.6, sz), [Vector2(0.0, 0.0), Vector2(0.2, 0.08), Vector2(0.24, 0.24), Vector2(0.2, 0.4), Vector2(0.0, 0.48)], 10)
	cross(g, "gold", Vector3(0, lt + 11.05, sz), 1.2, 0.07)
	ctx.p.top = lt + 12.5
	# Lamps on the portico and the steps.
	for sx: float in [-1.0, 1.0]:
		g.box("iron", Vector3(sx * 1.9, pod + 3.4, zf + 0.25), Vector3(0.05, 0.05, 0.4))
		g.box("glow", Vector3(sx * 1.9, pod + 3.2, zf + 0.45), Vector3(0.3, 0.45, 0.3))
	ctx.lights.append([Vector3(0, pod + 4.0, zp - 2.0), 10.0])
	ctx.pools.append([Vector3(0, pod + 0.05, zp - pd * 0.5), Vector2(W - 1.0, pd), 0.8])
	ctx.pools.append([Vector3(0, 0.1, zp + 3.0), Vector2(10.0, 6.0), 0.6])
	ctx.text.append([String(ctx.s.name), Vector3(0, ent + 0.95, zp + 0.17), 0.36, W - 2.0, Color(0.25, 0.24, 0.22)])
	ctx.path_w = 4.0
	ctx.path_x = 0.0
	ctx.paved.append(Rect2(-2.0, zp + 2.2, 4.0, -zp - 2.2))
	ctx.paved.append(Rect2(-W * 0.5, zp, W, 2.4))


# --- Buddhist temple -------------------------------------------------------------------------------------

static func _temple(ctx: Dictionary) -> void:
	var g: LandmarkGeo = ctx.g
	var p: Dictionary = ctx.p
	var W: float = p.W
	var HD: float = p.HD
	var fz: float = p.fz
	var pod: float = p.pod
	var eave_y: float = p.eave
	var zf := -fz
	var zb := zf - HD
	var zc := (zf + zb) * 0.5
	ctx.footprints = [Rect2(-W * 0.5 - 1.0, zb - 1.0, W + 2.0, HD + 2.0)]
	ctx.shapes = [[Vector3(0, pod * 0.5, zc), Vector3(W + 2.0, pod, HD + 2.0)], [Vector3(0, pod + 3.0, zc), Vector3(W - 3.6, 6.0, HD - 3.6)]]
	# The stone podium and its steps.
	g.box("granite", Vector3(0, pod * 0.5, zc), Vector3(W + 2.0, pod, HD + 2.0), Color.WHITE, Basis(), 0.04)
	g.box("granite", Vector3(0, pod + 0.05, zc), Vector3(W + 2.3, 0.12, HD + 2.3))
	steps(g, "granite", 0.0, 6.0, zf + 1.0 + 0.36 * 7.0, pod, zf + 0.5)
	# The hall: white plaster walls inside a red colonnade (the veranda 1.8 m wide all round).
	var ver := 1.8
	var iw := W - ver * 2.0
	var idp := HD - ver * 2.0
	var wy := pod + 0.12
	var wall_h := eave_y - wy - 0.5
	var bays := maxi(3, int(iw / 3.0))
	var fh: Array = []
	for i in bays:
		var u := iw * (float(i) + 0.5) / float(bays)
		if i == bays / 2:
			fh.append(["rect", u - 1.2, u + 1.2, 0.0, 3.4, "glass_leaded"])
		else:
			fh.append(["rect", u - 0.9, u + 0.9, 0.9, 3.6, "glass_leaded"])
	wall(g, "stucco", Vector3(-iw * 0.5, wy, zf - ver), Vector3(1, 0, 0), Vector3(0, 0, 1), iw, wall_h, 0.35, fh, true, true, 0.0, 0.18, "timber")
	var sh: Array = []
	var sbays := maxi(2, int(idp / 3.0))
	for i in sbays:
		var u := idp * (float(i) + 0.5) / float(sbays)
		sh.append(["rect", u - 0.8, u + 0.8, 0.9, 3.4, "glass_leaded"])
	wall(g, "stucco", Vector3(-iw * 0.5, wy, zb + ver), Vector3(0, 0, 1), Vector3(-1, 0, 0), idp, wall_h, 0.35, sh, true, false, 0.0, 0.18, "timber")
	wall(g, "stucco", Vector3(iw * 0.5, wy, zf - ver), Vector3(0, 0, -1), Vector3(1, 0, 0), idp, wall_h, 0.35, sh, true, false, 0.0, 0.18, "timber")
	wall(g, "stucco", Vector3(iw * 0.5, wy, zb + ver), Vector3(-1, 0, 0), Vector3(0, 0, -1), iw, wall_h, 0.35, [], true, true)
	# Timber frame on the walls: a sill, a head rail and posts, the wall panels between them.
	for f: Array in [[Vector3(0, 0, zf - ver + 0.04), Vector3(iw, 0, 0)], [Vector3(0, 0, zb + ver - 0.04), Vector3(iw, 0, 0)]]:
		var c: Vector3 = f[0]
		g.box("timber", Vector3(0, wy + 0.15, c.z), Vector3(iw + 0.1, 0.3, 0.14))
		g.box("timber", Vector3(0, wy + 3.8, c.z), Vector3(iw + 0.1, 0.24, 0.14))
	# The red columns round the veranda, with brackets under the eave beam.
	var nx := maxi(4, int(W / 3.0) + 1)
	var nz := maxi(3, int(HD / 3.0) + 1)
	var col_pts: Array[Vector2] = []
	for i in nx:
		var x := lerpf(-W * 0.5 + 0.4, W * 0.5 - 0.4, float(i) / float(nx - 1))
		col_pts.append(Vector2(x, zf - 0.4))
		col_pts.append(Vector2(x, zb + 0.4))
	for j in range(1, nz - 1):
		var z := lerpf(zf - 0.4, zb + 0.4, float(j) / float(nz - 1))
		col_pts.append(Vector2(-W * 0.5 + 0.4, z))
		col_pts.append(Vector2(W * 0.5 - 0.4, z))
	var ch := eave_y - wy - 0.6
	for q: Vector2 in col_pts:
		lathe(g, "granite", Vector3(q.x, wy, q.y), [Vector2(0.36, 0.0), Vector2(0.36, 0.18), Vector2(0.28, 0.3)], 12)
		lathe(g, "lacquer", Vector3(q.x, wy + 0.3, q.y), [Vector2(0.24, 0.0), Vector2(0.24, ch - 0.3)], 12)
		g.box("lacquer", Vector3(q.x, wy + ch - 0.1, q.y), Vector3(0.7, 0.24, 0.7))
	# Eave beams over the columns (front, back and sides), green-and-gold painted bands.
	for z: float in [zf - 0.4, zb + 0.4]:
		g.box("lacquer", Vector3(0, wy + ch + 0.2, z), Vector3(W - 0.4, 0.4, 0.4))
		g.box("gold", Vector3(0, wy + ch + 0.45, z), Vector3(W - 0.4, 0.1, 0.42))
	for x: float in [-W * 0.5 + 0.4, W * 0.5 - 0.4]:
		g.box("lacquer", Vector3(x, wy + ch + 0.2, zc), Vector3(0.4, 0.4, HD - 0.4))
	# The great roof: hip-and-gable, concave, its corners swept up, dark tiles.
	_curved_roof(g, Vector3(0, eave_y, zc), W + 3.2, HD + 3.2, float(p.ridge) - eave_y, 1.1)
	# The ridge and its end ornaments.
	var rl := (W + 3.2) * 0.5 - (HD + 3.2) * 0.5 + 1.0
	var ry: float = p.ridge
	g.box("temple_tile", Vector3(0, ry + 0.25, zc), Vector3(maxf(rl * 2.0, 2.0) + 0.6, 0.6, 0.55), Color.WHITE, Basis(), 0.06)
	for sx: float in [-1.0, 1.0]:
		lathe(g, "temple_tile", Vector3(sx * (maxf(rl, 1.0) + 0.3), ry + 0.5, zc), [Vector2(0.4, 0.0), Vector2(0.32, 0.6), Vector2(0.48, 1.1), Vector2(0.0, 1.5)], 8)
	lathe(g, "gold", Vector3(0, ry + 0.55, zc), [Vector2(0.3, 0.0), Vector2(0.38, 0.3), Vector2(0.2, 0.7), Vector2(0.06, 1.2), Vector2(0.0, 1.5)], 12)
	ctx.p.top = ry + 3.0
	# The front doors (lit at night) and a lantern each side.
	for sx: float in [-1.0, 1.0]:
		g.box("iron", Vector3(sx * 2.4, wy + ch - 0.4, zf - 0.5), Vector3(0.03, 0.5, 0.03))
		lathe(g, "glow", Vector3(sx * 2.4, wy + ch - 1.25, zf - 0.5), [Vector2(0.0, 0.0), Vector2(0.24, 0.12), Vector2(0.28, 0.45), Vector2(0.22, 0.72), Vector2(0.0, 0.8)], 10, Color(1.0, 0.5, 0.3))
	ctx.lights.append([Vector3(0, wy + 3.0, zf + 1.0), 10.0])
	ctx.pools.append([Vector3(0, pod + 0.1, zf - 0.9), Vector2(W, 2.6), 0.7])
	# The gate on the street: two red posts, tie beams and a small curved tile roof.
	var gw := 4.6
	for sx: float in [-1.0, 1.0]:
		lathe(g, "granite", Vector3(sx * gw * 0.5, 0, -1.0), [Vector2(0.4, 0.0), Vector2(0.38, 0.5)], 10)
		lathe(g, "lacquer", Vector3(sx * gw * 0.5, 0.5, -1.0), [Vector2(0.24, 0.0), Vector2(0.24, 3.6)], 12)
		ctx.shapes.append([Vector3(sx * gw * 0.5, 2.0, -1.0), Vector3(0.5, 4.0, 0.5)])
	g.box("lacquer", Vector3(0, 3.6, -1.0), Vector3(gw + 1.6, 0.35, 0.42))
	g.box("lacquer", Vector3(0, 2.9, -1.0), Vector3(gw, 0.25, 0.3))
	g.box("dark", Vector3(0, 3.25, -0.82), Vector3(1.8, 0.45, 0.05))
	_curved_roof(g, Vector3(0, 3.95, -1.0), gw + 2.6, 2.4, 1.1, 0.35)
	# Stone lanterns along the path, lit at night.
	var nl2 := maxi(2, int((fz - 5.0) / 6.0))
	for i in nl2:
		var z := lerpf(-4.5, zf + 3.5, float(i) / float(maxi(nl2 - 1, 1)))
		for sx: float in [-1.0, 1.0]:
			var lb := Vector3(sx * 2.6, 0, z)
			g.box("granite", lb + Vector3(0, 0.1, 0), Vector3(0.7, 0.2, 0.7))
			lathe(g, "granite", lb + Vector3(0, 0.2, 0), [Vector2(0.14, 0.0), Vector2(0.12, 0.8)], 6)
			g.box("granite", lb + Vector3(0, 1.05, 0), Vector3(0.6, 0.12, 0.6))
			g.box("glow", lb + Vector3(0, 1.32, 0), Vector3(0.36, 0.4, 0.36), Color(1.0, 0.7, 0.45))
			lathe(g, "granite", lb + Vector3(0, 1.52, 0), [Vector2(0.55, 0.0), Vector2(0.4, 0.15), Vector2(0.1, 0.35), Vector2(0.0, 0.45)], 6)
			ctx.pools.append([lb + Vector3(0, 0.1, 0), Vector2(3.0, 3.0), 0.5])
	# An incense burner on legs in front of the steps.
	var ib := Vector3(0, 0, zf + 4.0)
	lathe(g, "bronze", ib, [Vector2(0.0, 0.0), Vector2(0.5, 0.35), Vector2(0.6, 0.7), Vector2(0.55, 0.95), Vector2(0.62, 1.0), Vector2(0.0, 1.0)], 14)
	ctx.path_w = 4.0
	ctx.path_x = 0.0
	ctx.paved.append(Rect2(-W * 0.5 - 1.0, zf + 0.5, W + 2.0, -zf - 0.5))


## A concave hip roof over a rectangle centred on `c` (its eave line), `w` x `d`, rising `rise`
## to a ridge, its corners swept up by `lift`: rings of rounded rectangles from the eave to the
## ridge, so the tiles run down the slope (clay_roof's u round the eave, v up).
static func _curved_roof(g: LandmarkGeo, c: Vector3, w: float, d: float, rise: float, lift: float) -> void:
	var rings := 8
	var per := 10
	var grid: Array = []
	var hw := w * 0.5
	var hd := d * 0.5
	var ridge_half := maxf(hw - hd + 1.0, 0.6)
	for j in rings + 1:
		var s := float(j) / float(rings)
		# Concave: the slope is shallow at the eave and steep near the ridge.
		var y := rise * pow(s, 1.7)
		var ax := lerpf(hw, ridge_half, s)
		var az := lerpf(hd, 0.25, s)
		var ring: Array[Vector3] = []
		var corners := [Vector2(-ax, -az), Vector2(ax, -az), Vector2(ax, az), Vector2(-ax, az)]
		for side in 4:
			var a: Vector2 = corners[side]
			var b: Vector2 = corners[(side + 1) % 4]
			for k in per:
				var t := float(k) / float(per)
				var q := a.lerp(b, t)
				var corner := pow(absf(q.x) / maxf(ax, 0.01), 6.0) * pow(absf(q.y) / maxf(az, 0.01), 6.0)
				var up := lift * corner * pow(1.0 - s, 2.0)
				ring.append(c + Vector3(q.x, y + up, q.y))
		grid.append(ring)
	var m := 4 * per
	for j in rings:
		var ra: Array = grid[j]
		var rb: Array = grid[j + 1]
		for k in m:
			var a: Vector3 = ra[k]
			var b: Vector3 = ra[(k + 1) % m]
			var cc: Vector3 = rb[(k + 1) % m]
			var dd: Vector3 = rb[k]
			var na := _grid_n(grid, j, k, m, rings)
			var nb := _grid_n(grid, j, (k + 1) % m, m, rings)
			var nc := _grid_n(grid, j + 1, (k + 1) % m, m, rings)
			var nd := _grid_n(grid, j + 1, k, m, rings)
			var u0 := float(k) * (w + d) * 2.0 / float(m)
			var u1 := float(k + 1) * (w + d) * 2.0 / float(m)
			var v0 := float(j) * (rise + hd) / float(rings)
			var v1 := float(j + 1) * (rise + hd) / float(rings)
			g.quad_n("temple_tile", a, b, cc, dd, na, nb, nc, nd, Vector2(u0, v0), Vector2(u1, v0), Vector2(u1, v1), Vector2(u0, v1))
			if j == 0:
				# The eave's edge and its underside back to the beam.
				var dn := Vector3.DOWN * 0.3
				g.quad("lacquer", a, b, b + dn, a + dn, (a + b - 2.0 * c).normalized() * Vector3(1, 0, 1), Vector2(u0, a.y), Vector2(u1, b.y), Vector2(u1, b.y - 0.3), Vector2(u0, a.y - 0.3))
				var ia := c + (a - c) * Vector3(0.82, 0.0, 0.82) + Vector3.UP * (a.y - c.y - 0.3)
				var ib := c + (b - c) * Vector3(0.82, 0.0, 0.82) + Vector3.UP * (b.y - c.y - 0.3)
				g.quad("timber", a + dn, b + dn, ib, ia, Vector3.DOWN, Vector2(u0, 0), Vector2(u1, 0), Vector2(u1, 1), Vector2(u0, 1))


static func _grid_n(grid: Array, j: int, k: int, m: int, rings: int) -> Vector3:
	var r: Array = grid[j]
	var tk: Vector3 = (r[(k + 1) % m] as Vector3) - (r[(k - 1 + m) % m] as Vector3)
	var j0 := maxi(j - 1, 0)
	var j1 := mini(j + 1, rings)
	var tj: Vector3 = ((grid[j1] as Array)[k] as Vector3) - ((grid[j0] as Array)[k] as Vector3)
	var n := tk.cross(tj)
	if n.y < 0.0:
		n = -n
	return n.normalized() if n.length() > 1e-6 else Vector3.UP


# --- Synagogue ---------------------------------------------------------------------------------------------

static func _synagogue(ctx: Dictionary) -> void:
	var g: LandmarkGeo = ctx.g
	var p: Dictionary = ctx.p
	var W: float = p.W
	var bd: float = p.BD
	var fz: float = p.fz
	var H: float = p.H
	var tw: float = p.towers
	var th_: float = p.tower_h
	var zf := -fz
	var zb := zf - bd
	var x0 := -W * 0.5
	var plinth := 1.0
	ctx.footprints = [Rect2(x0, zb, W, bd + 1.0)]
	ctx.shapes = [[Vector3(0, H * 0.5, (zf + zb) * 0.5), Vector3(W, H, bd)]]
	g.box("granite", Vector3(0, plinth * 0.5, (zf + zb) * 0.5), Vector3(W + 0.4, plinth, bd + 0.4), Color.WHITE, Basis(), 0.03)
	steps(g, "granite", 0.0, W - tw * 2.0 - 1.0, zf + 0.36 * 6.0 + 0.2, plinth, zf - 0.2)
	# The front between the towers: a deep arched portal, and the round window above it.
	var mid_w := W - tw * 2.0
	var mx0 := x0 + tw
	var portal := 6.4
	wall(g, "stone", Vector3(mx0, plinth, zf), Vector3(1, 0, 0), Vector3(0, 0, 1), mid_w, H - plinth, 1.4,
		[["arch", mid_w * 0.5 - portal * 0.5, mid_w * 0.5 + portal * 0.5, 0.0, 6.8, ""], ["circle", mid_w * 0.5 - 1.8, mid_w * 0.5 + 1.8, 7.6, 11.2, "glass_stained"]],
		true, false, 0.0, 0.7)
	# Inside the portal: the doors (bronze, two leaves) under a glazed lunette.
	var pz := zf - 1.4
	wall(g, "stone", Vector3(mx0 + mid_w * 0.5 - portal * 0.5, plinth, pz), Vector3(1, 0, 0), Vector3(0, 0, 1), portal, 6.8, 0.4,
		[["rect", portal * 0.5 - 1.6, portal * 0.5 + 1.6, 0.0, 3.8, "bronze"], ["arch", portal * 0.5 - 2.4, portal * 0.5 + 2.4, 4.2, 6.6, "glass_stained"]], false, false, 0.0, 0.15)
	g.box("dark", Vector3(0, plinth + 1.9, pz - 0.12), Vector3(0.05, 3.8, 0.05))
	# Archivolts: three stepped rings round the portal.
	for ring in 3:
		var rr := portal * 0.5 + 0.2 + float(ring) * 0.35
		var spring := plinth + 6.8 - portal * 0.5
		for k in 15:
			var t := PI * float(k) / 14.0
			g.box("trim", Vector3(cos(t) * rr, spring + sin(t) * rr, zf + 0.08 - float(ring) * 0.0), Vector3(0.45, 0.3, 0.16 + float(ring) * 0.06), Color.WHITE, Basis(Vector3(0, 0, 1), t + PI * 0.5))
	# The window's tracery: two interlaced triangles of stone bars (the six-pointed star) and a ring.
	var wc := Vector3(0, plinth + 9.4, zf - 0.6)
	for tri_k in 2:
		for e in 3:
			var a0 := PI * 0.5 + TAU * float(e) / 3.0 + PI * float(tri_k)
			var a1 := a0 + TAU / 3.0
			var pa := wc + Vector3(cos(a0), sin(a0), 0) * 1.6
			var pb := wc + Vector3(cos(a1), sin(a1), 0) * 1.6
			var d := pb - pa
			g.box("trim", (pa + pb) * 0.5, Vector3(d.length(), 0.12, 0.14), Color.WHITE, Basis(Vector3(0, 0, 1), atan2(d.y, d.x)))
	for k in 24:
		var t := TAU * float(k) / 24.0
		g.box("trim", wc + Vector3(cos(t) * 1.9, sin(t) * 1.9, 0.62), Vector3(0.52, 0.32, 0.18), Color.WHITE, Basis(Vector3(0, 0, 1), t + PI * 0.5))
	# The name over the portal and a tablet band.
	g.box("trim", Vector3(0, plinth + 7.55, zf + 0.1), Vector3(mid_w - 0.4, 0.5, 0.2))
	ctx.text.append([String(ctx.s.name), Vector3(0, plinth + 7.42, zf + 0.21), 0.34, mid_w - 1.2, Color(0.30, 0.25, 0.18)])
	# Side and back walls: tall round-headed windows in two tiers.
	var bays := maxi(3, int(bd / 4.0))
	var wins: Array = []
	for i in bays:
		var u := bd * (float(i) + 0.5) / float(bays)
		wins.append(["arch", u - 0.8, u + 0.8, 2.0, 5.8, "glass_stained"])
		wins.append(["arch", u - 0.8, u + 0.8, 7.2, 11.2, "glass_stained"])
	wall(g, "stone", Vector3(x0, 0, zf), Vector3(0, 0, -1), Vector3(-1, 0, 0), bd, H, 0.7, wins, true, false, 0.0, 0.35, "trim")
	wall(g, "stone", Vector3(-x0, 0, zb), Vector3(0, 0, 1), Vector3(1, 0, 0), bd, H, 0.7, wins, true, false, 0.0, 0.35, "trim")
	wall(g, "stone", Vector3(-x0, 0, zb), Vector3(-1, 0, 0), Vector3(0, 0, -1), W, H, 0.7, [], true, true)
	g.box("dark", Vector3(0, H - 0.3, (zf + zb) * 0.5), Vector3(W - 1.2, 0.1, bd - 1.2))
	# Cornice and a parapet all round, with a stepped crest over the middle of the front.
	g.box("trim", Vector3(0, H + 0.2, (zf + zb) * 0.5), Vector3(W + 0.6, 0.4, bd + 0.6), Color.WHITE, Basis(), 0.06)
	for e: Array in [[Vector3(0, H + 0.9, zf - 0.2), Vector3(W, 1.0, 0.4)], [Vector3(0, H + 0.9, zb + 0.2), Vector3(W, 1.0, 0.4)],
			[Vector3(x0 + 0.2, H + 0.9, (zf + zb) * 0.5), Vector3(0.4, 1.0, bd)], [Vector3(-x0 - 0.2, H + 0.9, (zf + zb) * 0.5), Vector3(0.4, 1.0, bd)]]:
		g.box("stone", e[0], e[1])
	g.box("stone", Vector3(0, H + 1.9, zf - 0.2), Vector3(mid_w * 0.6, 1.2, 0.5))
	g.box("trim", Vector3(0, H + 2.55, zf - 0.2), Vector3(mid_w * 0.6 + 0.3, 0.12, 0.6))
	# The two towers: square shafts with a pair of arched windows high up, an octagonal drum and
	# a dome of copper gone green, a finial.
	for sx: float in [-1.0, 1.0]:
		var tc := Vector3(sx * (W * 0.5 - tw * 0.5), 0, zf - tw * 0.5 + 0.4)
		ctx.shapes.append([tc + Vector3(0, th_ * 0.5, 0), Vector3(tw, th_, tw)])
		var to := tc + Vector3(-tw * 0.5, 0, tw * 0.5)
		wall(g, "stone", to, Vector3(1, 0, 0), Vector3(0, 0, 1), tw, th_, 0.6,
			[["arch", tw * 0.5 - 0.7, tw * 0.5 + 0.7, 2.2, 5.6, "glass_stained"], ["arch", tw * 0.5 - 1.2, tw * 0.5 - 0.15, th_ - 5.0, th_ - 1.6, "dark"],
			["arch", tw * 0.5 + 0.15, tw * 0.5 + 1.2, th_ - 5.0, th_ - 1.6, "dark"]], false, false, 0.0, 0.35, "trim")
		g.box("stone", tc + Vector3(0, th_ * 0.5, -0.31), Vector3(tw, th_, tw - 0.62))
		g.box("trim", tc + Vector3(0, th_ + 0.2, 0), Vector3(tw + 0.5, 0.4, tw + 0.5), Color.WHITE, Basis(), 0.05)
		var dc := tc + Vector3(0, th_ + 0.4, 0)
		lathe(g, "stone", dc, [Vector2(tw * 0.42, 0.0), Vector2(tw * 0.42, 1.4), Vector2(tw * 0.47, 1.5), Vector2(tw * 0.47, 1.7)], 8)
		lathe(g, "dark", dc + Vector3(0, 1.7, 0), [Vector2(tw * 0.43, 0.0), Vector2(tw * 0.47, 0.6), Vector2(tw * 0.44, 1.4), Vector2(tw * 0.32, 2.3),
			Vector2(tw * 0.14, 2.9), Vector2(0.12, 3.3), Vector2(0.0, 3.4)], 16, Color(0.38, 0.62, 0.52))
		lathe(g, "gold", dc + Vector3(0, 5.05, 0), [Vector2(0.0, 0.0), Vector2(0.14, 0.1), Vector2(0.16, 0.3), Vector2(0.05, 0.5), Vector2(0.0, 0.9)], 10)
		# A lamp on each tower's face by the steps.
		g.box("glow", tc + Vector3(sx * -0.3, 3.2, tw * 0.5 + 0.18), Vector3(0.3, 0.45, 0.3))
	ctx.p.top = th_ + 7.5
	ctx.lights.append([Vector3(0, plinth + 4.5, zf + 1.0), 11.0])
	ctx.pools.append([Vector3(0, 0.1, zf + 2.5), Vector2(mid_w + 2.0, 6.0), 0.9])
	ctx.path_w = 5.0
	ctx.path_x = 0.0
	ctx.paved.append(Rect2(-2.5, zf + 2.4, 5.0, -zf - 2.4))
	ctx.paved.append(Rect2(-mid_w * 0.5 - 1.0, zf, mid_w + 2.0, 2.6))
