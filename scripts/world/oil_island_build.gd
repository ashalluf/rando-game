class_name OilIslandBuild
extends RefCounted
## Builds one decorated oil island (OilIslands) at true world coordinates under `parent`: the
## boulder revetment from the sea bed up to the pad, the concrete pad, the planted berm with its
## palms, the sound wall, the rig towers (a derrick inside four white screens, pastel fins, a
## visor, a curved shell on one corner, the derrick's top standing clear with its red light), the
## equipment sheds and tanks, the waterfall pouring off the shore side in three falls, the lamps.
## One mesh on ONE material (shaders/oil_island.gdshader, the kind in COLOR.a: `code()`); the
## boulders and the palms are batches. The far copy is the same builder with the boulders, shrubs,
## lamps, pipework and small sheds left out and nothing casting a shadow but the mesh; the
## detailed copy adds the collision (one concave shape for the ground you stand on, boxes for the
## towers and the wall) and, on desktop, a few `lamp_light` omnis gelled like the floods.

const K_PAD := 0
const K_ROCK := 1
const K_GREEN := 2
const K_SCREEN := 3
const K_PANEL := 4
const K_STEEL := 5
const K_FALLS := 6
const K_POOL := 7
const K_LAMP := 8
const K_WALL := 9
const K_FOAM := 10
const K_METAL := 11

const KEY := "isl"
const CONCRETE := Color(0.62, 0.6, 0.56)
const STEEL := Color(0.36, 0.33, 0.3)
const STEEL_RED := Color(0.55, 0.16, 0.1)
const LAMP_WARM := Color(1.0, 0.84, 0.62)
const LAMP_RED := Color(1.0, 0.06, 0.04)
const SHED := Color(0.78, 0.74, 0.64)
## Boulders laid on the revetment (detailed only): spacing round the island and down the slope.
const BOULDER_STEP := Vector2(2.7, 2.5)
const BOULDER_VARIANTS := 4
const BOULDER_DRAW := 320.0
## Palms along the berm's crest line, metres apart.
const PALM_STEP := 10.5

static var _material: ShaderMaterial = null
static var _boulders: Array[Mesh] = []
## Triangles of the last island built (for the checks and the cost notes).
static var last_triangles: int = 0


## The vertex code: kind and the night wash in COLOR.a (oil_island.gdshader decodes it).
static func code(kind: int, wash: int = 0) -> float:
	return (float(kind + 16 * wash) + 0.5) / 128.0


static func col(c: Color, kind: int, wash: int = 0) -> Color:
	return Color(c.r, c.g, c.b, code(kind, wash))


static func material() -> ShaderMaterial:
	if _material == null:
		_material = ShaderMaterial.new()
		_material.shader = load("res://shaders/oil_island.gdshader")
		_material.set_shader_parameter("pad_y", OilIslands.PAD_Y)
	return _material


static func build(lm: Dictionary, parent: Node3D, detailed: bool) -> void:
	var i := OilIslands.index_of(lm.id)
	if i < 0 or i >= OilIslands.ISLANDS.size():
		return
	var geo := LandmarkGeo.new()
	geo.use(KEY, material())
	var segs := OilIslands.OUTLINE_SEGS if detailed else OilIslands.OUTLINE_SEGS / 2
	var b := _Island.new(i, geo, detailed)
	b.segs = segs
	b.revetment()
	b.pad()
	b.wall()
	b.falls()
	for t: Dictionary in OilIslands.towers(i):
		b.tower(t)
	b.works()
	if detailed:
		b.lamps()
	last_triangles = geo.triangles
	var node := geo.commit(parent, "OilIsland_%d" % i, true)
	if node:
		node.set_meta("oil_island", i)
	var batch := MultiMeshBatch.new()
	b.palms(batch)
	if detailed:
		b.boulders(batch)
		b.shrubs(batch)
		var body := StaticBody3D.new()
		body.name = "OilIslandBody_%d" % i
		body.collision_layer = 1
		body.collision_mask = 0
		parent.add_child(body)
		geo.commit_collision(body)
		for box: Array in b.boxes:
			LandmarkGeo.shape_box(body, box[0], box[1], box[2])
		if not OS.has_feature("web"):
			b.lights(parent)
	else:
		geo.collision = PackedVector3Array()
		ArenaGrounds._far_shadows(batch)
	batch.build(parent)


## A low-poly boulder (a squashed, dented icosphere), its UV in metres for the stone shader.
static func boulder(variant: int) -> Mesh:
	if _boulders.size() > variant and _boulders[variant] != null:
		return _boulders[variant]
	while _boulders.size() <= variant:
		_boulders.append(null)
	var ico := _icosphere(1)
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var stretch := Vector3(1.0 + 0.25 * _hv(variant, 1), 0.62 + 0.2 * _hv(variant, 2), 0.9 + 0.2 * _hv(variant, 3))
	var pts: PackedVector3Array = ico[0]
	var moved := PackedVector3Array()
	for p in pts:
		var n := 0.82 + 0.3 * _hn(p * 2.3 + Vector3(variant, 0.0, 0.0))
		var q := p * n * stretch
		# A flat face where it was split from the bench: the quarry's cut.
		q.y = maxf(q.y, -0.42)
		moved.append(q * 0.5)
	var idx: PackedInt32Array = ico[1]
	var c := col(Color(0.8, 0.8, 0.8), K_ROCK)
	for k in range(0, idx.size(), 3):
		var a := moved[idx[k]]
		var bb := moved[idx[k + 1]]
		var cc := moved[idx[k + 2]]
		var fn := (bb - a).cross(cc - a).normalized()
		if fn.dot(a + bb + cc) < 0.0:
			var t := bb
			bb = cc
			cc = t
			fn = -fn
		for v: Vector3 in [a, cc, bb]:
			st.set_color(c)
			st.set_normal(((v.normalized() + fn) * 0.5).normalized())
			st.set_uv(Vector2(v.x + v.z, v.y) * 2.0)
			st.add_vertex(v)
	var mesh := st.commit()
	mesh.surface_set_material(0, material())
	_boulders[variant] = mesh
	return mesh


