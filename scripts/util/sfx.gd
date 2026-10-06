extends Node
## Autoload: sound effects. Real CC0 samples from `assets/audio/` where they exist, with the old
## runtime synthesis as the fallback for anything missing, so the game never loses a sound.
## play() for one-shots at a position, loop_player() for engine / boost / weather loops the caller
## owns and pitches. Names with several samples pick a random take each time, never the take that
## name played last, so a rifle burst or a street of footsteps never repeats the same file twice
## in a row.
##
## Every sound, sample or synthesized, is normalised to `reference_loudness_db` before a call
## site's volume_db is added. Peak-normalised recordings are not equally loud - three takes of one
## gun landed 9.3 dB apart and a breaking prop landed 13 dB under the synth sound it replaced -
## so without this the mix is whatever the files happened to be mastered at.

## Overall trim on every sound, in dB. Turn the whole game's SFX up or down here, and only here:
## it sits on top of the normalisation, so moving it changes the level of everything and never the
## balance. +6 puts the one-shots within about 5 dB of the levels the synthesized build played at;
## the master bus limiter catches the transients that would otherwise overshoot at that level.
@export var master_volume_db: float = 6.0
## The level every sound is normalised to: the dB of its loudest 50 ms window. Samples are trimmed
## by the measured numbers in SAMPLE_LOUDNESS_DB, synthesized ones are measured at startup, so two
## takes of one gun, two different sounds, and a sample and the synth fallback it replaces all land
## at the same loudness and a call site's volume_db is the whole of the mix. Headroom: a sample's
## loudest transient lands at this level plus its crest factor plus master_volume_db, and the worst
## crest in the set is break_0's 18.6 dB, so -20 with the +6 master puts that one transient a few
## dB over full scale at point-blank range and everything else under it. The master bus limiter
## (_install_limiter) rounds those peaks off rather than letting the device clip them, so this
## pair sets the level and the limiter handles the overshoot.
@export var reference_loudness_db: float = -20.0
## Random pitch spread on each one-shot (0.06 = +/- 6%) so repeats never sound identical.
@export var pitch_variation: float = 0.06
## How far a one-shot can still be heard, in metres.
@export var max_distance: float = 220.0
## Loudness falloff scale for one-shots: bigger carries further before it fades.
@export var unit_size: float = 12.0
## How far a loop (engine, boost, rain) can still be heard, in metres.
@export var loop_max_distance: float = 120.0
## Loudness falloff scale for loops.
@export var loop_unit_size: float = 10.0
## One-shot players: this many sounds can overlap before the oldest is cut off. Read at startup.
@export var pool_size: int = 24
## Set false to ignore assets/audio/ and use the synthesized sounds instead (to A/B the samples).
@export var use_samples: bool = true

const MIX_RATE := 22050
const AUDIO_DIR := "res://assets/audio/"
## Window the loudness metric averages over. Short enough to read the body of an impact, long
## enough to ignore the single-sample transient that peak normalisation lines up.
const LOUDNESS_WINDOW := 0.05

## Real recordings, all CC0. Every name here also has a synthesized fallback below, so a missing
## or unimported file degrades to the old sound rather than to silence.
const SAMPLES := {
	"shot": ["shot_0.ogg", "shot_1.ogg", "shot_2.ogg"],
	# Three different pump guns (12 gauge, near the shooter) so no two blasts are the same
	# recording, and the pump being racked between them.
	"shotgun": ["shotgun_0.ogg", "shotgun_1.ogg", "shotgun_2.ogg"],
	"pump": ["pump_0.ogg"],
	"explosion": ["explosion_0.ogg", "explosion_1.ogg"],
	"rocket": ["rocket_0.ogg"],
	"break": ["break_0.ogg", "break_1.ogg", "break_2.ogg"],
	"glass": ["glass_0.ogg", "glass_1.ogg", "glass_2.ogg"],
	"crash": ["crash_0.ogg", "crash_1.ogg", "crash_2.ogg"],
	"land": ["land_0.ogg", "land_1.ogg"],
	"thud": ["thud_0.ogg", "thud_1.ogg"],
	"footstep": ["footstep_0.ogg", "footstep_1.ogg", "footstep_2.ogg",
		"footstep_3.ogg", "footstep_4.ogg", "footstep_5.ogg"],
	"horn": ["horn_0.ogg"],
	"engine_loop": ["engine_loop_0.ogg"],
	"boost_loop": ["boost_loop_0.ogg"],
	"rain": ["rain_0.ogg"],
	"wind": ["wind_0.ogg"],
	"ambience_city": ["ambience_city_0.ogg"],
	"thunder": ["thunder_0.ogg"],
	# Air traffic (scripts/world/air_traffic.gd): a real airliner take-off roar and a real police
	# helicopter overhead, each cut to a seamless loop.
	"jet_loop": ["jet_loop_0.ogg"],
	"rotor_loop": ["rotor_loop_0.ogg"],
	# A street vendor's generator on the back of a taco truck (StreetVendors): a real motor, CC0,
	# cut to a seamless loop.
	"generator": ["generator_0.ogg"],
	# People. Screams are five female takes and seven male yells from four different voices, so
	# a panicking street is a crowd and not one person on a loop; yelp is the pain grunt of
	# someone knocked down; gore is the wet crack of a limb coming off.
	"scream": ["scream_0.ogg", "scream_1.ogg", "scream_2.ogg", "scream_3.ogg", "scream_4.ogg",
		"scream_5.ogg", "scream_6.ogg", "scream_7.ogg", "scream_8.ogg", "scream_9.ogg",
		"scream_10.ogg", "scream_11.ogg"],
	"yelp": ["yelp_0.ogg", "yelp_1.ogg", "yelp_2.ogg", "yelp_3.ogg", "yelp_4.ogg", "yelp_5.ogg",
		"yelp_6.ogg"],
	"gore": ["gore_0.ogg", "gore_1.ogg", "gore_2.ogg", "gore_3.ogg", "gore_4.ogg", "gore_5.ogg",
		"gore_6.ogg"],
	# A real police wail recorded in the street (public domain): one cycle, looped.
	"siren": ["siren_0.ogg"],
	# The light rail (LightRailSystem, LightRailTrain): a crossing bell loop, light rail horns, a
	# struck crossing bell for the street gong, a tram running (CC0 / public domain).
	"rail_bell": ["rail_bell_0.ogg", "rail_bell_1.ogg"],
	"rail_horn": ["rail_horn_0.ogg", "rail_horn_1.ogg"],
	"rail_gong": ["rail_gong_0.ogg", "rail_gong_1.ogg", "rail_gong_2.ogg"],
	"rail_roll": ["rail_roll_0.ogg", "rail_roll_1.ogg"],
	# The freight line (FreightRailSystem): a five-chime horn's crossing pattern and one blast, a
	# freight train's wheels rolling past, its engines (CC0, Wikimedia Commons).
	"freight_horn": ["freight_horn_0.ogg"],
	"freight_horn_blast": ["freight_horn_blast_0.ogg"],
	"freight_roll": ["freight_roll_0.ogg", "freight_roll_1.ogg"],
	"freight_engine": ["freight_engine_0.ogg"],
	# Bullet impacts by surface (WeaponFX.impact()) and a spent case on the ground (BrassCasings):
	# Kenney's Impact Sounds (CC0).
	"hit_concrete": ["hit_concrete_0.ogg", "hit_concrete_1.ogg", "hit_concrete_2.ogg"],
	"hit_metal": ["hit_metal_0.ogg", "hit_metal_1.ogg", "hit_metal_2.ogg"],
	"hit_glass": ["hit_glass_0.ogg", "hit_glass_1.ogg", "hit_glass_2.ogg"],
	"hit_wood": ["hit_wood_0.ogg", "hit_wood_1.ogg", "hit_wood_2.ogg"],
	"hit_dirt": ["hit_dirt_0.ogg", "hit_dirt_1.ogg", "hit_dirt_2.ogg"],
	"hit_flesh": ["hit_flesh_0.ogg", "hit_flesh_1.ogg", "hit_flesh_2.ogg"],
	"casing": ["casing_0.ogg", "casing_1.ogg"],
	# The city's birds (Birds): rock doves cooing and a flock's wing claps taking off, crows,
	# house sparrows, a gull's call close by. Public-domain field recordings (docs/ASSETS.md).
	"pigeon_coo": ["pigeon_coo_0.ogg", "pigeon_coo_1.ogg", "pigeon_coo_2.ogg", "pigeon_coo_3.ogg"],
	"wings": ["wings_0.ogg", "wings_1.ogg", "wings_2.ogg", "wings_3.ogg"],
	"crow": ["crow_0.ogg", "crow_1.ogg", "crow_2.ogg", "crow_3.ogg"],
	"sparrow": ["sparrow_0.ogg", "sparrow_1.ogg"],
	"gull_close": ["gull_close_0.ogg", "gull_close_1.ogg"],
	# Traffic honking (TrafficAI): close car horns cut from the far horns' CC0 recordings
	# (tools/traffic_horns.py) - taps and double taps, and long leans on the horn.
	"car_horn": ["car_horn_0.ogg", "car_horn_1.ogg", "car_horn_2.ogg", "car_horn_3.ogg", "car_horn_4.ogg"],
	"car_horn_long": ["car_horn_long_0.ogg", "car_horn_long_1.ogg", "car_horn_long_2.ogg"],
	# The player's feet by surface (Footsteps): Kenney's Impact Sounds (CC0) for concrete, grass
	# and wood; Freesound CC0 recordings cut step by step for asphalt, sand and a metal deck.
	"footstep_concrete": ["footstep_concrete_0.ogg", "footstep_concrete_1.ogg", "footstep_concrete_2.ogg",
		"footstep_concrete_3.ogg", "footstep_concrete_4.ogg"],
	"footstep_asphalt": ["footstep_asphalt_0.ogg", "footstep_asphalt_1.ogg", "footstep_asphalt_2.ogg",
		"footstep_asphalt_3.ogg"],
	"footstep_grass": ["footstep_grass_0.ogg", "footstep_grass_1.ogg", "footstep_grass_2.ogg",
		"footstep_grass_3.ogg", "footstep_grass_4.ogg"],
	"footstep_sand": ["footstep_sand_0.ogg", "footstep_sand_1.ogg", "footstep_sand_2.ogg", "footstep_sand_3.ogg"],
	"footstep_metal": ["footstep_metal_0.ogg", "footstep_metal_1.ogg", "footstep_metal_2.ogg", "footstep_metal_3.ogg"],
	"footstep_wood": ["footstep_wood_0.ogg", "footstep_wood_1.ogg", "footstep_wood_2.ogg",
		"footstep_wood_3.ogg", "footstep_wood_4.ogg"],
	# The city bus at a stop (VehicleAudio): pneumatic doors, the chime, the kneel's air release
	# (two of the air-brake takes), and its diesel idling (a seamless loop).
	"bus_door": ["bus_door_0.ogg", "bus_door_1.ogg", "bus_door_2.ogg"],
	"bus_chime": ["bus_chime_0.ogg", "bus_chime_1.ogg"],
	"bus_kneel": ["bus_hiss_1.ogg", "bus_hiss_2.ogg"],
	"diesel_idle": ["diesel_idle_0.ogg"],
	# The light rail car's door chime (VehicleAudio.TrainVoice).
	"rail_chime": ["rail_chime_0.ogg", "rail_chime_1.ogg"],
	# A basketball bouncing on a court (ParkBall).
	"ball_dribble": ["ball_dribble_0.ogg", "ball_dribble_1.ogg", "ball_dribble_2.ogg", "ball_dribble_3.ogg"],
	# Parked cars' alarms after a blast or a hit (CarAlarm): a pulsing electronic siren, a
	# multi-tone warble cycle and a horn honking in time, real recordings (CC0), each looped.
	"car_alarm": ["car_alarm_0.ogg", "car_alarm_1.ogg", "car_alarm_2.ogg"],
	# The dogs (Dog): a big dog's bark close up, a small dog's yap, a yelp when one is hit. CC0
	# recordings (docs/ASSETS.md); the dogs pitch them by size.
	"bark_big": ["bark_big_0.ogg", "bark_big_1.ogg", "bark_big_2.ogg", "bark_big_3.ogg", "bark_big_4.ogg", "bark_big_5.ogg"],
	"bark_small": ["bark_small_0.ogg", "bark_small_1.ogg", "bark_small_2.ogg", "bark_small_3.ogg", "bark_small_4.ogg"],
	"dog_yelp": ["dog_yelp_0.ogg", "dog_yelp_1.ogg", "dog_yelp_2.ogg"],
	# Driving (DrivingFX): a sedan's tyres squealing (three loops), metal grinding on the road for
	# a scrape, an exhaust backfire. Freesound CC0 (docs/ASSETS.md).
	"skid": ["skid_0.ogg", "skid_1.ogg", "skid_2.ogg"],
	"scrape": ["scrape_0.ogg"],
	"backfire": ["backfire_0.ogg"],
	# Engines (EngineAudio): per profile an idle, three on-load loops (low / mid / high rpm) and a
	# coasting loop, a turbo whistle, a blow-off valve and a reversing alarm. Built in code by
	# tools/engine_audio.py (firing pulses through pipe and muffler; no CC0 recording was reachable).
	"eng_four_idle": ["eng_four_idle_0.ogg"], "eng_four_low": ["eng_four_low_0.ogg"], "eng_four_mid": ["eng_four_mid_0.ogg"],
	"eng_four_high": ["eng_four_high_0.ogg"], "eng_four_off": ["eng_four_off_0.ogg"], "eng_v8_idle": ["eng_v8_idle_0.ogg"],
	"eng_v8_low": ["eng_v8_low_0.ogg"], "eng_v8_mid": ["eng_v8_mid_0.ogg"], "eng_v8_high": ["eng_v8_high_0.ogg"],
	"eng_v8_off": ["eng_v8_off_0.ogg"], "eng_diesel_idle": ["eng_diesel_idle_0.ogg"], "eng_diesel_low": ["eng_diesel_low_0.ogg"],
	"eng_diesel_mid": ["eng_diesel_mid_0.ogg"], "eng_diesel_high": ["eng_diesel_high_0.ogg"], "eng_diesel_off": ["eng_diesel_off_0.ogg"],
	"eng_bus_idle": ["eng_bus_idle_0.ogg"], "eng_bus_low": ["eng_bus_low_0.ogg"], "eng_bus_mid": ["eng_bus_mid_0.ogg"],
	"eng_bus_high": ["eng_bus_high_0.ogg"], "eng_bus_off": ["eng_bus_off_0.ogg"], "eng_v12_idle": ["eng_v12_idle_0.ogg"],
	"eng_v12_low": ["eng_v12_low_0.ogg"], "eng_v12_mid": ["eng_v12_mid_0.ogg"], "eng_v12_high": ["eng_v12_high_0.ogg"],
	"eng_v12_off": ["eng_v12_off_0.ogg"], "eng_moto_idle": ["eng_moto_idle_0.ogg"], "eng_moto_low": ["eng_moto_low_0.ogg"],
	"eng_moto_mid": ["eng_moto_mid_0.ogg"], "eng_moto_high": ["eng_moto_high_0.ogg"], "eng_moto_off": ["eng_moto_off_0.ogg"],
	"eng_turbo": ["eng_turbo_0.ogg"], "eng_blowoff": ["eng_blowoff_0.ogg"], "eng_beeper": ["eng_beeper_0.ogg"],
}

