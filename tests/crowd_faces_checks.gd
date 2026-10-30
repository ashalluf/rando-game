extends RefCounted
## The crowd's faces up close (CrowdFaces, character.gdshader's face pass), for tests/smoke_test.gd.
## Loaded at run time, not named there, so it compiles after the autoloads. Reads files, builds its
## own rig and materials: nothing here leans on where an earlier check left the player or the crowd.

var _t: Node


func run(t: Node, _city: Node3D) -> void:
	_t = t
	var ped: Script = load("res://scripts/npc/pedestrian.gd")
	var faces: Script = load("res://scripts/npc/crowd_faces.gd")
	var table_s: Script = load("res://scripts/npc/crowd_face_table.gd")
	var table: Dictionary = table_s.TABLE
	# the table: a row per crowd rig, tiles unique, rects and eyes inside the atlas, each eye's map
	# a mirror of the other's across (the MakeHuman eyes' UVs are mirrored) and well conditioned
	var models: Array = Array(ped.MODELS)
	var rows := table.size() == models.size()
	var tiles := {}
	var sane := true
	for path: String in models:
		var key := path.get_file().get_basename()
		if not table.has(key):
			rows = false
			continue
		var r: Dictionary = table[key]
		tiles[int(r.tile)] = true
		var rect: Array = r.rect
		sane = sane and rect[0] >= -0.01 and rect[1] >= -0.01 and rect[0] + rect[2] <= 1.01 and rect[1] + rect[3] <= 1.01
		sane = sane and rect[2] > 0.05 and rect[3] > 0.05 and rect[2] < 0.5 and rect[3] < 0.6
		for e in ["eye_l", "eye_r"]:
			var v: Array = r[e]
			var det: float = v[2] * v[5] - v[3] * v[4]
			sane = sane and v[0] > 0.0 and v[0] < 1.0 and v[1] > 0.0 and v[1] < 1.0 and absf(det) > 0.001
		var el: Array = r.eye_l
		var er: Array = r.eye_r
		sane = sane and signf(el[2]) == -signf(er[2]) and absf(absf(el[2]) - absf(er[2])) < 0.01
		var lid: Array = r.lid
		for x: float in lid:
			sane = sane and x > 0.0 and x < 1.0
	_t._check(rows, "crowd-faces: CrowdFaceTable has a row for every Pedestrian.MODELS rig (rerun tools/crowd_faces/face_fit.gd after a rig changes)")
	_t._check(tiles.size() == table.size() and table.size() <= table_s.COLS * table_s.ROWS, "crowd-faces: one face-atlas tile per rig, all inside the atlas")
	_t._check(sane, "crowd-faces: face rects, eye centres, eye maps (mirrored across, invertible) and lid samples all in the atlas")
	# the atlas: the size the table says, lossless (the zones are data, not a picture)
	var tex := load(faces.ATLAS) as Texture2D
	_t._check(tex != null and tex.get_width() == table_s.TILE * table_s.COLS and tex.get_height() == table_s.TILE * table_s.ROWS,
		"crowd-faces: crowd_faces.png is COLS x ROWS tiles of TILE")
	var imp := FileAccess.get_file_as_string(faces.ATLAS + ".import")
	_t._check(imp.contains("compress/mode=0") and imp.contains("detect_3d/compress_to=0"), "crowd-faces: the face atlas is imported lossless and never VRAM-compressed")
	# the shader: the pass is one branch, inside face_reach of the camera; per-person timing from the
	# instance's scale; the blink's numbers are CrowdFaces'
	var src := FileAccess.get_file_as_string("res://shaders/character.gdshader")
	_t._check(src.contains("face_pass > 0.5 && region_mask > 0.5 && face_dist < face_reach") and faces.REACH <= 12.0,
		"crowd-faces: the face pass costs only within face_reach (<= 12 m) of the camera, on the crowd rigs")
	_t._check(src.contains("varying flat float v_face_seed") and src.contains("length(MODEL_MATRIX[0].xyz)"),
		"crowd-faces: each person's blink and gaze phase comes from the instance's own scale (no per-person material)")
	var nums := "float slot = floor(t / %.1f)" % faces.BLINK_SLOT
	_t._check(src.contains(nums) and src.contains("dt < %.2f ? dt / %.2f" % [faces.BLINK_CLOSE, faces.BLINK_CLOSE]) \
		and src.contains("(dt < %.1f ? 1.0" % faces.BLINK_SHUT) and src.contains("(dt - %.1f) / %.2f" % [faces.BLINK_SHUT, faces.BLINK_OPEN]),
		"crowd-faces: the shader's blink timing matches CrowdFaces.blink()")
	_t._check(not src.contains("instance uniform"), "crowd-faces: no instance uniforms in the character shader (the Compatibility global buffer)")
	# the blink, through the GDScript mirror: 2 minutes of two people
	var counts := [0, 0]
	var together := 0
	var closed := 0
	var shut_seen := false
	for p in 2:
		var seed := 0.137 + 0.41 * float(p)
		var was := false
		for i in 120 * 50:
			var tt := float(i) / 50.0
			var b: float = faces.blink(seed, tt)
			shut_seen = shut_seen or b >= 0.999
			var now := b > 0.5
			if now and not was:
				counts[p] += 1
			was = now
	for i in 120 * 50:
		var tt := float(i) / 50.0
		var a: bool = faces.blink(0.137, tt) > 0.5
		closed += 1 if a else 0
		if a and faces.blink(0.547, tt) > 0.5:
			together += 1
	_t._check(counts[0] >= 24 and counts[0] <= 50 and counts[1] >= 24 and counts[1] <= 50 and shut_seen,
		"crowd-faces: a person blinks %d / %d times a minute (12-25), fully shut for an instant" % [counts[0] / 2, counts[1] / 2])
	# In step, every closed frame would be shared; by chance about one in twenty is.
	_t._check(closed > 0 and together * 3 < closed, "crowd-faces: two people do not blink in step (%d of %d closed frames shared in 2 minutes)" % [together, closed])
	# a crowd rig prepared as the game does: its look carries the pass and its rig's row
	var inst: Node3D = (load("res://assets/models/crowd_j.glb") as PackedScene).instantiate()
	_t.add_child(inst)
	ped.prepare_rig(inst, 5)
	var mat: ShaderMaterial = null
	for n in inst.find_children("*", "MeshInstance3D", true, false):
		if not ped.is_hair(n as MeshInstance3D) and (n as MeshInstance3D).material_override is ShaderMaterial:
			mat = (n as MeshInstance3D).material_override
	var row: Dictionary = table.get("crowd_j", {})
	var on := mat != null and float(mat.get_shader_parameter("face_pass")) == 1.0 and not row.is_empty() \
		and (mat.get_shader_parameter("face_rect") as Vector4).is_equal_approx(Vector4(row.rect[0], row.rect[1], row.rect[2], row.rect[3]))
	_t._check(on, "crowd-faces: a crowd look material carries the face pass and its rig's face rect")
	# the pass sets only face uniforms (no rolls: nothing a seed builds moves), and CROWD_FACES=0 sets none
	if mat:
		var bare := ShaderMaterial.new()
		bare.shader = mat.shader
		for u in mat.shader.get_shader_uniform_list():
			var nm: String = u.name
			if not _face_param(nm):
				bare.set_shader_parameter(nm, mat.get_shader_parameter(nm))
		var copy := bare.duplicate() as ShaderMaterial
		var albedo: Texture2D = mat.get_shader_parameter("albedo_tex")
		faces.apply(copy, albedo)
		var only_face := true
		for u in mat.shader.get_shader_uniform_list():
			var nm: String = u.name
			if not _face_param(nm) and copy.get_shader_parameter(nm) != bare.get_shader_parameter(nm):
				only_face = false
		_t._check(only_face and float(copy.get_shader_parameter("face_pass")) == 1.0, "crowd-faces: CrowdFaces.apply() touches only the face pass's own uniforms")
		var was_on: int = faces._on
		faces._on = 0
		var off := bare.duplicate() as ShaderMaterial
		faces.apply(off, albedo)
		faces._on = was_on
		var pass_off = off.get_shader_parameter("face_pass")
		_t._check(pass_off == null or float(pass_off) == 0.0, "crowd-faces: CROWD_FACES=0 leaves the pass off (the A/B)")
	inst.queue_free()


func _face_param(nm: String) -> bool:
	return nm.begins_with("face_") or nm.begins_with("eye_l") or nm.begins_with("eye_r") or nm == "lid_uv"
