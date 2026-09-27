# Draws the MARGIE logo: a double-helix ring (ring.svg) and the full logo page (logo.html)
# with the wordmark, rendered to PNG by render-logo.mjs.
import math
W=2048; C=W/2
R0=722; A=100; N=7; SW=76; GAP=22
BLUE='#1F6BFF'; ORANGE='#FF8A1F'; CYAN='#16D0EE'; LIME='#8BDF2E'
def pt(r,t): return (C+r*math.cos(t), C+r*math.sin(t))
def strand(sign,t0,t1,steps=120):
    ps=[]
    for i in range(steps+1):
        t=t0+(t1-t0)*i/steps
        r=R0+sign*A*math.sin(N*t)
        ps.append(pt(r,t))
    return 'M'+' L'.join(f'{x:.1f},{y:.1f}' for x,y in ps)
full=lambda s: strand(s,0,2*math.pi,1400)+' Z'
# Strand crossings sit at N*t = k*pi.
cross=[k*math.pi/N for k in range(2*N)]
d=math.pi/N*0.28
# The strand on top alternates at each crossing.
masks={1:[],-1:[]}
tops={1:[],-1:[]}
for k,t in enumerate(cross):
    top=1 if k%2==0 else -1
    seg=strand(top,t-d,t+d,40)
    masks[-top].append(seg)   # cuts a gap in the under strand
    tops[top].append(seg)
rungs=[]
cols=[CYAN,LIME,CYAN]
for k in range(2*N):
    a,b=cross[k],cross[k]+math.pi/N
    for j,f in enumerate((0.3,0.5,0.7)):
        t=a+(b-a)*f
        s=math.sin(N*t)
        r1=R0+A*s; r2=R0-A*s
        lo,hi=min(r1,r2),max(r1,r2)
        if hi-lo<SW*1.4: continue
        x1,y1=pt(lo+SW*0.55,t); x2,y2=pt(hi-SW*0.55,t)
        c=cols[(j+k)%3]
        rungs.append(f'<line x1="{x1:.1f}" y1="{y1:.1f}" x2="{x2:.1f}" y2="{y2:.1f}" stroke="{c}" stroke-width="30" stroke-linecap="round"/>')
def mask(name,segs):
    return f'<mask id="{name}" maskUnits="userSpaceOnUse" x="0" y="0" width="{W}" height="{W}"><rect width="{W}" height="{W}" fill="#fff"/>'+''.join(f'<path d="{s}" fill="none" stroke="#000" stroke-width="{SW+2*GAP}" stroke-linecap="butt"/>' for s in segs)+'</mask>'
ring=f'''<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 {W} {W}" width="{W}" height="{W}">
<defs>{mask('m1',masks[1])}{mask('m2',masks[-1])}</defs>
<g>{''.join(rungs)}</g>
<path d="{full(1)}" fill="none" stroke="{BLUE}" stroke-width="{SW}" stroke-linejoin="round" mask="url(#m1)"/>
<path d="{full(-1)}" fill="none" stroke="{ORANGE}" stroke-width="{SW}" stroke-linejoin="round" mask="url(#m2)"/>
</svg>'''
# The 'I' of the wordmark: a small upright helix, cap height tall.
H=168; IW=60
def vstrand(sign,steps=80,turns=1.5):
    ps=[]
    for i in range(steps+1):
        y=i/steps*H
        x=IW/2+sign*(IW/2-9)*math.sin(turns*2*math.pi*i/steps)
        ps.append((x,y))
    return 'M'+' L'.join(f'{x:.1f},{y:.1f}' for x,y in ps)
irungs=''.join(f'<line x1="14" y1="{y:.1f}" x2="{IW-14}" y2="{y:.1f}" stroke="{c}" stroke-width="11" stroke-linecap="round"/>' for y,c in [(H*0.17,CYAN),(H*0.5,LIME),(H*0.83,CYAN)])
ihelix=f'<svg class="i" viewBox="-6 -6 {IW+12} {H+12}" width="{IW+12}" height="{H+12}">{irungs}<path d="{vstrand(1)}" fill="none" stroke="{BLUE}" stroke-width="18" stroke-linecap="round"/><path d="{vstrand(-1)}" fill="none" stroke="{ORANGE}" stroke-width="18" stroke-linecap="round"/></svg>'
html=f'''<!doctype html><html><head><style>
html,body{{margin:0;background:transparent}}
.wrap{{position:relative;width:{W}px;height:{W}px}}
.ring{{position:absolute;inset:0}}
.text{{position:absolute;inset:0;display:flex;flex-direction:column;align-items:center;justify-content:center;gap:34px;font-family:"Avenir Next","Futura",sans-serif}}
.bsp{{color:{ORANGE};font-weight:700;font-size:118px;letter-spacing:0.42em;margin-right:-0.42em;line-height:1}}
.name{{display:flex;align-items:flex-end;color:{BLUE};font-weight:800;font-size:228px;letter-spacing:0.02em;line-height:.8}}
.name .i{{margin:0 18px 0 14px;transform:translateY(8px)}}
</style></head><body><div class="wrap"><div class="ring">{ring}</div>
<div class="text"><div class="bsp">BSP</div><div class="name"><span>MARG</span>{ihelix}<span>E</span></div></div></div></body></html>'''
open('logo.html','w').write(html); open('ring.svg','w').write(ring)
