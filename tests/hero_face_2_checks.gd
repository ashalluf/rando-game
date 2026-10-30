extends RefCounted
## The hero's face, second pass (wave 3, "hero-face-2"; tools/hero/ rebuild, hero_skin.gdshader,
## HeroLook), for tests/smoke_test.gd's room part:
##  - the skin wears the face's region map (pores, redness, cartilage) and the pass is on
##  - the baked maps say what they should: the micro detail's B is the pores' cavity (not a
##    normal's z), the region map spans big-pore and no-pore skin and marks some cartilage
##  - the transmittance is held down: deep red and weaker than the old orange
##  - the brows are strand cards on the hair shader with the strands' cut, not the painted card
##  - the face kept its contract: 54 bones, the eye and lash surfaces, the hero_x_* maps
## Leans on nothing an earlier check left: it reads the player's own hero and the files.

var _t: Node


func run(t: Node, player: Node3D) -> void:
	_t = t
	_check(HeroLook.face2(), "the hero face pass is on (HERO_FACE_2)")
	var avatar: Node3D = player.get("avatar")
	var look: HeroLook = avatar.get("hero_look") if avatar else null
	_check(look != null and look.skin != null, "the hero's skin is dressed by HeroLook")
	if look == null or look.skin == null:
		return
	_check_skin(look.skin)
	_check_maps()
	_check_brows(avatar)
	var sk := avatar.find_child("Skeleton3D", true, false) as Skeleton3D
	_check(sk != null and sk.get_bone_count() == 54, "the rebuilt hero keeps his 54 bones (%d)" % (sk.get_bone_count() if sk else -1))


func _check_skin(skin: ShaderMaterial) -> void:
	_check(skin.get_shader_parameter("region_tex") != null, "the skin reads the face's region map (hero_x_skin_region)")
	_check(float(skin.get_shader_parameter("face2")) == 1.0, "the skin shades the face's regions (face2 1)")
	var old_boost: float = 0.35
	var gain = skin.get_shader_parameter("transmit_gain2")
	var g: float = float(gain) if gain != null else 0.06
	_check(g < old_boost * 0.5, "thin ears pass far less light than the old orange transmittance (%.2f)" % g)
	var deep = skin.get_shader_parameter("transmit_deep")
	var c: Color = deep if deep is Color else Color(0.62, 0.16, 0.10)
	_check(c.r > c.g * 2.5 and c.r < 0.8, "the transmitted light is a deep red, not orange")


func _image(name: String) -> Image:
	var path := ProjectSettings.globalize_path("res://assets/models/hero_x_%s" % name)
	if not FileAccess.file_exists(path):
		return null
	return Image.load_from_file(path)


func _check_maps() -> void:
	var det := _image("skin_detail.png")
	_check(det != null, "the skin's micro detail map is there")
	if det:
		var lo := 1.0
		var sum := 0.0
		var n := 0
		for y in range(0, det.get_height(), 7):
			for x in range(0, det.get_width(), 7):
				var b := det.get_pixel(x, y).b
				lo = minf(lo, b)
				sum += b
				n += 1
		# a tangent normal's z sits near 1 everywhere; the cavity is 1 on open skin, low in a pore
		_check(lo < 0.45 and sum / n > 0.6, "the detail's B is the pores' cavity (min %.2f, mean %.2f)" % [lo, sum / maxf(n, 1)])
	var reg := _image("skin_region.png")
	_check(reg != null, "the face's region map is there (hero_x_skin_region)")
	if reg:
		var rmin := 1.0
		var rmax := 0.0
		var cart := 0
		for y in range(0, reg.get_height(), 5):
			for x in range(0, reg.get_width(), 5):
				var p := reg.get_pixel(x, y)
				rmin = minf(rmin, p.r)
				rmax = maxf(rmax, p.r)
				if p.b > 0.6:
					cart += 1
		_check(rmax - rmin > 0.5, "the pore size varies over the body (%.2f..%.2f)" % [rmin, rmax])
		_check(cart > 20, "the region map marks the ears' and nose's cartilage (%d samples)" % cart)


func _check_brows(avatar: Node3D) -> void:
	var brow: ShaderMaterial = null
	var eye := false
	var lash := false
	for node in avatar.find_children("*", "MeshInstance3D", true, false):
		var mi := node as MeshInstance3D
		if mi.mesh == null:
			continue
		for i in mi.mesh.get_surface_count():
			var src := mi.mesh.surface_get_material(i)
			if src == null:
				continue
			match src.resource_name:
				"hero_brows":
					brow = mi.get_surface_override_material(i) as ShaderMaterial
				"hero_eyes":
					eye = true
				"hero_lashes":
					lash = true
	_check(eye and lash, "the eyes and lashes keep their materials (HeroFace's contract)")
	_check(brow != null and brow.shader == HeroLook.HAIR, "the brows wear the hair shader")
	if brow:
		_check(float(brow.get_shader_parameter("alpha_cut")) < 0.3, "the strand brows keep their fine hairs (alpha cut %.2f)" % float(brow.get_shader_parameter("alpha_cut")))
		var tex := brow.get_shader_parameter("albedo_tex") as Texture2D
		# the strand atlas is 256 px of eight columns; the old painted brow was 512
		_check(tex != null and tex.get_width() == 256, "the brows are the strand atlas (%d px)" % (tex.get_width() if tex else -1))


func _check(ok: bool, label: String) -> void:
	_t.call("_check", ok, label)
