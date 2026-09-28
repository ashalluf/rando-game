class_name ShopfrontKit
extends RefCounted
## Real geometry for the street level and the curtain walls, built in code: storefront frames
## round every display window, doors, piers, sign-board trims, awnings in four shapes, projecting
## blade signs, and the mullion and transom caps of a glass curtain wall. They are facade-kit
## pieces (tools/facade_kit.py is the Blender half of the kit): they wear PropFactory.kit_material()
## and go into the building's one MultiMeshBatch (Building._kit), a few draws a building, off on
## the web with the rest of the kit (Building.kit_enabled).
##
## How a piece fits every opening from one mesh is shaders/facade_kit.gdshaderinc: the three-slice
## round a 1 x 1 m opening (INSTANCE_CUSTOM.b / .a are how much bigger the real one is each side),
## and, for these pieces, per-vertex ANCHORS (UV2.y - 1: bits 0-1 x, 2-3 y; 0 the slice, 1 the low
## edge, 2 the high edge, 3 the centre) and two optional layouts in one mesh (bit 4 kept where
## INSTANCE_CUSTOM.g > 0.5, bit 5 where it is not, bit 6 where INSTANCE_CUSTOM.r > 0.5, bit 7
## where it is not). So a door's meeting stiles stay in the middle of any width, its handles at
## hand height, the transom at door-head height; the jambs keep their 65 mm on a 1.2 m bay and a
## 2.7 m one.
##
## Pieces are modelled in the kit's frame: x along the wall (Building's `a`), y up, z out of the
## wall, metres; nothing reaches behind z = 0 (the wall face - the glass is drawn 12 cm behind it
## by shaders/building.gdshader, and anything behind the face is hidden by it). UV is (x, 1 + y),
## the kit's front-face convention, so the shader slices it with the vertex; UV2.x is occlusion.
## Vertex colour multiplies the instance colour (black brackets on a coloured sign) and its alpha
## is the lightbox mask (`night_glow`).
##
## Where the storefront pieces go is worked out exactly as the shader draws the shop it stands on:
## the shop runs (Building._shop_spans()), the door bay and whether it is a recessed entry, the
## centre mullion, the door layout and the frame colour all come from Building.shop_byte() with
## the shader's own salts (listed on SALT_*), so the painted frames that take over past
## `shop_paint_near` metres are the same frames.

## Anchor codes, one per axis (see the header).
const S := 0
const LO := 1
const HI := 2
const MID := 3
## Optional-layout bits.
const OPT_G := 16
const OPT_NOT_G := 32
const OPT_R := 64
const OPT_NOT_R := 128

## shop_hash salts shared with shaders/building.gdshader (Building.shop_hash lists them all).
const SALT_FRAME := 14
const SALT_DOOR := 15
const SALT_RECESS := 16
const SALT_MULLION := 17
const SALT_DOOR_SINGLE := 18
## Building's alone (the shader never needs them): a blade sign, and its board's paint.
const SALT_BLADE := 30
const SALT_BLADE_COLOR := 31

## The storefront the shader draws, in metres above the building's base on a 4.5 m storefront
## (Building.storefront_height): display glass from 0.15 of it, a door's from the pavement, both
## to 0.74; the transom bar at a fixed door-head height; the sign board 0.76 - 0.93.
const GLASS_LOW := 0.15
const GLASS_TOP := 0.74
const FASCIA_LOW := 0.76
const FASCIA_TOP := 0.93
const TRANSOM_LOW := 2.38
const TRANSOM_HIGH := 2.50
## Half the width of the glass in a bay, as a fraction of the bay (the shader's 0.44).
const GLASS_HALF := 0.44
## Frame sections (metres): a jamb's face, how far it laps over the glass edge, its depth.
const JAMB := 0.065
const LAP := 0.012
const FRAME_DEPTH := 0.07
## A door leaf: stile, rails, the kick plate, where a single leaf ends.
const STILE := 0.10
const RAIL := 0.10
const KICK := 0.28
const LEAF_SINGLE := 0.95
const MEETING := 0.06
## Share of door bays that are a deep recessed entry (the shader traces it; no door piece).
const RECESS_BYTE := 72
## Share of shops (of 256) with a centre mullion in their display bays, with a single door and a
## sidelight rather than a pair (where the bay is wide enough for one).
const MULLION_BYTE := 128
const SINGLE_BYTE := 120
const SINGLE_MIN_WIDTH := 1.45
## Storefront frame finishes, the shader's shop_frame_color(): black anodised, dark bronze, clear
## anodised, white, champagne. Weighted by the byte thresholds in frame_index().
const FRAME_COLORS := [Color(0.07, 0.07, 0.075), Color(0.20, 0.15, 0.11), Color(0.58, 0.59, 0.60),
	Color(0.86, 0.86, 0.84), Color(0.62, 0.55, 0.43)]
## Blade sign boards: deep paint colours that read against stone and glass.
const BLADE_COLORS := [Color(0.55, 0.08, 0.07), Color(0.07, 0.17, 0.36), Color(0.08, 0.28, 0.17),
	Color(0.10, 0.10, 0.11), Color(0.62, 0.44, 0.10), Color(0.84, 0.82, 0.76), Color(0.36, 0.10, 0.24),
	Color(0.08, 0.34, 0.40)]
## Curtain-wall caps: where the painted transom lines are on a curtain wall (fractions of the
## floor, building.gdshader's `curtain_spandrel`), a cap's face width and depth.
const CURTAIN_SILL := 0.08
const CURTAIN_HEAD := 0.93
const CAP_WIDTH := 0.075
## Floors per vertical cap instance: the instance's origin is what the distance cull measures.
const CAP_BAND_ROWS := 4
## INSTANCE_CUSTOM for a piece that is scaled, not sliced. Not MultiMeshBatch.add()'s default
## Color.BLACK: its alpha of 1 is a slice of a metre each way, which stood every cap up a whole
## band above the roof.
const NO_SLICE := Color(0.0, 0.0, 0.0, 0.0)

static var _cache: Dictionary = {}
## Off: Building lays none of these pieces (the painted storefront and frames carry it, as on the
## web) and hangs only the Blender kit's awning - the A/B of this kit (still_shot.gd
## STOREFRONT_KIT=0). Set before the buildings generate.
static var enabled: bool = true


## Which of FRAME_COLORS a shop's frames are (the shader's thresholds).
static func frame_index(key: int) -> int:
	var b := Building.shop_byte(key, SALT_FRAME)
	return 0 if b < 77 else (1 if b < 141 else (2 if b < 205 else (3 if b < 230 else 4)))


## Which bay of a shop of `span` bays is its door (the shader's door_bay).
static func door_index(key: int, span: int) -> int:
	return Building.shop_byte(key, SALT_DOOR) % maxi(span, 1)


static func recessed(key: int) -> bool:
	return Building.shop_byte(key, SALT_RECESS) < RECESS_BYTE


static func centre_mullion(key: int) -> bool:
	return Building.shop_byte(key, SALT_MULLION) < MULLION_BYTE


static func single_door(key: int, glass_w: float) -> bool:
	return glass_w >= SINGLE_MIN_WIDTH and Building.shop_byte(key, SALT_DOOR_SINGLE) < SINGLE_BYTE


