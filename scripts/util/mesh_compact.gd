class_name MeshCompact
extends RefCounted
## Drops the vertices no index refers to from a surface's arrays. A shadow twin is the same
## vertex buffer as the mesh it stands in for with only its coarse LODs' indices (PropFactory's
## shadow proxies, FoliageLod's shadow ladders), so most of that copy was never drawn and only
## took memory - on the CPU under the dummy renderer, in video memory everywhere else. The kept
## vertices keep their order and every attribute, so the triangles drawn are the same ones.
##
## MESH_COMPACT=0 in the environment turns it off (the A/B).

static var enabled := OS.get_environment("MESH_COMPACT") != "0"


## `arrays` (Mesh.ARRAY_MAX slots, indexed) with only the vertices `arrays[ARRAY_INDEX]` and every
## index array in `lods` use, renumbered. `lods` is changed in place (its values remapped).
## Returns `arrays` itself when nothing would be dropped or the arrays are not indexed.
static func compact(arrays: Array, lods: Dictionary = {}) -> Array:
	if not enabled or arrays.size() < Mesh.ARRAY_MAX or arrays[Mesh.ARRAY_INDEX] == null \
			or arrays[Mesh.ARRAY_VERTEX] == null:
		return arrays
	var count: int = (arrays[Mesh.ARRAY_VERTEX] as PackedVector3Array).size()
	if count == 0:
		return arrays
	var used := PackedByteArray()
	used.resize(count)
	var index_sets: Array[PackedInt32Array] = [arrays[Mesh.ARRAY_INDEX]]
	for k in lods:
		index_sets.append(lods[k])
	for idx: PackedInt32Array in index_sets:
		for i in idx:
			used[i] = 1
	var remap := PackedInt32Array()
	remap.resize(count)
	var kept := 0
	for v in count:
		if used[v] != 0:
			remap[v] = kept
			kept += 1
		else:
			remap[v] = -1
	if kept == count:
		return arrays
	var out := arrays.duplicate()
	for slot in Mesh.ARRAY_MAX:
		if slot == Mesh.ARRAY_INDEX or arrays[slot] == null:
			continue
		out[slot] = _pick(arrays[slot], count, kept, used)
	out[Mesh.ARRAY_INDEX] = _renumber(arrays[Mesh.ARRAY_INDEX], remap)
	for k in lods:
		lods[k] = _renumber(lods[k], remap)
	return out


## The kept vertices' share of one per-vertex array, whatever its element type and width.
static func _pick(src: Variant, count: int, kept: int, used: PackedByteArray) -> Variant:
	var n: int = src.size()
	if n == 0 or n % count != 0:
		return src
	var width := n / count
	var dst: Variant = src.duplicate()
	dst.resize(kept * width)
	var j := 0
	for v in count:
		if used[v] == 0:
			continue
		var a := v * width
		var b := j * width
		for c in width:
			dst[b + c] = src[a + c]
		j += 1
	return dst


static func _renumber(idx: PackedInt32Array, remap: PackedInt32Array) -> PackedInt32Array:
	var out := idx.duplicate()
	for i in out.size():
		out[i] = remap[out[i]]
	return out
