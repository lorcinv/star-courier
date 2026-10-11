#!/usr/bin/env python3
"""Read-only provenance and resource-closure audit. Writes only beside this file."""
from pathlib import Path
import re, json, hashlib
from collections import Counter, defaultdict
ROOT=Path('/workspace/scratch/445d2872ecf6')
OUT=ROOT/'recovery/asset-audit'
B=ROOT/'recovery/git-e6121c0'
N=ROOT/'recovery/unpacked/StarCourier-491aaff-ground-traffic-code/source'
F=ROOT/'recovery/unpacked/StarCourier-clerk-fullbody-FG01-source'
C=ROOT/'recovery/unpacked/StarCourier-Clerk-FG01-C2-small-review'
sha=lambda p:hashlib.sha256(p.read_bytes()).hexdigest()
files=lambda r:{str(p.relative_to(r)):p for p in r.rglob('*') if p.is_file()}
b,n,f,c=map(files,[B,N,F,C])
cp_path='docs/checkpoints/seeded-meteor-human-20261010.json'
cp=json.loads(n[cp_path].read_text()); hashes=cp['source_sha256']
support=json.loads(n['tools/aggregate_source_support.json'].read_text())
def save(name,x): (OUT/name).write_text(json.dumps(x,ensure_ascii=False,indent=2)+'\n')
def classify(path,expected=None):
 found=[]
 for label,fs in [('newer_source',n),('old_baseline',b),('FG01',f)]:
  if path in fs:found.append({'input':label,'path':str(fs[path].relative_to(ROOT)),'sha256':sha(fs[path]),'bytes':fs[path].stat().st_size})
 if expected:
  matches=[q for q in found if q['sha256']==expected]
  status='available_exact_checkpoint' if matches else 'available_old_same_path_hash_mismatch' if found else 'missing_asset'
 else:status='available_old_same_path_version_unverified' if found else 'missing_asset'
 return {'path':path,'status':status,'expected_sha256':expected,'copies':found}
delta={'newer_commit':'491aaffa4241fe1e09bdbb665e5316ba08cdff63','newer_tree':'2ca12fd7552cc7437685f887e8cd0d6cd1f1a838','old_tree':'0e29974828fbbd102731329d8473361af3bdae97','old_count':len(b),'newer_subset_count':len(n),'added':[],'modified':[],'identical':[],'old_only_omitted_not_deleted':sorted(b.keys()-n.keys())}
for path in sorted(n):
 record={'path':path,'newer_sha256':sha(n[path])}
 if path not in b:delta['added'].append(record)
 else:
  record['old_sha256']=sha(b[path]);delta['identical' if record['old_sha256']==record['newer_sha256'] else 'modified'].append(record)
delta['counts']={k:len(delta[k]) for k in ['added','modified','identical','old_only_omitted_not_deleted']}
save('source-path-delta.json',delta)
checks=[]
for root,prefix in [(N.parent,'source'),(F,'')]:
 manifest=json.loads((root/'SOURCE-MANIFEST.json').read_text()); bad=[]
 for r in manifest['files']:
  p=root/prefix/r['path']
  if not p.is_file() or sha(p)!=r['sha256']:bad.append(r['path'])
 checks.append({'manifest':str((root/'SOURCE-MANIFEST.json').relative_to(ROOT)),'files':len(manifest['files']),'failures':bad})
save('input-verification.json',checks)
# Exact current source dependency graph: main scene and project settings.
reachable=set();edges={};todo=['project.godot','scenes/main.tscn']
while todo:
 path=todo.pop()
 if path in reachable:continue
 reachable.add(path)
 if path not in n:continue
 deps=re.findall(r'["\']res://([^"\'\n]+)["\']',n[path].read_text())
 edges[path]=deps
 for dep in deps:
  if dep in n and (dep.startswith('scripts/') or dep.startswith('scenes/')):todo.append(dep)
