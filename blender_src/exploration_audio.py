"""Original deterministic additive/noise synthesis. 22050 Hz, mono PCM, no sampled works."""
from pathlib import Path
import math,random,wave,array
ROOT=Path(__file__).resolve().parents[1]; RATE=22050
random.seed(27013)
def write(name,seconds,fn):
 samples=array.array('h'); low=0.0
 for i in range(int(RATE*seconds)):
  t=i/RATE; white=random.uniform(-1,1); low=low*.98+white*.02
  # Periodic gain is silent at the loop seam to avoid a click in filtered noise.
  seam=min(1.0,t/.08,(seconds-t)/.08)
  v=fn(t,white,low)*max(0,seam)
  samples.append(int(max(-.94,min(.94,v))*32767))
 path=ROOT/'assets/audio/explore'/f'{name}.wav'
 with wave.open(str(path),'wb') as f:
  f.setnchannels(1);f.setsampwidth(2);f.setframerate(RATE);f.writeframes(samples.tobytes())
 print(name,len(samples)/RATE,'seconds',max(abs(v) for v in samples)/32767,'peak')
write('wind',8,lambda t,w,l:l*1.2*(.65+.3*math.sin(t*math.tau/8))+w*.014)
write('rain',8,lambda t,w,l:w*.17+l*.6)
write('surf',12,lambda t,w,l:(w*.06+l*.9)*(.5+.4*math.sin(t*math.tau/6)))
write('engine',8,lambda t,w,l:math.sin(t*math.tau*55)*.14+math.sin(t*math.tau*110)*.035+l*.4)
def forest(t,w,l):
 phrase=t%4; gate=math.sin(phrase*math.pi/.3)**2 if phrase<.3 else 0
 return l*.20+math.sin(math.tau*(1700*t+55*math.sin(t*17)))*gate*.035
write('forest',16,forest)
def pad(t,w,l):
 # A suspended chord, slowly opening and closing. Frequencies are exact loop multiples.
 return sum(math.sin(t*math.tau*f)*(.7+.3*math.sin(t*math.tau/32+i)) for i,f in enumerate([65.40625,98.0,130.8125,146.84375,196.0]))*.042
write('orbit_pad',32,pad)
