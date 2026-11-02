extends RefCounted
## The body of tools/chase_box_bug/probe.gd (loaded once the autoloads exist).

var tree: SceneTree
var out_dir: String
var car: Vehicle
var player: Player
var city: Node
var ws: Node
var cam: Camera3D
var spots: Array = [] # screen points: [left in, left out, right in, right out, centre]
var base: Image
const START := Vector3(2363.0, 0.0, 960.0)


func run(st: SceneTree) -> void:
	tree = st
	out_dir = OS.get_environment("OUT_DIR") if OS.get_environment("OUT_DIR") != "" else "build/chasebox"
	if not out_dir.begins_with("/"):
		out_dir = ProjectSettings.globalize_path("res://" + out_dir)
	DirAccess.make_dir_recursive_absolute(out_dir)
	city = tree.current_scene
	ws = tree.root.get_node("/root/WorldState")
	player = tree.get_first_node_in_group("player") as Player
	var police: Node = city.get_node_or_null("Police")
	if police:
		police.set("enabled", false)
	for i in 30:
		await tree.process_frame
	car = Vehicle.new()
	car.setup(Vehicle.BodyType.SEDAN, Color(0.55, 0.04, 0.05), Vehicle.Addon.NONE)
	city.add_child(car)
	car.collision_mask = 1
	await _place(START + Vector3(0, 0, 25), 0.0)
	if OS.get_environment("NO_ENTER") == "":
		player.enter_vehicle(car)
	await _wait(1.0)
	var v := 30.0 / 3.6
	var t := 0.0
	while t < 2.0:
		var f := -car.global_basis.z
		f.y = 0.0
		f = f.normalized()
		car.linear_velocity = Vector3(f.x * v, car.linear_velocity.y, f.z * v)
		car.hold_crash_watch(2)
		await tree.physics_frame
		t += 1.0 / 60.0
	if OS.get_environment("PAUSE") != "0":
		tree.paused = true
	cam = tree.root.get_camera_3d()
	_find_spots()
	base = await _shot("00_base")
	var dump := OS.get_environment("DUMP")
	if dump != "":
		_dump_near()
	var mode := OS.get_environment("MODE")
	if mode == "classes":
		await _by_class()
	elif mode == "bisect":
		await _bisect()


func _find_spots() -> void:
	var box := AABB()
	var first := true
	for n in car.find_children("*", "MeshInstance3D", true, false):
		var mi := n as MeshInstance3D
		if mi.mesh == null:
			continue
		var b: AABB = car.global_transform.affine_inverse() * mi.global_transform * mi.get_aabb()
		box = b if first else box.merge(b)
		first = false
	print("CAR box local ", box)
	var rear := box.end.z
	var y := box.position.y + box.size.y * 0.42
	var hx := box.size.x * 0.5
	var pts := [Vector3(-hx - 0.04, y, rear), Vector3(-hx - 0.9, y, rear), Vector3(hx + 0.04, y, rear), Vector3(hx + 0.9, y, rear), Vector3(0, y, rear)]
	spots.clear()
	for p: Vector3 in pts:
		spots.append(cam.unproject_position(car.global_transform * p))
	print("SPOTS ", spots)


func _patch(img: Image, at: Vector2) -> float:
	var s := 0.0
	var n := 0
	for dy in range(-2, 3):
		for dx in range(-2, 3):
			var x := clampi(int(at.x) + dx, 0, img.get_width() - 1)
			var y := clampi(int(at.y) + dy, 0, img.get_height() - 1)
			var c := img.get_pixel(x, y)
			s += (c.r + c.g + c.b) / 3.0 * 255.0
			n += 1
	return s / n


func _vals(img: Image) -> Array:
	var out := []
	for p: Vector2 in spots:
		out.append(_patch(img, p))
	return out


func _shot(name: String) -> Image:
	await tree.process_frame
	await RenderingServer.frame_post_draw
	await tree.process_frame
	await RenderingServer.frame_post_draw
	var img := tree.root.get_texture().get_image()
	img.save_jpg("%s/%s.jpg" % [out_dir, name], 0.9)
	var v := _vals(img)
	print("SHOT %s  Lin %.1f Lout %.1f Rin %.1f Rout %.1f C %.1f  (Lin-Lout %.1f, Rin-Rout %.1f)" % [name, v[0], v[1], v[2], v[3], v[4], v[0] - v[1], v[2] - v[3]])
	return img


