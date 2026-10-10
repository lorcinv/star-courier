"""Measure final REAPER masters and compressed runtime assets."""
from pathlib import Path
import json, subprocess
import numpy as np
from scipy.io import wavfile
root=Path(__file__).resolve().parent
report={}
for f in list((root/'renders').glob('*.wav'))+list((root.parent.parent/'assets/audio').glob('*.wav')):
 sr,raw=wavfile.read(f); x=raw.astype(float)/(np.iinfo(raw.dtype).max+1)
 report[f.name]={'sample_rate':sr,'duration_seconds':len(x)/sr,'peak_dBFS':round(20*np.log10(max(float(np.max(np.abs(x))),1e-10)),2),'rms_dBFS':round(20*np.log10(max(float(np.sqrt(np.mean(x*x))),1e-10)),2),'clipped_samples':int(np.sum(np.abs(x)>=.999)),'boundary_jump':float(np.max(np.abs(x[-1]-x[0])))}
for f in (root.parent.parent/'assets/audio').glob('*.ogg'):
 b=subprocess.check_output(['ffmpeg','-v','error','-i',str(f),'-f','f32le','-acodec','pcm_f32le','-']); x=np.frombuffer(b,dtype='<f4').reshape(-1,2)
 report[f.name]={'duration_seconds':len(x)/44100,'peak_dBFS':round(20*np.log10(float(np.max(np.abs(x)))),2),'boundary_jump':float(np.max(np.abs(x[-1]-x[0]))),'clipped_samples':int(np.sum(np.abs(x)>=1))}
for f in (root/'renders').glob('*.wav'):
 probe=json.loads(subprocess.check_output(['ffprobe','-v','quiet','-show_format','-of','json',str(f)]))
 report[f.name]['encoded_by']=probe['format'].get('tags',{}).get('encoded_by')
 assert report[f.name]['encoded_by']=='REAPER'
assert all(r['clipped_samples']==0 for r in report.values())
assert all(r['boundary_jump']<.001 for n,r in report.items() if 'loop' in n)
(root/'audio_validation.json').write_text(json.dumps(report,indent=2))
print(json.dumps(report,indent=2))
