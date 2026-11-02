# facades-mid-3 stills (fleet wave 5)

Generated buildings at 30-150 m across downtown, midtown and the historic core. opengl3
(Compatibility) stills from one city load each, `still_shot.gd DIFF=1` (clock, TIME and traffic
held, people and cars hidden), same EYEs before (main `bb03d731`) and after (`wt/facades-mid-3`).

- 01/02 Spring St at 6th looking north, noon (EYE 3108,2,330,0,9, FOV 62)
- 03/04 the historic core from 28 m (3113,28,430,8,-5)
- 05/06 east of downtown from 45 m (3300,45,720,25,-10)
- 07/08 Wilshire in midtown at street level (1100,2,300,-92,7)
- 09/10 midtown from 70 m (1150,70,520,10,-16)
- 11/12 crop of 01/02: the brick block's piers and recessed window strips
- 13/14 crop of 05/06: the tan block's piers and its weathered gravel roof
- 15 a test building (building_shot.gd), left FACADES_MID3=0, right on: stepped parapets
- 16 a test building, left off, right on: piers (close crop)

What changed: piers standing proud of recessed window strips on punched / slot-window masonry,
stepped and raised parapets on half the masonry blocks (near and far), weathered gravel roofs.

Golden hour, 17:20 (same load per side, `--hour=17.3`; the after set was shot with the pier
shadow at 0.5, the branch's final value is 0.42 - a touch lighter in the strips):
- 17/18 the historic core from 28 m
- 19/20 east of downtown from 45 m (the tan block's piers in raking light; its gravel roof)
- 21/22 midtown from 70 m
- 23/24 the east side from 30 m (3400,30,350,-30,-4: ribbon and curtain walls, unchanged by design)

- 25 Forward+ (lavapipe, the Mac's renderer), a test building, left FACADES_MID3=0, right the
  final branch: piers and recessed strips, stepped parapets
