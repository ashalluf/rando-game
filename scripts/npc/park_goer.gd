class_name ParkGoer
extends Pedestrian
## Somebody using a rec park or a school's grounds (Parks.people_steps()): an ordinary pedestrian -
## shot, knocked, bled and ragdolled like anyone, counted in the crowd cap, living the crowd-life
## layer (talks, phones, benches) - kept to the facility it came for instead of a block's pavement
## ring, and never crossing a road:
##   JOG    laps of a running track's lane (an oval: two straights and two bends), at a jog
##   LOOP   laps of a rec park's walking loop (a rect ring, the base ring walker on it), at a jog
##   PLAY   pickup basketball, a kickabout: short runs between spots on the court or the field
##   FIELD  a fielder on the diamond: stands at a position, now and then shuffles off it and back
##   HANG   round the playground or the picnic tables: strolls, stands, talks

enum Mode { JOG, LOOP, PLAY, FIELD, HANG }

var mode: int = Mode.HANG
## The oval (JOG): centre, long axis, half straight, radius of the lane run.
var oval_c := Vector2.ZERO
var oval_u := Vector2(1.0, 0.0)
var oval_hs: float = 40.0
var oval_r: float = 30.0
## Which way round (+1 / -1).
var oval_dir: float = 1.0


func setup_mode(m: int, area: Rect2, seed_value: int) -> void:
	mode = m
	var side := 2.0
	match m:
		Mode.LOOP:
			side = Parks.WALK_W
		Mode.PLAY, Mode.FIELD, Mode.HANG:
			side = maxf(minf(area.size.x, area.size.y) * 0.5, 1.5)
	setup(area, side, seed_value)
	cross_chance = 0.0
	match m:
		Mode.JOG, Mode.LOOP:
			jogger_share = Vector2(1.0, 1.0)
			pause_chance = 0.0
		Mode.PLAY:
			jogger_share = Vector2(0.7, 0.7)
			pause_chance = 0.35
			pause_seconds = Vector2(1.0, 4.0)
			life_chance = 0.1
		Mode.FIELD:
			jogger_share = Vector2.ZERO
			pause_chance = 0.9
			pause_seconds = Vector2(6.0, 22.0)
			life_chance = 0.05
		Mode.HANG:
			jogger_share = Vector2.ZERO
			pause_chance = 0.6
			pause_seconds = Vector2(4.0, 14.0)
			life_chance = 0.6


func setup_oval(c: Vector2, u: Vector2, half_straight: float, r: float, seed_value: int) -> void:
	oval_c = c
	oval_u = u
	oval_hs = half_straight
	oval_r = r
	setup_mode(Mode.JOG, Rect2(c - Vector2(half_straight + r, r), Vector2(half_straight + r, r) * 2.0), seed_value)
	oval_dir = 1.0 if (seed_value & 1) == 0 else -1.0
	_target = _random_ring_point(_sidewalk)


## The park people live the crowd's life too (the jog clip, talking, benches).
func _lives() -> bool:
	return true


func _leisure_place() -> bool:
	return true


# --- The oval ---------------------------------------------------------------------------------

func _perimeter() -> float:
	return 4.0 * oval_hs + TAU * oval_r


## The point `s` metres round the oval from the start of its +v straight.
func _oval_at(s: float) -> Vector2:
	var v := Vector2(-oval_u.y, oval_u.x)
	s = fposmod(s, _perimeter())
	var straight := 2.0 * oval_hs
	var bend := PI * oval_r
	if s < straight:
		return oval_c + oval_u * (-oval_hs + s) + v * oval_r
	s -= straight
	if s < bend:
		var a := PI * 0.5 - s / oval_r
		return oval_c + oval_u * (oval_hs + cos(a) * oval_r) + v * (sin(a) * oval_r)
	s -= bend
	if s < straight:
		return oval_c + oval_u * (oval_hs - s) - v * oval_r
	s -= straight
	var a2 := -PI * 0.5 - s / oval_r
	return oval_c + oval_u * (-oval_hs + cos(a2) * oval_r) + v * (sin(a2) * oval_r)


## Where on the oval a point is (metres round it), by its nearest point.
func _oval_s(p: Vector2) -> float:
	var v := Vector2(-oval_u.y, oval_u.x)
	var d := p - oval_c
	var a := d.dot(oval_u)
	var b := d.dot(v)
	if absf(a) <= oval_hs:
		return (a + oval_hs) if b >= 0.0 else (2.0 * oval_hs + PI * oval_r + (oval_hs - a))
	var straight := 2.0 * oval_hs
	var bend := PI * oval_r
	if a > 0.0:
		var ang := atan2(b, a - oval_hs)
		return straight + (PI * 0.5 - ang) * oval_r
	var ang2 := atan2(b, a + oval_hs)
	return 2.0 * straight + bend + fposmod(-PI * 0.5 - ang2, TAU) * oval_r


func _random_ring_point(sidewalk: float) -> Vector2:
	if mode != Mode.JOG:
		return super._random_ring_point(sidewalk)
	var here := Vector2(position.x, position.z)
	var s := _oval_s(here) if here != Vector2.ZERO else _rng.randf() * _perimeter()
	return _oval_at(s + oval_dir * _rng.randf_range(30.0, 70.0))


func _ring_route(from: Vector2, to: Vector2) -> PackedVector2Array:
	if mode != Mode.JOG:
		return super._ring_route(from, to)
	var out := PackedVector2Array()
	var s0 := _oval_s(from)
	var s1 := _oval_s(to)
	var span := fposmod((s1 - s0) * oval_dir, _perimeter())
	var n := int(span / 6.0)
	for i in range(1, n):
		out.append(_oval_at(s0 + oval_dir * float(i) * 6.0))
	return out
