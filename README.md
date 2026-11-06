# shots/memory-audit-w8

DIFF=1 still pairs (opengl3, 1280x720, tools/glshot/still_shot.gd): the top half of each image is
main's behaviour (TELEPORT_FREE=0), the bottom half this branch. One load at Flower at Olympic, then
three SHOTS hops (each a teleport through update_streaming(true)).

- 01_street_noon_load_ab.jpg - the load itself: 0 pixels differ.
- 02_macarthur_after_hop_ab.jpg - after hop 1: 78 pixels differ (an A/A of the same side: 86).
- 03_freeway_after_hop_ab.jpg - after hop 2: 692 pixels (A/A: 1,235) - a far vehicle on the deck.
- 04_beach_after_hop_ab.jpg - after hop 3: 576 pixels (A/A: 641) - a swimmer / bird at sea.

Peak RSS of that run (warm shader caches): 7,727 MB off -> 7,288 MB on.

## Final variant (commit e0212c76: the old chunks emptied, nodes freed on their old timer)

Re-shot the same four views with the final code (v4) against main's (TELEPORT_FREE=0):
load 1 pixel (by 1/255), the hops 578 / 150 / 335 pixels (0.06 / 0.02 / 0.04 %) - a car on the
street under a palm by MacArthur Park, the far deck, the sea; live systems DIFF does not freeze.
Peak RSS of that run 7,452 MB (main's 7,727).
