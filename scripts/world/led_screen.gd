class_name LedScreen
extends RefCounted
## The giant LED screens on the arena and the entertainment plaza (shaders/led_screen.gdshader).
## The slides' names come from one small dot-matrix atlas built here once, at load, from a 5 x 7
## font: every brand on it is INVENTED (owner's rule: no real sponsor, team, company or
## building names in game text), and a dot-matrix face is what a stadium screen's own lettering
## looks like from the street anyway. Slides with an empty name are pure motion graphics.

const ATLAS_W := 256
## Pixel rows per slide in the atlas: 7 for the glyphs, two above and two below.
const SLIDE_H := 11

## What the screens show, in order. Brands made up for this game; the arena, the plaza and its
## theatre are the game's own places. Blank entries are motion-only slides.
const SLIDES := [
	"RANDO ARENA", "FIZZMO COLA", "", "KITE MOBILE", "TONIGHT 7:30", "PELICAN AIRWAYS",
	"", "GLIMMA WATCHES", "BLAZO BURGERS", "STARLIGHT PLAZA", "VELTRO MOTORS", "SUNDOG SHADES",
	"", "LIVE MUSIC", "GO RANDO GO", "",
]

## 5 x 7 glyphs, rows top to bottom, '#' lit.
const GLYPHS := {
	"A": [".###.", "#...#", "#...#", "#####", "#...#", "#...#", "#...#"],
	"B": ["####.", "#...#", "#...#", "####.", "#...#", "#...#", "####."],
	"C": [".####", "#....", "#....", "#....", "#....", "#....", ".####"],
	"D": ["####.", "#...#", "#...#", "#...#", "#...#", "#...#", "####."],
	"E": ["#####", "#....", "#....", "####.", "#....", "#....", "#####"],
	"F": ["#####", "#....", "#....", "####.", "#....", "#....", "#...."],
	"G": [".####", "#....", "#....", "#.###", "#...#", "#...#", ".###."],
	"H": ["#...#", "#...#", "#...#", "#####", "#...#", "#...#", "#...#"],
	"I": [".###.", "..#..", "..#..", "..#..", "..#..", "..#..", ".###."],
	"J": ["..###", "...#.", "...#.", "...#.", "...#.", "#..#.", ".##.."],
	"K": ["#...#", "#..#.", "#.#..", "##...", "#.#..", "#..#.", "#...#"],
	"L": ["#....", "#....", "#....", "#....", "#....", "#....", "#####"],
	"M": ["#...#", "##.##", "#.#.#", "#.#.#", "#...#", "#...#", "#...#"],
	"N": ["#...#", "##..#", "#.#.#", "#..##", "#...#", "#...#", "#...#"],
	"O": [".###.", "#...#", "#...#", "#...#", "#...#", "#...#", ".###."],
	"P": ["####.", "#...#", "#...#", "####.", "#....", "#....", "#...."],
	"Q": [".###.", "#...#", "#...#", "#...#", "#.#.#", "#..#.", ".##.#"],
	"R": ["####.", "#...#", "#...#", "####.", "#.#..", "#..#.", "#...#"],
	"S": [".####", "#....", "#....", ".###.", "....#", "....#", "####."],
	"T": ["#####", "..#..", "..#..", "..#..", "..#..", "..#..", "..#.."],
	"U": ["#...#", "#...#", "#...#", "#...#", "#...#", "#...#", ".###."],
	"V": ["#...#", "#...#", "#...#", "#...#", "#...#", ".#.#.", "..#.."],
	"W": ["#...#", "#...#", "#...#", "#.#.#", "#.#.#", "##.##", "#...#"],
	"X": ["#...#", "#...#", ".#.#.", "..#..", ".#.#.", "#...#", "#...#"],
	"Y": ["#...#", "#...#", ".#.#.", "..#..", "..#..", "..#..", "..#.."],
	"Z": ["#####", "....#", "...#.", "..#..", ".#...", "#....", "#####"],
	"0": [".###.", "#...#", "#..##", "#.#.#", "##..#", "#...#", ".###."],
	"1": ["..#..", ".##..", "..#..", "..#..", "..#..", "..#..", ".###."],
	"2": [".###.", "#...#", "....#", "...#.", "..#..", ".#...", "#####"],
	"3": ["####.", "....#", "....#", ".###.", "....#", "....#", "####."],
	"4": ["...#.", "..##.", ".#.#.", "#..#.", "#####", "...#.", "...#."],
	"5": ["#####", "#....", "####.", "....#", "....#", "#...#", ".###."],
	"6": [".###.", "#....", "#....", "####.", "#...#", "#...#", ".###."],
	"7": ["#####", "....#", "...#.", "..#..", ".#...", ".#...", ".#..."],
	"8": [".###.", "#...#", "#...#", ".###.", "#...#", "#...#", ".###."],
	"9": [".###.", "#...#", "#...#", ".####", "....#", "....#", ".###."],
	":": [".....", "..#..", "..#..", ".....", "..#..", "..#..", "....."],
	"!": ["..#..", "..#..", "..#..", "..#..", "..#..", ".....", "..#.."],
	"&": [".##..", "#..#.", "#.#..", ".#...", "#.#.#", "#..#.", ".##.#"],
	"-": [".....", ".....", ".....", "#####", ".....", ".....", "....."],
	".": [".....", ".....", ".....", ".....", ".....", ".##..", ".##.."],
	" ": [".....", ".....", ".....", ".....", ".....", ".....", "....."],
}