## Where shaders/facade_kit.gdshaderinc puts an authored vertex of one of these pieces (its UV2.y
## code) on an instance whose INSTANCE_CUSTOM is (r, g, ex, ey): the shader's vertex() in
## GDScript, for the tests. A vertex of the layout the instance does not show collapses to 0.
static func place(v: Vector3, code: int, ex: float, ey: float, g: float, r: float = 0.0) -> Vector3:
	if (code & OPT_G and g < 0.5) or (code & OPT_NOT_G and g >= 0.5) or (code & OPT_R and r < 0.5) or (code & OPT_NOT_R and r >= 0.5):
		return Vector3.ZERO
	return Vector3(_anchor(v.x, ex, code % 4), _anchor(v.y, ey, (code / 4) % 4), v.z)


static func _anchor(x: float, extra: float, mode: int) -> float:
	match mode:
		LO:
			return x - extra
		HI:
			return x + extra
		MID:
			return x
	return x * (1.0 + 2.0 * extra) if absf(x) < 0.5 else x + signf(x) * extra


# --- Mesh building ---------------------------------------------------------------------------

## One surface growing: positions as authored (the anchors decide where they end up), flat
## normals, UV (x, 1 + y), UV2 (occlusion, 1 + code), vertex colour.
class Acc:
	var verts := PackedVector3Array()
	var norms := PackedVector3Array()
	var uvs := PackedVector2Array()
	var uv2s := PackedVector2Array()
	var cols := PackedColorArray()
	var idx := PackedInt32Array()


## An anchored coordinate: [anchor code, offset]. LO / HI offsets are from that edge of the unit
## opening, MID from its centre; S is the plain slice (the offset is the authored value).
static func _ax(anchor: int, offset: float) -> Vector2:
	return Vector2(float(anchor), offset)


static func _authored(c: Vector2) -> float:
	match int(c.x):
		LO:
			return -0.5 + c.y
		HI:
			return 0.5 + c.y
	return c.y


## A convex polygon (anchored corners [x: Vector2, y: Vector2, z: float]) facing `n`.
static func _poly(acc: Acc, corners: Array, n: Vector3, col: Color, opt: int, ao: PackedFloat32Array = PackedFloat32Array()) -> void:
	var pts: Array[Vector3] = []
	var codes: Array[int] = []
	for c: Array in corners:
		var cx: Vector2 = c[0]
		var cy: Vector2 = c[1]
		pts.append(Vector3(_authored(cx), _authored(cy), float(c[2])))
		codes.append(int(cx.x) + 4 * int(cy.x) + opt)
	var base := acc.verts.size()
	for i in pts.size():
		acc.verts.append(pts[i])
		acc.norms.append(n)
		acc.uvs.append(Vector2(pts[i].x, 1.0 + pts[i].y))
		acc.uv2s.append(Vector2(ao[i] if i < ao.size() else 0.0, 1.0 + float(codes[i])))
		acc.cols.append(col)
	for i in range(1, pts.size() - 1):
		var a := pts[0]
		var b := pts[i]
		var c := pts[i + 1]
		# Godot's front faces wind clockwise seen from the front: flip to face `n` whatever the
		# order the corners came in.
		if (b - a).cross(c - a).dot(n) > 0.0:
			acc.idx.append_array([base, base + i + 1, base + i])
		else:
			acc.idx.append_array([base, base + i, base + i + 1])


## A bar standing out of the wall: x0..x1, y0..y1 anchored, z0..z1, its front edges chamfered by
## `bevel`. Back face left out (it is against the wall or another member). `sides` masks which of
## -x, +x, -y, +y are built (1, 2, 4, 8).
static func _bar(acc: Acc, x0: Vector2, x1: Vector2, y0: Vector2, y1: Vector2, z0: float, z1: float,
		bevel: float, col: Color, opt: int = 0, sides: int = 15) -> void:
	var b := minf(bevel, (z1 - z0) * 0.45)
	var zm := z1 - b
	var ix0 := Vector2(x0.x, x0.y + b)
	var ix1 := Vector2(x1.x, x1.y - b)
	var iy0 := Vector2(y0.x, y0.y + b)
	var iy1 := Vector2(y1.x, y1.y - b)
	var back := PackedFloat32Array([0.45, 0.45, 0.0, 0.0])
	# Front.
	_poly(acc, [[ix0, iy0, z1], [ix1, iy0, z1], [ix1, iy1, z1], [ix0, iy1, z1]], Vector3(0, 0, 1), col, opt)
	var d := 0.7071
	# A bar with no bevel has no chamfer faces (they would be triangles of no area).
	var cham := b > 1e-4
	if sides & 1:
		_poly(acc, [[x0, y0, z0], [x0, y1, z0], [x0, y1, zm], [x0, y0, zm]], Vector3(-1, 0, 0), col, opt, back)
		if cham:
			_poly(acc, [[x0, y0, zm], [x0, y1, zm], [ix0, iy1, z1], [ix0, iy0, z1]], Vector3(-d, 0, d), col, opt)
	if sides & 2:
		_poly(acc, [[x1, y0, z0], [x1, y1, z0], [x1, y1, zm], [x1, y0, zm]], Vector3(1, 0, 0), col, opt, back)
		if cham:
			_poly(acc, [[x1, y0, zm], [x1, y1, zm], [ix1, iy1, z1], [ix1, iy0, z1]], Vector3(d, 0, d), col, opt)
	if sides & 4:
		_poly(acc, [[x0, y0, z0], [x1, y0, z0], [x1, y0, zm], [x0, y0, zm]], Vector3(0, -1, 0), col, opt, back)
		if cham:
			_poly(acc, [[x0, y0, zm], [x1, y0, zm], [ix1, iy0, z1], [ix0, iy0, z1]], Vector3(0, -d, d), col, opt)
	if sides & 8:
		_poly(acc, [[x0, y1, z0], [x1, y1, z0], [x1, y1, zm], [x0, y1, zm]], Vector3(0, 1, 0), col, opt, back)
		if cham:
			_poly(acc, [[x0, y1, zm], [x1, y1, zm], [ix1, iy1, z1], [ix0, iy1, z1]], Vector3(0, d, d), col, opt)


## A square rod between two anchored points [x, y, z] (x and y anchored, z plain), `r` its half
## thickness: four faces, no caps.
static func _rod(acc: Acc, p: Array, q: Array, r: float, col: Color, opt: int = 0) -> void:
	var pa := Vector3(_authored(p[0]), _authored(p[1]), float(p[2]))
	var qa := Vector3(_authored(q[0]), _authored(q[1]), float(q[2]))
	var dir := (qa - pa).normalized()
	var side := dir.cross(Vector3.UP if absf(dir.y) < 0.9 else Vector3.RIGHT).normalized()
	var up := side.cross(dir).normalized()
	var offs := [side * r + up * r, -side * r + up * r, -side * r - up * r, side * r - up * r]
	for k in 4:
		var o0: Vector3 = offs[k]
		var o1: Vector3 = offs[(k + 1) % 4]
		var nrm := (o0 + o1).normalized()
		_poly(acc, [
			[Vector2(p[0].x, p[0].y + o0.x), Vector2(p[1].x, p[1].y + o0.y), float(p[2]) + o0.z],
			[Vector2(q[0].x, q[0].y + o0.x), Vector2(q[1].x, q[1].y + o0.y), float(q[2]) + o0.z],
			[Vector2(q[0].x, q[0].y + o1.x), Vector2(q[1].x, q[1].y + o1.y), float(q[2]) + o1.z],
			[Vector2(p[0].x, p[0].y + o1.x), Vector2(p[1].x, p[1].y + o1.y), float(p[2]) + o1.z],
		], nrm, col, opt)


