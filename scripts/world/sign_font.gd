class_name SignFont
extends RefCounted
## A stroke font for road signs (StreetSigns): every glyph is a few centre-line polylines in a cell
## one unit tall (y up, x from 0 to the glyph's width), drawn by SignKit as ribbons of a constant
## width, the way the US road alphabets are drawn (a pen of one width, square terminals, round
## bowls). Our own shapes, after the proportions of those alphabets (series C/D: narrow, open);
## nothing is copied from a font file. Upper case, digits and the few marks road names use; a
## character with no glyph draws as a space.

## Gap between glyphs, in cap heights (the pen's own width is added on top by layout()).
const TRACKING := 0.16
## A word space, in cap heights.
const SPACE := 0.42

static var _glyphs: Dictionary = {}


## [strokes, width] for character `ch` (strokes: Array of PackedVector2Array, open polylines; a
## closed one repeats its first point at the end).
static func glyph(ch: String) -> Array:
	if _glyphs.is_empty():
		_build()
	return _glyphs.get(ch.to_upper(), [[], SPACE])


## Lays `text` out at cap height `cap` with a pen `pen` wide (metres): the strokes in metres with
## the text's left edge at x 0 and its baseline at y 0, and the width it takes ([strokes, width]).
static func layout(text: String, cap: float, pen: float) -> Array:
	var out: Array = []
	var x := 0.0
	var first := true
	for i in text.length():
		var g := glyph(text[i])
		var strokes: Array = g[0]
		var w: float = g[1]
		if strokes.is_empty():
			x += w * cap
			first = true
			continue
		if not first:
			x += TRACKING * cap + pen
		for s: PackedVector2Array in strokes:
			var p := PackedVector2Array()
			for v in s:
				p.append(Vector2(x + v.x * cap, v.y * cap))
			out.append(p)
		x += w * cap
		first = false
	return [out, x]


## Points round an ellipse centred on (cx, cy), radii rx / ry, from a0 to a1 degrees
## (anticlockwise when a1 > a0), `n` segments.
static func _arc(cx: float, cy: float, rx: float, ry: float, a0: float, a1: float, n: int = 0) -> PackedVector2Array:
	if n <= 0:
		n = maxi(3, int(absf(a1 - a0) / 15.0))
	var p := PackedVector2Array()
	for i in n + 1:
		var a := deg_to_rad(lerpf(a0, a1, float(i) / n))
		p.append(Vector2(cx + cos(a) * rx, cy + sin(a) * ry))
	return p


static func _l(pts: Array) -> PackedVector2Array:
	var p := PackedVector2Array()
	for v: Vector2 in pts:
		p.append(v)
	return p


## Joins polylines end to start into one stroke (so the joint gets a mitre, not two caps).
static func _j(parts: Array) -> PackedVector2Array:
	var p := PackedVector2Array()
	for part: PackedVector2Array in parts:
		for v in part:
			if p.size() > 0 and p[p.size() - 1].distance_to(v) < 0.001:
				continue
			p.append(v)
	return p


static func _mirror(g: Array, w: float) -> Array:
	var out: Array = []
	for s: PackedVector2Array in g:
		var p := PackedVector2Array()
		for v in s:
			p.append(Vector2(w - v.x, 1.0 - v.y))
		out.append(p)
	return out


