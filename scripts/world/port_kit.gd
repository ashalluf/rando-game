class_name PortKit
extends RefCounted
## The container terminal's kit, built in code (no model files): ISO shipping containers, a
## ship-to-shore gantry crane and a rubber-tyred yard gantry. CityChunk._build_port() lays them
## out; the far city (Skyline) keeps drawing a container as one box.
##
## * Containers are ONE mesh with a hand-built LOD ladder in one vertex buffer (like the palms,
##   PropFactory.PALM_LEVELS): the full box with corner castings, rails, posts, recessed panels,
##   doors with locking bars, keepers, handles and hinges (~700 triangles), a frame-and-panels
##   level (~150), and a plain box (12). The corrugation, liveries, lettering and weathering are
##   drawn by shaders/container.gdshader, so they cost no triangles. Every container of a chunk
##   is one MultiMesh draw; its shadow comes from a box twin (PropFactory.shadow_proxy()).
## * One mesh serves 20 ft and 40 ft, standard and high-cube boxes: the instance transform
##   scales the box, and the vertex shader moves every vertex near an end back to its distance
##   from that end, so castings, doors and rails keep their real size. So a 20 ft container is
##   the 40 ft transform scaled by L20 / L40 in x, a high-cube by H_HC / H_STD in y, and the far
##   city, the MultiMesh bounds and the collision all see the true size with no extra code.
## * The cranes are one merged mesh each (per boom state), on shaders/port_steel.gdshader, with a
##   three-level LOD ladder; their colours are vertex colours and UV2.x picks a finish (paint,
##   hazard stripes, grating, glass, rubber, lamps, cladding, ribbed girders).

# --- ISO 668 dimensions (metres) --------------------------------------------------------------
const L40 := 12.192
const L20 := 6.058
const H_STD := 2.591
const H_HC := 2.896
const W := 2.438
## The gap between two 20 ft boxes sharing a 40 ft slot (ISO 668's 76 mm).
const PAIR_GAP := 0.076

# Container part ids, carried in UV2.x (read by shaders/container.gdshader).
const P_SIDE := 0.0
const P_ROOF := 1.0
const P_FRONT := 2.0
const P_DOOR := 3.0
const P_FRAME := 4.0
const P_CAST := 5.0
const P_HARD := 6.0
const P_RUBBER := 7.0
const P_UNDER := 8.0

## Each container level's largest departure from the full box, in metres (the LOD "edge" the
## renderer weighs against a pixel, as for the palms): dropping the door hardware and castings
## moves the surface ~6 cm, the plain box ~10 cm (the doors' recess and the bars).
const CONTAINER_EDGES := [0.0, 0.06, 0.1]

## Container liveries: paint (sRGB) per livery index. The shader holds the rest of each livery
## (ink colour, name, owner code, mark) under the same index - change one, change both. All
## names and marks are invented; none is a real shipping line.
const LIVERY_PAINT := [
	Color(0.10, 0.24, 0.47), # 0 RANDO, deep blue
	Color(0.46, 0.13, 0.10), # 1 KAVELL, oxide red
	Color(0.12, 0.33, 0.22), # 2 TORVAN, bottle green
	Color(0.85, 0.43, 0.12), # 3 ZEPRA, orange
	Color(0.70, 0.71, 0.70), # 4 OLVANA, light grey
	Color(0.42, 0.16, 0.32), # 5 MERIDU, plum
	Color(0.80, 0.77, 0.70), # 6 a leasing pool's beige box
	Color(0.45, 0.52, 0.58), # 7 a leasing pool's grey-blue box
	Color(0.40, 0.25, 0.16), # 8 an old brown box, no livery left
]
## The old port rolled one of six flat colours per box (CityChunk._build_port still makes that
## roll, so the block's stacks stay where they were); this maps each onto the livery of its hue.
const COLOR_TO_LIVERY := [1, 0, 3, 2, 4, 5]
const LIVERY_COUNT := 9

# --- Ship-to-shore gantry crane (crane frame: origin at rail level, centred between the four
# legs, +Z out over the water) -----------------------------------------------------------------
## Rail gauge (the real 100 ft) and the legs' spacing along the quay.
const STS_GAUGE := 30.48
const STS_LEG_X := 9.2
## Underside of the girders (the portal beams' top), and the girders' depth.
const STS_PORTAL_Y := 44.0
const STS_GIRDER_D := 3.6
const STS_GIRDER_X := 3.9
## Boom reach past the waterside rail and the back-reach behind the landside rail.
const STS_OUTREACH := 60.0
const STS_BACKREACH := 24.0
## Apex of the A-frame (y) and how far the raised boom stands up from level (degrees).
const STS_APEX_Y := 80.0
const STS_APEX_Z := 7.0
const STS_RAISED_DEG := 78.0
## Waterside rail's distance in from the quay edge.
const STS_QUAY_SETBACK := 3.0
const STS_EDGES := [0.0, 0.45, 1.6]
## Crane poses as (trolley z, spreader underside y), crane frame. Parked: the trolley over the
## back-reach, the spreader drawn up. Working: out over the moored ship, whose centre line lies
## ~40 m out from the crane's centre (the quay at z 6519, the ship at 6541), the spreader at a
## few heights above its deck cargo.
const STS_PARKED := Vector2(-9.0, 36.0)
const STS_WORK_POSES := [Vector2(36.0, 22.0), Vector2(44.0, 28.0), Vector2(40.0, 33.0)]

# --- Rubber-tyred yard gantry (origin at ground level, centred, spanning Z) ------------------
const RTG_SPAN := 27.0
const RTG_LEG_X := 3.4
const RTG_H := 17.6
const RTG_EDGES := [0.0, 0.3, 1.0]

# Paint (sRGB): the terminal's own scheme, teal lower works and white upper works.
const TEAL := Color(0.07, 0.34, 0.38)
const WHITE := Color(0.86, 0.86, 0.83)
const DARK := Color(0.16, 0.17, 0.18)
const GREY := Color(0.52, 0.53, 0.54)
const YELLOW := Color(0.9, 0.68, 0.1)
const BLACK := Color(0.04, 0.04, 0.04)

# port_steel.gdshader finishes, carried in UV2.x.
const S_PAINT := 0.0
const S_STRIPE := 1.0
const S_GRATE := 2.0
const S_GLASS := 3.0
const S_RUBBER := 4.0
const S_LAMP := 5.0
const S_HOUSE := 6.0
const S_RIBBED := 7.0
const S_RED_LAMP := 8.0
const S_WINDOWS := 9.0
const S_LETTERED := 10.0

# --- Container ship (ship frame: origin at the anchor on the water, bow toward -X, y 0 is sea
# level). The hull's size is the old box hull's, which the collision still uses. -------------
const SHIP_HALF_L := 90.0
const SHIP_BOW_X := -97.0
const SHIP_BEAM := 30.0
const SHIP_DECK_Y := 8.4
## Where the containers sit (the tops of the hatch covers): the old deck top.
const SHIP_CARGO_Y := 9.0
const SHIP_KEEL_Y := -4.0
const SHIP_EDGES := [0.0, 0.4, 1.4]
const HULL_NAVY := Color(0.08, 0.11, 0.17)
const HULL_RED := Color(0.45, 0.11, 0.08)

static var _cache: Dictionary = {}


