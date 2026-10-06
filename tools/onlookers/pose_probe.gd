extends Node3D
## Headless probe of Onlookers' arm poses (tools/onlookers/pose_probe.tscn): one walker of each
## of a few rigs, posed FILM / POINT / COVER at a scene 8 m ahead; prints where the hand, the
## phone and the elbow end up relative to the head (metres, the person's frame: x right, y up,
## z ahead) and the phone screen's facing toward the eyes.
##   godot --headless --path . res://tools/onlookers/pose_probe.tscn

func _ready() -> void:
	var player := Node3D.new()
	player.add_to_group("player")
	add_child(player)
	for mi in [0, 3, 7]:
		for role in [Onlookers.Role.FILM, Onlookers.Role.POINT, Onlookers.Role.COVER]:
			var p := Pedestrian.new()
			p.setup(Rect2(-50, -50, 100, 100), 4.0, 777 + mi * 13)
			p.life_range = 1000.0
			add_child(p)
			await get_tree().physics_frame
			p._visual.rotation.y = 0.0 # facing -Z
			var s := {"kind": Onlookers.Kind.WRECK, "world": WorldState.to_world(p.global_position + Vector3(0, 0, -8)), "ref": null, "id": 0, "members": [], "spots": [], "callers": 0, "closing": false, "seed": 1}
			p.watch = {"scene": s, "role": role, "hand": "Right", "two": false, "w": 1.0, "want": 1.0, "one_left": 0.0, "seed": 1, "spot": Vector2.ZERO, "leave_ms": -1, "until": -1, "beat": 100.0, "base": CrowdLife.IDLE}
			p._act = CrowdLife.Act.WATCH
			p._life_near = true
			p._place_at(Vector2(p.position.x, p.position.z), 0.0)
			p._stage = Pedestrian.Stage.DOING
			p._speed = 0.0
			p._life_clip = CrowdLife.IDLE
			for i in 20:
				await get_tree().physics_frame
			var sk := p._head_skel
			var tf := sk.global_transform
			var head := tf * sk.get_bone_global_pose(sk.find_bone("Head")).origin
			var hand := tf * sk.get_bone_global_pose(sk.find_bone("RightHand")).origin
			var elbow := tf * sk.get_bone_global_pose(sk.find_bone("RightForeArm")).origin
			var basis := Basis(Vector3.RIGHT, Vector3.UP, Vector3.BACK) # x right, y up, z ahead(-Z world)
			var rel := func(v: Vector3) -> Vector3: return Vector3(v.x, v.y, -v.z)
			var line := "rig %d %s: hand %s elbow %s" % [mi, Onlookers.Role.keys()[role], rel.call(hand - head), rel.call(elbow - head)]
			if p.has_meta("onlooker_phone"):
				var ph: Node3D = p.get_meta("onlooker_phone")
				var m := ph.get_child(0) as Node3D
				var c := m.global_transform * Vector3(0, 0.075, 0.022)
				var scr := (m.global_basis * Vector3(0, 0, 1)).normalized()
				line += " phone %s screen.toEye %.2f fingers %s" % [rel.call(c - head), scr.dot((head - c).normalized()), rel.call((m.global_basis * Vector3(0, 1, 0)).normalized())]
			print(line)
			# skeleton forward check
			print("   skel +Z in world: ", (tf.basis * Vector3(0, 0, 1)).normalized(), " unit ", p._skel_unit)
			p.queue_free()
	get_tree().quit()
