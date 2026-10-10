"""Original Star Courier score: additive synthesis and rhythm composition.
Stems are composition inputs; REAPER renders the final mix, via render.lua.
No samples, external soundfonts, or pre-existing melodies.
"""
from pathlib import Path
import numpy as np
from scipy.io import wavfile
SR=22050
ROOT=Path(__file__).resolve().parent
OUT=ROOT/'stems'; OUT.mkdir(exist_ok=True)
rng=np.random.default_rng(71137)
def hz(m):return 440*2**((m-69)/12)
def tone(m,d,kind):
 t=np.arange(round(d*SR))/SR; f=hz(m)
 if kind=='pad':
  x=.60*np.sin(2*np.pi*f*t)+.22*np.sin(2*np.pi*(f*1.003)*t+.2)+.12*np.sin(4*np.pi*f*t)
  env=np.minimum(t/.28,1)*np.minimum((d-t)/.40,1)
 elif kind=='bass':
  x=np.sin(2*np.pi*f*t)+.18*np.sin(4*np.pi*f*t)+.09*np.sin(6*np.pi*f*t)
  env=np.minimum(t/.009,1)*np.exp(-t*2)*np.minimum((d-t)/.065,1)
 elif kind=='bell':
  x=np.sin(2*np.pi*f*t)+.25*np.sin(2*np.pi*f*2*t)*np.exp(-t*4)+.09*np.sin(2*np.pi*f*3*t)*np.exp(-t*6)
  env=np.minimum(t/.008,1)*np.exp(-t*3.8)*np.minimum((d-t)/.10,1)
 else:
  x=np.sin(2*np.pi*f*t)+.22*np.sin(4*np.pi*f*t)+.10*np.sin(6*np.pi*f*t)
  env=np.minimum(t/.025,1)*np.exp(-t*1.5)*np.minimum((d-t)/.09,1)
 return x*env

def put(buf,x,start,gain=1,pan=0,wrap=True):
 idx=(np.arange(len(x))+round(start*SR))%len(buf)
 gains=np.array([np.sqrt((1-pan)/2),np.sqrt((1+pan)/2)])*gain
 np.add.at(buf,idx,x[:,None]*gains)
