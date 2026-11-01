extends SceneTree
## Dumps the shop-name atlas Building builds at load, so it can be looked at without the game:
##
##   OUT=atlas.png godot --headless --path . --script tools/glshot/sign_atlas_shot.gd
##
## It prints the cell size in ems, the grid and every name's advance width, which are the three
## numbers shaders/building.gdshader needs to place a name on a sign band.
func _initialize() -> void:
	var tex := Building.sign_atlas()
	if tex == null:
		print("NO ATLAS")
		quit()
		return
	var img := tex.get_image()
	print("atlas %dx%d cell_em=%s grid=%s mipmaps=%s" % [img.get_width(), img.get_height(),
		Building._sign_cell_em, Building._sign_grid, img.has_mipmaps()])
	for i in Building.SHOP_NAMES.size():
		print("  %-12s adv=%.3f em" % [Building.SHOP_NAMES[i], Building._sign_adv[i]])
	var out := OS.get_environment("OUT")
	if out == "":
		out = "sign_atlas.png"
	# Alpha is the letter coverage; flatten it to grey so the dump can be looked at.
	var flat := Image.create(img.get_width(), img.get_height(), false, Image.FORMAT_RGB8)
	for y in img.get_height():
		for x in img.get_width():
			var a := img.get_pixel(x, y).a
			flat.set_pixel(x, y, Color(a, a, a))
	flat.save_png(out)
	print("saved ", out)
	quit()
