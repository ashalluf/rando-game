# Texture budget stills (wt/texture-budget)

opengl3 (Compatibility) renders under Xvfb. "Before" is origin/fleet/base, "after" is wt/texture-budget.

- 01 crowd face at 1.1 m, left before / right after (body atlas 2048 -> 1024 only).
- 02, 03 three rigs (long hair, afro, braid) at 1.4 m, top before / bottom after (body 1024, hair and body normals 512).
- 04 / 05 crowd row at 4.5 m (gameplay distance).
- 06 / 07 pigeon at 1 m, 08 / 09 the bird lineup (bird atlases 1024 -> 512).
- 10 / 11 every knee-high plant at 1-3 m (atlases 1024 -> 512).



## Bookmarks (second batch)

Texture memory the renderer reports (RENDERING_INFO_TEXTURE_MEM_USED), before -> after, same frame (GEO equal):

| bookmark | before | after |
|---|---|---|
| 12 downtown noon | 397.4 MB | 294.4 MB |
| 13 freeway | 417.7 MB | 306.7 MB |
| 14 masjid | 410.3 MB | 305.3 MB |
| 15 esplanade sunset | 396.1 MB | 285.1 MB |
| 16 beach town | 403.6 MB | 296.6 MB |

12-16: top before, bottom after (only the clouds differ: they run on shader time).
17 / 18: downtown with DIFF=1 (time held, movers hidden): pixel-identical, max difference 0.
