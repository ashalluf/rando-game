extends SceneTree
## Measures every crowd rig's head for its headwear (CrowdHat) and writes the table the hats are
## built from, scripts/npc/crowd_hat_table.gd. Rerun it whenever a crowd rig is rebuilt
## (tools/crowd/build.sh) - CrowdHat falls back to a generic head for a rig it has no row for,
## and the smoke test fails when the table and Pedestrian.MODELS disagree.
##
##   LIBGL_ALWAYS_SOFTWARE=1 xvfb-run -a -s "-screen 0 640x480x24" godot --rendering-driver opengl3 \
##     --display-driver x11 --audio-driver Dummy --path . --script tools/crowd/hat_fit.gd
##
## It needs mesh data, so never --headless (the dummy renderer keeps none). Seconds.
##
## What it measures, in the HEAD FRAME: metres, the skeleton's own axes (y up, z the way the rig
## faces), origin at the Head bone's rest position - the frame CrowdHat builds in.
##   - the eye centre (the body's eye vertices: the region colour says B and A both full),
##   - the ear top (the highest of the head's lateral-most vertices),
##   - a centre C at eye height, half way between the back of the skull and the forehead,
##   - the skull's radius from C on a grid of directions (ROWS elevations from PHI0 in PHI_STEP,
##     COLS azimuths from the front, 0 = +z, positive toward +x), by casting rays in at the head's
##     triangles (those weighted to the Head bone); then the ears taken out (a robust low-order fit
##     round each ring: a cap's band runs over the ear tops and a bulge there would lift it) and
##     the two sides averaged (the MakeHuman head is symmetric, the decimation is not quite),
##   - the hair's thickness over the skull on the same grid (rays at the Hair mesh's cards,
##     leaving out the brows and lashes): how much a hat has to make room for, and whether the
##     cards can be pressed under one (`hair`: "press") or are too much to (`hair`: "hide").
## REPORT=1 instead builds every hat of CrowdHat on every rig from the table already written and
## measures it against the real head: how far the skull comes through the hat (it must not) and
## how wide the gap is at the band edge, plus the triangle counts per level.
const OUT := "res://scripts/npc/crowd_hat_table.gd"
const PHI0 := -30.0
const PHI_STEP := 7.5
const ROWS := 17
const COLS := 32
## Hair thicker than this (metres, the median over the crown) is hidden under a hat, not pressed.
const HIDE_HAIR_OVER := 0.04


func _initialize() -> void:
	var ped = load("res://scripts/npc/pedestrian.gd")
	var models: Array = Array(ped.MODELS)
	if OS.get_environment("MODELS") != "":
		models = Array(OS.get_environment("MODELS").split(","))
	if OS.get_environment("REPORT") == "1":
		_report(models)
		quit()
		return
	var rows: Array[String] = []
	for path: String in models:
		var m := _measure(path)
		if m.is_empty():
			print("FIT ", path, ": no mesh data (run under opengl3, not --headless)")
			continue
		rows.append(_row(path.get_file(), m))
		print("FIT %s: eye y %.3f z %.3f, ear top %.3f, C %s, top %.3f, hair %s (crown median %.1f mm)" % [
			path.get_file(), m.eye.y, m.eye.z, m.ear.y, m.c, m.top, m.hair, m.hair_med * 1000.0])
	var f := FileAccess.open(OUT, FileAccess.WRITE)
	f.store_string("class_name CrowdHatTable\nextends RefCounted\n")
	f.store_string("## WRITTEN BY tools/crowd/hat_fit.gd - do not edit by hand; run the tool again instead.\n")
	f.store_string("## Per crowd rig, its head in the head frame (metres, skeleton axes, origin at the Head bone's\n")
	f.store_string("## rest position): c the centre the grids are measured from, eye [y, z], ear [top y, |x|, z],\n")
	f.store_string("## top (crown height), hair (\"press\" or \"hide\" under a hat), skull (radius from c in tenths\n")
	f.store_string("## of a millimetre, ROWS elevations x COLS azimuths, row-major) and hair_t (the hair's\n")
	f.store_string("## thickness over it in millimetres, same grid). See CrowdHat.Head.\n")
	f.store_string("const PHI0 := %.1f\nconst PHI_STEP := %.1f\nconst ROWS := %d\nconst COLS := %d\n" % [PHI0, PHI_STEP, ROWS, COLS])
	f.store_string("const TABLE := {\n")
	for r in rows:
		f.store_string(r)
	f.store_string("}\n")
	f.close()
	print("FIT wrote ", OUT, " (", rows.size(), " rigs)")
	quit()


