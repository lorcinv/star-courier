#!/usr/bin/env python3
"""Independent output checks for the bounded pixel conversion study."""
import hashlib
import json
from pathlib import Path

import numpy as np
from PIL import Image

ROOT=Path(__file__).resolve().parent
SOURCE=ROOT.parent/'art_direction_v4/pixel-cel-shop-reference-03.png'
EXPECTED='bd9388bd6cb6784572cabd0eca876bb6fce9a6d7c538438128d22d8367242cae'


def main():
    checks=[]
    def check(name,passed,detail=None):
        checks.append({'name':name,'passed':bool(passed),'detail':detail})
        assert passed, name
    check('approved original unchanged', hashlib.sha256(SOURCE.read_bytes()).hexdigest()==EXPECTED)
    rgb=np.array(Image.open(SOURCE).convert('RGB'))
    for w,h in [(640,360),(560,315),(480,270)]:
        a=np.array(Image.open(ROOT/f'grid_only_{w}x{h}.png').convert('RGB'))
        check(f'logical {w}x{h} dimensions',a.shape==(h,w,3))
        cuts=json.loads((ROOT/f'grid_only_{w}x{h}_source_cuts.json').read_text())
        xs,ys=np.array(cuts['columns']),np.array(cuts['rows'])
        check(f'{w}x{h} source cuts monotonic and exhaustive',
              (xs[0],ys[0],xs[-1],ys[-1])==(0,0,1672,941) and
              len(xs)==w+1 and len(ys)==h+1 and
              np.min(np.diff(xs))>0 and np.min(np.diff(ys))>0,
              {'source_cell_widths':np.unique(np.diff(xs)).tolist(),
               'source_cell_heights':np.unique(np.diff(ys)).tolist()})
        # Check every logical cell contains one of its own actual source colors.
        match=np.zeros((h,w),bool)
        for dy in range(int(np.max(np.diff(ys)))):
            for dx in range(int(np.max(np.diff(xs)))):
                gx,gy=xs[:-1]+dx,ys[:-1]+dy
                valid=(gy<ys[1:])[:,None] & (gx<xs[1:])[None,:]
                sample=rgb[np.minimum(gy,940)[:,None],np.minimum(gx,1671)[None,:]]
                match|=valid & np.all(sample==a,axis=2)
        check(f'{w}x{h} only existing pixel colors from each cell',match.all())
    for n in [96,64,16]:
        data=json.loads((ROOT/f'palette_{n}.json').read_text())
        palette={tuple(bytes.fromhex(c[1:])) for c in data['colors']}
        small=np.array(Image.open(ROOT/f'clean_{n}c_640x360.png').convert('RGB'))
        used={tuple(x) for x in np.unique(small.reshape(-1,3),axis=0)}
        check(f'{n}-color exact palette membership',used<=palette,{'colors_used':len(used),'palette_size':len(palette)})
        if n!=16:
            large=np.array(Image.open(ROOT/f'clean_{n}c_640x360_4k_nearest6x.png').convert('RGB'))
            check(f'{n}-color 4K dimensions',large.shape==(2160,3840,3))
            check(f'{n}-color uniform exact 6x6 blocks',np.array_equal(large,np.repeat(np.repeat(small,6,axis=0),6,axis=1)))
            check(f'{n}-color 4K contains no added colors',len(np.unique(large.reshape(-1,3),axis=0))==len(used))
    out={'checks':checks,'passed':len(checks),'failed':0,
         'not_tested':['Upstream Rust executable parity (no external executable installed)',
                       'Complete realtime Godot temporal stability suite; limited horizontal GPU evidence is independently recounted in runtime_independent_recount.json',
                       'User acceptance of the alternative palette study'],
         'source_sha256':EXPECTED}
    (ROOT/'validation_results.json').write_text(json.dumps(out,indent=2)+'\n')
    print(json.dumps(out,indent=2))


if __name__=='__main__':main()
