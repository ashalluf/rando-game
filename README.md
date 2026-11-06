# shots/rc5-port-gate

Refcam `port_gate` (tools/refcams/cameras_w8.json): the container terminal's truck gate at 10:00
clear, eye level by the west booth island looking east along the booth row. opengl3 stills
(the Compatibility renderer), 1280 x 720, from `refcams.py run --only port_gate`.

- `01_before_port_gate.jpg` - main (RC5_PORT_GATE=0): grey booth boxes with black mirror glass,
  blank white detector blocks on the portal, a flat canopy slab on bare posts, the yard's cracked
  concrete, half the lanes empty.
- `02_after_port_gate.jpg` - RcPortGate: glazed booths with a lit cabin, roof cap and AC, driver
  pedestals, yellow island kerbs; red-and-white boom barriers; canopy steel (beams, purlins) on
  striped crash plinths; louvred detector housings on hazard bases; the gate paved in asphalt
  with arrows and nose hatching; a busier queue.
- `03_before_wide_from_the_north_west.jpg` / `04_after_wide_from_the_north_west.jpg` - the view
  from the gate's north-west corner (2775, 5938) where the quay cranes' tops show over the stacks:
  the queue of bobtails north of the portal, the asphalt (04 is a still_shot.gd scout before the
  soffit tint; the pair are not the same frame time).
- `05_ten_cameras_off_vs_on.jpg` - the ten original refcams, RC5_PORT_GATE=0 (top) against on
  (bottom): no camera sees the port; the three flags are live traffic in other places.

`02` is the final head (soffit retinted); its numbers: 1,993,887 triangles / 1,552 draws against
the before's 1,896,687 / 1,480.
