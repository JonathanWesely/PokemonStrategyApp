"""Prototype for the Champions team-select recogniser.
Pipeline:  panels -> type badges (chromaticity + glyph IoU) -> sprite NCC
           against the TRUE 2D sprites -> type-gated unique assignment.
This is the reference implementation that lib/src/recognition/ mirrors."""
from PIL import Image
import numpy as np, json, glob, os
from scipy import ndimage as ndi
from scipy.optimize import linear_sum_assignment

ROOT=os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
REF=os.path.join(ROOT,'pokemon2Dsprites'); BADGE=os.path.join(ROOT,'pokemontypeimages','badges')
MAN=json.load(open(REF+'/manifest.json'))['sprites']
N=32

# ---------------------------------------------------------------- helpers --
def to_patch(rgb, alpha, n=N):
    ys,xs=np.where(alpha>0.35)
    if len(ys)==0: return None
    y0,y1,x0,x1=ys.min(),ys.max()+1,xs.min(),xs.max()+1
    r=rgb[y0:y1,x0:x1].astype(np.float32); w=alpha[y0:y1,x0:x1].astype(np.float32)
    h,wd=w.shape; s=max(h,wd)
    R=np.zeros((s,s,3),np.float32); A=np.zeros((s,s),np.float32)
    oy,ox=(s-h)//2,(s-wd)//2
    R[oy:oy+h,ox:ox+wd]=r; A[oy:oy+h,ox:ox+wd]=w
    R=np.asarray(Image.fromarray(R.astype(np.uint8)).resize((n,n),Image.LANCZOS),np.float32)/255.
    A=np.asarray(Image.fromarray((A*255).astype(np.uint8)).resize((n,n),Image.LANCZOS),np.float32)/255.
    return R,A

def ncc(pa,pb):
    (Ra,Aa),(Rb,Ab)=pa,pb
    w=Aa*Ab; s=w.sum()
    if s<20: return -1.0
    tot=0.
    for c in range(3):
        x,y=Ra[...,c],Rb[...,c]
        dx=x-(w*x).sum()/s; dy=y-(w*y).sum()/s
        tot+=(w*dx*dy).sum()/(np.sqrt((w*dx*dx).sum()*(w*dy*dy).sum())+1e-8)
    shape=w.sum()/(np.maximum(Aa,Ab).sum()+1e-8)
    return 0.75*(tot/3.)+0.25*shape

def tight(crop,bgcol=None):
    c=crop.astype(np.float32); H,W,_=c.shape
    if bgcol is None:
        ring=np.zeros((H,W),bool); ring[:2,:]=ring[-2:,:]=True; ring[:,:2]=ring[:,-2:]=True
        bgcol=np.median(c[ring],0)
    m=ndi.binary_opening(np.sqrt(((c-bgcol)**2).sum(2))>45,np.ones((3,3)))
    if m.sum()<30: return c
    lab,k=ndi.label(m); sz=ndi.sum(m,lab,range(1,k+1))
    return c[ndi.find_objects(lab)[int(np.argmax(sz))]]

def badge_feat(crop,n=28):
    """Exposure-invariant badge signature: body chromaticity + white-glyph mask."""
    c=np.asarray(Image.fromarray(np.clip(crop,0,255).astype(np.uint8)).resize((n,n),Image.LANCZOS),np.float32)
    s=c.sum(2)+1e-6
    chroma=np.dstack([c[...,0]/s, c[...,1]/s])
    lum=c.mean(2); sat=c.max(2)-c.min(2)
    glyph=((lum>np.percentile(lum,70))&(sat<np.percentile(sat,45))).astype(np.float32)
    body=chroma[glyph<0.5]
    col=np.median(body,0) if len(body)>40 else np.median(chroma.reshape(-1,2),0)
    return col,glyph

# ------------------------------------------------------------ references --
REFS=[]
for m in MAN:
    a=np.asarray(Image.open(os.path.join(REF,m['file'])).convert('RGBA'))
    REFS.append((m,to_patch(a[...,:3],a[...,3]/255.)))
TYPES={}
for f in sorted(glob.glob(BADGE+'/*.png')):
    TYPES[os.path.basename(f)[:-4]]=badge_feat(tight(np.asarray(Image.open(f).convert('RGB')).astype(float)))

MIN_GLYPH_IOU=0.35   # see read_badge

