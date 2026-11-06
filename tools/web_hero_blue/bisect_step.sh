#!/bin/bash
# usage: bis.sh <commit> <outdir>
set -e
C=$1; OUT=$2; G=/home/user/tools/Godot_v4.7.2-stable_linux.x86_64
cd /home/user/old && git checkout -q -f $C && mkdir -p build/web_old && touch build/.gdignore
timeout 1500 $G --headless --path . --import > $OUT.import.log 2>&1 || true
rm -rf build/web_old/*; timeout 1200 $G --headless --path . --export-release "Web" build/web_old/index.html > $OUT.export.log 2>&1
mkdir -p $OUT; cd /home/user/rando-game/tools/webshot && WEB_ROOT=/home/user/old/build/web_old timeout 2500 ./bookmarks.sh $OUT rain > $OUT/bm.txt 2>&1 || true
python3 - $OUT <<'PY'
import sys
from PIL import Image; import numpy as np
o=sys.argv[1]; im=Image.open(o+'/rain.png').convert('RGB'); im.save(o+'/rain.jpg'); a=np.asarray(im).astype(float)
h,w,_=a.shape; c=a[int(h*.45):int(h*.68),int(w*.47):int(w*.53)]
b=(c[:,:,2]-c[:,:,0])>30; print('BLUE', b.sum(), c[b].mean(0) if b.any() else '')
PY
