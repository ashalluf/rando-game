extends SceneTree
## Measures every crowd rig's FACE for character.gdshader's close-up face pass (CrowdFaces) and
## writes the two things it reads: the face atlas assets/textures/crowd/crowd_faces.png (one
## TILE x TILE tile per rig, in that rig's body-atlas UV over its face rect) and the table
## scripts/npc/crowd_face_table.gd. Rerun it whenever a crowd rig is rebuilt (tools/crowd/build.sh)
## or added to Pedestrian.MODELS - the smoke test fails when the table and MODELS disagree.
##
##   LIBGL_ALWAYS_SOFTWARE=1 xvfb-run -a -s "-screen 0 640x480x24" godot --rendering-driver opengl3 \
##     --display-driver x11 --audio-driver Dummy --path . --script tools/crowd_faces/face_fit.gd
##
## It needs mesh data, so never --headless (the dummy renderer keeps none). About a minute.
##
## The head frame is hat_fit.gd's (metres, skeleton axes: y up, z the way the rig faces), moved to
## the midpoint of the two eye centres and scaled by the eye spacing against the average face
## (EYE_HALF), so one zone table fits every face. Per rig:
##   - eyes: each eye's centre (the centroid of its eye vertices - B and A both full), and the
##     linear map from a direction on the eyeball (x across, y up; unit sphere) to atlas UV, fitted
##     by least squares over the front half: uv = c + J * (dx, dy). The shader moves the iris by
##     sampling at uv - J * gaze and finds the lid line from J^-1 (uv - c);
##   - lid: an atlas UV on the upper-lid skin over each eye, the colour the painted blink takes;
##   - the face map, RGBA over the bounding UV rect of the head's front skin: R blood (cheeks, nose,
##     lips, ears), G cavity (under the eyes, the eye sockets' inner corners, the nose wings, the
##     mouth corners, the lip line), B oil (forehead, nose, chin: the T-zone), A 1.0 lips / 0.5
##     thin skin (ears, nose wings) - evaluated per texel from the interpolated head-frame position.
const OUT_TABLE := "res://scripts/npc/crowd_face_table.gd"
const OUT_ATLAS := "res://assets/textures/crowd/crowd_faces.png"
const TILE := 128
const COLS := 8
## Half the distance between the eye centres on the average face, metres.
const EYE_HALF := 0.032


func _initialize() -> void:
	var ped = load("res://scripts/npc/pedestrian.gd")
	var models: Array = Array(ped.MODELS)
	var rows_n := int(ceil(float(models.size()) / float(COLS)))
	var atlas := Image.create(TILE * COLS, TILE * rows_n, false, Image.FORMAT_RGBA8)
	atlas.fill(Color(0, 0, 0, 0))
	var rows: Array[String] = []
	for i in models.size():
		var path: String = models[i]
		var m := _measure(path)
		if m.is_empty():
			print("FACE ", path, ": no mesh data (run under opengl3, not --headless)")
			continue
		var tile := Vector2i((i % COLS) * TILE, (i / COLS) * TILE)
		atlas.blit_rect(m.map, Rect2i(0, 0, TILE, TILE), tile)
		rows.append(_row(path.get_file().get_basename(), i, m))
		print("FACE %s: eyes %.4f apart, rect %s, J_l %s, fit err %.4f, %d face tris" % [
			path.get_file(), m.spacing, m.rect, m.jl, m.err, m.tris])
	atlas.save_png(OUT_ATLAS)
	var f := FileAccess.open(OUT_TABLE, FileAccess.WRITE)
	f.store_string("class_name CrowdFaceTable\nextends RefCounted\n")
	f.store_string("## WRITTEN BY tools/crowd_faces/face_fit.gd - do not edit by hand; run the tool again instead.\n")
	f.store_string("## Per crowd rig (the body atlas' name less _body): tile (index in crowd_faces.png, COLS a row),\n")
	f.store_string("## rect (the face map's rect in atlas UV: x, y, w, h), eyes [c.x, c.y, j00, j01, j10, j11] for the\n")
	f.store_string("## rig's left (+x) and right eye (uv = c + J * (dx, dy) on the unit eyeball), lid [u, v] over each.\n")
	f.store_string("const TILE := %d\nconst COLS := %d\nconst ROWS := %d\n" % [TILE, COLS, rows_n])
	f.store_string("const TABLE := {\n")
	for r in rows:
		f.store_string(r)
	f.store_string("}\n")
	f.close()
	print("FACE wrote ", OUT_TABLE, " and ", OUT_ATLAS, " (", rows.size(), " rigs)")
	quit()


