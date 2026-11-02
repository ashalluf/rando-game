extends Node
## A top-down hillshade of the oil field's relief, the drainages tinted green (OilField.drainage()),
## headless, seconds: godot --headless --path . res://tools/oil_field/topdown.tscn   (OUT=png path)
func _ready() -> void:
	var macro := MacroMap.new()
	macro.seed = 1337
	macro.setup()
	var f: OilField = macro.oil
	var n := 400
	var img := Image.create(n, n, false, Image.FORMAT_RGB8)
	var r := f.rect.grow(30.0)
	var hs := PackedFloat32Array()
	hs.resize(n * n)
	for j in n:
		for i in n:
			hs[j * n + i] = macro.relief_at(r.position + r.size * Vector2(float(i) / n, float(j) / n))
	var dx := r.size.x / n
	for j in range(1, n - 1):
		for i in range(1, n - 1):
			var gx := (hs[j * n + i + 1] - hs[j * n + i - 1]) / (2.0 * dx)
			var gz := (hs[(j + 1) * n + i] - hs[(j - 1) * n + i]) / (2.0 * dx)
			var nrm := Vector3(-gx, 1.0, -gz).normalized()
			var l := clampf(nrm.dot(Vector3(-0.5, 0.7, -0.5).normalized()), 0.0, 1.0)
			var dr := f.drainage(r.position + r.size * Vector2(float(i) / n, float(j) / n))
			img.set_pixel(i, j, Color(l * (1.0 - dr * 0.5), l, l * (1.0 - dr * 0.5)))
	img.save_png(OS.get_environment("OUT") if OS.get_environment("OUT") != "" else "user://oil_topdown.png")
	get_tree().quit()
