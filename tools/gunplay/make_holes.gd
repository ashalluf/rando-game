extends SceneTree
## Bakes the bullet marks' maps (HoleArt, painted in code) into
## assets/textures/bullet_holes/: <surface>_<variant>_{albedo,normal,orm}.png and the shotgun
## pattern's pattern_{albedo,normal,orm}.png. GDScript paints them in ~20 s, far too slow for the
## loading screen, so they ship as files (GunplayFeel.hole_textures() loads them, and paints a
## missing one). Rerun after changing HoleArt, then --import and fix the new .import files
## (tools/fix_texture_imports.py; normal maps take compress/normal_map=1).
##
##   godot --headless --path . --script tools/gunplay/make_holes.gd

const DIR := "res://assets/textures/bullet_holes/"


func _initialize() -> void:
	var gf: GDScript = load("res://scripts/weapons/gunplay_feel.gd")
	var art: GDScript = load("res://scripts/weapons/hole_art.gd")
	var px: int = gf.get("HOLE_PX")
	for surf: int in gf.call("baked_surfaces"):
		for v in int(gf.get("VARIANTS")):
			_save(art.call("build", surf, v, px), gf.call("hole_stem", surf, v))
	_save(art.call("build_pattern", px), "pattern")
	print("MAKE_HOLES done")
	quit()


func _save(maps: Array, stem: String) -> void:
	for i in 3:
		var img := (maps[i] as ImageTexture).get_image()
		img.clear_mipmaps()
		img.save_png(ProjectSettings.globalize_path(DIR + "%s_%s.png" % [stem, ["albedo", "normal", "orm"][i]]))