save('runtime-source-graph.json',{'reachable':sorted(reachable),'edges':edges})
# Resource inventory: broad immutable checkpoint inventory PLUS precisely expanded
# current runtime paths. A checkpoint inventory is NOT a claim of active reachability.
assets={p:classify(p,h) for p,h in hashes.items() if p.startswith('assets/')}
for p,r in assets.items():r['evidence']=[cp_path+'#/source_sha256/'+p];r['runtime_reasons']=[]
def add(p,reason):
 p=p.removeprefix('res://')
 if p not in assets:
  assets[p]=classify(p,hashes.get(p));assets[p]['evidence']=[];assets[p]['runtime_reasons']=[]
 if reason not in assets[p]['runtime_reasons']:assets[p]['runtime_reasons'].append(reason)
for src,deps in edges.items():
 for p in deps:
  if p.startswith('assets/') and re.search(r'\.(png|json|gdshader|otf|ogg|wav|svg)$',p) and '%' not in p:add(p,'literal:'+src)
# Dynamic world texture policy and bounded part catalog, preserving -pixel preference.
def world_texture(name,reason):
 if name=='modules/joint':name='modules/cohesion/joint-collar-pixel'
 elif name=='modules/coupler':name='modules/cohesion/coupler-latch-pixel'
 elif name.startswith(('actors/','modules/')):
  if 'assets/2d_v5/'+name+'-pixel.png' in b:name+='-pixel'
  elif name.startswith('actors/') and 'assets/2d_v5/'+name+'-native.png' in b:name+='-native'
 add('assets/2d_v5/'+name+'.png',reason)
world=n['scripts/world_view_2d.gd'].read_text()
for name in set(re.findall(r'"((?:environment|flight|props|space|launch-support|npcs|modules)/[\w/-]+)"',world)):
 if name.endswith(('/', '-')):continue
 world_texture(name,'dynamic world sprite id')
for name in ['investigation/black-marble-pixel','workshop/right-bay-tier1-open-pixel','workshop/right-bay-tier2-open-pixel','flight/rock-1','flight/rock-2']:
 world_texture(name,'bounded world/route constant')
partids=set(re.findall(r'"([a-z_]+)": _part\(',n['scripts/parts.gd'].read_text()))|{'cargo','drill','joint'}
for name in sorted(partids):world_texture('modules/'+name,'parts catalog and world texture policy')
for actor in ['clerk','customer']:
 for pose in ['idle','handoff']:world_texture('actors/'+actor+'-'+pose,'actor helper / actor_metadata compatibility')
for pose in ['idle','carry-parcel','offer-parcel','carry-part','offer-part','alert','carry-empty','offer-empty','turn-front','lift-shaft','lift-joint','lift-claw']:
 add('assets/2d_v5/robot/'+pose+'.png','assembly_2d bounded POSES / arm pieces')
for actor in ['clerk','human_courier']:
 emotions=['neutral','pleased','concerned']+(['curious','surprised','warm_smile'] if actor=='clerk' else [])
 for emotion in emotions:add('assets/2d_v5/dialogue/'+actor+'-'+emotion+'.png','dialogue/courier_stories bounded portraits')
for actor in ['elf_archivist','alien_botanist','robot_machinist']:
 for emotion in ['neutral','pleased','concerned']:add('assets/2d_v5/npcs/'+actor+'/portraits/'+emotion+'.png','courier_stories bounded portraits')
for name in ['meteor','fragment-a','fragment-b']:add('assets/2d_v5/events/meteor/'+name+'.png','orbital_meteor_presentation bounded name list')
add('assets/2d_v5/events/meteor/manifest.json','orbital_meteor_presentation raw JSON')
for sound in ['ui_select','delivery_success','warning','launch']:add('assets/audio/'+sound+'.wav','main._sound bounded call sites')
# Existing raw JSONs: recurse exact authored references; distinguish obsolete same-path
# actor/NPC data from fully hash-matching preserved motion/rig metadata.
raw_paths=[
 'assets/2d_v5/actors/actor-manifest.json',
 'assets/2d_v5/npcs/npc-manifest.json',
 'assets/2d_v5/actors/cooperative/motion-manifest.json',
 'assets/2d_v5/npcs/walk_exit/motion-manifest.json',
 'assets/2d_v5/actors/single_walk_v1/single-walk-registration.json',
 'assets/2d_v5/actors/rig_motion_v1/rig-registration.json',
 'assets/2d_v5/actors/human_rig_motion_v1/rig-registration.json',
 'assets/2d_v5/events/meteor/manifest.json']
