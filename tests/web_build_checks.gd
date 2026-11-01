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
## WebGL2's floor for MAX_UNIFORM_BLOCK_SIZE: the Compatibility renderer puts a material's
## uniforms in one std140 block (the most today: ocean, ~2.9 KB).
const WEB_UBO_BYTES := 16384
## Custom varying components a shader may add on top of the renderer's own (normal, tangent,
## UVs, colour, shadow coordinates). WebGL2 guarantees only 60 in all (MAX_VARYING_COMPONENTS);
## the most today is building_lod, 34. Past this the program fails to LINK in a browser with a
## low limit and the material draws nothing.
const WEB_VARYING_COMPONENTS := 40
## A shader's source with its includes, comments stripped (KB): the browser translates and
## compiles every byte when the material is first drawn, and the page stops while it does
## (building.gdshader, 160 KB after wave 4, is the slowest program the web compiles). A budget
## so the next pass that grows it sees the number.
const WEB_SOURCE_KB := 200
## Elements of a shader's constant arrays, summed (const_array_items()): building's vinyl glyph
## table is 1,240 after wave 4. ANGLE on Windows unrolls them into the program.
const WEB_CONST_ITEMS := 1600

var _t: Node


func run(t: Node, city: Node) -> void:
	_t = t
	_preset()
	_shaders()
	_quality(city)
	_rain_ceiling(city)


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
	_excluded(str(cfg.get_value(web, "exclude_filter", "")))


## The Web preset leaves out files nothing loads (the retired Meshy pedestrians, the editor
## thumbnails: ~45 MB of the download). Nothing in scripts/ or scenes/ may load one of them.
func _excluded(filter: String) -> void:
	var globs: Array[String] = []
	for g in filter.split(","):
		if g.strip_edges() != "":
			globs.append("res://" + g.strip_edges())
	_t._check(globs.size() >= 2, "web: the Web preset excludes the unused rigs and thumbnails (%s)" % filter)
	var bad: Array[String] = []
	var re := RegEx.create_from_string("(load|ext_resource|ResourceLoader)[^\\n]*\"(res://[^\"]+)\"")
	for path in _files("res://scripts", ".gd") + _files("res://scenes", ".tscn"):
		for m in re.search_all(FileAccess.get_file_as_string(path)):
			for g in globs:
				if m.get_string(2).match(g):
					bad.append("%s -> %s" % [path, m.get_string(2)])
	_t._check(bad.is_empty(), "web: nothing loads a file the Web export leaves out %s" % [bad])
	_excluded_by_name(globs)


## Wave 3's cuts (old Poly Haven scans the code-built kits replaced, two exotic bodies no body
## type uses, the Meshy sedan: ~32 MB) are reached through a directory constant plus a file name
## (`MODEL_DIR + "prop_hydrant.glb"`), which the res:// scan above cannot see. So no script or
## scene line outside a comment may name one of their stems, and every glob must still match a
## file (a filter that matches nothing is stale: the file was renamed and now ships).
func _excluded_by_name(globs: Array[String]) -> void:
	var stems: Array[String] = []
	var stale: Array[String] = []
	var assets := _files("res://assets/models", "")
	for g in globs:
		if not assets.any(func(a: String) -> bool: return a.match(g)):
			stale.append(g)
		var stem := g.get_file().trim_suffix("*").trim_suffix(".glb")
		# The retired Meshy rigs keep their own rule: the police compare one of their paths.
		if stem != "" and not stem.begins_with("pedestrian_"):
			stems.append(stem)
	_t._check(stale.is_empty(), "web: every Web exclude glob still matches a file %s" % [stale])
	var bad: Array[String] = []
	for path in _files("res://scripts", ".gd") + _files("res://scenes", ".tscn"):
		for line in FileAccess.get_file_as_string(path).split("\n"):
			var code := line.get_slice("#", 0) if path.ends_with(".gd") else line
			for st in stems:
				if code.contains(st):
					bad.append("%s: %s" % [path.get_file(), st])
	_t._check(stems.size() >= 8 and bad.is_empty(),
		"web: no script names an asset the Web export leaves out (%d stems) %s" % [stems.size(), bad])


func _files(dir: String, ext: String) -> Array[String]:
	var out: Array[String] = []
	for f in DirAccess.get_files_at(dir):
		if f.ends_with(ext):
			out.append(dir.path_join(f))
	for d in DirAccess.get_directories_at(dir):
		out.append_array(_files(dir.path_join(d), ext))
	return out


