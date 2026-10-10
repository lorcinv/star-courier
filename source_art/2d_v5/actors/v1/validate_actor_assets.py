from pathlib import Path
from PIL import Image
import hashlib,json,numpy as np
HERE=Path(__file__).resolve().parent
ROOT=HERE.parents[2]
m=json.loads((HERE/'actor-manifest.json').read_text())
palette={tuple(bytes.fromhex(c[1:])) for c in json.loads((ROOT/m['palette']).read_text())['colors']}
report={'passed':True,'actors':{},'checks':['Original SHA256 matches manifest and tool output','Common frame dimensions and foot registration per actor','Strict binary alpha','Every opaque RGB is in approved reference96 palette','Transparent margin on every edge','No full-body clipping']}
for actor,a in m['actors'].items():
 checks={}
 for pose,v in a['poses'].items():
  orig=ROOT/v['original'];runtime=ROOT/v['runtime'];default=ROOT.parent/'generated_images'/v['generation_output_filename']
  sha=lambda p:hashlib.sha256(p.read_bytes()).hexdigest()
  assert sha(orig)==v['original_sha256']
  assert default.exists() and sha(default)==sha(orig)
  im=Image.open(runtime).convert('RGBA');arr=np.asarray(im)
  assert tuple(im.size)==tuple(a['shared_canvas'])
  assert v['foot_anchor']==a['foot_anchor']
  assert set(np.unique(arr[:,:,3])).issubset({0,255})
  colors={tuple(c) for c in arr[arr[:,:,3]>0][:,:3]}
  assert colors.issubset(palette)
  b=im.getchannel('A').getbbox();assert b[0]>0 and b[1]>0 and b[2]<im.width and b[3]<im.height
  checks[pose]={'runtime':str(runtime.relative_to(ROOT)),'size':im.size,'alpha_bounds':b,'opaque_colors':len(colors),'original_sha256_verified':True,'source_default_copy_matches':True}
 report['actors'][actor]=checks
(HERE/'validation.json').write_text(json.dumps(report,indent=2)+'\n')
print(json.dumps(report,indent=2))