func _row(key: String, m: Dictionary) -> String:
	var skull := PackedStringArray()
	for v: float in m.skull:
		skull.append(str(int(round(v * 10000.0))))
	var hair := PackedStringArray()
	for v: float in m.hair_t:
		hair.append(str(int(round(v * 1000.0))))
	return "\t\"%s\": {\"c\": [%.4f, %.4f, %.4f], \"eye\": [%.4f, %.4f], \"ear\": [%.4f, %.4f, %.4f], \"top\": %.4f, \"hair\": \"%s\",\n\t\t\"skull\": [%s],\n\t\t\"hair_t\": [%s]},\n" % [
		key, m.c.x, m.c.y, m.c.z, m.eye.y, m.eye.z, m.ear.y, m.ear.x, m.ear.z, m.top, m.hair,
		", ".join(skull), ", ".join(hair)]


## The rig's meshes in the head frame: {name: {pos, hw (Head weight), idx, cols}}, or {} without
## mesh data.
func _head_frame(path: String) -> Dictionary:
	var inst: Node3D = (load(path) as PackedScene).instantiate()
	get_root().add_child(inst)
	var skel := inst.find_child("Skeleton3D", true, false) as Skeleton3D
	var out := {}
	if skel == null or skel.find_bone("Head") < 0:
		inst.free()
		return out
	var hb := skel.find_bone("Head")
	var unit := 1.0
	var node: Node3D = skel
	while node != null and node != inst:
		unit *= node.transform.basis.get_scale().y
		node = node.get_parent() as Node3D
	var head_o := skel.get_bone_global_rest(hb).origin
	for n in inst.find_children("*", "MeshInstance3D", true, false):
		var mi := n as MeshInstance3D
		if mi.skin == null or mi.mesh == null:
			continue
		var arrays := mi.mesh.surface_get_arrays(0)
		if arrays.is_empty() or arrays[Mesh.ARRAY_BONES] == null:
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
		out[String(mi.name)] = {"pos": pos, "hw": hw, "idx": arrays[Mesh.ARRAY_INDEX], "cols": arrays[Mesh.ARRAY_COLOR]}
	inst.free()
	return out


func _tri_mesh(faces: PackedVector3Array) -> TriangleMesh:
	if faces.is_empty():
		return null
	var am := ArrayMesh.new()
	var arr := []
	arr.resize(Mesh.ARRAY_MAX)
	arr[Mesh.ARRAY_VERTEX] = faces
	am.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arr)
	return am.generate_triangle_mesh()


static func dir(th: float, ph: float) -> Vector3:
	return Vector3(sin(th) * cos(ph), sin(ph), cos(th) * cos(ph))


## Radius from c along each grid direction to the first surface of `tm` met coming in from
## outside, or -1 where the ray finds nothing.
func _cast(tm: TriangleMesh, c: Vector3) -> PackedFloat32Array:
	var out := PackedFloat32Array()
	out.resize(ROWS * COLS)
	for i in ROWS:
		var ph := deg_to_rad(PHI0 + PHI_STEP * i)
		for j in COLS:
			var th := TAU * float(j) / float(COLS)
			var d := dir(th, ph)
			# Four rays a millimetre apart, the outermost hit kept: a ray down the head's middle
			# runs along the mirror seam's edges, where it can slip through between two
			# triangles and find the inside of the face.
			var side := d.cross(Vector3.UP if absf(d.y) < 0.9 else Vector3.RIGHT).normalized()
			var up := side.cross(d).normalized()
			var best := -1.0
			if tm:
				for o: Vector2 in [Vector2(0.0011, 0.0004), Vector2(-0.0009, 0.0007), Vector2(0.0003, -0.0012), Vector2(-0.0006, -0.0008)]:
					var start := c + d * 0.6 + side * o.x + up * o.y
					var r: Dictionary = tm.intersect_ray(start, -d)
					if not r.is_empty():
						best = maxf(best, ((r.position as Vector3) - c).dot(d))
			out[i * COLS + j] = best
	return out