func _shaders() -> void:
	var worst := 0
	var worst_name := ""
	var over: Array[String] = []
	var instance: Array[String] = []
	var count := 0
	var big_ubo := 0
	var big_ubo_name := ""
	var ubo_over: Array[String] = []
	var big_vary := 0
	var big_vary_name := ""
	var vary_over: Array[String] = []
	for file in DirAccess.get_files_at("res://shaders"):
		if not file.ends_with(".gdshader"):
			continue
		count += 1
		var src := _strip_comments(_source("res://shaders/" + file, {}))
		var samplers := sampler_count(src)
		if samplers > worst:
			worst = samplers
			worst_name = file
		if samplers > WEB_SAMPLERS:
			over.append("%s (%d)" % [file, samplers])
		if RegEx.create_from_string("\\binstance\\s+uniform\\b").search(src):
			instance.append(file)
		var ubo := ubo_bytes(src)
		if ubo > big_ubo:
			big_ubo = ubo
			big_ubo_name = file
		if ubo > WEB_UBO_BYTES:
			ubo_over.append("%s (%d)" % [file, ubo])
		var vary := varying_components(src)
		if vary > big_vary:
			big_vary = vary
			big_vary_name = file
		if vary > WEB_VARYING_COMPONENTS:
			vary_over.append("%s (%d)" % [file, vary])
	_t._check(count > 50, "web: the shader folder was read (%d shaders)" % count)
	_t._check(over.is_empty(), "web: every shader within %d texture samplers (most %d, %s) %s" % [
		WEB_SAMPLERS, worst, worst_name, over])
	_t._check(instance.is_empty(), "web: no shader uses instance uniforms %s" % [instance])
	_t._check(big_ubo > 1000 and ubo_over.is_empty(),
		"web: every material's uniforms fit WebGL2's %d-byte block (most %d, %s) %s" % [
		WEB_UBO_BYTES, big_ubo, big_ubo_name, ubo_over])
	_t._check(big_vary > 10 and vary_over.is_empty(),
		"web: every shader within %d custom varying components (most %d, %s) %s" % [
		WEB_VARYING_COMPONENTS, big_vary, big_vary_name, vary_over])
	var big_kb := 0
	var big_kb_name := ""
	var big_const := 0
	var big_const_name := ""
	var size_over: Array[String] = []
	for file in DirAccess.get_files_at("res://shaders"):
		if not file.ends_with(".gdshader"):
			continue
		var src2 := _strip_comments(_source("res://shaders/" + file, {}))
		var kb := src2.length() / 1024
		var items := const_array_items(src2)
		if kb > big_kb:
			big_kb = kb
			big_kb_name = file
		if items > big_const:
			big_const = items
			big_const_name = file
		if kb > WEB_SOURCE_KB or items > WEB_CONST_ITEMS:
			size_over.append("%s (%d KB, %d const items)" % [file, kb, items])
	_t._check(big_kb > 20 and big_const > 100 and size_over.is_empty(),
		"web: every shader within %d KB of source and %d constant-array items (most %d KB %s, %d items %s) %s" % [
		WEB_SOURCE_KB, WEB_CONST_ITEMS, big_kb, big_kb_name, big_const, big_const_name, size_over])
	_t._check(const_array_items("const float A[3] = float[](1.0, 2.0, 3.0); const vec2 B[] = vec2[](vec2(0.0, 1.0), vec2(2.0, 3.0));") == 5,
		"web: the constant-array count reads sized and unsized tables")
	# The two counters, proven on planted sources.
	_t._check(ubo_bytes("uniform float a; uniform vec3 b; uniform vec4 c[4]; uniform sampler2D t; global uniform vec4 g;") == 96,
		"web: the uniform block estimate is std140 (%d, wants 96)" % ubo_bytes("uniform float a; uniform vec3 b; uniform vec4 c[4];"))
	_t._check(varying_components("varying vec3 a; varying flat float b; varying vec2 c[2];") == 8,
		"web: the varying count adds components")


static func sampler_count(src: String) -> int:
	var re := RegEx.create_from_string("\\buniform\\s+(?:lowp\\s+|mediump\\s+|highp\\s+)?(?:u|i)?sampler(?:2D|3D|Cube|2DArray)\\w*\\b")
	return re.search_all(src).size()