## A growing indexed mesh: points, normals, per-vertex colour and UV2 (finish or part id, AO),
## and UV in metres in each face's own plane. Every triangle is wound to face the normal it is
## given, so no caller has to think about winding. `xf` moves everything pushed (a raised boom).
class Buf:
	var v := PackedVector3Array()
	var n := PackedVector3Array()
	var uv := PackedVector2Array()
	var uv2 := PackedVector2Array()
	var col := PackedColorArray()
	var idx := PackedInt32Array()
	var xf := Transform3D.IDENTITY
	var color := Color.WHITE
	var part := 0.0
	var ao := 1.0

	func _push(p: Vector3, nrm: Vector3) -> int:
		v.append(xf * p)
		n.append((xf.basis * nrm).normalized())
		var ax := absf(nrm.x)
		var ay := absf(nrm.y)
		var az := absf(nrm.z)
		if ax >= ay and ax >= az:
			uv.append(Vector2(p.z, p.y))
		elif ay >= az:
			uv.append(Vector2(p.x, p.z))
		else:
			uv.append(Vector2(p.x, p.y))
		uv2.append(Vector2(part, ao))
		col.append(color)
		return v.size() - 1

	func quad(a: Vector3, b: Vector3, c: Vector3, d: Vector3, nrm: Vector3) -> void:
		# Front faces are the ones whose (c - a) x (b - a) points along the normal (Godot's
		# clockwise front face, as LandmarkGeo.tri() has it).
		if (c - a).cross(b - a).dot(nrm) < 0.0:
			var t := b
			b = d
			d = t
		var i0 := _push(a, nrm)
		var i1 := _push(b, nrm)
		var i2 := _push(c, nrm)
		var i3 := _push(d, nrm)
		idx.append_array(PackedInt32Array([i0, i1, i2, i0, i2, i3]))

	## An axis-aligned box. `faces` is a mask: 1 +x, 2 -x, 4 +y, 8 -y, 16 +z, 32 -z.
	func box(lo: Vector3, hi: Vector3, faces: int = 63) -> void:
		if faces & 1:
			quad(Vector3(hi.x, lo.y, lo.z), Vector3(hi.x, hi.y, lo.z), Vector3(hi.x, hi.y, hi.z), Vector3(hi.x, lo.y, hi.z), Vector3.RIGHT)
		if faces & 2:
			quad(Vector3(lo.x, lo.y, lo.z), Vector3(lo.x, lo.y, hi.z), Vector3(lo.x, hi.y, hi.z), Vector3(lo.x, hi.y, lo.z), Vector3.LEFT)
		if faces & 4:
			quad(Vector3(lo.x, hi.y, lo.z), Vector3(lo.x, hi.y, hi.z), Vector3(hi.x, hi.y, hi.z), Vector3(hi.x, hi.y, lo.z), Vector3.UP)
		if faces & 8:
			quad(Vector3(lo.x, lo.y, lo.z), Vector3(hi.x, lo.y, lo.z), Vector3(hi.x, lo.y, hi.z), Vector3(lo.x, lo.y, hi.z), Vector3.DOWN)
		if faces & 16:
			quad(Vector3(lo.x, lo.y, hi.z), Vector3(hi.x, lo.y, hi.z), Vector3(hi.x, hi.y, hi.z), Vector3(lo.x, hi.y, hi.z), Vector3.BACK)
		if faces & 32:
			quad(Vector3(lo.x, lo.y, lo.z), Vector3(lo.x, hi.y, lo.z), Vector3(hi.x, hi.y, lo.z), Vector3(hi.x, lo.y, lo.z), Vector3.FORWARD)

	## A box of `w0` x `h0` at p0 to `w1` x `h1` at p1 (width across `up` x axis, height along
	## the part of `up` square to the axis): legs, struts, braces, stair flights.
	func beam(p0: Vector3, p1: Vector3, w0: float, h0: float, w1: float = -1.0, h1: float = -1.0, up: Vector3 = Vector3.UP, caps: bool = true) -> void:
		var ax := p1 - p0
		if ax.length_squared() < 1e-8:
			return
		var a := ax.normalized()
		var side := a.cross(up)
		if side.length_squared() < 1e-6:
			side = a.cross(Vector3.RIGHT if absf(a.x) < 0.9 else Vector3.BACK)
		side = side.normalized()
		var u := side.cross(a).normalized()
		if w1 < 0.0:
			w1 = w0
		if h1 < 0.0:
			h1 = h0
		var c0: Array[Vector3] = [p0 - side * w0 * 0.5 - u * h0 * 0.5, p0 + side * w0 * 0.5 - u * h0 * 0.5,
			p0 + side * w0 * 0.5 + u * h0 * 0.5, p0 - side * w0 * 0.5 + u * h0 * 0.5]
		var c1: Array[Vector3] = [p1 - side * w1 * 0.5 - u * h1 * 0.5, p1 + side * w1 * 0.5 - u * h1 * 0.5,
			p1 + side * w1 * 0.5 + u * h1 * 0.5, p1 - side * w1 * 0.5 + u * h1 * 0.5]
		var norms: Array[Vector3] = [-u, side, u, -side]
		for i in 4:
			var j := (i + 1) % 4
			quad(c0[i], c0[j], c1[j], c1[i], norms[i])
		if caps:
			quad(c0[0], c0[1], c0[2], c0[3], -a)
			quad(c1[0], c1[1], c1[2], c1[3], a)

	## A smooth-sided prism of `sides` round p0 -> p1 (bars, wheels, ropes, stays, drums).
	func cyl(p0: Vector3, p1: Vector3, r: float, sides: int = 6, caps: bool = false, r1: float = -1.0) -> void:
		var ax := p1 - p0
		if ax.length_squared() < 1e-8:
			return
		var a := ax.normalized()
		var side := a.cross(Vector3.UP if absf(a.y) < 0.9 else Vector3.RIGHT).normalized()
		var u := side.cross(a)
		if r1 < 0.0:
			r1 = r
		var ring: Array[int] = []
		for i in sides:
			var ang := TAU * float(i) / float(sides)
			var d := side * cos(ang) + u * sin(ang)
			ring.append(_push(p0 + d * r, d))
			ring.append(_push(p1 + d * r1, d))
		for i in sides:
			var j := (i + 1) % sides
			var a0 := ring[i * 2]
			var a1 := ring[i * 2 + 1]
			var b0 := ring[j * 2]
			var b1 := ring[j * 2 + 1]
			var out := (n[a0] + n[b0]).normalized()
			_tri_idx(a0, b0, b1, out)
			_tri_idx(a0, b1, a1, out)
		if caps:
			for end in 2:
				var centre := p0 if end == 0 else p1
				var rr := r if end == 0 else r1
				var nrm := -a if end == 0 else a
				var c := _push(centre, nrm)
				var pts: Array[int] = []
				for i in sides:
					var ang := TAU * float(i) / float(sides)
					pts.append(_push(centre + (side * cos(ang) + u * sin(ang)) * rr, nrm))
				for i in sides:
					_tri_idx(c, pts[i], pts[(i + 1) % sides], xf.basis * nrm)

	func _tri_idx(i0: int, i1: int, i2: int, want: Vector3) -> void:
		if (v[i2] - v[i0]).cross(v[i1] - v[i0]).dot(want) < 0.0:
			idx.append_array(PackedInt32Array([i0, i2, i1]))
		else:
			idx.append_array(PackedInt32Array([i0, i1, i2]))

	func arrays() -> Array:
		var out := []
		out.resize(Mesh.ARRAY_MAX)
		out[Mesh.ARRAY_VERTEX] = v
		out[Mesh.ARRAY_NORMAL] = n
		out[Mesh.ARRAY_TEX_UV] = uv
		out[Mesh.ARRAY_TEX_UV2] = uv2
		out[Mesh.ARRAY_COLOR] = col
		out[Mesh.ARRAY_INDEX] = idx
		return out

	func triangles() -> int:
		return idx.size() / 3


## Levels of one object as one mesh: their vertices one after another in a single buffer, level
## 0's triangles as the base and each coarser level's as a LOD at its `edges` entry (metres), so
## a MultiMesh draws any level of any instance with no second node (PropFactory._palm_ladder()).
static func ladder(levels: Array, edges: Array, material: Material, first: int = 0) -> ArrayMesh:
	var base: Buf = levels[first]
	var arrays: Array = base.arrays().duplicate(true)
	var lods := {}
	var offset: int = (arrays[Mesh.ARRAY_VERTEX] as PackedVector3Array).size()
	for l in range(first + 1, levels.size()):
		var src: Array = (levels[l] as Buf).arrays()
		for slot in Mesh.ARRAY_MAX:
			if slot == Mesh.ARRAY_INDEX or arrays[slot] == null:
				continue
			arrays[slot].append_array(src[slot])
		var li: PackedInt32Array = (src[Mesh.ARRAY_INDEX] as PackedInt32Array).duplicate()
		for i in li.size():
			li[i] += offset
		lods[float(edges[l])] = li
		offset += (src[Mesh.ARRAY_VERTEX] as PackedVector3Array).size()
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays, [], lods)
	mesh.surface_set_material(0, material)
	return mesh


## Builds every kit mesh the port can ask for (the container, the gantry, the crane in each
## pose, the quay pieces), ~100 ms, so the loading screen pays for it rather than the first port
## chunk to stream in; returns the materials the loading screen should draw once through a
## MultiMesh (the batches' pipeline variant).
static func warm() -> Array:
	container_mesh()
	container_shadow_mesh()
	rtg_mesh()
	sts_mesh(true, STS_PARKED.x, STS_PARKED.y)
	for pose: Vector2 in STS_WORK_POSES:
		sts_mesh(false, pose.x, pose.y)
	mast_mesh()
	bollard_mesh()
	fender_mesh()
	return [container_material(), steel_material()]


# --- Containers --------------------------------------------------------------------------------

static func container_material() -> ShaderMaterial:
	if _cache.has("container_mat"):
		return _cache["container_mat"]
	var mat := ShaderMaterial.new()
	mat.shader = load("res://shaders/container.gdshader")
	_cache["container_mat"] = mat
	return mat


## The 40 ft container mesh (all sizes, see the header), centred on its box like the old
## `PropFactory.container()` so every transform that placed a box still places a container.
static func container_mesh() -> ArrayMesh:
	if _cache.has("container"):
		return _cache["container"]
	var levels: Array = [_container_level(0), _container_level(1), _container_level(2)]
	var mesh := ladder(levels, CONTAINER_EDGES, container_material())
	_cache["container"] = mesh
	return mesh


## The container's shadow stand-in: a box pulled in a few centimetres behind every panel, so the
## box never shadows the recessed panels of the container it stands for (a proxy face in front
## of a lit face is a shadow on it), and cut 3 cm off the top and bottom for the roof's sake.
static func container_shadow_mesh() -> ArrayMesh:
	if _cache.has("container_shadow"):
		return _cache["container_shadow"]
	var b := Buf.new()
	var hl := L40 * 0.5
	var hh := H_STD * 0.5
	var hw := W * 0.5
	b.box(Vector3(-hl + 0.06, -hh + 0.03, -hw + 0.06), Vector3(hl - 0.09, hh - 0.03, hw - 0.06))
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, b.arrays())
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mesh.surface_set_material(0, mat)
	_cache["container_shadow"] = mesh
	return mesh


