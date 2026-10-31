# ambient-sound-2: the street's sound at eye level

No stills: this task is sound. This is what plays where (branch `wt/ambient-sound-2`,
docs/HANDOFF.md "The street at eye level"). `AMBIENT_SOUND_2=0` turns all of it off for an A/B.

## New sounds, and what triggers each

| Sound | Where / when | Driven by |
|---|---|---|
| Crowd footsteps (concrete, asphalt, grass, sand, wood, metal; 16 % in heels on hard ground) | the 6 walkers nearest you within 15 m, each at its own pace (~2 steps/s walking, ~3 running) | StreetSounds: their real speed + `Footsteps.surface_at()` |
| Shop door bell | a shopper going into a shop and coming back out, within 40 m | StreetErrands' shop errands |
| Car door: latch + swing, then slam | a parked car's driver getting out, a shopper getting in, a delivery driver | ErrandCar's door |
| Air brakes "psssht" | a bus or truck coming to a stand (bus stop, red light), within 80 m, once per stop | real traffic, by position |
| Your tyres on gravel / dirt | driving on grass, sand, a fire road or a dirt drive (not hill asphalt); silent in the air | ray under your car |
| Your tyres hissing on a wet road | rain-wet roads (wetness > 0.3), louder with speed | Weather.wetness |
| Traffic's wet hiss | the 3 nearest traffic cars on a wet road, instead of the dry roll | Ambience traffic voices |
| Leaves in the wind (bed) | leafy streets, parks, suburbs, hills; louder in wind / storm / Santa Ana; mostly gone in a car | Ambience `leaves` |
| The sea from afar (from the coast's direction) | up to ~2.4 km inland and from the hills, most at night, giving way to the surf at the beach | Ambience `sea_far` |
| Far dog barks | now come from a real dog nearby (yard dog, walker's dog) when there is one | Ambience `dog` one-shot |

## The mix at the audio probe's places (beds > 5 %; `tools/audio_probe.tscn`, HOUR=12 / 22)

| Place | Noon | 22:00 |
|---|---|---|
| downtown canyon (Flower) | city 1.00, crowd 0.67, traffic 0.42 | city_far 0.85, crowd 0.67 |
| under the 110 | city 1.00, freeway 1.00 | city_far 0.85, freeway 0.55 |
| midtown street | city 0.75, birds 0.12, **leaves 0.12** | city_far 0.75, crickets 0.22, **leaves 0.12** |
| LA River channel | river 1.00, birds 0.22, **leaves 0.21** | river 1.00, crickets 0.40, **leaves 0.21** |
| plaza | city 1.00, fountain 0.98 (no leaves) | city_far 0.85, fountain 0.98 |
| playground | playground 1.00, **leaves 0.10** | crickets 0.19, **leaves 0.10** |
| beach | surf 0.83, wind 0.37, **sea_far 0.17**, leaves 0.12 | surf 0.83, crickets 0.39, **sea_far 0.26** |
| hills | birds 0.60, **sea_far 0.55**, leaves 0.17 | crickets 1.00, **sea_far 0.85**, leaves 0.17 |

Sources: docs/ASSETS.md "The street at eye level audio" (Freesound CC0; the wet hiss synthesised).
Not heard by anyone yet: the cloud box has no audio output. Tune on the Mac:
`StreetSounds.walk_step_db` (-15), `Ambience.layer_db.leaves` (-15) / `sea_far` (-12), the tyre dBs.
