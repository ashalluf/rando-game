extends SceneTree
## Measures the LOD candidates of every scanned plant on the ladder path and writes the table
## FoliageLod reads (scripts/world/foliage_lod_table.gd). Headless is fine: it only reads meshes.
##
##   godot --headless --path . --script tools/foliage_lods.gd            # measure, write table
##   REPORT=1 godot --headless --path . --script tools/foliage_lods.gd   # print, write nothing
##   FILES=tree_a.glb,tree_c.glb ...                                     # just these (report)
##
## Run it again whenever a foliage model is re-exported or the engine is upgraded (the smoke test
## fails if the table stops matching - see FoliageLod.build()). Several minutes: the distances
## are exact point-to-triangle queries in GDScript.
##
## Per surface, the candidates are generate_lods()'s own levels and FoliageLod's thinned levels
## (surfaces of many small pieces). Each is measured against the full surface: points spread
## over one surface by area, and the exact distance from each to the nearest point of the other
## surface, both ways (the full surface to the level: what vanished or moved; the level to the
## full surface: what grew or was added). Nothing within SEARCH metres counts as SEARCH. The
## departure is the larger of the two ways' PERCENTILE of those distances (a few stray points
## a pixel off are not a visible change; a percent of the canopy is), in model metres (a batch
## of these scales it by its biggest instance, MultiMeshBatch.build()). On leaf surfaces a level
## must also keep MIN_AREA of the cover, and a thinned level its outline (FoliageLod.outline()).
## A level is kept if it is on the trade-off front (nothing else has fewer triangles AND a
## smaller departure) and saves at least MIN_STEP of the triangles of the level before it.

const SAMPLES := 2000
const SEARCH := 1.5
const PERCENTILE := 0.98
const MIN_STEP := 0.3
## On a leaf surface, or one made mostly of two-triangle cards (the jacaranda's twigs), surface
## area IS cover: no level may keep less than this share of it, whatever its departure says (the
## simplifier's leaf LODs thin a canopy while staying close to what is left of it).
const MIN_AREA := 0.85


func _initialize() -> void:
	var report := OS.get_environment("REPORT") == "1"
	var files: Array = OS.get_environment("FILES").split(",", false)
	var all := files.is_empty()
	if all:
		files = PropFactory.foliage_ladder_files()
	var table := {}
	var t_all := Time.get_ticks_msec()
	for f: String in files:
		var t0 := Time.get_ticks_msec()
		var im := PropFactory.foliage_importer(PropFactory.MODEL_DIR + f)
		if im == null:
			push_error("missing " + f)
			continue
		var scale := 1.0
		print(f)
		var surfaces: Array = []
		for s in im.get_surface_count():
			surfaces.append(_surface(im, s, scale))
		table[f] = {"surfaces": surfaces}
		print("  (%d ms)" % (Time.get_ticks_msec() - t0))
	print("all measured in %d ms" % (Time.get_ticks_msec() - t_all))
	if not report and all:
		_write(table)
	quit()


