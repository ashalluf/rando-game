# shots/specular-aliasing

Shimmer and crawl in motion (wt/specular-aliasing). Flicker maps are the per-pixel second temporal
difference of a slow camera pan (x4), averaged over the strip (tools/specular_aliasing/strip.py);
bright = flickers. City strips are the jittered TAA-like proxy (`--ss 4`), opengl3.

- 01_before_street_noon.jpg / _flicker.jpg - street_noon camera, main, a frame and its flicker map
- 02_after_street_noon.jpg / _flicker.jpg - the same with the pass on
- 03_car_lacquer_before_after.jpg - a dark sedan 22 m off orbiting 0.06 deg a frame: the lacquer's
  sun sparkles along the shoulder line and roof edge (left) gone with geometric specular AA on the
  clear coat (right); the frame itself unchanged. Car-region flicker -40 %.
