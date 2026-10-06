# Coast highway under the bluffs (wt/coast-highway)

opengl3 (Compatibility) stills, 1280x720, seed 1337, hour 15 unless noted. "before" is the same
build with `COAST_HIGHWAY=0` (the old coast: floating scrub, holes in the hill chunks, a cliff
curtain over the sand). Views: `tools/glshot/still_shot.gd` EYEs
`-1180,45,-1060,-45,-16` (aerial from the sea), `-1028,6.2,-1100,0,-4` (road level, north),
`-1072,1.7,-1180,-22,3` (the beach under the houses), spawn `-1040,-1180,0,-6`.

- 01 / 02 before / after, aerial from the sea
- 03 / 04 before / after, road level looking north (before: inside the hill)
- 05 the beach houses on their pilings, decks and stairs over the sand
- 06 the road at 21:00
- 07 the spawn view: cars and surfers' vans along both shoulders, the seawall parapet

## Final set (same build as the branch head's code)

- 08 aerial from the sea (compare 01 / 02)
- 09 the houses' street faces from the road: garages, doors, wood bands, planters, bins, mailboxes
- 10 the beach under the houses: pilings, braces, decks with glass rails, stairs to the sand
- 11 the north end: k-rails, barricade, ROAD CLOSED and the slide's boulders
- 12 a lifeguard tower on the open beach, sunbathers, surfers past the break
- 13 golden hour (18:18) from the north-west, the pier and the city beyond
- 14 21:00: cobra lamps on the bluff side, traffic with its lights on
- 15 traffic both ways, looking south to the beach town and the pier
- 16 cars along the open beach's shoulder, the seawall parapet

Frame cost (still_shot.gd GEO, opengl3 1280x720, same view, COAST_HIGHWAY=0 / on): aerial
2.29 M / 405 draws -> 2.11 M / 728; road level 1.28 M / 387 -> 2.11 M / 768 (most of it the
parked cars; the before view stood inside the hill, with chunks missing their terrain).