static func _build() -> void:
	var V := func(x: float, y: float) -> Vector2: return Vector2(x, y)
	var g := {}
	g["A"] = [[_l([V.call(0, 0), V.call(0.32, 1), V.call(0.64, 0)]), _l([V.call(0.12, 0.34), V.call(0.52, 0.34)])], 0.64]
	g["B"] = [[_j([_l([V.call(0, 0.52), V.call(0, 1), V.call(0.34, 1)]), _arc(0.34, 0.76, 0.22, 0.24, 90, -90), _l([V.call(0.34, 0.52), V.call(0, 0.52)])]),
		_j([_l([V.call(0, 0.52), V.call(0.36, 0.52)]), _arc(0.36, 0.26, 0.24, 0.26, 90, -90), _l([V.call(0.36, 0), V.call(0, 0), V.call(0, 0.52)])])], 0.6]
	g["C"] = [[_arc(0.33, 0.5, 0.33, 0.5, 48, 312, 20)], 0.62]
	g["D"] = [[_j([_l([V.call(0.26, 0), V.call(0, 0), V.call(0, 1), V.call(0.26, 1)]), _arc(0.26, 0.5, 0.34, 0.5, 90, -90, 12)])], 0.6]
	g["E"] = [[_l([V.call(0.52, 1), V.call(0, 1), V.call(0, 0), V.call(0.52, 0)]), _l([V.call(0, 0.52), V.call(0.42, 0.52)])], 0.52]
	g["F"] = [[_l([V.call(0.52, 1), V.call(0, 1), V.call(0, 0)]), _l([V.call(0, 0.52), V.call(0.42, 0.52)])], 0.5]
	g["G"] = [[_j([_arc(0.33, 0.5, 0.33, 0.5, 45, 352, 20), _l([V.call(0.66, 0.44), V.call(0.38, 0.44)])])], 0.66]
	g["H"] = [[_l([V.call(0, 0), V.call(0, 1)]), _l([V.call(0.58, 0), V.call(0.58, 1)]), _l([V.call(0, 0.52), V.call(0.58, 0.52)])], 0.58]
	g["I"] = [[_l([V.call(0, 0), V.call(0, 1)])], 0.0]
	g["J"] = [[_j([_l([V.call(0.44, 1), V.call(0.44, 0.26)]), _arc(0.22, 0.26, 0.22, 0.26, 0, -180, 9)])], 0.44]
	g["K"] = [[_l([V.call(0, 0), V.call(0, 1)]), _l([V.call(0.56, 1), V.call(0, 0.36)]), _l([V.call(0.19, 0.57), V.call(0.58, 0)])], 0.58]
	g["L"] = [[_l([V.call(0, 1), V.call(0, 0), V.call(0.46, 0)])], 0.4]
	g["M"] = [[_l([V.call(0, 0), V.call(0, 1), V.call(0.37, 0.18), V.call(0.74, 1), V.call(0.74, 0)])], 0.74]
	g["N"] = [[_l([V.call(0, 0), V.call(0, 1), V.call(0.6, 0), V.call(0.6, 1)])], 0.6]
	g["O"] = [[_arc(0.35, 0.5, 0.35, 0.5, 90, 450, 24)], 0.7]
	g["P"] = [[_j([_l([V.call(0, 0), V.call(0, 1), V.call(0.34, 1)]), _arc(0.34, 0.74, 0.24, 0.26, 90, -90, 9), _l([V.call(0.34, 0.48), V.call(0, 0.48)])])], 0.58]
	g["Q"] = [[_arc(0.35, 0.5, 0.35, 0.5, 90, 450, 24), _l([V.call(0.42, 0.22), V.call(0.72, -0.04)])], 0.72]
	g["R"] = [[_j([_l([V.call(0, 0), V.call(0, 1), V.call(0.34, 1)]), _arc(0.34, 0.74, 0.24, 0.26, 90, -90, 9), _l([V.call(0.34, 0.48), V.call(0, 0.48)])]), _l([V.call(0.3, 0.48), V.call(0.6, 0)])], 0.6]
	g["S"] = [[_j([_arc(0.29, 0.75, 0.27, 0.25, 25, 270, 12), _arc(0.3, 0.25, 0.29, 0.25, 90, -155, 12)])], 0.59]
	g["T"] = [[_l([V.call(0, 1), V.call(0.58, 1)]), _l([V.call(0.29, 1), V.call(0.29, 0)])], 0.58]
	g["U"] = [[_j([_l([V.call(0, 1), V.call(0, 0.3)]), _arc(0.3, 0.3, 0.3, 0.3, 180, 360, 12), _l([V.call(0.6, 0.3), V.call(0.6, 1)])])], 0.6]
	g["V"] = [[_l([V.call(0, 1), V.call(0.32, 0), V.call(0.64, 1)])], 0.64]
	g["W"] = [[_l([V.call(0, 1), V.call(0.2, 0), V.call(0.43, 0.78), V.call(0.66, 0), V.call(0.86, 1)])], 0.86]
	g["X"] = [[_l([V.call(0, 1), V.call(0.6, 0)]), _l([V.call(0, 0), V.call(0.6, 1)])], 0.6]
	g["Y"] = [[_l([V.call(0, 1), V.call(0.31, 0.5), V.call(0.62, 1)]), _l([V.call(0.31, 0.5), V.call(0.31, 0)])], 0.62]
	g["Z"] = [[_l([V.call(0, 1), V.call(0.56, 1), V.call(0, 0), V.call(0.58, 0)])], 0.58]
	g["0"] = [[_arc(0.3, 0.5, 0.3, 0.5, 90, 450, 22)], 0.6]
	g["1"] = [[_l([V.call(0.04, 0.8), V.call(0.24, 1), V.call(0.24, 0)])], 0.3]
	g["2"] = [[_j([_arc(0.29, 0.71, 0.28, 0.29, 155, -35, 10), _l([V.call(0, 0), V.call(0.58, 0)])])], 0.58]
	g["3"] = [[_j([_arc(0.28, 0.75, 0.26, 0.25, 150, -90, 10), _arc(0.3, 0.26, 0.29, 0.26, 90, -150, 10)])], 0.59]
	g["4"] = [[_l([V.call(0.46, 0), V.call(0.46, 1), V.call(0, 0.3), V.call(0.62, 0.3)])], 0.62]
	g["5"] = [[_j([_l([V.call(0.54, 1), V.call(0.07, 1), V.call(0.03, 0.56)]), _arc(0.3, 0.32, 0.3, 0.32, 128, -145, 12)])], 0.6]
	var six := [_arc(0.31, 0.3, 0.3, 0.3, 90, 450, 18), _arc(0.43, 0.42, 0.42, 0.56, 72, 182, 8)]
	g["6"] = [six, 0.61]
	g["7"] = [[_l([V.call(0, 1), V.call(0.58, 1), V.call(0.18, 0)])], 0.58]
	g["8"] = [[_arc(0.29, 0.76, 0.25, 0.24, 270, 630, 18), _arc(0.29, 0.26, 0.29, 0.26, 90, 450, 18)], 0.58]
	g["9"] = [_mirror(six, 0.61), 0.61]
	g["."] = [[_l([V.call(0, 0), V.call(0, 0.04)])], 0.0]
	g[","] = [[_l([V.call(0.04, 0.06), V.call(-0.02, -0.12)])], 0.04]
	g["-"] = [[_l([V.call(0, 0.45), V.call(0.3, 0.45)])], 0.3]
	g["'"] = [[_l([V.call(0, 1), V.call(0, 0.76)])], 0.0]
	g["/"] = [[_l([V.call(0, 0), V.call(0.42, 1)])], 0.42]
	g[":"] = [[_l([V.call(0, 0), V.call(0, 0.04)]), _l([V.call(0, 0.6), V.call(0, 0.64)])], 0.0]
	g["&"] = [[_j([_l([V.call(0.62, 0), V.call(0.12, 0.62)]), _arc(0.26, 0.8, 0.16, 0.2, 200, -20, 8), _l([V.call(0.38, 0.66), V.call(0.08, 0.38)]), _arc(0.27, 0.22, 0.24, 0.22, 140, 330, 8), _l([V.call(0.5, 0.15), V.call(0.62, 0.36)])])], 0.62]
	_glyphs = g
