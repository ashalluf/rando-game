# shots/dogs (branch wt/dogs)

opengl3 (Compatibility) renders under Xvfb + llvmpipe, not the Mac's Forward+.

- `breeds_three_quarter.jpg`, `breeds_side.jpg`, `breeds_front.jpg`: the six breeds one by one
  (labrador, German shepherd, husky / pit bull mix, terrier, chihuahua), standing, NEAR level with
  fur shells (`tools/glshot/dog_shot.gd BREEDS=<breed> VIEW=three|side|front FOV=36`).
- `lineup_all_three_quarter.jpg`: all six at real relative size.
- `fur_closeup_husky_shepherd.jpg`: the shells' strands up close.
- `sit_lineup.jpg`: the sit, each dog looking up at the camera (`POSE=sit VIEW=side`).
- `trot_sequence_shepherd.jpg`: six frames of the trot, 0.07 s apart (`POSE=trot SEQ=6`).
- `walker_pavement.jpg`: a dog walker staged on a beach-town pavement, the German shepherd on its
  lead (`tools/glshot/dog_city_shot.gd MODE=walker -- --spawn=-593,-102,0,0 --hour=10`).
- `walker_lab_terrier.jpg`: a walker and a terrier trotting on a lead in the crowd lab
  (`tools/crowd/crowd_lab.tscn SCENARIO=dog FOLLOW=1`).
- `yard_dog_fence.jpg`: a brindle pit bull in a front garden, alert behind the pickets, facing the
  player out on the street (`dog_city_shot.gd MODE=yard -- --spawn=-447,556,0,0`).
