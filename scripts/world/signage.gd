class_name Signage
extends RefCounted
## Lit commercial signage: backlit fascia lightboxes, projecting blade signs, neon tube
## lettering, illuminated canopy undersides and backlit pylon panels. Used by Commercial
## (plazas, big boxes, fast food, gas stations).
##
## Nothing here is a real light. Every lit surface is either the neon shader
## (shaders/neon_sign.gdshader, whose emission is driven by the `lamp_factor` shader global) or
## the existing additive night quad (shaders/light_pool.gdshader, through
## PropFactory.lamp_face() / PropFactory.light_pool()). That is the same trick the street lamps
## use: it costs nothing by day, comes on with night_factor, and comes on in a storm at noon
## too, because lamp_factor is max(night_factor, weather_darken * 0.85). A city with an
## OmniLight per shopfront would never render.
##
## Everything goes into the chunk's MultiMeshBatch under a handful of shared keys (K_BOX,
## K_TUBE, K_GLOW, K_POOL), so a whole plaza of lightboxes is one draw call and a whole
## forecourt of glow is another.
##
## Variation is hashed from world position, name and the city seed - never rolled off the
## chunk rng. An extra rng call in a seeded generation path shifts every downstream roll and
## moves the city.
##
## All business words are original. Never a real brand, ever.
##
## Static: call everything with the chunk.

# --- Tunables ---------------------------------------------------------------------------
# These are consts rather than @export because Signage is a static RefCounted that is never
# instantiated, the same way Commercial and PropFactory hold their numbers.

## Emission of a backlit plastic lightbox at full night. Over 1 so it blooms.
const BOX_NIGHT_EMISSION := 2.6
## Emission of a lightbox in daylight (real ones are lit in the day too, just invisibly).
const BOX_DAY_EMISSION := 0.10
## Emission of a neon tube or channel letter at night. Tubes read far hotter than a box.
const TUBE_NIGHT_EMISSION := 7.0
## Emission of a tube by day. Near zero: an unlit neon tube is clear glass, not a lit stick.
const TUBE_DAY_EMISSION := 0.04
## How much of its colour an unlit tube shows as paint (clear glass shows almost none).
const TUBE_ALBEDO := 0.18
## Emission of channel letters standing off a fascia box.
const LETTER_NIGHT_EMISSION := 4.2
## Strength of the tight additive halo around a lit sign.
const GLOW_STRENGTH := 1.9
## Strength of the soft pools of light signage throws on the ground and under canopies.
const POOL_STRENGTH := 1.35
## Odds a shop unit also gets a projecting blade sign out over the pavement. Only units
## without an awning are eligible, so the fraction that actually get one is about half this.
const BLADE_ODDS := 0.55
## Odds a shop window gets a small neon tube sign in it.
const WINDOW_NEON_ODDS := 0.45
## Odds a shop fascia is a neon colour rather than a white backlit box.
const COLOUR_FASCIA_ODDS := 0.55
## How bright a canopy underside light panel is relative to a shop lightbox. A petrol station
## canopy is the brightest thing in a night city; this is what sells that.
const CANOPY_GAIN := 1.5

## Neon and backlit-plastic colours. Saturated but not primary-crayon: real tubes are hot pink,
## ice blue, amber, lime, violet and warm white.
const NEON := [
	Color(1.00, 0.22, 0.45), Color(0.25, 0.72, 1.00), Color(1.00, 0.70, 0.24),
	Color(0.36, 1.00, 0.56), Color(0.72, 0.42, 1.00), Color(1.00, 0.95, 0.86),
	Color(1.00, 0.38, 0.14), Color(0.20, 0.95, 0.88),
]
## Warm white: the colour of a backlit plastic box and of most canopy lighting.
const WARM := Color(1.00, 0.93, 0.80)
## Cool white: newer LED fascias and forecourt lighting.
const COOL := Color(0.88, 0.95, 1.00)

## Short generic words for blade signs. Original, never a brand. Kept short: each distinct
## word is its own TextMesh and therefore its own MultiMesh draw in the chunk.
const BLADE_WORDS := ["OPEN", "24 HR", "EATS", "COLD", "DELI", "FRESH"]
## Short generic words for window neon. Original, never a brand.
const WINDOW_WORDS := ["OPEN", "24 HR", "ATM", "COFFEE"]

const K_BOX := "sign_box"
const K_TUBE := "sign_tube"
const K_GLOW := "sign_glow"
const K_POOL := "sign_pool"
const K_ARM := "sign_arm"

