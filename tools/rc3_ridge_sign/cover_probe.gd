extends "res://tools/glshot/still_shot.gd"
## SHOT_ONLY: just the probe.
## Who draws the blocks round a point in the ridge-sign refcam: for each block in a box, the chunk
## there (level, visible, children) and whether the far city covers it. Run like still_shot.gd with
## TREES_AB=1 and BOX=ix0,iz0,ix1,iz1.

func _trees_ab(_path: String) -> void:
	var streamer: Node = current_scene
	var sky: Variant = streamer.get("_skyline") if streamer else null
	var box := OS.get_environment("BOX").split(",")
	for iz in range(int(box[1]), int(box[3]) + 1):
		for ix in range(int(box[0]), int(box[2]) + 1):
			var b := Vector2i(ix, iz)
			var ch: Node = streamer.chunks.get(b) if streamer.chunks.has(b) else null
			var s := "BLOCK %s" % b
			if ch:
				s += " chunk level %d visible %s kids %d" % [ch.level, ch.visible, ch.get_child_count()]
			else:
				s += " no chunk"
			if sky:
				s += " covered %s alpha %.2f inst %d tile %s" % [sky.is_covered(b), sky.block_alpha(b), sky.block_instances(b), sky.has_tile(sky.tile_of(b))]
				var t = sky._tiles.get(sky.tile_of(b))
				if t != null and t.node:
					s += " node_vis %s" % (t.node as Node3D).visible
			print(s)
	print("SKYLINE ", sky)
