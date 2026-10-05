# shader-warm stills

Frame-time charts from `tools/shader_warm/first_use_probe.tscn` (Forward+ on lavapipe, the test
room under the city's environment). There is nothing new to look at in the game itself: the work
is the absence of a hitch.

- `01_first_use_before_after_lite.jpg` - worst frame and summed time over 1.5x a normal frame for
  ten first-use events (first rifle burst, rocket, people, shotgun on a person, every car body,
  police, emergency, a burning car, nightfall, rain), cold vs with the loading screen's new
  rehearsal (`WarmRehearsal`). Lite environment (no SDFGI / volumetric fog / SSIL) so lavapipe
  fits in memory. Total over-base time 58.9 s -> 14.9 s.
