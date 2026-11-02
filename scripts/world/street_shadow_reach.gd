class_name StreetShadowReach
## Small street furniture casts its shadow only near the camera (perf audit 2026-10-05,
## docs/HANDOFF.md, the perf-audit section). A bench, a bollard or a parking meter throws a shadow
## a metre or two long: past ~40-60 m the cascades are 10-30 cm a texel and it is a smudge under
## the prop, but every instance of the chunk's batch still went into all four cascades - downtown
## the benches alone were 179k shadow triangles, bollards 87k. MultiMeshBatch.set_shadow_reach()
## keeps each batch's own shadow (or its lighter twin) while one of its instances is within the
## reach of the camera; up close nothing changes. `SHADOW_REACH=0` on still_shot.gd turns every
## reach off (the A/B), as it does the facade kit's roofline.

## Batch key -> reach in metres.
const REACH := {
	"bench": 60.0, "bollard": 40.0, "bus_sign": 40.0, "meter": 40.0, "rack": 50.0,
	"sc_newsbox": 50.0, "cafe_set": 60.0, "hydrant": 40.0, "hydrant_aged": 40.0,
	"mailbox": 50.0, "planter": 60.0,
}


static func apply(chunk: CityChunk) -> void:
	if chunk.level != CityChunk.Level.FULL:
		return
	for key: String in REACH:
		chunk._batch.set_shadow_reach(key, float(REACH[key]))
