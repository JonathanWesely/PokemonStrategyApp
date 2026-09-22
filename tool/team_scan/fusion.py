import numpy as np, sys, json
from PIL import Image
import proto, detect
import os; sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), '..')); import dart_twin as dt
from scipy import ndimage as ndi
meta, refs = dt.load_refs()
truth = {'t1_moves': ['Chesnaught','Typhlosion','Rillaboom','Sableye','Scolipede','Armarouge'],
         't1_stats': ['Chesnaught','Typhlosion','Rillaboom','Sableye','Scolipede','Armarouge'],
         't2_moves': ['Heat Rotom','Charizard','Froslass','Garchomp','Whimsicott','Paldean Tauros (Blaze)'],
         't2_stats': ['Heat Rotom','Charizard','Froslass','Garchomp','Whimsicott','Paldean Tauros (Blaze)']}
rows = []
for key in truth:
    photo = proto.load(key+'.jpg'); cards,_ = proto.find_cards(photo)
    ch = np.median([c[3]-c[1] for c in cards])
    sides = [f*ch for f in (0.24,0.28,0.32,0.36,0.41)]
    templates = detect.prep_templates(refs, sides)
    for i,card in enumerate(cards):
        win = detect.window_of(photo, cards[i])
        det = {n: v for v,n,sp in detect.rank(win, templates, top=300)}
        x0,y0,x1,y1 = card; chh,cw = y1-y0,x1-x0; H,W,_ = photo.shape
        crop = photo[max(0,y0-int(0.18*chh)):min(H,y0+int(0.33*chh)),
                     max(0,x0-int(0.005*cw)):min(W,x0+int(0.140*cw))]
        c = crop.astype(np.float32)/255.0
        h,w,_ = c.shape; m = max(5,w//12); k5 = np.ones(5)/5
        bgs = []
        for sl in (c[:,-m:], c[:,:m]):
            bg = np.median(sl, axis=1)
            for cc in range(3): bg[:,cc] = np.convolve(bg[:,cc], k5, mode='same')
            bgs.append(bg)
        d = np.minimum(*[np.sqrt(((c-bg[:,None,:])**2).sum(2)) for bg in bgs])
        alpha = np.clip((d-0.16)/0.25, 0, 1)
        rgb, a = dt.keep_main_blob(c, alpha)
        seg = {}
        if a.size >= 16:
            hard = a>=0.35; holes = ndi.binary_fill_holes(hard)&~hard
            hl,hk = ndi.label(holes); cap = 0.6*hard.sum()
            for j in range(1,hk+1):
                mm = hl==j
                if mm.sum()<=cap: a[mm]=np.maximum(a[mm],0.9)
            cr,ca = dt.square_resize(rgb,a,32)
            for s,rr,ra in refs:
                seg[s['name']] = dt.template_score(cr,ca,rr,ra)
        rows.append((key,i,truth[key][i],det,seg))
        print('done', key, i+1, flush=True)
json.dump([[k,i,t,{a:float(b) for a,b in d.items()},{a:float(b) for a,b in sg.items()}] for k,i,t,d,sg in rows], open('fusion_scores.json','w'))
