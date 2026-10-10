#!/usr/bin/env python3
"""Technical contact sheet matching the runtime's existing-raster composites."""
from PIL import Image,ImageDraw
from pathlib import Path
import json
ROOT=Path(__file__).resolve().parents[4]
m=json.loads((ROOT/'assets/2d_v5/npcs/walk_exit/motion-manifest.json').read_text());npc=json.loads((ROOT/'assets/2d_v5/npcs/npc-manifest.json').read_text())
board=Image.new('RGBA',(220*6,295*6),(22,31,51,255));draw=ImageDraw.Draw(board);row=0
for id in ['elf_archivist','alien_botanist','robot_machinist']:
 for aid,a in npc['appearances'][id]['accessory_options'].items():
  records=m['actors'][id]['walk']+[m['actors'][id]['gestures']['farewell'],m['actors'][id]['gestures']['neutral']]
  for col,r in enumerate(records):
   desired_right=col==4
   body=Image.open(ROOT/r['runtime']).convert('RGBA');acc=Image.open(ROOT/a['runtime']).convert('RGBA')
   flip=desired_right!=(r['facing']=='right');aflip=not desired_right
   foot=r['foot_anchor'];hip=r['hip_anchor'];local=a['local_anchor']
   f=[body.width-foot[0] if flip else foot[0],foot[1]];h=[body.width-hip[0] if flip else hip[0],hip[1]]
   if flip:body=body.transpose(Image.Transpose.FLIP_LEFT_RIGHT)
   if aflip:acc=acc.transpose(Image.Transpose.FLIP_LEFT_RIGHT)
   al=[acc.width-local[0] if aflip else local[0],local[1]]
   px=col*220+110-f[0];py=row*295+260-f[1]
   board.alpha_composite(body,(round(px),round(py)));board.alpha_composite(acc,(round(px+h[0]-al[0]),round(py+h[1]-al[1])))
   draw.text((col*220+5,row*295+8),id+' / '+aid,fill='white')
   draw.text((col*220+5,row*295+269),r.get('id',str(col)),fill='white')
  row+=1
board.convert('RGB').save(ROOT/'source_art/2d_v5/actors/cooperative/customer-accessory-review.png')
