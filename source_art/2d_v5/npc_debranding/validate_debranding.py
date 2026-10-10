#!/usr/bin/env python3
"""Verifies bounded NPC paint corrections without claiming engine integration."""
from pathlib import Path
from PIL import Image
import numpy as np,json,hashlib
ROOT=Path(__file__).resolve().parents[3];H=Path(__file__).resolve().parent
P=json.loads((H/'provenance.json').read_text());B=json.loads((H/'before-sha256.json').read_text());checks=[]
def check(ok,msg):
 assert ok,msg
 checks.append(msg)
sha=lambda p:hashlib.sha256(p.read_bytes()).hexdigest()
for record in P['sources']:
 original=ROOT/record['original'];edited=ROOT/record['edit'];registered=ROOT/record['registered_source']
 check(sha(original)==record['original_sha256'],record['key']+' original preserved')
 check(sha(edited)==record['edit_sha256'],record['key']+' built-in output preserved')
 check(sha(registered)==record['registered_sha256'],record['key']+' registered source SHA')
 a=np.array(Image.open(original).convert('RGBA'));b=np.array(Image.open(registered).convert('RGBA'));mask=np.zeros(a.shape[:2],bool)
 for x1,y1,x2,y2 in record['replacement_regions_xyxy']:mask[y1:y2,x1:x2]=True
 check(np.array_equal(a[:,:,3],b[:,:,3]),record['key']+' original alpha exact')
 check(np.array_equal(a[~mask],b[~mask]),record['key']+' all non-logo pixels exact')
changed=set(P['runtime_changes'])
for path,expected in B.items():
 p=ROOT/path
 if path not in changed:check(sha(p)==expected,path+' unchanged SHA')
 if path.startswith('assets/2d_v5/npcs') and path in changed:
  a=np.array(Image.open(H/'before-runtime'/path).convert('RGBA'));b=np.array(Image.open(p).convert('RGBA'))
  check(a.shape==b.shape,path+' original dimensions')
  check(np.array_equal(a[:,:,3],b[:,:,3]),path+' original alpha exact')
  if '/portraits/' in path:check(np.array_equal(a[:300],b[:300]),path+' face area exact')
  if path.endswith(('idle-pixel.png','handoff-pixel.png')):check(np.array_equal(a[:80],b[:80]),path+' head area exact')
parcel=json.loads((H/'parcel-provenance.json').read_text());p=ROOT/parcel['runtime'];a=np.array(Image.open(p));pal={tuple(int(c[i:i+2],16) for i in (1,3,5)) for c in json.loads((ROOT/'source_art/pixel_pipeline_studies/palette_96.json').read_text())['colors']}
check(sha(p)==parcel['sha256'],'neutral parcel SHA');check(list(Image.open(p).size)==[66,45],'neutral parcel dimensions');check(set(np.unique(a[:,:,3]))<={0,255},'neutral parcel binary alpha');check({tuple(x) for x in a[a[:,:,3]>0,:3]}<=pal,'neutral parcel shared96');check(np.all(a[a[:,:,3]==0,:3]==0),'neutral parcel transparent RGB zero')
result={'status':'pass','checks_passed':len(checks),'scope':'Original-preservation, bounded-imagegen edits, alpha/face invariants and parcel technical checks. No engine integration claim.','checks':checks};(H/'validation.json').write_text(json.dumps(result,indent=2)+'\n');print('PASS:',len(checks),'debranding checks')