func _measure(path: String) -> Dictionary:
	var data := _head_frame(path)
	if not data.has("Body"):
		return {}
	var body: Dictionary = data["Body"]
	var bp: PackedVector3Array = body.pos
	var bw: PackedFloat32Array = body.hw
	var cols = body.cols
	if bp.is_empty() or cols == null:
		return {}
	# The eyes: the region colour's "eye" (B and A both full) on head vertices.
	var eye := Vector3.ZERO
	var ne := 0
	for v in bp.size():
		var col: Color = cols[v]
		if col.b > 0.9 and col.a > 0.9 and bw[v] > 0.5:
			eye += bp[v]
			ne += 1
	if ne == 0:
		return {}
	eye /= float(ne)
	var zmin := 1e9
	var zmax := -1e9
	var top := -1e9
	var half := 0.0
	for v in bp.size():
		if bw[v] < 0.5:
			continue
		var p := bp[v]
		top = maxf(top, p.y)
		if p.y > eye.y + 0.03:
			zmin = minf(zmin, p.z)
			zmax = maxf(zmax, p.z)
		if p.y > eye.y - 0.03 and p.y < eye.y + 0.04:
			half = maxf(half, absf(p.x - eye.x))
	# Centred on the eyes across: the Head bone's origin is a few millimetres off the head's
	# middle on some rigs.
	var c := Vector3(eye.x, eye.y, (zmin + zmax) * 0.5)
	# The ear top: the highest head vertex standing within 6 mm of the head's widest point
	# round eye height (that is the ear, whose top sits about level with the brows).
	var ear := Vector3(half, eye.y, c.z)
	for v in bp.size():
		var p := bp[v]
		if bw[v] > 0.5 and absf(p.x - eye.x) > half - 0.006 and absf(p.y - eye.y) < 0.05 and p.y > ear.y:
			ear = Vector3(absf(p.x - eye.x), p.y, p.z)
	# The skull: rays at the head-weighted triangles.
	var faces := PackedVector3Array()
	var idx: PackedInt32Array = body.idx
	for t in idx.size() / 3:
		var a := idx[t * 3]
		var b := idx[t * 3 + 1]
		var e := idx[t * 3 + 2]
		if bw[a] < 0.3 or bw[b] < 0.3 or bw[e] < 0.3:
			continue
		faces.append(bp[a])
		faces.append(bp[b])
		faces.append(bp[e])
	var skull := _cast(_tri_mesh(faces), c)
	_fill_misses(skull)
	_remove_ears(skull, atan2(ear.x, ear.z - c.z))
	_symmetrise(skull)
	_smooth(skull, 1)
	# The hair: its cards, less the brows and lashes (in front of the face, below the forehead).
	var hair_t := PackedFloat32Array()
	hair_t.resize(ROWS * COLS)
	var crown: Array = []
	if data.has("Hair"):
		var hd: Dictionary = data["Hair"]
		var hp: PackedVector3Array = hd.pos
		var hidx: PackedInt32Array = hd.idx
		var hfaces := PackedVector3Array()
		for t in hidx.size() / 3:
			var a := hp[hidx[t * 3]]
			var b := hp[hidx[t * 3 + 1]]
			var e := hp[hidx[t * 3 + 2]]
			var m := (a + b + e) / 3.0
			if m.z > c.z + 0.035 and m.y < eye.y + 0.04:
				continue
			hfaces.append(a)
			hfaces.append(b)
			hfaces.append(e)
		var hr := _cast(_tri_mesh(hfaces), c)
		for k in hr.size():
			hair_t[k] = clampf(hr[k] - skull[k], 0.0, 0.08) if hr[k] > 0.0 else 0.0
		# Over the crown (from 20 degrees up), where a hat sits.
		for i in ROWS:
			if PHI0 + PHI_STEP * i < 20.0:
				continue
			for j in COLS:
				crown.append(hair_t[i * COLS + j])
	_smooth(hair_t, 2)
	crown.sort()
	var med: float = crown[crown.size() / 2] if not crown.is_empty() else 0.0
	return {"c": c, "eye": Vector3(0.0, eye.y, eye.z), "ear": ear, "top": top,
		"skull": skull, "hair_t": hair_t, "hair": "hide" if med > HIDE_HAIR_OVER else "press", "hair_med": med}


## A ray that found no head (low at the back, where the neck takes the weight) takes the ring
## above it.
func _fill_misses(g: PackedFloat32Array) -> void:
	for i in range(ROWS - 2, -1, -1):
		for j in COLS:
			if g[i * COLS + j] <= 0.0:
				g[i * COLS + j] = g[(i + 1) * COLS + j]


## The ears stand off the skull round azimuth +-`ear_th` near eye height, and a cap's band
## runs just over their tops: a bulge there would lift it off the head. In the rows round eye
## height, every sample within EAR_WINDOW of an ear that stands more than 2 mm proud of the line
## between the samples either side of the window is put back on that line. (A fit of the whole
## ring does not do: the nose and the back of the skull are no smoother than an ear.)
const EAR_WINDOW := 0.62
func _remove_ears(g: PackedFloat32Array, ear_th: float) -> void:
	for i in ROWS:
		var ph := PHI0 + PHI_STEP * i
		if ph > 30.0:
			continue
		# The window on the +x side, in columns: ja and jb are the samples just outside it.
		var ja := int(floor((ear_th - EAR_WINDOW) / TAU * COLS))
		var jb := int(ceil((ear_th + EAR_WINDOW) / TAU * COLS))
		for side in [1, -1]:
			# The -x side is the mirror image: column j there is COLS - j.
			var ca := posmod(side * ja, COLS)
			var cb := posmod(side * jb, COLS)
			var ra := g[i * COLS + ca]
			var rb := g[i * COLS + cb]
			for k in range(1, jb - ja):
				var j := posmod(side * (ja + k), COLS)
				var line := lerpf(ra, rb, float(k) / float(jb - ja))
				if g[i * COLS + j] > line + 0.002:
					g[i * COLS + j] = line + 0.001