## One level of the container (doors at +X, the front wall at -X). 0 is the full box, 1 drops
## the castings, door hardware and gasket (posts run full height), 2 is a plain box whose faces
## the shader draws as panels and frame.
static func _container_level(lv: int) -> Buf:
	var b := Buf.new()
	var hl := L40 * 0.5
	var hh := H_STD * 0.5
	var hw := W * 0.5
	if lv >= 2:
		b.part = P_SIDE
		b.box(Vector3(-hl, -hh, -hw), Vector3(hl, hh, hw), 16 | 32)
		b.part = P_ROOF
		b.box(Vector3(-hl, -hh, -hw), Vector3(hl, hh, hw), 4)
		b.part = P_FRONT
		b.box(Vector3(-hl, -hh, -hw), Vector3(hl, hh, hw), 2)
		b.part = P_DOOR
		b.box(Vector3(-hl, -hh, -hw), Vector3(hl, hh, hw), 1)
		b.part = P_UNDER
		b.box(Vector3(-hl, -hh, -hw), Vector3(hl, hh, hw), 8)
		return b
	var cx := 0.178
	var cy := 0.118
	var cz := 0.162
	# Corner castings (level 0) or full-height corner posts (level 1).
	for sx: float in [-1.0, 1.0]:
		for sz: float in [-1.0, 1.0]:
			var x0 := hl - cx if sx > 0.0 else -hl
			var x1 := hl if sx > 0.0 else -hl + cx
			var z0 := hw - cz if sz > 0.0 else -hw
			var z1 := hw if sz > 0.0 else -hw + cz
			if lv == 0:
				b.part = P_CAST
				for sy: float in [-1.0, 1.0]:
					var y0 := hh - cy if sy > 0.0 else -hh
					var y1 := hh if sy > 0.0 else -hh + cy
					b.box(Vector3(x0, y0, z0), Vector3(x1, y1, z1))
				b.part = P_FRAME
				var px0 := hl - 0.16 if sx > 0.0 else -hl + 0.006
				var px1 := hl - 0.006 if sx > 0.0 else -hl + 0.16
				var pz0 := hw - 0.15 if sz > 0.0 else -hw + 0.006
				var pz1 := hw - 0.006 if sz > 0.0 else -hw + 0.15
				b.box(Vector3(px0, -hh + cy, pz0), Vector3(px1, hh - cy, pz1), 1 | 2 | 16 | 32)
			else:
				b.part = P_FRAME
				b.box(Vector3(x0, -hh, z0), Vector3(x1, hh, z1))
	b.part = P_FRAME
	for sz: float in [-1.0, 1.0]:
		# Top side rail (100 mm tube) and bottom side rail (a 160 mm channel).
		var tz0 := hw - 0.1 if sz > 0.0 else -hw + 0.008
		var tz1 := hw - 0.008 if sz > 0.0 else -hw + 0.1
		b.box(Vector3(-hl + cx, hh - 0.1, tz0), Vector3(hl - cx, hh - 0.004, tz1), 4 | 8 | 16 | 32)
		var bz0 := hw - 0.07 if sz > 0.0 else -hw + 0.008
		var bz1 := hw - 0.008 if sz > 0.0 else -hw + 0.07
		b.box(Vector3(-hl + cx, -hh + 0.004, bz0), Vector3(hl - cx, -hh + 0.162, bz1), 4 | 8 | (16 if sz > 0.0 else 32))
	# Front end: top rail and sill.
	b.box(Vector3(-hl + 0.008, hh - 0.13, -hw + cz), Vector3(-hl + 0.13, hh - 0.004, hw - cz), 2 | 4 | 8)
	b.box(Vector3(-hl + 0.008, -hh + 0.004, -hw + cz), Vector3(-hl + 0.13, -hh + 0.15, hw - cz), 2 | 4 | 8)
	# Door end: header and sill, their faces about flush with the doors.
	b.box(Vector3(hl - 0.2, hh - 0.2, -hw + cz), Vector3(hl - 0.07, hh - 0.004, hw - cz), 1 | 4 | 8)
	b.box(Vector3(hl - 0.2, -hh + 0.004, -hw + cz), Vector3(hl - 0.07, -hh + 0.19, hw - cz), 1 | 4 | 8)
	# Panels, recessed behind the frame; the shader corrugates them.
	b.part = P_SIDE
	for sz: float in [-1.0, 1.0]:
		var z := sz * (hw - 0.045)
		b.quad(Vector3(-hl + 0.16, -hh + 0.162, z), Vector3(hl - 0.16, -hh + 0.162, z), Vector3(hl - 0.16, hh - 0.1, z), Vector3(-hl + 0.16, hh - 0.1, z), Vector3(0.0, 0.0, sz))
	b.part = P_ROOF
	var ry := hh - 0.025
	b.quad(Vector3(-hl + 0.13, ry, -hw + 0.1), Vector3(hl - 0.2, ry, -hw + 0.1), Vector3(hl - 0.2, ry, hw - 0.1), Vector3(-hl + 0.13, ry, hw - 0.1), Vector3.UP)
	b.part = P_FRONT
	var fx := -hl + 0.045
	b.quad(Vector3(fx, -hh + 0.15, -hw + 0.15), Vector3(fx, -hh + 0.15, hw - 0.15), Vector3(fx, hh - 0.13, hw - 0.15), Vector3(fx, hh - 0.13, -hw + 0.15), Vector3.LEFT)
	b.part = P_UNDER
	var uy := -hh + 0.01
	b.quad(Vector3(-hl + 0.15, uy, -hw + 0.06), Vector3(hl - 0.15, uy, -hw + 0.06), Vector3(hl - 0.15, uy, hw - 0.06), Vector3(-hl + 0.15, uy, hw - 0.06), Vector3.DOWN)
	# Door leaves: their front face and the edge at the centre gap.
	b.part = P_DOOR
	var dy0 := -hh + 0.19
	var dy1 := hh - 0.2
	for sz: float in [-1.0, 1.0]:
		var z0 := 0.006 if sz > 0.0 else -(hw - 0.15)
		var z1 := hw - 0.15 if sz > 0.0 else -0.006
		b.box(Vector3(hl - 0.12, dy0, z0), Vector3(hl - 0.075, dy1, z1), 1 | (32 if sz > 0.0 else 16))
	if lv == 0:
		b.part = P_RUBBER
		b.box(Vector3(hl - 0.125, dy0, -0.006), Vector3(hl - 0.085, dy1, 0.006), 1)
	# Locking bars: two a leaf, with cam keepers at both ends, guides, a handle and its catch.
	b.part = P_HARD
	for sz: float in [-1.0, 1.0]:
		for bz: float in [0.24, 0.66]:
			var z := sz * bz
			if lv == 0:
				b.cyl(Vector3(hl - 0.045, -hh + 0.1, z), Vector3(hl - 0.045, hh - 0.12, z), 0.017, 6)
				for kt: float in [-1.0, 1.0]:
					var ky0 := hh - 0.19 if kt > 0.0 else -hh + 0.06
					b.box(Vector3(hl - 0.07, ky0, z - 0.05), Vector3(hl - 0.015, ky0 + 0.11, z + 0.05), 1 | 4 | 8 | 16 | 32)
					b.box(Vector3(hl - 0.075, kt * 0.55 - 0.025, z - 0.04), Vector3(hl - 0.03, kt * 0.55 + 0.025, z + 0.04), 1 | 4 | 8 | 16 | 32)
				var hz0 := minf(z, z + sz * 0.36)
				var hz1 := maxf(z, z + sz * 0.36)
				b.box(Vector3(hl - 0.04, -0.27, hz0), Vector3(hl - 0.012, -0.23, hz1), 1 | 4 | 8 | 16 | 32)
				var cz0 := z + sz * 0.38
				b.box(Vector3(hl - 0.07, -0.3, cz0 - 0.03), Vector3(hl - 0.03, -0.2, cz0 + 0.03), 1 | 4 | 8 | 16 | 32)
			else:
				b.box(Vector3(hl - 0.062, -hh + 0.1, z - 0.017), Vector3(hl - 0.028, hh - 0.12, z + 0.017), 1 | 16 | 32)
	if lv == 0:
		# Hinges down each leaf's outer edge.
		for sz: float in [-1.0, 1.0]:
			for hy: float in [-0.95, -0.33, 0.33, 0.95]:
				var z0 := minf(sz * (hw - 0.2), sz * (hw - 0.13))
				var z1 := maxf(sz * (hw - 0.2), sz * (hw - 0.13))
				b.box(Vector3(hl - 0.08, hy - 0.06, z0), Vector3(hl - 0.02, hy + 0.06, z1), 1 | 4 | 8 | 16 | 32)
	return b


## The instance transform for a container whose box centre is `centre`: `forty` false for a
## 20 ft box, `high_cube` for a 9'6" one, `flip` turns the doors to -X.
static func container_xform(centre: Vector3, forty: bool, high_cube: bool, flip: bool) -> Transform3D:
	var basis := Basis(Vector3.UP, PI) if flip else Basis()
	basis = basis.scaled_local(Vector3(1.0 if forty else L20 / L40, H_HC / H_STD if high_cube else 1.0, 1.0))
	return Transform3D(basis, centre)


## Instance colour (the livery's paint, jittered so no two boxes of a line are one colour) and
## custom data (livery, weathering, seed, 1) for livery `livery`, from `rng`.
static func container_look(livery: int, rng: RandomNumberGenerator) -> Array:
	var paint: Color = LIVERY_PAINT[clampi(livery, 0, LIVERY_COUNT - 1)]
	var j := rng.randf_range(-0.06, 0.06)
	var fade := rng.randf_range(0.0, 0.08)
	paint = Color(paint.r * (1.0 + j) + fade * 0.4, paint.g * (1.0 + j) + fade * 0.4, paint.b * (1.0 + j * 0.8) + fade * 0.4)
	var wear := pow(rng.randf(), 1.7) * 0.75
	if livery == 8:
		wear = rng.randf_range(0.6, 1.0)
	var custom := Color((float(livery) + 0.5) / 16.0, wear, rng.randf(), 1.0)
	return [paint.clamp(), custom]


# --- Ship-to-shore gantry crane ---------------------------------------------------------------

static func steel_material() -> ShaderMaterial:
	if _cache.has("steel_mat"):
		return _cache["steel_mat"]
	var mat := ShaderMaterial.new()
	mat.shader = load("res://shaders/port_steel.gdshader")
	_cache["steel_mat"] = mat
	return mat


## Where the raised boom's hinge is (crane frame).
static func sts_hinge() -> Vector3:
	return Vector3(0.0, STS_PORTAL_Y + STS_GIRDER_D * 0.5, STS_GAUGE * 0.5 + 1.5)


## The transform that stands the boom up about its hinge (identity when lowered).
static func sts_boom_xf(raised: bool) -> Transform3D:
	if not raised:
		return Transform3D.IDENTITY
	var h := sts_hinge()
	return Transform3D(Basis.IDENTITY, h) * Transform3D(Basis(Vector3.RIGHT, -deg_to_rad(STS_RAISED_DEG)), Vector3.ZERO) * Transform3D(Basis.IDENTITY, -h)


## A whole ship-to-shore crane as one mesh with its LOD ladder, cached per pose: `raised` boom,
## the trolley at `trolley_z` along the girders (crane frame) and the spreader's underside at
## `spreader_y`.
static func sts_mesh(raised: bool, trolley_z: float, spreader_y: float) -> ArrayMesh:
	var key := "sts_%d_%d_%d" % [int(raised), roundi(trolley_z), roundi(spreader_y)]
	if _cache.has(key):
		return _cache[key]
	var levels: Array = []
	for lv in 3:
		levels.append(_sts_level(lv, raised, trolley_z, spreader_y))
	var mesh := ladder(levels, STS_EDGES, steel_material())
	_cache[key] = mesh
	return mesh