dynamic_edges=[]
def strings(o,loc=()):
 if isinstance(o,dict):
  for k,v in o.items():yield from strings(v,loc+(str(k),))
 elif isinstance(o,list):
  for k,v in enumerate(o):yield from strings(v,loc+(str(k),))
 elif isinstance(o,str):yield loc,o
for p in raw_paths:
 add(p,'runtime raw JSON read')
 available=f.get(p,b.get(p))
 if not available:continue
 for loc,value in strings(json.loads(available.read_text())):
  if value.startswith('assets/') and value.endswith(('.png','.json')):
   # Current clerk subclass substitutes the single-walk record; legacy clerk
   # walk/run references in cooperative JSON are recovery evidence, not loaded.
   active=not (p.endswith('cooperative/motion-manifest.json') and len(loc)>2 and loc[2] in ('walk','run'))
   dynamic_edges.append({'manifest':p,'field':'.'.join(loc),'target':value,'readable_manifest_status':assets[p]['status'],'current_clerk_override_excludes':not active})
   if active:add(value,'manifest:'+p+'#'+'.'.join(loc))
# Missing JSON bodies prevent exact field enumeration; checkpoint names preserve
# the full single-walk and human-rig target sets without inventing filenames.
for p in hashes:
 if p.startswith(('assets/2d_v5/actors/single_walk_v1/','assets/2d_v5/actors/human_rig_motion_v1/')):add(p,'checkpoint-known manifest target; actual registration bytes missing')
 if '/neutral-idle-pixel.png' in p or '/neutral-front-arm-pixel.png' in p or p.endswith('/customer-neutral-idle-pixel.png'):add(p,'newer neutral appearance contract + checkpoint exact path')
# Current source preloads all three protected-bird PNGs after this earlier checkpoint.
# Their paths were collected via the source graph above.
save('dynamic-manifest-edges.json',dynamic_edges)
save('runtime-raw-json.json',[assets[p] for p in raw_paths])
save('asset-inventory.json',{'scope':'All 473 historical checkpoint asset entries plus currently resolved runtime paths. Exact refers to Oct 10 checkpoint SHA, not undocumented 491aaff art revision. Runtime reasons identify active/static and conservative manifest-derived dependencies. Missing registration JSONs prevent an unconditional complete dynamic closure claim.','counts':dict(Counter(r['status'] for r in assets.values())),'assets':[assets[p] for p in sorted(assets)]})
save('known-runtime-assets.json',{'scope':'Explicit load paths and hand-expanded bounded dynamic paths plus checkpoint-known targets of unavailable manifests; excludes unused historical checkpoint assets. Old actor/NPC manifests are obsolete and their edges are annotated. No Godot/runnable claim.','counts':dict(Counter(r['status'] for r in assets.values() if r['runtime_reasons'])),'assets':[assets[p] for p in sorted(assets) if assets[p]['runtime_reasons']]})
# Exact checkpoint missing/mismatched assets, retain all names even where historical.
save('missing-assets.json',[assets[p] for p in sorted(assets) if assets[p]['status']=='missing_asset'])
save('wrong-version-assets.json',[assets[p] for p in sorted(assets) if assets[p]['status']=='available_old_same_path_hash_mismatch'])
# Aggregate-required originals carry their own exact hashes.
support_records=[]
for r in support['files']:
 rec=classify(r['path'],r['sha256']);rec['consumers']=r['consumers'];support_records.append(rec)
save('aggregate-source-support-audit.json',{'counts':dict(Counter(r['status'] for r in support_records)),'files':support_records})
# Source/editable references exactly written in preserved records. Do not guess
# names beneath missing source directories or use candidate metadata as approved.
source_refs=defaultdict(list)
for label,fs in [('newer_source',n),('FG01',f)]:
 for path,full in fs.items():
  if full.suffix not in ('.gd','.py','.json','.md','.txt','.sh'):continue
  try:text=full.read_text()
  except UnicodeDecodeError:continue
  for ref in re.findall(r'(?:res://)?source_art/[\w./-]+',text):
   ref=ref.removeprefix('res://')
   if ref.endswith('.') and not ref.endswith('..'):ref=ref[:-1]
   source_refs[ref].append(label+':'+path)
