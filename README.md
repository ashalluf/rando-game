# perf-audit-2 stills

Frame-cost A/B pairs for the second perf audit (docs/HANDOFF.md, "Perf audit 2"). opengl3 /
llvmpipe, 1280x720, `DIFF=1` on tools/glshot/still_shot.gd (cars, people, particles hidden, the
clock held), before = origin/main, after = wt/perf-audit-2. Heatmaps from tools/glshot/img_diff.py:
the frame dimmed, every pixel that differs red.

- 01_before_downtown_noon_diffframe.jpg - downtown, Flower at Olympic, noon: 6,684,567 tris / 3,204 draws
- 02_after_downtown_noon_diffframe.jpg - the same frame after: 6,458,887 tris / 3,198 draws (-3.4 %)
- 03_diff_heatmap_downtown_116px.jpg - 116 pixels moved (0.013 %): the parked scooters ~40 m off (their new LODs)
- 04_before_port_noon_diffframe.jpg - the port, noon (the refinery's far pieces on the right)
- 05_after_port_noon_diffframe.jpg - after: -654 tris, the far pieces 25.1 -> 14.2 MB
- 06_diff_heatmap_port_86px.jpg - 86 pixels moved (0.009 %)