func _symmetrise(g: PackedFloat32Array) -> void:
	for i in ROWS:
		for j in range(1, COLS / 2):
			var a := g[i * COLS + j]
			var b := g[i * COLS + COLS - j]
			g[i * COLS + j] = (a + b) * 0.5
			g[i * COLS + COLS - j] = (a + b) * 0.5


## A 1-2-1 blur round each ring and up each meridian, `passes` times (the top ring is one point).
func _smooth(g: PackedFloat32Array, passes: int) -> void:
	for p in passes:
		var o := g.duplicate()
		for i in ROWS:
			for j in COLS:
				var l := o[i * COLS + (j + COLS - 1) % COLS]
				var r := o[i * COLS + (j + 1) % COLS]
				var dn := o[maxi(i - 1, 0) * COLS + j]
				var up := o[mini(i + 1, ROWS - 1) * COLS + j]
				g[i * COLS + j] = (4.0 * o[i * COLS + j] + l + r + dn + up) / 8.0
		var mean := 0.0
		for j in COLS:
			mean += g[(ROWS - 1) * COLS + j]
		mean /= float(COLS)
		for j in COLS:
			g[(ROWS - 1) * COLS + j] = mean


## REPORT=1: every hat on every rig, against the real head. CrowdHat is loaded by path: this
## script compiles before the table it writes is read back.
func _report(models: Array) -> void:
	var hat = load("res://scripts/npc/crowd_hat.gd")
	var names := ["cap", "beanie", "bucket", "peaked"]
	for path: String in models:
		var data := _head_frame(path)
		if not data.has("Body"):
			print("HAT ", path.get_file(), ": no mesh data")
			continue
		var body: Dictionary = data["Body"]
		var bpos: PackedVector3Array = body.pos
		var bw: PackedFloat32Array = body.hw
		var head = hat.head_for(path)
		var c: Vector3 = head.c
		for kind: int in [0, 1, 2, 3]:
			var t0 := Time.get_ticks_usec()
			var mesh: ArrayMesh = hat.build_mesh(path, kind)
			var ms := float(Time.get_ticks_usec() - t0) / 1000.0
			var tm := mesh.generate_triangle_mesh()
			var worst := 1.0
			var gaps: Array[float] = []
			var edge_gaps: Array[float] = []
			var through := 0
			var covered := 0
			for v in bpos.size():
				if bw[v] < 0.5:
					continue
				var p: Vector3 = bpos[v]
				var d: Vector3 = p - c
				var r: float = d.length()
				if r < 0.03:
					continue
				d /= r
				var th: float = atan2(d.x, d.z)
				var ph: float = asin(clampf(d.y, -1.0, 1.0))
				var pe: float = hat.edge_phi(head, kind, th)
				if ph < pe:
					continue
				covered += 1
				# Coming in from outside, the first cloth met is the hat's outside: the head is
				# through the hat wherever that is short of the vertex. (Its inside - the
				# sweatband, the knit - may touch the skin; that is a hat sitting on a head.)
				var hit: Dictionary = tm.intersect_ray(c + d * 0.4, -d)
				if hit.is_empty():
					continue
				var gap: float = ((hit.position as Vector3) - c).length() - r
				worst = minf(worst, gap)
				if gap < 0.0:
					through += 1
				gaps.append(gap)
				if ph < pe + 0.08:
					edge_gaps.append(gap)
			gaps.sort()
			edge_gaps.sort()
			var med: float = gaps[gaps.size() / 2] if not gaps.is_empty() else 0.0
			var e_lo: float = edge_gaps[0] if not edge_gaps.is_empty() else 0.0
			var e_hi: float = edge_gaps[edge_gaps.size() - 1] if not edge_gaps.is_empty() else 0.0
			print("HAT %s %s: tris per level %s, built in %.0f ms; %d head vertices covered, %d through, outside closest %.1f mm, median %.1f mm, at the band %.1f..%.1f mm" % [
				path.get_file(), names[kind], str(hat.lod_triangles(mesh)), ms, covered, through, worst * 1000.0,
				med * 1000.0, e_lo * 1000.0, e_hi * 1000.0])
