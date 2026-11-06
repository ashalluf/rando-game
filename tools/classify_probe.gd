extends SceneTree
## Probe: what surface does WeaponFX.classify() give for shots into the city?
##
##   godot --headless --path . --script tools/classify_probe.gd
##
## The ground slabs and the street props share ONE StreetProps body per chunk, so a name test
## cannot separate them; and Building only builds a shopfront on a tall enough ground-floor
## part of a non-warehouse. This aims rays at each case on purpose rather than sampling and
## hoping, and prints a tally per case.
const NAMES := ["CONCRETE", "METAL", "GLASS", "WOOD", "DIRT", "FLESH"]


func _tally(d: Dictionary, s: int) -> void:
	d[s] = int(d.get(s, 0)) + 1


func _show(label: String, d: Dictionary, n: int) -> void:
	print("PROBE %s, n=%d" % [label, n])
	for s: int in d:
		print("   %s = %d" % [NAMES[s], d[s]])


func _initialize() -> void:
	var scene: PackedScene = load("res://scenes/levels/city.tscn")
	root.add_child(scene.instantiate())
	await process_frame
	for i in 240:
		await process_frame
	var streamer := root.get_child(root.get_child_count() - 1)
	var space: PhysicsDirectSpaceState3D = streamer.get_world_3d().direct_space_state

	# 1. The ground, straight down. Road, pavement, lawn, plaza - all on StreetProps.
	var rng := RandomNumberGenerator.new()
	rng.seed = 7
	var ground := {}
	var gn := 0
	for i in 400:
		var a := rng.randf() * TAU
		var r := rng.randf_range(4.0, 40.0)
		var from := Vector3(cos(a) * r, 14.0, sin(a) * r)
		var q := PhysicsRayQueryParameters3D.create(from, from + Vector3.DOWN * 40.0, 1)
		var hit: Dictionary = space.intersect_ray(q)
		if hit.is_empty():
			continue
		_tally(ground, WeaponFX.classify(hit.collider, hit.position, hit.normal))
		gn += 1
	_show("ground, straight down", ground, gn)

	# 2. Street props, aimed at their own shapes. These are the ones that SHOULD be metal.
	var props := {}
	var pn := 0
	for body: Node in root.find_children("StreetProps", "StaticBody3D", true, false):
		var co := body as CollisionObject3D
		for child: Node in body.get_children():
			var cs := child as CollisionShape3D
			if cs == null or not cs.has_meta("prop"):
				continue
			var centre := cs.global_position
			var from := centre + Vector3(2.5, 0.0, 0.0)
			var q := PhysicsRayQueryParameters3D.create(from, centre, 1)
			var hit: Dictionary = space.intersect_ray(q)
			if hit.is_empty() or hit.collider != body:
				continue
			_tally(props, WeaponFX.classify(hit.collider, hit.position, hit.normal))
			pn += 1
			if pn >= 200:
				break
		if pn >= 200:
			break
	_show("street props, aimed at a shape with a prop meta", props, pn)

	# 3. Building walls, by shape kind, at shopfront height.
	var by_kind := {}
	for b: Node in root.find_children("*", "StaticBody3D", true, false):
		if not b.is_in_group("building"):
			continue
		var n3 := b as Node3D
		var fp: Variant = b.get("footprint")
		if typeof(fp) != TYPE_VECTOR2:
			continue
		var half: float = maxf((fp as Vector2).x, (fp as Vector2).y) * 0.5 + 3.0
		var at := n3.global_position + Vector3(0.0, 1.7, 0.0)
		var q := PhysicsRayQueryParameters3D.create(at + Vector3(half, 0.0, 0.0), at, 1)
		var hit: Dictionary = space.intersect_ray(q)
		if hit.is_empty() or hit.collider != b:
			continue
		var kind: int = int(b.get("shape"))
		var store: bool = b.get("allow_storefront") == true
		var key := "shape%d/storefront=%s" % [kind, store]
		if not by_kind.has(key):
			by_kind[key] = {}
		_tally(by_kind[key], WeaponFX.classify(hit.collider, hit.position, hit.normal))
	print("PROBE building walls at 1.7 m (shape 7 = WAREHOUSE)")
	var keys := by_kind.keys()
	keys.sort()
	for k: String in keys:
		var line := ""
		for s: int in by_kind[k]:
			line += "%s=%d " % [NAMES[s], by_kind[k][s]]
		print("   %s -> %s" % [k, line])
	quit()
