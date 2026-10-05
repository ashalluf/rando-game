extends RefCounted
## The web build (tests/smoke_test.gd): what a headless run can hold the browser build to.
## The headless check never sees WebGL, so these are the budgets and settings that, broken,
## only show up as a blank material or a black page in somebody's browser:
##  - the Web export preset: single-threaded, no GDExtension, desktop (S3TC) textures;
##  - every shader, with its includes, under WebGL2's texture units: 16 a fragment shader on most
##    browsers (SwiftShader and Chrome on a Mac both report 16), of which the Compatibility
##    renderer takes up to seven for its own (shadow atlases, radiance, screen and depth
##    textures), so a material gets WEB_SAMPLERS;
##  - no `instance uniform` (the Compatibility global buffer: CLAUDE.md, Car glass and drivers);
##  - Quality's web path (`_apply_web()`) drops the sky's cloud_detail and the ground_detail
##    global, as CLAUDE.md says the web does - it used to leave both on, since the web never
##    runs apply_level().

const WEB_SAMPLERS := 9

var _t: Node


func run(t: Node, city: Node) -> void:
	_t = t
	_preset()
	_shaders()
	_quality(city)


func _preset() -> void:
	var cfg := ConfigFile.new()
	_t._check(cfg.load("res://export_presets.cfg") == OK, "web: export_presets.cfg loads")
	var web := ""
	for section in cfg.get_sections():
		if section.begins_with("preset.") and section.count(".") == 1 and cfg.get_value(section, "platform", "") == "Web":
			web = section
	_t._check(web != "", "web: there is a Web export preset")
	if web == "":
		return
	var opts := web + ".options"
	_t._check(cfg.get_value(opts, "variant/thread_support", true) == false,
		"web: the export is single-threaded (no cross-origin isolation headers on GitHub Pages)")
	_t._check(cfg.get_value(opts, "variant/extensions_support", true) == false, "web: no GDExtension")
	_t._check(cfg.get_value(opts, "vram_texture_compression/for_desktop", false) == true,
		"web: desktop (S3TC) textures are exported for desktop browsers")


func _shaders() -> void:
	var worst := 0
	var worst_name := ""
	var over: Array[String] = []
	var instance: Array[String] = []
	var count := 0
	for file in DirAccess.get_files_at("res://shaders"):
		if not file.ends_with(".gdshader"):
			continue
		count += 1
		var src := _strip_comments(_source("res://shaders/" + file, {}))
		var samplers := 0
		var re := RegEx.create_from_string("\\buniform\\s+(?:lowp\\s+|mediump\\s+|highp\\s+)?(?:u|i)?sampler(?:2D|3D|Cube|2DArray)\\w*\\b")
		samplers = re.search_all(src).size()
		if samplers > worst:
			worst = samplers
			worst_name = file
		if samplers > WEB_SAMPLERS:
			over.append("%s (%d)" % [file, samplers])
		if RegEx.create_from_string("\\binstance\\s+uniform\\b").search(src):
			instance.append(file)
	_t._check(count > 50, "web: the shader folder was read (%d shaders)" % count)
	_t._check(over.is_empty(), "web: every shader within %d texture samplers (most %d, %s) %s" % [
		WEB_SAMPLERS, worst, worst_name, over])
	_t._check(instance.is_empty(), "web: no shader uses instance uniforms %s" % [instance])


func _quality(city: Node) -> void:
	var q: Node = city.get_node_or_null("Quality")
	_t._check(q != null and q.has_method("_apply_web"), "web: Quality has its web settings")
	if q == null or not q.has_method("_apply_web"):
		return
	var we := city.get_node_or_null("WorldEnvironment") as WorldEnvironment
	var sky: ShaderMaterial = null
	if we and we.environment and we.environment.sky:
		sky = we.environment.sky.sky_material as ShaderMaterial
	_t._check(sky != null, "web: the sky is a shader material")
	var cloud: Variant = sky.get_shader_parameter("cloud_detail") if sky else null
	var ground: Variant = RenderingServer.global_shader_parameter_get("ground_detail")
	q.call("_apply_web")
	var cloud_web: Variant = sky.get_shader_parameter("cloud_detail") if sky else null
	var ground_web: Variant = RenderingServer.global_shader_parameter_get("ground_detail")
	# The dummy renderer of the headless run reads every global back as null; a real one reads 0.
	_t._check(cloud_web == 0.0 and (ground_web == null or ground_web == 0.0),
		"web: the web drops the sky's cloud detail and ground_detail (%s, %s)" % [cloud_web, ground_web])
	# Put the desktop values back for whatever runs after this.
	if sky:
		sky.set_shader_parameter("cloud_detail", 1.0 if cloud == null else cloud)
	RenderingServer.global_shader_parameter_set("ground_detail", 1.0 if ground == null else ground)


func _source(path: String, seen: Dictionary) -> String:
	if seen.has(path) or not FileAccess.file_exists(path):
		return ""
	seen[path] = true
	var src := FileAccess.get_file_as_string(path)
	var out := src
	for m in RegEx.create_from_string("#include\\s+\"([^\"]+)\"").search_all(src):
		var inc := m.get_string(1)
		if not inc.begins_with("res://"):
			inc = path.get_base_dir().path_join(inc)
		out += "\n" + _source(inc, seen)
	return out


func _strip_comments(src: String) -> String:
	src = RegEx.create_from_string("(?s)/\\*.*?\\*/").sub(src, "", true)
	return RegEx.create_from_string("//[^\\n]*").sub(src, "", true)