static func _sts_level(lv: int, raised: bool, trolley_z: float, spreader_y: float) -> Buf:
	var b := Buf.new()
	var gz := STS_GAUGE * 0.5
	var lx := STS_LEG_X
	var py := STS_PORTAL_Y
	var gt := py + STS_GIRDER_D
	var gx := STS_GIRDER_X
	var hinge_z := gz + 1.5
	var tip := gz + STS_OUTREACH
	var back := -gz - STS_BACKREACH
	var boom := sts_boom_xf(raised)
	# --- Bogies: an equaliser beam on two four-wheel bogies under each leg, rubber buffers.
	for sx: float in [-1.0, 1.0]:
		for sz: float in [-1.0, 1.0]:
			var fx := sx * lx
			var fz := sz * gz
			b.color = YELLOW
			b.part = S_STRIPE
			b.box(Vector3(fx - 3.8, 1.55, fz - 0.8), Vector3(fx + 3.8, 2.4, fz + 0.8))
			b.color = DARK
			b.part = S_PAINT
			for bx: float in [-1.9, 1.9]:
				b.box(Vector3(fx + bx - 1.55, 0.75, fz - 0.62), Vector3(fx + bx + 1.55, 1.55, fz + 0.62), 1 | 2 | 8 | 16 | 32)
				if lv == 0:
					for wx: float in [-0.8, 0.8]:
						b.cyl(Vector3(fx + bx + wx, 0.45, fz - 0.14), Vector3(fx + bx + wx, 0.45, fz + 0.14), 0.45, 6, true)
			if lv <= 1:
				b.color = BLACK
				b.part = S_RUBBER
				for ex: float in [-1.0, 1.0]:
					b.box(Vector3(fx + ex * 3.8 - 0.35, 1.6, fz - 0.45), Vector3(fx + ex * 3.8 + 0.35, 2.3, fz + 0.45))
	# --- Legs: tapered box sections, hazard striped at the foot.
	for sx: float in [-1.0, 1.0]:
		for sz: float in [-1.0, 1.0]:
			var fx := sx * lx
			var fz := sz * gz
			var foot := 2.4
			var band := 7.0
			var top := py - 1.5
			var w_at := func(y: float) -> float: return lerpf(2.3, 1.85, (y - foot) / (top - foot))
			b.color = YELLOW
			b.part = S_STRIPE
			b.beam(Vector3(fx, foot, fz), Vector3(fx, band, fz), w_at.call(foot), w_at.call(foot), w_at.call(band), w_at.call(band), Vector3.BACK)
			b.color = TEAL
			b.part = S_PAINT
			b.beam(Vector3(fx, band, fz), Vector3(fx, top, fz), w_at.call(band), w_at.call(band), w_at.call(top), w_at.call(top), Vector3.BACK, false)
	# --- Portal: sill beams low along each side, portal beams across the top, ties, knee braces.
	b.color = TEAL
	b.part = S_PAINT
	for sx: float in [-1.0, 1.0]:
		b.beam(Vector3(sx * lx, 14.0, -gz + 1.1), Vector3(sx * lx, 14.0, gz - 1.1), 1.5, 1.8)
		b.beam(Vector3(sx * lx, py - 1.5, -gz + 1.1), Vector3(sx * lx, py - 1.5, gz - 1.1), 1.3, 2.6)
	for sz: float in [-1.0, 1.0]:
		b.box(Vector3(-lx - 1.0, py - 3.0, sz * gz - 1.1), Vector3(lx + 1.0, py, sz * gz + 1.1))
		if lv <= 1:
			for sx: float in [-1.0, 1.0]:
				b.beam(Vector3(sx * lx, py - 10.0, sz * gz), Vector3(sx * (lx - 4.8), py - 3.0, sz * gz), 0.9, 0.9, -1.0, -1.0, Vector3.BACK)
	# --- Girders over the portal and the back-reach (white, ribbed), their cross ties and rails.
	b.color = WHITE
	b.part = S_RIBBED
	for sx: float in [-1.0, 1.0]:
		b.box(Vector3(sx * gx - 0.75, py, back), Vector3(sx * gx + 0.75, gt, hinge_z))
	b.part = S_PAINT
	var tz := back + 2.0
	while tz < hinge_z - 1.0:
		b.box(Vector3(-gx + 0.75, py, tz - 0.35), Vector3(gx - 0.75, py + 0.7, tz + 0.35), 4 | 8 | 16 | 32)
		tz += 9.0
	b.box(Vector3(-gx - 0.75, py, back - 0.6), Vector3(gx + 0.75, gt, back), 2 | 1 | 4 | 32)
	if lv <= 1:
		# Plan bracing under the girders: a zig-zag between their bottom chords.
		var bz0 := back + 2.0
		var side := 1.0
		while bz0 < hinge_z - 5.0:
			b.beam(Vector3(-side * (gx - 0.75), py + 0.25, bz0), Vector3(side * (gx - 0.75), py + 0.25, bz0 + 4.5), 0.3, 0.3)
			bz0 += 4.5
			side = -side
	if lv <= 1:
		b.color = DARK
		for sx: float in [-1.0, 1.0]:
			b.box(Vector3(sx * gx - 0.09, gt, back + 0.5), Vector3(sx * gx + 0.09, gt + 0.16, hinge_z), 1 | 2 | 4 | 32)
	# --- Machinery house on the back-reach, a teal fascia round its eaves, plant on its roof.
	var hz0 := back + 0.6
	var hz1 := back + 20.0
	b.color = WHITE
	b.part = S_HOUSE
	b.box(Vector3(-6.0, gt, hz0), Vector3(6.0, gt + 6.6, hz1), 1 | 2 | 16 | 32)
	b.part = S_PAINT
	b.color = Color(0.78, 0.79, 0.78)
	b.box(Vector3(-6.0, gt + 6.6, hz0), Vector3(6.0, gt + 6.7, hz1), 4)
	b.color = TEAL
	b.box(Vector3(-6.06, gt + 5.9, hz0 - 0.06), Vector3(6.06, gt + 6.75, hz1 + 0.06), 1 | 2 | 16 | 32)
	if lv <= 1:
		b.color = GREY
		b.box(Vector3(-4.5, gt + 6.7, hz0 + 3.0), Vector3(-1.5, gt + 8.0, hz0 + 6.0))
		b.box(Vector3(1.5, gt + 6.7, hz0 + 9.0), Vector3(4.2, gt + 7.6, hz0 + 14.0))
		# A maintenance hoist rail along the roof, on two posts.
		b.color = YELLOW
		b.box(Vector3(-0.2, gt + 6.7, hz0 + 1.0), Vector3(0.2, gt + 9.2, hz0 + 1.4))
		b.box(Vector3(-0.2, gt + 6.7, hz1 - 1.4), Vector3(0.2, gt + 9.2, hz1 - 1.0))
		b.box(Vector3(-0.25, gt + 9.2, hz0 + 1.0), Vector3(0.25, gt + 9.6, hz1 - 1.0))
	if lv == 0:
		# Handrails round the house roof.
		b.color = YELLOW
		var ry := gt + 6.7
		for sx: float in [-1.0, 1.0]:
			b.box(Vector3(sx * 5.9 - 0.03, ry + 1.0, hz0 + 0.1), Vector3(sx * 5.9 + 0.03, ry + 1.06, hz1 - 0.1), 1 | 2 | 4 | 8)
			var pz := hz0 + 0.2
			while pz < hz1:
				b.box(Vector3(sx * 5.9 - 0.03, ry, pz - 0.03), Vector3(sx * 5.9 + 0.03, ry + 1.0, pz + 0.03), 1 | 2 | 16 | 32)
				pz += 2.4
		for ez: float in [hz0 + 0.1, hz1 - 0.1]:
			b.box(Vector3(-5.9, ry + 1.0, ez - 0.03), Vector3(5.9, ry + 1.06, ez + 0.03), 4 | 8 | 16 | 32)
	# --- Walkways down both girders' outer sides, railings on them (level 0).
	for sx: float in [-1.0, 1.0]:
		var wx0 := minf(sx * (gx + 0.75), sx * (gx + 1.75))
		var wx1 := maxf(sx * (gx + 0.75), sx * (gx + 1.75))
		var wy := gt - 1.3
		for seg in 2:
			var z0 := back + 0.5 if seg == 0 else hinge_z
			var z1 := hinge_z if seg == 0 else tip - 0.5
			if seg == 1:
				b.xf = boom
			if lv <= 1:
				b.color = DARK
				b.part = S_GRATE
				b.box(Vector3(wx0, wy - 0.1, z0), Vector3(wx1, wy, z1), 4 | 8 | 1 | 2)
			if lv == 0:
				b.color = YELLOW
				b.part = S_PAINT
				var rx := sx * (gx + 1.72)
				var z := z0 + 0.3
				while z < z1:
					b.box(Vector3(rx - 0.03, wy, z - 0.03), Vector3(rx + 0.03, wy + 1.1, z + 0.03), 1 | 2 | 16 | 32)
					z += 2.4
				for ry: float in [wy + 0.55, wy + 1.08]:
					b.box(Vector3(rx - 0.03, ry - 0.03, z0), Vector3(rx + 0.03, ry + 0.03, z1), 1 | 2 | 4 | 8)
			b.xf = Transform3D.IDENTITY
	# --- The boom: twin girders tapering to the tip, cross ties, rails, hinge pins, tip beam.
	b.xf = boom
	b.color = WHITE
	b.part = S_RIBBED
	for sx: float in [-1.0, 1.0]:
		b.beam(Vector3(sx * gx, gt - STS_GIRDER_D * 0.5, hinge_z), Vector3(sx * gx, gt - 1.1, tip), 1.5, STS_GIRDER_D, 1.2, 2.2)
	b.part = S_PAINT
	var bz := hinge_z + 6.0
	while bz < tip - 2.0:
		var depth := lerpf(STS_GIRDER_D, 2.2, (bz - hinge_z) / (tip - hinge_z))
		b.box(Vector3(-gx + 0.7, gt - depth, bz - 0.3), Vector3(gx - 0.7, gt - depth + 0.6, bz + 0.3), 4 | 8 | 16 | 32)
		bz += 9.0
	b.box(Vector3(-gx - 0.6, gt - 2.2, tip - 0.2), Vector3(gx + 0.6, gt, tip + 0.6))
	if lv <= 1:
		var bz1 := hinge_z + 1.5
		var side2 := 1.0
		while bz1 < tip - 6.0:
			var depth := lerpf(STS_GIRDER_D, 2.2, (bz1 + 2.5 - hinge_z) / (tip - hinge_z))
			b.beam(Vector3(-side2 * (gx - 0.7), gt - depth + 0.2, bz1), Vector3(side2 * (gx - 0.7), gt - depth + 0.2, bz1 + 5.0), 0.26, 0.26)
			bz1 += 5.0
			side2 = -side2
		# The sheave house over the boom tip.
		b.color = WHITE
		b.box(Vector3(-2.2, gt, tip - 3.4), Vector3(2.2, gt + 1.8, tip - 0.2))
	if lv <= 1:
		b.color = DARK
		for sx: float in [-1.0, 1.0]:
			b.box(Vector3(sx * gx - 0.09, gt, hinge_z), Vector3(sx * gx + 0.09, gt + 0.16, tip - 0.4), 1 | 2 | 4)
		b.color = GREY
		b.cyl(Vector3(-gx - 1.0, gt - STS_GIRDER_D * 0.5, hinge_z), Vector3(gx + 1.0, gt - STS_GIRDER_D * 0.5, hinge_z), 0.45, 8, true)
	if lv == 0:
		# Floodlights under the boom and a red light at its tip.
		b.color = GREY
		b.part = S_LAMP
		var lz := hinge_z + 8.0
		while lz < tip - 4.0:
			var depth := lerpf(STS_GIRDER_D, 2.2, (lz - hinge_z) / (tip - hinge_z))
			for sx: float in [-1.0, 1.0]:
				b.box(Vector3(sx * gx - 0.3, gt - depth - 0.4, lz - 0.3), Vector3(sx * gx + 0.3, gt - depth, lz + 0.3))
			lz += 12.0
		b.part = S_RED_LAMP
		b.color = Color(0.8, 0.1, 0.08)
		b.box(Vector3(-0.25, gt, tip + 0.1), Vector3(0.25, gt + 0.5, tip + 0.6))
	b.xf = Transform3D.IDENTITY
	# --- A-frame: struts from the portal to the apex, ties, the apex beam and sheave house.
	b.color = WHITE
	b.part = S_PAINT
	var apex_l := Vector3(-6.4, STS_APEX_Y, STS_APEX_Z)
	var apex_r := Vector3(6.4, STS_APEX_Y, STS_APEX_Z)
	for sx: float in [-1.0, 1.0]:
		var apex := apex_r if sx > 0.0 else apex_l
		var fr := Vector3(sx * lx, py, gz)
		var rr := Vector3(sx * lx, py, -gz)
		b.beam(fr, apex, 1.6, 1.6, 1.2, 1.2, Vector3.RIGHT)
		b.beam(rr, apex, 1.6, 1.6, 1.2, 1.2, Vector3.RIGHT)
		b.beam(fr.lerp(apex, 0.5), rr.lerp(apex, 0.5), 0.8, 0.8, -1.0, -1.0, Vector3.RIGHT)
	var ft := 0.5
	b.beam(Vector3(-lx, py, gz).lerp(apex_l, ft), Vector3(lx, py, gz).lerp(apex_r, ft), 0.8, 0.8)
	b.beam(Vector3(-lx, py, -gz).lerp(apex_l, ft), Vector3(lx, py, -gz).lerp(apex_r, ft), 0.8, 0.8)
	if lv <= 1:
		# X bracing across the back of the A-frame.
		b.beam(Vector3(-lx, py, -gz).lerp(apex_l, 0.12), Vector3(lx, py, -gz).lerp(apex_r, 0.48), 0.5, 0.5)
		b.beam(Vector3(lx, py, -gz).lerp(apex_r, 0.12), Vector3(-lx, py, -gz).lerp(apex_l, 0.48), 0.5, 0.5)
	b.box(Vector3(-7.2, STS_APEX_Y - 1.0, STS_APEX_Z - 1.0), Vector3(7.2, STS_APEX_Y + 1.2, STS_APEX_Z + 1.0))
	b.box(Vector3(-2.6, STS_APEX_Y + 1.2, STS_APEX_Z - 2.0), Vector3(2.6, STS_APEX_Y + 3.8, STS_APEX_Z + 2.0))
	if lv <= 1:
		b.part = S_RED_LAMP
		b.color = Color(0.8, 0.1, 0.08)
		b.box(Vector3(-0.3, STS_APEX_Y + 3.8, STS_APEX_Z - 0.3), Vector3(0.3, STS_APEX_Y + 4.4, STS_APEX_Z + 0.3))
	# --- Stays: forestays from the apex to the boom, backstays to the back-reach.
	if lv <= 1:
		b.color = Color(0.7, 0.71, 0.7)
		b.part = S_PAINT
		for sx: float in [-1.0, 1.0]:
			var apex := (apex_r if sx > 0.0 else apex_l) + Vector3(0.0, 0.5, 0.0)
			for at: float in [hinge_z + 30.0, tip - 3.0]:
				b.cyl(apex, boom * Vector3(sx * gx, gt, at), 0.2, 6)
			b.cyl(apex, Vector3(sx * gx, gt + 0.2, back + 2.0), 0.22, 6)
	# --- Trolley on the girders, the operator's cab hung under it, hoist ropes, the spreader.
	var tpos := trolley_z
	var on_boom := tpos > hinge_z
	b.xf = boom if on_boom else Transform3D.IDENTITY
	b.color = Color(0.8, 0.81, 0.8)
	b.part = S_PAINT
	b.box(Vector3(-gx - 0.9, gt + 0.16, tpos - 5.0), Vector3(gx + 0.9, gt + 2.6, tpos + 5.0))
	if lv <= 1:
		b.color = GREY
		b.box(Vector3(-2.2, gt + 2.6, tpos - 3.0), Vector3(2.2, gt + 3.5, tpos + 2.0))
	if lv == 0:
		# Rope sheaves on the trolley deck and its wheels on the rails.
		b.color = DARK
		for rx: float in [-0.9, 0.9]:
			for rz: float in [-1.8, 1.8]:
				b.cyl(Vector3(rx - 0.25, gt + 2.6, tpos + rz), Vector3(rx + 0.25, gt + 2.6, tpos + rz), 0.55, 8, true)
		for sx: float in [-1.0, 1.0]:
			for wz: float in [-3.8, 3.8]:
				b.cyl(Vector3(sx * gx - 0.15, gt + 0.45, tpos + wz), Vector3(sx * gx + 0.15, gt + 0.45, tpos + wz), 0.42, 8, true)
	# The cab: glass on every side, a frame at roof and floor, hangers up to the trolley.
	b.color = Color(0.8, 0.81, 0.8)
	b.box(Vector3(0.2, py - 0.8, tpos + 1.5), Vector3(3.0, py - 0.3, tpos + 4.6))
	b.box(Vector3(0.2, py - 3.6, tpos + 1.5), Vector3(3.0, py - 3.3, tpos + 4.6))
	b.part = S_GLASS
	b.color = Color(0.2, 0.24, 0.28)
	b.box(Vector3(0.25, py - 3.3, tpos + 1.55), Vector3(2.95, py - 0.8, tpos + 4.55), 1 | 2 | 16 | 32)
	if lv <= 1:
		b.part = S_PAINT
		b.color = GREY
		for hz: float in [tpos + 1.8, tpos + 4.3]:
			b.box(Vector3(1.0, py - 0.3, hz - 0.12), Vector3(2.2, gt + 0.2, hz + 0.12), 1 | 2 | 16 | 32)
	if lv == 0:
		b.color = Color(0.12, 0.12, 0.12)
		b.part = S_PAINT
		for rx: float in [-0.9, 0.9]:
			for rz: float in [-1.8, 1.8]:
				b.cyl(Vector3(rx, gt + 0.2, tpos + rz), Vector3(rx, spreader_y + 1.2, tpos + rz), 0.04, 4)
	b.xf = Transform3D.IDENTITY
	# The spreader hangs plumb whatever the boom does.
	var sp := boom * Vector3(0.0, 0.0, tpos) if on_boom else Vector3(0.0, 0.0, tpos)
	b.color = YELLOW
	b.part = S_PAINT
	b.box(Vector3(-1.2, spreader_y + 0.45, sp.z - 1.5), Vector3(1.2, spreader_y + 1.25, sp.z + 1.5))
	b.box(Vector3(-6.1, spreader_y, sp.z - 0.35), Vector3(6.1, spreader_y + 0.45, sp.z + 0.35))
	for ex: float in [-1.0, 1.0]:
		b.box(Vector3(ex * 5.95 - 0.16, spreader_y, sp.z - 1.22), Vector3(ex * 5.95 + 0.16, spreader_y + 0.45, sp.z + 1.22))
		if lv == 0:
			# Flippers at the corners, turned down to guide it onto a box, and the motor housings.
			for ez: float in [-1.0, 1.0]:
				b.box(Vector3(ex * 6.08 - 0.08, spreader_y - 0.55, sp.z + ez * 1.22 - 0.25), Vector3(ex * 6.08 + 0.08, spreader_y + 0.1, sp.z + ez * 1.22 + 0.25))
			b.color = GREY
			b.box(Vector3(ex * 3.2 - 0.6, spreader_y + 0.45, sp.z - 0.5), Vector3(ex * 3.2 + 0.6, spreader_y + 0.95, sp.z + 0.5))
			b.color = YELLOW
	# --- The lift shaft up the other landside leg (levels 0-1), its machine room on top.
	if lv <= 1:
		b.color = Color(0.7, 0.72, 0.72)
		b.part = S_RIBBED
		b.box(Vector3(-lx - 3.4, 2.4, -gz - 1.1), Vector3(-lx - 1.2, py - 5.0, -gz + 1.1), 2 | 16 | 32 | 4)
		b.part = S_PAINT
		b.color = TEAL
		b.box(Vector3(-lx - 3.6, py - 5.0, -gz - 1.3), Vector3(-lx - 1.2, py - 2.8, -gz + 1.3), 2 | 16 | 32 | 4)
	else:
		b.color = Color(0.78, 0.79, 0.78)
		b.part = S_PAINT
		b.box(Vector3(-lx - 3.4, 2.4, -gz - 1.1), Vector3(-lx - 1.2, py - 3.0, -gz + 1.1), 2 | 16 | 32)
	# --- The stair tower up the outside of a landside leg (levels 0-1; a slab at level 2).
	var sx0 := lx + 1.3
	var sx1 := lx + 2.3
	var za := -gz - 0.9
	var zb := -gz + 2.9
	if lv <= 1:
		b.color = GREY
		var y := 2.4
		var k := 0
		while y < py - 4.0:
			var z0 := za if k % 2 == 0 else zb
			var z1 := zb if k % 2 == 0 else za
			b.part = S_GRATE
			b.beam(Vector3((sx0 + sx1) * 0.5, y, z0), Vector3((sx0 + sx1) * 0.5, y + 3.4, z1), 1.0, 0.14, -1.0, -1.0, Vector3.UP)
			var land := z1 + (0.6 if k % 2 == 0 else -0.6)
			b.box(Vector3(sx0, y + 3.3, minf(land, z1) - 0.6), Vector3(sx1, y + 3.44, maxf(land, z1) + 0.6), 4 | 8 | 16 | 32 | 1)
			if lv == 0:
				b.part = S_PAINT
				b.color = YELLOW
				b.beam(Vector3(sx1 + 0.03, y + 1.0, z0), Vector3(sx1 + 0.03, y + 4.4, z1), 0.05, 0.05)
				b.color = GREY
			y += 3.4
			k += 1
		b.part = S_PAINT
		for pz: float in [za - 1.2, zb + 1.2]:
			b.box(Vector3(sx1 + 0.05, 2.4, pz - 0.08), Vector3(sx1 + 0.2, py - 3.0, pz + 0.08), 1 | 2 | 16 | 32)
	else:
		b.color = GREY
		b.part = S_PAINT
		b.box(Vector3(sx0, 2.4, za - 1.2), Vector3(sx1 + 0.2, py - 3.0, zb + 1.2), 1 | 16 | 32)
	# --- Cable reel on a landside leg, its drum's axis along the quay.
	if lv <= 1:
		b.color = DARK
		b.part = S_PAINT
		b.cyl(Vector3(-lx + 1.2, 5.6, -gz - 2.6), Vector3(-lx + 2.4, 5.6, -gz - 2.6), 2.1, 12 if lv == 0 else 8, true)
		b.box(Vector3(-lx + 1.4, 2.4, -gz - 1.2), Vector3(-lx + 2.2, 5.6, -gz - 0.9))
	# Floodlights under the portal beams.
	if lv == 0:
		b.color = GREY
		b.part = S_LAMP
		for sz: float in [-1.0, 1.0]:
			for fx: float in [-5.0, 5.0]:
				b.box(Vector3(fx - 0.3, py - 3.45, sz * gz - 0.3), Vector3(fx + 0.3, py - 3.0, sz * gz + 0.3))
	return b