## Loudest-50 ms level of every take above, in dB, in the same order, measured off the committed
## .ogg files. play() trims each take by `reference_loudness_db` minus its entry. These are
## measurements, not taste: re-measure a file if you replace it (mean square over a sliding 50 ms
## window, take the loudest window, 10*log10). Anything missing here is left untrimmed.
const SAMPLE_LOUDNESS_DB := {
	"shot": [-18.35, -12.10, -21.41],
	"shotgun": [-15.23, -15.21, -15.60],
	"pump": [-8.43],
	"explosion": [-18.02, -13.49],
	"rocket": [-12.17],
	"break": [-23.08, -21.79, -17.18],
	"glass": [-17.59, -21.24, -15.11],
	"crash": [-19.14, -21.64, -21.22],
	"land": [-13.06, -14.97],
	"thud": [-12.01, -10.20],
	"footstep": [-21.59, -23.16, -21.67, -22.83, -22.63, -24.13],
	"horn": [-14.04],
	"engine_loop": [-16.39],
	"boost_loop": [-15.45],
	"rain": [-20.06],
	"wind": [-16.11],
	"ambience_city": [-18.05],
	"thunder": [-10.47],
	"jet_loop": [-11.89],
	"rotor_loop": [-11.66],
	"generator": [-17.65],
	"scream": [-14.30, -13.93, -13.99, -14.16, -13.98, -14.02, -14.10, -14.14, -14.00, -14.01,
		-13.95, -13.96],
	"yelp": [-13.93, -13.96, -13.96, -14.10, -14.21, -14.11, -14.01],
	"gore": [-11.97, -13.00, -13.86, -12.48, -14.75, -12.11, -11.95],
	"siren": [-7.74],
	"rail_bell": [-21.97, -21.97],
	"rail_horn": [-8.74, -11.97],
	"rail_gong": [-4.88, -4.70, -4.61],
	"rail_roll": [-22.05, -22.04],
	"freight_horn": [-8.29],
	"freight_horn_blast": [-8.31],
	"freight_roll": [-28.58, -24.27],
	"freight_engine": [-10.51],
	"hit_concrete": [-8.91, -11.72, -8.43],
	"hit_metal": [-12.70, -13.98, -14.45],
	"hit_glass": [-15.20, -13.82, -14.37],
	"hit_wood": [-12.01, -9.16, -13.45],
	"hit_dirt": [-10.64, -9.93, -9.89],
	"hit_flesh": [-8.56, -9.17, -9.04],
	"casing": [-13.15, -11.68],
	"pigeon_coo": [-10.08, -6.31, -9.63, -7.81],
	"wings": [-21.93, -20.80, -23.89, -21.29],
	"crow": [-11.77, -11.39, -10.98, -8.73],
	"sparrow": [-12.15, -11.52],
	"gull_close": [-10.40, -9.05],
	"car_horn": [-9.55, -6.69, -7.36, -9.49, -9.55],
	"car_horn_long": [-10.32, -9.55, -7.31],
	"footstep_concrete": [-17.86, -19.00, -19.29, -18.24, -17.58],
	"footstep_asphalt": [-18.18, -17.94, -18.49, -19.47],
	"footstep_grass": [-17.79, -17.38, -17.99, -18.21, -17.73],
	"footstep_sand": [-25.68, -19.47, -22.70, -17.01],
	"footstep_metal": [-13.37, -14.76, -16.15, -13.26],
	"footstep_wood": [-13.87, -13.12, -12.58, -14.46, -12.63],
	"bus_door": [-12.51, -18.10, -11.80],
	"bus_chime": [-4.23, -4.23],
	"bus_kneel": [-11.75, -12.24],
	"diesel_idle": [-19.33],
	"rail_chime": [-9.14, -8.53],
	"ball_dribble": [-14.33, -14.77, -14.27, -14.01],
	"car_alarm": [-13.47, -9.24, -12.05],
	"bark_big": [-5.26, -4.88, -4.79, -3.41, -5.46, -5.02],
	"bark_small": [-16.59, -17.13, -17.65, -16.79, -18.89],
	"dog_yelp": [-11.57, -10.06, -6.64],
	"skid": [-15.27, -14.21, -10.02],
	"scrape": [-11.43],
	"backfire": [-2.58],
	"eng_four_idle": [-17.17], "eng_four_low": [-18.60], "eng_four_mid": [-18.86], "eng_four_high": [-18.99],
	"eng_four_off": [-19.18], "eng_v8_idle": [-17.91], "eng_v8_low": [-18.69], "eng_v8_mid": [-18.65],
	"eng_v8_high": [-18.91], "eng_v8_off": [-18.88], "eng_diesel_idle": [-20.74], "eng_diesel_low": [-18.69],
	"eng_diesel_mid": [-18.64], "eng_diesel_high": [-19.05], "eng_diesel_off": [-18.34], "eng_bus_idle": [-18.63],
	"eng_bus_low": [-17.89], "eng_bus_mid": [-18.54], "eng_bus_high": [-19.24], "eng_bus_off": [-18.53],
	"eng_v12_idle": [-18.93], "eng_v12_low": [-19.35], "eng_v12_mid": [-19.45], "eng_v12_high": [-19.46],
	"eng_v12_off": [-19.58], "eng_moto_idle": [-17.97], "eng_moto_low": [-17.82], "eng_moto_mid": [-18.66],
	"eng_moto_high": [-18.65], "eng_moto_off": [-19.12], "eng_turbo": [-21.32], "eng_blowoff": [-14.33],
	"eng_beeper": [-4.36],
}

