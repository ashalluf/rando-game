extends RefCounted
## Stages street props breaking for tools/glshot/still_shot.gd (PROPS=hydrant,lamp,...), and
## returns the EYE ("x,y,z,yaw,pitch", true world) that frames it. Loaded at run time (after the
## autoloads). The first kind's nearest prop to the camera (or to PB_FIND=x,z) is the centre;
## every prop of the listed kinds within PB_RADIUS (default 14 m) of it is broken (PB_DAMAGE,
## default 200; "lean" in the list bends the lamps instead, "glass" only breaks shelter glass),
## hit from the camera's side. PB_EYE_DIST / PB_EYE_HEIGHT / PB_EYE_SIDE place the camera.

static func stage(tree: SceneTree, kinds_env: String, cam: Camera3D) -> String:
	var ws := tree.root.get_node("/root/WorldState")
	var kinds := kinds_env.split(",")
	var from: Vector3 = cam.global_position
	var find := OS.get_environment("PB_FIND")
	if find != "":
		var p := find.split(",")
		from = ws.to_local(Vector3(p[0].to_float(), cam.global_position.y, p[1].to_float()))
	var best: Dictionary = {}
	var best_ch: CityChunk = null
	var best_d := INF
	var all: Array = []
	for ch in _chunks(tree.current_scene):
		for r: Dictionary in ch.prop_records:
			if r.dead or not kinds.has(String(r.kind)):
				continue
			var g := ch.to_global(r.position)
			all.append([ch, r, g])
			if String(r.kind) == kinds[0]:
				var d := Vector2(g.x - from.x, g.z - from.z).length()
				if d < best_d:
					best_d = d
					best = r
					best_ch = ch
	if best.is_empty():
		print("PROPS: no ", kinds[0], " near ", ws.to_world(from))
		return ""
	var centre := best_ch.to_global(best.position)
	var away := Vector3(from.x - centre.x, 0.0, from.z - centre.z)
	away = away.normalized() if away.length() > 0.5 else Vector3.BACK
	var radius := float(OS.get_environment("PB_RADIUS")) if OS.get_environment("PB_RADIUS") != "" else 14.0
	var dmg := float(OS.get_environment("PB_DAMAGE")) if OS.get_environment("PB_DAMAGE") != "" else 200.0
	var broken := 0
	for e in all:
		var g: Vector3 = e[2]
		if g.distance_to(centre) > radius:
			continue
		var r: Dictionary = e[1]
		var ch: CityChunk = e[0]
		var amount := dmg
		if r.kind == "lamp" and kinds.has("lean"):
			amount = 45.0
		elif r.kind == "bus_stop" and kinds.has("glass"):
			amount = 50.0
		ch.damage_prop(r, amount, -away)
		if r.kind == "bus_stop" and not r.dead and not kinds.has("glass"):
			ch.damage_prop(r, amount, -away)
		broken += 1
	var dist := float(OS.get_environment("PB_EYE_DIST")) if OS.get_environment("PB_EYE_DIST") != "" else 9.0
	var up := float(OS.get_environment("PB_EYE_HEIGHT")) if OS.get_environment("PB_EYE_HEIGHT") != "" else 1.7
	var side := float(OS.get_environment("PB_EYE_SIDE")) if OS.get_environment("PB_EYE_SIDE") != "" else 2.5
	var right := away.cross(Vector3.UP).normalized()
	var eye := centre + away * dist + right * side + Vector3.UP * up
	var look := centre + Vector3.UP * 1.6 - eye
	var yaw := rad_to_deg(atan2(-look.x, -look.z))
	var pitch := rad_to_deg(atan2(look.y, Vector2(look.x, look.z).length()))
	var w: Vector3 = ws.to_world(eye)
	print("PROPS %s: broke %d round %s" % [kinds_env, broken, ws.to_world(centre)])
	return "%.2f,%.2f,%.2f,%.2f,%.2f" % [w.x, w.y, w.z, yaw, pitch]


static func _chunks(root: Node) -> Array:
	var out: Array = []
	if root == null:
		return out
	for c in root.get_children():
		if c is CityChunk and (c as CityChunk).level == CityChunk.Level.FULL:
			out.append(c)
	return out