func _drawables() -> Array:
	var out := []
	for n in tree.root.find_children("*", "VisualInstance3D", true, false):
		var vi := n as VisualInstance3D
		if vi.is_visible_in_tree() and vi.layers != 0:
			out.append(vi)
	return out


func _dump_near() -> void:
	var cp := car.global_position
	for vi: VisualInstance3D in _drawables():
		var gi := vi as Node3D
		var d := gi.global_position.distance_to(cp)
		var aabb := vi.get_aabb()
		var gb: AABB = vi.global_transform * aabb
		var touches := gb.grow(0.5).has_point(cp)
		if d < 8.0 or touches:
			var sc: Variant = vi.get_script()
			print("NEAR %.1f %s %s script=%s aabb=%s" % [d, vi.get_class(), vi.get_path(), sc.resource_path if sc else "", gb.size])


func _set_off(list: Array, off: bool) -> void:
	for vi: VisualInstance3D in list:
		if off:
			vi.set_meta("cb_layers", vi.layers)
			vi.layers = 0
		elif vi.has_meta("cb_layers"):
			vi.layers = vi.get_meta("cb_layers")
			vi.remove_meta("cb_layers")


func _gone(img: Image) -> Array:
	# Did the lamp squares go? The inner patch moves while the outer one stays.
	var b := _vals(base)
	var v := _vals(img)
	var dl := (b[0] - v[0]) - (b[1] - v[1])
	var dr := (b[2] - v[2]) - (b[3] - v[3])
	return [dl, dr]


func _by_class() -> void:
	var groups := {}
	for vi: VisualInstance3D in _drawables():
		var sc: Variant = vi.get_script()
		var key: String = sc.resource_path.get_file() if sc else vi.get_class()
		var p := vi.get_parent()
		var ps: Variant = p.get_script() if p else null
		if ps:
			key += "@" + ps.resource_path.get_file()
		if not groups.has(key):
			groups[key] = []
		groups[key].append(vi)
	print("CLASSES ", groups.size())
	var i := 0
	for key: String in groups:
		_set_off(groups[key], true)
		var img: Image = await _shot("cls_%03d" % i)
		var g := _gone(img)
		print("CLASS %03d %s n=%d  dL %.1f dR %.1f" % [i, key, groups[key].size(), g[0], g[1]])
		_set_off(groups[key], false)
		i += 1


func _bisect() -> void:
	var all := _drawables()
	var cp := car.global_position
	# Skip the obvious: the car's own children (ruled out) and the road under the car.
	var list := []
	for vi: VisualInstance3D in all:
		if car.is_ancestor_of(vi):
			continue
		list.append(vi)
	print("BISECT over ", list.size())
	await _bis(list, 0)


func _bis(list: Array, depth: int) -> void:
	if list.is_empty():
		return
	_set_off(list, true)
	var img: Image = await _shot("bis_%d_%d" % [depth, list.size()])
	_set_off(list, false)
	var g := _gone(img)
	var hit: bool = g[0] > 3.0 or g[1] > 3.0
	print("BIS depth %d n %d  dL %.1f dR %.1f  %s" % [depth, list.size(), g[0], g[1], "HIT" if hit else "-"])
	if not hit:
		return
	if list.size() == 1:
		var vi: VisualInstance3D = list[0]
		var sc: Variant = vi.get_script()
		print("CULPRIT %s %s script=%s" % [vi.get_class(), vi.get_path(), sc.resource_path if sc else ""])
		return
	var h := list.size() / 2
	await _bis(list.slice(0, h), depth + 1)
	await _bis(list.slice(h), depth + 1)


func _place(world: Vector3, yaw: float) -> void:
	var p: Vector3 = ws.call("to_local", world)
	player.global_position = p + Vector3.UP * 2.0
	city.call("update_streaming", true)
	for i in 4:
		await tree.process_frame
	var plan: CityPlan = city.get("plan")
	var gy := plan.height_at(Vector2(world.x, world.z)) if plan else 0.0
	var at: Vector3 = ws.call("to_local", Vector3(world.x, gy + 0.9, world.z))
	car.hold_crash_watch(6)
	car.global_transform = Transform3D(Basis(Vector3.UP, yaw), at)
	car.linear_velocity = Vector3.ZERO
	car.angular_velocity = Vector3.ZERO
	city.call("update_streaming", true)
	await _wait(0.6)


func _wait(seconds: float) -> void:
	var t := 0.0
	while t < seconds:
		await tree.process_frame
		t += tree.root.get_process_delta_time()
