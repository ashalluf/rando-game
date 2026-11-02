extends RefCounted
## Stages what a blast leaves behind for tools/glshot/still_shot.gd (AFTERMATH=kind), and returns
## the EYE ("x,y,z,yaw,pitch", true world) that frames it. Loaded at run time (after the
## autoloads), so it names TreeFire, BlastAftermath and Explosion freely.
##
##   palms    a rocket in the street beside the nearest palm row: the fireball, leaves torn off
##   burning  that row's crowns alight, well into the burn (use --hour=22 for the night still)
##   charred  the same row burnt out (and the crater the rocket left), the next day
##   column   a big fire there (trees and the row), the camera AF_FAR metres off across the basin
##   crater   the crater and the rubble from a few metres up, the smoke gone
##
## AF_FIND=x,z searches for the palm row round that true world point instead of the camera.
## AF_EYE_DIST / AF_EYE_HEIGHT / AF_SIDE place the camera (metres from the row, up, to the side).

static func stage(tree: SceneTree, kind: String, cam: Camera3D) -> String:
	var ws := tree.root.get_node("/root/WorldState")
	var from: Vector3 = cam.global_position
	var find := OS.get_environment("AF_FIND")
	if find != "":
		var p := find.split(",")
		from = ws.to_local(Vector3(p[0].to_float(), cam.global_position.y, p[1].to_float()))
	var row := palm_row(from)
	if row.is_empty():
		print("AFTERMATH: no palm row near ", ws.to_world(from))
		return ""
	var centre := Vector3.ZERO
	for h: Array in row:
		centre += WorldState.to_local((h[1] as Dictionary).foot)
	centre /= float(row.size())
	# The row's direction, and the side of it the street is on (the side away from the nearest wall).
	var a := WorldState.to_local((row[0][1] as Dictionary).foot)
	var b := WorldState.to_local((row[row.size() - 1][1] as Dictionary).foot)
	var along := (b - a)
	along.y = 0.0
	along = along.normalized() if along.length() > 0.5 else Vector3.RIGHT
	var across := along.cross(Vector3.UP).normalized()
	if _blocked(tree, centre + Vector3.UP * 1.5, across, 12.0):
		across = -across
	var blast_at := centre + across * _f("AF_BLAST_OUT", 4.0) + Vector3.UP * 0.5
	var ground := _ground(tree, blast_at)
	if ground != Vector3.INF:
		blast_at = ground + Vector3.UP * 0.4
	print("AFTERMATH %s: %d palms round %s, blast at %s" % [kind, row.size(), ws.to_world(centre), ws.to_world(blast_at)])
	var dist := _f("AF_EYE_DIST", 34.0)
	var up := _f("AF_EYE_HEIGHT", 2.0)
	var side := _f("AF_SIDE", 10.0)
	var eye := centre + across * dist + along * side
	# A spot with no crown between it and the row (trees have no collision to ray against).
	var cands: Array = []
	for f: float in [1.0, 0.75, 0.55, 1.3, 0.4]:
		for g: float in [1.0, -1.0, 0.0, 2.0, -2.0]:
			cands.append(Vector2(dist * f, side * g))
	for cand: Vector2 in cands:
		var e := centre + across * cand.x + along * cand.y
		var eg := _ground(tree, e)
		if eg == Vector3.INF or absf(eg.y - centre.y) > 1.5:
			continue
		if _clear_view(e, centre):
			eye = e
			break
	var e_ground := _ground(tree, eye)
	eye.y = (e_ground.y if e_ground != Vector3.INF else centre.y) + up
	var look := centre + Vector3.UP * 7.0
	# AF_NOFIRE=1: the same frame with nothing staged (the frame-cost A/B).
	var stage_it := OS.get_environment("AF_NOFIRE") != "1"
	match kind:
		"palms":
			if stage_it:
				Explosion.blast(tree.current_scene, blast_at, 9.0, 30.0, 0.0)
		"burning":
			for h: Array in row:
				if stage_it:
					TreeFire.ignite(tree.current_scene, h[0], h[1], _f("AF_BURN", 0.45))
			look = centre + Vector3.UP * 9.0
		"charred":
			if stage_it:
				BlastAftermath.crater(tree.current_scene, blast_at - Vector3.UP * 0.4, Vector3.UP, 9.0)
				for h: Array in row:
					TreeFire.char_tree(h[0], h[1])
		"column":
			for h: Array in TreeFire.trees_near(centre, 40.0):
				if stage_it:
					TreeFire.ignite(tree.current_scene, h[0], h[1], 0.4)
			var mgr := TreeFire.manager(tree)
			mgr._update_columns(1.0)
			for c: SmokeColumn in mgr.columns():
				c.strength = 1.0
				c._glow = 1.0
				for k in 40:
					c.step(1.0, 1.0, 70.0, mgr._wind())
			var far := _f("AF_FAR", 1500.0)
			var dir := (across + along * 0.4).normalized()
			eye = centre + dir * far
			var g2 := _ground(tree, eye)
			eye.y = (g2.y if g2 != Vector3.INF else centre.y) + _f("AF_EYE_HEIGHT", 60.0)
			look = centre + Vector3.UP * 220.0
		"crater":
			if stage_it:
				Explosion.blast(tree.current_scene, blast_at, 9.0, 30.0, 0.0)
			eye = blast_at + across * 7.0 + along * 3.0 + Vector3.UP * 5.0
			look = blast_at
	var d := look - eye
	var yaw := rad_to_deg(atan2(-d.x, -d.z))
	var pitch := rad_to_deg(atan2(d.y, Vector2(d.x, d.z).length()))
	var we: Vector3 = ws.to_world(eye)
	return "%.2f,%.2f,%.2f,%.2f,%.2f" % [we.x, we.y, we.z, yaw, pitch]


