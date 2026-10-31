class_name NightCity
extends RefCounted
## The far city at night: the numbers `shaders/far_traffic.gdshaderinc` and the night profiles in
## `shaders/window_lights.gdshaderinc` / `street_glow.gdshaderinc` share with GDScript (Skyline
## lays the freeway decks' pattern phase from PERIOD, FreewayKit the LOD decks', and
## tests/night_city_checks.gd holds the copies equal).

## Metres one car and its gap take in the light pattern, and the cells in its period.
const CELL := 14.0
const CELLS := 32.0
const PERIOD := CELL * CELLS

## Share of the lanes' cells taken, by hour, keys every two hours from midnight (traffic_level()).
const LEVEL_KEYS: Array[float] = [0.30, 0.16, 0.12, 0.45, 0.95, 0.70, 0.66, 0.72, 0.95, 0.80, 0.62, 0.48, 0.30]


static func traffic_level(hour: float) -> float:
	var h := fposmod(hour, 24.0)
	var f := h * 0.5
	var i := floori(f)
	var t := f - float(i)
	t = t * t * (3.0 - 2.0 * t)
	return lerpf(LEVEL_KEYS[clampi(i, 0, 12)], LEVEL_KEYS[clampi(i + 1, 0, 12)], t)


## Share of the lit offices still lit, by hour (window_lights.gdshaderinc window_hour_scale()).
const WINDOW_KEYS: Array[float] = [0.66, 0.46, 0.38, 0.52, 0.90, 1.0, 1.0, 1.0, 1.05, 1.25, 1.18, 1.04, 0.66]


static func window_hour_scale(hour: float) -> float:
	var f := fposmod(hour, 24.0) * 0.5
	var i := floori(f)
	var t := f - float(i)
	t = t * t * (3.0 - 2.0 * t)
	return lerpf(WINDOW_KEYS[clampi(i, 0, 12)], WINDOW_KEYS[clampi(i + 1, 0, 12)], t)


## Street lamps: sodium or LED by patch (street_glow.gdshaderinc lamp_led(), the same integer roll).
const LAMP_CELL := 420.0
const LAMP_CENTRE := Vector2(2800.0, 100.0)
## The two lamps' light: the near lamps' OmniLight3D and pool colours (CityChunk._add_lamp()).
const SODIUM_LIGHT := Color(1.0, 0.86, 0.62)
const LED_LIGHT := Color(0.86, 0.92, 1.0)


static func _lamp_hash(x: int) -> int:
	x &= 0xffffffff
	x ^= x >> 16
	x = (x * 2146121005) & 0xffffffff
	x ^= x >> 15
	x = (x * 2221713035) & 0xffffffff
	x ^= x >> 16
	return x


## True where the street lamps at this TRUE world point are LED (white), false sodium (orange).
static func lamp_led(world_xz: Vector2) -> bool:
	var cx := floori(world_xz.x / LAMP_CELL)
	var cz := floori(world_xz.y / LAMP_CELL)
	var key := ((cx + 32768) * 65536 + (cz + 32768)) & 0xffffffff
	var roll := float(_lamp_hash(key) >> 8) / 16777216.0
	var share := lerpf(0.72, 0.38, clampf((world_xz.distance_to(LAMP_CENTRE) - 2000.0) / 4500.0, 0.0, 1.0))
	return roll < share


static func lamp_light(world_xz: Vector2) -> Color:
	return LED_LIGHT if lamp_led(world_xz) else SODIUM_LIGHT


## The lamp pool's instance colour: white under sodium (the pool's own tint), and the LED's
## colour as a ratio of that tint (PropFactory.light_pool()).
static func pool_color(world_xz: Vector2) -> Color:
	return Color(0.86, 1.095, 1.72) if lamp_led(world_xz) else Color.WHITE