## The accumulated surfaces as one mesh, a kit material per surface. `grow` is how far past its
## authored box (in x and y) the slice may stretch the piece: the culling box has to hold it.
static func _commit(surfaces: Dictionary, grow: Vector2) -> ArrayMesh:
	var mesh := ArrayMesh.new()
	for mat_name: String in surfaces:
		var acc: Acc = surfaces[mat_name]
		if acc.idx.is_empty():
			continue
		var arrays := []
		arrays.resize(Mesh.ARRAY_MAX)
		arrays[Mesh.ARRAY_VERTEX] = acc.verts
		arrays[Mesh.ARRAY_NORMAL] = acc.norms
		arrays[Mesh.ARRAY_TEX_UV] = acc.uvs
		arrays[Mesh.ARRAY_TEX_UV2] = acc.uv2s
		arrays[Mesh.ARRAY_COLOR] = acc.cols
		arrays[Mesh.ARRAY_INDEX] = acc.idx
		mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
		mesh.surface_set_material(mesh.get_surface_count() - 1, PropFactory.kit_material(mat_name))
	if grow != Vector2.ZERO:
		var box := mesh.get_aabb()
		mesh.custom_aabb = AABB(box.position - Vector3(grow.x, grow.y, 0.0), box.size + Vector3(grow.x, grow.y, 0.0) * 2.0)
	return mesh


## A piece by name (cached): "bay", "door", "pier", "fascia", "awning_dome", "awning_flat",
## "awning_roller", "blade", "cap_v", "cap_h". `sf` is the storefront height it is built for.
static func mesh(piece: String, sf: float = 4.5) -> Mesh:
	var key := "%s_%.2f" % [piece, sf]
	if _cache.has(key):
		return _cache[key]
	var surfaces := {}
	match piece:
		"bay":
			_build_bay(surfaces, sf)
		"door":
			_build_door(surfaces, sf)
		"pier":
			_build_pier(surfaces, "kit_stone")
		"pier_metal":
			_build_pier(surfaces, "kit_alu")
		"fascia":
			_build_fascia(surfaces)
		"awning_dome":
			_build_awning_dome(surfaces)
		"awning_flat":
			_build_awning_flat(surfaces)
		"awning_roller":
			_build_awning_roller(surfaces)
		"blade":
			_build_blade(surfaces)
		"cap_v":
			_build_cap(surfaces, true)
		"cap_h":
			_build_cap(surfaces, false)
	# Room for the biggest opening each is stretched over: a 2.7 m bay 3.3 m tall, a 12 m shop's
	# sign board, a 4.4 m pier, a 2.5 m blade sign, a 12 m awning. The caps are scaled, not sliced.
	var grow := {"bay": Vector2(1.2, 1.4), "door": Vector2(1.2, 1.4), "pier": Vector2(0.0, 2.0),
		"pier_metal": Vector2(0.0, 2.0), "fascia": Vector2(6.0, 0.2), "blade": Vector2(0.0, 1.0),
		"awning_dome": Vector2(6.0, 0.0), "awning_flat": Vector2(6.0, 0.0), "awning_roller": Vector2(6.0, 0.0)}
	var m := _commit(surfaces, grow.get(piece, Vector2.ZERO))
	_cache[key] = m
	return m


## Every piece and its materials, for the loading screen to warm.
const PIECES := ["bay", "door", "pier", "pier_metal", "fascia", "awning_dome", "awning_flat", "awning_roller", "blade", "cap_v", "cap_h"]


static func warm() -> Array:
	var out: Array = []
	for p: String in PIECES:
		out.append(mesh(p))
	return out


static func _acc(surfaces: Dictionary, mat_name: String) -> Acc:
	if not surfaces.has(mat_name):
		surfaces[mat_name] = Acc.new()
	return surfaces[mat_name]


## A display bay's frame, round the glass: the opening IS the glass. Jambs and head outside it
## (keeping their size), a sloped sill under it, the transom bar at door-head height above the
## pavement (anchored to the bottom edge, which is `GLASS_LOW` of the storefront up), and on
## instances with INSTANCE_CUSTOM.g set a centre mullion. INSTANCE_CUSTOM.r set leaves out the
## sill and transom (the portal round a recessed entry).
static func _build_bay(surfaces: Dictionary, sf: float) -> void:
	var acc := _acc(surfaces, "kit_alu")
	var w := Color.WHITE
	var glass_low := GLASS_LOW * sf
	_frame_sides(acc, 0)
	# Sill: a sloped aluminium sill projecting a little further, at the foot of the glass.
	_bar(acc, _ax(LO, -JAMB - 0.01), _ax(HI, JAMB + 0.01), _ax(LO, -0.045), _ax(LO, LAP), 0.0, 0.10, 0.02, w, OPT_NOT_R)
	# Transom bar and the glazing bead under it.
	var t0 := TRANSOM_LOW - glass_low
	var t1 := TRANSOM_HIGH - glass_low
	_bar(acc, _ax(LO, 0.0), _ax(HI, 0.0), _ax(LO, t0), _ax(LO, t1), 0.0, FRAME_DEPTH - 0.01, 0.012, w, OPT_NOT_R, 12)
	# Centre mullion, sill to head.
	_bar(acc, _ax(MID, -0.03), _ax(MID, 0.03), _ax(LO, LAP), _ax(HI, -LAP), 0.0, FRAME_DEPTH - 0.012, 0.01, w, OPT_G, 3)


## Jambs and head round a unit opening, lapping over its edge by LAP (shared by bay and door).
static func _frame_sides(acc: Acc, opt: int) -> void:
	var w := Color.WHITE
	_bar(acc, _ax(LO, -JAMB), _ax(LO, LAP), _ax(LO, -0.045), _ax(HI, 0.0), 0.0, FRAME_DEPTH, 0.014, w, opt, 11)
	_bar(acc, _ax(HI, -LAP), _ax(HI, JAMB), _ax(LO, -0.045), _ax(HI, 0.0), 0.0, FRAME_DEPTH, 0.014, w, opt, 11)
	_bar(acc, _ax(LO, -JAMB), _ax(HI, JAMB), _ax(HI, -LAP), _ax(HI, 0.06), 0.0, FRAME_DEPTH, 0.014, w, opt)


