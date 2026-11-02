extends RefCounted
## The person_closeup refcam's fixes (wave 6, rc3-person-closeup), for tests/smoke_test.gd. Loaded
## at run time, so it compiles after the autoloads. Pure: it loads its own copies of the rig and
## its idle library (never the shared, cached ones), so nothing here leans on what an earlier check
## or the city left.
##
## IdleRelax: the library idle's arms come in by the thighs and its feet under the hips, every other
## bone untouched, once per library. The bag: hung from the fist, cords meeting at the grip. Hair
## strands and toned lips: the uniforms exist and are set. The switch turns it all off. The camera
## row and its stage.

const RIG := "res://assets/models/crowd_h.glb"
const GAIT := "res://assets/models/crowd_gait/crowd_h_gait.res"

var _t: Object


func run(t: Object, _city: Node3D) -> void:
	_t = t
	await _stance()
	_bag()
	_shaders()
	_switch()
	_camera_row()


## Feet and hands measured on a copy of crowd_h posed by the raw and the relaxed gait idle.
func _stance() -> void:
	var scene: PackedScene = load(RIG)
	if scene == null or not ResourceLoader.exists(GAIT):
		_t._check(false, "IdleRelax: crowd_h and its gait library load")
		return
	var inst: Node3D = scene.instantiate()
	_t.get_tree().root.add_child(inst)
	var ap: AnimationPlayer = inst.find_child("AnimationPlayer", true, false)
	var sk: Skeleton3D = inst.find_child("Skeleton3D", true, false)
	Pedestrian.fix_arm_pose(ap, RIG)
	var raw: AnimationLibrary = ResourceLoader.load(GAIT, "", ResourceLoader.CACHE_MODE_IGNORE)
	var mine := AnimationLibrary.new()
	mine.add_animation("idle", raw.get_animation("idle"))
	ap.add_animation_library("ckgait", mine)
	var before := _measure(ap, sk, "ckgait/idle")
	var relaxed := IdleRelax.blend_clip(raw.get_animation("idle"), ap.get_animation("Idle"), 0.85, 5.5, sk)
	mine.add_animation("idle", relaxed)
	var after := _measure(ap, sk, "ckgait/idle")
	_t._check(before[0] - after[0] >= 0.08, "IdleRelax: the idle's feet come in under the hips (%.2f -> %.2f m apart sideways)" % [before[0], after[0]])
	_t._check(after[0] >= 0.15, "IdleRelax: the feet stay apart (%.2f m), not crossed" % after[0])
	_t._check(before[1] - after[1] >= 0.03, "IdleRelax: the hands hang nearer the thighs (%.2f -> %.2f m out from the hips)" % [before[1], after[1]])
	_t._check(absf(before[2] - after[2]) < 0.02, "IdleRelax: the head is where the clip put it (moved %.3f m)" % absf(before[2] - after[2]))
	_t._check(absf(before[3] - after[3]) < 0.04, "IdleRelax: the feet stay on the ground (%.3f -> %.3f m)" % [before[3], after[3]])
	_t._check(relaxed.length == raw.get_animation("idle").length and relaxed.get_track_count() == raw.get_animation("idle").get_track_count(),
		"IdleRelax: the relaxed clip keeps its length and tracks")
	# Once per library: a second relax() of a relaxed library changes nothing.
	var done := AnimationLibrary.new()
	done.add_animation("idle", relaxed)
	done.set_meta(IdleRelax.META, true)
	ap.add_animation_library("gait", done)
	IdleRelax.relax(ap, "gait")
	_t._check(done.get_animation("idle") == relaxed, "IdleRelax: a library is relaxed once")
	inst.queue_free()
	await _t.get_tree().process_frame


