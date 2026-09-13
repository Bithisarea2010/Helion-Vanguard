"""Original Helion 1.3 sound palette. Run using Blender's bundled numpy.
Only writes hv_*.wav and its evidence manifest; preserves the original bank.
Mono spatial one-shots, intentional headroom, periodic seamless flight bed.
"""
from pathlib import Path
import numpy as np
import wave, json

ROOT=Path(__file__).resolve().parents[1]
OUT=ROOT/'assets/audio/sfx'
EVIDENCE=ROOT/'docs/evidence/quality-2026-09-13/after'
SR=44100
rng=np.random.default_rng(1309)
manifest=[]
palette=[]

def time(d): return np.arange(int(SR*d))/SR
def oscillator(f): return np.sin(np.cumsum(f)*2*np.pi/SR)
def band(x,lo,hi):
    f=np.fft.rfftfreq(len(x),1/SR)
    filt=1/(1+(f/hi)**4) * (1-1/(1+(f/max(lo,1))**4))
    return np.fft.irfft(np.fft.rfft(x)*filt,len(x))
def air(d,lo=100,hi=5000): return band(rng.normal(0,1,int(SR*d)),lo,hi)
def tail(x):
    out=x.copy()
    for sec,gain in [(.013,.13),(.029,.10),(.051,.06)]:
        n=int(sec*SR);out[n:] += x[:-n]*gain
    return out
def write(name,x,peak=.68,loop=False):
    x=x-np.mean(x)
    if not loop:
        fade=min(len(x)//3,int(.035*SR))
        x[-fade:] *= np.linspace(1,0,fade)
        attack=min(int(.001*SR),len(x));x[:attack] *= np.linspace(0,1,attack)
    x *= peak/max(np.max(np.abs(x)),1e-9)
    pcm=np.round(x*32767).astype('<i2')
    with wave.open(str(OUT/(name+'.wav')),'wb') as w:
        w.setnchannels(1);w.setsampwidth(2);w.setframerate(SR);w.writeframes(pcm.tobytes())
    manifest.append({'name':name,'seconds':len(x)/SR,'peak_dbfs':float(20*np.log10(max(abs(x)))),
        'rms_dbfs':float(20*np.log10(np.sqrt(np.mean(x*x)))), 'clipped_samples':int(np.sum(abs(x)>=1)),
        'boundary_step':float(abs(x[-1]-x[0])), 'loop':loop})
    if not loop:palette.append(np.concatenate([x*.60,np.zeros(int(.25*SR))]))

t=time(.31)
pulse=oscillator(240+1450*np.exp(-t*25))*.64*np.exp(-t*19)
pulse+=np.sin(2*np.pi*85*t)*.25*np.exp(-t*35)+air(.31,1300,6500)*.18*np.exp(-t*75)
write('hv_pulse',tail(pulse))
t=time(.19)
cannon=air(.19,280,7200)*np.exp(-t*77)*.58
cannon+=(np.sin(2*np.pi*132*t)+.38*np.sin(2*np.pi*367*t))*np.exp(-t*31)*.42
write('hv_cannon',tail(cannon),.60)
t=time(.9);a=np.maximum(t-.075,0)
rail=oscillator(650+820*np.minimum(t/.075,1))*np.minimum(t/.075,1)*np.exp(-t*25)*.10
rail+=(oscillator(180+2900*np.exp(-a*33))*np.exp(-a*13)*.52+air(.9,400,7000)*np.exp(-a*30)*.40)*(t>=.075)
rail+=np.sin(2*np.pi*65*t)*np.exp(-a*10)*(t>=.075)*.35
write('hv_rail',tail(rail))
t=time(.72)
plasma=oscillator(95+620*np.exp(-t*13))*.65*np.exp(-t*7)
plasma+=air(.72,180,2500)*.34*np.exp(-t*12)+np.sin(2*np.pi*49*t)*.24*np.exp(-t*10)
write('hv_plasma',tail(np.tanh(plasma*1.3)))
t=time(.47)
shield=sum(np.sin(2*np.pi*f*t+3*np.exp(-t*14)) for f in [730,1120,1840])/3
shield=shield*np.exp(-t*10)+air(.47,2200,6500)*.12*np.exp(-t*45)
write('hv_shield',tail(shield),.51)
t=time(.42)
armor=air(.42,200,5500)*np.exp(-t*55)*.7
armor+=(np.sin(2*np.pi*94*t)*.5+np.sin(2*np.pi*321*t)*.17)*np.exp(-t*15)
write('hv_armor',tail(armor),.62)

def motif(notes,duration):
    t=time(duration);out=np.zeros(len(t))
    for delay,f in notes:
        a=np.maximum(t-delay,0);en=(1-np.exp(-a*200))*np.exp(-a*5)*(t>=delay)
        out+=(np.sin(2*np.pi*f*a)+.20*np.sin(2*np.pi*f*2*a))*en*.35
    return tail(out)
write('hv_transit',motif([(0,587.33),(.13,880),(.26,1174.66)],1.3),.55)
write('hv_resupply',motif([(0,440),(.13,587.33),(.28,880)],1.3),.51)
# Frequencies and slow modulation complete integer periods in sixteen seconds.
t=time(16)
bed=(np.sin(2*np.pi*58*t)*.45+np.sin(2*np.pi*87.5*t)*.19+np.sin(2*np.pi*116.125*t)*.10)
bed=bed*(.72+.12*np.sin(2*np.pi*t/16))
bed+=band(rng.normal(0,1,len(t)),45,650)*.18*(.8+.2*np.cos(2*np.pi*t/8))
write('hv_flight_bed',bed,.36,True)
# A dry, original-only preview; excludes the owner's music playlist.
preview=np.concatenate(palette)
with wave.open(str(EVIDENCE/'sound-palette.wav'),'wb') as w:
    w.setnchannels(1);w.setsampwidth(2);w.setframerate(SR)
    w.writeframes(np.round(preview*32767).astype('<i2').tobytes())
(EVIDENCE/'audio-assets.json').write_text(json.dumps(manifest,indent=2)+'\n')
print(json.dumps(manifest,indent=2))
