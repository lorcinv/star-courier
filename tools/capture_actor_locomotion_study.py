#!/usr/bin/env python3
"""Real-clock native renderer fixture; no injected gameplay, no fixed FPS."""
from pathlib import Path
import json,os,subprocess,time,hashlib
ROOT=Path(__file__).resolve().parents[1]
OUT=ROOT/'docs/qa/v5/locomotion-v2-native';OUT.mkdir(parents=True,exist_ok=True)
RUNTIME=ROOT/'.runtime/locomotion-v2-native'
for part in ['home','data','config','cache']:(RUNTIME/part).mkdir(parents=True,exist_ok=True)
display=os.environ.get('SC_LOCOMOTION_DISPLAY','546')
env=dict(os.environ,DISPLAY='localhost:'+display,HOME=str(RUNTIME/'home'),XDG_DATA_HOME=str(RUNTIME/'data'),XDG_CONFIG_HOME=str(RUNTIME/'config'),XDG_CACHE_HOME=str(RUNTIME/'cache'))
xlog=(OUT/'xorg.stdout').open('w');glog=(OUT/'game.log').open('w');flog=(OUT/'ffmpeg.log').open('w')
xorg=subprocess.Popen(['/usr/lib/xorg/Xorg',':'+display,'-noreset','-nolisten','unix','-nolisten','local','-listen','tcp','-ac','-config',str(ROOT/'tools/xorg_native_1920.conf'),'-logfile',str(OUT/'xorg.log')],stdout=xlog,stderr=subprocess.STDOUT)
game=None;rec=None
try:
 time.sleep(1)
 rec=subprocess.Popen(['ffmpeg','-hide_banner','-loglevel','warning','-y','-f','x11grab','-framerate','30','-video_size','1280x720','-i',env['DISPLAY']+'.0+0,0','-t','13','-c:v','libx264','-preset','veryfast','-crf','17','-pix_fmt','yuv420p','-movflags','+faststart',str(OUT/'actor-locomotion-normal-speed.mp4')],env=env,stdout=flog,stderr=subprocess.STDOUT)
 started=time.monotonic();game=subprocess.Popen(['godot','--path',str(ROOT),'--audio-driver','Dummy','--rendering-method','gl_compatibility','--resolution','1280x720','--position','0,0','--script','res://tools/actor_locomotion_study.gd'],env=env,stdout=glog,stderr=subprocess.STDOUT)
 game.wait(timeout=24);rec.wait(timeout=18)
 metadata={'real_wall_seconds':time.monotonic()-started,'game_exit':game.returncode,'capture_exit':rec.returncode,'capture_fps':30,'engine_fps_claim':None,'fixed_fps':False,'speedup':False,'native_renderer':True,'native_gameplay_input':False,'fixture':'Production walk/run/idle adapters at210px gameplay height, true process-clock155/300px-per-second travel, fixed floor, stops and reversals.','sources':{}}
 for f in ['scripts/actor_motion_2d.gd','assets/2d_v5/actors/cooperative/motion-manifest.json','assets/2d_v5/npcs/walk_exit/motion-manifest.json','tools/actor_locomotion_study.gd']:
  metadata['sources'][f]=hashlib.sha256((ROOT/f).read_bytes()).hexdigest()
 (OUT/'capture-metadata.json').write_text(json.dumps(metadata,indent=2)+'\n')
 if game.returncode or rec.returncode:raise RuntimeError(metadata)
 print(json.dumps(metadata,indent=2))
finally:
 for p in [game,rec,xorg]:
  if p is not None and p.poll() is None:p.terminate();p.wait(timeout=5)
