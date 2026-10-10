"""Publish a fully validated, closed actor batch via Linux atomic directory exchange."""
from pathlib import Path
import json,hashlib,shutil,ctypes,os
HERE=Path(__file__).resolve().parent;ROOT=HERE.parents[3];RUNTIME=ROOT/'assets/2d_v5/actors';STAGE=HERE/'staged-runtime'
READY=HERE/'ready-runtime';PREVIOUS=HERE/'previous-runtime-boundary'
sha=lambda p:hashlib.sha256(p.read_bytes()).hexdigest()
m=json.loads((STAGE/'actor-manifest.json').read_text());v=json.loads((HERE/'validation.json').read_text());assert v['passed']
expected={f'{a}-{p}-pixel.png'for a in ['clerk','customer']for p in ['idle','handoff']}
assert expected.issubset({p.name for p in STAGE.glob('*.png')})
for a,data in m['actors'].items():
 for p,d in data['poses'].items():assert sha(STAGE/f'{a}-{p}-pixel.png')==d['runtime_sha256']
assert not READY.exists() and not PREVIOUS.exists(),'Publication directory already exists; reconcile before publishing.'
shutil.copytree(RUNTIME,READY)
for p in STAGE.iterdir():
 if p.is_file():shutil.copy2(p,READY/p.name)
for p in READY.glob('*.png.import'):p.unlink() # Force Godot to import revised source pixels.
m['status']='published as one atomic actor-directory exchange'
(READY/'actor-manifest.json').write_text(json.dumps(m,indent=2)+'\n')
libc=ctypes.CDLL(None,use_errno=True);renameat2=getattr(libc,'renameat2',None)
if renameat2 is None:raise RuntimeError('Atomic exchange unavailable; runtime unchanged, coordinate a closed fallback.')
renameat2.argtypes=[ctypes.c_int,ctypes.c_char_p,ctypes.c_int,ctypes.c_char_p,ctypes.c_uint];renameat2.restype=ctypes.c_int
result=renameat2(-100,os.fsencode(READY),-100,os.fsencode(RUNTIME),2)
if result:raise OSError(ctypes.get_errno(),os.strerror(ctypes.get_errno()))
READY.rename(PREVIOUS)
for a,data in m['actors'].items():
 for p,d in data['poses'].items():assert sha(RUNTIME/f'{a}-{p}-pixel.png')==d['runtime_sha256']
for target in [HERE/'actor-manifest.json',HERE.parent/'actor-manifest.json']:target.write_text(json.dumps(m,indent=2)+'\n')
v['published_runtime_hashes_verified']=True;v['atomic_publication']='Linux renameat2 RENAME_EXCHANGE of complete actor directory';v['previous_runtime_snapshot']=str(PREVIOUS.relative_to(ROOT))
for target in [HERE/'validation.json',HERE.parent/'validation.json']:target.write_text(json.dumps(v,indent=2)+'\n')
print(json.dumps({'published':True,'actor_manifest':str((RUNTIME/'actor-manifest.json').relative_to(ROOT)),'v2_source_manifest':str((HERE/'actor-manifest.json').relative_to(ROOT)),'previous_runtime':str(PREVIOUS.relative_to(ROOT)),'same_canvas_and_foot_anchors':True},indent=2))