## Sample names that have to loop. Set on the stream in code rather than in the .import file, so
## an .import regenerated by the editor can never silently drop the loop flag.
const LOOPING := ["engine_loop", "boost_loop", "rain", "wind", "ambience_city", "skid", "siren",
	"jet_loop", "rotor_loop", "generator", "rail_bell", "rail_roll", "diesel_idle", "rail_motor",
	"rail_hum", "car_alarm", "freight_roll", "freight_engine", "scrape",
	"eng_four_idle", "eng_four_low", "eng_four_mid", "eng_four_high", "eng_four_off", "eng_v8_idle", "eng_v8_low", "eng_v8_mid",
	"eng_v8_high", "eng_v8_off", "eng_diesel_idle", "eng_diesel_low", "eng_diesel_mid", "eng_diesel_high", "eng_diesel_off", "eng_bus_idle",
	"eng_bus_low", "eng_bus_mid", "eng_bus_high", "eng_bus_off", "eng_v12_idle", "eng_v12_low", "eng_v12_mid", "eng_v12_high",
	"eng_v12_off", "eng_moto_idle", "eng_moto_low", "eng_moto_mid", "eng_moto_high", "eng_moto_off", "eng_turbo", "eng_beeper"]

## The city's ambience (scripts/util/ambience.gd), all CC0 (sources in docs/ASSETS.md). Kept apart
## from SAMPLES only so the two lists read separately; both ship and both load the same way.
## Beds (amb_*) are 22-30 s seamless loops; the rest are one-shots the Ambience node drops round
## the listener. Every name here also has a synthesized fallback (_build_ambience_synth), built
## only when its files do not load: they are long, and startup should not pay for them twice.
const AMBIENCE_SAMPLES := {
	"amb_city": ["amb_city_0.ogg"],
	"amb_city_far": ["amb_city_far_0.ogg"],
	"amb_crowd": ["amb_crowd_0.ogg"],
	"amb_birds": ["amb_birds_0.ogg"],
	"amb_crickets": ["amb_crickets_0.ogg"],
	"amb_gale": ["amb_gale_0.ogg"],
	"amb_rain_heavy": ["amb_rain_heavy_0.ogg"],
	"amb_rain_roof": ["amb_rain_roof_0.ogg"],
	"amb_rain_car": ["amb_rain_car_0.ogg"],
	"amb_freeway": ["amb_freeway_0.ogg"],
	"amb_surf": ["amb_surf_0.ogg"],
	"amb_airport": ["amb_airport_0.ogg"],
	"amb_port": ["amb_port_0.ogg"],
	"car_roll": ["car_roll_0.ogg"],
	"car_pass": ["car_pass_0.ogg", "car_pass_1.ogg", "car_pass_2.ogg", "car_pass_3.ogg"],
	"car_pass_wet": ["car_pass_wet_0.ogg"],
	"horn_far": ["horn_far_0.ogg", "horn_far_1.ogg", "horn_far_2.ogg", "horn_far_3.ogg", "horn_far_4.ogg"],
	"siren_far": ["siren_far_0.ogg", "siren_far_1.ogg"],
	"dog": ["dog_0.ogg", "dog_1.ogg", "dog_2.ogg", "dog_3.ogg"],
	"bus_hiss": ["bus_hiss_0.ogg", "bus_hiss_1.ogg", "bus_hiss_2.ogg"],
	"gull": ["gull_0.ogg", "gull_1.ogg", "gull_2.ogg", "gull_3.ogg", "gull_4.ogg"],
	"coyote": ["coyote_0.ogg", "coyote_1.ogg", "coyote_2.ogg"],
	"ship_horn": ["ship_horn_0.ogg", "ship_horn_1.ogg", "ship_horn_2.ogg"],
	"crane": ["crane_0.ogg", "crane_1.ogg", "crane_2.ogg", "crane_3.ogg"],
	# The city's spaces (Ambience): water trickling down the river's low-flow channel, a plaza
	# fountain, kids at a playground, and construction somewhere down the block (one-shots).
	"amb_river": ["amb_river_0.ogg"],
	"amb_fountain": ["amb_fountain_0.ogg"],
	"amb_playground": ["amb_playground_0.ogg"],
	"construction": ["construction_0.ogg", "construction_1.ogg", "construction_2.ogg"],
}

## Levels of the takes above, in the same order. One-shots use the SAMPLE_LOUDNESS_DB metric (the
## loudest 50 ms window). The beds are steady by construction and every one of them is cut to a
## long-term RMS of -22 dB, which is what is recorded for them: one laugh in the crowd walla sits
## 12 dB over its bed, and trimming the whole bed by that laugh would bury it.
const AMBIENCE_LOUDNESS_DB := {
	"amb_city": [-22.0], "amb_city_far": [-22.0], "amb_crowd": [-22.0], "amb_birds": [-22.0],
	"amb_crickets": [-22.0], "amb_gale": [-22.0], "amb_rain_heavy": [-22.0], "amb_rain_roof": [-22.0],
	"amb_rain_car": [-22.0], "amb_freeway": [-22.0], "amb_surf": [-22.0], "amb_airport": [-22.0],
	"amb_port": [-22.0], "car_roll": [-22.0],
	"car_pass": [-5.41, -12.15, -8.77, -12.83],
	"car_pass_wet": [-11.31],
	"horn_far": [-10.57, -9.55, -6.67, -7.34, -9.53],
	"siren_far": [-8.65, -10.72],
	"dog": [-6.75, -7.10, -7.46, -10.99],
	"bus_hiss": [-13.77, -11.75, -12.24],
	"gull": [-9.86, -9.25, -10.56, -10.07, -11.66],
	"coyote": [-6.57, -10.93, -9.84],
	"ship_horn": [-8.19, -12.66, -7.08],
	"crane": [-10.25, -11.37, -10.90, -4.51],
	"amb_river": [-22.0], "amb_fountain": [-22.0], "amb_playground": [-22.0],
	"construction": [-12.00, -11.42, -7.82],
}

## Ambience names that loop (set in code, like LOOPING).
const AMBIENCE_LOOPING := ["amb_city", "amb_city_far", "amb_crowd", "amb_birds", "amb_crickets",
	"amb_gale", "amb_rain_heavy", "amb_rain_roof", "amb_rain_car", "amb_freeway", "amb_surf",
	"amb_airport", "amb_port", "car_roll", "amb_river", "amb_fountain", "amb_playground"]

## Bus names (built by _install_buses). Everything a thing in the world makes goes to World;
## the weather and the city's ambience go to Ambience; Game holds both.
const BUS_GAME := &"Game"
const BUS_WORLD := &"World"
const BUS_AMBIENCE := &"Ambience"
## Gunfire and blasts coming back off the city (echo()): delayed copies of the shot, low-passed
## and smeared by a reverb of their own. Sends to Game, so the wheel's muffle takes it too.
const BUS_ECHO := &"Echo"
## Effect slots on the Echo bus.
const ECHO_FILTER := 0
const ECHO_VERB := 1
## Names that echo, and how loud their echo is relative to the shot's own level (dB).
const ECHO_NAMES := {"shot": 0.0, "shotgun": 1.0, "explosion": 3.0, "rocket": -4.0}
## Shots further than this from the listener do not echo for him (m); and the echo of one this far
## off is this many dB down on one at the listener's side (falls 3 dB per doubling, a reverberant
## field's rate, from `ECHO_NEAR`).
const ECHO_REACH := 450.0
const ECHO_NEAR := 15.0
const ECHO_VOICES := 8
## Older Sfx names that are ambience rather than events in the world.
const AMBIENT_NAMES := ["rain", "wind", "ambience_city", "thunder"]

var _streams: Dictionary = {}
var _gains: Dictionary = {} # name -> per-take trim in dB, parallel to _streams
var _last_take: Dictionary = {} # name -> index played last, so a take never repeats back to back
var _pool: Array[AudioStreamPlayer3D] = []
var _next: int = 0
var _rng := RandomNumberGenerator.new()
## What the space round the listener throws back (set by Ambience from its probe, see echo_for()):
## {"taps": [[delay s, dB, direction (Vector3, world)], ...], "cutoff": Hz, "room": 0..1}. Empty =
## no echo (the test room, a car's cabin).
var echo_profile: Dictionary = {}
## Echoes waiting for their moment: [due msec, stream, dB, pitch, direction].
var _echo_queue: Array = []
var _echo_pool: Array[AudioStreamPlayer3D] = []
var _echo_next: int = 0
## Echoes played since load (the smoke test and the HUD).
var echoes_played: int = 0


func _ready() -> void:
	LoadClock.start("sfx")
	_rng.seed = 1
	_install_limiter()
	_install_buses()
	_build_synth()
	if use_samples:
		_load_samples()
	_build_ambience_synth()
	for i in maxi(pool_size, 1):
		var p := AudioStreamPlayer3D.new()
		p.max_distance = max_distance
		p.unit_size = unit_size
		p.bus = BUS_WORLD
		add_child(p)
		_pool.append(p)
	LoadClock.stop("sfx")


## A hard limiter across the whole master bus.
##
## Everything is normalised to `reference_loudness_db` by its loudest 50 ms *window*, which is the
## right thing to level a mix by - but a window is not a peak. The sharpest recording in the set
## (break_0) carries 18.6 dB between its window level and its single loudest sample, so at
## point-blank range that one transient lands a few dB over full scale and the output device
## clamps it into a square edge. That is the one flaw left in the loudness pass, and backing the
## master off far enough to bury it would cost about 5 dB across the entire game for the sake of a
## handful of sub-millisecond spikes.
##
## A limiter is the answer the flaw actually asks for: it does nothing at all until a peak reaches
## the ceiling and then rounds that peak off instead of clipping it, so the level stays where it
## was tuned and a crate breaking in your face stops crunching. This is also what keeps the game
## safe when the chaos stacks up - eight explosions, a dozen cars and the rain sum well past unity
## no matter how carefully each one is levelled.
##
## Built in code rather than in a bus layout resource, because a .tres bus layout has to be made
## in the editor and the owner cannot open it.
func _install_limiter() -> void:
	for i in AudioServer.get_bus_effect_count(0):
		if AudioServer.get_bus_effect(0, i) is AudioEffectHardLimiter:
			return
	var lim := AudioEffectHardLimiter.new()
	# Just under full scale, so the converter never sees a sample at the rail.
	lim.ceiling_db = -0.5
	# Only the peaks: nothing below this is touched at all.
	lim.pre_gain_db = 0.0
	AudioServer.add_bus_effect(0, lim)


