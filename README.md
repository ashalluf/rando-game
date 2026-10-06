# prop-destruction stills (wave 2)

Street props breaking by KIND (PropBreak). Props-alone stage (`tools/glshot/prop_break_shot.gd`,
opengl3 / Compatibility, a plain pavement and sky - not the city's lighting).

- 01_before_props_noon - hydrant, street lamp (StreetLamps cobra), bus shelter, mailbox, meter, news box
- 02_car_about_to_hit - a sedan at 14 m/s on the pavement
- 03_car_smash_hydrant_on_hood_lamp_falling - hydrant sheared and thrown onto the hood, the geyser starting, the lamp swinging over on its foot hinge
- 04_car_smash_after_lamp_down_geyser - lamp down across the pavement, the car dented, geyser running
- 05_hydrant_geyser_3s - the column (13 m), crown spray and the falling rain
- 06_geyser_wet_pavement_14s - the wet patch spread round it, ringed by the falling drops
- 07_shelter_glass_bursting - the shelter's glass as tempered cubes 0.12 s after the hit
- 08_lamp_bent_by_hit_glass_popped - a 45-damage hit bends the post at its foot; the lamp pops
- 09_mailbox_newsbox_burst_meter_snapped - letters and newspapers out, the meter snapped off its stub
- 10_letters_newspapers_falling_meter_flung - 0.9 s later
- 11_city_before_downtown_noon - downtown (Flower St), the real city, nothing broken (EYE 2353.75,1.95,909.89,145.05,-0.61)
- 12_city_after_1s_geyser_lamp_going_over - `PROPS=hydrant,lamp,mailbox,newsbox,meter,bus_stop` on still_shot.gd: the hydrant's geyser, the twin-globe lamp popped and starting to go over, a meter's stub in front
- 13_city_after_6s_geyser_wet_pavement - 6 s later from further back: the wet pavement round the column
- 14_geyser_night_props_stage - the geyser at night on the stage (no street lamps there; the spray dims with the night)
- 15_shelter_glass_on_pavement_3s - the shelter's glass lying as cubes, the frame standing

Frame cost at the 11/12 eye: 3.906 M tris / 1,624 draws unbroken, 3.936 M / 1,652 mid-break (+0.8 %, all of it transient). Nothing new is drawn until something breaks.
