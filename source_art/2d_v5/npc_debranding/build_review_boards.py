#!/usr/bin/env python3
"""Technical review composition only; none of these labels/backdrops enter game assets."""
from pathlib import Path
from PIL import Image,ImageDraw,ImageFont
import json
R=Path(__file__).resolve().parents[3];H=Path(__file__).resolve().parent;N=H/'staged-runtime/assets/2d_v5/npcs'
if not N.exists():N=R/'assets/2d_v5/npcs'
m=json.loads((N/'npc-manifest.json').read_text());font=ImageFont.truetype('/usr/share/fonts/truetype/dejavu/DejaVuSans.ttf',20);small=ImageFont.truetype('/usr/share/fonts/truetype/dejavu/DejaVuSans.ttf',16)
for id in ['human_courier','elf_archivist','alien_botanist','robot_machinist']:
 board=Image.new('RGB',(1556,560),(18,28,52));d=ImageDraw.Draw(board);d.text((12,9),id+' / native 512px portraits',font=font,fill='#ffe6b0')
 for i,e in enumerate(['neutral','pleased','concerned']):
  p=R/f'assets/2d_v5/dialogue/human_courier-{e}.png' if id=='human_courier' else N/id/'portraits'/f'{e}.png';im=Image.open(p);assert im.size==(512,512);board.paste(im,(10+i*512,40),im)
 board.save(H/'proofs'/f'{id}-portraits-native512.png')
board=Image.new('RGB',(1060,1050),(18,28,52));d=ImageDraw.Draw(board)
for row,(id,r) in enumerate(m['appearances'].items()):
 y=10+row*345;d.text((12,y),id+' / all accessories / native world scale',font=font,fill='#ffe6b0')
 for ai,(aid,info) in enumerate(r['accessory_options'].items()):
  for pi,pose in enumerate(['idle','handoff']):
   x=12+(ai*2+pi)*255;im=Image.open(N/id/f'{pose}--{aid}-preview.png');board.paste(im,(x,y+42),im);d.text((x,y+304),pose+' / '+aid,font=small,fill='#92c6e9')
board.save(H/'proofs/all-accessory-variants-native.png')
bg=Image.open(R/'assets/2d_v5/environment/shop-shell.png').convert('RGBA').resize((1280,720),Image.Resampling.NEAREST);board=Image.new('RGB',(1280,800),(18,28,52));board.paste(bg,(0,50));d=ImageDraw.Draw(board);d.text((16,12),'Compositing audit: native sprite scale on existing shop background (not engine screenshot)',font=font,fill='#ffe6b0')
for i,id in enumerate(['human_courier','elf_archivist','alien_botanist','robot_machinist']):
 p=R/'assets/2d_v5/actors/customer-idle-pixel.png' if id=='human_courier' else N/id/f'idle--{m["appearances"][id]["default_accessory"]}-preview.png';im=Image.open(p);x=130+i*290;board.paste(im,(x,292),im);d.text((x,774),id,font=small,fill='#92c6e9')
board.save(H/'proofs/shop-background-compositing.png')
box=Image.open(N/'shared/customer-parcel-neutral-pixel.png');proof=Image.new('RGB',(610,260),(18,28,52));d=ImageDraw.Draw(proof);d.text((12,10),'Neutral customer parcel: native 66x45 / 4x nearest',font=font,fill='#ffe6b0');proof.paste(box,(30,85),box);z=box.resize((264,180),Image.Resampling.NEAREST);proof.paste(z,(280,60),z);proof.save(H/'proofs/customer-parcel-neutral-proof.png')
print('Native portraits, all accessories, shop composite and neutral parcel proof regenerated')
