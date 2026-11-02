class_name PortMooring
extends RefCounted
## Mooring lines from the moored container ship to the quay's bollards (refcam port_crane: the
## ship lay a few metres off the quay with nothing holding her, which reads as a model floating
## on a mirror). Built by the quay chunk that owns each bollard (FULL only), in the sailor's
## pattern: head and stern lines run out ahead and astern, breast lines square across at bow and
## stern, springs cross from a chock near each end to bollards toward midships. Each line is two
## hawsers hanging in a shallow catenary. PORT_MOORING=0 is the A/B.

static var enabled: bool = OS.get_environment("PORT_MOORING") != "0"

## [bollard x from the ship's centre (lo, hi), chock x from the ship's centre]; a bollard in a
## span takes a line to that chock.
const PATTERN := [
	[-135.0, -104.0, -86.0], # head lines
	[-86.0, -70.0, -78.0], # bow breast
	[-44.0, -26.0, -60.0], # forward spring
	[26.0, 44.0, 60.0], # aft spring
	[72.0, 90.0, 80.0], # stern breast
	[100.0, 132.0, 84.0], # stern lines
]
const ROPE_R := 0.055
const SAG := 0.7
const ROPE_COLOR := Color(0.74, 0.7, 0.6)


## The lines for the bollards at `bollards` (world x, y top, z) of a quay chunk; `ship` the
## moored ship's anchor (plan XZ). Returns a MeshInstance3D (or null) in the chunk's space.
static func build(bollards: Array, ship: Vector2) -> MeshInstance3D:
	if not enabled or ship.x == INF:
		return null
	var b := PortKit.Buf.new()
	b.color = ROPE_COLOR
	b.part = PortKit.S_PAINT
	var n := 0
	for at: Vector3 in bollards:
		var rel := at.x - ship.x
		for row: Array in PATTERN:
			if rel < float(row[0]) or rel >= float(row[1]):
				continue
			var cx: float = row[2]
			var chock := Vector3(ship.x + cx, PortKit._ship_deck_y(cx) + 1.1, ship.y - PortKit._ship_half_beam(cx, true) + 0.15)
			for k in 2:
				var off := Vector3(0.0, 0.0, 0.0) if k == 0 else Vector3(0.0, 0.25, 0.0)
				_rope(b, chock + off + Vector3(0.35 * k, 0.0, 0.0), at + Vector3(0.12 * k, 0.55, 0.0))
				n += 1
	if n == 0:
		return null
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, b.arrays())
	mesh.surface_set_material(0, PortKit.steel_material())
	var mi := MeshInstance3D.new()
	mi.name = "MooringLines"
	mi.mesh = mesh
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
	mi.visibility_range_end = 420.0
	return mi


## A hawser from `a` to `b`, sagging SAG metres at the middle, in eight straight pieces.
static func _rope(b: PortKit.Buf, a: Vector3, c: Vector3) -> void:
	var segs := 8
	var prev := a
	for i in range(1, segs + 1):
		var t := float(i) / float(segs)
		var p := a.lerp(c, t) + Vector3.DOWN * SAG * 4.0 * t * (1.0 - t)
		b.cyl(prev, p, ROPE_R, 5)
		prev = p
