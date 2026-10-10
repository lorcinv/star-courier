#!/usr/bin/env python3
"""Higher-density alternatives rebuilt from the unchanged 1672x941 original.

Uses the previously reviewed project-native grid and palette functions. See the
parent study's MIT attribution files. This never resamples the 640x360 output to
produce a higher logical resolution and never modifies prior study artifacts.
"""
from pathlib import Path
import hashlib
import importlib.util
import json

import numpy as np
from PIL import Image, ImageDraw, ImageFont

ROOT=Path(__file__).resolve().parent
PREVIOUS=ROOT.parent
spec=importlib.util.spec_from_file_location('pixel_study',PREVIOUS/'study_reference.py')
study=importlib.util.module_from_spec(spec);spec.loader.exec_module(study)
SOURCE=study.SOURCE
FONT='/usr/share/fonts/opentype/noto/NotoSansCJK-Regular.ttc'
FONT_BOLD='/usr/share/fonts/opentype/noto/NotoSansCJK-Bold.ttc'


def sha(path):return hashlib.sha256(path.read_bytes()).hexdigest()


def caption(im,xy,string,size=22,fill='#e8eef7',bold=False):
    ImageDraw.Draw(im).text(xy,string,font=ImageFont.truetype(FONT_BOLD if bold else FONT,size,index=2),fill=fill)


def palette_from_previous():
    p=json.loads((PREVIOUS/'palette_96.json').read_text())
    return np.array([[int(hx[i:i+2],16) for i in (1,3,5)] for hx in p['colors']],dtype=np.uint8)


def original_box_in_4k(box):
    return tuple(round(v*(3840/1672 if i%2==0 else 2160/941)) for i,v in enumerate(box))


def compare(original,versions):
    # All detail panels below are direct crops of equal 3840x2160 display
    # canvases, pasted at 1:1. Their size, content bounds and scale are identical.
    cards=[('原图 1672×941','未做网格清理',original.resize((3840,2160),Image.Resampling.NEAREST))]
    cards += [('旧版 640×360','96 色 · 4K 每像素 6×6',Image.open(PREVIOUS/'clean_96c_640x360_4k_nearest6x.png').convert('RGB'))]
    cards += [('新版 960×540','相同 96 色 · 4K 每像素 4×4',versions[(960,540)])]
    cards += [('新版 1280×720','相同 96 色 · 4K 每像素 3×3',versions[(1280,720)])]
    colw,gap,margin=360,20,24
    width=margin*2+4*colw+3*gap
    c=Image.new('RGB',(width,1265),'#10192b')
    caption(c,(24,18),'提高真实像素密度',34,bold=True)
    caption(c,(24,65),'新版均从原图重新采样；局部为相同范围、相同显示尺寸。',22,fill='#9caec5')
    for i,(title,subtitle,im) in enumerate(cards):
        x=margin+i*(colw+gap)
        caption(c,(x,115),title,25,bold=True)
        caption(c,(x,153),subtitle,18,fill='#adbed2')
        c.paste(im.resize((360,203),Image.Resampling.NEAREST),(x,190))
    caption(c,(24,420),'店员脸部：看眼睛、嘴形和发梢',24,bold=True)
    face_box=original_box_in_4k((273,350,419,515))
    for i,(_,_,im) in enumerate(cards):
        crop=im.crop(face_box);x=margin+i*(colw+gap)+(colw-crop.width)//2
        c.paste(crop,(x,465))
    caption(c,(24,863),'飞船前舱：看轮廓、窗框和亮边',24,bold=True)
    craft_box=original_box_in_4k((972,345,1128,486))
    for i,(_,_,im) in enumerate(cards):
        crop=im.crop(craft_box);x=margin+i*(colw+gap)+(colw-crop.width)//2
        c.paste(crop,(x,908))
    caption(c,(24,1235),'此图比较密度，三个清理版本共用同一套 96 色，避免色差干扰判断。',18,fill='#adbed2')
    c.save(ROOT/'像素密度对比_原图_640_960_1280.png')


def main():
    assert sha(SOURCE)==study.SOURCE_HASH
    prior={str(p.relative_to(PREVIOUS)):sha(p) for p in PREVIOUS.iterdir() if p.is_file()}
    original=Image.open(SOURCE).convert('RGB');rgb=np.array(original)
    palette=palette_from_previous()
    report={'source':str(SOURCE),'source_sha256':study.SOURCE_HASH,
            'source_size':[1672,941],'higher_density_built_from_original':True,
            'palette':'unchanged previous 96-color palette for fair density comparison',
            'dither':'none','variants':{},'previous_files_unchanged':False}
    versions={}
    for wh in [(960,540),(1280,720)]:
        w,h=wh
        base,cuts=study.grid_medoid(rgb,wh)
        Image.fromarray(base).save(ROOT/f'grid_only_{w}x{h}.png')
        (ROOT/f'grid_only_{w}x{h}_source_cuts.json').write_text(json.dumps(cuts)+'\n')
        out=study.map_palette(base,palette)
        im=Image.fromarray(out);im.save(ROOT/f'clean_96c_{w}x{h}.png')
        scale=3840//w
        large=im.resize((3840,2160),Image.Resampling.NEAREST)
        large.save(ROOT/f'clean_96c_{w}x{h}_4k_nearest{scale}x.png')
        assert np.array_equal(np.array(large),np.repeat(np.repeat(out,scale,axis=0),scale,axis=1))
        versions[wh]=large
        report['variants'][f'{w}x{h}']={'logical_size':list(wh),'4k_size':[3840,2160],
            'scale':scale,'constant_square_pixel_blocks':True,
            'colors_used':len(np.unique(out.reshape(-1,3),axis=0)),
            'source_cell_widths':np.unique(np.diff(cuts['columns'])).tolist(),
            'source_cell_heights':np.unique(np.diff(cuts['rows'])).tolist()}
    compare(original,versions)
    assert sha(SOURCE)==study.SOURCE_HASH
    current={str(p.relative_to(PREVIOUS)):sha(p) for p in PREVIOUS.iterdir() if p.is_file()}
    assert prior==current
    report['previous_files_unchanged']=True
    (ROOT/'density_metrics.json').write_text(json.dumps(report,indent=2)+'\n')
    print(json.dumps(report,indent=2))


if __name__=='__main__':main()