## A door bay: the opening is the door bay's glass, from the pavement to the head. Frame, the
## transom at door-head height with the transom light above it, and below it either a pair of
## glazed leaves with pull handles (INSTANCE_CUSTOM.g unset) or one leaf with a push bar beside a
## sidelight (set). The leaf members are anchored to the edges and the centre, the rails and
## handles to the threshold, so every width keeps real stiles and a door at real height.
static func _build_door(surfaces: Dictionary, sf: float) -> void:
	var acc := _acc(surfaces, "kit_alu")
	var w := Color.WHITE
	var dark := Color(0.35, 0.35, 0.36)
	_frame_sides(acc, 0)
	var t0 := TRANSOM_LOW
	var t1 := TRANSOM_HIGH
	var leaf_z := FRAME_DEPTH - 0.022
	# Threshold plate.
	_bar(acc, _ax(LO, -JAMB), _ax(HI, JAMB), _ax(LO, 0.0), _ax(LO, 0.022), 0.0, 0.09, 0.006, dark, 0, 12)
	# Transom bar.
	_bar(acc, _ax(LO, 0.0), _ax(HI, 0.0), _ax(LO, t0), _ax(LO, t1), 0.0, FRAME_DEPTH - 0.008, 0.012, w, 0, 12)
	# --- A pair of leaves (INSTANCE_CUSTOM.g < 0.5) ---
	var p := OPT_NOT_G
	for side: int in [LO, HI]:
		var sgn := -1.0 if side == LO else 1.0
		# Outer stile, against the jamb.
		var o0 := _ax(side, 0.0 if side == LO else -STILE)
		var o1 := _ax(side, STILE if side == LO else 0.0)
		_bar(acc, o0, o1, _ax(LO, 0.022), _ax(LO, t0), 0.0, leaf_z, 0.01, w, p)
		# Meeting stile at the centre, a 6 mm gap between the pair.
		var m0 := _ax(MID, -MEETING if side == LO else 0.003)
		var m1 := _ax(MID, -0.003 if side == LO else MEETING)
		_bar(acc, m0, m1, _ax(LO, 0.022), _ax(LO, t0), 0.0, leaf_z, 0.01, w, p)
		# Top rail and kick rail between them.
		var a0 := _ax(side, STILE) if side == LO else _ax(MID, MEETING)
		var a1 := _ax(MID, -MEETING) if side == LO else _ax(side, -STILE)
		_bar(acc, a0, a1, _ax(LO, t0 - RAIL), _ax(LO, t0), 0.0, leaf_z - 0.004, 0.008, w, p, 12)
		_bar(acc, a0, a1, _ax(LO, 0.022), _ax(LO, KICK), 0.0, leaf_z - 0.004, 0.008, w, p, 12)
		# Pull handle: a round-ish bar on two stand-offs, 12 cm off the meeting stiles.
		var hx := 0.12 * sgn
		var h0 := 0.78
		var h1 := 1.38
		_bar(acc, _ax(MID, hx - 0.014), _ax(MID, hx + 0.014), _ax(LO, h0), _ax(LO, h1), leaf_z + 0.045, leaf_z + 0.072, 0.012, dark, p)
		for hy: float in [h0 + 0.06, h1 - 0.06]:
			_bar(acc, _ax(MID, hx - 0.009), _ax(MID, hx + 0.009), _ax(LO, hy - 0.009), _ax(LO, hy + 0.009), leaf_z - 0.004, leaf_z + 0.046, 0.0, dark, p, 3)
	# --- One leaf and a sidelight (INSTANCE_CUSTOM.g > 0.5): the leaf from the low edge ---
	var q := OPT_G
	var lw := LEAF_SINGLE
	_bar(acc, _ax(LO, 0.0), _ax(LO, STILE), _ax(LO, 0.022), _ax(LO, t0), 0.0, leaf_z, 0.01, w, q)
	_bar(acc, _ax(LO, lw - STILE), _ax(LO, lw), _ax(LO, 0.022), _ax(LO, t0), 0.0, leaf_z, 0.01, w, q)
	_bar(acc, _ax(LO, STILE), _ax(LO, lw - STILE), _ax(LO, t0 - RAIL), _ax(LO, t0), 0.0, leaf_z - 0.004, 0.008, w, q, 12)
	_bar(acc, _ax(LO, STILE), _ax(LO, lw - STILE), _ax(LO, 0.022), _ax(LO, KICK), 0.0, leaf_z - 0.004, 0.008, w, q, 12)
	# Fixed mullion between the leaf and the sidelight, full height to the transom.
	_bar(acc, _ax(LO, lw), _ax(LO, lw + MEETING), _ax(LO, 0.0), _ax(LO, t0), 0.0, FRAME_DEPTH - 0.006, 0.012, w, q, 3)
	# The sidelight's kick rail.
	_bar(acc, _ax(LO, lw + MEETING), _ax(HI, 0.0), _ax(LO, 0.022), _ax(LO, KICK), 0.0, leaf_z - 0.004, 0.008, w, q, 12)
	# Push bar across the leaf on two stand-offs.
	_bar(acc, _ax(LO, STILE + 0.04), _ax(LO, lw - STILE - 0.04), _ax(LO, 0.97), _ax(LO, 1.03), leaf_z + 0.04, leaf_z + 0.07, 0.012, dark, q, 12)
	for sx: float in [STILE + 0.08, lw - STILE - 0.08]:
		_bar(acc, _ax(LO, sx - 0.012), _ax(LO, sx + 0.012), _ax(LO, 0.988), _ax(LO, 1.012), leaf_z - 0.004, leaf_z + 0.041, 0.0, dark, q, 12)


## Pier cladding over the box pier between two shops (0.5 x 0.5 m, 0.39 m proud of the wall):
## a plinth and a capital that keep their size, a shaft with chamfered arrises that stretches.
## Built round the pier's full height as the unit opening (INSTANCE_CUSTOM.a from it).
static func _build_pier(surfaces: Dictionary, mat_name: String) -> void:
	var acc := _acc(surfaces, mat_name)
	var w := Color.WHITE
	var ao_col := Color(0.9, 0.9, 0.9)
	# Plinth, with a weathered top.
	_bar(acc, _ax(MID, -0.305), _ax(MID, 0.305), _ax(LO, 0.0), _ax(LO, 0.42), 0.0, 0.455, 0.035, ao_col, 0)
	_bar(acc, _ax(MID, -0.29), _ax(MID, 0.29), _ax(LO, 0.42), _ax(LO, 0.47), 0.0, 0.44, 0.02, w, 0, 11)
	# Shaft.
	_bar(acc, _ax(MID, -0.268), _ax(MID, 0.268), _ax(LO, 0.47), _ax(HI, -0.34), 0.0, 0.415, 0.03, w, 0, 3)
	# Capital: a neck, a fillet and a projecting abacus.
	_bar(acc, _ax(MID, -0.28), _ax(MID, 0.28), _ax(HI, -0.34), _ax(HI, -0.24), 0.0, 0.425, 0.012, w, 0, 7)
	_bar(acc, _ax(MID, -0.30), _ax(MID, 0.30), _ax(HI, -0.24), _ax(HI, -0.17), 0.0, 0.45, 0.02, w, 0)
	_bar(acc, _ax(MID, -0.325), _ax(MID, 0.325), _ax(HI, -0.17), _ax(HI, 0.0), 0.0, 0.48, 0.03, w, 0)


## A trim round a shop's sign board: the unit opening is the board (the shader's fascia), the
## trim outside it, with a drip flashing along the top.
static func _build_fascia(surfaces: Dictionary) -> void:
	var acc := _acc(surfaces, "kit_alu")
	var w := Color.WHITE
	var t := 0.045
	_bar(acc, _ax(LO, -t), _ax(HI, t), _ax(LO, -t), _ax(LO, 0.0), 0.0, 0.055, 0.012, w)
	_bar(acc, _ax(LO, -t), _ax(LO, 0.0), _ax(LO, 0.0), _ax(HI, 0.0), 0.0, 0.055, 0.012, w, 0, 3)
	_bar(acc, _ax(HI, 0.0), _ax(HI, t), _ax(LO, 0.0), _ax(HI, 0.0), 0.0, 0.055, 0.012, w, 0, 3)
	_bar(acc, _ax(LO, -t), _ax(HI, t), _ax(HI, 0.0), _ax(HI, t), 0.0, 0.055, 0.012, w, 0, 12)
	# Drip flashing on top: thin and deep.
	_bar(acc, _ax(LO, -t - 0.01), _ax(HI, t + 0.01), _ax(HI, t), _ax(HI, t + 0.018), 0.0, 0.10, 0.004, w)