# --- Rubber-tyred yard gantry -----------------------------------------------------------------

static func rtg_mesh() -> ArrayMesh:
	if _cache.has("rtg"):
		return _cache["rtg"]
	var levels: Array = [_rtg_level(0), _rtg_level(1), _rtg_level(2)]
	var mesh := ladder(levels, RTG_EDGES, steel_material())
	_cache["rtg"] = mesh
	_cache["rtg_shadow"] = ladder(levels, RTG_EDGES, steel_material(), 1)
	return mesh


## The yard gantry's shadow twin: its own ladder from level 1 (no railings, wheels or ropes).
static func rtg_shadow_mesh() -> ArrayMesh:
	rtg_mesh()
	return _cache["rtg_shadow"]


## One level of the yard gantry: a teal sill beam on tyres each side, teal legs, white girders
## across the span, the trolley over the middle row with its spreader parked high, a diesel
## house on one sill and a stair up one leg.
static func _rtg_level(lv: int) -> Buf:
	var b := Buf.new()
	var hz := RTG_SPAN * 0.5
	var lx := RTG_LEG_X
	var h := RTG_H
	var gt := h + 1.5
	for sz: float in [-1.0, 1.0]:
		var z := sz * hz
		b.color = TEAL
		b.part = S_PAINT
		b.box(Vector3(-lx - 1.2, 1.25, z - 0.55), Vector3(lx + 1.2, 2.3, z + 0.55))
		b.color = YELLOW
		b.part = S_STRIPE
		for sx: float in [-1.0, 1.0]:
			b.box(Vector3(sx * lx - 1.5, 0.95, z - 0.5), Vector3(sx * lx + 1.5, 1.25, z + 0.5), 1 | 2 | 8 | 16 | 32)
			for tx: float in [-0.75, 0.75]:
				b.color = BLACK
				b.part = S_RUBBER
				b.cyl(Vector3(sx * lx + tx, 0.72, z - 0.32), Vector3(sx * lx + tx, 0.72, z + 0.32), 0.72, 12 if lv == 0 else 8, lv <= 1)
				if lv == 0:
					b.color = GREY
					b.part = S_PAINT
					for hs: float in [-1.0, 1.0]:
						b.cyl(Vector3(sx * lx + tx, 0.72, z + hs * 0.32), Vector3(sx * lx + tx, 0.72, z + hs * 0.36), 0.36, 8, true)
				b.color = YELLOW
				b.part = S_STRIPE
	# Legs, hazard striped at the foot, and knee braces to the end beams.
	for sx: float in [-1.0, 1.0]:
		for sz: float in [-1.0, 1.0]:
			var foot := Vector3(sx * lx, 2.3, sz * hz)
			var head := Vector3(sx * (lx - 0.3), h, sz * (hz - 0.2))
			var band := foot.lerp(head, 0.15)
			b.color = YELLOW
			b.part = S_STRIPE
			b.beam(foot, band, 0.95, 0.95, 0.93, 0.93, Vector3.BACK, false)
			b.color = TEAL
			b.part = S_PAINT
			b.beam(band, head, 0.93, 0.93, 0.8, 0.8, Vector3.BACK, false)
			if lv <= 1:
				b.beam(Vector3(sx * (lx - 0.2), h - 3.6, sz * (hz - 0.2)), Vector3(sx * (lx - 2.4), h, sz * (hz - 0.2)), 0.45, 0.45, -1.0, -1.0, Vector3.BACK)
	# Girders across the span, end beams over the legs, trolley rails.
	b.color = WHITE
	b.part = S_RIBBED
	for sx: float in [-1.0, 1.0]:
		b.box(Vector3(sx * (lx - 0.3) - 0.45, h, -hz - 1.1), Vector3(sx * (lx - 0.3) + 0.45, gt, hz + 1.1))
	b.part = S_PAINT
	for sz: float in [-1.0, 1.0]:
		b.box(Vector3(-lx - 0.2, h - 0.25, sz * (hz - 0.2) - 0.55), Vector3(lx + 0.2, gt, sz * (hz - 0.2) + 0.55))
	if lv <= 1:
		b.color = DARK
		for sx: float in [-1.0, 1.0]:
			b.box(Vector3(sx * (lx - 0.3) - 0.07, gt, -hz - 0.8), Vector3(sx * (lx - 0.3) + 0.07, gt + 0.12, hz + 0.8), 1 | 2 | 4)
	# Trolley with its machinery and the cab hung off its side.
	b.color = WHITE
	b.part = S_PAINT
	b.box(Vector3(-lx - 0.3, gt + 0.12, -2.3), Vector3(lx + 0.3, gt + 2.0, 2.3))
	b.color = TEAL
	b.box(Vector3(-2.0, gt + 2.0, -1.6), Vector3(1.6, gt + 2.9, 1.4))
	b.color = Color(0.8, 0.81, 0.8)
	b.box(Vector3(lx + 0.3, h - 1.3, 0.3), Vector3(lx + 2.2, h - 1.0, 2.3))
	b.box(Vector3(lx + 0.3, h + 1.2, 0.3), Vector3(lx + 2.2, h + 1.5, 2.3))
	b.color = Color(0.2, 0.24, 0.28)
	b.part = S_GLASS
	b.box(Vector3(lx + 0.35, h - 1.0, 0.35), Vector3(lx + 2.15, h + 1.2, 2.25), 1 | 2 | 16 | 32)
	b.part = S_PAINT
	var spy := h - 5.5
	if lv == 0:
		b.color = Color(0.12, 0.12, 0.12)
		for rx: float in [-0.7, 0.7]:
			for rz: float in [-1.2, 1.2]:
				b.cyl(Vector3(rx, gt + 0.1, rz), Vector3(rx, spy + 1.0, rz), 0.035, 4)
	b.color = YELLOW
	b.box(Vector3(-1.0, spy + 0.4, -1.3), Vector3(1.0, spy + 1.0, 1.3))
	b.box(Vector3(-6.1, spy, -0.3), Vector3(6.1, spy + 0.4, 0.3))
	for ex: float in [-1.0, 1.0]:
		b.box(Vector3(ex * 5.95 - 0.14, spy, -1.22), Vector3(ex * 5.95 + 0.14, spy + 0.4, 1.22))
	# The diesel house outside one sill, louvred, and a stair up the leg next to it.
	b.color = WHITE
	b.part = S_HOUSE
	b.box(Vector3(-2.6, 2.3, -hz - 2.5), Vector3(2.6, 4.7, -hz - 0.55), 1 | 2 | 4 | 32)
	if lv <= 1:
		b.color = DARK
		b.part = S_PAINT
		b.cyl(Vector3(1.8, 4.7, -hz - 1.2), Vector3(1.8, 5.8, -hz - 1.2), 0.12, 6)
		b.color = GREY
		var y := 2.3
		var k := 0
		var za := -hz - 1.6
		var zb := -hz + 1.6
		while y < h - 2.5:
			var z0 := za if k % 2 == 0 else zb
			var z1 := zb if k % 2 == 0 else za
			b.part = S_GRATE
			b.beam(Vector3(lx + 1.05, y, z0), Vector3(lx + 1.05, y + 3.0, z1), 0.8, 0.12)
			if lv == 0:
				b.part = S_PAINT
				b.color = YELLOW
				b.beam(Vector3(lx + 1.47, y + 0.95, z0), Vector3(lx + 1.47, y + 3.95, z1), 0.04, 0.04)
				b.color = GREY
			y += 3.0
			k += 1
	if lv == 0:
		b.color = GREY
		b.part = S_LAMP
		for sz: float in [-1.0, 1.0]:
			b.box(Vector3(-0.3, h - 0.65, sz * (hz - 0.2) - 0.25), Vector3(0.3, h - 0.25, sz * (hz - 0.2) + 0.25))
	return b


