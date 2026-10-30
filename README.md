# Aerial review (wave 3, `wt/aerial-review`)

opengl3 1280x720 (the Compatibility renderer, not the Mac's Forward+), clear weather. Before = origin/main
at the start of the session, after = the branch (AERIAL_REVIEW=0 is the A/B). Cameras (TRUE world x,y,z,yaw,pitch):
downtown 2050,300,750,-49,-24; midtown west -450,260,950,-40,-20; suburbs/coast -500,320,1700,0,-24;
beach town -1450,260,-150,-90,-22; port 2300,320,5300,-140,-24; hills 0,520,-500,0,-14; downtown 800 m
2300,800,1000,-25,-42; hours 12.5, 17.3, 21.5.

- 01/02 the sea seam: streamed ocean chunks (dark, emitted) against the horizon plane's lit sea, cut along the chunk grid. Gone.
- 03/04 the hill terrain's 13 m mottle tile as a checkerboard from 300 m. Gone.
- 05/06 night: the plane's renderer-lit band dimmed a second time, a dark ring round the streamed hill tiles. Gone.
- 07/08 far city tree crowns as pale olive confetti beside the real trees' dark green. Darkened.
- 09/10 RockFar's far tors as brown flecks over the ranges. Softer (spread -40 %), still faintly visible.
- 11/12 night hills: the plane and the tiles lit alike.
- 13-18 after: downtown noon / golden, hills and valley, beach town, downtown from 800 m, downtown at night.