## A traditional dome awning: a quarter-ellipse barrel of canvas (0.95 m deep, 0.85 m tall,
## hanging from y = 0) with flat cheeks at the two sliced edges, a valance, and an iron frame.
## x from the low to the high edge of the unit opening (the awning's width).
static func _build_awning_dome(surfaces: Dictionary) -> void:
	var cloth := _acc(surfaces, "kit_fabric")
	var iron := _acc(surfaces, "kit_iron")
	var w := Color.WHITE
	var depth := 0.95
	var high := 0.85
	var seg := 9
	var prof: Array[Vector2] = []   # (z, y)
	for i in seg + 1:
		var t := float(i) / float(seg) * PI * 0.5
		prof.append(Vector2(depth * sin(t), -high * (1.0 - cos(t))))
	for i in seg:
		var a := prof[i]
		var b := prof[i + 1]
		var n := Vector3(0.0, b.x - a.x, -(b.y - a.y)).normalized()
		if n.z < 0.0:
			n = -n
		_poly(cloth, [[_ax(LO, 0.0), _ax(S, a.y), a.x], [_ax(HI, 0.0), _ax(S, a.y), a.x],
			[_ax(HI, 0.0), _ax(S, b.y), b.x], [_ax(LO, 0.0), _ax(S, b.y), b.x]], n, w, 0)
	# Valance, straight.
	var fb := prof[seg]
	_poly(cloth, [[_ax(LO, 0.0), _ax(S, fb.y), fb.x], [_ax(HI, 0.0), _ax(S, fb.y), fb.x],
		[_ax(HI, 0.0), _ax(S, fb.y - 0.22), fb.x], [_ax(LO, 0.0), _ax(S, fb.y - 0.22), fb.x]], Vector3(0, 0, 1), w, 0)
	# Cheeks: fans from the wall at the bottom.
	for side: int in [LO, HI]:
		var cheek: Array = [[_ax(side, 0.0), _ax(S, -high), 0.0]]
		for i in seg + 1:
			cheek.append([_ax(side, 0.0), _ax(S, prof[i].y), prof[i].x])
		_poly(cloth, cheek, Vector3(-1.0 if side == LO else 1.0, 0.0, 0.0), w, 0)
	# Frame: a rail on the wall, the front bar, and a hoop at each end.
	_bar(iron, _ax(LO, -0.02), _ax(HI, 0.02), _ax(S, -0.04), _ax(S, 0.0), 0.0, 0.04, 0.0, w)
	_rod(iron, [_ax(LO, 0.0), _ax(S, fb.y), fb.x], [_ax(HI, 0.0), _ax(S, fb.y), fb.x], 0.014, w)
	for side: int in [LO, HI]:
		for i in seg:
			_rod(iron, [_ax(side, 0.0), _ax(S, prof[i].y), prof[i].x], [_ax(side, 0.0), _ax(S, prof[i + 1].y), prof[i + 1].x], 0.011, w)


## A flat metal canopy: a thin slab 1.2 m out from y = 0 with a deeper fascia lip, held by two
## tie rods from wall plates above. One surface in the frame metal (the instance colour).
static func _build_awning_flat(surfaces: Dictionary) -> void:
	var acc := _acc(surfaces, "kit_alu")
	var w := Color.WHITE
	var reach := 1.2
	_bar(acc, _ax(LO, -0.04), _ax(HI, 0.04), _ax(S, -0.10), _ax(S, 0.0), 0.0, reach, 0.01, w)
	_bar(acc, _ax(LO, -0.04), _ax(HI, 0.04), _ax(S, -0.26), _ax(S, 0.02), reach - 0.07, reach, 0.012, w)
	# A tie rod from each end of the fascia up to a plate on the wall.
	for side: int in [LO, HI]:
		var off := 0.25 if side == LO else -0.25
		_rod(acc, [_ax(side, off), _ax(S, 0.02), reach - 0.05], [_ax(side, off), _ax(S, 0.95), 0.03], 0.012, Color(0.6, 0.6, 0.6))
		_bar(acc, _ax(side, off - 0.05), _ax(side, off + 0.05), _ax(S, 0.88), _ax(S, 1.0), 0.0, 0.02, 0.004, w)


## A retractable awning: the cassette on the wall, the canvas sloping down 1.5 m out, the front
## bar with a valance, and a folding arm at each end under it.
static func _build_awning_roller(surfaces: Dictionary) -> void:
	var cloth := _acc(surfaces, "kit_fabric")
	var iron := _acc(surfaces, "kit_iron")
	var w := Color.WHITE
	var reach := 1.5
	var drop := 0.45
	var y0 := -0.14
	var y1 := y0 - drop
	_bar(iron, _ax(LO, -0.03), _ax(HI, 0.03), _ax(S, -0.19), _ax(S, 0.0), 0.0, 0.19, 0.04, w)
	var n := Vector3(0.0, reach, drop).normalized()
	_poly(cloth, [[_ax(LO, 0.0), _ax(S, y0), 0.17], [_ax(HI, 0.0), _ax(S, y0), 0.17],
		[_ax(HI, 0.0), _ax(S, y1), reach], [_ax(LO, 0.0), _ax(S, y1), reach]], n, w, 0)
	_poly(cloth, [[_ax(LO, 0.0), _ax(S, y1), reach + 0.01], [_ax(HI, 0.0), _ax(S, y1), reach + 0.01],
		[_ax(HI, 0.0), _ax(S, y1 - 0.24), reach + 0.01], [_ax(LO, 0.0), _ax(S, y1 - 0.24), reach + 0.01]], Vector3(0, 0, 1), w, 0)
	_bar(iron, _ax(LO, -0.02), _ax(HI, 0.02), _ax(S, y1 - 0.05), _ax(S, y1 + 0.02), reach - 0.06, reach, 0.01, w)
	for side: int in [LO, HI]:
		var off := 0.18 if side == LO else -0.18
		# Shoulder on the wall, elbow half way, hand at the front bar.
		var shoulder := [_ax(side, off), _ax(S, -0.95), 0.04]
		var elbow := [_ax(side, off + (0.35 if side == LO else -0.35)), _ax(S, -0.80), reach * 0.55]
		var hand := [_ax(side, off), _ax(S, y1 + 0.02), reach - 0.05]
		_rod(iron, shoulder, elbow, 0.018, w)
		_rod(iron, elbow, hand, 0.016, w)
		_bar(iron, _ax(side, off - 0.05), _ax(side, off + 0.05), _ax(S, -1.02), _ax(S, -0.88), 0.0, 0.05, 0.01, w)