def read_badge(crop,panelbg):
    """-> [(score, type, glyph_iou)] best first. The glyph IoU is the
    EXPOSURE-INVARIANT half of the evidence: hue alone will always name some
    type, and on a soft, colour-cast capture (the rig's OV2640) it names the
    wrong one with a confident score - rig frame 2026-09-17 read Water as
    Fire and Ghost as Normal at iou 0.03 and 0.12, while every correct read
    on the phone fixtures scored iou >= 0.19. Callers drop a read below
    MIN_GLYPH_IOU: no badge means 'no prior', which is worth far more than a
    confident wrong one (it costs the true species typePriorPenalty AND
    hands typePriorBonus to an impostor)."""
    col,gl=badge_feat(tight(crop,panelbg))
    out=[]
    for t,(tc,tg) in TYPES.items():
        d=np.sqrt(((col-tc)**2).sum())
        iou=(gl*tg).sum()/(np.maximum(gl,tg).sum()+1e-6)
        out.append((0.55*(1-min(d/0.22,1))+0.45*iou, t, iou))
    out.sort(reverse=True); return out

def slot_filled(crop,panelbg):
    c=crop.astype(np.float32)
    lum=c.mean(2); sat=c.max(2)-c.min(2)
    white=((lum>150)&(sat<70)).mean()
    far=np.sqrt(((np.median(c.reshape(-1,3),0)-panelbg)**2).sum())
    return white>0.045 and far>40

# ---------------------------------------------------------------- panels --
# v3 (2026-09-06): exposure-invariant card mask + evenly-spaced-slot model.
# Mirrors SpriteMatcher._findPanels in Dart; tune here first.

def red_mask(a):
    a=a.astype(np.float32); s=a.sum(2)+1e-6
    r=a[...,0]/s; g=a[...,1]/s; v=a.max(2)
    # crimson AND magenta cards; rejects the trainer-name pill (g too high),
    # yellow walls, blue court, white glare, orange Joy-Con.
    return (r>=0.36)&(g<=0.27)&(r>=g+0.15)&(v>=55)

def runs(v,thr):
    out=[]; s=None
    for i,x in enumerate(v):
        if x>thr and s is None: s=i
        elif x<=thr and s is not None: out.append((s,i)); s=None
    if s is not None: out.append((s,len(v)))
    return out

def run_containing(rs, i):
    for r in rs:
        if r[0]<=i<r[1]: return r
    return max(rs,key=lambda r:r[1]-r[0]) if rs else None