## "Not bolted to anything": the rows keep the per-instance ground lift, which is what
## something standing on the ground wants. See `_anchor()`.
const FREE := Vector2.INF

## How lettering is rendered. LIT is a channel letter that glows (bright letters on a coloured
## box); PRINT is opaque paint that stays dark while the box behind it lights up, which is what
## a white backlit lightbox actually looks like; TUBE is bare neon.
enum Letters { LIT, PRINT, TUBE }

static var _cache: Dictionary = {}


# --- Deterministic variation (hashed, never rng) ----------------------------------------

## 0..1 from a hash of `parts`. Same city seed and same place, same sign, for ever, and it
## costs no rng roll so nothing downstream moves.
static func chance(parts: Array) -> float:
	return float(hash(parts) & 0xffffff) / 16777216.0


static func pick_color(list: Array, parts: Array) -> Color:
	var c: Color = list[(hash(parts) & 0x7fffffff) % list.size()]
	return c


static func pick_word(list: Array, parts: Array) -> String:
	var w: String = list[(hash(parts) & 0x7fffffff) % list.size()]
	return w


## The sign colour for one business: warm or cool white for most (a backlit plastic box is
## usually white with the name printed on it), a neon colour for the rest.
static func sign_color(parts: Array) -> Color:
	if chance(parts + ["hue"]) < COLOUR_FASCIA_ODDS:
		return pick_color(NEON, parts + ["neon"])
	return WARM if chance(parts + ["warm"]) < 0.6 else COOL


# --- Frames ------------------------------------------------------------------------------

## The outward direction of a face whose yaw is `yaw` (forward is -Z, so yaw for a facing
## direction d is atan2(-d.x, -d.z); this is the inverse).
static func forward(yaw: float) -> Vector3:
	return Vector3(-sin(yaw), 0.0, -cos(yaw))


## The direction along the wall for a face at `yaw`, in world terms (+X when `yaw` is 0).
##
## It is NOT the local +X of `_face(yaw, ...)`. That basis is built from Basis(UP, yaw + PI),
## whose local +X works out as -along(yaw). To step sideways across a sign's own face - to put
## one word on each side of a double-sided panel - use `forward(yaw + PI * 0.5)`, which is that
## face's outward normal by definition. Reading this the other way round is what rendered every
## blade sign's lettering mirrored.
static func along(yaw: float) -> Vector3:
	return Vector3(cos(yaw), 0.0, -sin(yaw))


## A pure scale basis. Built from columns rather than Basis.scaled(), which scales in world
## axes and would shear a rotated sign.
static func _scale_basis(s: Vector3) -> Basis:
	return Basis(Vector3(s.x, 0.0, 0.0), Vector3(0.0, s.y, 0.0), Vector3(0.0, 0.0, s.z))


## The basis for a sign face looking along `yaw`: local +X runs along the wall, +Y is up, +Z is
## the outward normal (which is what both the quads and TextMesh read from).
static func _face(yaw: float, s: Vector3, pitch: float = 0.0) -> Basis:
	return Basis(Vector3.UP, yaw + PI) * Basis(Vector3.RIGHT, pitch) * _scale_basis(s)


# --- Meshes and materials ----------------------------------------------------------------

static func _material(key: String, albedo_mix: float, day: float, night: float, rough: float) -> ShaderMaterial:
	if _cache.has(key):
		return _cache[key]
	var mat := ShaderMaterial.new()
	mat.shader = load("res://shaders/neon_sign.gdshader")
	mat.set_shader_parameter("albedo_mix", albedo_mix)
	mat.set_shader_parameter("day_emission", day)
	mat.set_shader_parameter("night_emission", night)
	mat.set_shader_parameter("base_roughness", rough)
	_cache[key] = mat
	return mat


static func box_material() -> ShaderMaterial:
	return _material("sign_box_mat", 1.0, BOX_DAY_EMISSION, BOX_NIGHT_EMISSION, 0.4)


static func tube_material() -> ShaderMaterial:
	return _material("sign_tube_mat", TUBE_ALBEDO, TUBE_DAY_EMISSION, TUBE_NIGHT_EMISSION, 0.15)


static func letter_material() -> ShaderMaterial:
	return _material("sign_letter_mat", 0.85, BOX_DAY_EMISSION, LETTER_NIGHT_EMISSION, 0.35)


## Opaque printed lettering: no emission at all, so the name stays a dark silhouette on a box
## that is glowing behind it. Lit letters on a white lightbox would wash the name out.
static func print_material() -> ShaderMaterial:
	return _material("sign_print_mat", 1.0, 0.0, 0.0, 0.55)


