class_name FreewayFill
extends RefCounted
## How the freeway decks are filled with traffic (the freeway refcam, wave 4: at 13:00 the 110 by
## downtown had a handful of cars in a kilometre). TrafficManager._maintain_freeway() used to hand
## out ONE slot per `freeway_gap` (34 m) and direction for all four lanes, from the far end of the
## window up (so the cap ran out before the stretch in front of the player), with every lane's
## car on the same metre - a car per 136 lane-metres at best, and abreast when it came.
##
## Here every LANE has its own slots (`LANE_GAP` apart, jittered by a hash so lanes do not line
## up), the free ones are offered nearest the player first, the cap grows by `CAP_GAIN` and goes
## mostly to the route the player is on (`shares()`), and once a route is filled new cars only
## enter past `INFLOW_FROM` (out where a car is a few pixels; the flow brings them in). Cars far
## behind the flow leave at `retire_reach()` instead of 1.35 x freeway_range. The hour still
## decides how many free slots stay empty (FreewayCloseup.spawn_skip()), one roll a slot.
## `FREEWAY_FILL=0` in the environment is the A/B: the old fill exactly.

static var enabled := OS.get_environment("FREEWAY_FILL") != "0"

## Metres between one lane's slots (a car per slot at most; the follow rule keeps ~20 m).
const LANE_GAP := 42.0
## How much of a slot's length its car may be slid by its hash (so lanes do not line up).
const JITTER := 0.7
## The window filled nearest-first while a route is short of its share (load, teleport).
const DENSE_REACH := 420.0
## Once filled, new cars enter only this far from the player (both ends of the window).
const INFLOW_FROM := 330.0
## A route counts as short (fill mode) below this share of its cars.
const FILL_BELOW := 0.6
## The freeway car cap times this (the old cap left the deck nearly empty).
const CAP_GAIN := 1.7
## A route nearer than this gets a full share; at freeway_range a share of FAR_WEIGHT.
const NEAR_ROUTE := 120.0
const FAR_WEIGHT := 0.3
## Spawns queued per route per upkeep tick (fill / steady).
const PER_TICK_FILL := 16
const PER_TICK := 8


## The cap the freeway cars may reach, from TrafficManager.max_freeway_cars (which Quality scales).
static func cap(max_cars: int) -> int:
	return roundi(float(max_cars) * CAP_GAIN) if enabled else max_cars


## How far along its route a car may be from the player before it leaves (was 1.35 x range).
static func retire_reach(freeway_range: float) -> float:
	return minf(freeway_range * 1.35, DENSE_REACH + 260.0) if enabled else freeway_range * 1.35


## Cars per live route: `dists` are the routes' distances from the player (metres), `total` the
## cap. The route under the player takes a full share, far ones FAR_WEIGHT of one.
static func shares(dists: Array, total: int, freeway_range: float) -> Array[int]:
	var out: Array[int] = []
	if dists.is_empty():
		return out
	if not enabled:
		for d in dists:
			out.append(maxi(1, total / dists.size()))
		return out
	var w: Array[float] = []
	var sum := 0.0
	for d in dists:
		var k := clampf((float(d) - NEAR_ROUTE) / maxf(freeway_range - NEAR_ROUTE, 1.0), 0.0, 1.0)
		var wi := lerpf(1.0, FAR_WEIGHT, k)
		w.append(wi)
		sum += wi
	for wi in w:
		out.append(maxi(1, floori(float(total) * wi / sum)))
	return out


## The slot index of a car `t` metres along (its lane's own slots).
static func slot_of(t: float) -> int:
	return floori(t / LANE_GAP)


## Where in slot `slot` of (route, direction, lane) its car starts: a hash slides it along.
static func slot_t(ri: int, dir: int, li: int, slot: int) -> float:
	var h := absi(hash([ri, dir, li, slot, "fw_fill"]))
	return (float(slot) + 0.5 * (1.0 - JITTER) + JITTER * float(h % 1000) / 1000.0) * LANE_GAP


## The free slots to offer, nearest the player first: Array of [t, dir, li]. `taken` holds the
## occupied Vector3i(slot, dir, li); `anchor` is where along the route the player is; `filling`
## offers the whole dense window, else only the band past INFLOW_FROM.
static func candidates(ri: int, anchor: float, total_len: float, taken: Dictionary, filling: bool, lanes: int) -> Array:
	var out: Array = []
	var reach := DENSE_REACH
	var s0 := slot_of(maxf(0.0, anchor - reach))
	var s1 := slot_of(minf(total_len, anchor + reach))
	for slot in range(s0, s1 + 1):
		for dir: int in [1, -1]:
			for li in lanes:
				if taken.has(Vector3i(slot, dir, li)):
					continue
				var t := slot_t(ri, dir, li, slot)
				if t <= 1.0 or t >= total_len - 1.0:
					continue
				var d := absf(t - anchor)
				if d > reach or (not filling and d < INFLOW_FROM):
					continue
				out.append([d, t, dir, li])
	out.sort_custom(func(a: Array, b: Array) -> bool: return float(a[0]) < float(b[0]))
	for c in out:
		c.remove_at(0)
	return out
