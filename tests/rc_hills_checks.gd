extends RefCounted
## The hills reference camera (fleet wave 4, rc-hills; docs/HANDOFF.md "The hills refcam"): checks
## for tests/smoke_test.gd. CPU and source only (no pixel is read headless):
##   * summit crags are broad, low tors now, never the old spires (wider than they stand tall);
##   * the far tors carry a screen-size cull and a darker blend, RockFar's far materials have them;
##   * the terrain's steep faces take their textures from the side, with the derivatives taken
##     outside the branch (textureGrad), and the tile fade is on;
##   * the shrub clumps' gathering field is a pure function of the place, in 0..1, with gaps;
##   * the ridge sign is two meshes (letters, frame), spanning what the old letters spanned.
## RC_HILLS=0 is the A/B: everything goes back, and the checks only say so.

var _t: Node


func run(t: Node, city: Node3D) -> void:
	_t = t
	if not RcHills.on():
		_t._check(true, "rc-hills: off (RC_HILLS=0)")
		return
	var plan: CityPlan = city.get("plan") if city else null
	if plan and plan.macro:
		_crags(plan)
		_sign(plan)
	_far_rock()
	_terrain()
	_cluster()


func _crags(plan: CityPlan) -> void:
	var tors := RockOutcrops.tors(plan)
	var summits := 0
	var spires := 0
	for tr: Dictionary in tors:
		if not bool(tr.get("summit", false)):
			continue
		summits += 1
		var b := RockKit.bounds(int(tr.kind))
		var sc: Vector3 = (tr.basis as Basis).get_scale()
		var wide := maxf(b.size.x * sc.x, b.size.z * sc.z)
		if float(tr.top) > wide:
			spires += 1
	_t._check(summits > 0 and spires == 0, "rc-hills: summit crags stand lower than they are wide (%d summits, %d spires)" % [summits, spires])


func _far_rock() -> void:
	var src := FileAccess.get_file_as_string("res://shaders/rock_outcrop.gdshader")
	_t._check(src.contains("uniform vec2 far_cull_ndc") and src.contains("far_grey_gain"), "rc-hills: the far tor shader has the screen-size cull and the blend gain")
	var m := RockKit.material(RockKit.TOR_KINDS[0], true, true)
	RcHills.apply_rock(m, true)
	var c: Vector2 = m.get_shader_parameter("far_cull_ndc")
	_t._check(c.y > c.x and c.x > 0.0 and c.y < 0.05, "rc-hills: far tors under %.3f-%.3f of the frame are dropped" % [c.x, c.y])
	var src_far := FileAccess.get_file_as_string("res://scripts/world/rock_far.gd")
	_t._check(src_far.contains("RcHills.apply_rock(mat, far)"), "rc-hills: RockFar hands its materials to RcHills")


func _terrain() -> void:
	var m := PropFactory.terrain_material()
	_t._check(float(m.get_shader_parameter("side_mix")) == 1.0, "rc-hills: the terrain lays steep faces from the side")
	var tf: Vector2 = m.get_shader_parameter("tile_fade_px")
	_t._check(tf.y > tf.x and tf.x > 0.0, "rc-hills: the dirt and rock tiles fade past %.1f-%.1f m a pixel" % [tf.x, tf.y])
	var src := FileAccess.get_file_as_string("res://shaders/terrain.gdshader")
	var body := src.substr(src.find("vec3 side_tex("), 700)
	_t._check(body.contains("textureGrad") and not body.contains("texture(t"), "rc-hills: the side samples carry their own derivatives (no texture() in the branch)")


func _cluster() -> void:
	var lo := 1.0
	var hi := 0.0
	var gaps := 0
	var n := 0
	for i in 60:
		for j in 60:
			var p := Vector2(i * 3.7 - 400.0, j * 4.1 - 1300.0)
			var c := RcHills.cluster(p)
			lo = minf(lo, c)
			hi = maxf(hi, c)
			if c < RcHills.CLUSTER_GAP:
				gaps += 1
			n += 1
	_t._check(RcHills.cluster(Vector2(12.5, -900.25)) == RcHills.cluster(Vector2(12.5, -900.25)), "rc-hills: the clump field is a function of the place")
	var share := float(gaps) / float(n)
	_t._check(lo >= 0.0 and hi <= 1.0 and share > 0.08 and share < 0.45, "rc-hills: the clumps gather into thickets with gaps (%.0f %% of the ground a gap)" % (share * 100.0))


func _sign(plan: CityPlan) -> void:
	var lm: Dictionary = {}
	for l: Dictionary in Landmarks.all():
		if l.id == "sign":
			lm = l
	if lm.is_empty():
		_t._check(false, "rc-hills: the sign landmark exists")
		return
	var holder := Node3D.new()
	HillSignLetters.build(lm.anchor, holder, null, plan, false)
	var letters := holder.get_node_or_null("SignLetters") as MeshInstance3D
	var frame := holder.get_node_or_null("SignFrame") as MeshInstance3D
	var ok := letters != null and frame != null and letters.mesh != null
	var span := 0.0
	if ok:
		span = letters.mesh.get_aabb().size.x
	var line := Landmarks.sign_line(lm.anchor, plan)
	var old := Landmarks.SIGN_SPAN
	_t._check(ok and absf(span - old) < old * 0.05, "rc-hills: the sign is letters and a frame across the old span (%.0f m of %.0f)" % [span, old])
	var n := Landmarks.SIGN_TEXT.length()
	var cap := 7.0 * Landmarks.SIGN_SPAN / (float(n) * 5.0 + float(n - 1) * 1.5)
	var low := float(line.ground) + 2.0 - HillSignLetters.STEP_MAX * cap
	_t._check(ok and letters.mesh.get_aabb().position.y >= low - HillSignLetters.PEN * cap * 0.5 - 0.5, "rc-hills: no letter steps further down the hill than %.0f m under the old line" % (float(line.ground) + 2.0 - low))
	# Each letter clear of the ground under its middle (the end letters used to sink into the ridge).
	var buried := 0
	var aabb := letters.mesh.get_aabb() if ok else AABB()
	for i in n:
		var x := aabb.position.x + aabb.size.x * (float(i) + 0.5) / float(n)
		if plan.height_at(Vector2(x, float(lm.anchor.y))) > aabb.end.y - cap:
			buried += 1
	_t._check(ok and buried == 0, "rc-hills: no letter's ground stands over the lowest letter's foot (%d)" % buried)
	holder.free()
