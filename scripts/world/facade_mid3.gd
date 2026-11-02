class_name FacadeMid3
extends RefCounted
## Generated buildings from 30-150 m (fleet wave 5, "facades-mid-3", 2026-11-01: "what still reads
## as a box with a window grid"). Shader work, shared by the near walls (building.gdshader) and the
## far boxes (building_lod.gdshader), every roll an integer hash of the building's shader seed
## (Building.seed % 1000) so a wall looks the same either side of the LOD line; no roll of the
## Building's own streams moves:
## - piers and recessed window strips on punched and slot-window walls
##   (shaders/facade_mid3.gdshaderinc, fm3_system()): the piers stand proud from the base to the
##   attic, their sides and their sun shadows worked out as coverage;
## - see docs/HANDOFF.md "Facades at mid distance, third pass" for the rest.
##
## `FACADES_MID3=0` in the environment turns all of it off (the A/B): the walls, the roofs and the
## far boxes draw exactly as before.

static var enabled: bool = OS.get_environment("FACADES_MID3") != "0"

## Pier systems (fm3_system()).
enum System { FLAT, EVERY_BAY, PAIRS }

## Building.Finish values the shader takes (render, brick, panels); glass walls have none.
const MAX_FINISH := 2


## The shader's wl_roll() (window_lights.gdshaderinc): the top 24 bits of wl_hash(), which is
## Building.shop_hash() bit for bit.
static func wl_roll(key: int, salt: int) -> float:
	return float(Building.shop_hash(key, salt) >> 8) / 16777216.0


## fm3_system(): the building's pier system from its shader seed, window style and finish.
static func system(shader_seed: int, window_style: int, finish: int) -> int:
	if (window_style != 0 and window_style != 3) or finish > MAX_FINISH:
		return System.FLAT
	var k := wl_roll(clampi(shader_seed, 0, 999), 120)
	if finish == 1:
		return System.FLAT if k < 0.22 else (System.EVERY_BAY if k < 0.68 else System.PAIRS)
	if finish == 2:
		return System.FLAT if k < 0.45 else System.EVERY_BAY
	return System.FLAT if k < 0.34 else (System.EVERY_BAY if k < 0.74 else System.PAIRS)


## Stepped and raised parapets: a share of masonry blocks raise the parapet in the middle of a
## street face - one panel, or two or three steps - the commonest roofline of the city's 1910s-1940s
## commercial blocks, and what keeps a street of them from being a row of flat-topped boxes. Built
## near as roof plant (Building._add_parapet_steps(), after the plant, so no prop's index moves) and
## far as roof plant boxes (FarBuilding), from this one list. Hashes of the seed only.
const PARAPET_ODDS := 0.52
const PARAPET_FACE_ODDS := 0.72
## The parapet band's own section (Building._add_facade_details' cap band): 5 cm proud, 42 cm in.
const PANEL_OUT := 0.05
const PANEL_IN := 0.42
const COPING_H := 0.12
const COPING_OUT := 0.14
const COPING_IN := 0.52


static func _h01(key: Array) -> float:
	return float(absi(hash(key)) % 100003) / 100003.0


## The raised parapet pieces of `b` (planned: plan_only() has run; `style` its style), in the
## building's own space: [[size, centre, Color], ...] - each step's panel, then its coping.
static func parapet_steps(b: Building, style: Dictionary) -> Array:
	var out: Array = []
	if not enabled or b.finish == Building.Finish.GLASS or b.shape == Building.Shape.WAREHOUSE:
		return out
	if b.window_style == Building.WindowStyle.CURTAIN or b.height < 8.0 or b.height > 75.0:
		return out
	if _h01([b.seed, "fm3 parapet"]) >= PARAPET_ODDS:
		return out
	var facade: Color = style.facade
	var panel_col := facade.lightened(0.06)
	var coping_col := (style.accent as Color).lightened(0.25)
	for pi in b.parts.size():
		var part: Dictionary = b.parts[pi]
		if int(part.get("podium", 0)) > 0:
			continue
		var size: Vector3 = part.size
		var c: Vector3 = part.center
		var top := c.y + size.y * 0.5
		if top < b.height - 0.01:
			continue
		var rise := b.parapet_rise(part)
		if rise <= 0.0:
			continue
		var base := top + rise - 0.11 - 0.04
		var faces := [[Vector3(1, 0, 0), Vector3(0, 0, 1), size.z, size.x], [Vector3(-1, 0, 0), Vector3(0, 0, 1), size.z, size.x],
			[Vector3(0, 0, 1), Vector3(1, 0, 0), size.x, size.z], [Vector3(0, 0, -1), Vector3(1, 0, 0), size.x, size.z]]
		for f in 4:
			if f + 1 == b.back_face:
				continue
			var n: Vector3 = faces[f][0]
			var a: Vector3 = faces[f][1]
			var length: float = faces[f][2]
			var depth: float = faces[f][3]
			if length < 9.0 or _h01([b.seed, "fm3 parapet face", pi, f]) >= PARAPET_FACE_ODDS:
				continue
			var kind := absi(hash([b.seed, "fm3 parapet kind", pi, f])) % 3
			var r := _h01([b.seed, "fm3 parapet h", pi, f])
			var steps: Array = []   # [width, height over the parapet]
			match kind:
				0:
					steps.append([clampf(length * 0.34, 3.5, 14.0), lerpf(1.1, 1.7, r)])
				1:
					var h1 := lerpf(0.6, 0.8, r)
					steps.append([length * 0.56, h1])
					steps.append([clampf(length * 0.26, 2.5, 9.0), h1 + lerpf(0.7, 1.0, 1.0 - r)])
				_:
					steps.append([length * 0.70, 0.5])
					steps.append([length * 0.42, lerpf(0.95, 1.15, r)])
					steps.append([clampf(length * 0.18, 2.2, 7.0), lerpf(1.55, 1.9, r)])
			var face_c := Vector3(c.x, 0.0, c.z) + n * depth * 0.5
			for s: Array in steps:
				var w: float = s[0]
				var h: float = s[1]
				var axis_size := a * w + n * (PANEL_OUT + PANEL_IN)
				var panel_size := Vector3(absf(axis_size.x), h, absf(axis_size.z))
				var panel_c := face_c + n * ((PANEL_OUT - PANEL_IN) * 0.5) + Vector3(0.0, base + h * 0.5, 0.0)
				out.append([panel_size, panel_c, panel_col])
				var cap_axis := a * (w + 0.2) + n * (COPING_OUT + COPING_IN)
				var cap_size := Vector3(absf(cap_axis.x), COPING_H, absf(cap_axis.z))
				var cap_c := face_c + n * ((COPING_OUT - COPING_IN) * 0.5) + Vector3(0.0, base + h + COPING_H * 0.5, 0.0)
				out.append([cap_size, cap_c, coping_col])
	return out