## A projecting blade sign: a board 0.14 m thick standing 0.62 m out from the wall on two iron
## brackets, its two faces a lightbox (vertex alpha) in the sign colour, a dark trim round the
## edge. The unit opening is the board's height (INSTANCE_CUSTOM.a from it); the board is centred
## on x = 0 and keeps its thickness.
static func _build_blade(surfaces: Dictionary) -> void:
	var acc := _acc(surfaces, "kit_sign")
	var face := Color(1.0, 1.0, 1.0, 1.0)
	var trim := Color(0.16, 0.16, 0.17, 0.0)
	var black := Color(0.06, 0.06, 0.065, 0.0)
	var z0 := 0.20
	var z1 := z0 + 0.62
	var hx := 0.07
	# Board faces (-x and +x) and its edges.
	for s: float in [-1.0, 1.0]:
		_poly(acc, [[_ax(MID, s * hx), _ax(LO, 0.05), z0 + 0.05], [_ax(MID, s * hx), _ax(HI, -0.05), z0 + 0.05],
			[_ax(MID, s * hx), _ax(HI, -0.05), z1 - 0.05], [_ax(MID, s * hx), _ax(LO, 0.05), z1 - 0.05]], Vector3(s, 0, 0), face, 0)
	# Trim: a frame 5 cm wide round each face, standing 8 mm proud, and the board's edge.
	for s: float in [-1.0, 1.0]:
		var xa := _ax(MID, s * hx)
		var xb := _ax(MID, s * (hx + 0.008))
		for band: Array in [[_ax(LO, 0.0), _ax(LO, 0.05), z0, z1], [_ax(HI, -0.05), _ax(HI, 0.0), z0, z1],
				[_ax(LO, 0.05), _ax(HI, -0.05), z0, z0 + 0.05], [_ax(LO, 0.05), _ax(HI, -0.05), z1 - 0.05, z1]]:
			_poly(acc, [[xb, band[0], band[2]], [xb, band[1], band[2]], [xb, band[1], band[3]], [xb, band[0], band[3]]], Vector3(s, 0, 0), trim, 0)
	# Edges of the board.
	_poly(acc, [[_ax(MID, -hx - 0.008), _ax(HI, 0.0), z0], [_ax(MID, hx + 0.008), _ax(HI, 0.0), z0],
		[_ax(MID, hx + 0.008), _ax(HI, 0.0), z1], [_ax(MID, -hx - 0.008), _ax(HI, 0.0), z1]], Vector3(0, 1, 0), trim, 0)
	_poly(acc, [[_ax(MID, -hx - 0.008), _ax(LO, 0.0), z0], [_ax(MID, hx + 0.008), _ax(LO, 0.0), z0],
		[_ax(MID, hx + 0.008), _ax(LO, 0.0), z1], [_ax(MID, -hx - 0.008), _ax(LO, 0.0), z1]], Vector3(0, -1, 0), trim, 0)
	_poly(acc, [[_ax(MID, -hx - 0.008), _ax(LO, 0.0), z1], [_ax(MID, hx + 0.008), _ax(LO, 0.0), z1],
		[_ax(MID, hx + 0.008), _ax(HI, 0.0), z1], [_ax(MID, -hx - 0.008), _ax(HI, 0.0), z1]], Vector3(0, 0, 1), trim, 0)
	_poly(acc, [[_ax(MID, -hx - 0.008), _ax(LO, 0.0), z0], [_ax(MID, hx + 0.008), _ax(LO, 0.0), z0],
		[_ax(MID, hx + 0.008), _ax(HI, 0.0), z0], [_ax(MID, -hx - 0.008), _ax(HI, 0.0), z0]], Vector3(0, 0, -1), trim, 0)
	# Brackets: an arm at the top and one at the bottom from wall plates, and a diagonal stay.
	for end: int in [LO, HI]:
		var yo := 0.10 if end == LO else -0.10
		_bar(acc, _ax(MID, -0.02), _ax(MID, 0.02), _ax(end, yo - 0.02), _ax(end, yo + 0.02), 0.0, z0 + 0.08, 0.0, black)
		_bar(acc, _ax(MID, -0.07), _ax(MID, 0.07), _ax(end, yo - 0.09), _ax(end, yo + 0.09), 0.0, 0.025, 0.006, black)
	_rod(acc, [_ax(MID, 0.0), _ax(HI, -0.32), 0.02], [_ax(MID, 0.0), _ax(HI, -0.10), z0 + 0.02], 0.012, black)


## A curtain-wall cap: `vertical` a mullion cap 1 m tall (y 0..1, scaled up a band of floors),
## else a transom cap 1 m long (x -0.5..0.5, scaled along the wall). A pressure plate on the
## glass line and a deeper cover cap on it, both with their arrises chamfered. No slicing.
static func _build_cap(surfaces: Dictionary, vertical: bool) -> void:
	var acc := _acc(surfaces, "kit_mullion")
	var w := Color.WHITE
	var h := CAP_WIDTH * 0.5
	if vertical:
		_bar(acc, _ax(S, -h), _ax(S, h), _ax(S, 0.0), _ax(S, 1.0), 0.0, 0.028, 0.006, w, 0, 3)
		_bar(acc, _ax(S, -h * 0.62), _ax(S, h * 0.62), _ax(S, 0.0), _ax(S, 1.0), 0.028, 0.15, 0.01, Color(0.92, 0.92, 0.92), 0, 3)
	else:
		_bar(acc, _ax(S, -0.5), _ax(S, 0.5), _ax(S, -h), _ax(S, h), 0.0, 0.026, 0.006, w, 0, 12)
		_bar(acc, _ax(S, -0.5), _ax(S, 0.5), _ax(S, -h * 0.6), _ax(S, h * 0.6), 0.026, 0.10, 0.008, Color(0.92, 0.92, 0.92), 0, 12)


# --- Placement ---------------------------------------------------------------------------------

## True when a pier (at `u` along the wall as the shader counts it) is within 5 cm of `at`.
static func _near_any(list: Array[float], at: float) -> bool:
	for v in list:
		if absf(v - at) < 0.05:
			return true
	return false


