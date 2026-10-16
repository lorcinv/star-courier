#!/usr/bin/env python3
"""Extend the existing native XTest driver with a real held-pointer drag.
The child and drag helper share the same isolated execution network namespace.
No engine method calls, synthetic Godot events, or save mutations are used.
"""
import json, os, pathlib, subprocess, sys
from PIL import Image
root=pathlib.Path(__file__).resolve().parents[1]
child=subprocess.Popen([sys.executable,str(root/'tools/qa_native_regression.py')],stdin=subprocess.PIPE,stdout=subprocess.PIPE,text=True,bufsize=1)
def receive():
 line=child.stdout.readline()
 if not line:raise RuntimeError('Native driver exited before replying')
 result=json.loads(line)
 if result.get('screenshot') and result.get('geometry'):
  actual=Image.open(result['screenshot']).size;expected=(result['geometry']['width'],result['geometry']['height'])
  if actual!=expected:raise RuntimeError(f'Native screenshot was clipped by the Xorg root: {actual} instead of {expected}')
  result['verified_capture_pixels']=actual
 return result
def send(command):
 child.stdin.write(json.dumps(command)+'\n');child.stdin.flush();return receive()
try:
 print(json.dumps(receive(),ensure_ascii=False),flush=True)
 for line in sys.stdin:
  command=json.loads(line)
  if 'drag' in command:
   start,end=command.pop('drag')
   result=subprocess.check_output([sys.executable,str(root/'tests/qa_v5_hud_drag.py'),'--display','localhost:'+os.environ.get('SC_QA_DISPLAY','245'),'--start',','.join(map(str,start)),'--end',','.join(map(str,end))],text=True)
   drag=json.loads(result)
   with open(root/os.environ.get('SC_QA_OUT','docs/qa/astra-native-regression')/'native-drag-events.jsonl','a') as log:log.write(result)
   response=send(command);response['drag']=drag
  else:response=send(command)
  print(json.dumps(response,ensure_ascii=False),flush=True)
  if command.get('quit'):break
finally:
 child.stdin.close()
 try:child.wait(timeout=15)
 except subprocess.TimeoutExpired:child.terminate();child.wait(timeout=5)
