class_name AirRoute
extends RefCounted
## A flight path in TRUE world space (never local: see WorldState), sampled by distance flown:
## a ground track of straight legs joined by circular turns, with a height for every point.
## Ambient jets follow one of these instead of flying a physics model, which is what makes an
## arrival land on the runway centre line every time and a departure clear the same hills every
## time, and costs one lookup a tick. Built once by AirTraffic, shared by every flight on it.
##
## The ground track comes from waypoints with a turn radius per corner (the radius sets the
## bank the plane shows: bank = atan(v^2 / (g r))). Heights are set afterwards from a nominal
## profile (a glide slope, a climb gradient, a cruise level) and then lifted clear of whatever
## is under the route with clear(), which is the same grade-limited envelope Freeway uses to
## keep its deck out of the hills: the lowest profile that is above every obstacle and never
## climbs or descends steeper than it is allowed to.

## Spacing of the sampled points along the track (metres).
const STEP := 20.0

var xz: PackedVector2Array = PackedVector2Array()
var y: PackedFloat32Array = PackedFloat32Array()
## Distance flown to each point.
var dist: PackedFloat32Array = PackedFloat32Array()
## Heading at each point (yaw, forward = -Z) and the signed rate it turns at (rad per metre,
## positive = turning left).
var yaw: PackedFloat32Array = PackedFloat32Array()
var turn: PackedFloat32Array = PackedFloat32Array()
var length: float = 0.0
## Named distances along the route: "aim" and "runway_end" on arrivals, "runway_start",
## "liftoff" on departures.
var marks: Dictionary = {}
var name: String = ""


## The ground track through `points` (world XZ), each interior corner rounded with an arc of
## `radii[i]` metres (index as `points`; the first and last entries are unused). A radius too big
## for its two legs is shrunk until the arc fits in the middle 90 % of the shorter leg.
static func from_waypoints(points: PackedVector2Array, radii: PackedFloat32Array, route_name: String = "") -> AirRoute:
	var r := AirRoute.new()
	r.name = route_name
	var track := PackedVector2Array()
	track.append(points[0])
	var cursor := points[0]
	for i in range(1, points.size() - 1):
		var a := points[i - 1]
		var p := points[i]
		var b := points[i + 1]
		var u := (p - a).normalized()
		var v := (b - p).normalized()
		var cross := u.x * v.y - u.y * v.x
		var theta := acos(clampf(u.dot(v), -1.0, 1.0))
		var rad: float = radii[i] if i < radii.size() else 0.0
		if theta < 0.002 or rad <= 0.0:
			_straight(track, cursor, p)
			cursor = p
			continue
		var t := rad * tan(theta * 0.5)
		var room := minf(p.distance_to(cursor), p.distance_to(b)) * 0.45
		if t > room:
			t = room
			rad = t / tan(theta * 0.5)
		var s := p - u * t
		var e := p + v * t
		_straight(track, cursor, s)
		# In XZ, a positive cross turns the track toward (-u.y, u.x).
		var side := signf(cross)
		var centre := s + Vector2(-u.y, u.x) * side * rad
		var a0 := (s - centre).angle()
		var sweep := theta * side
		var steps := maxi(2, ceili(absf(sweep) * rad / STEP))
		for k in range(1, steps + 1):
			var ang := a0 + sweep * float(k) / float(steps)
			track.append(centre + Vector2(cos(ang), sin(ang)) * rad)
		cursor = e
	_straight(track, cursor, points[points.size() - 1])
	r._set_track(track)
	return r


## Appends points from `from` (already in the track) to `to`, at most STEP apart.
static func _straight(track: PackedVector2Array, from: Vector2, to: Vector2) -> void:
	var span := from.distance_to(to)
	if span < 0.01:
		return
	var steps := maxi(1, ceili(span / STEP))
	for k in range(1, steps + 1):
		track.append(from.lerp(to, float(k) / float(steps)))


func _set_track(track: PackedVector2Array) -> void:
	xz = track
	var n := track.size()
	dist.resize(n)
	y.resize(n)
	yaw.resize(n)
	turn.resize(n)
	var total := 0.0
	for i in n:
		if i > 0:
			total += track[i].distance_to(track[i - 1])
		dist[i] = total
		y[i] = 0.0
	length = total
	for i in n:
		var d: Vector2 = (track[mini(i + 1, n - 1)] - track[maxi(i - 1, 0)])
		yaw[i] = atan2(-d.x, -d.y)
	for i in n:
		var a := yaw[maxi(i - 1, 0)]
		var b := yaw[mini(i + 1, n - 1)]
		var ds := dist[mini(i + 1, n - 1)] - dist[maxi(i - 1, 0)]
		turn[i] = wrapf(b - a, -PI, PI) / maxf(ds, 0.01)


## Index of the point at or before distance `d`.
func index_at(d: float) -> int:
	var lo := 0
	var hi := dist.size() - 1
	if d <= 0.0:
		return 0
	if d >= length:
		return hi - 1
	while hi - lo > 1:
		var mid := (lo + hi) >> 1
		if dist[mid] <= d:
			lo = mid
		else:
			hi = mid
	return lo


## Everything a flight needs at distance `d`: world position, heading, turn rate and the grade
## of the height profile (rise over run).
func sample(d: float) -> Dictionary:
	var i := index_at(d)
	var j := mini(i + 1, dist.size() - 1)
	var span := maxf(dist[j] - dist[i], 0.001)
	var t := clampf((d - dist[i]) / span, 0.0, 1.0)
	var p := xz[i].lerp(xz[j], t)
	return {
		"pos": Vector3(p.x, lerpf(y[i], y[j], t), p.y),
		"yaw": lerp_angle(yaw[i], yaw[j], t),
		"turn": lerpf(turn[i], turn[j], t),
		"grade": (y[j] - y[i]) / span,
	}


func height_at(d: float) -> float:
	var i := index_at(d)
	var j := mini(i + 1, dist.size() - 1)
	var span := maxf(dist[j] - dist[i], 0.001)
	return lerpf(y[i], y[j], clampf((d - dist[i]) / span, 0.0, 1.0))


## The distance along the route nearest to world XZ `p` (a scan; setup and tests only).
func nearest(p: Vector2) -> float:
	var best := INF
	var at := 0.0
	for i in xz.size():
		var d2 := xz[i].distance_squared_to(p)
		if d2 < best:
			best = d2
			at = dist[i]
	return at


## Lifts the profile clear of `required` (a minimum height at every point) with the lowest
## envelope that never climbs steeper than `climb` or descends steeper than `descend` (both rise
## over run) toward or away from an obstacle, then keeps the higher of that and the profile. The
## maximum of two grade-limited profiles is grade-limited, so the result stays flyable.
func clear(required: PackedFloat32Array, climb: float, descend: float) -> void:
	var n := y.size()
	var fwd := PackedFloat32Array()
	fwd.resize(n)
	var back := PackedFloat32Array()
	back.resize(n)
	for i in n:
		fwd[i] = required[i]
		if i > 0:
			# After an obstacle, the path may come down at most `descend` per metre.
			fwd[i] = maxf(fwd[i], fwd[i - 1] - descend * (dist[i] - dist[i - 1]))
	for k in n:
		var i := n - 1 - k
		back[i] = fwd[i]
		if i < n - 1:
			# Before one, it may climb up to it at most `climb` per metre.
			back[i] = maxf(back[i], back[i + 1] - climb * (dist[i + 1] - dist[i]))
	for i in n:
		y[i] = maxf(y[i], back[i])
