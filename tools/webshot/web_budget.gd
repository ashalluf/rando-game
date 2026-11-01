extends SceneTree
## The web's static budgets per shader, the numbers tests/web_build_checks.gd holds, in seconds
## and without a city: texture samplers (with includes), the std140 uniform block, custom varying
## components, the size of the flattened source and its constant arrays. Top N of each.
##   godot --headless --path . --script tools/webshot/web_budget.gd [-- --top=12]

const Checks := preload("res://tests/web_build_checks.gd")


func _initialize() -> void:
	var top := 12
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--top="):
			top = int(a.substr(6))
	var c = Checks.new()
	var rows: Array = []
	for file in DirAccess.get_files_at("res://shaders"):
		if not file.ends_with(".gdshader"):
			continue
		var src: String = c._strip_comments(c._source("res://shaders/" + file, {}))
		rows.append({"name": file, "samplers": Checks.sampler_count(src), "ubo": Checks.ubo_bytes(src),
			"vary": Checks.varying_components(src), "kb": src.length() / 1024,
			"const_items": Checks.const_array_items(src)})
	for key in ["samplers", "ubo", "vary", "kb", "const_items"]:
		rows.sort_custom(func(x, y): return x[key] > y[key])
		var line := "%s:" % key
		for i in mini(top, rows.size()):
			line += " %s=%d" % [rows[i].name.trim_suffix(".gdshader"), rows[i][key]]
		print(line)
	print("shaders: %d" % rows.size())
	quit()
