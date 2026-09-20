"""Prototype for the Champions team-select recogniser.
Pipeline:  panels -> type badges (chromaticity + glyph IoU) -> sprite NCC
           against the TRUE 2D sprites -> type-gated unique assignment.
This is the reference implementation that lib/src/recognition/ mirrors."""
from PIL import Image
import numpy as np, json, glob, os
from scipy import ndimage as ndi
from scipy.optimize import linear_sum_assignment

REF='out/pokemon2Dsprites'; BADGE='out/pokemontypeimages/badges'
MAN=json.load(open(REF+'/manifest.json'))['sprites']
N=48

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

def read_badge(crop,panelbg):
    col,gl=badge_feat(tight(crop,panelbg))
    out=[]
    for t,(tc,tg) in TYPES.items():
        d=np.sqrt(((col-tc)**2).sum())
        iou=(gl*tg).sum()/(np.maximum(gl,tg).sum()+1e-6)
        out.append((0.55*(1-min(d/0.22,1))+0.45*iou, t))
    out.sort(reverse=True); return out

def slot_filled(crop,panelbg):
    c=crop.astype(np.float32)
    lum=c.mean(2); sat=c.max(2)-c.min(2)
    white=((lum>150)&(sat<70)).mean()
    far=np.sqrt(((np.median(c.reshape(-1,3),0)-panelbg)**2).sum())
    return white>0.045 and far>40

# ---------------------------------------------------------------- panels --
def find_panels(a):
    R,G,B=a[...,0],a[...,1],a[...,2]
    m=ndi.binary_closing((R>G+70)&(G<95)&(R>100),np.ones((5,5)))
    lab,k=ndi.label(m); sz=ndi.sum(m,lab,range(1,k+1)); objs=ndi.find_objects(lab)
    H,W=m.shape; out=[]
    for j in range(1,k+1):
        sl=objs[j-1]; hh=sl[0].stop-sl[0].start; ww=sl[1].stop-sl[1].start
        if sz[j-1]<0.002*H*W: continue
        if not (1.6*hh<ww<4.0*hh): continue
        out.append([sl[1].start,sl[0].start,sl[1].stop,sl[0].stop])
    out.sort(key=lambda b:b[1])
    if not out: return out
    x0=int(np.median([b[0] for b in out])); x1=int(np.max([b[2] for b in out]))
    return [[x0,b[1],x1,b[3]] for b in out]

SPRITE_X=(0.13,0.63); SLOTS=[(0.635,0.812),(0.812,0.985)]; BADGE_Y=(0.06,0.56)

def analyse(path, truth=None, verbose=True):
    a=np.asarray(Image.open(path).convert('RGB')).astype(np.float32)
    panels=find_panels(a)
    rows=[]
    for (x0,y0,x1,y1) in panels:
        p=a[y0:y1,x0:x1]; ph,pw,_=p.shape
        R,G,B=p[...,0],p[...,1],p[...,2]
        bg=np.median(p[(R>G+70)&(G<95)&(R>100)],0)
        types=[]
        for fx0,fx1 in SLOTS:
            c=p[int(BADGE_Y[0]*ph):int(BADGE_Y[1]*ph), int(fx0*pw):int(fx1*pw)]
            if c.size and slot_filled(c,bg): types.append(read_badge(c,bg)[0][1])
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
    print('refs',len(REFS),'types',len(TYPES))
    analyse('/mnt/user-data/uploads/PokemonStrategyApp/images/PokemonSelectionScreen.png',
            truth=['Raichu','Staraptor','Pelipper','Swampert','Dragonite','Bellibolt'])
