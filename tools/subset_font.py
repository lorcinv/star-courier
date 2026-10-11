#!/usr/bin/env python3
"""Build the game's renamed OFL font subset from Noto Sans CJK SC.
Usage: python tools/subset_font.py /path/to/NotoSansCJK-Regular.ttc
For a TTC, collection index 2 is Simplified Chinese. Requires fonttools.
The game has no arbitrary user-authored text field. This keeps every literal
in scripts plus ASCII, punctuation, arrows and common technical symbols.
"""
from pathlib import Path
import sys
from fontTools import subset
from fontTools.ttLib import TTFont
root=Path(__file__).resolve().parents[1]
source=Path(sys.argv[1])
# Preserve source timestamps so identical text/source bytes give identical subsets.
font=TTFont(source,fontNumber=2 if source.suffix.lower()=='.ttc' else -1,recalcTimestamp=False)
codepoints=set(range(0x20,0x7F))
for first,last in [(0x2000,0x2070),(0x2190,0x2300),(0x25A0,0x2600),(0x3000,0x3040),(0xFF00,0xFFF0)]:
 codepoints.update(range(first,last))
for path in (root/'scripts').glob('*.gd'):
 codepoints.update(ord(c) for c in path.read_text(encoding='utf-8'))
options=subset.Options()
options.name_IDs=['*'];options.name_legacy=True;options.name_languages=['*']
options.layout_features=['*'];options.notdef_glyph=True;options.notdef_outline=True;options.recommended_glyphs=True
sub=subset.Subsetter(options=options);sub.populate(unicodes=codepoints);sub.subset(font)
for record in font['name'].names:
 if record.nameID in (1,3,4,6,16):
  text='StarCourierSans-Regular' if record.nameID in (3,6) else 'Star Courier Sans'
  record.string=text.encode(record.getEncoding(),errors='replace')
if 'CFF ' in font:
 cff=font['CFF '].cff;cff.fontNames=['StarCourierSans-Regular']
 for top in cff.topDictIndex:
  top.FullName='Star Courier Sans';top.FamilyName='Star Courier Sans'
font.save(root/'assets/fonts/ChineseSans.otf')
print('Subset glyphs:',len(font.getBestCmap()),'bytes:',(root/'assets/fonts/ChineseSans.otf').stat().st_size)