## A 1 m cube with the lightbox material; instances scale it to the panel they want, so every
## backlit box in the chunk shares one mesh and one draw.
static func box_mesh() -> Mesh:
	return _unit_box("sign_box_mesh", box_material())


static func tube_mesh() -> Mesh:
	return _unit_box("sign_tube_mesh", tube_material())


static func _unit_box(key: String, mat: Material) -> Mesh:
	if _cache.has(key):
		return _cache[key]
	var mesh := BoxMesh.new()
	mesh.size = Vector3.ONE
	mesh.material = mat
	_cache[key] = mesh
	return mesh


static func glow_mesh() -> Mesh:
	if _cache.has("sign_glow_mesh"):
		return _cache["sign_glow_mesh"]
	# White tint: the per-instance colour does the tinting, so one mesh covers every colour.
	var mesh := PropFactory.lamp_face(Color.WHITE, GLOW_STRENGTH)
	_cache["sign_glow_mesh"] = mesh
	return mesh


static func pool_mesh() -> Mesh:
	if _cache.has("sign_pool_mesh"):
		return _cache["sign_pool_mesh"]
	var mesh := PropFactory.light_pool(Color.WHITE, POOL_STRENGTH)
	_cache["sign_pool_mesh"] = mesh
	return mesh


static func text_mesh(txt: String, height: float, style: Letters) -> Mesh:
	var key := "sign_tm_%s_%.2f_%d" % [txt, height, int(style)]
	if _cache.has(key):
		return _cache[key]
	var tm := TextMesh.new()
	tm.text = txt
	tm.font_size = 48
	tm.pixel_size = height / 48.0
	# Channel letters are boxes standing off the fascia, not decals, so give them real depth.
	tm.depth = 0.02 if style == Letters.TUBE else 0.06
	tm.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	tm.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	match style:
		Letters.TUBE:
			tm.material = tube_material()
		Letters.PRINT:
			tm.material = print_material()
		_:
			tm.material = letter_material()
	_cache[key] = tm
	return tm


# --- Instance rows -----------------------------------------------------------------------
# Every piece is returned as a [key, mesh, transform, colour] row, which is exactly what both
# MultiMeshBatch.add() and CityChunk._add_prop() take. Returning them rather than adding them
# lets a sign ride inside a breakable prop's instance list, so shooting a pylon takes its
# light with it.

## A backlit plastic lightbox. `size` is (width along the wall, height, thickness); `yaw` is
## the yaw of the face's outward normal, the same convention the shop text uses.
static func panel(at: Vector3, size: Vector3, yaw: float, color: Color) -> Array:
	return [K_BOX, box_mesh(), Transform3D(_face(yaw, size), at), color]


## A neon tube or a glowing accent bar. Same shape as a panel, far hotter and nearly clear
## when it is off.
static func tube(at: Vector3, size: Vector3, yaw: float, color: Color) -> Array:
	return [K_TUBE, tube_mesh(), Transform3D(_face(yaw, size), at), color]


## The tight additive halo around a lit sign. `pitch` 0 faces out along `yaw`, -PI/2 lies flat
## facing up, +PI/2 faces straight down (a canopy underside). The colour's alpha scales it.
static func glow(at: Vector3, size: Vector2, yaw: float, color: Color, pitch: float = 0.0) -> Array:
	return [K_GLOW, glow_mesh(), Transform3D(_face(yaw, Vector3(size.x, size.y, 1.0), pitch), at), color]


## A soft wide pool of light: a forecourt, a walkway, the ground under a canopy.
static func pool(at: Vector3, size: Vector2, color: Color, yaw: float = 0.0, pitch: float = -PI * 0.5) -> Array:
	return [K_POOL, pool_mesh(), Transform3D(_face(yaw, Vector3(size.x, size.y, 1.0), pitch), at), color]


## Channel letters or neon lettering, shrunk to fit `room` metres so a long name does not run
## across the shop next door.
static func text(txt: String, height: float, at: Vector3, yaw: float, color: Color, room: float,
		style: Letters = Letters.LIT) -> Array:
	# Rough advance width for this font, the same estimate Building uses for its shop names.
	var wide := float(txt.length()) * height * 0.62
	var fit: float = minf(1.0, room / maxf(wide, 0.01))
	var key := "sign_txt%d_%s_%.2f" % [int(style), txt, height]
	return [key, text_mesh(txt, height, style), Transform3D(_face(yaw, Vector3(fit, fit, 1.0)), at), color]


