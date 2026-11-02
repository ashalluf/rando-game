class_name MetroLook
extends RefCounted
## The underground terminus judged from its platform (wave 7, refcam `metro_station`,
## docs/HANDOFF.md "The metro station refcam"): what MetroBuild draws differently with it on.
## - The polished terrazzo mirrors the light lines over it (metro_station.gdshader floor_mirror():
##   the reflected ray meets the ceiling's plane, each line spread by the floor's roughness and the
##   distance, emitted by Fresnel; halved on Forward+, which adds its own reflections).
## - The track walls carry ad lightboxes (the invented campaigns of the billboard atlas, posters
##   2:1) where they had four blank map boards a side; one map a side stays, and the bank's tiled
##   back wall over the island carries a bulletin.
## - The car's line bullet gets its white "C" (LightRailTrain, MetroLook.bullet_letter()).
## METRO_LOOK=0 in the environment is the A/B (the station as wave 3 built it).

static var enabled: bool = OS.get_environment("METRO_LOOK") != "0"

const ATLAS := "res://assets/textures/billboards/billboard_ads.jpg"
const ATLAS_SIZE := Vector2(2048.0, 3072.0)
## How strongly the floors mirror (metro_station.gdshader mirror_gain).
const MIRROR := 1.4
## Ad formats (billboard_face.gdshader cell()).
const BULLETIN := 0
const POSTER := 1


## The atlas rect of ad `i` in format `fmt` (billboard_face.gdshader's cell(), the same numbers),
## inset a texel and a half so the mips do not bleed the neighbours in: (x0, y0, x1, y1) in UV.
static func cell(fmt: int, i: int) -> Rect2:
	var o: Vector2
	var s: Vector2
	if fmt == POSTER:
		o = Vector2(float(i % 4) * 512.0, 1788.0 + float(i / 4) * 256.0)
		s = Vector2(512.0, 256.0)
	else:
		o = Vector2(float(i % 2) * 1024.0, float(i / 2) * 298.0)
		s = Vector2(1024.0, 298.0)
	return Rect2((o + Vector2(1.5, 1.5)) / ATLAS_SIZE, (s - Vector2(3.0, 3.0)) / ATLAS_SIZE)


## Which poster a station wall slot shows: a hash, never a roll (same on every seed).
static func ad_for(slot: Array) -> int:
	return int(hash(["metro_ad"] + slot)) % 12


## The bullet's letter on a car: a "C" as a flat arc (ring 300 degrees round, open toward
## `open_dir`) in the plane of `n`, centred at `c`: two triangles a segment, wound to face `n`.
static func bullet_letter(c: Vector3, n: Vector3, up: Vector3, r_out: float, r_in: float, col: Color) -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var side := up.cross(n).normalized()
	var segs := 20
	var a0 := deg_to_rad(35.0)
	var a1 := TAU - a0
	for i in segs:
		var t0 := lerpf(a0, a1, float(i) / float(segs))
		var t1 := lerpf(a0, a1, float(i + 1) / float(segs))
		# The opening faces the reader's right (a "C"): angle 0 along +side.
		var d0 := side * cos(t0) + up * sin(t0)
		var d1 := side * cos(t1) + up * sin(t1)
		var p := [c + d0 * r_in, c + d0 * r_out, c + d1 * r_out, c + d1 * r_in]
		for tri: Array in [[p[0], p[1], p[2]], [p[0], p[2], p[3]]]:
			var a: Vector3 = tri[0]
			var b: Vector3 = tri[1]
			var e: Vector3 = tri[2]
			if (b - a).cross(e - a).dot(n) > 0.0:
				# Godot's front faces wind clockwise: flip a counter-clockwise one.
				var tmp := b
				b = e
				e = tmp
			for v: Vector3 in [a, b, e]:
				st.set_normal(n)
				st.set_color(col)
				st.add_vertex(v)
	return st.commit()
