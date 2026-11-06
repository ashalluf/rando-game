extends SceneTree
## MapPainter alone, in seconds: the plan and its map data without the city, drawn into a window
## (no relief: that needs the city's bake). opengl3 under Xvfb:
##
##   OUT=p.png AT=2620,250 PPM=0.54 YAW=0 SIZE=520 xvfb-run -a -s "-screen 0 1280x1024x24" godot \
##     --rendering-driver opengl3 --display-driver x11 --audio-driver Dummy --path . \
##     --script tools/minimap/painter_shot.gd --resolution 1280x1024
##
## FULL=1 draws it the full map's way (marks with district and street names).
var _ctl: Control
var _plan: CityPlan
var _data: MapData
var _at := Vector2(2620, 250)
var _ppm := 0.54
var _yaw := 0.0
var _size := 520.0


func _initialize() -> void:
	var sd := 1337
	var macro := MacroMap.new()
	macro.seed = sd
	macro.setup()
	_plan = CityPlan.new()
	_plan.seed = sd
	_plan.macro = macro
	_data = MapData.new(_plan)
	if OS.get_environment("AT") != "":
		var p := OS.get_environment("AT").split(",")
		_at = Vector2(float(p[0]), float(p[1]))
	if OS.get_environment("PPM") != "":
		_ppm = float(OS.get_environment("PPM"))
	if OS.get_environment("YAW") != "":
		_yaw = deg_to_rad(float(OS.get_environment("YAW")))
	if OS.get_environment("SIZE") != "":
		_size = float(OS.get_environment("SIZE"))
	_ctl = Control.new()
	_ctl.size = Vector2(_size, _size)
	_ctl.position = Vector2(20, 20)
	_ctl.draw.connect(_draw)
	var bg := ColorRect.new()
	bg.color = Minimap.COLORS.land
	bg.size = Vector2(_size, _size) + Vector2(40, 40)
	root.add_child(bg)
	root.add_child(_ctl)
	for i in 4:
		await process_frame
	var t0 := Time.get_ticks_usec()
	_ctl.queue_redraw()
	await process_frame
	await process_frame
	print("first frame ms=%.1f" % ((Time.get_ticks_usec() - t0) / 1000.0))
	var out := OS.get_environment("OUT")
	root.get_texture().get_image().save_png(out if out != "" else "painter.png")
	quit()


func _draw() -> void:
	var size := _ctl.size
	var v := MapPainter.View.new()
	v.xf = Transform2D(Vector2(_ppm, 0.0), Vector2(0.0, _ppm), size * 0.5 - _at * _ppm)
	v.k = _ppm
	v.ppm = _ppm
	var r := size.x / _ppm * 0.75
	v.area = Rect2(_at - Vector2.ONE * r, Vector2.ONE * r * 2.0)
	v.base = Transform2D(_yaw, size * 0.5) * Transform2D(0.0, -size * 0.5)
	v.yaw = _yaw
	v.screen = size
	v.full = OS.get_environment("FULL") == "1"
	var t0 := Time.get_ticks_usec()
	_data.ensure_rect(v.area)
	var t1 := Time.get_ticks_usec()
	_ctl.draw_set_transform_matrix(v.base)
	MapPainter.draw_geo(_ctl, v, _plan, _data)
	var t2 := Time.get_ticks_usec()
	MapPainter.draw_marks(_ctl, v, _plan, _data)
	var t3 := Time.get_ticks_usec()
	print("ensure %.2f ms  geo %.2f ms  marks %.2f ms" % [(t1 - t0) / 1000.0, (t2 - t1) / 1000.0, (t3 - t2) / 1000.0])