## The storefront of one wall of a ground-floor part, as Building._add_facade_details() lays out
## that wall (its face centre `fc` at height 0, `a` along it, `n` out of it, `size_u` long in
## `cols` bays of `pitch`, `cut` off each end by a chamfer, the part's `bottom`, the storefront's
## height `sf`, `span` bays a shop, the pier `stops` along `a`, the pier boxes' colour, the floor
## height and the part's top): a frame round every display window, the door (or the portal of a
## recessed entry), cladding on every pier, a trim round every sign board, and some blade signs.
## `face_id` is the shader's (1..4). Everything off the shop's integer rolls (see the header).
static func storefront_face(b: Building, kit: MultiMeshBatch, face_id: int, fc: Vector3, a: Vector3, n: Vector3,
		size_u: float, cols: int, pitch: float, cut: float, bottom: float, sf: float, span: float,
		stops: Array[float], masonry: bool, floor_h: float, top: float, pier_color: Color) -> void:
	var wall := Basis(a, Vector3.UP, n)
	var skip := 1 if cut > 0.0 else 0
	var span_i := maxi(int(span + 0.5), 1)
	var runs := ceili(float(cols) / float(span_i))
	var glass_w := 2.0 * GLASS_HALF * pitch
	var glass_top := GLASS_TOP * sf
	var bay_mesh := mesh("bay", sf)
	var door_mesh := mesh("door", sf)
	# The piers as the shader counts `u` (from the other end of the wall).
	var pier_u: Array[float] = []
	var pier_h := sf - 0.10
	var pier_mesh := mesh("pier" if masonry else "pier_metal")
	var pier_key := "kit_shop_pier" if masonry else "kit_shop_pier_metal"
	for pu in stops:
		pier_u.append(size_u * 0.5 - pu)
		kit.add(pier_key, pier_mesh, Transform3D(wall, fc + a * pu + Vector3(0.0, bottom + pier_h * 0.5, 0.0)),
			pier_color, Color(0.0, 0.0, 0.0, (pier_h - 1.0) * 0.5))
		b.shop_piece_count += 1
	var names := _face_names(b, face_id - 1, int(float(cols) / float(span_i)))
	var blade_byte := roundi(b.kit_blade_chance * 256.0)
	for run in runs:
		var key := b.shop_key(face_id, run)
		var colour: Color = FRAME_COLORS[frame_index(key)]
		var door_i := door_index(key, span_i)
		var rec := recessed(key)
		var split := centre_mullion(key)
		var single := single_door(key, glass_w)
		for k in span_i:
			var col := run * span_i + k
			if col >= cols:
				break
			if col < skip or col >= cols - skip:
				continue
			var along := size_u * 0.5 - (float(col) + 0.5) * pitch
			var is_door := k == door_i
			var low := 0.0 if is_door else GLASS_LOW * sf
			var h := glass_top - low
			var at := fc + a * along + Vector3(0.0, bottom + (low + glass_top) * 0.5, 0.0)
			var custom := Color(0.0, 0.0, (glass_w - 1.0) * 0.5, (h - 1.0) * 0.5)
			if is_door and not rec:
				custom.g = 1.0 if single else 0.0
				kit.add("kit_shop_door", door_mesh, Transform3D(wall, at), colour, custom)
			else:
				# A recessed entry keeps the frame round its mouth, without sill or transom.
				custom.g = 1.0 if split and not is_door else 0.0
				custom.r = 1.0 if is_door else 0.0
				kit.add("kit_shop_bay", bay_mesh, Transform3D(wall, at), colour, custom)
			b.shop_piece_count += 1
		# The sign board's trim, between the piers at the shop's two ends.
		var u_lo := maxf(float(run * span_i) * pitch, cut)
		var u_hi := minf(float(mini((run + 1) * span_i, cols)) * pitch, size_u - cut)
		var lo_pier := _near_any(pier_u, u_lo)
		var hi_pier := _near_any(pier_u, u_hi)
		var lo_in := 0.30 if lo_pier else 0.05
		var hi_in := 0.30 if hi_pier else 0.05
		var board_w := u_hi - u_lo - lo_in - hi_in
		if board_w > 0.6:
			var mid_u := (u_lo + lo_in + u_hi - hi_in) * 0.5
			var board_h := (FASCIA_TOP - FASCIA_LOW) * sf
			var at_b := fc + a * (size_u * 0.5 - mid_u) + Vector3(0.0, bottom + (FASCIA_LOW + FASCIA_TOP) * 0.5 * sf, 0.0)
			kit.add("kit_shop_fascia", mesh("fascia"), Transform3D(wall, at_b), colour,
				Color(0.0, 0.0, (board_w - 1.0) * 0.5, (board_h - 1.0) * 0.5))
			b.shop_piece_count += 1
		# A blade sign on the pier at one end of the shop, above the sign band.
		if Building.shop_byte(key, SALT_BLADE) >= blade_byte or run >= names.size():
			continue
		var bu := -1.0
		if lo_pier and u_lo > cut + 0.3:
			bu = u_lo
		elif hi_pier and u_hi < size_u - cut - 0.3:
			bu = u_hi
		if bu < 0.0:
			continue
		var y0 := bottom + sf + 0.32
		var hgt := clampf(floor_h * 1.25, 1.5, 2.5)
		if y0 + hgt > top - 0.8:
			continue
		var sign_col: Color = BLADE_COLORS[Building.shop_byte(key, SALT_BLADE_COLOR) % BLADE_COLORS.size()]
		# Lit as the shop's board is (Building.shop_letters()): a lightbox, or dark behind lit
		# channel letters, or off with the shop.
		var sign_off := not Building.shop_open(key) and Building.shop_byte(key, 9) < 150
		var channel := Building.shop_byte(key, 10) >= 110
		var glow := 0.0 if sign_off or channel else 1.0
		var at_s := fc + a * (size_u * 0.5 - bu) + Vector3(0.0, y0 + hgt * 0.5, 0.0)
		kit.add("kit_shop_blade", mesh("blade"), Transform3D(wall, at_s), sign_col,
			Color(glow, 0.0, 0.0, (hgt - 1.0) * 0.5))
		b.shop_piece_count += 1
		b._blade_texts.append([names[run], Transform3D(wall, at_s + n * 0.51), hgt, b.shop_letters(key)])


## The shop names Building puts on this face's sign bands, run by run (its own loop: the same
## hash, the same step past a repeat), so a blade sign carries its shop's name.
static func _face_names(b: Building, face_index: int, runs: int) -> Array:
	var out: Array = []
	var last := -1
	for run in runs:
		var i := absi(hash([b.seed, "sign_name", face_index, run * 7919])) % Building.SHOP_NAMES.size()
		if i == last:
			i = (i + 1) % Building.SHOP_NAMES.size()
		last = i
		out.append(Building.SHOP_NAMES[i])
	return out


## A flat name for a blade sign's face, as CPU arrays (cached per text and size): positions,
## normals and indices of PropFactory.text_mesh()'s letters without their 1 cm of depth and with
## coarser curves. Each face has its own letters, so nothing sees their backs, and the sides and
## the fine curves were ten times the triangles (2,548 for "PHARMACY" against 216) - twelve names
## in reach cost 140 k triangles. Taken with get_mesh_arrays() once: SurfaceTool.append_from()
## reads a mesh back from the renderer, which was 3 ms a building headless alone.
static func _text_geo(text: String, height: float) -> Array:
	var key := "textgeo_%s_%.2f" % [text, height]
	if _cache.has(key):
		return _cache[key]
	var tm := TextMesh.new()
	tm.text = text
	tm.font_size = 48
	tm.pixel_size = height / 48.0
	tm.depth = 0.0
	tm.curve_step = 2.0
	tm.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	tm.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	var arr := tm.get_mesh_arrays()
	var geo := [arr[Mesh.ARRAY_VERTEX], arr[Mesh.ARRAY_NORMAL], arr[Mesh.ARRAY_INDEX]]
	_cache[key] = geo
	return geo


## A building's blade-sign names growing, one per letters' material (Building._commit_blade_texts()).
class TextAcc:
	var verts := PackedVector3Array()
	var norms := PackedVector3Array()
	var idx := PackedInt32Array()

	func add(geo: Array, xf: Transform3D) -> void:
		var src_v: PackedVector3Array = geo[0]
		var src_n: PackedVector3Array = geo[1]
		var src_i = geo[2]
		var base := verts.size()
		var nb := xf.basis.orthonormalized()
		for v in src_v:
			verts.append(xf * v)
		for nv in src_n:
			norms.append(nb * nv)
		if src_i == null or (src_i as PackedInt32Array).is_empty():
			for k in src_v.size():
				idx.append(base + k)
		else:
			for k: int in src_i:
				idx.append(base + k)

	func commit() -> ArrayMesh:
		var mesh := ArrayMesh.new()
		if idx.is_empty():
			return mesh
		var arrays := []
		arrays.resize(Mesh.ARRAY_MAX)
		arrays[Mesh.ARRAY_VERTEX] = verts
		arrays[Mesh.ARRAY_NORMAL] = norms
		arrays[Mesh.ARRAY_INDEX] = idx
		mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
		return mesh


## A blade sign's name on both faces of its board, into `acc`: `xform` is the board's middle
## (x through its thickness, y up, z out of the wall), `hgt` its height. A short name stacks its
## letters, the old theatre way; a long one runs up the board, reading bottom to top.
static func blade_letters(acc: TextAcc, text: String, xform: Transform3D, hgt: float) -> void:
	var face_x := 0.07 + 0.008 + 0.006
	var room := hgt - 0.34
	var stacked := text.length() <= 6 and text.find(" ") < 0
	for s: float in [1.0, -1.0]:
		# Letter +X to the viewer's right, +Y up, +Z out of the face.
		var upright := Basis(Vector3(0.0, 0.0, -s), Vector3.UP, Vector3(s, 0.0, 0.0))
		var along_up := Basis(Vector3.UP, Vector3(0.0, 0.0, s), Vector3(s, 0.0, 0.0))
		if stacked:
			var cap := minf(0.30, room / maxf(float(text.length()), 1.0) * 0.82)
			var step := room / maxf(float(text.length()), 1.0)
			for i in text.length():
				var y := room * 0.5 - step * (float(i) + 0.5)
				acc.add(_text_geo(text[i], cap), xform * Transform3D(upright, Vector3(s * face_x, y, 0.0)))
		else:
			var cap := 0.24
			var wide := float(text.length()) * cap * 0.62
			var fit := minf(1.0, room / maxf(wide, 0.01))
			acc.add(_text_geo(text, cap), xform * Transform3D(along_up.scaled_local(Vector3(fit, fit, 1.0)), Vector3(s * face_x, 0.0, 0.0)))