func _surface(im: ImporterMesh, s: int, scale: float) -> Dictionary:
	var arrays := im.get_surface_arrays(s)
	var vx: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	var base: PackedInt32Array = arrays[Mesh.ARRAY_INDEX]
	var mat := im.get_surface_material(s)
	var rng := RandomNumberGenerator.new()
	rng.seed = 1234 + s
	var base_grid := _grid(vx, base)
	var base_pts := _samples(vx, base, rng)
	var info := FoliageLod.analyse(vx, base)
	var tris := base.size() / 3
	var leafy := mat is BaseMaterial3D and ((mat as BaseMaterial3D).transparency != BaseMaterial3D.TRANSPARENCY_DISABLED or mat.resource_name in PropFactory.MISLABELLED_LEAVES)
	if not info.is_empty() and info.cards * 2 > info.count:
		leafy = true
	print("  s%d %s tris=%d pieces=%s%s" % [s, mat.resource_name if mat else "?", tris, "-" if info.is_empty() else "%d (%d thinnable, %d cards)" % [info.count, info.thinnable, info.cards], " leafy" if leafy else ""])
	var cands: Array = []
	for l in im.get_surface_lod_count(s):
		var idx := im.get_surface_lod_indices(s, l)
		# The cheap test first: a leafy level that has lost its cover is out whatever it measures.
		var cover := _area(vx, idx) / maxf(float(base_pts[1]), 1e-9)
		if leafy and cover < MIN_AREA:
			print("    %-9s tris=%6d area=%.2f  (cover lost: out)" % ["gen %d" % l, idx.size() / 3, cover])
			continue
		cands.append(_measure(["gen", l], vx, idx, vx, base, base_grid, base_pts, rng))
	if not info.is_empty():
		var pc := FoliageLod.piece_cover(arrays, info, _albedo(mat))
		for stride in FoliageLod.STRIDES:
			var pick := _phase(info, pc, stride)
			if pick.is_empty():
				continue
			var th := FoliageLod.thin(arrays, info, stride, pick.phase, pick.grow)
			if th.is_empty():
				continue
			cands.append(_measure(["thin", stride, pick.phase, pick.grow], th.arrays[Mesh.ARRAY_VERTEX], th.index, vx, base, base_grid, base_pts, rng))
	# A thinned level whose outline - where the first and last 1 % of its area lie along each
	# axis, so one stray twig at the tip of a limb does not count - moved further than its
	# departure is out: grown pieces must not swell the crown, dropped ones must not shrink it.
	# (A generated level is a re-tessellation, which the corner-weighted outline cannot compare
	# fairly; its departure already bounds how far it moved.)
	var outline := FoliageLod.outline(vx, base)
	var kept_cands: Array = []
	for c: Dictionary in cands:
		c.drift = FoliageLod.outline_drift(outline, c.outline)
		if c.id[0] == "thin" and c.drift > c.dep:
			print("    %-9s tris=%6d  (outline moved %.3f m, departure %.3f: out)" % ["%s %d" % [c.id[0], c.id[1]], c.tris, c.drift, c.dep])
		else:
			kept_cands.append(c)
	for c: Dictionary in cands:
		print("    %-9s tris=%6d area=%.2f  p90 %.3f  p95 %.3f  p98 %.3f  (fwd p98 %.3f back p98 %.3f) drift %.3f%s" % [
			"%s %d" % [c.id[0], c.id[1]], c.tris, c.area, c.p90, c.p95, c.p98, c.fwd98, c.back98, c.drift,
			"  phase %d grow %.3f" % [c.id[2], c.id[3]] if c.id[0] == "thin" else ""])
	cands = kept_cands
	# The trade-off front, then the steps.
	cands.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return a.tris > b.tris)
	var levels: Array = []
	var last_tris := tris
	var last_edge := 0.0
	for c: Dictionary in cands:
		var edge: float = c.dep * scale
		var dominated := false
		for o: Dictionary in cands:
			if o != c and o.tris <= c.tris and o.dep * scale <= edge and (o.tris < c.tris or o.dep < c.dep):
				dominated = true
				break
		if dominated or c.tris > last_tris * (1.0 - MIN_STEP) or edge <= last_edge:
			continue
		if edge >= SEARCH * scale * 0.99:
			continue
		edge = snappedf(edge, 0.001)
		if edge <= last_edge:
			edge = last_edge + 0.001
		var level: Array = [c.id[0], c.id[1], c.tris, edge]
		if c.id[0] == "thin":
			level.append_array([c.id[2], c.id[3]])
		levels.append(level)
		last_tris = c.tris
		last_edge = edge
	print("    ladder %s" % str(levels))
	return {"tris": tris, "levels": levels}


func _measure(id: Array, lvx: PackedVector3Array, lix: PackedInt32Array, vx: PackedVector3Array, base: PackedInt32Array, base_grid: Dictionary, base_pts: Array, rng: RandomNumberGenerator) -> Dictionary:
	var lgrid := _grid(lvx, lix)
	var fwd := PackedFloat32Array()
	for pn: Vector3 in base_pts[0]:
		fwd.append(_nearest(lgrid, pn))
	var lpts := _samples(lvx, lix, rng)
	var back := PackedFloat32Array()
	for pn: Vector3 in lpts[0]:
		back.append(_nearest(base_grid, pn))
	var both := fwd + back
	fwd.sort()
	back.sort()
	both.sort()
	# Both ways, each at the percentile: pooled into one list, an error on one side only (twigs
	# removed, nothing added) would be diluted by the other side's zeros.
	var dep := maxf(_pct(fwd, PERCENTILE), _pct(back, PERCENTILE))
	return {"id": id, "tris": lix.size() / 3, "area": float(lpts[1]) / maxf(float(base_pts[1]), 1e-9), "outline": FoliageLod.outline(lvx, lix),
		"p90": _pct(both, 0.9), "p95": _pct(both, 0.95), "p98": _pct(both, 0.98),
		"fwd98": _pct(fwd, 0.98), "back98": _pct(back, 0.98), "dep": dep}


## A surface's source albedo (the JPG its import came from, read raw), or null.
static func _albedo(mat: Material) -> Image:
	var tex: Texture2D = (mat as BaseMaterial3D).albedo_texture if mat is BaseMaterial3D else null
	if tex == null or tex.resource_path == "":
		return null
	return Image.load_from_file(ProjectSettings.globalize_path(tex.resource_path))


