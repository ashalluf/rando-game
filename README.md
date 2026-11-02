# shots/rc4-port-night

Wave-7 refcam `port_night` (tools/refcams/cameras_w7.json): the container terminal at 22:00 clear,
from the quay's east end inside the crane gauge looking west - the moored ship and its deckhouse on
the left, the working cranes' portals overhead, a yard tractor under crane 58 with a box coming down
onto it (port clock held at 162 s), the floodlit stacks on the right. opengl3 stills, 1280x720.

- `01_before_port_night.jpg` - main (6ffcde38): a "floodlit" terminal lit by the moon alone; the
  lamps are flat beige squares; the deckhouse a grid of big half-lit squares; the hull a black wall.
- `02_after_port_night.jpg` - this branch: the masts' and cranes' floods light the stacks, the
  crane legs and the deckhouse (aimed down: the girders over the lamps stay dark); the apron is
  floodlit concrete (the yard's pools had been 3-5 m hot spots: the default MultiMesh custom);
  framed deckhouse windows, fewer lit, in a few tones; dark lamp housings.
- `90_rejected_floods_unaimed.jpg` - a first pass, rejected: floods lighting in every direction
  burned the crane tops white over an unlit ground.
- `03_kit_night_opengl3_top_forward_bottom.jpg` - the kit alone at night (tools/glshot/port_shot.gd
  NIGHT=1): top opengl3, bottom Forward+ under lavapipe; left PORT_NIGHT=0, right on. The floods
  read the same on both renderers.