def save(path,x):wavfile.write(path,SR,(np.clip(x,-.999,.999)*32767).astype(np.int16))
def cue(name,bpm,flight):
 beat=60/bpm; dur=beat*64; n=round(dur*SR)
 tracks={k:np.zeros((n,2)) for k in ['Warm nebula pads','Courier sub bass','Glass parcel arpeggio','Signal melody','Pocket rhythm']}
 # Cmaj9, Am9, Fmaj9, G6; two bars per harmony, twice through.
 chords=[[48,55,59,62,64],[45,52,55,59,60],[41,48,52,55,57],[43,50,55,57,59]]
 lead=[(0,76),(1.5,79),(3,74),(4,72),(6,71),(8,72),(10,76),(11.5,74),(12,71),(14,67)]
 for bar in range(16):
  chord=chords[(bar//2)%4]; start=bar*4*beat
  for j,m in enumerate(chord):put(tracks['Warm nebula pads'],tone(m,4*beat+.55,'pad'),start,.037 if flight else .044,(j-2)*.28)
  for b in ([0,1.5,2,3.25] if flight else [0,2.5]):put(tracks['Courier sub bass'],tone(chord[0]-12,.7*beat,'bass'),start+b*beat,.19)
  steps=8 if flight else 4
  for j in range(steps):
   m=chord[[0,2,3,4,2,1,3,2][j]]+12
   put(tracks['Glass parcel arpeggio'],tone(m,.72,'bell'),start+j*(4/steps)*beat,.065,(-1 if j%2 else 1)*.48)
   put(tracks['Glass parcel arpeggio'],tone(m,.72,'bell'),start+(j*(4/steps)+.75)*beat,.016,(-1 if j%2 else 1)*-.5)
  # Rounded kick and filtered digital hats. No sampled percussion.
  for b in ([0,1,2,3] if flight else [0,2]):
   t=np.arange(round(.24*SR))/SR
   x=np.sin(2*np.pi*(48*t+55*.016*(1-np.exp(-t/.016))))*np.exp(-t*18)*np.minimum(t/.002,1)
   put(tracks['Pocket rhythm'],x,start+b*beat,.20 if flight else .12)
  for b in np.arange(.5,4,.5 if flight else 1):
   t=np.arange(round(.08*SR))/SR; noise=rng.standard_normal(len(t)); noise=np.r_[0,np.diff(noise)]*.28
   put(tracks['Pocket rhythm'],noise*np.exp(-t*65)*np.minimum(t/.002,1),start+b*beat,.045 if flight else .023,.3 if int(b*2)%2 else -.3)
  for b in [1,3]:
   t=np.arange(round(.16*SR))/SR; x=(rng.standard_normal(len(t))*.20+np.sin(2*np.pi*180*t)*.35)*np.exp(-t*25)*np.minimum(t/.003,1)
   put(tracks['Pocket rhythm'],x,start+b*beat,.08 if flight else .04,-.15)
 for base in [0,32]:
  for pos,m in lead:
   when=(base+pos+(0 if flight else 8))*beat
   if when<dur:put(tracks['Signal melody'],tone(m+(0 if flight else -12),.9*beat,'lead'),when,.068 if flight else .040,-.10)
 for i,(track,x) in enumerate(tracks.items()):
  # Circular echo preserves musical seam and supplies depth.
  if i in [0,2,3]: x=x+.18*np.roll(x,round(.75*beat*SR),axis=0)[:,::-1]
  save(OUT/f'{name}_{i+1}.wav',x)
 # RPP maintains named editable tracks and explicit render interval.
 p=[f'<REAPER_PROJECT 0.1 7.82 1',f'  SAMPLERATE 44100',f'  TEMPO {bpm}',f'  TIMELOCKMODE 1',f'  LOOP 1',f'  LOOPGRAN 0 4',f'  SELECTION 0 {dur}',f'  RENDER_FILE "../../assets/audio"',f'  RENDER_PATTERN "{name}"',f'  RENDER_BOUNDSFLAG 0',f'  RENDER_RANGE 1 0 {dur}',f'  RENDER_SRATE 44100',f'  RENDER_CHANNELS 2',f'  RENDER_ADDTOPROJ 0',f'  MASTER_VOLUME 0.92']
 for i,track in enumerate(tracks):
  p.extend(['  <TRACK',f'    NAME "{track}"','    VOLPAN 1 0','    MAINSEND 1','    <ITEM','      POSITION 0',f'      LENGTH {dur}','      VOLPAN 1 0 1 -1','      SOFFS 0','      FADEIN 1 0.005 0','      FADEOUT 1 0.005 0',f'      NAME "{name}_{i+1}.wav"','      <SOURCE WAVE',f'        FILE "stems/{name}_{i+1}.wav"','      >','    >','  >'])
 p.append('>'); (ROOT/f'{name}.rpp').write_text('\n'.join(p)+'\n')
 print(name,dur,'seconds',len(tracks),'stems')
cue('workshop_loop',96,False);cue('flight_loop',120,True)
# Compact tactile UI sounds, all additive original synthesis.
sfx=ROOT.parent.parent/'assets/audio'
for name,notes,d in [('ui_select',[84],.14),('module_snap',[60,72],.24),('delivery_success',[72,76,79,84],.80),('warning',[63,60],.48),('launch',[48,60,72],1.10)]:
 x=np.zeros((round(d*SR),2))
 for i,m in enumerate(notes):
  start=i*(d*.50/max(1,len(notes)-1)); wave=tone(m,min(.4,d-start),'bell' if name!='launch' else 'lead')
  put(x,wave,start,.17,0)
 x[-min(200,len(x)):]*=np.linspace(1,0,min(200,len(x)))[:,None]
 save(sfx/f'{name}.wav',x)
