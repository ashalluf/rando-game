extends RefCounted
## The hero at arm's length, second pass (wave 4, "hero-closeup-2"; HeroLook, hero_hair.gdshaderinc
## and its three shaders, hero_skin / hero_eye / hero_cloth, tools/hero_closeup_2/soften_tzone.py),
## for tests/smoke_test.gd's room part:
##  - the pass is on (HERO_CLOSEUP_2) and every hero material it touches carries `closeup2` 1
##  - the hair and the brows wear the strand-light core with the blended fringe as the next pass;
##    the base shader (the A/B) has no light() of its own, the fringe draws only under the cut
##  - the brows' core cut sits above the strands' fine tips (the fringe draws them)
##  - the shipped skin maps: the oily T-zone has no hard step left in the mask's oil channel or
##    across the nose in the roughness map (the waxy sky-coloured box), and prep_textures.py
##    builds it with smooth edges for the next rebuild
##  - the lips the skin recolours are there on the region map (G redness, no pores R), on the head
## Leans on nothing an earlier check left: it reads the player's own hero and the files.

var _t: Node


func run(t: Node, player: Node3D) -> void:
	_t = t
	_check(HeroLook.closeup2(), "the hero close-up 2 pass is on (HERO_CLOSEUP_2)")
	var avatar: Node3D = player.get("avatar")
	var look: HeroLook = avatar.get("hero_look") if avatar else null
	_check(look != null and look.skin != null and look.hair != null and look.cloth != null,
		"HeroLook dressed the hero's skin, hair and velour")
	if look == null or look.skin == null or look.hair == null or look.cloth == null:
		return
	_check(float(look.skin.get_shader_parameter("closeup2")) == 1.0, "the skin takes the lips and the oil breakup (closeup2 1)")
	_check(float(look.cloth.get_shader_parameter("closeup2")) == 1.0, "the velour takes the cloth sheen and the creases (closeup2 1)")
	_check(float(look.cloth_rib.get_shader_parameter("closeup2")) == 1.0 if look.cloth_rib else false, "the rib bands take it too")
	_check_hair(look.hair, "hair")
	var brow := _surface_material(avatar, "hero_brows")
	_check(brow != null, "the brows have their own material")
	if brow:
		_check_hair(brow, "brows")
		var cut := float(brow.get_shader_parameter("alpha_cut"))
		_check(cut > 0.4 and cut < 0.7, "the brows' core keeps only the strands' bodies, the fringe their tips (cut %.2f)" % cut)
		var col = brow.get_shader_parameter("brow_color")
		var c: Color = col if col is Color else Color(0.16, 0.12, 0.095)
		_check(c.r > c.g and c.g > c.b and c.r > 0.1, "the brows are a dark brown, not the texture's black")
	var eye := _surface_material(avatar, "hero_eyes")
	if eye and eye.shader == HeroLook.EYE:
		_check(float(eye.get_shader_parameter("closeup2")) == 1.0, "the eyes take the tear line and the caruncle (closeup2 1)")
	_check_shaders()
	_check_maps()


func _check_hair(m: ShaderMaterial, what: String) -> void:
	_check(m.shader == HeroLook.HAIR, "the %s wear the strand-light core shader" % what)
	_check(float(m.get_shader_parameter("closeup2")) == 1.0, "the %s's strand light is on (closeup2 1)" % what)
	var f := m.next_pass as ShaderMaterial
	_check(f != null and f.shader == HeroLook.HAIR_FRINGE, "the %s have the soft fringe as the next pass" % what)
	if f:
		_check(f.get_shader_parameter("albedo_tex") == m.get_shader_parameter("albedo_tex")
			and is_equal_approx(_num(f.get_shader_parameter("alpha_cut"), 0.32), _num(m.get_shader_parameter("alpha_cut"), 0.32)),
			"the %s's fringe reads the same strands and cut as the core" % what)


## A shader parameter left at its default reads null.
func _num(v: Variant, default: float) -> float:
	return float(v) if v != null else default


func _surface_material(avatar: Node3D, name: String) -> ShaderMaterial:
	for node in avatar.find_children("*", "MeshInstance3D", true, false):
		var mi := node as MeshInstance3D
		if mi.mesh == null:
			continue
		for i in mi.mesh.get_surface_count():
			var src := mi.mesh.surface_get_material(i)
			if src and src.resource_name == name:
				return mi.get_surface_override_material(i) as ShaderMaterial
	return null