# --- Container ship ---------------------------------------------------------------------------

static func ship_mesh() -> ArrayMesh:
	if _cache.has("ship"):
		return _cache["ship"]
	var levels: Array = [_ship_level(0), _ship_level(1), _ship_level(2)]
	var mesh := ladder(levels, SHIP_EDGES, steel_material())
	_cache["ship"] = mesh
	return mesh


## Half the beam at station `x`, at the deck (`deck` true) or the waterline: the parallel
## midbody, the bow's entrance (flared, so the deck is fuller than the waterline) and a slight
## run aft to the transom.
static func _ship_half_beam(x: float, deck: bool) -> float:
	var hb := SHIP_BEAM * 0.5
	if x < -45.0:
		var t := clampf((-45.0 - x) / (-45.0 - SHIP_BOW_X), 0.0, 1.0)
		return hb * (sqrt(maxf(1.0 - t * t, 0.0)) if deck else 1.0 - pow(t, 1.35))
	if x > 66.0:
		var t := clampf((x - 66.0) / (SHIP_HALF_L - 66.0), 0.0, 1.0)
		return hb * (1.0 - t * t * (0.1 if deck else 0.22))
	return hb


## The deck's sheer: level amidships, rising to the forecastle.
static func _ship_deck_y(x: float) -> float:
	var t := clampf((-60.0 - x) / (-60.0 - SHIP_BOW_X), 0.0, 1.0)
	return SHIP_DECK_Y + 2.6 * t * t