static var _atlas: ImageTexture
static var _widths: PackedFloat32Array = PackedFloat32Array()
static var _cache: Dictionary = {}


## The slide atlas, built once: each slide's name centred in its own SLIDE_H-pixel row.
static func atlas() -> ImageTexture:
	if _atlas:
		return _atlas
	var img := Image.create(ATLAS_W, SLIDE_H * SLIDES.size(), false, Image.FORMAT_L8)
	img.fill(Color.BLACK)
	_widths = PackedFloat32Array()
	_widths.resize(16)
	for k in SLIDES.size():
		var text: String = SLIDES[k]
		var w := text_width(text)
		_widths[k] = float(w)
		if w == 0:
			continue
		var x := int((ATLAS_W - w) / 2)
		for ch in text:
			var rows: Array = GLYPHS.get(ch, GLYPHS[" "])
			for r in 7:
				var row: String = rows[r]
				for c in 5:
					if row[c] == "#":
						img.set_pixel(x + c, k * SLIDE_H + 2 + r, Color.WHITE)
			x += 6
	_atlas = ImageTexture.create_from_image(img)
	return _atlas


## Pixel width of a name in the 5 x 7 face with one pixel between letters.
static func text_width(text: String) -> int:
	if text.is_empty():
		return 0
	return text.length() * 6 - 1


## A screen material. `aspect` is the screen's width over its height, `res` its LEDs across,
## `seed` desynchronises it from its neighbours. Cached per (aspect, res, seed).
static func material(aspect: float, res: float, seed_value: float, slide_seconds: float = 6.0) -> ShaderMaterial:
	var key := "%.2f_%.0f_%.2f_%.1f" % [aspect, res, seed_value, slide_seconds]
	if _cache.has(key):
		return _cache[key]
	var mat := ShaderMaterial.new()
	mat.shader = load("res://shaders/led_screen.gdshader")
	mat.set_shader_parameter("slides", atlas())
	mat.set_shader_parameter("atlas_w", float(ATLAS_W))
	mat.set_shader_parameter("slide_h", float(SLIDE_H))
	mat.set_shader_parameter("slide_count", SLIDES.size())
	mat.set_shader_parameter("slide_w", _widths)
	mat.set_shader_parameter("slide_seconds", slide_seconds)
	mat.set_shader_parameter("seed", seed_value)
	mat.set_shader_parameter("aspect", aspect)
	mat.set_shader_parameter("res", res)
	_cache[key] = mat
	return mat


## A flat screen quad of `size` (width, height) metres centred at `at`, facing `yaw` (the
## direction its face looks: forward is -Z). UV 0..1 from its top left. Added to `geo` under a
## surface of its own material.
static func add(geo: LandmarkGeo, key: String, at: Vector3, size: Vector2, face_yaw: float, res: float, seed_value: float) -> void:
	geo.use(key, material(size.x / size.y, res, seed_value))
	var fwd := Vector3(-sin(face_yaw), 0.0, -cos(face_yaw))
	# The right hand of someone standing in front of it, looking at it: (-fwd) x up. Written as
	# Signage.along() it comes out mirrored, which is exactly what that function's note warns of.
	var right := Vector3(-cos(face_yaw), 0.0, sin(face_yaw))
	var hw := right * size.x * 0.5
	var hh := Vector3.UP * size.y * 0.5
	geo.quad(key, at - hw + hh, at + hw + hh, at + hw - hh, at - hw - hh, fwd,
		Vector2(0.0, 0.0), Vector2(1.0, 0.0), Vector2(1.0, 1.0), Vector2(0.0, 1.0))
