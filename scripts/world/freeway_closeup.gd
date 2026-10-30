class_name FreewayCloseup
extends RefCounted
## The freeway at speed, close up (wave 3, docs/HANDOFF.md "The freeway close up"): the deck's
## concrete (shaders/freeway_deck.gdshader: lane-wide slabs, skewed joints, tining, wheel paths,
## oil, skid marks, patches, overlay stretches, shoulders with grit, litter, weeds and a rumble
## strip), the close-up pass on the kit's own two shaders (`closeup` on freeway_structure /
## freeway_paint: barrier chips, graffiti on the barriers and fascias, sign panels with their
## seams, bolts, sheeting and dirt, raised markers you can see by day, the paint's tyre grime), and
## the rush hours' traffic (`spawn_skip()`: the freeway's empty slots fill by the hour).
## `FREEWAY_CLOSEUP=0` in the environment is the A/B: the old asphalt road material, the kit's
## shaders as they were, the old fill.

static var enabled := OS.get_environment("FREEWAY_CLOSEUP") != "0"

## The chance a free traffic slot is left empty (TrafficManager._maintain_freeway() rolls it,
## one roll a slot either way): 0.35 was the old flat rate; by the hour it runs from the rush's
## nose-to-tail to the small hours' scatter (NightCity.traffic_level(), 0.12 .. 0.95).
const SKIP_RUSH := 0.08
const SKIP_QUIET := 0.62

static var _deck_mat: ShaderMaterial


static func deck_material() -> ShaderMaterial:
	if _deck_mat == null:
		_deck_mat = ShaderMaterial.new()
		_deck_mat.shader = load("res://shaders/freeway_deck.gdshader")
		_deck_mat.set_shader_parameter("concrete_tex", PropFactory.texture("concrete", "Color"))
		_deck_mat.set_shader_parameter("concrete_nrm", PropFactory.texture("concrete", "NormalGL"))
		_deck_mat.set_shader_parameter("asphalt_tex", PropFactory.texture("asphalt_aerial", "Color"))
		_deck_mat.set_shader_parameter("asphalt_nrm", PropFactory.texture("asphalt_aerial", "NormalGL"))
		_deck_mat.set_shader_parameter("lane_inner", Freeway.LANE_INNER)
		_deck_mat.set_shader_parameter("lane_max", Freeway.LANE_MAX)
		_deck_mat.set_shader_parameter("outer_shoulder_min", Freeway.OUTER_SHOULDER_MIN)
		_deck_mat.set_shader_parameter("outer_inset", Freeway.LANE_OUTER_INSET)
		_deck_mat.set_shader_parameter("lanes", float(Freeway.LANES))
	return _deck_mat


## A light standard's head glows in the night air: NightAtmos's halo (a camera-facing quad that
## collapses by day) in the chunk's batch, the batch's relief taken back off (the deck is placed in
## true heights). Its strength: a freeway head is a bigger, brighter light than a street lamp's.
const HALO_SCALE := 1.15
const HALO_STRENGTH := 1.25


static func lamp_halo(chunk: CityChunk, at: Vector3, sodium: bool) -> void:
	if not enabled or not NightAtmos.enabled or chunk.capturing:
		return
	NightAtmos.ensure(chunk.get_parent())
	var col := NightAtmos.HALO_SODIUM if sodium else NightAtmos.HALO_LED
	var xf := Transform3D(Basis.from_scale(Vector3.ONE * NightAtmos.LAMP_HALO * HALO_SCALE), at - Vector3(0.0, chunk._gy(at.x, at.z), 0.0))
	chunk._batch.add(NightAtmos.HALO_KEY, NightAtmos.halo_mesh(), xf, col, Color(HALO_STRENGTH, 0.0, 0.0, 0.0))
	NightAtmos.finish_batch(chunk._batch)


## The share of free freeway slots left empty at `hour` (pure).
static func spawn_skip(hour: float) -> float:
	if not enabled:
		return 0.35
	var level := clampf((NightCity.traffic_level(hour) - 0.12) / (0.95 - 0.12), 0.0, 1.0)
	return lerpf(SKIP_QUIET, SKIP_RUSH, level)