static func _hv(v: int, s: int) -> float:
	return float(hash([v, s, "oil_boulder"]) & 0xffff) / 65535.0


static func _hn(p: Vector3) -> float:
	return sin(p.x * 3.1 + p.y * 1.7) * 0.5 + sin(p.y * 2.3 + p.z * 2.9) * 0.3 + sin(p.z * 1.9 + p.x * 2.2) * 0.2


static func _icosphere(subdiv: int) -> Array:
	var t := (1.0 + sqrt(5.0)) / 2.0
	var verts := PackedVector3Array([Vector3(-1, t, 0), Vector3(1, t, 0), Vector3(-1, -t, 0), Vector3(1, -t, 0),
		Vector3(0, -1, t), Vector3(0, 1, t), Vector3(0, -1, -t), Vector3(0, 1, -t),
		Vector3(t, 0, -1), Vector3(t, 0, 1), Vector3(-t, 0, -1), Vector3(-t, 0, 1)])
	for k in verts.size():
		verts[k] = verts[k].normalized()
	var faces := PackedInt32Array([0, 11, 5, 0, 5, 1, 0, 1, 7, 0, 7, 10, 0, 10, 11, 1, 5, 9, 5, 11, 4, 11, 10, 2, 10, 7, 6, 7, 1, 8,
		3, 9, 4, 3, 4, 2, 3, 2, 6, 3, 6, 8, 3, 8, 9, 4, 9, 5, 2, 4, 11, 6, 2, 10, 8, 6, 7, 9, 8, 1])
	for _s in subdiv:
		var mid := {}
		var out := PackedInt32Array()
		for k in range(0, faces.size(), 3):
			var m := PackedInt32Array()
			for e in 3:
				var a := faces[k + e]
				var b := faces[k + (e + 1) % 3]
				var key := Vector2i(mini(a, b), maxi(a, b))
				if not mid.has(key):
					mid[key] = verts.size()
					verts.append(((verts[a] + verts[b]) * 0.5).normalized())
				m.append(mid[key])
			out.append_array([faces[k], m[0], m[2], faces[k + 1], m[1], m[0], faces[k + 2], m[2], m[1], m[0], m[1], m[2]])
		faces = out
	return [verts, faces]


