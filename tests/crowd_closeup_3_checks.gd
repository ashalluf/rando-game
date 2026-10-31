extends RefCounted
## The crowd at 2-6 m, third pass (CrowdCloseup3; docs/HANDOFF.md "The crowd up close, third
## pass"), for tests/smoke_test.gd. Loaded at run time, not named there, so it compiles after the
## autoloads. Builds its own rigs and materials: leans on nothing an earlier check left.

var _t: Node


func run(t: Node, _city: Node3D) -> void:
	_t = t
	var ped: Script = load("res://scripts/npc/pedestrian.gd")
	var cc: Script = load("res://scripts/npc/crowd_closeup_3.gd")
	var table: Dictionary = load("res://scripts/npc/crowd_stride_table.gd").TABLE
	# the stride table: a row for every rig, speeds a person's feet can have
	var models: Array = Array(ped.MODELS)
	var rows := true
	var sane := true
	for path: String in models:
		var key := path.get_file().get_basename()
		if not table.has(key):
			rows = false
			continue
		var r: Dictionary = table[key]
		sane = sane and float(r.walk) > 0.5 and float(r.walk) < 1.1 and float(r.run) > 2.0 and float(r.run) < 4.2 \
			and float(r.jog) > 2.0 and float(r.jog) < 4.6 and float(r.run) > 2.5 * float(r.walk)
	_t._check(rows, "crowd-closeup-3: CrowdStrideTable has a row for every Pedestrian.MODELS rig (rerun tools/crowd_closeup_3/stride_fit.gd WRITE=1 after a rig changes)")
	_t._check(sane, "crowd-closeup-3: every rig's measured walk (0.5-1.1 m/s), run and jog speeds are a person's")
	# the table is what the rigs do now: two rigs measured again here, the planted toe's backward
	# speed in the rig's own walk (a rebuild that moved the legs without a rerun fails this)
	for key in ["crowd_a", "crowd_n"]:
		var path := "res://assets/models/%s.glb" % key
		if not table.has(key) or not ResourceLoader.exists(path):
			continue
		var got := await _walk_speed(path)
		_t._check(absf(got - float(table[key].walk)) < 0.03 * float(table[key].walk) + 0.005,
			"crowd-closeup-3: %s's walk measures %.3f m/s, the table says %.3f" % [key, got, float(table[key].walk)])
	# a walker on the rig's own clip takes the rig's speed; one on a gait clip keeps the clip's
	var p = ped.new()
	p._model_path = "res://assets/models/crowd_n.glb"
	p._walk_clip = ped.WALK_CLIP
	cc.fit_strides(p)
	var row: Dictionary = table.get("crowd_n", {})
	_t._check(not row.is_empty() and is_equal_approx(p._walk_clip_speed, float(row.walk)) and is_equal_approx(p._run_clip_speed, float(row.run))
		and is_equal_approx(p._jog_clip_speed, float(row.jog)), "crowd-closeup-3: a walker on its rig's own clips plays them at the rig's measured speeds")
	var q = ped.new()
	q._model_path = "res://assets/models/crowd_n.glb"
	q._walk_clip = "gait/casual"
	q._walk_clip_speed = 0.93
	cc.fit_strides(q)
	_t._check(is_equal_approx(q._walk_clip_speed, 0.93) and is_equal_approx(q._run_clip_speed, float(row.get("run", 0.0))),
		"crowd-closeup-3: a walker on a gait-library clip keeps that clip's own speed (its run is the rig's)")
	p.free()
	q.free()
	# the rate maths reads the fitted speeds (no constant left for the run and the jog)
	var src := FileAccess.get_file_as_string("res://scripts/npc/pedestrian.gd")
	_t._check(src.contains("rate = _speed / (_run_clip_speed * _stride)") and src.contains("rate = _speed / (_jog_clip_speed * _stride)")
		and src.contains("CrowdCloseup3.fit_strides(self)"), "crowd-closeup-3: Pedestrian's run and jog rates use the rig's measured clip speeds")
	# the hair's edges: the switch is a uniform; the shader keeps its old cut with it off
	var hsrc := FileAccess.get_file_as_string("res://shaders/crowd_hair.gdshader")
	_t._check(hsrc.contains("uniform float closeup") and hsrc.contains("if (closeup > 0.5)") and hsrc.contains("RENDERER_COMPATIBILITY"),
		"crowd-closeup-3: crowd_hair.gdshader's strand cut and silhouette fade sit behind `closeup`, the dither held still on Compatibility")
	var tex := load("res://assets/models/crowd_a_hair.png") as Texture2D
	if tex:
		var mat: ShaderMaterial = ped.hair_material(tex, null, 0.0)
		_t._check(is_equal_approx(float(mat.get_shader_parameter("closeup")), cc.hair_closeup()),
			"crowd-closeup-3: a crowd hair material carries the hair edges' switch")
	_t._check(cc.enabled() == (OS.get_environment("CROWD_CLOSEUP_3") != "0"), "crowd-closeup-3: CROWD_CLOSEUP_3=0 is the A/B")
	# the build: soles, outsoles and laces are the crowd builder's (rigs are rebuilt from it)
	var bsrc := FileAccess.get_file_as_string("res://tools/crowd/build_character.py")
	var cfg := FileAccess.get_file_as_string("res://tools/crowd/crowd_config.json")
	_t._check(bsrc.contains("import crowd_shoes") and bsrc.contains("BUDGET.get(\"hands\"") and cfg.contains("\"hands\":")
		and FileAccess.file_exists("res://tools/crowd/crowd_shoes.py") and FileAccess.file_exists("res://tools/crowd/shoe_paint.py"),
		"crowd-closeup-3: the crowd builder adds the shoe parts and gives the hands their own triangle budget")


## The planted toe's backward speed (m/s at speed_scale 1) in a rig's own walk, as stride_fit.gd
## measures it.
func _walk_speed(path: String) -> float:
	var ped: Script = load("res://scripts/npc/pedestrian.gd")
	var inst: Node3D = (load(path) as PackedScene).instantiate()
	_t.get_tree().root.add_child(inst)
	await _t.get_tree().process_frame
	var ap: AnimationPlayer = inst.find_children("*", "AnimationPlayer", true, false)[0]
	ped.fix_arm_pose(ap, path)
	var skel: Skeleton3D = inst.find_children("*", "Skeleton3D", true, false)[0]
	var a := ap.get_animation(ped.WALK_CLIP)
	ap.play(ped.WALK_CLIP)
	ap.speed_scale = 0.0
	var n := 240
	var dt := a.length / float(n)
	var tot := 0.0
	var time := 0.0
	var ys: Array = [[], []]
	var zs: Array = [[], []]
	var bones := [skel.find_bone("LeftToeBase"), skel.find_bone("RightToeBase")]
	for f in n + 1:
		ap.seek(dt * float(f), true)
		for s in 2:
			var g := skel.global_transform * skel.get_bone_global_pose(bones[s])
			ys[s].append(g.origin.y)
			zs[s].append(g.origin.z)
	for s in 2:
		var ymin: float = (ys[s] as Array).min()
		for f in n:
			if ys[s][f] < ymin + 0.015 and ys[s][f + 1] < ymin + 0.015 and zs[s][f + 1] < zs[s][f]:
				tot += zs[s][f] - zs[s][f + 1]
				time += dt
	inst.queue_free()
	return tot / time if time > 0.0 else 0.0