## Which phase of `stride` a thinned level keeps (FoliageLod.kept()): the one whose level keeps
## level 0's tone best, and the growth that makes its textured cover exactly level 0's. At most
## 16 phases are tried. Returns {"phase", "grow"} or {} if a level would keep nothing.
static func _phase(info: Dictionary, pc: Dictionary, stride: int) -> Dictionary:
	var cover: PackedFloat64Array = pc.cover
	var tone: PackedColorArray = pc.tone
	var rank: PackedInt32Array = info.rank
	var fixed_cover := 0.0
	var fixed_tone := Color(0, 0, 0, 0)
	var thin_cover := 0.0
	var thin_tone := Color(0, 0, 0, 0)
	for k in rank.size():
		if rank[k] < 0:
			fixed_cover += cover[k]
			fixed_tone += tone[k]
		else:
			thin_cover += cover[k]
			thin_tone += tone[k]
	var ref := ((fixed_tone + thin_tone) / maxf(fixed_cover + thin_cover, 1e-12)).get_luminance()
	var best := {}
	var best_err := INF
	for phase in mini(stride, 16):
		var kc := 0.0
		var kt := Color(0, 0, 0, 0)
		for k in rank.size():
			if rank[k] >= 0 and rank[k] % stride == phase:
				kc += cover[k]
				kt += tone[k]
		if kc <= 0.0:
			continue
		var g2 := thin_cover / kc
		var lum := ((fixed_tone + kt * g2) / maxf(fixed_cover + kc * g2, 1e-12)).get_luminance()
		var err := absf(lum / maxf(ref, 1e-9) - 1.0)
		if err < best_err:
			best_err = err
			best = {"phase": phase, "grow": snappedf(sqrt(g2), 0.0001)}
	return best


static func _area(vx: PackedVector3Array, ix: PackedInt32Array) -> float:
	var total := 0.0
	for t in range(0, ix.size(), 3):
		total += 0.5 * (vx[ix[t + 1]] - vx[ix[t]]).cross(vx[ix[t + 2]] - vx[ix[t]]).length()
	return total


static func _pct(a: PackedFloat32Array, q: float) -> float:
	return a[clampi(int(q * a.size()), 0, a.size() - 1)] if a.size() > 0 else SEARCH


## A uniform grid over a triangle soup for nearest-point queries: each triangle listed in every
## cell its bounds touch. The cell is a couple of median triangle sizes.
static func _grid(vx: PackedVector3Array, ix: PackedInt32Array) -> Dictionary:
	var n := ix.size() / 3
	var a := PackedVector3Array()
	var b := PackedVector3Array()
	var c := PackedVector3Array()
	a.resize(n)
	b.resize(n)
	c.resize(n)
	var sizes := PackedFloat32Array()
	sizes.resize(n)
	for t in n:
		a[t] = vx[ix[t * 3]]
		b[t] = vx[ix[t * 3 + 1]]
		c[t] = vx[ix[t * 3 + 2]]
		sizes[t] = maxf((b[t] - a[t]).length(), maxf((c[t] - a[t]).length(), (c[t] - b[t]).length()))
	var sorted := sizes.duplicate()
	sorted.sort()
	var h := maxf(float(sorted[n / 2]) * 2.0, 0.01) if n > 0 else 1.0
	var cells := {}
	for t in n:
		var lo := (a[t].min(b[t]).min(c[t]) / h).floor()
		var hi := (a[t].max(b[t]).max(c[t]) / h).floor()
		for x in range(int(lo.x), int(hi.x) + 1):
			for y in range(int(lo.y), int(hi.y) + 1):
				for z in range(int(lo.z), int(hi.z) + 1):
					var key := Vector3i(x, y, z)
					# An Array, not a PackedInt32Array: a packed array read out of a Dictionary is a
					# copy, and appending to it leaves the cell's own list as it was.
					if cells.has(key):
						(cells[key] as Array).append(t)
					else:
						cells[key] = [t]
	return {"a": a, "b": b, "c": c, "h": h, "cells": cells}


## Distance from `p` to the nearest point of the grid's triangles, searching shells of cells
## outwards until nothing nearer can remain, up to SEARCH.
static func _nearest(g: Dictionary, p: Vector3) -> float:
	var h: float = g.h
	var cells: Dictionary = g.cells
	var a: PackedVector3Array = g.a
	var b: PackedVector3Array = g.b
	var c: PackedVector3Array = g.c
	var cp := Vector3i((p / h).floor())
	var best := SEARCH * SEARCH
	var tested := {}
	var r := 0
	while true:
		for x in range(cp.x - r, cp.x + r + 1):
			for y in range(cp.y - r, cp.y + r + 1):
				for z in range(cp.z - r, cp.z + r + 1):
					if r > 0 and absi(x - cp.x) < r and absi(y - cp.y) < r and absi(z - cp.z) < r:
						continue
					var key := Vector3i(x, y, z)
					if not cells.has(key):
						continue
					for t: int in cells[key]:
						if tested.has(t):
							continue
						tested[t] = true
						var d := _tri_dist2(p, a[t], b[t], c[t])
						if d < best:
							best = d
		# Everything within r * h of p has been tested.
		var reach := float(r) * h
		if best <= reach * reach or reach > SEARCH:
			break
		r += 1
	return sqrt(best)