## Effect slots on the buses below, for set_filter() / set_reverb() and the smoke test.
const GAME_MUFFLE := 0 # Game: low-pass while time is slowed, and after a blast close by
const WORLD_REVERB := 0 # World: street-canyon reverb
const AMBIENCE_ENCLOSE := 0 # Ambience: low-pass when shut in (a car, a covered street)
const AMBIENCE_DUCK := 1 # Ambience: compressor keyed on World, so gunfire pushes the city down

## The bus layout, in code for the same reason as the limiter (a .tres layout needs the editor):
##   Master (limiter) <- Game (muffle) <- World (reverb)
##                                     <- Ambience (enclosure low-pass, ducking compressor)
## The Ambience node moves the filters and the reverb; nothing else needs to know the buses exist.
## On the web build (sample playback) bus effects are skipped by the engine and the plain mix
## plays, which is the right way for this to degrade.
func _install_buses() -> void:
	var game := _ensure_bus(BUS_GAME, &"Master")
	var world := _ensure_bus(BUS_WORLD, BUS_GAME)
	var amb := _ensure_bus(BUS_AMBIENCE, BUS_GAME)
	if AudioServer.get_bus_effect_count(game) == 0:
		var muffle := AudioEffectLowPassFilter.new()
		muffle.cutoff_hz = 20000.0
		AudioServer.add_bus_effect(game, muffle)
		AudioServer.set_bus_effect_enabled(game, GAME_MUFFLE, false)
	if AudioServer.get_bus_effect_count(world) == 0:
		var verb := AudioEffectReverb.new()
		verb.room_size = 0.4
		verb.damping = 0.55
		verb.spread = 0.9
		verb.hipass = 0.25 # no bass smear: a street echoes the crack, not the thump
		verb.dry = 1.0
		verb.wet = 0.04
		verb.predelay_msec = 30.0
		verb.predelay_feedback = 0.3
		AudioServer.add_bus_effect(world, verb)
	var echo := _ensure_bus(BUS_ECHO, BUS_GAME)
	if AudioServer.get_bus_effect_count(echo) == 0:
		var dull := AudioEffectLowPassFilter.new()
		dull.cutoff_hz = 4000.0
		AudioServer.add_bus_effect(echo, dull)
		var tail := AudioEffectReverb.new()
		tail.room_size = 0.6
		tail.damping = 0.6
		tail.spread = 1.0
		tail.hipass = 0.15
		tail.dry = 0.55
		tail.wet = 0.45
		tail.predelay_msec = 20.0
		AudioServer.add_bus_effect(echo, tail)
	if AudioServer.get_bus_effect_count(amb) == 0:
		var enclose := AudioEffectLowPassFilter.new()
		enclose.cutoff_hz = 20000.0
		AudioServer.add_bus_effect(amb, enclose)
		AudioServer.set_bus_effect_enabled(amb, AMBIENCE_ENCLOSE, false)
		var duck := AudioEffectCompressor.new()
		duck.threshold = -26.0
		duck.ratio = 4.0
		duck.attack_us = 2000.0
		duck.release_ms = 900.0
		duck.gain = 0.0
		duck.sidechain = BUS_WORLD
		AudioServer.add_bus_effect(amb, duck)


func _ensure_bus(bus_name: StringName, send: StringName) -> int:
	var idx := AudioServer.get_bus_index(bus_name)
	if idx < 0:
		AudioServer.add_bus()
		idx = AudioServer.bus_count - 1
		AudioServer.set_bus_name(idx, bus_name)
	AudioServer.set_bus_send(idx, send)
	return idx


## Sets a bus's low-pass (the Game muffle or the Ambience enclosure). 20 kHz or more switches it
## off rather than running a filter that does nothing.
func set_filter(bus_name: StringName, cutoff_hz: float) -> void:
	var idx := AudioServer.get_bus_index(bus_name)
	if idx < 0 or AudioServer.get_bus_effect_count(idx) == 0:
		return
	var fx := AudioServer.get_bus_effect(idx, 0) as AudioEffectLowPassFilter
	if fx == null:
		return
	var on := cutoff_hz < 19000.0
	fx.cutoff_hz = clampf(cutoff_hz, 20.0, 20000.0)
	if AudioServer.is_bus_effect_enabled(idx, 0) != on:
		AudioServer.set_bus_effect_enabled(idx, 0, on)


## The World bus reverb: wet level, room size (0..1) and pre-delay (ms); damping (0..1) and the
## reverb's own high-pass (0..1) when given (negative leaves them).
func set_reverb(wet: float, room: float, predelay_msec: float, damping: float = -1.0, hipass: float = -1.0) -> void:
	var idx := AudioServer.get_bus_index(BUS_WORLD)
	if idx < 0 or AudioServer.get_bus_effect_count(idx) <= WORLD_REVERB:
		return
	var verb := AudioServer.get_bus_effect(idx, WORLD_REVERB) as AudioEffectReverb
	if verb == null:
		return
	verb.wet = clampf(wet, 0.0, 1.0)
	verb.room_size = clampf(room, 0.0, 1.0)
	verb.predelay_msec = clampf(predelay_msec, 20.0, 500.0)
	if damping >= 0.0:
		verb.damping = clampf(damping, 0.0, 1.0)
	if hipass >= 0.0:
		verb.hipass = clampf(hipass, 0.0, 1.0)


## What the space throws back: the echo taps (see echo_profile) and the Echo bus's filter and tail.
func set_echo(profile: Dictionary) -> void:
	echo_profile = profile
	var idx := AudioServer.get_bus_index(BUS_ECHO)
	if idx < 0 or AudioServer.get_bus_effect_count(idx) <= ECHO_VERB:
		return
	var dull := AudioServer.get_bus_effect(idx, ECHO_FILTER) as AudioEffectLowPassFilter
	if dull:
		dull.cutoff_hz = clampf(float(profile.get("cutoff", 4000.0)), 200.0, 20000.0)
	var tail := AudioServer.get_bus_effect(idx, ECHO_VERB) as AudioEffectReverb
	if tail:
		tail.room_size = clampf(float(profile.get("room", 0.6)), 0.0, 1.0)


## Queues the echoes of a shot of `name` heard `distance` metres off (its take, level and pitch),
## by the current echo_profile. play() calls it for every name in ECHO_NAMES.
func echo(name: String, stream: AudioStream, volume_db: float, pitch: float, distance: float) -> int:
	var taps: Array = echo_profile.get("taps", [])
	if taps.is_empty() or stream == null or distance > ECHO_REACH:
		return 0
	var far_db := -10.0 * log(maxf(distance, ECHO_NEAR) / ECHO_NEAR) / log(10.0)
	var now := Time.get_ticks_msec()
	var n := 0
	for tap: Array in taps:
		# The echo leaves from the shot, so a far shot's echo comes that much later too.
		var due := now + int((float(tap[0]) + distance * 0.25 / 343.0) * 1000.0)
		_echo_queue.append([due, stream, volume_db + float(ECHO_NAMES.get(name, 0.0)) + float(tap[1]) + far_db, pitch, tap[2]])
		n += 1
	return n


func _process(_delta: float) -> void:
	if _echo_queue.is_empty():
		return
	var now := Time.get_ticks_msec()
	var i := 0
	while i < _echo_queue.size():
		var e: Array = _echo_queue[i]
		if int(e[0]) <= now:
			_play_echo(e)
			_echo_queue.remove_at(i)
		else:
			i += 1


func _play_echo(e: Array) -> void:
	if _echo_pool.is_empty():
		for k in ECHO_VOICES:
			var v := AudioStreamPlayer3D.new()
			v.name = "Echo_%d" % k
			v.attenuation_model = AudioStreamPlayer3D.ATTENUATION_DISABLED
			v.attenuation_filter_cutoff_hz = 20500.0
			v.panning_strength = 0.6
			v.bus = BUS_ECHO
			add_child(v)
			_echo_pool.append(v)
	var cam := get_viewport().get_camera_3d() if get_viewport() else null
	var eye := cam.global_position if cam else Vector3.ZERO
	var dir: Vector3 = e[4] if e[4] is Vector3 else Vector3.FORWARD
	var v := _echo_pool[_echo_next]
	_echo_next = (_echo_next + 1) % _echo_pool.size()
	v.stop()
	v.stream = e[1]
	v.global_position = eye + dir.normalized() * 10.0
	# The web plays the plain mix (no bus filter), so its echoes are brighter: keep them lower.
	v.volume_db = float(e[2]) - (4.0 if OS.has_feature("web") else 0.0)
	v.pitch_scale = float(e[3])
	v.play()
	echoes_played += 1


## Which bus a name plays on: the weather and the ambience on Ambience, everything else on World.
func bus_for(name: String) -> StringName:
	if AMBIENCE_SAMPLES.has(name) or name in AMBIENT_NAMES:
		return BUS_AMBIENCE
	return BUS_WORLD


## One take of `name` for a caller that owns its own player (the Ambience node): [stream, trim in
## dB, master_volume_db included], never the take this name played last. Empty if there is none.
func take(name: String) -> Array:
	var takes: Array = _streams.get(name, [])
	if takes.is_empty():
		return []
	var idx := _pick(name, takes.size())
	return [takes[idx], master_volume_db + _trim_db(name, idx)]


## Take `idx` of `name` (wrapped) for a caller that owns its player: [stream, trim in dB]. A car's
## horn is always the same take (EngineAudio.horn()). Empty if there is none.
func take_at(name: String, idx: int) -> Array:
	var takes: Array = _streams.get(name, [])
	if takes.is_empty():
		return []
	var i := posmod(idx, takes.size())
	return [takes[i], master_volume_db + _trim_db(name, i)]


