# memory-audit stills

The memory audit cuts copies and leaks; nothing on screen may change. Each pair is the same
frame (DIFF=1 on tools/glshot/still_shot.gd: TIME, clock and signals held, moving things hidden),
before (fleet/base) and after (wt/memory-audit), opengl3 + Xvfb, 960x540.

- `01_before_downtown_noon_opengl3.jpg` - downtown_noon bookmark, before. Peak RSS of the run 4299 MB.
- `02_after_downtown_noon_opengl3.jpg` - the same frame after. Peak RSS 4100 MB. Same GEO
  (6.40 M triangles, 3,418 draws).
- `03_diff_heatmap_downtown_noon.jpg` - the difference: 68 pixels of 518,400 differ, by 1/255 at
  most (red); the rest is dimmed. The shadow twins drop unused vertices only.