func _row(key: String, tile: int, m: Dictionary) -> String:
	var r: Rect2 = m.rect
	return "\t\"%s\": {\"tile\": %d, \"rect\": [%.5f, %.5f, %.5f, %.5f], \"eye_l\": [%.5f, %.5f, %.5f, %.5f, %.5f, %.5f], \"eye_r\": [%.5f, %.5f, %.5f, %.5f, %.5f, %.5f], \"lid\": [%.5f, %.5f, %.5f, %.5f]},\n" % [
		key, tile, r.position.x, r.position.y, r.size.x, r.size.y,
		m.cl.x, m.cl.y, m.jl[0], m.jl[1], m.jl[2], m.jl[3],
		m.cr.x, m.cr.y, m.jr[0], m.jr[1], m.jr[2], m.jr[3],
		m.lid_l.x, m.lid_l.y, m.lid_r.x, m.lid_r.y]


## The Body mesh in rest pose, metres, head-bone-relative (hat_fit.gd's frame), with UVs.
func _body(path: String) -> Dictionary:
	var inst: Node3D = (load(path) as PackedScene).instantiate()
	get_root().add_child(inst)
	var skel := inst.find_child("Skeleton3D", true, false) as Skeleton3D
	var out := {}
	if skel == null or skel.find_bone("Head") < 0:
		inst.free()
		return out
	var unit := 1.0
	var node: Node3D = skel
	while node != null and node != inst:
		unit *= node.transform.basis.get_scale().y
		node = node.get_parent() as Node3D
	var head_o := skel.get_bone_global_rest(skel.find_bone("Head")).origin
	for n in inst.find_children("*", "MeshInstance3D", true, false):
		var mi := n as MeshInstance3D
		if mi.skin == null or mi.mesh == null or String(mi.name).begins_with("Hair"):
			continue
		var arrays := mi.mesh.surface_get_arrays(0)
		if arrays.is_empty() or arrays[Mesh.ARRAY_BONES] == null or arrays[Mesh.ARRAY_COLOR] == null:
			continue
		var verts: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
		var bones: PackedInt32Array = arrays[Mesh.ARRAY_BONES]
		var weights: PackedFloat32Array = arrays[Mesh.ARRAY_WEIGHTS]
		var per := bones.size() / maxi(verts.size(), 1)
		var hbind := -1
		var bind_xf: Array[Transform3D] = []
		for i in mi.skin.get_bind_count():
			if String(mi.skin.get_bind_name(i)) == "Head":
				hbind = i
			var b := skel.find_bone(mi.skin.get_bind_name(i))
			bind_xf.append((skel.get_bone_global_rest(b) if b >= 0 else Transform3D.IDENTITY) * mi.skin.get_bind_pose(i))
		var pos := PackedVector3Array()
		var hw := PackedFloat32Array()
		pos.resize(verts.size())
		hw.resize(verts.size())
		for v in verts.size():
			var p := Vector3.ZERO
			var w := 0.0
			for k in per:
				var wt := weights[v * per + k]
				var bi := bones[v * per + k]
				p += wt * (bind_xf[bi] * verts[v])
				if bi == hbind:
					w += wt
			pos[v] = (p - head_o) * unit
			hw[v] = w
		out = {"pos": pos, "hw": hw, "idx": arrays[Mesh.ARRAY_INDEX], "cols": arrays[Mesh.ARRAY_COLOR],
			"uv": arrays[Mesh.ARRAY_TEX_UV]}
		break
	inst.free()
	return out


