#!/usr/bin/env python3
"""Run the reproducible robot composition proof in an isolated native display."""
from pathlib import Path
import os, subprocess, time, tempfile
root=Path(__file__).resolve().parents[3]
runtime=Path(tempfile.mkdtemp(prefix='star-courier-robot-proof-'))
for sub in ['home','data','config','cache']:(runtime/sub).mkdir(parents=True,exist_ok=True)
env=dict(os.environ,DISPLAY='localhost:288',HOME=str(runtime/'home'),XDG_DATA_HOME=str(runtime/'data'),XDG_CONFIG_HOME=str(runtime/'config'),XDG_CACHE_HOME=str(runtime/'cache'))
with open(runtime/'xorg-stdout.log','w') as xlog, open(root/'source_art/2d_v5/robot/runtime-proof.log','w') as log:
 display=subprocess.Popen(['/usr/lib/xorg/Xorg',':288','-noreset','-nolisten','unix','-nolisten','local','-listen','tcp','-ac','-config','/workspace/shared/reaper-portable/xorg1440.conf','-logfile',str(runtime/'xorg.log')],stdout=xlog,stderr=subprocess.STDOUT)
 try:
  time.sleep(1)
  result=subprocess.run(['godot','--path',str(root),'--audio-driver','Dummy','--rendering-method','gl_compatibility','--resolution','1280x720','-s','res://source_art/2d_v5/robot/runtime_robot_proof.gd'],env=env,stdout=log,stderr=subprocess.STDOUT,timeout=45)
  print('Runtime proof exit:',result.returncode)
 finally:
  display.terminate();display.wait(timeout=5)
print((root/'source_art/2d_v5/robot/runtime-proof.log').read_text())