## [feet apart sideways, mean hand distance out from the hips' side line, head height, lowest foot]
## in metres, over the clip.
func _measure(ap: AnimationPlayer, sk: Skeleton3D, clip: String) -> Array:
	var unit := sk.global_basis.get_scale().x
	var feet := 0.0
	var hands := 0.0
	var head := 0.0
	var low := INF
	var n := 0
	for t in [0.4, 1.9, 3.3, 5.1, 6.6]:
		ap.play(clip)
		ap.seek(t, true)
		ap.pause()
		var hips := sk.get_bone_global_pose(sk.find_bone("Hips"))
		var side := hips.basis.x.normalized()
		var l := sk.get_bone_global_pose(sk.find_bone("LeftFoot")).origin
		var r := sk.get_bone_global_pose(sk.find_bone("RightFoot")).origin
		var lh := sk.get_bone_global_pose(sk.find_bone("LeftHand")).origin
		var rh := sk.get_bone_global_pose(sk.find_bone("RightHand")).origin
		var lu := sk.get_bone_global_pose(sk.find_bone("LeftUpLeg")).origin
		var ru := sk.get_bone_global_pose(sk.find_bone("RightUpLeg")).origin
		feet += absf((l - r).dot(side))
		hands += absf((lh - lu).dot(side)) + absf((rh - ru).dot(side))
		head += sk.get_bone_global_pose(sk.find_bone("Head")).origin.y
		low = minf(low, minf(l.y, r.y))
		n += 1
	return [feet / n * unit, hands / (2.0 * n) * unit, head / n * unit, low * unit]


func _bag() -> void:
	var was := PersonCloseup._on
	PersonCloseup._on = 1
	CrowdLife._meshes.erase(CrowdLife.Prop.BAG)
	var box := CrowdLife.prop_mesh(CrowdLife.Prop.BAG).get_aabb()
	_t._check(box.position.y > -0.01 and box.position.y < 0.01, "the bag's cords meet at the grip (top %.3f m)" % box.position.y)
	_t._check(box.end.y > 0.35 and box.end.y < 0.5 and box.size.x > 0.24, "the bag hangs a paper bag's height under it (%.2f m, %.2f wide)" % [box.end.y, box.size.x])
	var g := CrowdLife.BAG_GRIP.length()
	_t._check(g > 0.06 and g < 0.11, "the bag is held in the curl of the fingers, %.3f m from the wrist" % g)
	CrowdLife._meshes.erase(CrowdLife.Prop.BAG)
	PersonCloseup._on = was


func _shaders() -> void:
	var hair := FileAccess.get_file_as_string("res://shaders/crowd_hair.gdshader")
	var body := FileAccess.get_file_as_string("res://shaders/character.gdshader")
	_t._check(hair.contains("uniform float strand_detail = 0.0;") and hair.contains("hair_spec_mod"),
		"crowd_hair: the strand detail is a uniform, off by default (the old shader bit for bit)")
	_t._check(body.contains("uniform float lip_tame = 0.0;"), "character: lip_tame is a uniform, off by default")
	var tex := ImageTexture.create_from_image(Image.create(4, 4, false, Image.FORMAT_RGBA8))
	var was := PersonCloseup._on
	PersonCloseup._on = 1
	var mat := Pedestrian.hair_material(tex, null)
	_t._check(is_equal_approx(float(mat.get_shader_parameter("strand_detail")), PersonCloseup.STRAND_DETAIL),
		"the crowd's hair material turns the strands on")
	PersonCloseup._on = was


func _switch() -> void:
	var was := PersonCloseup._on
	var was_r := IdleRelax._on
	PersonCloseup._on = 0
	IdleRelax._on = -1
	_t._check(not IdleRelax.enabled(), "PERSON_CLOSEUP=0 turns the idle relax off")
	PersonCloseup._on = was
	IdleRelax._on = was_r


func _camera_row() -> void:
	var data: Variant = JSON.parse_string(FileAccess.get_file_as_string("res://tools/refcams/cameras_w6.json"))
	var row: Dictionary = {}
	if data is Dictionary:
		for c: Dictionary in data.get("cameras", []):
			if c.get("name", "") == "person_closeup":
				row = c
	_t._check(not row.is_empty() and row.get("stage", "") == "person" and float(row.hour) == 13.0,
		"cameras_w6.json has the person_closeup row (staged, 13:00)")
	var stager: GDScript = load("res://tools/refcams/person_stage.gd")
	var s: int = stager.call("seed_for", RIG, 0)
	var available: Array = []
	for p in Pedestrian.MODELS:
		if ResourceLoader.exists(p) and not (p in Pedestrian.VARIETY_MODELS and not Pedestrian.variety_on()):
			available.append(p)
	var r := RandomNumberGenerator.new()
	r.seed = hash([s, "style"])
	_t._check(available[r.randi() % available.size()] == RIG, "person_stage.seed_for finds a seed that deals crowd_h")