## The palms nearest `at` that stand in a row (three or more within 30 m of the first).
static func palm_row(at: Vector3) -> Array:
	var near := TreeFire.trees_near(at, 600.0)
	for h: Array in near:
		var t: Dictionary = h[1]
		if not t.palm:
			continue
		var row: Array = [h]
		var c := WorldState.to_local(t.foot)
		for o: Array in TreeFire.trees_near(c, 30.0):
			var ot: Dictionary = o[1]
			if ot.palm and ot.id != t.id and row.size() < 6:
				var of := WorldState.to_local(ot.foot)
				if absf(of.y - c.y) < 2.0:
					row.append(o)
		if row.size() >= 3:
			row.sort_custom(func(x, y): return WorldState.to_local(x[1].foot).dot(Vector3(1, 0, 1)) < WorldState.to_local(y[1].foot).dot(Vector3(1, 0, 1)))
			return row
	return []


static func _ground(tree: SceneTree, at: Vector3) -> Vector3:
	var space := tree.root.world_3d.direct_space_state
	var q := PhysicsRayQueryParameters3D.create(at + Vector3.UP * 30.0, at + Vector3.DOWN * 40.0, 1)
	var hit := space.intersect_ray(q)
	return hit.position if not hit.is_empty() else Vector3.INF


static func _blocked(tree: SceneTree, at: Vector3, dir: Vector3, reach: float) -> bool:
	var space := tree.root.world_3d.direct_space_state
	var q := PhysicsRayQueryParameters3D.create(at, at + dir * reach, 1)
	return not space.intersect_ray(q).is_empty()


static func _f(name: String, def: float) -> float:
	var v := OS.get_environment(name)
	return v.to_float() if v != "" else def


## True when no tree's crown stands within its radius of the line from `eye` to `target` (xz),
## other than at the target end.
static func _clear_view(eye: Vector3, target: Vector3) -> bool:
	var a := Vector2(eye.x, eye.z)
	var b := Vector2(target.x, target.z)
	var len := a.distance_to(b)
	for h: Array in TreeFire.trees_near(eye, len):
		var c := WorldState.to_local(h[1].crown)
		var p := Vector2(c.x, c.z)
		var t := clampf((p - a).dot(b - a) / maxf(len * len, 0.01), 0.0, 1.0)
		if t > 0.8:
			continue
		if p.distance_to(a.lerp(b, t)) < float(h[1].r) + 1.0:
			return false
	return true
