extends SceneTree
func _t(m: Mesh) -> int:
	return 0 if m == null else m.get_faces().size() / 3
func _initialize() -> void:
	print("bush()            %d" % _t(PropFactory.bush()))
	for i in 4:
		print("model_shrub(%d)    %d" % [i, _t(PropFactory.model_shrub(i))])
	for i in 4:
		print("model_bush(%d)     %d" % [i, _t(PropFactory.model_bush(i))])
	for i in 3:
		print("model_plant(%d)    %d" % [i, _t(PropFactory.model_plant(i))])
	for i in 5:
		print("model_tree(%d)     %d  h=%.1f" % [i, _t(PropFactory.model_tree(i)), PropFactory.model_tree(i).get_aabb().size.y])
	print("model_cafe_set    %d" % _t(PropFactory.model_cafe_set()))
	print("model_planter     %d" % _t(PropFactory.model_planter()))
	print("model_bench       %d" % _t(PropFactory.model_bench()))
	print("model_trash(0)    %d" % _t(PropFactory.model_trash_can(false)))
	print("palm(0)           %d" % _t(PropFactory.palm(0)))
	quit()