## Pushes rows into the chunk's batch. Signs never cast shadows: they are thin, self-lit and
## there are hundreds of them.
static func emit(chunk: CityChunk, rows: Array) -> void:
	# Pools lie flat on the tarmac, so tilt them to the ground slope the way the road markings
	# are tilted. Without this a 20 m pool on a rolling block sinks into the asphalt uphill and
	# the depth test eats half of it.
	chunk._batch.tilt_keys[K_POOL] = true
	for row: Array in rows:
		chunk._batch.add(row[0], row[1], row[2], row[3] if row.size() > 3 else Color.WHITE)
		chunk._batch.set_no_shadow(row[0])


## Re-bases `rows` onto the single ground sample at `anchor`, cancelling the per-instance lift.
##
## MultiMeshBatch.add() raises every instance by the city relief at that instance's own XZ.
## That is right for anything standing on the ground - a pool of light on the tarmac, a lamp -
## and wrong for anything bolted to a structure: CityChunk._add_slab() lifts a solid box by ONE
## sample, at its centre, so a wall or a forecourt canopy is dead flat while the signage screwed
## to it follows the slope underneath and tears off it. MacroMap.relief_height is 22 m, so the
## gap is centimetres over a shopfront and a metre-plus across a big box: a 20 m canopy ring
## came apart into four bars at four heights, and the soffit panels (2 cm of clearance) sank
## into the slab on the uphill side.
##
## `anchor` is the XZ the structure itself was placed at; `FREE` leaves the rows alone. Rows are
## built fresh by each composed sign and Arrays are references, so this edits them in place.
static func _anchor(chunk: CityChunk, rows: Array, anchor: Vector2) -> Array:
	if anchor == FREE:
		return rows
	var base: float = chunk._gy(anchor.x, anchor.y)
	for row: Array in rows:
		var xform: Transform3D = row[2]
		xform.origin.y += base - chunk._gy(xform.origin.x, xform.origin.z)
		row[2] = xform
	return rows


## Marks rows that were added some other way (inside a breakable prop) as shadowless.
static func quiet(chunk: CityChunk, rows: Array) -> void:
	for row: Array in rows:
		chunk._batch.set_no_shadow(row[0])


# --- Composed signs ------------------------------------------------------------------------

## The full lit fascia over a shopfront: a backlit box, channel letters standing off it and the
## halo around them. `base` is the point on the wall face at ground level, `yaw` the yaw of the
## wall's outward normal, `stand` how far the box sits proud of the wall.
static func fascia(chunk: CityChunk, base: Vector3, yaw: float, band_y: float, width: float,
		box_h: float, stand: float, txt: String, text_h: float, color: Color,
		anchor: Vector2 = FREE) -> void:
	var f := forward(yaw)
	var at := base + Vector3(0.0, band_y, 0.0)
	# A white lightbox carries its name in opaque dark paint and glows around it; a coloured box
	# carries bright channel letters. White-on-white would be unreadable once it is lit.
	var warm := color.r > 0.85 and color.g > 0.85
	var letters := Color(0.14, 0.14, 0.18) if warm else Color(1.0, 0.97, 0.92)
	var letter_glow := color if not warm else Color(1.0, 0.9, 0.7)
	emit(chunk, _anchor(chunk, [
		panel(at + f * stand, Vector3(width, box_h, 0.14), yaw, color),
		text(txt, text_h, at + f * (stand + 0.12), yaw, letters, width * 0.86,
			Letters.PRINT if warm else Letters.LIT),
		glow(at + f * (stand + 0.24), Vector2(width * 1.1, box_h * 2.3), yaw,
			Color(letter_glow.r, letter_glow.g, letter_glow.b, 0.55)),
	], anchor))


## A thin glowing accent line: a fascia pinstripe, a roofline band, a kerb light.
static func stripe(chunk: CityChunk, at: Vector3, yaw: float, length: float, height: float,
		color: Color, halo: float = 1.0, anchor: Vector2 = FREE) -> void:
	var f := forward(yaw)
	emit(chunk, _anchor(chunk, [
		tube(at, Vector3(length, height, 0.10), yaw, color),
		glow(at + f * 0.14, Vector2(length, maxf(height * 5.0, 0.6)), yaw,
			Color(color.r, color.g, color.b, 0.45 * halo)),
	], anchor))


