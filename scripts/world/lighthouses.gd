class_name Lighthouses
extends RefCounted
## The harbour's two lights (fleet task "lighthouses", 2026-10-29): GULL POINT LIGHT, a
## Victorian lighthouse house with its lantern room on the headland's south-east cliff (the form of
## San Pedro's Point Fermin light), and HARBOR GATE LIGHT at the seaward end of a long rubble
## breakwater off the port (the form of the Angels Gate light on the San Pedro breakwater). Names
## invented. At night both lanterns turn: drawn beams (LighthouseKit.beam_mesh(), additive), a
## SpotLight3D carrying volumetric fog on Forward+ where the fog is on, and a point light seen from
## across the basin (lighthouse_lamp.gdshader, aircraft_lights.gdshader's never-smaller-than-a-few-
## pixels billboard) that FLASHES when a beam sweeps past the eye.
##
## Everything here is data in world XZ - the headland and the port are fixed geography
## (MacroMap.peninsula_*, port_rect), so no seed moves them - and is hung on the landmark
## machinery: Landmarks.all() appends entries(), each piece builds detailed in the FULL chunk that
## holds its anchor and far (no collision) everywhere else (CityStreamer's far landmarks). The
## breakwater is cut into SEG_LEN pieces, a landmark each, so the part round the player is the
## detailed one wherever along its 1.6 km they are. The lighthouse stands on a pad carved into the
## headland (carve(), one line in MacroMap.height_at()); the hills' scatter, planting and far trees
## keep off it (covers()). LIGHTHOUSES=0 in the environment: none of it (the A/B).

const LIGHT_ID := "gull_point_light"
const GATE_ID := "harbor_gate_light"
const SEG_PREFIX := "breakwater_"

const LIGHT_NAME := "GULL POINT LIGHT"
const GATE_NAME := "HARBOR GATE LIGHT"

## The lighthouse: the centre of its pad (world XZ) on the 17.6 m rim of the headland's south-east
## corner, and the way its porch faces (out to sea, south-east).
const LIGHT_AT := Vector2(2174.0, 6656.0)
const LIGHT_FRONT := Vector2(0.56, 0.83)
## The pad: level out to PAD_RADIUS, then cut at 1:1 / filled at 1:1.4 back to the ground out to
## PAD_REACH (the rim falls 10 m on its inland side and the fill closes that hollow round it).
const PAD_RADIUS := 21.0
const PAD_REACH := 40.0
const CUT_SLOPE := 1.0
const FILL_SLOPE := 1.0 / 1.4
## Pad level over the natural ground at the centre.
const PAD_LIFT := 0.0

## The breakwater's crest line, root to head (world XZ): from inside the headland's bank east of
## the lighthouse, south-east off the cove, then east across the bay a kilometre off the harbour.
const BREAKWATER := [Vector2(2163.0, 6702.0), Vector2(2560.0, 6905.0), Vector2(3740.0, 6964.0)]
## Pieces of the breakwater, one landmark each.
const SEG_LEN := 110.0
## Cross-section: the concrete walkway cap's top and width, the armour's crest (on either side of
## the cap), the faces' slope (horizontal per vertical) and the foot on the sea floor.
const CAP_TOP := 4.6
const CAP_WIDTH := 4.2
const CREST_Y := 4.1
const CREST_HALF := 3.6
const FACE_SLOPE := 1.5
const FOOT_Y := -3.2
## The breakwater light's pier block at the head: half size and top.
const PIER_HALF := 7.0
const PIER_TOP := 5.6
## Water level (the ocean chunks' plane).
const WATER_Y := 0.15

## The lights: rotation period (s), beams, colour, beam length (m), lantern centre height over the
## base (pad / pier top). Gull Point: white, a flash every 10 s (two panels, one turn in 20 s).
## Harbor Gate: green, a flash every 15 s (one panel).
const LIGHTS := {
	LIGHT_ID: {"period": 20.0, "beams": 2, "color": Color(1.0, 0.93, 0.78), "length": 1700.0, "lamp": 14.75, "phase": 0.13},
	GATE_ID: {"period": 15.0, "beams": 1, "color": Color(0.30, 1.0, 0.48), "length": 1300.0, "lamp": 13.4, "phase": 0.61},
}

static var _enabled: int = -1


static func enabled() -> bool:
	if _enabled < 0:
		_enabled = 0 if OS.get_environment("LIGHTHOUSES") == "0" else 1
	return _enabled == 1


## The landmark entries (Landmarks.all() appends them): the lighthouse, the breakwater's pieces and
## the head light. Radius 1 at sea (a radius drops city lots and calms relief; there is none
## there); the lighthouse's is its pad, which keeps the hill shells and the shells' lawn off it.
static func entries() -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	if not enabled():
		return out
	out.append({"id": LIGHT_ID, "anchor": LIGHT_AT, "radius": PAD_RADIUS})
	var segs := segments()
	for k in segs.size():
		var s: Dictionary = segs[k]
		out.append({"id": SEG_PREFIX + str(k), "anchor": (s.a + s.b) * 0.5, "radius": 1.0, "seg": k})
	out.append({"id": GATE_ID, "anchor": gate_at(), "radius": 1.0})
	return out


static func is_piece(id: String) -> bool:
	return id == LIGHT_ID or id == GATE_ID or id.begins_with(SEG_PREFIX)


## The breakwater cut into pieces: [{a, b, s0, s1}] along the crest line (s metres from the root).
static var _segs: Array = []


