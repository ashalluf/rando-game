# boot-compile: stills and logs

- `01_after_boot_compiling_scripts_273_of_652.jpg` - the boot's picture presented from INSIDE the
  game's 485-script compile (opengl3, 1280x720, the 70th pulse): "273 / 652 scripts", the clock at
  0:10. On main this picture stood still for 15.7 s at this point.
- `02_before_compile_probe_main_dec7e128.txt` / `03_after_compile_probe.txt` -
  tools/boot_compile/compile_probe.tscn, headless, quiet 4-core box: the cycle's one load() and the
  longest stretches between frames (15,130 ms -> 1,093 ms).
- `04_before_launch_loading_lines.txt` / `05_after_launch_loading_lines.txt` -
  tools/load_time/load_time.sh (opengl3 under Xvfb): main's "LOADING frame gap: 15688 ms";
  after, the longest gap 1,082 ms.