func _measure(path: String) -> Dictionary:
	var b := _body(path)
	if b.is_empty():
		return {}
	var pos: PackedVector3Array = b.pos
	var hw: PackedFloat32Array = b.hw
	var cols: PackedColorArray = b.cols
	var uvs: PackedVector2Array = b.uv
	var idx: PackedInt32Array = b.idx
	if pos.is_empty() or uvs.is_empty():
		return {}
	# The eyes, split across the midline of the head's eye vertices.
	var all_eye: Array[int] = []
	var mid := 0.0
	for v in pos.size():
		if cols[v].b > 0.9 and cols[v].a > 0.9 and hw[v] > 0.5:
			all_eye.append(v)
			mid += pos[v].x
	if all_eye.size() < 20:
		return {}
	mid /= float(all_eye.size())
	var el: Array[int] = []
	var er: Array[int] = []
	var cl3 := Vector3.ZERO
	var cr3 := Vector3.ZERO
	for v in all_eye:
		if pos[v].x > mid:
			el.append(v)
			cl3 += pos[v]
		else:
			er.append(v)
			cr3 += pos[v]
	cl3 /= float(el.size())
	cr3 /= float(er.size())
	var e_mid := (cl3 + cr3) * 0.5
	var spacing := cl3.distance_to(cr3)
	var k := spacing * 0.5 / EYE_HALF
	var fit_l := _fit_eye(el, cl3, pos, uvs)
	var fit_r := _fit_eye(er, cr3, pos, uvs)
	# The face's skin triangles: skin (A) and not eye, head-weighted, in the face box.
	var face_tris: Array[int] = []
	var rect := Rect2()
	var have := false
	for t in idx.size() / 3:
		var ok := true
		for c in 3:
			var v := idx[t * 3 + c]
			var q := (pos[v] - e_mid) / k
			if cols[v].a < 0.5 or cols[v].b > 0.9 or hw[v] < 0.3 or q.z < -0.115 or q.y < -0.15 or q.y > 0.11:
				ok = false
				break
		if not ok:
			continue
		face_tris.append(t)
	# Only the face's own UV island (the biggest connected piece): the mouth's inside, the teeth
	# and stray head skin sit elsewhere in the atlas and would stretch the rect over half of it.
	face_tris = _main_island(face_tris, idx, uvs)
	for t in face_tris:
		for c in 3:
			var uv := uvs[idx[t * 3 + c]]
			if not have:
				rect = Rect2(uv, Vector2.ZERO)
				have = true
			else:
				rect = rect.expand(uv)
	rect = rect.grow(0.004)
	# The lid colour: the skin vertex nearest a point on the upper lid over each eye.
	var lid_l := _lid_uv(cl3, k, pos, cols, uvs, hw)
	var lid_r := _lid_uv(cr3, k, pos, cols, uvs, hw)
	# Rasterise the zones over the rect.
	var map := Image.create(TILE, TILE, false, Image.FORMAT_RGBA8)
	map.fill(Color(0, 0, 0, 0))
	var cover := PackedByteArray()
	cover.resize(TILE * TILE)
	for t in face_tris:
		var ia := idx[t * 3]
		var ib := idx[t * 3 + 1]
		var ic := idx[t * 3 + 2]
		var pa := (uvs[ia] - rect.position) / rect.size * float(TILE)
		var pb := (uvs[ib] - rect.position) / rect.size * float(TILE)
		var pc := (uvs[ic] - rect.position) / rect.size * float(TILE)
		var qa := (pos[ia] - e_mid) / k
		var qb := (pos[ib] - e_mid) / k
		var qc := (pos[ic] - e_mid) / k
		var lo := Vector2i(clampi(int(floor(minf(pa.x, minf(pb.x, pc.x)))), 0, TILE - 1), clampi(int(floor(minf(pa.y, minf(pb.y, pc.y)))), 0, TILE - 1))
		var hi := Vector2i(clampi(int(ceil(maxf(pa.x, maxf(pb.x, pc.x)))), 0, TILE - 1), clampi(int(ceil(maxf(pa.y, maxf(pb.y, pc.y)))), 0, TILE - 1))
		var den := (pb.y - pc.y) * (pa.x - pc.x) + (pc.x - pb.x) * (pa.y - pc.y)
		if absf(den) < 1e-9:
			continue
		for y in range(lo.y, hi.y + 1):
			for x in range(lo.x, hi.x + 1):
				var p := Vector2(x + 0.5, y + 0.5)
				var w0 := ((pb.y - pc.y) * (p.x - pc.x) + (pc.x - pb.x) * (p.y - pc.y)) / den
				var w1 := ((pc.y - pa.y) * (p.x - pc.x) + (pa.x - pc.x) * (p.y - pc.y)) / den
				var w2 := 1.0 - w0 - w1
				# A little outside the triangle too (half a texel), so edges meet.
				var m := -0.6 / maxf(absf(den), 1.0) * TILE
				if w0 < m or w1 < m or w2 < m:
					continue
				var q := qa * w0 + qb * w1 + qc * w2
				map.set_pixel(x, y, _zones(q))
				cover[y * TILE + x] = 1
	_dilate(map, cover, 2)
	var jl: Array = fit_l.j
	var jr: Array = fit_r.j
	return {"map": map, "rect": rect, "cl": fit_l.c, "jl": jl, "cr": fit_r.c, "jr": jr,
		"err": maxf(fit_l.err, fit_r.err), "lid_l": lid_l, "lid_r": lid_r, "spacing": spacing,
		"tris": face_tris.size()}