static func _ship_level(lv: int) -> Buf:
	var b := Buf.new()
	# --- The hull: lofted stations from the stem to the transom, each a section of five points
	# a side (keel, bilge, waterline, boot-top, deck edge), painted by height.
	var stations: Array[float] = []
	var step := 4.0 if lv == 0 else (8.0 if lv == 1 else 16.0)
	var x := SHIP_BOW_X + 0.6
	while x < SHIP_HALF_L:
		stations.append(x)
		x += step if x > -60.0 and x < 60.0 else step * 0.5
	stations.append(SHIP_HALF_L)
	for side: float in [-1.0, 1.0]:
		for i in stations.size() - 1:
			var xa := stations[i]
			var xb := stations[i + 1]
			var pa := _ship_section(xa, side)
			var pb := _ship_section(xb, side)
			for k in pa.size() - 1:
				var ya: float = (pa[k].y + pa[k + 1].y) * 0.5
				b.color = HULL_RED if ya < 0.2 else (BLACK if ya < 1.3 else HULL_NAVY)
				b.part = S_LETTERED if ya >= 1.3 else S_PAINT
				var nrm := (pb[k] - pa[k]).cross(pa[k + 1] - pa[k]).normalized() * side
				if nrm.z * side < 0.0:
					nrm = -nrm
				b.quad(pa[k], pb[k], pb[k + 1], pa[k + 1], nrm)
	# The stem: close the two sides at the bow with a narrow face; the transom aft.
	var bow_l := _ship_section(stations[0], -1.0)
	var bow_r := _ship_section(stations[0], 1.0)
	for k in bow_l.size() - 1:
		b.color = HULL_NAVY if bow_l[k].y > 1.3 else HULL_RED
		b.quad(bow_l[k], bow_r[k], bow_r[k + 1], bow_l[k + 1], Vector3.LEFT)
	var st_l := _ship_section(SHIP_HALF_L, -1.0)
	var st_r := _ship_section(SHIP_HALF_L, 1.0)
	for k in range(1, st_l.size() - 1):
		b.color = HULL_NAVY if st_l[k].y > 1.3 else HULL_RED
		b.quad(st_l[k], st_r[k], st_r[k + 1], st_l[k + 1], Vector3.RIGHT)
	# The deck: strips across the beam at each station, and a white sheer line under its edge.
	b.color = Color(0.36, 0.34, 0.3)
	b.part = S_PAINT
	for i in stations.size() - 1:
		var xa := stations[i]
		var xb := stations[i + 1]
		var la := _ship_section(xa, -1.0)
		var lb := _ship_section(xb, -1.0)
		var ra := _ship_section(xa, 1.0)
		var rb := _ship_section(xb, 1.0)
		b.quad(la[la.size() - 1], lb[lb.size() - 1], rb[rb.size() - 1], ra[ra.size() - 1], Vector3.UP)
	if lv <= 1:
		b.color = Color(0.85, 0.85, 0.82)
		for side: float in [-1.0, 1.0]:
			for i in stations.size() - 1:
				var xa := stations[i]
				var xb := stations[i + 1]
				var ya := _ship_deck_y(xa) - 0.9
				var yb := _ship_deck_y(xb) - 0.9
				var za := side * (_ship_half_beam(xa, true) + 0.02)
				var zb := side * (_ship_half_beam(xb, true) + 0.02)
				b.quad(Vector3(xa, ya, za), Vector3(xb, yb, zb), Vector3(xb, yb + 0.35, zb), Vector3(xa, ya + 0.35, za), Vector3(0.0, 0.0, side))
	# --- Hatch covers under the ten bays of containers, lashing bridges between the bays.
	for i in 10:
		var bx := -70.0 + i * 14.0
		b.color = Color(0.3, 0.32, 0.33)
		b.part = S_PAINT
		b.box(Vector3(bx - 6.4, SHIP_DECK_Y, -13.2), Vector3(bx + 6.4, SHIP_CARGO_Y, 13.2), 1 | 2 | 4 | 16 | 32)
		if lv <= 1 and i < 9:
			b.color = Color(0.55, 0.56, 0.55)
			var lx := bx + 7.0
			for sz: float in [-1.0, 0.0, 1.0]:
				b.box(Vector3(lx - 0.25, SHIP_DECK_Y, sz * 13.0 - 0.25), Vector3(lx + 0.25, SHIP_CARGO_Y + 5.2, sz * 13.0 + 0.25), 1 | 2 | 16 | 32)
			b.part = S_GRATE
			b.box(Vector3(lx - 0.5, SHIP_CARGO_Y + 5.2, -13.4), Vector3(lx + 0.5, SHIP_CARGO_Y + 5.4, 13.4))
			if lv == 0:
				b.part = S_PAINT
				b.color = YELLOW
				for sx: float in [-1.0, 1.0]:
					b.box(Vector3(lx + sx * 0.47 - 0.03, SHIP_CARGO_Y + 6.4, -13.4), Vector3(lx + sx * 0.47 + 0.03, SHIP_CARGO_Y + 6.46, 13.4), 1 | 2 | 4)
	# --- Forecastle: a breakwater across the foredeck, a foremast, mooring winches.
	var fx := -78.0
	b.color = HULL_NAVY
	b.part = S_PAINT
	b.box(Vector3(fx - 0.4, _ship_deck_y(fx), -11.0), Vector3(fx + 0.4, _ship_deck_y(fx) + 3.2, 11.0))
	b.color = Color(0.88, 0.88, 0.85)
	b.box(Vector3(-86.3, _ship_deck_y(-86.0), -0.3), Vector3(-85.7, _ship_deck_y(-86.0) + 11.0, 0.3), 1 | 2 | 16 | 32)
	if lv <= 1:
		b.color = Color(0.2, 0.36, 0.25)
		for wz: float in [-5.0, 5.0]:
			b.box(Vector3(-91.0, _ship_deck_y(-91.0), wz - 1.2), Vector3(-88.5, _ship_deck_y(-91.0) + 1.6, wz + 1.2))
			b.box(Vector3(82.0, SHIP_DECK_Y, wz * 1.6 - 1.2), Vector3(84.5, SHIP_DECK_Y + 1.6, wz * 1.6 + 1.2))
	# --- The accommodation block aft: white, window rows, a bridge deck with wings to the full
	# beam, a mast with radars, the funnel behind in the line's colour, a freefall lifeboat.
	var ax0 := 72.0
	var ax1 := 84.0
	var top := SHIP_DECK_Y + 21.0
	b.color = Color(0.9, 0.9, 0.87)
	b.part = S_WINDOWS
	b.box(Vector3(ax0, SHIP_DECK_Y, -11.0), Vector3(ax1, top, 11.0), 1 | 2 | 16 | 32)
	b.part = S_PAINT
	b.box(Vector3(ax0, top, -11.0), Vector3(ax1, top + 0.3, 11.0), 4)
	b.part = S_WINDOWS
	b.box(Vector3(ax0 - 0.5, top - 3.2, -15.2), Vector3(ax0 + 5.5, top, 15.2), 2 | 8 | 16 | 32)
	b.part = S_PAINT
	b.box(Vector3(ax0 - 0.5, top, -15.2), Vector3(ax0 + 5.5, top + 0.3, 15.2), 4 | 1)
	if lv <= 1:
		b.color = Color(0.9, 0.9, 0.87)
		b.box(Vector3(ax0 + 3.0, top + 0.3, -0.3), Vector3(ax0 + 3.6, top + 7.0, 0.3), 1 | 2 | 16 | 32)
		b.box(Vector3(ax0 + 1.8, top + 5.0, -3.0), Vector3(ax0 + 4.8, top + 5.3, 3.0))
		b.color = GREY
		b.box(Vector3(ax0 + 2.8, top + 5.3, -2.2), Vector3(ax0 + 3.8, top + 5.6, 2.2))
	b.color = Color(0.85, 0.85, 0.82)
	b.box(Vector3(84.5, SHIP_DECK_Y, -3.8), Vector3(89.0, top + 6.0, 3.8), 1 | 2 | 16 | 32)
	b.color = TEAL
	b.box(Vector3(84.45, top + 2.0, -3.85), Vector3(89.05, top + 4.2, 3.85), 1 | 2 | 16 | 32)
	b.color = BLACK
	b.box(Vector3(84.5, top + 6.0, -3.8), Vector3(89.0, top + 6.6, 3.8))
	if lv <= 1:
		b.color = Color(0.95, 0.45, 0.08)
		b.beam(Vector3(90.5, SHIP_DECK_Y + 5.0, 0.0), Vector3(86.5, SHIP_DECK_Y + 7.4, 0.0), 3.0, 2.6)
		b.color = GREY
		b.beam(Vector3(91.0, SHIP_DECK_Y + 4.0, -1.8), Vector3(85.0, SHIP_DECK_Y + 8.0, -1.8), 0.25, 0.4)
		b.beam(Vector3(91.0, SHIP_DECK_Y + 4.0, 1.8), Vector3(85.0, SHIP_DECK_Y + 8.0, 1.8), 0.25, 0.4)
	if lv == 0:
		# Railings along the main deck edges.
		b.color = Color(0.85, 0.85, 0.82)
		b.part = S_PAINT
		for side: float in [-1.0, 1.0]:
			var z := side * (SHIP_BEAM * 0.5 - 0.3)
			b.box(Vector3(-60.0, SHIP_DECK_Y + 1.0, z - 0.03), Vector3(71.5, SHIP_DECK_Y + 1.06, z + 0.03), 4 | 8 | 16 | 32)
			var rx := -60.0
			while rx < 71.5:
				b.box(Vector3(rx - 0.03, SHIP_DECK_Y, z - 0.03), Vector3(rx + 0.03, SHIP_DECK_Y + 1.0, z + 0.03), 1 | 2 | 16 | 32)
				rx += 2.0
		b.part = S_RED_LAMP
		b.color = Color(0.8, 0.1, 0.08)
		b.box(Vector3(-86.3, _ship_deck_y(-86.0) + 11.0, -0.3), Vector3(-85.7, _ship_deck_y(-86.0) + 11.5, 0.3))
	return b