## Elements in a shader's constant arrays (`const T name[N]` or `= T[](...)`), summed: the
## generated tables (vinyl glyphs, letter strokes). Each element is an instruction the browser's
## shader translator must emit and its driver compile; on ANGLE (Chrome on Windows / D3D) big
## constant tables are the slowest thing to compile, and the page stalls while it does.
static func const_array_items(src: String) -> int:
	var re := RegEx.create_from_string("\\bconst\\s+(?:lowp\\s+|mediump\\s+|highp\\s+)?\\w+\\s+\\w+\\s*\\[\\s*(\\d*)\\s*\\]\\s*=")
	var n := 0
	for m in re.search_all(src):
		if m.get_string(1) != "":
			n += int(m.get_string(1))
			continue
		# No size: count the initialiser's top-level elements.
		var i := m.get_end()
		var depth := 0
		var items := 0
		var seen := false
		while i < src.length():
			var ch := src[i]
			if ch == "(" or ch == "{":
				depth += 1
				if depth == 1:
					seen = true
					items = 1
			elif ch == ")" or ch == "}":
				depth -= 1
				if depth == 0 and seen:
					break
			elif ch == "," and depth == 1:
				items += 1
			elif ch == ";" and depth == 0:
				break
			i += 1
		n += items
	return n


const _TYPE_SIZE := {"float": [4, 4], "int": [4, 4], "uint": [4, 4], "bool": [4, 4],
	"vec2": [8, 8], "ivec2": [8, 8], "uvec2": [8, 8], "bvec2": [8, 8],
	"vec3": [12, 16], "ivec3": [12, 16], "uvec3": [12, 16], "bvec3": [12, 16],
	"vec4": [16, 16], "ivec4": [16, 16], "uvec4": [16, 16], "bvec4": [16, 16],
	"mat2": [32, 16], "mat3": [48, 16], "mat4": [64, 16]}


## A material's non-sampler uniforms laid out std140 (an upper bound: uniforms behind an
## #ifdef count too). Global and instance uniforms live elsewhere.
static func ubo_bytes(src: String) -> int:
	var re := RegEx.create_from_string("(?<!global )(?<!instance )\\buniform\\s+(?:lowp\\s+|mediump\\s+|highp\\s+)?(\\w+)\\s+\\w+\\s*(?:\\[\\s*(\\d+)\\s*\\])?")
	var off := 0
	for m in re.search_all(src):
		var t := m.get_string(1)
		if t.contains("sampler") or not _TYPE_SIZE.has(t):
			continue
		var sz: int = _TYPE_SIZE[t][0]
		var al: int = _TYPE_SIZE[t][1]
		if m.get_string(2) != "":
			al = 16
			sz = ((sz + 15) / 16) * 16 * int(m.get_string(2))
		off = ((off + al - 1) / al) * al + sz
	return off


static func varying_components(src: String) -> int:
	const PER := {"float": 1, "int": 1, "uint": 1, "vec2": 2, "ivec2": 2, "uvec2": 2,
		"vec3": 3, "ivec3": 3, "uvec3": 3, "vec4": 4, "ivec4": 4, "uvec4": 4,
		"mat2": 4, "mat3": 9, "mat4": 16}
	var re := RegEx.create_from_string("\\bvarying\\s+(?:flat\\s+|smooth\\s+)?(?:lowp\\s+|mediump\\s+|highp\\s+)?(\\w+)\\s+\\w+\\s*(?:\\[\\s*(\\d+)\\s*\\])?")
	var n := 0
	for m in re.search_all(src):
		n += int(PER.get(m.get_string(1), 4)) * (int(m.get_string(2)) if m.get_string(2) != "" else 1)
	return n


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


## The painted deck (the web, Forward+ below MEDIUM) closes into a stratus ceiling in rain: it
## used to leave blue holes over the rain (a rain day's coverage is ~0.75). A clear day's deck,
## at the most the hour's swing gives it, stays untouched.
func _rain_ceiling(city: Node) -> void:
	var src := FileAccess.get_file_as_string("res://shaders/sky.gdshader")
	var lo := _const_f(src, "PAINTED_STRAT_LO")
	var hi := _const_f(src, "PAINTED_STRAT_HI")
	var dn: Node = city.get_node_or_null("DayNight")
	var base: float = float(dn.get("cloud_coverage")) if dn else 0.42
	var rain_extra: float = load("res://scripts/world/weather.gd").call("_cloud", 2) # RAIN
	var rain_min := smoothstep(lo, hi, base - 0.12 + rain_extra)
	var clear_max := smoothstep(lo, hi, base + 0.12)
	_t._check(lo > 0.0 and hi > lo and rain_min >= 0.6 and clear_max == 0.0,
		"web: the painted sky closes over the rain (%.2f at the thinnest hour) and leaves a clear day alone (%.2f)" % [rain_min, clear_max])


func _const_f(src: String, name: String) -> float:
	var m := RegEx.create_from_string("const\\s+float\\s+" + name + "\\s*=\\s*([0-9.]+)").search(src)
	return float(m.get_string(1)) if m else -1.0
