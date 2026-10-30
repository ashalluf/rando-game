extends RefCounted
## The Forward+ review's checks for tests/smoke_test.gd (fleet session fwd-review-c, docs/HANDOFF.md
## "Forward+ review: weather, Broadway, the stack, the map"): the HUD's map scales with the window
## (the minimap, its ring and the health bar over it at 1080 lines and 4K; the full map's marks
## layer), and the colour-space fixes stay in the shaders they were made in. Loaded at run time,
## so it compiles after the autoloads.

var _t: Node
var _tree: SceneTree


func _check(ok: bool, label: String) -> void:
	_t._check(ok, label)


func run(t: Node, city: Node3D) -> void:
	_t = t
	_tree = t.get_tree()
	await _hud_scale(city)
	_shaders()


func _hud_scale(city: Node3D) -> void:
	var hud: Node = city.get_node_or_null("DebugHud")
	var frame := hud.get_node_or_null("MinimapFrame") as Control if hud else null
	var ring := hud.get_node_or_null("MinimapBorder") as Control if hud else null
	_check(frame != null and frame.has_method("hud_scale") and ring != null, "the minimap frame scales with the window")
	if frame == null or ring == null:
		return
	var fs: GDScript = frame.get_script()
	_check(is_equal_approx(fs.call("hud_scale", Vector2(1920.0, 1080.0)), 1.0) and is_equal_approx(fs.call("hud_scale", Vector2(3840.0, 2160.0)), 2.0),
		"the HUD's scale is 1 at 1080 lines and 2 at 4K")
	frame.call("layout")
	var view := frame.get_viewport_rect().size
	var s: float = fs.call("hud_scale", view)
	var r: Rect2 = frame.call("screen_rect")
	var base: float = frame.get("base_size")
	var margin: float = frame.get("base_margin")
	_check(is_equal_approx(frame.scale.x, s) and is_equal_approx(ring.scale.x, s) and is_equal_approx(base, 260.0) and is_equal_approx(margin, 24.0),
		"the minimap and its ring are scaled %.2f at %d lines (260 px at 1080)" % [s, int(view.y)])
	var drawn := frame.get_global_rect()
	_check(drawn.end.distance_to(view - Vector2.ONE * margin * s) < 1.0 and absf(drawn.size.x - base * s) < 1.0 and r.is_equal_approx(drawn),
		"the minimap's corner keeps its scaled margin (%s in %s)" % [str(drawn), str(view)])
	_check(ring.get_global_rect().is_equal_approx(drawn), "the ring sits exactly on the minimap")
	var mini := frame.get_node_or_null("Minimap") as Control
	_check(mini != null and is_equal_approx(mini.size.x, base), "the minimap keeps its 1080-line canvas inside the scaled frame")
	var wanted := hud.get_node_or_null("WantedHud") if hud else null
	if wanted == null:
		for c in hud.get_children():
			if c is WantedHud:
				wanted = c
	var bar := wanted.get_node_or_null("Health") as Control if wanted else null
	if wanted:
		wanted.call("_layout")
	_check(bar != null and absf(bar.size.x - drawn.size.x) < 1.0 and bar.position.y + bar.size.y < drawn.position.y and bar.position.y + bar.size.y > drawn.position.y - 12.0 * s,
		"the health bar sits just over the scaled minimap, as wide")
	# The full map: its marks layer is drawn at 1080 lines and scaled to the window.
	var wm: Node = _tree.get_first_node_in_group("world_map")
	if wm == null:
		_check(false, "the full map is there")
		return
	wm.call("open")
	await _tree.process_frame
	var marks := wm.find_child("Marks", true, false) as Control
	var us: float = wm.call("_ui_scale")
	_check(marks != null and is_equal_approx(marks.scale.x, us) and (marks.size * marks.scale).distance_to(view) < 1.0,
		"the full map's marks are drawn at 1080 lines and scaled %.2f to the window" % us)
	var v = wm.call("_screen_view")
	var c := Vector2(wm.get("center"))
	_check(v != null and (v.to(c) * us).distance_to(view * 0.5) < 1.0 and (v.to(c + Vector2(100.0, 0.0)) * us).distance_to(wm.call("world_to_screen", c + Vector2(100.0, 0.0))) < 1.0,
		"a mark lands where the map draws its place")
	wm.call("close")
	await _tree.process_frame


func _shaders() -> void:
	var splash := FileAccess.get_file_as_string("res://shaders/roof_splash.gdshader")
	_check(splash.contains("cs_srgb_to_linear(sky_tint.rgb)") and splash.contains("ALBEDO = cs_out(col)"),
		"the roof splashes decode the sky's sRGB tint and hand it over in the renderer's space")