## One island's build: the frame and the geometry helpers.
class _Island:
	var i: int
	var geo: LandmarkGeo
	var detailed: bool
	var segs: int = 120
	## Collision boxes: [centre, size, basis].
	var boxes: Array = []
	var _yaw: float
	var _falls_t: float

	func _init(island: int, g: LandmarkGeo, near: bool) -> void:
		i = island
		geo = g
		detailed = near
		_yaw = float(OilIslands.ISLANDS[island].yaw)
		_falls_t = OilIslands.falls_angle(island)

	## Local frame point (x along the long axis, z across) at height y, as true world.
	func w(p: Vector2, y: float) -> Vector3:
		var q := OilIslands.to_world(i, p)
		return Vector3(q.x, y, q.y)

	func wdir(d: Vector2) -> Vector3:
		var q := d.rotated(_yaw)
		return Vector3(q.x, 0.0, q.y)

	func basis_local() -> Basis:
		return Basis(Vector3.UP, -_yaw)

	func t_at(k: int) -> float:
		return TAU * float(k) / float(segs)

	## How close angle t is to the falls (0 there, 1 away), for the berm, palms and wall to make
	## room for them.
	func falls_room(t: float, half_width: float) -> float:
		var p := OilIslands.edge_local(i, t)
		var f := OilIslands.edge_local(i, _falls_t)
		return smoothstep(half_width, half_width + 6.0, p.distance_to(f))

	# --- The revetment: from the pad edge down to the sea bed, quarry stone. -------------------

	func revetment() -> void:
		var rings: Array = OilIslands.RINGS
		var c := OilIslandBuild.col(Color(0.8, 0.8, 0.8), K_ROCK)
		var u := 0.0
		var prev: Array = []
		for k in segs + 1:
			var t := t_at(k)
			var row: Array = []
			for r: Array in rings:
				row.append(w(OilIslands.ring_local(i, t, float(r[0])), float(r[1])))
			if k > 0:
				var du: float = (row[0] as Vector3).distance_to(prev[0] as Vector3)
				var slant := 0.0
				for j in rings.size() - 1:
					var a: Vector3 = prev[j]
					var b: Vector3 = row[j]
					var cc: Vector3 = row[j + 1]
					var d: Vector3 = prev[j + 1]
					var s1 := slant + a.distance_to(d)
					var outward := ((a + b) * 0.5 - w(Vector2.ZERO, 0.0))
					outward.y = 0.0
					var want := (cc - b).cross(b - a)
					if want.dot(outward + Vector3.UP * 20.0) < 0.0:
						want = -want
					geo.quad(KEY, a, b, cc, d, want, Vector2(u, slant), Vector2(u + du, slant), Vector2(u + du, s1), Vector2(u, s1), c, detailed)
					slant = s1
				u += du
			prev = row

	# --- The pad: concrete inside the berm, the berm's mound of groundcover, the coping. -------

	func pad() -> void:
		var y0 := OilIslands.PAD_Y
		var grass := OilIslandBuild.col(Color(0.5, 0.5, 0.5), K_GREEN)
		var conc := OilIslandBuild.col(CONCRETE, K_PAD)
		# The inner pad.
		var inner := PackedVector2Array()
		for k in segs:
			var q := OilIslands.to_world(i, OilIslands.ring_local(i, -t_at(k), -OilIslands.BERM_IN))
			inner.append(q)
		geo.cap(KEY, LandmarkGeo.ccw(inner), y0, conc, detailed)
		# Coping walk on the edge and the berm: rings from the edge inward.
		var berm_d: Array = [0.0, -OilIslands.BERM_OUT]
		var n := 7
		for k in n:
			berm_d.append(-lerpf(OilIslands.BERM_OUT, OilIslands.BERM_IN, float(k + 1) / float(n)))
		var prev: Array = []
		for k in segs + 1:
			var t := t_at(k)
			var room := falls_room(t, OilIslands.FALLS_WIDTH * 0.5 + 4.0)
			var row: Array = []
			for d: float in berm_d:
				var h := OilIslands.berm_height(-d) * room
				row.append(w(OilIslands.ring_local(i, t, d), y0 + h))
			if k > 0:
				for j in berm_d.size() - 1:
					var a: Vector3 = prev[j]
					var b: Vector3 = row[j]
					var cc: Vector3 = row[j + 1]
					var d: Vector3 = prev[j + 1]
					var cl := conc if j == 0 else grass
					geo.quad(KEY, a, b, cc, d, Vector3.UP, Vector2(a.x, a.z), Vector2(b.x, b.z), Vector2(cc.x, cc.z), Vector2(d.x, d.z), cl, detailed)
			prev = row

	# --- The sound wall: precast panels stepping in height, a painted band, both faces. --------

	func wall() -> void:
		var y0 := OilIslands.PAD_Y
		var band: Color = OilIslands.PASTELS[int(OilIslands.h01(i, "band") * OilIslands.PASTELS.size()) % OilIslands.PASTELS.size()]
		var wash := int(OilIslands.h01(i, "wallwash") * 8.0) % 8
		var cw := OilIslandBuild.col(band, K_WALL, wash)
		var thick := 0.5
		var n := segs
		var u := 0.0
		for k in n:
			var t0 := t_at(k)
			var t1 := t_at(k + 1)
			var a := OilIslands.ring_local(i, t0, -OilIslands.WALL_IN)
			var b := OilIslands.ring_local(i, t1, -OilIslands.WALL_IN)
			var hsel := OilIslands.h01(i, "wh", floori(k / 3.0))
			var h := y0 + lerpf(OilIslands.WALL_H.x, OilIslands.WALL_H.y, floorf(hsel * 3.0) / 2.0)
			var nrm := (b - a).orthogonal().normalized()
			if nrm.dot((a + b) * 0.5) < 0.0:
				nrm = -nrm
			var ao := a + nrm * thick * 0.5
			var bo := b + nrm * thick * 0.5
			var ai := a - nrm * thick * 0.5
			var bi := b - nrm * thick * 0.5
			var ln := a.distance_to(b)
			var wo := wdir(nrm)
			geo.quad(KEY, w(ao, y0), w(bo, y0), w(bo, h), w(ao, h), wo, Vector2(u, y0), Vector2(u + ln, y0), Vector2(u + ln, h), Vector2(u, h), cw)
			geo.quad(KEY, w(ai, y0), w(bi, y0), w(bi, h), w(ai, h), -wo, Vector2(u, y0), Vector2(u + ln, y0), Vector2(u + ln, h), Vector2(u, h), cw)
			geo.quad(KEY, w(ao, h), w(bo, h), w(bi, h), w(ai, h), Vector3.UP, Vector2(u, 0.0), Vector2(u + ln, 0.0), Vector2(u + ln, thick), Vector2(u, thick), cw)
			# The ends of a step show where the next panel is lower.
			var hn := y0 + lerpf(OilIslands.WALL_H.x, OilIslands.WALL_H.y, floorf(OilIslands.h01(i, "wh", floori((k + 1) / 3.0)) * 3.0) / 2.0)
			if hn < h:
				var tg := wdir((b - a).normalized())
				geo.quad(KEY, w(bo, hn), w(bi, hn), w(bi, h), w(bo, h), tg, Vector2(0.0, hn), Vector2(thick, hn), Vector2(thick, h), Vector2(0.0, h), cw)
			var hp := y0 + lerpf(OilIslands.WALL_H.x, OilIslands.WALL_H.y, floorf(OilIslands.h01(i, "wh", floori(((k - 1 + n) % n) / 3.0)) * 3.0) / 2.0)
			if hp < h:
				var tg2 := wdir((a - b).normalized())
				geo.quad(KEY, w(ao, hp), w(ai, hp), w(ai, h), w(ao, h), tg2, Vector2(0.0, hp), Vector2(thick, hp), Vector2(thick, h), Vector2(0.0, h), cw)
			u += ln
			if detailed:
				var mid := (a + b) * 0.5
				boxes.append([w(mid, (y0 + h) * 0.5), Vector3(ln, h - y0, thick), Basis(Vector3.UP, -atan2((b - a).y, (b - a).x) - _yaw)])

	# --- The waterfall: a rock cliff at the shore side, two falls and a pool, a cascade down the
	# revetment into the sea. ---------------------------------------------------------------

	func falls() -> void:
		var t := _falls_t
		var e := OilIslands.edge_local(i, t)
		var nrm := OilIslands.edge_normal(i, t)
		var tg := Vector2(-nrm.y, nrm.x)
		var y0 := OilIslands.PAD_Y
		var top := OilIslands.FALLS_TOP
		var mid := y0 + (top - y0) * 0.45
		var hw := OilIslands.FALLS_WIDTH * 0.5
		var rock := OilIslandBuild.col(Color(0.85, 0.85, 0.85), K_ROCK)
		var water := OilIslandBuild.col(Color.WHITE, K_FALLS)
		var pool := OilIslandBuild.col(Color.WHITE, K_POOL)
		var foam := OilIslandBuild.col(Color.WHITE, K_FOAM)
		# The cliff: an upper tier (from 15 m in to 8 m in) and a lower one (8 m to 3 m in), each a
		# block of stone wider than the water, so the water runs between shoulders.
		_rock_block(e, nrm, tg, -15.0, -8.0, hw + 6.0, top, rock)
		_rock_block(e, nrm, tg, -8.0, -3.0, hw + 4.5, mid, rock)
		_rock_block(e, nrm, tg, -3.0, 0.6, hw + 3.0, y0 + 0.3, rock)
		# The upper fall: a sheet on the upper tier's face, a little proud of it.
		var sw := hw - 1.5
		_sheet(e + nrm * -7.85, tg, sw, top - 0.15, mid, nrm, water)
		# The pool on the lower tier, and its lip.
		var p0 := e + nrm * -7.9
		var p1 := e + nrm * -3.1
		geo.quad(KEY, w(p0 - tg * sw, mid + 0.06), w(p0 + tg * sw, mid + 0.06), w(p1 + tg * sw, mid + 0.06), w(p1 - tg * sw, mid + 0.06), Vector3.UP,
			Vector2(-sw, 0.0), Vector2(sw, 0.0), Vector2(sw, 4.8), Vector2(-sw, 4.8), pool)
		# The lower fall, down the lower tier's face to the pad edge's rock.
		_sheet(e + nrm * -2.85, tg, sw * 0.85, mid - 0.05, y0 + 0.35, nrm, water)
		# The cascade down the revetment, following its rings, a few cm proud.
		var rings: Array = OilIslands.RINGS
		var vdown := 0.0
		var cw := sw * 0.8
		for j in rings.size() - 2:
			var d0 := float(rings[j][0]) + 0.6
			var d1 := float(rings[j + 1][0])
			var y_a := float(rings[j][1]) + 0.35
			var y_b := float(rings[j + 1][1]) + 0.25
			if j == rings.size() - 3:
				y_b = 0.25
			var a := e + nrm * d0
			var b := e + nrm * d1
			var slope := Vector3(0.0, y_b - y_a, 0.0) + wdir(nrm) * (d1 - d0)
			var want := slope.cross(wdir(tg))
			if want.y < 0.0:
				want = -want
			var ln := slope.length()
			geo.quad(KEY, w(a - tg * cw, y_a), w(a + tg * cw, y_a), w(b + tg * cw * 1.25, y_b), w(b - tg * cw * 1.25, y_b), want,
				Vector2(-cw, vdown), Vector2(cw, vdown), Vector2(cw, vdown + ln), Vector2(-cw, vdown + ln), water)
			vdown += ln
			cw *= 1.25
			if y_b <= 0.3:
				break
		# Foam where it meets the sea.
		var fd := float(rings[2][0]) - 1.0
		var fa := e + nrm * fd
		var fb := e + nrm * (fd + 9.0)
		var fwid := cw + 4.0
		geo.quad(KEY, w(fa - tg * fwid, 0.2), w(fa + tg * fwid, 0.2), w(fb + tg * (fwid + 3.0), 0.18), w(fb - tg * (fwid + 3.0), 0.18), Vector3.UP,
			Vector2(-fwid, 0.0), Vector2(fwid, 0.0), Vector2(fwid + 3.0, 9.0), Vector2(-fwid - 3.0, 9.0), foam)
		if detailed:
			var c := (e + nrm * -8.0)
			boxes.append([w(c, (y0 + top) * 0.5), Vector3(14.0, top - y0, hw * 2.0 + 10.0), Basis(Vector3.UP, -atan2(nrm.y, nrm.x) - _yaw)])

	## A block of stone from `d0` to `d1` metres along the outward normal, `half` wide, its top
	## at `top`, standing on the pad (its sides and top in the rock kind, with a ragged top edge).
	func _rock_block(e: Vector2, nrm: Vector2, tg: Vector2, d0: float, d1: float, half: float, top: float, c: Color) -> void:
		var y0 := OilIslands.PAD_Y - 0.5
		var pts: Array[Vector2] = [e + nrm * d0 - tg * half, e + nrm * d0 + tg * half, e + nrm * d1 + tg * (half - 1.2), e + nrm * d1 - tg * (half - 1.2)]
		var tops: Array[float] = []
		for k in 4:
			tops.append(top + (OilIslands.h01(i, "rb%d" % int(d0), k) - 0.5) * 1.2)
		for k in 4:
			var a: Vector2 = pts[k]
			var b: Vector2 = pts[(k + 1) % 4]
			var out2 := ((a + b) * 0.5 - (e + nrm * (d0 + d1) * 0.5)).normalized()
			var ln := a.distance_to(b)
			geo.quad(KEY, w(a, y0), w(b, y0), w(b, tops[(k + 1) % 4]), w(a, tops[k]), wdir(out2),
				Vector2(0.0, y0), Vector2(ln, y0), Vector2(ln, top), Vector2(0.0, top), c, detailed)
		var cen: Vector2 = (pts[0] + pts[1] + pts[2] + pts[3]) * 0.25
		var cy := top + 0.6
		for k in 4:
			var a: Vector2 = pts[k]
			var b: Vector2 = pts[(k + 1) % 4]
			geo.tri(KEY, w(a, tops[k]), w(b, tops[(k + 1) % 4]), w(cen, cy), Vector3.UP, a * 1.0, b * 1.0, cen * 1.0, c, detailed)

	## A vertical sheet of falling water centred at `at`, `half` wide, from y_top down to y_bot,
	## facing `nrm` (local), with v the metres fallen.
	func _sheet(at: Vector2, tg: Vector2, half: float, y_top: float, y_bot: float, nrm: Vector2, c: Color) -> void:
		var h := y_top - y_bot
		geo.quad(KEY, w(at - tg * half, y_top), w(at + tg * half, y_top), w(at + tg * half + nrm * 0.6, y_bot), w(at - tg * half + nrm * 0.6, y_bot), wdir(nrm),
			Vector2(-half, 0.0), Vector2(half, 0.0), Vector2(half, h), Vector2(-half, h), c)

	# --- A rig tower. --------------------------------------------------------------------------

	func tower(t: Dictionary) -> void:
		var c: Vector2 = t.at
		var hgt: float = t.h
		var y0 := OilIslands.PAD_Y
		var th := OilIslands.TOWER_HALF
		var wash: int = t.wash
		var wash2: int = t.wash2
		var paint: Color = OilIslands.PASTELS[t.paint]
		var paint2: Color = OilIslands.PASTELS[(int(t.paint) + 2) % OilIslands.PASTELS.size()]
		var k: int = t.seed
		var b := basis_local()
		# The derrick's enclosure, corrugated, inside the screens.
		geo.box(KEY, w(c, y0 + hgt * 0.42), Vector3(th * 2.0, hgt * 0.84, th * 2.0), OilIslandBuild.col(SHED, K_METAL), b)
		# Four screens, one a face, standing 1.3 m off it, each to its own height with a slanted top.
		var top_max := y0
		var dirs := [Vector2(1, 0), Vector2(0, 1), Vector2(-1, 0), Vector2(0, -1)]
		for f in 4:
			var n: Vector2 = dirs[f]
			var tg := Vector2(-n.y, n.x)
			var off := th + 1.3
			var half := th + 1.6
			var ha := y0 + hgt * lerpf(0.6, 0.88, OilIslands.h01(i, "sa%d" % k, f))
			var hb := y0 + hgt * lerpf(0.6, 0.88, OilIslands.h01(i, "sb%d" % k, f))
			top_max = maxf(top_max, maxf(ha, hb))
			var fw := wash if f % 2 == 0 else wash2
			_slab(c + n * off - tg * half, c + n * off + tg * half, y0, ha, hb, 0.7, n, OilIslandBuild.col(Color.WHITE, K_SCREEN, fw))
			# A pastel fin standing out of the screen, and a visor across it near the top.
			var fy := y0 + hgt * lerpf(0.18, 0.4, OilIslands.h01(i, "fy%d" % k, f))
			var fl := hgt * lerpf(0.22, 0.42, OilIslands.h01(i, "fl%d" % k, f))
			var fx := (OilIslands.h01(i, "fx%d" % k, f) - 0.5) * half
			var finc := paint if f % 2 == 0 else paint2
			var fc := c + n * (off + 1.6) + tg * fx
			geo.box(KEY, w(fc, fy + fl * 0.5), Vector3(0.6, fl, 3.2) if f % 2 == 0 else Vector3(3.2, fl, 0.6), OilIslandBuild.col(finc, K_PANEL, fw), b)
			var vy := minf(ha, hb) - 3.5
			var vc := c + n * (off + 0.9)
			var vsize := Vector3(1.6, 1.3, half * 2.0 + 1.6) if f % 2 == 0 else Vector3(half * 2.0 + 1.6, 1.3, 1.6)
			geo.box(KEY, w(vc, vy), vsize, OilIslandBuild.col(paint2 if f % 2 == 0 else paint, K_PANEL, fw), b)
		# The curved shell round one corner: a quarter cylinder, both faces.
		var corner: Vector2 = [Vector2(1, 1), Vector2(-1, 1), Vector2(-1, -1), Vector2(1, -1)][int(t.shell)]
		var cc := c + corner * (th + 1.3)
		var a0 := atan2(corner.y, corner.x) - PI * 0.42
		var a1 := atan2(corner.y, corner.x) + PI * 0.42
		var sy0 := y0 + 6.0
		var sy1 := y0 + hgt * lerpf(0.45, 0.7, OilIslands.h01(i, "sh", k))
		var sc := OilIslandBuild.col(paint, K_PANEL, wash)
		_shell(cc, 5.2, a0, a1, sy0, sy1, sc)
		# The derrick's top standing clear of the screens: four legs leaning in, girts, the crown.
		var leg0 := top_max - 2.0
		var leg1 := y0 + hgt
		var steel := OilIslandBuild.col(STEEL_RED if OilIslands.h01(i, "red", k) < 0.5 else STEEL, K_STEEL)
		var spread0 := th * 0.75
		var spread1 := 1.3
		for q in 4:
			var cq: Vector2 = [Vector2(1, 1), Vector2(-1, 1), Vector2(-1, -1), Vector2(1, -1)][q]
			_strut(c + cq * spread0, leg0, c + cq * spread1, leg1, 0.32, steel)
		var girts := 3 if detailed else 1
		for g in girts:
			var f := (float(g) + 1.0) / float(girts + 1)
			var gy := lerpf(leg0, leg1, f)
			var s := lerpf(spread0, spread1, f)
			for q in 4:
				var p0: Vector2 = [Vector2(1, 1), Vector2(-1, 1), Vector2(-1, -1), Vector2(1, -1)][q] * s
				var p1: Vector2 = [Vector2(1, 1), Vector2(-1, 1), Vector2(-1, -1), Vector2(1, -1)][(q + 1) % 4] * s
				_strut(c + p0, gy, c + p1, gy, 0.22, steel)
		geo.box(KEY, w(c, leg1 + 0.8), Vector3(3.2, 1.6, 3.2), steel, b)
		geo.box(KEY, w(c, leg1 + 2.1), Vector3(0.9, 0.9, 0.9), OilIslandBuild.col(LAMP_RED, K_LAMP), b)
		if detailed:
			boxes.append([w(c, y0 + hgt * 0.42), Vector3((th + 2.0) * 2.0, hgt * 0.84, (th + 2.0) * 2.0), b])

	## A thin slab between two local points from y0 to tops ya (at a) and yb (at b), `thick`
	## through toward -n (it stands on the n side), every face drawn.
	func _slab(a: Vector2, b: Vector2, y0: float, ya: float, yb: float, thick: float, n: Vector2, c: Color) -> void:
		var ai := a - n * thick
		var bi := b - n * thick
		var ln := a.distance_to(b)
		var wn := wdir(n)
		geo.quad(KEY, w(a, y0), w(b, y0), w(b, yb), w(a, ya), wn, Vector2(0.0, y0), Vector2(ln, y0), Vector2(ln, yb), Vector2(0.0, ya), c)
		geo.quad(KEY, w(ai, y0), w(bi, y0), w(bi, yb), w(ai, ya), -wn, Vector2(ln, y0), Vector2(0.0, y0), Vector2(0.0, yb), Vector2(ln, ya), c)
		geo.quad(KEY, w(a, ya), w(b, yb), w(bi, yb), w(ai, ya), Vector3.UP, Vector2(0.0, 0.0), Vector2(ln, 0.0), Vector2(ln, thick), Vector2(0.0, thick), c)
		var te := wdir((b - a).normalized())
		geo.quad(KEY, w(b, y0), w(bi, y0), w(bi, yb), w(b, yb), te, Vector2(0.0, y0), Vector2(thick, y0), Vector2(thick, yb), Vector2(0.0, yb), c)
		geo.quad(KEY, w(a, y0), w(ai, y0), w(ai, ya), w(a, ya), -te, Vector2(0.0, y0), Vector2(thick, y0), Vector2(thick, ya), Vector2(0.0, ya), c)

	## A curved shell (local centre, radius, angles in the island frame), both faces.
	func _shell(cen: Vector2, r: float, a0: float, a1: float, y0: float, y1: float, c: Color) -> void:
		var n := 10 if detailed else 6
		var u := 0.0
		for k in n:
			var t0 := lerpf(a0, a1, float(k) / float(n))
			var t1 := lerpf(a0, a1, float(k + 1) / float(n))
			var d0 := Vector2(cos(t0), sin(t0))
			var d1 := Vector2(cos(t1), sin(t1))
			var p0 := cen + d0 * r
			var p1 := cen + d1 * r
			var q0 := cen + d0 * (r - 0.4)
			var q1 := cen + d1 * (r - 0.4)
			# The shell's top sweeps up toward one end, like a sail.
			var h0 := lerpf(y1 - 6.0, y1, float(k) / float(n))
			var h1 := lerpf(y1 - 6.0, y1, float(k + 1) / float(n))
			var ln := p0.distance_to(p1)
			geo.quad_n(KEY, w(p0, y0), w(p1, y0), w(p1, h1), w(p0, h0), wdir(d0), wdir(d1), wdir(d1), wdir(d0),
				Vector2(u, y0), Vector2(u + ln, y0), Vector2(u + ln, h1), Vector2(u, h0), c)
			geo.quad_n(KEY, w(q0, y0), w(q0, h0), w(q1, h1), w(q1, y0), -wdir(d0), -wdir(d0), -wdir(d1), -wdir(d1),
				Vector2(u, y0), Vector2(u, h0), Vector2(u + ln, h1), Vector2(u + ln, y0), c)
			geo.quad(KEY, w(p0, h0), w(p1, h1), w(q1, h1), w(q0, h0), Vector3.UP, Vector2(u, 0.0), Vector2(u + ln, 0.0), Vector2(u + ln, 0.4), Vector2(u, 0.4), c)
			u += ln

	## A square strut (a steel member) from local a at ya to local b at yb.
	func _strut(a: Vector2, ya: float, b: Vector2, yb: float, size: float, c: Color) -> void:
		var pa := w(a, ya)
		var pb := w(b, yb)
		var axis := pb - pa
		var ln := axis.length()
		if ln < 0.01:
			return
		var y := axis / ln
		var x := y.cross(Vector3.UP if absf(y.y) < 0.9 else Vector3.RIGHT).normalized()
		var z := x.cross(y).normalized()
		geo.box(KEY, (pa + pb) * 0.5, Vector3(size, ln, size), c, Basis(x, y, z))

	# --- The works inside the wall: sheds, tanks, a pipe rack. -----------------------------------

	func works() -> void:
		var y0 := OilIslands.PAD_Y
		var half: Vector2 = OilIslands.ISLANDS[i].half
		var b := basis_local()
		var span := half.x - 45.0
		var side := half.y - OilIslands.WALL_IN - 9.0
		# The well bay down the middle: darker concrete, the two rails the rigs walk along.
		var bay_len := (half.x - OilIslands.WALL_IN - 20.0) * 2.0
		geo.box(KEY, w(Vector2.ZERO, y0 + 0.04), Vector3(bay_len, 0.08, 14.0), OilIslandBuild.col(Color(0.4, 0.39, 0.37), K_PAD), b)
		for r in [-4.2, 4.2]:
			geo.box(KEY, w(Vector2(0.0, r), y0 + 0.16), Vector3(bay_len, 0.16, 0.3), OilIslandBuild.col(Color(0.35, 0.3, 0.27), K_STEEL), b)
		# Sheds along both long sides inside the wall: pump houses, switchgear, stores.
		var per := 4 if detailed else 3
		for sd in 2:
			for k in per:
				var id := sd * 8 + k
				var room := span * 2.0 / float(per)
				var x := -span + room * (float(k) + 0.5) + (OilIslands.h01(i, "shx", id) - 0.5) * room * 0.2
				var z := side * (1.0 if sd == 0 else -1.0)
				var size := Vector3(room * lerpf(0.55, 0.8, OilIslands.h01(i, "shw", id)), lerpf(4.5, 8.5, OilIslands.h01(i, "shh", id)), lerpf(7.0, 10.0, OilIslands.h01(i, "shd", id)))
				var tone: Color = SHED.lerp(OilIslands.PASTELS[id % OilIslands.PASTELS.size()], 0.35)
				geo.box(KEY, w(Vector2(x, z), y0 + size.y * 0.5), size, OilIslandBuild.col(tone, K_METAL), b)
				geo.box(KEY, w(Vector2(x, z), y0 + size.y + 0.15), Vector3(size.x + 0.4, 0.3, size.z + 0.4), OilIslandBuild.col(Color(0.5, 0.5, 0.48), K_PAD), b)
				if detailed:
					# A roll-up door and a light over it on the side facing the well bay.
					var face := z - signf(z) * (size.z * 0.5 + 0.02)
					geo.box(KEY, w(Vector2(x, face), y0 + 2.0), Vector3(3.6, 4.0, 0.08), OilIslandBuild.col(Color(0.62, 0.62, 0.6), K_METAL), b)
					geo.box(KEY, w(Vector2(x + 2.6, face - signf(z) * 0.15), y0 + 4.5), Vector3(0.5, 0.25, 0.3), OilIslandBuild.col(LAMP_WARM, K_LAMP), b)
					boxes.append([w(Vector2(x, z), y0 + size.y * 0.5), size, b])
		# Two tanks at the long ends, a light mast beside each, and a pipe rack along the bay.
		for k in 2:
			var sx := 1.0 if k == 0 else -1.0
			var x := (half.x - OilIslands.WALL_IN - 12.0) * sx
			var r := lerpf(4.0, 6.0, OilIslands.h01(i, "tk", k))
			geo.cylinder(KEY, w(Vector2(x, 0.0), y0), r, lerpf(7.0, 10.0, OilIslands.h01(i, "tkh", k)), 16 if detailed else 10, OilIslandBuild.col(Color(0.86, 0.85, 0.8), K_METAL))
			for zs in [-1.0, 1.0]:
				var m := Vector2(x - sx * 4.0, zs * 15.0)
				_strut(m, y0, m, y0 + 22.0, 0.5, OilIslandBuild.col(Color(0.55, 0.55, 0.53), K_STEEL))
				geo.box(KEY, w(m, y0 + 22.4), Vector3(2.4, 0.5, 1.0), OilIslandBuild.col(LAMP_WARM, K_LAMP), b)
		if detailed:
			var ln := bay_len - 16.0
			var rz := -side * 0.6
			for k in 3:
				_strut(Vector2(-ln * 0.5, rz + float(k) * 0.7), y0 + 3.4, Vector2(ln * 0.5, rz + float(k) * 0.7), y0 + 3.4, 0.4, OilIslandBuild.col(Color(0.42, 0.4, 0.36), K_STEEL))
			var bents := int(ln / 8.0)
			for k in bents + 1:
				var x := -ln * 0.5 + ln * float(k) / float(bents)
				_strut(Vector2(x, rz - 0.4), y0, Vector2(x, rz - 0.4), y0 + 3.7, 0.25, OilIslandBuild.col(STEEL, K_STEEL))
				_strut(Vector2(x, rz + 1.8), y0, Vector2(x, rz + 1.8), y0 + 3.7, 0.25, OilIslandBuild.col(STEEL, K_STEEL))

	# --- The lamps on the coping: a post every 16 m with a warm head. ----------------------------

	func lamps() -> void:
		var y0 := OilIslands.PAD_Y
		var n := int(_perimeter() / 16.0)
		for k in n:
			var t := TAU * (float(k) + 0.5) / float(n)
			if falls_room(t, OilIslands.FALLS_WIDTH * 0.5 + 3.0) < 0.5:
				continue
			var p := OilIslands.ring_local(i, t, -0.9)
			_strut(p, y0, p, y0 + 4.2, 0.14, OilIslandBuild.col(Color(0.2, 0.2, 0.2), K_STEEL))
			geo.box(KEY, w(p, y0 + 4.35), Vector3(0.45, 0.3, 0.45), OilIslandBuild.col(LAMP_WARM, K_LAMP), basis_local())

	func _perimeter() -> float:
		var s := 0.0
		var prev := OilIslands.edge_local(i, 0.0)
		for k in 64:
			var p := OilIslands.edge_local(i, TAU * float(k + 1) / 64.0)
			s += p.distance_to(prev)
			prev = p
		return s

	# --- Planting and stone. -------------------------------------------------------------------

	func palms(batch: MultiMeshBatch) -> void:
		var y0 := OilIslands.PAD_Y
		var d := -lerpf(OilIslands.BERM_OUT, OilIslands.BERM_IN, 0.5)
		var n := int(_perimeter() / PALM_STEP)
		for k in n:
			var t := TAU * (float(k) + OilIslands.h01(i, "pj", k) * 0.6) / float(n)
			if falls_room(t, OilIslands.FALLS_WIDTH * 0.5 + 2.0) < 0.5:
				continue
			var p := OilIslands.ring_local(i, t, d + (OilIslands.h01(i, "pd", k) - 0.5) * 5.0)
			var variant := int(OilIslands.h01(i, "pv", k) * float(PropFactory.PALM_VARIANTS)) % PropFactory.PALM_VARIANTS
			var s := lerpf(0.9, 1.45, OilIslands.h01(i, "ps", k))
			var yaw := OilIslands.h01(i, "py", k) * TAU
			var h := OilIslands.berm_height(-(d + (OilIslands.h01(i, "pd", k) - 0.5) * 5.0)) * 0.85
			batch.add("palm_%d" % variant, PropFactory.palm(variant), Transform3D(Basis(Vector3.UP, yaw).scaled(Vector3(s, s, s)), w(p, y0 + h)))
		# A pair of tall palms either side of the falls.
		var e := OilIslands.edge_local(i, _falls_t)
		var nrm := OilIslands.edge_normal(i, _falls_t)
		var tg := Vector2(-nrm.y, nrm.x)
		for sgn: float in [-1.0, 1.0]:
			var p: Vector2 = e + nrm * -10.0 + tg * sgn * (OilIslands.FALLS_WIDTH * 0.5 + 8.0)
			batch.add("palm_0", PropFactory.palm(0), Transform3D(Basis(Vector3.UP, sgn).scaled(Vector3(1.6, 1.6, 1.6)), w(p, y0 + 0.5)))

	func shrubs(batch: MultiMeshBatch) -> void:
		var y0 := OilIslands.PAD_Y
		var n := int(_perimeter() / 5.0)
		for k in n:
			var t := TAU * float(k) / float(n)
			if falls_room(t, OilIslands.FALLS_WIDTH * 0.5 + 2.0) < 0.5:
				continue
			for row in 2:
				var d := -lerpf(OilIslands.BERM_OUT + 2.5, OilIslands.BERM_IN - 2.5, float(row))
				var p := OilIslands.ring_local(i, t + (OilIslands.h01(i, "bj%d" % row, k) - 0.5) * 0.02, d)
				var h := OilIslands.berm_height(-d)
				var v := int(OilIslands.h01(i, "bv", k) * 3.0) % 3
				var s := lerpf(0.8, 1.4, OilIslands.h01(i, "bs%d" % row, k))
				batch.add("oil_bush_%d" % v, PropFactory.model_bush(v), Transform3D(Basis(Vector3.UP, OilIslands.h01(i, "by", k) * TAU).scaled(Vector3(s, s, s)), w(p, y0 + h - 0.1)))

	func boulders(batch: MultiMeshBatch) -> void:
		var rings: Array = OilIslands.RINGS
		var per := _perimeter()
		var cols := int(per / BOULDER_STEP.x)
		# Down the slope from the crest to just under the water: rings 1..2.
		var d_top := float(rings[1][0]) - 0.6
		var d_bot := float(rings[2][0]) + 1.5
		var rows := int((d_bot - d_top) / BOULDER_STEP.y) + 1
		for k in cols:
			for r in rows:
				var id := k * 31 + r
				var t := TAU * (float(k) + (OilIslands.h01(i, "bx", id) - 0.5) * 0.8 + float(r % 2) * 0.5) / float(cols)
				if falls_room(t, OilIslands.FALLS_WIDTH * 0.3) < 0.5:
					continue
				var d := lerpf(d_top, d_bot, (float(r) + OilIslands.h01(i, "bd", id) * 0.7) / float(rows))
				var y := _ring_y(d)
				var p := OilIslands.ring_local(i, t, d)
				var s := lerpf(1.6, 2.9, OilIslands.h01(i, "bsz", id))
				var nrm := OilIslands.edge_normal(i, t)
				var tilt := Basis(wdir(Vector2(-nrm.y, nrm.x)).normalized(), 0.45)
				var basis := tilt * Basis(Vector3.UP, OilIslands.h01(i, "bry", id) * TAU)
				basis = basis.scaled(Vector3(s, s * lerpf(0.7, 1.0, OilIslands.h01(i, "bsy", id)), s))
				var v := int(OilIslands.h01(i, "bvar", id) * BOULDER_VARIANTS) % BOULDER_VARIANTS
				batch.add("oil_boulder_%d" % v, OilIslandBuild.boulder(v), Transform3D(basis, w(p, y - 0.25 * s)),
					Color(lerpf(0.85, 1.1, OilIslands.h01(i, "bt", id)), lerpf(0.85, 1.05, OilIslands.h01(i, "bt2", id)), lerpf(0.85, 1.0, OilIslands.h01(i, "bt3", id)), 1.0))
		for v in BOULDER_VARIANTS:
			batch.set_shadow_reach("oil_boulder_%d" % v, 70.0)
			batch.set_draw_distance("oil_boulder_%d" % v, BOULDER_DRAW)

	func _ring_y(d: float) -> float:
		var rings: Array = OilIslands.RINGS
		for k in rings.size() - 1:
			if d <= float(rings[k + 1][0]):
				return lerpf(float(rings[k][1]), float(rings[k + 1][1]), (d - float(rings[k][0])) / (float(rings[k + 1][0]) - float(rings[k][0])))
		return float(rings[rings.size() - 1][1])

	# --- Real lights (desktop, detailed): a gelled flood at each tower's foot and the falls. ---

	func lights(parent: Node3D) -> void:
		var y0 := OilIslands.PAD_Y
		for t: Dictionary in OilIslands.towers(i):
			var l := OmniLight3D.new()
			l.position = w((t.at as Vector2) + Vector2(OilIslands.TOWER_HALF + 5.0, 0.0), y0 + 3.0) - Vector3.ZERO
			l.omni_range = 26.0
			l.omni_attenuation = 1.1
			l.light_color = OilIslands.WASHES[t.wash]
			l.light_energy = 0.0
			l.shadow_enabled = false
			l.distance_fade_enabled = true
			l.distance_fade_begin = 160.0
			l.distance_fade_length = 40.0
			l.add_to_group("lamp_light")
			parent.add_child(l)
		var e := OilIslands.edge_local(i, _falls_t)
		var nrm := OilIslands.edge_normal(i, _falls_t)
		var lf := OmniLight3D.new()
		lf.position = w(e + nrm * 3.0, y0 + 2.0)
		lf.omni_range = 22.0
		lf.light_color = Color(0.6, 0.85, 1.0)
		lf.light_energy = 0.0
		lf.distance_fade_enabled = true
		lf.distance_fade_begin = 160.0
		lf.distance_fade_length = 40.0
		lf.add_to_group("lamp_light")
		parent.add_child(lf)