func has(name: String) -> bool:
	var takes: Array = _streams.get(name, [])
	return not takes.is_empty()


func play(name: String, at: Vector3, volume_db: float = 0.0, pitch: float = 1.0) -> void:
	var takes: Array = _streams.get(name, [])
	if takes.is_empty() or _pool.is_empty():
		return
	var idx := _pick(name, takes.size())
	var p := _pool[_next]
	_next = (_next + 1) % _pool.size()
	p.stop()
	p.stream = takes[idx]
	p.global_position = at
	p.volume_db = volume_db + master_volume_db + _trim_db(name, idx)
	p.pitch_scale = pitch * _rng.randf_range(1.0 - pitch_variation, 1.0 + pitch_variation)
	p.bus = bus_for(name)
	p.play()
	if ECHO_NAMES.has(name):
		var cam := get_viewport().get_camera_3d() if get_viewport() else null
		var d := at.distance_to(cam.global_position) if cam else 0.0
		echo(name, takes[idx], p.volume_db, p.pitch_scale, d)


## A looping player for the caller to parent and control.
func loop_player(name: String, volume_db: float = -6.0) -> AudioStreamPlayer3D:
	var p := AudioStreamPlayer3D.new()
	var takes: Array = _streams.get(name, [])
	var trim := 0.0
	if not takes.is_empty():
		p.stream = takes[0]
		trim = _trim_db(name, 0)
	p.volume_db = volume_db + master_volume_db + trim
	p.max_distance = loop_max_distance
	p.unit_size = loop_unit_size
	p.bus = bus_for(name)
	return p


## Index of a random take, uniform over every take but the one this name played last.
func _pick(key: String, count: int) -> int:
	if count <= 1:
		return 0
	var last: int = _last_take.get(key, -1)
	var idx := _rng.randi() % count
	if idx == last:
		idx = (last + 1 + _rng.randi() % (count - 1)) % count
	_last_take[key] = idx
	return idx


## The normalisation trim for one take, in dB. Zero for anything with no measurement behind it.
func _trim_db(key: String, idx: int) -> float:
	var gains: Array = _gains.get(key, [])
	if idx < 0 or idx >= gains.size():
		return 0.0
	return gains[idx]


# --- Samples -----------------------------------------------------------------------------

func _load_samples() -> void:
	_load_table(SAMPLES, SAMPLE_LOUDNESS_DB, LOOPING)
	_load_table(AMBIENCE_SAMPLES, AMBIENCE_LOUDNESS_DB, AMBIENCE_LOOPING)


func _load_table(table: Dictionary, levels: Dictionary, looping: Array) -> void:
	for key: String in table:
		var takes: Array[AudioStream] = []
		var gains: Array[float] = []
		var names: Array = table[key]
		var loudness: Array = levels.get(key, [])
		for i in names.size():
			var file_name: String = names[i]
			var path := AUDIO_DIR + file_name
			if not ResourceLoader.exists(path):
				continue
			var stream := ResourceLoader.load(path) as AudioStream
			if stream == null:
				continue
			if key in looping:
				_set_looping(stream)
			takes.append(stream)
			var measured: float = loudness[i] if i < loudness.size() else reference_loudness_db
			gains.append(reference_loudness_db - measured)
		if not takes.is_empty():
			_streams[key] = takes # real takes replace the synthesized fallback
			_gains[key] = gains


func _set_looping(stream: AudioStream) -> void:
	if stream is AudioStreamOggVorbis:
		var ogg := stream as AudioStreamOggVorbis
		ogg.loop = true
		ogg.loop_offset = 0.0


# --- Synthesis (fallback) ----------------------------------------------------------------

func _build_synth() -> void:
	_put("shot", _noise_burst(0.10, 40.0, 0.9, 0.35))
	_put("shotgun", _noise_burst(0.32, 13.0, 1.0, 0.12))
	_put("pump", _noise_burst(0.07, 60.0, 0.6, 0.7))
	_put("rocket", _noise_burst(0.35, 9.0, 0.7, 0.08))
	_put("explosion", _noise_burst(1.3, 3.5, 1.0, 0.03))
	_put("jump", _sweep(0.16, 320.0, 640.0, 0.45))
	_put("land", _thud(0.12, 90.0, 0.7))
	_put("thud", _thud(0.18, 70.0, 0.9))
	_put("footstep", _thud(0.07, 140.0, 0.4))
	_put("break", _noise_burst(0.28, 14.0, 0.8, 0.2))
	_put("glass", _noise_burst(0.34, 11.0, 0.7, 0.75))
	_put("crash", _noise_burst(0.45, 8.0, 1.0, 0.15))
	_put("horn", _horn(0.5))
	_put("car_horn", _horn(0.35))
	_put("car_horn_long", _horn(1.3))
	_put("yelp", _yelp(0.4))
	_put("scream", _yelp(1.1))
	_put("gore", _noise_burst(0.3, 16.0, 0.8, 0.05))
	_put("click", _sweep(0.05, 1200.0, 900.0, 0.4))
	_put("boost_loop", _boost_loop(0.6), true)
	_put("engine_loop", _engine_loop(0.4), true)
	_put("skid", _skid_loop(0.5), true)
	_put("rain", _rain_loop(1.5), true)
	_put("wind", _wind_loop(2.0), true)
	_put("ambience_city", _city_loop(2.0), true)
	_put("thunder", _thunder(3.2))
	_put("siren", _siren_wail(4.0), true)
	# The emergency services (Emergency): an ambulance's yelp and a fire engine's air horn.
	_put("siren_yelp", _siren_yelp(2.0), true)
	_put("fire_horn", _air_horn(1.4))
	_put("jet_loop", _jet_loop(1.6), true)
	_put("rotor_loop", _rotor_loop(1.2), true)
	_put("generator", _engine_loop(0.5), true)
	# The light rail (LightRailSystem, LightRailTrain): a crossing bell, the horn, the street gong,
	# the train rolling. Fallbacks for the CC0 takes in SAMPLES.
	_put("rail_bell", _bell_loop(1.0), true)
	_put("rail_horn", _horn(1.1))
	_put("rail_gong", _gong(1.2))
	_put("rail_roll", _rail_roll(1.6), true)
	# The freight line: fallbacks for its CC0 takes.
	_put("freight_horn", _horn(3.0))
	_put("freight_horn_blast", _horn(1.5))
	_put("freight_roll", _rail_roll(1.6), true)
	_put("freight_engine", _engine_loop(0.5), true)
	# Synthesised only (no CC0 take yet): a burning car (CarDamage).
	_put("fire_loop", _fire_loop(2.4), true)
	# A spent rifle case hitting the ground (BrassCasings) and bullet impacts by surface.
	_put("casing", _tink(0.22))
	_put("hit_concrete", _noise_burst(0.12, 45.0, 0.7, 0.5))
	_put("hit_metal", _tink(0.3))
	_put("hit_glass", _noise_burst(0.2, 18.0, 0.6, 0.85))
	_put("hit_wood", _thud(0.1, 220.0, 0.6))
	_put("hit_dirt", _noise_burst(0.1, 50.0, 0.6, 0.2))
	_put("hit_flesh", _thud(0.12, 110.0, 0.8))
	# Birds: a low warble for a coo, a burst of claps, harsh caws, chirps.
	_put("pigeon_coo", _sweep(0.6, 420.0, 330.0, 0.4))
	_put("wings", _noise_burst(0.8, 4.0, 0.5, 0.3))
	_put("crow", _sweep(0.35, 1300.0, 900.0, 0.5))
	_put("sparrow", _chirps(0.8, 4, 3000.0, 4500.0))
	_put("gull_close", _chirps(1.2, 3, 1400.0, 2200.0))
	# Footsteps by surface, the bus and the light rail car (fallbacks for the takes in SAMPLES).
	_put("footstep_concrete", _thud(0.07, 160.0, 0.4))
	_put("footstep_asphalt", _thud(0.08, 130.0, 0.4))
	_put("footstep_grass", _noise_burst(0.12, 30.0, 0.3, 0.35))
	_put("footstep_sand", _noise_burst(0.14, 22.0, 0.3, 0.25))
	_put("footstep_metal", _tink(0.25))
	_put("footstep_wood", _thud(0.12, 210.0, 0.5))
	_put("bus_door", _noise_burst(1.6, 2.2, 0.5, 0.75))
	_put("bus_chime", _chime(1.6, [880.0, 698.5]))
	_put("bus_kneel", _noise_burst(1.1, 2.5, 0.6, 0.8))
	_put("diesel_idle", _engine_loop(0.6), true)
	_put("rail_chime", _chime(1.2, [1046.5, 784.0, 1046.5]))
	_put("ball_dribble", _thud(0.18, 95.0, 0.9))
	# Synthesised only: the light rail car's traction motors (an inverter whine the train pitches
	# with its speed) and the hum and crackle off its pantograph and the overhead wire.
	_put("rail_motor", _motor_whine(2.0), true)
	_put("rail_hum", _wire_hum(2.0), true)
	# A parked car's alarm (CarAlarm): an electronic wail is what a real one is.
	_put("car_alarm", _siren_wail(2.0), true)
	_put("bark_big", _bark(0.6))
	_put("bark_small", _chirps(0.3, 2, 900.0, 1400.0))
	_put("dog_yelp", _yelp(0.45))
	# Driving (DrivingFX): a grinding scrape and a backfire's pop.
	_put("scrape", _skid_loop(0.7), true)
	_put("backfire", _noise_burst(0.22, 22.0, 1.0, 0.12))
	# Engines (EngineAudio): the old engine tone for every loop, a hiss for the turbo and the
	# blow-off, a beep for the reversing alarm. Fallbacks for tools/engine_audio.py's files.
	var eng_tone := _engine_loop(0.4)
	var eng_stream := _wav(eng_tone, true, _synth_gain(eng_tone))
	for eng: String in SAMPLES:
		if eng.begins_with("eng_") and eng in LOOPING:
			var takes: Array[AudioStream] = [eng_stream]
			_streams[eng] = takes
			_gains[eng] = [0.0]
	_put("eng_turbo", _motor_whine(1.0), true)
	_put("eng_blowoff", _noise_burst(0.4, 7.0, 0.6, 0.8))
	_put("eng_beeper", _chime(1.0, [1100.0]), true)