# Include original/recipe references carried in recovered runtime registrations.
for p in raw_paths:
 available=f.get(p,b.get(p))
 if available:
  for loc,value in strings(json.loads(available.read_text())):
   if value.startswith('source_art/'):source_refs[value].append(p+'#'+'.'.join(loc))
originals=[]
for p,refs in sorted(source_refs.items()):
 if Path(p).suffix not in ['.png','.py','.json','.txt','.md','.blend','.ttf','.ttc','.otf']:continue
 r=classify(p,next((x['sha256'] for x in support['files'] if x['path']==p),None));r['references']=sorted(set(refs));
 r['kind']='original_image' if p.endswith('.png') else 'source_recipe_or_metadata' if p.endswith(('.py','.json')) else 'source_support_or_evidence'
 if r['status']=='missing_asset':r['status']='missing_editable_original' if r['kind']=='original_image' else 'missing_source_support'
 originals.append(r)
save('source-originals-and-recipes.json',{'note':'Exact paths only; absent newer recipes mean this is a known lower bound, not a complete authoring closure. Original font input is supplied by CLI; repo-relative location is unknown.','counts':dict(Counter(r['status'] for r in originals)),'files':originals})
# File-hash discovery across every preserved recovered input, allowing an exact
# matching asset at a different path without guessing/renaming it in production.
needed={r['expected_sha256'] for r in assets.values() if r['status'] in ('missing_asset','available_old_same_path_hash_mismatch') and r['expected_sha256']}
byhash=defaultdict(list)
for root in [B,ROOT/'recovery/unpacked']:
 for q in root.rglob('*'):
  if q.is_file() and q.suffix.lower() in ('.png','.json','.otf','.gdshader'):
   h=sha(q)
   if h in needed:byhash[h].append(str(q.relative_to(ROOT)))
save('alternate-path-hash-search.json',{'wanted_hashes':len(needed),'matches':dict(byhash)})
# Font coverage audit reads current old OTF and newer source text only.
font_report={}
try:
 from fontTools.ttLib import TTFont
 font=TTFont(b['assets/fonts/ChineseSans.otf']);cm=font.getBestCmap()
 wanted={ord(ch) for p,q in n.items() if p.startswith('scripts/') and p.endswith('.gd') for ch in q.read_text() if ord(ch)>127 and not ch.isspace()}
 missing=sorted(wanted-set(cm));font_report={'newer_script_count':sum(p.startswith('scripts/') and p.endswith('.gd') for p in n),'non_ascii_non_whitespace_codepoints':len(wanted),'old_font_codepoints':len(cm),'missing_count':len(missing),'missing_characters':''.join(map(chr,missing)),'missing_codepoints':['U+%04X'%c for c in missing],'source_input':'NotoSansCJK-Regular.ttc (CLI argument; no repository-local original found)','subset_recipe':'tools/subset_font.py'}
except Exception as e:font_report={'error':str(e)}
save('font-coverage.json',font_report)
summary={'source_delta':delta['counts'],'checkpoint_assets':dict(Counter(classify(p,h)['status'] for p,h in hashes.items() if p.startswith('assets/'))),'known_asset_inventory':dict(Counter(r['status'] for r in assets.values())),'known_runtime_inventory':dict(Counter(r['status'] for r in assets.values() if r['runtime_reasons'])),'source_support':dict(Counter(r['status'] for r in support_records)),'originals':dict(Counter(r['status'] for r in originals)),'reachable_source_files':len(reachable),'raw_json_dependencies':len(raw_paths),'FG01_assets':sum(p.startswith('assets/') for p in f),'alternate_path_hash_matches':len(byhash),'font_missing':font_report.get('missing_count')}
save('summary.json',summary);print(json.dumps(summary,indent=2))
