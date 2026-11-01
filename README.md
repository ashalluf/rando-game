# shots/load-time-3

An infra task (load time and first-use hitches), so the stills are the measurements:

- `01_first_use_hitches_wave4.jpg` - ms of hitch the first time each of wave 4's things appears after
  the loading screen (tools/shader_warm/first_use_probe.tscn EVENTS=wave4, opengl3, rehearsal on):
  main 4.1 s in all, this branch 0.
- `02_cold_launch_stages.jpg` - cold-cache launch stages (headless, LOAD_SCREEN_HEADLESS=1): the
  ground bake 25.1 -> 20.0 s (byte-identical images), the rehearsal now has its own LOADING line.
  The other stages are unchanged (run-to-run noise of a few seconds).