func _put(key: String, samples: PackedFloat32Array, looping: bool = false) -> void:
	var takes: Array[AudioStream] = [_wav(samples, looping, _synth_gain(samples))]
	_streams[key] = takes
	_gains[key] = [0.0] # baked into the buffer instead, so there is nothing left to trim


## Linear gain that lands a generated buffer on reference_loudness_db. Applied before the 16-bit
## clamp in _wav(), so the bursts that used to be written clipped flat come out intact.
func _synth_gain(samples: PackedFloat32Array) -> float:
	var loud := _loudness_db(samples)
	if loud <= -119.0:
		return 1.0
	return db_to_linear(clampf(reference_loudness_db - loud, -60.0, 24.0))


## Loudest 50 ms window of a buffer, in dB: the same metric SAMPLE_LOUDNESS_DB is measured with.
func _loudness_db(samples: PackedFloat32Array) -> float:
	var n := samples.size()
	if n == 0:
		return -120.0
	var w := mini(int(LOUDNESS_WINDOW * MIX_RATE), n)
	var sum := 0.0
	for i in w:
		sum += samples[i] * samples[i]
	var best := sum
	for i in range(w, n):
		sum += samples[i] * samples[i] - samples[i - w] * samples[i - w]
		best = maxf(best, sum)
	return 10.0 * log(maxf(best / float(w), 1e-12)) / log(10.0)


func _wav(samples: PackedFloat32Array, looping: bool = false, gain: float = 1.0) -> AudioStreamWAV:
	var wav := AudioStreamWAV.new()
	wav.format = AudioStreamWAV.FORMAT_16_BITS
	wav.mix_rate = MIX_RATE
	wav.stereo = false
	var bytes := PackedByteArray()
	bytes.resize(samples.size() * 2)
	for i in samples.size():
		var v := int(clampf(samples[i] * gain, -1.0, 1.0) * 32767.0)
		bytes.encode_s16(i * 2, v)
	wav.data = bytes
	if looping:
		wav.loop_mode = AudioStreamWAV.LOOP_FORWARD
		wav.loop_begin = 0
		wav.loop_end = samples.size()
	return wav


## A small brass case hitting pavement: a tick of noise and a few inharmonic partials ringing
## out fast, the highest dying first (a thin-walled tube's modes, roughly).
func _tink(seconds: float) -> PackedFloat32Array:
	var n := int(seconds * MIX_RATE)
	var out := PackedFloat32Array()
	out.resize(n)
	var partials := [[3150.0, 38.0, 0.55], [4880.0, 52.0, 0.4], [6710.0, 70.0, 0.3], [8420.0, 95.0, 0.18]]
	for i in n:
		var t := float(i) / MIX_RATE
		var v := 0.0
		for p: Array in partials:
			v += sin(TAU * float(p[0]) * t) * exp(-float(p[1]) * t) * float(p[2])
		v += _rng.randf_range(-1.0, 1.0) * exp(-900.0 * t) * 0.6
		out[i] = v * 0.8
	return out


func _noise_burst(seconds: float, decay: float, gain: float, smooth: float) -> PackedFloat32Array:
	var n := int(seconds * MIX_RATE)
	var out := PackedFloat32Array()
	out.resize(n)
	var last := 0.0
	for i in n:
		var t := float(i) / MIX_RATE
		var white := _rng.randf_range(-1.0, 1.0)
		last = lerpf(last, white, smooth) # low-pass: smaller smooth = deeper rumble
		out[i] = last * exp(-decay * t) * gain * 3.0
	return out


func _sweep(seconds: float, f0: float, f1: float, gain: float) -> PackedFloat32Array:
	var n := int(seconds * MIX_RATE)
	var out := PackedFloat32Array()
	out.resize(n)
	var phase := 0.0
	for i in n:
		var t := float(i) / n
		var f := lerpf(f0, f1, t)
		phase += TAU * f / MIX_RATE
		var env := sin(t * PI)
		out[i] = sin(phase) * env * gain
	return out


func _thud(seconds: float, f: float, gain: float) -> PackedFloat32Array:
	var n := int(seconds * MIX_RATE)
	var out := PackedFloat32Array()
	out.resize(n)
	for i in n:
		var t := float(i) / MIX_RATE
		out[i] = sin(TAU * f * t * (1.0 - t * 2.0)) * exp(-18.0 * t) * gain
	return out


func _yelp(seconds: float) -> PackedFloat32Array:
	var n := int(seconds * MIX_RATE)
	var out := PackedFloat32Array()
	out.resize(n)
	var phase := 0.0
	for i in n:
		var t := float(i) / n
		var f := lerpf(750.0, 280.0, t * t) * (1.0 + 0.06 * sin(t * 60.0))
		phase += TAU * f / MIX_RATE
		var env := minf(t * 12.0, 1.0) * (1.0 - t)
		out[i] = (sin(phase) * 0.7 + sin(phase * 2.0) * 0.3) * env * 0.6
	return out


## Two detuned tones a major third apart, which is roughly what a car horn is.
func _horn(seconds: float) -> PackedFloat32Array:
	var n := int(seconds * MIX_RATE)
	var out := PackedFloat32Array()
	out.resize(n)
	for i in n:
		var t := float(i) / MIX_RATE
		var env := minf(t * 60.0, 1.0) * minf((seconds - t) * 40.0, 1.0)
		var a := sin(TAU * 440.0 * t)
		var b := sin(TAU * 554.0 * t)
		var buzz := sin(TAU * 880.0 * t) * 0.2 + sin(TAU * 1108.0 * t) * 0.15
		out[i] = (a * 0.4 + b * 0.35 + buzz) * env * 0.6
	return out


## A level crossing bell: two strikes a second on a bright bell, as a loop.
func _bell_loop(seconds: float) -> PackedFloat32Array:
	var n := int(seconds * MIX_RATE)
	var out := PackedFloat32Array()
	out.resize(n)
	for i in n:
		var t := fmod(float(i) / MIX_RATE, 0.5)
		var v := sin(TAU * 1380.0 * t) * 0.6 + sin(TAU * 2760.0 * t) * 0.25 + sin(TAU * 3720.0 * t) * 0.12
		out[i] = v * exp(-7.0 * t) * 0.7
	return out


## The street gong of a light rail car: two strikes, low and ringing.
func _gong(seconds: float) -> PackedFloat32Array:
	var n := int(seconds * MIX_RATE)
	var out := PackedFloat32Array()
	out.resize(n)
	for i in n:
		var t := float(i) / MIX_RATE
		var v := 0.0
		for strike: float in [0.0, 0.42]:
			var u := t - strike
			if u >= 0.0:
				v += (sin(TAU * 620.0 * u) * 0.6 + sin(TAU * 1490.0 * u) * 0.25 + sin(TAU * 2260.0 * u) * 0.1) * exp(-5.5 * u)
		out[i] = v * 0.6
	return out


## A train rolling: wheel-on-rail noise with the traction motors' whine over it.
func _rail_roll(seconds: float) -> PackedFloat32Array:
	var n := int(seconds * MIX_RATE)
	var out := PackedFloat32Array()
	out.resize(n)
	var last := 0.0
	for i in n:
		var t := float(i) / MIX_RATE
		last = lerpf(last, _rng.randf_range(-1.0, 1.0), 0.05)
		out[i] = last * 0.7 + sin(TAU * 420.0 * t) * 0.05 + sin(TAU * 840.0 * t) * 0.025
	return out


func _boost_loop(seconds: float) -> PackedFloat32Array:
	var n := int(seconds * MIX_RATE)
	var out := PackedFloat32Array()
	out.resize(n)
	var last := 0.0
	for i in n:
		var t := float(i) / MIX_RATE
		last = lerpf(last, _rng.randf_range(-1.0, 1.0), 0.12)
		out[i] = last * 0.5 + sin(TAU * 110.0 * t) * 0.15 + sin(TAU * 220.0 * t) * 0.08
	return out


func _engine_loop(seconds: float) -> PackedFloat32Array:
	var n := int(seconds * MIX_RATE)
	var out := PackedFloat32Array()
	out.resize(n)
	for i in n:
		var t := float(i) / MIX_RATE
		var saw := fmod(t * 55.0, 1.0) * 2.0 - 1.0
		out[i] = saw * 0.25 + sin(TAU * 110.0 * t) * 0.2 + sin(TAU * 165.0 * t) * 0.08
	return out


## Tyre skid: band-limited noise with a resonant squeal riding on top. No CC0 recording of a
## skid was found, so this one has no sample behind it.
func _skid_loop(seconds: float) -> PackedFloat32Array:
	var n := int(seconds * MIX_RATE)
	var out := PackedFloat32Array()
	out.resize(n)
	var last := 0.0
	var band := 0.0
	for i in n:
		var t := float(i) / MIX_RATE
		last = lerpf(last, _rng.randf_range(-1.0, 1.0), 0.6)
		band = lerpf(band, last, 0.25) # a second pole: leaves a narrow noise band
		var squeal := sin(TAU * (1250.0 + 90.0 * sin(TAU * 7.0 * t)) * t)
		out[i] = (last - band) * 0.8 + squeal * 0.18
	return out


## A car on fire: a low roar that breathes, with crackles (short bright clicks) scattered through
## it. The end is cross-faded into the start so the loop has no seam.
func _fire_loop(seconds: float) -> PackedFloat32Array:
	var n := int(seconds * MIX_RATE)
	var out := PackedFloat32Array()
	out.resize(n)
	var low := 0.0
	var mid := 0.0
	for i in n:
		var t := float(i) / MIX_RATE
		var w := _rng.randf_range(-1.0, 1.0)
		low = lerpf(low, w, 0.025)
		mid = lerpf(mid, w, 0.25)
		var breath := 0.78 + 0.22 * sin(TAU * 3.0 * t / seconds) * sin(TAU * 2.0 * t / seconds + 0.7)
		out[i] = low * 2.6 * breath + (mid - low) * 0.1
	var pops := int(seconds * 28.0)
	for k in pops:
		var at := _rng.randi_range(0, n - 1)
		var amp := pow(_rng.randf(), 2.2) * 0.85
		var span := int(MIX_RATE * _rng.randf_range(0.002, 0.014))
		for j in span:
			if at + j < n:
				out[at + j] += amp * _rng.randf_range(-1.0, 1.0) * exp(-float(j) / maxf(float(span) * 0.3, 1.0))
	var fade := int(0.05 * MIX_RATE)
	for j in fade:
		var f := float(j) / float(fade)
		out[n - fade + j] = lerpf(out[n - fade + j], out[j], f)
	return out


