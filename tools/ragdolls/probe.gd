extends Node
## Jointed ragdoll probe (RagdollJoints), headless, seconds: drops dolls of a few rigs onto a floor,
## a kerb and a car-bonnet-sized box, steps the physics and prints how they fell, whether the joints
## held, when each froze and the physics time. Usage:
##   godot --headless --path . tools/ragdolls/probe.tscn [-- --n=6 --steps=600]
## RAGDOLLS=0 compares the old single body.

func _ready() -> void:
	call_deferred("_run")


func _run() -> void:
	var n := 4
	var steps := 600
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--n="):
			n = int(a.substr(4))
		elif a.begins_with("--steps="):
			steps = int(a.substr(8))
	var world := Node3D.new()
	add_child(world)
	var cam := Camera3D.new()
	world.add_child(cam)
	cam.position = Vector3(0, 3, 12)
	cam.current = true
	_box(world, Vector3(0, -0.5, 0), Vector3(200, 1, 200)) # the road
	_box(world, Vector3(0, 0.075, -3.0), Vector3(40, 0.15, 3.0)) # a kerb and pavement
	_box(world, Vector3(4, 0.5, 2.0), Vector3(1.8, 1.0, 4.2), 4) # a car's height, props layer
	await get_tree().physics_frame
	var models: Array = load("res://scripts/npc/pedestrian.gd").MODELS
	var dolls: Array = []
	var t0 := Time.get_ticks_usec()
	for i in n:
		var d := Ragdoll.new()
		world.add_child(d)
		d.global_position = Vector3(-6 + i * 3.0, 0.05, 0.0)
		d.rotation.y = float(i) * 0.9
		var ok := d.build_from_rig(models[i % models.size()], 0)
		d.fling(Vector3(i % 3 - 1, 1.2, -1.5 if i % 2 == 0 else 1.5) * 3.0)
		dolls.append(d)
		print("doll %d %s ok=%s jointed=%s bodies=%d" % [i, String(models[i % models.size()]).get_file(), ok, d.get("_joints") != null, d.bodies.size()])
	print("build ms %.1f" % ((Time.get_ticks_usec() - t0) / 1000.0))
	var phys := 0.0
	var wall0 := 0
	for s in steps:
		if s == 2 or s == 302:
			wall0 = Time.get_ticks_usec()
		if s == 62 or s == 362:
			var asleep := dolls.filter(func(d): return PhysicsServer3D.body_get_state(d.bodies[0].get_rid(), PhysicsServer3D.BODY_STATE_SLEEPING)).size()
			print("asleep %d of %d, jointed %d" % [asleep, dolls.size(), RagdollJoints.active_count()])
			print("wall ms/step (%s; run with --fixed-fps 60) %.3f" % ["tumbling" if s == 62 else "settled", (Time.get_ticks_usec() - wall0) / 60000.0])
		await get_tree().physics_frame
		if s < 6 and OS.get_environment("VEL") == "1":
			print("v ", dolls[0].bodies[0].linear_velocity, " at ", dolls[0].bodies[0].global_position)
		phys += Performance.get_monitor(Performance.TIME_PHYSICS_PROCESS)
		if s == 59:
			print("physics ms/step over the first 60 steps (tumbling) %.3f" % (phys * 1000.0 / 60.0))
		if s % 100 == 99:
			var line := "step %d active=%d" % [s + 1, RagdollJoints.active_count()]
			for d in dolls:
				var j: RagdollJoints = d._joints
				line += " | %s y=%.2f gap=%.3f" % ["F" if j == null or j.frozen else "J", d.bodies[0].global_position.y, _gap(d)]
			print(line)
			if s == 99 and OS.get_environment("GAPS") == "1":
				for d in dolls:
					var j: RagdollJoints = d._joints
					var g := ""
					for a: Array in j.anchors:
						g += "%s %.2f  " % [(a[1] as Node).name, ((a[0] as Node3D).global_transform * (a[2] as Vector3)).distance_to((a[1] as Node3D).global_position)]
					print(g)
	print("physics ms/step avg %.3f" % (phys * 1000.0 / steps))
	for d in dolls:
		var skel: Skeleton3D = d._skeleton()
		var head := skel.global_transform * skel.get_bone_global_pose(skel.find_bone("Head")).origin
		var foot := skel.global_transform * skel.get_bone_global_pose(skel.find_bone("LeftFoot")).origin
		print("head y %.2f foot y %.2f pelvis %s shapes %d" % [head.y, foot.y, d.bodies[0].global_position, d.bodies[0].get_children().filter(func(c): return c is CollisionShape3D).size()])
	get_tree().quit()


func _gap(d: Ragdoll) -> float:
	var j: RagdollJoints = d._joints
	return 0.0 if j == null or j.frozen else j.gap()


func _box(parent: Node3D, at: Vector3, size: Vector3, layer: int = 1) -> void:
	var b := StaticBody3D.new()
	b.collision_layer = layer
	b.collision_mask = 0
	var cs := CollisionShape3D.new()
	var bs := BoxShape3D.new()
	bs.size = size
	cs.shape = bs
	b.add_child(cs)
	parent.add_child(b)
	b.global_position = at