## The light a lit shopfront throws back onto its own wall and down onto the pavement. Cheap,
## and it is what stops a lit sign looking like a sticker on a dark wall.
## `base` is the wall face at y = 0; `ground_y` is the top of the pavement in front of it.
## `stand` has to clear anything proud of that wall - a big box's pilasters stick out 40 cm,
## and a wash behind them is a wash the pilasters eat.
static func wash(chunk: CityChunk, base: Vector3, yaw: float, y: float, width: float,
		height: float, color: Color, walkway: float = 0.0, ground_y: float = 0.0,
		stand: float = 0.18, anchor: Vector2 = FREE) -> void:
	var f := forward(yaw)
	# The wall glow is bolted to the wall, so it takes the wall's own ground sample; the pool is
	# painted on the pavement, which follows the relief per vertex, so it keeps its own.
	emit(chunk, _anchor(chunk, [glow(base + f * stand + Vector3(0.0, y, 0.0),
		Vector2(width, height), yaw, Color(color.r, color.g, color.b, 0.32))], anchor))
	if walkway <= 0.0:
		return
	# Centred well out from the wall: a pool centred on the wall would spend half of itself
	# inside the building, where the depth test throws it away.
	emit(chunk, [pool(base + f * (walkway * 0.75) + Vector3(0.0, ground_y + 0.10, 0.0),
		Vector2(width * 1.1, walkway * 1.5), Color(color.r, color.g, color.b, 0.5))])


## A projecting blade sign: a double-sided panel on a bracket out over the pavement, lit on
## both faces. This is the silhouette that reads as "shops" from down the street.
static func blade(chunk: CityChunk, base: Vector3, yaw: float, y: float, color: Color, txt: String,
		anchor: Vector2 = FREE) -> void:
	var f := forward(yaw)
	var side := yaw + PI * 0.5
	# The panel's own outward normal, which is the axis its two faces are offset along. NOT
	# along(yaw): _face() builds its basis from Basis(UP, yaw + PI), whose local +X is
	# -along(yaw), so offsetting by along() put each word on the far side of the panel from the
	# face it was turned to. One side showed the extruded back of the glyphs - the word read
	# mirrored - and the other sat behind the opaque panel and was depth-rejected, so both sides
	# of every blade sign were wrong. pylon_rows() does the same job with explicit +-Z offsets
	# and matching yaws, which is why it has always been right.
	var n := forward(side)
	var at := base + f * 0.95 + Vector3(0.0, y, 0.0)
	var warm := color.r > 0.85 and color.g > 0.85
	var letters := Color(0.14, 0.14, 0.18) if warm else Color(1.0, 0.97, 0.92)
	var rows := [
		[K_ARM, PropFactory.box(K_ARM, Vector3(0.07, 0.07, 1.0), Color(0.24, 0.24, 0.26)),
			Transform3D(_face(yaw, Vector3(1.0, 1.0, 1.15)), base + f * 0.55 + Vector3(0.0, y + 0.72, 0.0)), Color.WHITE],
		panel(at, Vector3(1.3, 1.3, 0.14), side, color),
	]
	for s: float in [1.0, -1.0]:
		var face_yaw := side if s > 0.0 else side + PI
		rows.append(text(txt, 0.32, at + n * (s * 0.10), face_yaw, letters, 1.1,
			Letters.PRINT if warm else Letters.LIT))
		rows.append(glow(at + n * (s * 0.20), Vector2(1.7, 1.9), face_yaw,
			Color(color.r, color.g, color.b, 0.5)))
	emit(chunk, _anchor(chunk, rows, anchor))


## A small neon tube sign in a shop window, with its halo on the glass.
static func window_neon(chunk: CityChunk, base: Vector3, yaw: float, y: float, color: Color,
		txt: String, anchor: Vector2 = FREE) -> void:
	var f := forward(yaw)
	var at := base + f * 0.16 + Vector3(0.0, y, 0.0)
	emit(chunk, _anchor(chunk, [
		text(txt, 0.30, at, yaw, color, 2.2, Letters.TUBE),
		glow(at + f * 0.06, Vector2(maxf(float(txt.length()) * 0.24, 1.0), 0.95), yaw,
			Color(color.r, color.g, color.b, 0.6)),
	], anchor))


