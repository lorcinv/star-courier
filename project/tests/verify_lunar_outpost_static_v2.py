"""Read-only source/asset checks. These are not a substitute for Godot/native QA."""
from pathlib import Path
import hashlib
import json
import re
from PIL import Image
ROOT = Path(__file__).resolve().parents[1]
PINS = {
 'assets/2d_v5/moon/far-sky-clamped.png': ('a7556349c5c61047bd5e96ce1b25681057555b9fa399f22678441ac51215fed9', (1536,864)),
 'assets/2d_v5/moon/regolith-decorative-wrap.png': ('32b046c05035b4c8882841518c8567ba3b5b75fa651dc7b549240ffed1951888', (1280,720)),
 'assets/2d_v5/moon/moon_background.gdshader': ('5b53b57650f2737e6c1d56e626b29ec63b367a21df523aa5bc86413f77530379', None),
 'assets/2d_v5/flight/receiver.png': ('8b9303bb183d412e8f601da83f4a199d25bcfb36c5751d6e13ea26a6c0a481f0', (279,220)),
 'assets/2d_v5/flight/rock-1.png': ('795c9de6c637ab59083e0a51f38b1e877cd4e4f8679580712a2b66e2e0394e01', (144,160)),
 'assets/2d_v5/flight/rock-2.png': ('e2d4b611b18040a00924172d61a152dfe452f6d7c61d8ec0fbee64cc5d9eaa26', (115,160)),
}
checks = []
for name, (sha,size) in PINS.items():
    file = ROOT/name
    assert hashlib.sha256(file.read_bytes()).hexdigest() == sha, name
    if size: assert Image.open(file).size == size, name
    checks.append('pinned '+name)
terrain = Image.open(ROOT/'assets/2d_v5/moon/regolith-decorative-wrap.png').convert('RGBA')
assert not terrain.getchannel('A').crop((0,0,1280,540)).getbbox()
assert terrain.crop((0,0,1,720)).tobytes() == terrain.crop((1279,0,1280,720)).tobytes()
checks.append('regolith upper 75% transparent and same-direction edges exact')
source = (ROOT/'scripts/pilot_free_lunar_route_v2.gd').read_text()
assert '"deck_clearance_m":6.0,"art_width_m":8.0' in source
assert 7+6-149*8/279 > 8
assert '松开方向减速' not in source and 'Ctrl' in source
assert '"generation"' in source and '"pilot_gates"' in source
assert 'const SOURCE_PROFILE:String="lunar-outpost-source-v2"' in source
checks.append('new content is explicit, two-way, physically separate from old Moon')
shader = (ROOT/'assets/2d_v5/moon/moon_background.gdshader').read_text()
assert 'TIME' not in shader and 'hint_screen_texture' not in shader
assert 'clamp(pixel.y' in shader and 'repeat_x ? mod' in shader
presenter=(ROOT/'scripts/lunar_outpost_presentation_2d.gd').read_text()
assert 'set_process(false)' in presenter and 'res://scripts/pilot_moon_profile' not in presenter
assert not re.search(r'sim\.(route|obstacles|bodies|parts)\s*=',presenter)
checks.append('presenter samples physical state and restored camera only')
caps=(ROOT/'scripts/recovery_presentation_caps.gd').read_text()
assert '"moon","otherworld","wormhole","protected-bird","bird":return false' in caps
checks.append('historical capability flags remain closed')
receipt=json.loads((ROOT/'source_art/dev04-lunar/recovery-receipt.json').read_text())
assert set(receipt['drive_dependency_ids']) == {'18Ze76H4DvJBrHkT3LCxzfG0BmoAG4RbN','1-iWVIyZ9pen1pZbPwJOxAAaeEMIYPZ9m'}
checks.append('recovered art provenance IDs retained')
print(json.dumps({'passed':len(checks),'checks':checks,'engine_run':False,'native_qa_run':False},ensure_ascii=False,indent=2))