## Squared distance from p to triangle abc (closest point by Voronoi region, Ericson 5.1.5).
static func _tri_dist2(p: Vector3, a: Vector3, b: Vector3, c: Vector3) -> float:
	var ab := b - a
	var ac := c - a
	var ap := p - a
	var d1 := ab.dot(ap)
	var d2 := ac.dot(ap)
	if d1 <= 0.0 and d2 <= 0.0:
		return ap.length_squared()
	var bp := p - b
	var d3 := ab.dot(bp)
	var d4 := ac.dot(bp)
	if d3 >= 0.0 and d4 <= d3:
		return bp.length_squared()
	var vc := d1 * d4 - d3 * d2
	if vc <= 0.0 and d1 >= 0.0 and d3 <= 0.0:
		return (ap - ab * (d1 / (d1 - d3))).length_squared()
	var cp := p - c
	var d5 := ab.dot(cp)
	var d6 := ac.dot(cp)
	if d6 >= 0.0 and d5 <= d6:
		return cp.length_squared()
	var vb := d5 * d2 - d1 * d6
	if vb <= 0.0 and d2 >= 0.0 and d6 <= 0.0:
		return (ap - ac * (d2 / (d2 - d6))).length_squared()
	var va := d3 * d6 - d5 * d4
	if va <= 0.0 and (d4 - d3) >= 0.0 and (d5 - d6) >= 0.0:
		return (bp - (c - b) * ((d4 - d3) / ((d4 - d3) + (d5 - d6)))).length_squared()
	var denom := 1.0 / (va + vb + vc)
	return (ap - ab * (vb * denom) - ac * (vc * denom)).length_squared()


## SAMPLES points spread over the surface by area (random triangle by area, random point in it).
## Returns [points, total area].
static func _samples(vx: PackedVector3Array, ix: PackedInt32Array, rng: RandomNumberGenerator) -> Array:
	var cum := PackedFloat64Array()
	var total := 0.0
	for t in range(0, ix.size(), 3):
		total += 0.5 * (vx[ix[t + 1]] - vx[ix[t]]).cross(vx[ix[t + 2]] - vx[ix[t]]).length()
		cum.append(total)
	var pts := PackedVector3Array()
	if cum.is_empty():
		return [pts, 0.0]
	for k in SAMPLES:
		var t := mini(cum.bsearch(rng.randf() * total), cum.size() - 1)
		var a := vx[ix[t * 3]]
		var b := vx[ix[t * 3 + 1]]
		var c := vx[ix[t * 3 + 2]]
		var u := rng.randf()
		var v := rng.randf()
		if u + v > 1.0:
			u = 1.0 - u
			v = 1.0 - v
		pts.append(a + (b - a) * u + (c - a) * v)
	return [pts, total]


func _write(table: Dictionary) -> void:
	var lines: PackedStringArray = []
	lines.append("class_name FoliageLodTable")
	lines.append("extends RefCounted")
	lines.append("## WRITTEN BY tools/foliage_lods.gd - do not edit by hand; run the tool again instead.")
	lines.append("## Per scanned plant, per surface: its full triangle count, the LOD levels kept")
	lines.append("## ([\"gen\", generated LOD, triangles, edge in metres] or [\"thin\", stride, triangles, edge,")
	lines.append("## phase, growth]). See FoliageLod.")
	lines.append("const TABLE := {")
	var keys: Array = table.keys()
	keys.sort()
	for f: String in keys:
		lines.append("\t\"%s\": {\"surfaces\": [" % f)
		for s: Dictionary in table[f].surfaces:
			var lv: PackedStringArray = []
			for l: Array in s.levels:
				if l[0] == "thin":
					lv.append("[\"thin\", %d, %d, %.3f, %d, %.4f]" % [l[1], l[2], l[3], l[4], l[5]])
				else:
					lv.append("[\"%s\", %d, %d, %.3f]" % [l[0], l[1], l[2], l[3]])
			lines.append("\t\t{\"tris\": %d, \"levels\": [%s]}," % [s.tris, ", ".join(lv)])
		lines.append("\t]},")
	lines.append("}")
	var fa := FileAccess.open("res://scripts/world/foliage_lod_table.gd", FileAccess.WRITE)
	fa.store_string("\n".join(lines) + "\n")
	fa.close()
	print("wrote scripts/world/foliage_lod_table.gd")
