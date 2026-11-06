import sys,base64,io,os
from PIL import Image
log,out=sys.argv[1],sys.argv[2]
os.makedirs(out,exist_ok=True)
ims=[]
for line in open(log,errors='ignore'):
    if 'PROBE_IMG' in line:
        parts=line.strip().split()
        i=parts.index('PROBE_IMG'); name=parts[i+1]; data=parts[i+2]
        im=Image.open(io.BytesIO(base64.b64decode(data))).convert('RGB')
        im.save(f'{out}/{name}.png'); ims.append((name,im))
for n,im in ims:
    w,h=im.size
    # hero region: centre
    crop=im.crop((int(w*0.44),int(h*0.42),int(w*0.56),int(h*0.70)))
    import numpy as np
    a=np.asarray(crop).astype(float)
    lum=a.mean(2); mask=lum<90
    print(n,im.size,'dark-pixel mean',a[mask].mean(0).round(1) if mask.any() else None, 'bluest', a[(a[:,:,2]-a[:,:,0])>30].mean(0).round(1) if ((a[:,:,2]-a[:,:,0])>30).any() else None, int(((a[:,:,2]-a[:,:,0])>30).sum()))
if ims:
    cs=[im.crop((int(im.size[0]*0.38),int(im.size[1]*0.3),int(im.size[0]*0.62),int(im.size[1]*0.75))).resize((230,243)) for n,im in ims]
    strip=Image.new('RGB',(230*len(cs),243))
    for k,c in enumerate(cs): strip.paste(c,(230*k,0))
    strip.save(f'{out}/strip.png')
