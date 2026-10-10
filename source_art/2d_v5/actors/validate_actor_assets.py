from pathlib import Path
from PIL import Image
import hashlib,json,numpy as np
HERE=Path(__file__).resolve().parent;ROOT=HERE.parents[2];m=json.loads((ROOT/'assets/2d_v5/actors/actor-manifest.json').read_text());assert m['version']==2
sha=lambda p:hashlib.sha256(p.read_bytes()).hexdigest()
palette={tuple(bytes.fromhex(c[1:]))for c in json.loads((ROOT/m['palette']).read_text())['colors']}
v1=json.loads((HERE/'v1/actor-manifest.json').read_text())
for pose,source in m['sources'].items():
 path=ROOT/source['path'];assert sha(path)==source['sha256'];assert sha(ROOT.parent/'generated_images'/source['tool_output_filename'])==sha(path)
for actor,a in m['actors'].items():
 assert a['shared_canvas']==v1['actors'][actor]['shared_canvas'];assert a['foot_anchor']==v1['actors'][actor]['foot_anchor']
 for pose,p in a['poses'].items():
  path=ROOT/p['runtime'];assert sha(path)==p['runtime_sha256'];im=Image.open(path).convert('RGBA');arr=np.array(im)
  assert tuple(im.size)==tuple(a['shared_canvas']);assert set(np.unique(arr[:,:,3]))=={0,255}
  colors={tuple(c)for c in arr[arr[:,:,3]>0][:,:3]};assert colors.issubset(palette)
  b=im.getchannel('A').getbbox();assert list(b)==p['runtime_alpha_bounds'];assert b[0]>0 and b[1]>0 and b[2]<im.width and b[3]<im.height
for actor,a in v1['actors'].items():
 for pose,p in a['poses'].items():
  assert sha(HERE/'v1'/Path(p['original']).name)==p['original_sha256']
  assert sha(HERE/'v1/runtime-snapshot'/Path(p['runtime']).name)==p['runtime_sha256']
print('V2 runtime verified: imagegen originals unchanged; V1 preserved; shared canvas/anchors; binary alpha; reference96 palette; transparent margins; manifest hashes.')
