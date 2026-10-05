# gate-speed stills

No visual change: this branch makes the headless check (the fleet's gate) faster. The "stills" are charts of what was measured on the fleet box (4 cores, 15 GB).

- `01_gate_wall_time.jpg` - smoke test wall time: plain 808 s before and after; `SHARDS=2` 515 s, `SHARDS=3` 341-375 s, `SHARDS=4` 326 s. Same pass / fail list in every mode.
- `02_gate_peak_memory.jpg` - peak memory of all Godot processes together: 3.1 GB plain, 6.7 GB for three shards (2.3 GB each).
- `03_where_the_time_went.jpg` - the profile (`SMOKE_PROFILE=1`) of one plain run, by part and check file.