def find_panels(a, expected=6):
    H,W,_=a.shape
    m=red_mask(a); m[:, :W//2]=False
    m=ndi.binary_opening(m,np.ones((3,3)))
    colp=ndi.uniform_filter1d(m.mean(0),9)
    if colp.max()<=0: return []
    xr=run_containing(runs(colp,0.15*colp.max()), int(np.argmax(colp)))
    if xr is None: return []
    sx0,sx1=xr
    rowp=ndi.uniform_filter1d(m[:,sx0:sx1].mean(1),5)
    hi=np.percentile(rowp,90); lo=np.percentile(rowp,20)
    bands=[b for b in runs(rowp, lo+0.40*(hi-lo)) if b[1]-b[0]>=0.02*H]
    if not bands: return []
    hs=np.array([b[1]-b[0] for b in bands]); med=np.median(hs)
    bands=[b for b,h in zip(bands,hs) if 0.6*med<=h<=1.5*med]
    if len(bands)<2:
        return [[sx0,b[0],sx1,b[1]] for b in bands]
    # A sprite bright enough to break the card mask splits that card into
    # FRAGMENTS that survive the height filter, and a fragment must not set
    # the pitch, the height or the phase: the whole even-spacing model hangs
    # off one anchor centre, so a half-card anchor slides all six slots (rig
    # frame 2026-09-17: every panel 28px off, and Scovillain cropped to 74px
    # of its 110px card). Estimate all three from FULL bands only, and take
    # the phase as a median residual so one bad band cannot move it.
    kept=np.array([b[1]-b[0] for b in bands]); cardh=float(np.median(kept))
    # TWO-sided: a band merged with its neighbour (the trainer-name pill fuses
    # with card 1 at the detect scale) is as misleading an anchor as a
    # fragment, and the 1.5x arm of the height filter above lets it through.
    full=[b for b,h in zip(bands,kept) if 0.8*cardh<=h<=1.15*cardh]
    if len(full)<2: full=bands
    cs=np.array([(b[0]+b[1])/2 for b in full])
    gaps=np.diff(cs); pitch=float(np.median(gaps[gaps<1.6*gaps.min()]))
    ph=min(0.95*pitch, float(np.median([b[1]-b[0] for b in full])))
    phase=float(np.median(cs-np.round((cs-cs[0])/pitch)*pitch))
    idx=np.round((cs-phase)/pitch).astype(int)
    lo_s=min(0,int(idx.max())-expected+1); hi_s=max(0,int(idx.max())-expected+1)
    def mass(c):
        y0=max(0,int(c-ph/2)); y1=min(H,int(c+ph/2))
        return float(rowp[y0:y1].sum()) if y1>y0 else 0.0
    # Phase: the layout whose six slots hold the most red. A panel drowned in
    # glare still carries more red than the blank strip below the stack, so
    # this recovers it; counting detected bands alone slides the stack down.
    best=None
    for start in range(lo_s-1,hi_s+2):
        slots=[phase+pitch*(start+k) for k in range(expected)]
        if slots[0]<0.35*pitch or slots[-1]>H-0.35*pitch: continue
        sc=sum(mass(s) for s in slots)
        if best is None or sc>best[0]: best=(sc,slots)
    if best is None: return []
    cx=(sx0+sx1)//2
    rows=[]; xs0=[]; xs1=[]
    for c in best[1]:
        # No snapping to bands. The phase is already a median fit over whole
        # cards and lands within ~2px; every misplaced panel across two rig
        # frames came from a slot snapping onto a band that was not a card
        # (a sprite-broken fragment, or a card fused with the trainer pill).
        y0=max(0,int(round(c-ph/2))); y1=min(H,int(round(c+ph/2)))
        if y1-y0<0.5*ph: continue
        cp=m[y0:y1,:].mean(0)
        xr2=run_containing(runs(cp,0.12), cx)
        if xr2 and (xr2[1]-xr2[0])>=0.6*(sx1-sx0): xs0.append(xr2[0]); xs1.append(xr2[1])
        rows.append((y0,y1))
    # One x-range for the whole stack (median of per-panel extents): glare or
    # a dark sprite can shrink a single panel's extent, and the fisheye tilt
    # across the stack is only a few percent of the card width.
    x0=int(np.median(xs0)) if xs0 else sx0
    x1=int(np.median(xs1)) if xs1 else sx1
    return [[x0,y0,x1,y1] for y0,y1 in rows]


SPRITE_X=(0.13,0.63); SLOTS=[(0.635,0.812),(0.812,0.985)]; BADGE_Y=(0.06,0.56)
BG_DIST=45.0

def badge_boxes(p, bg, y0, y1, ax0, ax1):
    """Badge squares in the badge area: column runs of off-card pixels, a
    run ~2x as wide as tall split in two. The game centres a SINGLE badge
    between the two slots (each slot sees half; neither half reads). Mirrors
    ChampionsReferenceSet.badgeBoxes."""
    reg=p[y0:y1, ax0:ax1]
    d=np.sqrt(((reg-bg)**2).sum(2))
    on=(d>BG_DIST).mean(0)>0.25
    rs=runs(on.astype(float),0.5)
    merged=[]
    for r in rs:
        if merged and r[0]-merged[-1][1]<3: merged[-1]=(merged[-1][0],r[1])
        else: merged.append(r)
    h=y1-y0; boxes=[]
    for r0,r1 in merged:
        w=r1-r0
        if w<0.3*h: continue
        n=max(1,min(2,int(round(w/h)))); step=w/n
        for k in range(n):
            boxes.append((ax0+int(r0+k*step)-2,y0,ax0+int(r0+(k+1)*step)+2,y1))
    return boxes[:2]

WORK_W=1200   # SpriteMatcher.workWidth

def panels_of(a, expected=6):
    """Panels in ORIGINAL pixels, detected the way Dart does it: on a copy no
    wider than WORK_W, then scaled back. Detecting at native resolution finds
    different bands (at 1200 the trainer pill fuses with card 1) - so a twin
    that skips the downscale is not testing what ships."""
    H,W,_=a.shape
    if W<=WORK_W: return find_panels(a,expected)
    k=WORK_W/W
    small=np.asarray(Image.fromarray(a.astype(np.uint8)).resize(
        (WORK_W,round(H*k)), Image.BILINEAR)).astype(np.float32)
    out=[]
    for x0,y0,x1,y1 in find_panels(small,expected):
        out.append([max(0,int(round(x0/k))), max(0,int(round(y0/k))),
                    min(W,int(round(x1/k))), min(H,int(round(y1/k)))])
    return out

def analyse(path, truth=None, verbose=True):
    a=np.asarray(Image.open(path).convert('RGB')).astype(np.float32)
    panels=panels_of(a)
    rows=[]
    for (x0,y0,x1,y1) in panels:
        p=a[y0:y1,x0:x1]; ph,pw,_=p.shape
        R,G,B=p[...,0],p[...,1],p[...,2]
        bg=np.median(p[(R>G+70)&(G<95)&(R>100)],0)
        types=[]
        by0,by1=int(BADGE_Y[0]*ph),int(BADGE_Y[1]*ph)
        def read(c):
            if not c.size or not slot_filled(c,bg): return None
            r=read_badge(c,bg)[0]
            return r[1] if r[2]>=MIN_GLYPH_IOU else None
        for fx0,fx1 in SLOTS:
            t=read(p[by0:by1, int(fx0*pw):int(fx1*pw)])
            if t: types.append(t)
        if not types:   # a single badge is centred between the slots: find the square itself
            for bx0,by0_,bx1,by1_ in badge_boxes(p,bg,by0,by1,int(SLOTS[0][0]*pw),int(SLOTS[-1][1]*pw)):
                t=read(p[by0_:by1_, max(0,bx0):min(pw,bx1)])
                if t: types.append(t)
        sp=p[:, int(SPRITE_X[0]*pw):int(SPRITE_X[1]*pw)]
        d=np.sqrt(((sp-bg)**2).sum(2))
        fg=ndi.binary_fill_holes(ndi.binary_closing(d>80,np.ones((3,3)),iterations=2))
        lab,k=ndi.label(fg); keep=np.zeros(d.shape,bool)
        if k:
            sz=ndi.sum(fg,lab,range(1,k+1)); main=int(np.argmax(sz))+1; keep=(lab==main)
            dil=ndi.binary_dilation(keep,np.ones((3,3)),iterations=8)
            for j in range(1,k+1):
                if j!=main and sz[j-1]>=40 and (dil&(lab==j)).any(): keep|=(lab==j)
            keep=ndi.binary_fill_holes(keep)
        alpha=np.clip((d-60)/40,0,1)*ndi.binary_dilation(keep,np.ones((3,3)))
        q=to_patch(sp,alpha)
        rows.append((types,q))

    # score matrix: sprite NCC + type agreement prior
    S=np.zeros((len(rows),len(REFS)))
    for i,(types,q) in enumerate(rows):
        want={t.capitalize() for t in types}
        for j,(m,r) in enumerate(REFS):
            s=ncc(q,r)
            rt=set(m['types'] or [])
            if want and rt:
                agree=len(want&rt)/len(want)
                s+= 0.22*agree - 0.10*(1-agree)
            S[i,j]=s
    ri,ci=linear_sum_assignment(-S)                     # 6 different Pokemon
    hits=0
    for i,j in sorted(zip(ri,ci)):
        m=REFS[j][0]
        rank=sorted(range(len(REFS)),key=lambda k:-S[i,k])
        alts=' | '.join(f"{REFS[k][0]['displayName']}:{S[i,k]:.3f}" for k in rank[1:4])
        mark=''
        if truth:
            good=m['displayName']==truth[i]; hits+=good
            mark=' OK' if good else f'  WRONG (want {truth[i]})'
        if verbose:
            print(f" panel{i+1} [{'+'.join(t for t in rows[i][0]) or '-':<16}] -> "
                  f"{m['displayName']}:{S[i,j]:.3f}{mark}\n            runners-up: {alts}")
    if truth: print(f'\n  sprites {hits}/{len(truth)}')
    return rows

if __name__=='__main__':
    import sys as _sys
    print('refs',len(REFS),'types',len(TYPES))
    path=_sys.argv[1] if len(_sys.argv)>1 else os.path.join(ROOT,'test','fixtures','select1.jpeg')
    truth=_sys.argv[2].split(',') if len(_sys.argv)>2 else (
        ['Raichu','Staraptor','Pelipper','Swampert','Dragonite','Bellibolt'] if path.endswith('select1.jpeg') else None)
    analyse(path, truth=truth)
