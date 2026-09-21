extends SceneTree
func _initialize() -> void:
	for v in PropFactory.PALM_VARIANTS:
		print("palm variant %d tris=%d" % [v, PropFactory.palm(v).get_faces().size() / 3])
	quit()
