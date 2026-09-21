extends SceneTree
## Checks that the raised letters land exactly on the painted name behind them. Both are drawn
## for a stretch of street, so if the TextMesh's ink and the atlas cell's ink are not the same
## rectangle, a shopfront shows the painted name poking out from behind its own letters.
##
##   godot --headless --path . --script tools/glshot/sign_align_probe.gd
func _initialize() -> void:
	Building.sign_atlas()
	var em: float = Building.SIGN_HEIGHT
	var cell: Vector2 = Building._sign_cell_em
	var worst := 0.0
	var worst_c := 0.0
	for i in Building.SHOP_NAMES.size():
		var mesh: Mesh = Building.sign_letter_mesh(i)
		var aabb := mesh.get_aabb()
		# What the shader draws: the whole cell, one em of it SIGN_HEIGHT metres wide.
		var cell_w := cell.x * em
		var adv := Building.sign_advance(i) * em
		# The atlas centres the name's advance box in the cell, and so does TextMesh, so the
		# two agree when the advance widths agree. The mesh's AABB is ink, which is the advance
		# less the side bearings - compare centres, and widths to within those bearings.
		var d_center := absf(aabb.position.x + aabb.size.x * 0.5)
		var d_width := absf(aabb.size.x - adv)
		worst = maxf(worst, d_width / em)
		worst_c = maxf(worst_c, d_center / em)
		print("%-12s mesh_ink=%.3f em  atlas_adv=%.3f em  dx=%.3f em  centre_off=%.3f em  cell=%.2f em" % [
			Building.SHOP_NAMES[i], aabb.size.x / em, adv / em, d_width / em, d_center / em, cell_w / em])
	print("worst width difference %.3f em, worst centre offset %.3f em" % [worst, worst_c])
	quit()
