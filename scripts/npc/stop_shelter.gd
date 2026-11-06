class_name StopShelter
extends RefCounted
## A bus queue in the rain (refcam `bus_stop_rain`, docs/HANDOFF.md "The bus stop in the rain"):
## StreetErrands lines its riders up along the kerb in front of the shelter (`add_stop`'s slots),
## which in a downpour left the people with no umbrella or hood standing in the open a metre from
## the roof, getting soaked. Once it rains past RainCrowd's SHELTER_LEVEL, someone with nothing to
## keep it off waits UNDER the roof instead: in front of the bench, spread along it by their slot.
## Those with an umbrella keep their place at the kerb. Pure; one hook in StreetErrands._start_bus().
## The switch is RainDusk's (RC5_BUS_STOP=0 puts every rider back on the kerb slots).

## Metres from the kerb to where a sheltering rider stands (the shelter's spot is 2.0 m in, its
## bench 0.5 m further back, its roof over 1.2 .. 2.8 m), and along the kerb by slot.
const IN_FROM_KERB := 1.75
const ALONG := [-1.25, 1.05, -0.15, 1.75, -1.95, 0.5]


## Where rider `p` waits in slot `slot` of `stop` (StreetErrands' dictionary), `at` the queue slot.
static func spot(p: Pedestrian, stop: Dictionary, slot: int, at: Vector2) -> Vector2:
	if not RainDusk.enabled or p == null or p.rain == null or slot < 0 or slot >= ALONG.size():
		return at
	if RainCrowd.rain_now() < RainCrowd.SHELTER_LEVEL or p.rain.gear != RainCrowd.Gear.NONE:
		return at
	var kerb: Vector2 = stop.kerb
	var inward: Vector2 = stop.inward
	var travel: Vector2 = stop.travel
	return kerb + inward * IN_FROM_KERB + travel * float(ALONG[slot])