## Steady hiss of rain: low-passed white noise with a slow flutter.
func _rain_loop(seconds: float) -> PackedFloat32Array:
	var n := int(seconds * MIX_RATE)
	var out := PackedFloat32Array()
	out.resize(n)
	var last := 0.0
	for i in n:
		var t := float(i) / MIX_RATE
		last = lerpf(last, _rng.randf_range(-1.0, 1.0), 0.45)
		out[i] = last * 0.35 * (0.85 + 0.15 * sin(TAU * 0.7 * t))
	return out


## Wind: deeper than rain and gustier, so the level breathes over a few seconds.
func _wind_loop(seconds: float) -> PackedFloat32Array:
	var n := int(seconds * MIX_RATE)
	var out := PackedFloat32Array()
	out.resize(n)
	var last := 0.0
	for i in n:
		var t := float(i) / MIX_RATE
		last = lerpf(last, _rng.randf_range(-1.0, 1.0), 0.06)
		var gust := 0.7 + 0.3 * sin(TAU * t / seconds) # one whole gust per loop, so it seams
		out[i] = last * 2.2 * gust
	return out


## Distant traffic: a low rumble with a slow swell, enough to keep a street from sounding dead.
func _city_loop(seconds: float) -> PackedFloat32Array:
	var n := int(seconds * MIX_RATE)
	var out := PackedFloat32Array()
	out.resize(n)
	var last := 0.0
	for i in n:
		var t := float(i) / MIX_RATE
		last = lerpf(last, _rng.randf_range(-1.0, 1.0), 0.03)
		var swell := 0.75 + 0.25 * sin(TAU * t / seconds)
		out[i] = last * 3.0 * swell + sin(TAU * 62.0 * t) * 0.03
	return out


## A police wail: one slow sweep up and back down, exactly one loop long. Electronic sirens
## drive a horn with something close to a square wave, so it is the odd harmonics with a
## little soft clipping, and the whole sweep is scaled so the waveform's phase closes on itself
## at the loop point (no click where it wraps).
func _siren_wail(seconds: float) -> PackedFloat32Array:
	var n := int(seconds * MIX_RATE)
	var out := PackedFloat32Array()
	out.resize(n)
	var lo := 680.0
	var hi := 1480.0
	var total := 0.0
	for i in n:
		var t := float(i) / float(n)
		total += TAU * (lo + (hi - lo) * (0.5 - 0.5 * cos(TAU * t))) / MIX_RATE
	var fix := (roundf(total / TAU) * TAU) / total
	var phase := 0.0
	for i in n:
		var t := float(i) / float(n)
		phase += TAU * (lo + (hi - lo) * (0.5 - 0.5 * cos(TAU * t))) * fix / MIX_RATE
		var s := sin(phase) + 0.30 * sin(3.0 * phase) + 0.15 * sin(5.0 * phase) + 0.06 * sin(2.0 * phase)
		out[i] = tanh(s * 1.4) * 0.5
	return out


## A yelp: the wail's sweep run fast (about four a second), a whole number of sweeps a loop.
func _siren_yelp(seconds: float) -> PackedFloat32Array:
	var n := int(seconds * MIX_RATE)
	var out := PackedFloat32Array()
	out.resize(n)
	var lo := 720.0
	var hi := 1550.0
	var sweeps := roundf(seconds * 3.8)
	var total := 0.0
	for i in n:
		var t := float(i) / float(n)
		total += TAU * (lo + (hi - lo) * (0.5 - 0.5 * cos(TAU * sweeps * t))) / MIX_RATE
	var fix := (roundf(total / TAU) * TAU) / total
	var phase := 0.0
	for i in n:
		var t := float(i) / float(n)
		phase += TAU * (lo + (hi - lo) * (0.5 - 0.5 * cos(TAU * sweeps * t))) * fix / MIX_RATE
		var s := sin(phase) + 0.30 * sin(3.0 * phase) + 0.15 * sin(5.0 * phase)
		out[i] = tanh(s * 1.5) * 0.5
	return out


## A fire engine's air horn: two blaring reed tones a minor third apart, a hard attack, a held
## blast and a short tail.
func _air_horn(seconds: float) -> PackedFloat32Array:
	var n := int(seconds * MIX_RATE)
	var out := PackedFloat32Array()
	out.resize(n)
	var pa := 0.0
	var pb := 0.0
	for i in n:
		var t := float(i) / MIX_RATE
		var env := minf(t / 0.04, 1.0) * clampf((seconds - t) / 0.25, 0.0, 1.0)
		var bend := 1.0 - 0.06 * exp(-t * 18.0)
		pa += TAU * 196.0 * bend / MIX_RATE
		pb += TAU * 233.0 * bend / MIX_RATE
		# Reeds: a buzzy, odd-heavy wave each.
		var a := fposmod(pa / TAU, 1.0) * 2.0 - 1.0
		var b := fposmod(pb / TAU, 1.0) * 2.0 - 1.0
		out[i] = tanh((a + b) * 1.6) * 0.45 * env
	return out


## Thunder: a deep rumble that cracks first, then rolls off.
func _thunder(seconds: float) -> PackedFloat32Array:
	var n := int(seconds * MIX_RATE)
	var out := PackedFloat32Array()
	out.resize(n)
	var last := 0.0
	for i in n:
		var t := float(i) / MIX_RATE
		last = lerpf(last, _rng.randf_range(-1.0, 1.0), 0.02 + 0.2 * exp(-8.0 * t))
		var env := exp(-1.4 * t) * (1.0 + 0.5 * sin(TAU * 2.3 * t) * exp(-t))
		out[i] = clampf(last * 6.0 * env, -1.0, 1.0)
	return out


## Jet roar fallback: deep broadband noise with a turbine whine on top. Loops seamlessly because
## the whine's frequency is a whole number of cycles over the buffer.
func _jet_loop(seconds: float) -> PackedFloat32Array:
	var n := int(seconds * MIX_RATE)
	var out := PackedFloat32Array()
	out.resize(n)
	var low := 0.0
	var mid := 0.0
	var whine_hz := roundf(1850.0 * seconds) / seconds
	for i in n:
		var t := float(i) / MIX_RATE
		var white := _rng.randf_range(-1.0, 1.0)
		low = lerpf(low, white, 0.03)
		mid = lerpf(mid, white, 0.25)
		out[i] = low * 2.4 + (mid - low) * 0.5 + sin(TAU * whine_hz * t) * 0.035
	return out


## Rotor chop fallback: a low thump per blade pass over a turbine hiss. The blade rate is a whole
## number of passes per buffer so the loop has no seam.
func _rotor_loop(seconds: float) -> PackedFloat32Array:
	var n := int(seconds * MIX_RATE)
	var out := PackedFloat32Array()
	out.resize(n)
	var hiss := 0.0
	var pass_hz := roundf(19.5 * seconds) / seconds
	for i in n:
		var t := float(i) / MIX_RATE
		var ph := fmod(t * pass_hz, 1.0)
		var thump := exp(-ph * 9.0) * sin(TAU * 70.0 * ph / pass_hz)
		hiss = lerpf(hiss, _rng.randf_range(-1.0, 1.0), 0.35)
		out[i] = thump * 0.8 + hiss * 0.12 * (0.7 + 0.3 * exp(-ph * 5.0))
	return out


# --- Ambience fallbacks ------------------------------------------------------------------

## Synthesized stand-ins for the ambience, built only for the names whose recordings did not load
## (all of them with use_samples off). Short loops of shaped noise and tones: enough that a missing
## file is heard as roughly the right thing - a roar, a wash of surf, a chirp - not as silence.
func _build_ambience_synth() -> void:
	for key: String in AMBIENCE_SAMPLES:
		if not _streams.has(key):
			_put(key, ambience_synth(key), key in AMBIENCE_LOOPING)


## The synthesized fallback for one ambience name (public so the smoke test can check each one).
func ambience_synth(key: String) -> PackedFloat32Array:
	match key:
		"amb_city": return _bed(3.0, 0.05, 2.2, 0.0, 0.0)
		"amb_city_far": return _bed(3.0, 0.02, 3.0, 0.0, 0.0)
		"amb_freeway": return _bed(2.0, 0.14, 1.4, 0.0, 0.0)
		"amb_airport": return _bed(3.0, 0.03, 2.6, 1650.0, 0.03)
		"amb_port": return _bed(3.0, 0.02, 2.8, 100.0, 0.08)
		"amb_crowd": return _babble(3.0)
		"amb_birds": return _chirps(4.0, 9, 2600.0, 4800.0)
		"amb_crickets": return _crickets(2.0)
		"amb_gale": return _wind_loop(3.0)
		"amb_rain_heavy": return _bed(2.0, 0.7, 0.45, 0.0, 0.0)
		"amb_rain_roof": return _drips(2.0, 60)
		"amb_rain_car": return _drips(2.0, 90)
		"amb_surf": return _surf(7.0)
		"car_roll": return _bed(1.0, 0.08, 1.6, 55.0, 0.12)
		"car_pass", "car_pass_wet": return _pass_by(2.8)
		"horn_far": return _horn(0.45)
		"siren_far": return _siren_wail(4.0)
		"dog": return _bark(0.9)
		"bus_hiss": return _noise_burst(1.1, 2.5, 0.6, 0.8)
		"gull": return _chirps(1.2, 3, 1400.0, 2200.0)
		"coyote": return _howl(2.2)
		"ship_horn": return _ship_horn(3.5)
		"crane": return _clank(1.2)
		"amb_river": return _bed(2.0, 0.55, 0.35, 0.0, 0.0)
		"amb_fountain": return _drips(2.0, 140)
		"amb_playground": return _babble(3.0)
		"construction": return _clank(1.0)
	return _bed(1.0, 0.05, 1.0, 0.0, 0.0)


