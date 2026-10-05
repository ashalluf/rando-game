# shots/ref-cameras

The ten reference cameras (tools/refcams on wt/ref-cameras), opengl3 + Xvfb (llvmpipe), 1280x720,
one city load. Base run on fleet/base (df0d0d1 = 92945c7 + the refcams commits; no game code changed).

- 01_refcams_sheet_base.jpg - the 2x5 contact sheet with each shot's luminance p5/p50/p95, saturation, CCT, triangles and draws
- 02..11_base_<name>.jpg - each camera full size: street noon, street night (21:30 rain), sunset (17:51), golden aerial (17:12), downtown aerial, beach, hills, freeway, MacArthur Park, pier at night
- base_report.txt - the numbers

Opengl3 is the Compatibility renderer, not the Mac's Forward+.