## One side's hull section at station x, keel to deck edge (ship frame).
static func _ship_section(x: float, side: float) -> Array[Vector3]:
	var wl := _ship_half_beam(x, false)
	var dk := _ship_half_beam(x, true)
	var deck := _ship_deck_y(x)
	var bow := clampf((-45.0 - x) / (-45.0 - SHIP_BOW_X), 0.0, 1.0)
	var bilge := wl * lerpf(0.86, 0.3, bow)
	return [Vector3(x, SHIP_KEEL_Y, side * bilge * 0.7), Vector3(x, SHIP_KEEL_Y + 2.2, side * lerpf(wl * 0.98, wl * 0.55, bow)),
		Vector3(x, 0.15, side * wl), Vector3(x, 1.3, side * lerpf(wl, dk, 0.2)), Vector3(x, deck, side * dk)]


# --- Quay furniture ---------------------------------------------------------------------------

## A cast mooring bollard: a squat post with a flared head, on a base plate.
static func bollard_mesh() -> ArrayMesh:
	if _cache.has("bollard"):
		return _cache["bollard"]
	var b := Buf.new()
	b.color = Color(0.1, 0.1, 0.1)
	b.part = S_PAINT
	b.box(Vector3(-0.42, 0.0, -0.42), Vector3(0.42, 0.06, 0.42), 1 | 2 | 4 | 16 | 32)
	b.cyl(Vector3(0.0, 0.06, 0.0), Vector3(0.0, 0.62, 0.0), 0.24, 10, false, 0.2)
	b.cyl(Vector3(0.0, 0.62, 0.0), Vector3(0.0, 0.78, 0.0), 0.34, 10, true)
	b.color = YELLOW
	b.cyl(Vector3(0.0, 0.78, 0.0), Vector3(0.0, 0.8, 0.0), 0.3, 10, true)
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, b.arrays())
	mesh.surface_set_material(0, steel_material())
	_cache["bollard"] = mesh
	return mesh


## A yard high mast: a tapered pole on a plinth, a railed platform and a ring of floodlights
## (lit by port_steel.gdshader after dark) 34 m up, the terminal's night skyline.
const MAST_H := 34.0


static func mast_mesh() -> ArrayMesh:
	if _cache.has("mast"):
		return _cache["mast"]
	var b := Buf.new()
	b.color = Color(0.6, 0.62, 0.6)
	b.part = S_PAINT
	b.box(Vector3(-0.8, 0.0, -0.8), Vector3(0.8, 0.9, 0.8), 1 | 2 | 4 | 16 | 32)
	b.cyl(Vector3(0.0, 0.9, 0.0), Vector3(0.0, MAST_H, 0.0), 0.42, 8, false, 0.2)
	b.color = GREY
	b.box(Vector3(-1.9, MAST_H - 0.3, -1.9), Vector3(1.9, MAST_H, 1.9))
	b.color = YELLOW
	for s: float in [-1.0, 1.0]:
		b.box(Vector3(-1.9, MAST_H, s * 1.9 - 0.03), Vector3(1.9, MAST_H + 1.0, s * 1.9 + 0.03), 16 | 32 | 4)
		b.box(Vector3(s * 1.9 - 0.03, MAST_H, -1.9), Vector3(s * 1.9 + 0.03, MAST_H + 1.0, 1.9), 1 | 2 | 4)
	b.color = GREY
	b.part = S_LAMP
	for i in 8:
		var a := TAU * float(i) / 8.0
		var c := Vector3(cos(a) * 1.5, MAST_H - 0.75, sin(a) * 1.5)
		b.box(c - Vector3(0.35, 0.35, 0.35), c + Vector3(0.35, 0.35, 0.35))
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, b.arrays())
	mesh.surface_set_material(0, steel_material())
	_cache["mast"] = mesh
	return mesh


## A cell fender: a black rubber cylinder standing against the quay face, its steel panel
## facing the water (+Z).
static func fender_mesh() -> ArrayMesh:
	if _cache.has("fender"):
		return _cache["fender"]
	var b := Buf.new()
	b.color = BLACK
	b.part = S_RUBBER
	b.cyl(Vector3(0.0, -1.2, 0.0), Vector3(0.0, 0.3, 0.0), 0.55, 10, true)
	b.color = Color(0.2, 0.2, 0.2)
	b.part = S_PAINT
	b.box(Vector3(-1.1, -1.4, 0.5), Vector3(1.1, 0.35, 0.7))
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, b.arrays())
	mesh.surface_set_material(0, steel_material())
	_cache["fender"] = mesh
	return mesh


## Collision boxes for a crane, as [size, transform in the crane frame]: legs, sill and portal
## beams, the girders and boom (you can land on them), the machinery house and the bogies.
static func sts_shapes(raised: bool) -> Array:
	var out: Array = []
	var gz := STS_GAUGE * 0.5
	var lx := STS_LEG_X
	var py := STS_PORTAL_Y
	var gt := py + STS_GIRDER_D
	var gx := STS_GIRDER_X
	var hinge_z := gz + 1.5
	var back := -gz - STS_BACKREACH
	for sx: float in [-1.0, 1.0]:
		for sz: float in [-1.0, 1.0]:
			out.append([Vector3(2.1, py - 2.4, 2.1), Transform3D(Basis(), Vector3(sx * lx, 2.4 + (py - 2.4) * 0.5, sz * gz))])
			out.append([Vector3(7.6, 2.4, 1.6), Transform3D(Basis(), Vector3(sx * lx, 1.2, sz * gz))])
		out.append([Vector3(1.5, 1.8, STS_GAUGE - 2.2), Transform3D(Basis(), Vector3(sx * lx, 14.0, 0.0))])
		out.append([Vector3(1.5, STS_GIRDER_D, hinge_z - back), Transform3D(Basis(), Vector3(sx * gx, py + STS_GIRDER_D * 0.5, (hinge_z + back) * 0.5))])
		var boom_len := STS_OUTREACH - 1.5
		out.append([Vector3(1.4, 2.8, boom_len), sts_boom_xf(raised) * Transform3D(Basis(), Vector3(sx * gx, gt - 1.4, hinge_z + boom_len * 0.5))])
	for sz: float in [-1.0, 1.0]:
		out.append([Vector3(2.0 * lx + 2.0, 3.0, 2.2), Transform3D(Basis(), Vector3(0.0, py - 1.5, sz * gz))])
	out.append([Vector3(12.0, 6.7, 19.4), Transform3D(Basis(), Vector3(0.0, gt + 3.35, back + 10.3))])
	return out


## The same crane as a handful of boxes for the far city (Skyline), as [size, transform in the
## crane frame, colour]: legs, portal beams, girders, the boom, the house and the A-frame.
static func sts_far_boxes(raised: bool) -> Array:
	var out: Array = []
	var gz := STS_GAUGE * 0.5
	var lx := STS_LEG_X
	var py := STS_PORTAL_Y
	var gt := py + STS_GIRDER_D
	var hinge_z := gz + 1.5
	var back := -gz - STS_BACKREACH
	for sx: float in [-1.0, 1.0]:
		for sz: float in [-1.0, 1.0]:
			out.append([Vector3(2.0, py, 2.0), Transform3D(Basis(), Vector3(sx * lx, py * 0.5, sz * gz)), TEAL])
	for sz: float in [-1.0, 1.0]:
		out.append([Vector3(2.0 * lx + 2.0, 3.0, 2.2), Transform3D(Basis(), Vector3(0.0, py - 1.5, sz * gz)), TEAL])
	out.append([Vector3(9.3, STS_GIRDER_D, hinge_z - back), Transform3D(Basis(), Vector3(0.0, py + STS_GIRDER_D * 0.5, (hinge_z + back) * 0.5)), WHITE])
	var boom_len := STS_OUTREACH - 1.5
	out.append([Vector3(9.0, 2.8, boom_len), sts_boom_xf(raised) * Transform3D(Basis(), Vector3(0.0, gt - 1.4, hinge_z + boom_len * 0.5)), WHITE])
	out.append([Vector3(12.0, 6.7, 19.4), Transform3D(Basis(), Vector3(0.0, gt + 3.35, back + 10.3)), WHITE])
	for sx: float in [-1.0, 1.0]:
		var apex := Vector3(sx * 6.4, STS_APEX_Y, STS_APEX_Z)
		for sz: float in [-1.0, 1.0]:
			var foot := Vector3(sx * lx, py, sz * gz)
			out.append([Vector3(1.4, 1.4, foot.distance_to(apex)), _box_between(foot, apex), WHITE])
	return out


## The transform that stretches a unit box from `a` to `b` (its length in z).
static func _box_between(a: Vector3, b: Vector3) -> Transform3D:
	var fwd := (b - a).normalized()
	var up := Vector3.UP if absf(fwd.y) < 0.95 else Vector3.RIGHT
	var x := up.cross(fwd).normalized()
	var y := fwd.cross(x).normalized()
	return Transform3D(Basis(x, y, fwd), (a + b) * 0.5)


## Collision for a yard gantry (gantry frame): legs, sills, girders and the trolley.
static func rtg_shapes() -> Array:
	var out: Array = []
	var hz := RTG_SPAN * 0.5
	for sz: float in [-1.0, 1.0]:
		out.append([Vector3(2.0 * RTG_LEG_X + 2.4, 2.3, 1.1), Transform3D(Basis(), Vector3(0.0, 1.15, sz * hz))])
		for sx: float in [-1.0, 1.0]:
			out.append([Vector3(0.9, RTG_H - 2.3, 0.9), Transform3D(Basis(), Vector3(sx * (RTG_LEG_X - 0.15), 2.3 + (RTG_H - 2.3) * 0.5, sz * (hz - 0.1)))])
	for sx: float in [-1.0, 1.0]:
		out.append([Vector3(0.9, 1.5, RTG_SPAN + 2.2), Transform3D(Basis(), Vector3(sx * (RTG_LEG_X - 0.3), RTG_H + 0.75, 0.0))])
	out.append([Vector3(2.0 * RTG_LEG_X + 0.6, 1.9, 4.6), Transform3D(Basis(), Vector3(0.0, RTG_H + 1.5 + 1.0, 0.0))])
	return out