## A bed of low-passed noise with an optional steady tone (a turbine whine, a quay's hum). The
## tone's frequency is rounded to whole cycles over the buffer, so the loop has no seam.
func _bed(seconds: float, smooth: float, gain: float, tone_hz: float, tone: float) -> PackedFloat32Array:
	var n := int(seconds * MIX_RATE)
	var out := PackedFloat32Array()
	out.resize(n)
	var hz := roundf(tone_hz * seconds) / seconds
	var last := 0.0
	for i in n:
		var t := float(i) / MIX_RATE
		last = lerpf(last, _rng.randf_range(-1.0, 1.0), smooth)
		out[i] = last * gain * (0.85 + 0.15 * sin(TAU * t / seconds)) + sin(TAU * hz * t) * tone
	return out


## Crowd walla: a few "voices", each a band of noise opened and closed at a syllable rate.
func _babble(seconds: float) -> PackedFloat32Array:
	var n := int(seconds * MIX_RATE)
	var out := PackedFloat32Array()
	out.resize(n)
	for v in 4:
		var rate := _rng.randf_range(3.0, 6.0)
		var phase := _rng.randf() * TAU
		var smooth := _rng.randf_range(0.12, 0.3)
		var low := 0.0
		var band := 0.0
		for i in n:
			var t := float(i) / MIX_RATE
			low = lerpf(low, _rng.randf_range(-1.0, 1.0), smooth)
			band = lerpf(band, low, 0.08)
			var syllable := maxf(0.0, sin(TAU * rate * t + phase + 1.3 * sin(TAU * 0.7 * t)))
			out[i] += (low - band) * syllable * 0.5
	return out


## Short tonal sweeps scattered through the buffer: birdsong, or a gull's cry when lower.
func _chirps(seconds: float, count: int, f_lo: float, f_hi: float) -> PackedFloat32Array:
	var n := int(seconds * MIX_RATE)
	var out := PackedFloat32Array()
	out.resize(n)
	for c in count:
		var start := int(_rng.randf_range(0.0, maxf(seconds - 0.35, 0.01)) * MIX_RATE)
		var length := int(_rng.randf_range(0.06, 0.3) * MIX_RATE)
		var f0 := _rng.randf_range(f_lo, f_hi)
		var f1 := f0 * _rng.randf_range(0.6, 1.5)
		var phase := 0.0
		for k in length:
			var u := float(k) / float(length)
			phase += TAU * lerpf(f0, f1, u) * (1.0 + 0.04 * sin(u * 60.0)) / MIX_RATE
			if start + k < n:
				out[start + k] += sin(phase) * sin(u * PI) * 0.5
	return out


## Field crickets: a 4.4 kHz carrier gated into triple pulses, twice a second.
func _crickets(seconds: float) -> PackedFloat32Array:
	var n := int(seconds * MIX_RATE)
	var out := PackedFloat32Array()
	out.resize(n)
	for i in n:
		var t := float(i) / MIX_RATE
		var cycle := fmod(t, 0.5)
		var gate := 0.0
		for p in 3:
			var at := 0.05 + 0.045 * p
			if cycle > at and cycle < at + 0.025:
				gate = sin((cycle - at) / 0.025 * PI)
		out[i] = sin(TAU * 4400.0 * t) * gate * 0.4
	return out


## Surf: a wash of noise that swells and breaks once per buffer, brighter as it breaks.
func _surf(seconds: float) -> PackedFloat32Array:
	var n := int(seconds * MIX_RATE)
	var out := PackedFloat32Array()
	out.resize(n)
	var low := 0.0
	var high := 0.0
	for i in n:
		var u := float(i) / float(n)
		var swell := pow(0.5 - 0.5 * cos(TAU * u), 3.0)
		var white := _rng.randf_range(-1.0, 1.0)
		low = lerpf(low, white, 0.04)
		high = lerpf(high, white, 0.5)
		out[i] = low * (0.8 + 1.8 * swell) + high * 0.35 * swell
	return out


## Rain on something hard: a steady hiss with sharp drops scattered over it.
func _drips(seconds: float, per_second: int) -> PackedFloat32Array:
	var out := _rain_loop(seconds)
	var n := out.size()
	for d in int(seconds * per_second):
		var at := _rng.randi() % n
		var f := _rng.randf_range(1800.0, 4200.0)
		for k in 220:
			if at + k >= n:
				break
			out[at + k] += sin(TAU * f * float(k) / MIX_RATE) * exp(-float(k) / 40.0) * 0.5
	return out


## A car going by: noise that swells to a peak at 1.2 s and falls away duller, as the Doppler does.
func _pass_by(seconds: float) -> PackedFloat32Array:
	var n := int(seconds * MIX_RATE)
	var out := PackedFloat32Array()
	out.resize(n)
	var last := 0.0
	for i in n:
		var t := float(i) / MIX_RATE
		var env := exp(-pow((t - 1.2) / 0.45, 2.0))
		last = lerpf(last, _rng.randf_range(-1.0, 1.0), 0.35 if t < 1.2 else 0.12)
		out[i] = last * env * 1.5
	return out


## A dog: two short barks, a pitched growl under a burst of breath noise.
func _bark(seconds: float) -> PackedFloat32Array:
	var n := int(seconds * MIX_RATE)
	var out := PackedFloat32Array()
	out.resize(n)
	for b in 2:
		var start := int((0.05 + 0.4 * b) * MIX_RATE)
		var length := int(0.16 * MIX_RATE)
		var phase := 0.0
		for k in length:
			var u := float(k) / float(length)
			phase += TAU * lerpf(520.0, 330.0, u) / MIX_RATE
			var tone := sin(phase) + 0.5 * sin(phase * 2.0) + 0.3 * sin(phase * 3.0)
			if start + k < n:
				out[start + k] = (tone * 0.6 + _rng.randf_range(-0.4, 0.4)) * sin(u * PI) * 0.6
	return out


## A coyote: a yip rising into a long wavering howl.
func _howl(seconds: float) -> PackedFloat32Array:
	var n := int(seconds * MIX_RATE)
	var out := PackedFloat32Array()
	out.resize(n)
	var phase := 0.0
	for i in n:
		var t := float(i) / MIX_RATE
		var u := t / seconds
		var f := lerpf(700.0, 1250.0, smoothstep(0.0, 0.3, u)) * (1.0 + 0.03 * sin(TAU * 5.5 * t))
		phase += TAU * f / MIX_RATE
		var env := smoothstep(0.0, 0.15, u) * (1.0 - smoothstep(0.7, 1.0, u))
		out[i] = (sin(phase) + 0.25 * sin(phase * 2.0)) * env * 0.5
	return out


## A ship's horn: a low fundamental with strong harmonics, a slow attack and a long release.
func _ship_horn(seconds: float) -> PackedFloat32Array:
	var n := int(seconds * MIX_RATE)
	var out := PackedFloat32Array()
	out.resize(n)
	for i in n:
		var t := float(i) / MIX_RATE
		var env := minf(t / 0.25, 1.0) * minf((seconds - t) / 0.8, 1.0)
		var s := sin(TAU * 98.0 * t) + 0.7 * sin(TAU * 196.0 * t) + 0.45 * sin(TAU * 294.0 * t) + 0.2 * sin(TAU * 392.0 * t)
		out[i] = tanh(s * 0.8) * env * 0.6
	return out


## A steel clank: a few inharmonic partials struck at once and left to ring.
func _clank(seconds: float) -> PackedFloat32Array:
	var n := int(seconds * MIX_RATE)
	var out := PackedFloat32Array()
	out.resize(n)
	for i in n:
		var t := float(i) / MIX_RATE
		var s := sin(TAU * 310.0 * t) * exp(-4.0 * t) + 0.6 * sin(TAU * 827.0 * t) * exp(-6.0 * t)
		s += 0.4 * sin(TAU * 1523.0 * t) * exp(-9.0 * t) + 0.25 * sin(TAU * 2410.0 * t) * exp(-14.0 * t)
		out[i] = s * 0.4 + _rng.randf_range(-1.0, 1.0) * exp(-60.0 * t) * 0.5
	return out


## A transit chime: each tone a struck sine with a little second harmonic, ringing out.
func _chime(seconds: float, tones: Array) -> PackedFloat32Array:
	var n := int(seconds * MIX_RATE)
	var out := PackedFloat32Array()
	out.resize(n)
	var gap := seconds / float(tones.size() + 1)
	for i in n:
		var t := float(i) / MIX_RATE
		var v := 0.0
		for k in tones.size():
			var u := t - gap * float(k)
			if u >= 0.0:
				var f: float = tones[k]
				v += (sin(TAU * f * u) * 0.7 + sin(TAU * f * 2.0 * u) * 0.12) * exp(-3.2 * u) * minf(u * 400.0, 1.0)
		out[i] = v * 0.5
	return out


## A light rail car's traction inverters: a few tones a fifth and an octave apart over a breath of
## noise, every frequency whole cycles over the buffer so the loop has no seam. The train pitches
## it with its speed (VehicleAudio.TrainVoice), so the tones climb as it pulls away.
func _motor_whine(seconds: float) -> PackedFloat32Array:
	var n := int(seconds * MIX_RATE)
	var out := PackedFloat32Array()
	out.resize(n)
	var parts := [[420.0, 0.5], [630.0, 0.22], [840.0, 0.3], [1260.0, 0.12], [1680.0, 0.08]]
	var last := 0.0
	for i in n:
		var t := float(i) / MIX_RATE
		var v := 0.0
		for p: Array in parts:
			var hz := roundf(float(p[0]) * seconds) / seconds
			v += sin(TAU * hz * t) * float(p[1])
		last = lerpf(last, _rng.randf_range(-1.0, 1.0), 0.3)
		out[i] = v * 0.35 * (0.9 + 0.1 * sin(TAU * t * 3.0 / seconds)) + last * 0.06
	return out


## The overhead wire and the pantograph: a 60 Hz buzz rich in odd harmonics, with a crackle of
## sparks now and then where the pan slides along the contact wire.
func _wire_hum(seconds: float) -> PackedFloat32Array:
	var n := int(seconds * MIX_RATE)
	var out := PackedFloat32Array()
	out.resize(n)
	for i in n:
		var t := float(i) / MIX_RATE
		var v := 0.0
		for h: int in [1, 2, 3, 5, 7]:
			v += sin(TAU * 60.0 * float(h) * t) / float(h)
		out[i] = v * 0.3
	for c in int(seconds * 7.0):
		var at := _rng.randi() % n
		for k in 120:
			if at + k >= n:
				break
			out[at + k] += _rng.randf_range(-1.0, 1.0) * exp(-float(k) / 18.0) * 0.5
	return out