static func segments() -> Array:
	if not _segs.is_empty():
		return _segs
	var s := 0.0
	for i in BREAKWATER.size() - 1:
		var a: Vector2 = BREAKWATER[i]
		var b: Vector2 = BREAKWATER[i + 1]
		var length := a.distance_to(b)
		var n := maxi(1, int(round(length / SEG_LEN)))
		for k in n:
			var t0 := float(k) / n
			var t1 := float(k + 1) / n
			_segs.append({"a": a.lerp(b, t0), "b": a.lerp(b, t1), "s0": s + length * t0, "s1": s + length * t1,
				"first": i == 0 and k == 0, "last": i == BREAKWATER.size() - 2 and k == n - 1})
		s += length
	return _segs


## Total crest length.
static func breakwater_length() -> float:
	var segs := segments()
	return float((segs[segs.size() - 1] as Dictionary).s1)


## The head of the breakwater, where the light's pier stands.
static func gate_at() -> Vector2:
	return BREAKWATER[BREAKWATER.size() - 1]


## The breakwater's direction at its head (root to head).
static func gate_dir() -> Vector2:
	var n := BREAKWATER.size()
	return ((BREAKWATER[n - 1] as Vector2) - (BREAKWATER[n - 2] as Vector2)).normalized()


## Half the mound's width at height y (from the crest line).
static func half_width_at(y: float) -> float:
	if y >= CREST_Y:
		return CREST_HALF
	return CREST_HALF + (CREST_Y - y) * FACE_SLOPE


## Distance from world XZ `p` to the breakwater's crest line, and the s there.
static func nearest(p: Vector2) -> Vector2:
	var best := INF
	var best_s := 0.0
	var s := 0.0
	for i in BREAKWATER.size() - 1:
		var a: Vector2 = BREAKWATER[i]
		var b: Vector2 = BREAKWATER[i + 1]
		var ab := b - a
		var t := clampf((p - a).dot(ab) / ab.length_squared(), 0.0, 1.0)
		var d := p.distance_to(a + ab * t)
		if d < best:
			best = d
			best_s = s + ab.length() * t
		s += ab.length()
	return Vector2(best, best_s)


## True when world XZ `p` (grown by `margin`) is on the lighthouse's pad or the breakwater, so the
## hills' scatter, planting and the far trees keep off it (CityChunk._near_pad, Skyline).
static func covers(p: Vector2, margin: float) -> bool:
	if not enabled():
		return false
	if p.distance_squared_to(LIGHT_AT) < (PAD_RADIUS + 3.0 + margin) * (PAD_RADIUS + 3.0 + margin):
		return true
	if p.x < 2100.0 or p.y < 6640.0:
		return false
	return nearest(p).x < half_width_at(0.0) + margin


# --- The pad ---------------------------------------------------------------------------------------

## The pad's level for this map: the natural ground at its centre (cached per MacroMap).
static func pad_y(macro: MacroMap) -> float:
	if macro.has_meta("lighthouse_pad_y"):
		return float(macro.get_meta("lighthouse_pad_y"))
	var raw := macro.raw_height_at(LIGHT_AT)
	var y := raw + macro._relief_at(LIGHT_AT, raw) + PAD_LIFT
	macro.set_meta("lighthouse_pad_y", y)
	return y


## MacroMap.height_at()'s hook: the pad levelled, cut and filled back to the ground round it.
static func carve(macro: MacroMap, p: Vector2, h: float) -> float:
	if not enabled():
		return h
	var dx := p.x - LIGHT_AT.x
	var dz := p.y - LIGHT_AT.y
	if absf(dx) > PAD_REACH or absf(dz) > PAD_REACH:
		return h
	var d := sqrt(dx * dx + dz * dz)
	if d >= PAD_REACH:
		return h
	var y := pad_y(macro)
	if d <= PAD_RADIUS:
		return y
	var e := d - PAD_RADIUS
	var dh := h - y
	var reach := (CUT_SLOPE if dh > 0.0 else FILL_SLOPE) * e
	var off := minf(absf(dh), reach)
	# A rounded shoulder at the pad's edge, and handed back to the ground by PAD_REACH.
	off = minf(off, absf(dh) * smoothstep(0.0, 3.0, e))
	off = lerpf(off, absf(dh), smoothstep(PAD_REACH - PAD_RADIUS - 6.0, PAD_REACH - PAD_RADIUS, e))
	return y + signf(dh) * off


# --- Building -------------------------------------------------------------------------------------

## Landmarks.build()'s hook for every piece.
static func build(lm: Dictionary, parent: Node3D, statics: StaticBody3D, plan: CityPlan, detailed: bool) -> void:
	var id: String = lm.id
	# The far copies are built on the loading screen: build the near meshes there too.
	if not detailed:
		LighthouseKit.warm()
	if id == LIGHT_ID:
		var y := pad_y(plan.macro) if plan and plan.macro else 17.6
		LighthouseKit.build_lighthouse(parent, statics, Vector3(LIGHT_AT.x, y, LIGHT_AT.y), LIGHT_FRONT, detailed)
	elif id == GATE_ID:
		LighthouseKit.build_gate(parent, statics, gate_at(), gate_dir(), detailed)
	elif id.begins_with(SEG_PREFIX):
		LighthouseKit.build_breakwater(parent, statics, int(lm.get("seg", int(id.substr(SEG_PREFIX.length())))), plan, detailed)