## The triangles of `tris` in the largest piece connected through shared UV positions.
func _main_island(tris: Array[int], idx: PackedInt32Array, uvs: PackedVector2Array) -> Array[int]:
	var parent := {}
	var key := func(v: int) -> Vector2i:
		return Vector2i(int(round(uvs[v].x * 65536.0)), int(round(uvs[v].y * 65536.0)))
	var find := func(find_ref: Callable, a: Vector2i) -> Vector2i:
		while parent[a] != a:
			parent[a] = parent[parent[a]]
			a = parent[a]
		return a
	for t in tris:
		var ks: Array[Vector2i] = []
		for c in 3:
			var kk: Vector2i = key.call(idx[t * 3 + c])
			if not parent.has(kk):
				parent[kk] = kk
			ks.append(kk)
		var r0: Vector2i = find.call(find, ks[0])
		for c in [1, 2]:
			var rc: Vector2i = find.call(find, ks[c])
			if rc != r0:
				parent[rc] = r0
	var count := {}
	for t in tris:
		var r: Vector2i = find.call(find, key.call(idx[t * 3]))
		count[r] = int(count.get(r, 0)) + 1
	var best: Vector2i
	var bn := -1
	for r in count:
		if count[r] > bn:
			bn = count[r]
			best = r
	var out: Array[int] = []
	for t in tris:
		if find.call(find, key.call(idx[t * 3])) == best:
			out.append(t)
	return out


func _g(x: float, y: float) -> float:
	return exp(-(x * x + y * y))


## The zones at q (head frame, average-face metres from the eyes' midpoint; x to the rig's left,
## y up, z forward). Smooth fields, no edges: the shader multiplies, and a hard edge would print.
func _zones(q: Vector3) -> Color:
	var ax := absf(q.x)
	var front := clampf((q.z + 0.045) / 0.03, 0.0, 1.0)
	var ex := ax - EYE_HALF
	# Blood: the cheeks (the apples, low and out), the nose (tip and wings), the lips, the ears,
	# a touch on the chin and the forehead.
	var cheeks := _g((ax - 0.036) / 0.019, (q.y + 0.038) / 0.017) * front
	var nose := _g(q.x / 0.014, (q.y + 0.042) / 0.016) * front
	var lips := _g(q.x / 0.025, (q.y + 0.069) / 0.0105) * front
	var chin := _g(q.x / 0.022, (q.y + 0.105) / 0.016) * front * 0.35
	var brow := _g(q.x / 0.05, (q.y - 0.05) / 0.02) * front * 0.2
	var ears := clampf((ax - 0.062) / 0.01, 0.0, 1.0) * (1.0 - front) * clampf((q.y + 0.05) / 0.02, 0.0, 1.0) * clampf((0.04 - q.y) / 0.02, 0.0, 1.0)
	var blood := clampf(cheeks * 0.8 + nose * 0.75 + lips + chin + brow + ears * 0.7, 0.0, 1.0)
	# Cavity: under each eye (the tear trough and the bag's shadow), the inner corners by the
	# bridge, the upper lid's crease, the nose wings' crease and nostrils, the mouth corners and
	# the line between the lips.
	var trough := _g(ex / 0.017, (q.y + 0.016) / 0.007) * front
	var inner := _g((ax - 0.015) / 0.006, (q.y + 0.002) / 0.007) * front
	var crease := _g(ex / 0.016, (q.y - 0.011) / 0.004) * front * 0.55
	var wings := _g((ax - 0.017) / 0.005, (q.y + 0.047) / 0.007) * front
	var corners := _g((ax - 0.026) / 0.005, (q.y + 0.07) / 0.005) * front * 0.8
	var lip_line := _g(q.x / 0.022, (q.y + 0.0685) / 0.0018) * front * 0.7
	# The brows' roots under the hair cards (the cards alone read as a pen line): an arch over each
	# eye, densest at the inner end.
	var bx := ax - 0.03
	var brow_root := _g(bx / 0.019, (q.y - (0.026 - bx * bx * 9.0)) / 0.0045) * front * (0.75 + 0.25 * clampf(-bx / 0.015, 0.0, 1.0))
	var cavity := clampf(trough * 0.9 + inner * 0.8 + crease + wings * 0.9 + corners + lip_line + brow_root * 0.85, 0.0, 1.0)
	# Oil: the forehead, the nose bridge and tip, the chin.
	var forehead := _g(q.x / 0.04, (q.y - 0.045) / 0.022) * front
	var bridge := _g(q.x / 0.01, (q.y + 0.025) / 0.03) * front
	var chin_o := _g(q.x / 0.018, (q.y + 0.103) / 0.012) * front
	var oil := clampf(forehead * 0.85 + bridge + chin_o * 0.7, 0.0, 1.0)
	# Lips 1.0; thin skin 0.5 (ears, nose wings).
	var lip_mask := clampf((1.0 - pow((q.x / 0.026), 2.0) - pow((q.y + 0.069) / 0.0115, 2.0)) * 4.0, 0.0, 1.0) * front
	var thin := maxf(ears, _g((ax - 0.017) / 0.006, (q.y + 0.045) / 0.008) * front)
	var a := maxf(lip_mask, minf(thin, 1.0) * 0.5 * (1.0 - lip_mask))
	return Color(blood, cavity, oil, a)