func _check_shaders() -> void:
	var core := FileAccess.get_file_as_string("res://shaders/hero_hair.gdshader")
	var fringe := FileAccess.get_file_as_string("res://shaders/hero_hair_fringe.gdshader")
	var base := FileAccess.get_file_as_string("res://shaders/hero_hair_base.gdshader")
	var inc := FileAccess.get_file_as_string("res://shaders/hero_hair.gdshaderinc")
	_check(core.contains("#define HAIR_LIGHT") and not core.contains("HAIR_FRINGE") and core.contains("depth_draw_opaque"),
		"the hair core: the strand light, opaque, no fringe")
	_check(fringe.contains("#define HAIR_FRINGE") and fringe.contains("depth_draw_never"),
		"the hair fringe: blended, writes no depth")
	_check(not base.contains("HAIR_LIGHT") and not base.contains("HAIR_FRINGE"),
		"the A/B hair shader keeps the renderer's own lighting")
	_check(inc.contains("#ifdef HAIR_LIGHT") and inc.contains("void light()") and inc.contains("discard"),
		"the include holds the strand light and the fringe's discard above the cut")
	for p: String in ["res://shaders/hero_hair.gdshader", "res://shaders/hero_hair_fringe.gdshader",
			"res://shaders/hero_hair_base.gdshader", "res://shaders/hero_skin.gdshader",
			"res://shaders/hero_eye.gdshader", "res://shaders/hero_cloth.gdshader"]:
		var sh := load(p) as Shader
		var names := []
		if sh:
			for u: Dictionary in sh.get_shader_uniform_list():
				names.append(String(u.name))
		_check(names.has("closeup2"), "%s compiles with the closeup2 switch" % p.get_file())
	var prep := FileAccess.get_file_as_string("res://tools/hero/prep_textures.py")
	_check(not prep.contains("(ax < 0.02) * ss(") and not prep.contains("* (ax < 0.055) * front"),
		"prep_textures.py builds the T-zone with smooth edges (no hard ax steps)")


func _image(path: String) -> Image:
	var g := ProjectSettings.globalize_path(path)
	return Image.load_from_file(g) if FileAccess.file_exists(g) else null


func _check_maps() -> void:
	var mask := _image("res://assets/models/hero_x_skin_mask.png")
	_check(mask != null, "the skin mask is there")
	if mask:
		var step := 0.0
		var peak := 0.0
		for y in range(380, 680):
			for x in range(760, 1000):
				var a := mask.get_pixel(x, y).a
				peak = maxf(peak, a)
				step = maxf(step, maxf(absf(a - mask.get_pixel(x + 1, y).a), absf(a - mask.get_pixel(x, y + 1).a)))
		_check(step < 0.12, "the oily T-zone has no hard edge in the mask (largest step %.3f, was 0.98)" % step)
		_check(peak > 0.5, "and is still there (peak %.2f)" % peak)
	var rough := _image("res://assets/models/hero_hero_skin_roughness.png")
	_check(rough != null, "the skin roughness map is there")
	if rough:
		var step := 0.0
		for y in range(490, 565):
			for x in range(812, 876):
				var g := rough.get_pixel(x, y).g
				step = maxf(step, maxf(absf(g - rough.get_pixel(x + 1, y).g), absf(g - rough.get_pixel(x, y + 1).g)))
		_check(step < 0.1, "the nose's oily patch has no box edge in the roughness map (largest step %.3f, was 0.18)" % step)
	var reg := _image("res://assets/models/hero_x_skin_region.png")
	if reg:
		var lips := 0
		var on_head := 0
		for y in range(0, reg.get_height(), 5):
			for x in range(0, reg.get_width(), 5):
				var p := reg.get_pixel(x, y)
				if p.g > 0.34 and p.r < 0.06:
					lips += 1
					if x > reg.get_width() * 0.75:
						on_head += 1
		_check(lips > 40 and lips < 1500 and on_head > lips * 0.8,
			"the region map holds a lip patch on the head for the skin to recolour (%d samples, %d on the head)" % [lips, on_head])


func _check(ok: bool, label: String) -> void:
	_t.call("_check", ok, label)