## A glowing band around all four edges of a canopy or a roofline. `size` is the canopy's
## footprint; the band sits just outside it at `y`.
## `anchor` matters more here than anywhere else: the four bars sit 6 to 10 m from the centre
## of a 20 x 12 m canopy, so without it they are lifted by four different ground samples and the
## band steps at every corner instead of running round the fascia.
static func ring(chunk: CityChunk, center: Vector3, size: Vector2, y: float, height: float,
		color: Color, out: float = 0.07, anchor: Vector2 = FREE) -> void:
	var half := size * 0.5
	var edges := [
		[0.0, Vector3(center.x, y, center.z - half.y - out), size.x + out * 3.0],
		[PI, Vector3(center.x, y, center.z + half.y + out), size.x + out * 3.0],
		[PI * 0.5, Vector3(center.x - half.x - out, y, center.z), size.y + out * 3.0],
		[-PI * 0.5, Vector3(center.x + half.x + out, y, center.z), size.y + out * 3.0],
	]
	var rows := []
	for e: Array in edges:
		var yaw: float = e[0]
		var at: Vector3 = e[1]
		var length: float = e[2]
		rows.append(tube(at, Vector3(length, height, 0.12), yaw, color))
		rows.append(glow(at + forward(yaw) * 0.16, Vector2(length, height * 4.5), yaw,
			Color(color.r, color.g, color.b, 0.4)))
	emit(chunk, _anchor(chunk, rows, anchor))


## The underside of a canopy: a grid of recessed light panels, the glow hanging under each and
## broad pools on the ground below. A petrol station canopy is the brightest thing in any night
## city, which is exactly why it is worth this many quads.
static func canopy(chunk: CityChunk, center: Vector3, size: Vector2, under_y: float,
		cols: int, rows_n: int, color: Color, ground_y: float, gain: float = 1.0,
		anchor: Vector2 = FREE) -> void:
	var soffit := []
	for i in cols:
		for j in rows_n:
			var x: float = center.x + size.x * ((i + 0.5) / float(cols) - 0.5) * 0.78
			var z: float = center.z + size.y * ((j + 0.5) / float(rows_n) - 0.5) * 0.7
			var pw: float = size.x * 0.66 / float(cols)
			var pd: float = size.y * 0.55 / float(rows_n)
			# The lit panel itself, facing down, recessed into the soffit.
			soffit.append(tube(Vector3(x, under_y - 0.03, z), Vector3(pw, 0.06, pd), 0.0, color))
			# The glow hanging under it: this is what the eye reads as a lit canopy.
			soffit.append(glow(Vector3(x, under_y - 0.20, z), Vector2(pw * 1.9, pd * 1.9), 0.0,
				Color(color.r, color.g, color.b, 0.55 * gain), PI * 0.5))
	# The panels are recessed into the slab with about 2 cm to spare, so they have to ride the
	# slab's own ground sample; the pools are on the tarmac and ride the tarmac's.
	emit(chunk, _anchor(chunk, soffit, anchor))
	# Two broad pools on the forecourt. Wide falloff, so the tarmac lifts rather than getting a
	# hard disc painted on it.
	var pools := []
	for j in 2:
		var z: float = center.z + size.y * ((j + 0.5) * 0.5 - 0.5) * 0.9
		pools.append(pool(Vector3(center.x, ground_y + 0.10, z), Vector2(size.x * 1.25, size.y * 0.85),
			Color(color.r, color.g, color.b, 0.55 * gain)))
	emit(chunk, pools)


## The lit half of a pylon sign: a backlit face on each side of the panel, neon letters and the
## halo. Returned as instance rows rather than emitted, so they ride in the pylon's own
## breakable prop and shooting it takes its light with it.
static func pylon_rows(at: Vector3, width: float, panel_h: float, txt: String, color: Color, text_h: float) -> Array:
	var warm := color.r > 0.85 and color.g > 0.85
	var letters := Color(0.14, 0.14, 0.18) if warm else Color(1.0, 0.97, 0.92)
	var halo := color if not warm else Color(1.0, 0.9, 0.7)
	var rows := []
	for s: float in [1.0, -1.0]:
		# The +Z face of the pylon looks along +Z, whose yaw is PI; the -Z face's yaw is 0.
		var yaw: float = PI if s > 0.0 else 0.0
		var z: float = at.z + s * 0.22
		rows.append(panel(Vector3(at.x, at.y, z), Vector3(width - 0.2, panel_h - 0.16, 0.07), yaw, color))
		rows.append(text(txt, text_h, Vector3(at.x, at.y, at.z + s * 0.30), yaw, letters, width * 0.88,
			Letters.PRINT if warm else Letters.LIT))
		rows.append(glow(Vector3(at.x, at.y, at.z + s * 0.40), Vector2(width * 1.15, panel_h * 2.0), yaw,
			Color(halo.r, halo.g, halo.b, 0.55)))
	return rows