## The curtain wall of one face of a part: a mullion cap on every painted mullion line (the
## shader's fu < 0.05 of each bay, and one at the far corner) in bands of CAP_BAND_ROWS floors, and
## a transom cap on each floor's two transom lines (curtain_spandrel's 0.08 and 0.93), the flat
## part of the wall long. `colour` is the building's frame paint (the lines' `mullion_color`).
static func curtain_face(b: Building, kit: MultiMeshBatch, fc: Vector3, a: Vector3, n: Vector3, size_u: float,
		cols: int, pitch: float, cut: float, bottom: float, sf: float, floor_h: float, rows: int, top: float, colour: Color) -> void:
	var skip := 1 if cut > 0.0 else 0
	var y0 := bottom + sf
	var y1 := top - 0.3
	if y1 - y0 < floor_h or cols - 2 * skip < 1:
		return
	var cap_v := mesh("cap_v")
	var cap_h := mesh("cap_h")
	var lines: Array[float] = []
	for col in range(skip, cols - skip):
		lines.append((float(col) + 0.025) * pitch)
	lines.append(float(cols - skip) * pitch - CAP_WIDTH * 0.5 - 0.005)
	var band_h := floor_h * float(CAP_BAND_ROWS)
	var y := y0
	while y < y1 - 0.05:
		var y_top := minf(y + band_h, y1)
		for u in lines:
			kit.add("kit_cap_v", cap_v, Transform3D(Basis(a, Vector3.UP * (y_top - y), n), fc + a * (size_u * 0.5 - u) + Vector3(0.0, y, 0.0)), colour, NO_SLICE)
			b.cap_piece_count += 1
		y = y_top
	var run_len := size_u - 2.0 * cut
	for row in rows:
		for f: float in [CURTAIN_SILL, CURTAIN_HEAD]:
			var yy := y0 + (float(row) + f) * floor_h
			if yy > y1:
				continue
			kit.add("kit_cap_h", cap_h, Transform3D(Basis(a * run_len, Vector3.UP, n), fc + Vector3(0.0, yy, 0.0)), colour, NO_SLICE)
			b.cap_piece_count += 1


# --- Window frames -----------------------------------------------------------------------------

## A window frame for Building's `Frames` MultiMesh, in its unit space (outer edge 1 x 1, depth
## 0..1 along +Z, scaled per instance to the window and 0.1 m): four bars `tx` / `ty` of the
## window wide (Building works them out from FRAME_WIDTH, so the frame is a real 45-60 mm section
## on any window), with their fronts 55 mm out and the faces that look into the opening, and
## `sash` 1 a meeting rail (a sash window), 2 a meeting rail and a muntin (a casement), set back
## a little behind the frame's face. With `sill`, the old box ledge under it. The material is
## PropFactory.material()'s, which Building._detail_material() copies.
static func window_frame(sill: bool, tx: float, ty: float, sash: int) -> Mesh:
	var qx := clampi(roundi(tx * 400.0), 4, 60)
	var qy := clampi(roundi(ty * 400.0), 4, 60)
	var key := "wf_%d_%d_%d_%d" % [int(sill), qx, qy, sash]
	if _cache.has(key):
		return _cache[key]
	tx = float(qx) / 400.0
	ty = float(qy) / 400.0
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	st.set_material(PropFactory.material(Color.WHITE, 0.55))
	var zf := 0.55
	# Jambs, head and sill rail: fronts and inner faces.
	_st_bar(st, Vector3(-0.5, -0.5, 0.0), Vector3(-0.5 + tx, 0.5, zf), 2 | 16)
	_st_bar(st, Vector3(0.5 - tx, -0.5, 0.0), Vector3(0.5, 0.5, zf), 1 | 16)
	_st_bar(st, Vector3(-0.5 + tx, 0.5 - ty, 0.0), Vector3(0.5 - tx, 0.5, zf), 4 | 16)
	_st_bar(st, Vector3(-0.5 + tx, -0.5, 0.0), Vector3(0.5 - tx, -0.5 + ty, zf), 8 | 16)
	if sash >= 1:
		var ry := 0.04
		_st_bar(st, Vector3(-0.5 + tx, ry - ty * 0.55, 0.0), Vector3(0.5 - tx, ry + ty * 0.55, zf - 0.15), 4 | 8 | 16)
	if sash >= 2:
		_st_bar(st, Vector3(-tx * 0.45, -0.5 + ty, 0.0), Vector3(tx * 0.45, 0.5 - ty, zf - 0.15), 1 | 2 | 16)
	if sill:
		var bm := BoxMesh.new()
		bm.size = Vector3(1.12, 0.08, 1.6)
		st.append_from(bm, 0, Transform3D(Basis(), Vector3(0.0, -0.54, 0.8)))
	var m := st.commit()
	_cache[key] = m
	return m


## A box's faces into `st`: `mask` bits 1 -x, 2 +x, 4 -y, 8 +y, 16 +z (the front).
static func _st_bar(st: SurfaceTool, lo: Vector3, hi: Vector3, mask: int) -> void:
	if mask & 16:
		_st_quad(st, Vector3(lo.x, lo.y, hi.z), Vector3(hi.x, lo.y, hi.z), Vector3(hi.x, hi.y, hi.z), Vector3(lo.x, hi.y, hi.z), Vector3(0, 0, 1))
	if mask & 1:
		_st_quad(st, Vector3(lo.x, lo.y, lo.z), Vector3(lo.x, hi.y, lo.z), Vector3(lo.x, hi.y, hi.z), Vector3(lo.x, lo.y, hi.z), Vector3(-1, 0, 0))
	if mask & 2:
		_st_quad(st, Vector3(hi.x, lo.y, lo.z), Vector3(hi.x, hi.y, lo.z), Vector3(hi.x, hi.y, hi.z), Vector3(hi.x, lo.y, hi.z), Vector3(1, 0, 0))
	if mask & 4:
		_st_quad(st, Vector3(lo.x, lo.y, lo.z), Vector3(hi.x, lo.y, lo.z), Vector3(hi.x, lo.y, hi.z), Vector3(lo.x, lo.y, hi.z), Vector3(0, -1, 0))
	if mask & 8:
		_st_quad(st, Vector3(lo.x, hi.y, lo.z), Vector3(hi.x, hi.y, lo.z), Vector3(hi.x, hi.y, hi.z), Vector3(lo.x, hi.y, hi.z), Vector3(0, 1, 0))


## A quad facing `nrm`, wound clockwise seen from the front (Godot's front faces).
static func _st_quad(st: SurfaceTool, p0: Vector3, p1: Vector3, p2: Vector3, p3: Vector3, nrm: Vector3) -> void:
	var tri := [p0, p1, p2, p0, p2, p3]
	if (p1 - p0).cross(p2 - p0).dot(nrm) > 0.0:
		tri = [p0, p2, p1, p0, p3, p2]
	for p: Vector3 in tri:
		st.set_normal(nrm)
		st.set_uv(Vector2.ZERO)
		st.add_vertex(p)