func _fit_eye(ids: Array[int], c3: Vector3, pos: PackedVector3Array, uvs: PackedVector2Array) -> Dictionary:
	# Least squares uv = c + J d over the front of the eyeball (d the unit direction from its
	# centre): normal equations of [1, dx, dy].
	var ata := Basis()
	var s := [0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0]
	var bu := Vector3.ZERO
	var bv := Vector3.ZERO
	var used: Array = []
	for v in ids:
		var d := (pos[v] - c3).normalized()
		if d.z < 0.55:
			continue
		var r := Vector3(1.0, d.x, d.y)
		for i in 3:
			for j in 3:
				s[i * 3 + j] += r[i] * r[j]
		bu += r * uvs[v].x
		bv += r * uvs[v].y
		used.append([d, uvs[v]])
	ata = Basis(Vector3(s[0], s[3], s[6]), Vector3(s[1], s[4], s[7]), Vector3(s[2], s[5], s[8]))
	if absf(ata.determinant()) < 1e-12:
		return {"c": Vector2.ZERO, "j": [0.0, 0.0, 0.0, 0.0], "err": 1.0}
	var inv := ata.inverse()
	var xu := inv * bu
	var xv := inv * bv
	var err := 0.0
	for rec: Array in used:
		var d: Vector3 = rec[0]
		var uv: Vector2 = rec[1]
		var p := Vector2(xu.x + xu.y * d.x + xu.z * d.y, xv.x + xv.y * d.x + xv.z * d.y)
		err = maxf(err, p.distance_to(uv))
	return {"c": Vector2(xu.x, xv.x), "j": [xu.y, xu.z, xv.y, xv.z], "err": err}


## The outer skin of the upper lid over an eye: of the skin in a small column over the eye's centre,
## the vertex furthest forward (the socket's inner lid, pink, is further back).
func _lid_uv(c3: Vector3, k: float, pos: PackedVector3Array, cols: PackedColorArray, uvs: PackedVector2Array, hw: PackedFloat32Array) -> Vector2:
	var best := -1e9
	var out := Vector2.ZERO
	for v in pos.size():
		if cols[v].a < 0.5 or cols[v].b > 0.9 or hw[v] < 0.5:
			continue
		var q := (pos[v] - c3) / k
		if absf(q.x) > 0.005 or q.y < 0.013 or q.y > 0.022:
			continue
		if pos[v].z > best:
			best = pos[v].z
			out = uvs[v]
	if best < -1e8:
		return _nearest_skin_uv(c3 + Vector3(0.0, 0.019, 0.006) * k, pos, cols, uvs, hw)
	return out


func _nearest_skin_uv(p: Vector3, pos: PackedVector3Array, cols: PackedColorArray, uvs: PackedVector2Array, hw: PackedFloat32Array) -> Vector2:
	var best := 1e9
	var out := Vector2.ZERO
	for v in pos.size():
		if cols[v].a < 0.5 or cols[v].b > 0.9 or hw[v] < 0.5:
			continue
		var d := pos[v].distance_squared_to(p)
		if d < best:
			best = d
			out = uvs[v]
	return out


## Grows the covered texels outward `n` times, so bilinear filtering at an island's edge never
## pulls in the empty background.
func _dilate(img: Image, cover: PackedByteArray, n: int) -> void:
	for it in n:
		var add: Array = []
		for y in TILE:
			for x in TILE:
				if cover[y * TILE + x] != 0:
					continue
				var acc := Color(0, 0, 0, 0)
				var cnt := 0
				for o: Vector2i in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
					var nx := x + o.x
					var ny := y + o.y
					if nx >= 0 and ny >= 0 and nx < TILE and ny < TILE and cover[ny * TILE + nx] != 0:
						acc += img.get_pixel(nx, ny)
						cnt += 1
				if cnt > 0:
					add.append([x, y, acc / float(cnt)])
		for a: Array in add:
			img.set_pixel(a[0], a[1], a[2])
			cover[a[1] * TILE + a[0]] = 1
