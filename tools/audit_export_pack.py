#!/usr/bin/env python3
"""Read-only Godot 4 PCK / embedded Windows EXE inventory with integrity checks.
Usage: python3 audit_pack.py FILE --output report.json [--project IMMUTABLE_EXPORT_SOURCE]
No executable is run. Uses Godot 4.6.3 PCK v2/v3 layout; rejects encryption/patch bundles.
"""
import argparse,fnmatch,hashlib,json,re,struct
from pathlib import Path
POLICY=Path(__file__).with_name('runtime-policy.json')
def audit(path,project=None):
 data=Path(path).read_bytes();size=len(data)
 def unpack(fmt,at):
  assert 0<=at and at+struct.calcsize(fmt)<=size,('truncated',at,fmt)
  return struct.unpack_from(fmt,data,at)
 pe=None
 if data[:2]==b'MZ':
  peoff,=unpack('<I',0x3c);assert data[peoff:peoff+4]==b'PE\0\0','invalid PE signature'
  machine,=unpack('<H',peoff+4);optional,=unpack('<H',peoff+24)
  assert machine==0x8664 and optional==0x20b,('not PE32+ AMD64',machine,optional)
  pe={'machine':'AMD64','optional_header':'PE32+'}
 if data[:4]==b'GDPC':start=0
 else:
  assert data[-4:]==b'GDPC','no embedded-PCK trailer (signed EXE needs PE-section reader)'
  packsize,=unpack('<Q',size-12);start=size-12-packsize
  assert data[start:start+4]==b'GDPC',('bad embedded PCK start',start)
 version,major,minor,patch,flags=unpack('<5I',start+4)
 assert version in (2,3),('unsupported PCK version',version)
 assert not flags&~2,('encrypted/sparse/unknown pack flags',flags)
 base,=unpack('<Q',start+24)
 if version==3 or flags&2:base+=start
 if version==3:
  d,=unpack('<Q',start+32);cursor=start+d
 else:cursor=start+96
 count,=unpack('<I',cursor);cursor+=4
 entries={}
 for i in range(count):
  plen,=unpack('<I',cursor);cursor+=4
  assert 0<plen<65536,('path length',plen)
  name=data[cursor:cursor+plen].rstrip(b'\0').decode('utf8').removeprefix('res://');cursor+=plen
  offset,length=unpack('<QQ',cursor);cursor+=16
  md5=data[cursor:cursor+16];cursor+=16
  ff,=unpack('<I',cursor);cursor+=4
  assert ff==0,('unsupported encrypted/removal/delta entry',name,ff)
  assert name not in entries and not name.startswith('/') and '..' not in Path(name).parts,('unsafe/duplicate entry',name)
  absolute=base+offset
  assert 0<=absolute<=size and absolute+length<=size,('entry bounds',name)
  payload=data[absolute:absolute+length]
  assert hashlib.md5(payload).digest()==md5,('MD5 mismatch',name)
  entries[name]={'size':length,'sha256':hashlib.sha256(payload).hexdigest(),'offset':absolute}
 policy=json.loads(POLICY.read_text());failures=[]
 for name in entries:
  source_name=name.removesuffix('.remap').removesuffix('.import')
  if source_name.endswith('.gdc'):source_name=source_name[:-1]
  if any(fnmatch.fnmatchcase(source_name,p) for p in policy['exclude_filters']):failures.append('forbidden entry: '+name)
  if name.startswith(('.git/','.runtime/','.godot/editor/')) or '/__pycache__/' in name or name.endswith(('.pyc','.blend','.blend1','.glb')):failures.append('source/cache/3D entry: '+name)
 # Imported runtime files under .godot/imported and .godot/exported are necessary.
 remap_targets=set()
 for name,row in entries.items():
  if name.endswith(('.import','.remap')):
   text=data[row['offset']:row['offset']+row['size']].decode('utf8')
   for target in re.findall(r'"res://([^"\n]+)"',text):
    if target.startswith('.godot/') or target.endswith(('.gdc','.ctex','.res','.scn')):
     if target not in entries:failures.append('missing remapped payload: '+target+' via '+name)
     remap_targets.add(target)
 for name in entries:
  if name.startswith(('.godot/imported/','.godot/exported/')) and name not in remap_targets:failures.append('orphan imported/exported payload: '+name)
 if project:
  root=Path(project)
  for name in policy['required_manifests']+['licenses/Godot-MIT.txt','licenses/NotoSansCJK.txt','assets/fonts/NOTICE.txt']:
   if name not in entries:failures.append('missing required raw file: '+name);continue
   if hashlib.sha256((root/name).read_bytes()).hexdigest()!=entries[name]['sha256']:failures.append('source/pack mismatch: '+name)
  def expected(name):
   return not any(fnmatch.fnmatchcase(name,p) for p in policy['exclude_filters'])
  # all_resources must retain every asset in the accepted runtime folders;
  # paths listed only in JSON cannot be recovered from scene dependencies.
  for folder in ['assets/2d_v5','assets/audio','assets/fonts','assets/icons']:
   for f in (root/folder).rglob('*'):
    name=f.relative_to(root).as_posix()
    if f.is_file() and f.suffix in ('.png','.ogg','.wav','.otf','.gdshader') and expected(name):
     if not any(candidate in entries for candidate in [name,name+'.import',name+'.remap']):failures.append('missing runtime resource: '+name)
  for f in (root/'scripts').glob('*.gd'):
   name=f.relative_to(root).as_posix()
   if expected(name) and not any(n in entries for n in [name,name+'.remap',name+'c']):failures.append('missing runtime script: '+name)
  # Manifest-contained runtime asset paths must resolve through remaps/imports.
  def walk(value):
   if isinstance(value,dict):
    for v in value.values():yield from walk(v)
   elif isinstance(value,list):
    for v in value:yield from walk(v)
   elif isinstance(value,str) and value.startswith(('res://assets/','assets/')):yield value.removeprefix('res://')
  for manifest in policy['required_manifests']:
   for name in walk(json.loads((root/manifest).read_text())):
    if not any(n in entries for n in [name,name+'.import',name+'.remap']):failures.append('unresolved manifest resource: '+name)
 return {'artifact':str(Path(path).resolve()),'size':size,'sha256':hashlib.sha256(data).hexdigest(),'pe':pe,'pack_start':start,'pack_format':version,'engine':[major,minor,patch],'entry_count':count,'failures':sorted(set(failures)),'entries':entries,'limitations':'Inventory/integrity only. No native Windows execution or gameplay claim.'}
if __name__=='__main__':
 ap=argparse.ArgumentParser();ap.add_argument('artifact');ap.add_argument('--project');ap.add_argument('--output',required=True);args=ap.parse_args()
 report=audit(args.artifact,args.project);Path(args.output).write_text(json.dumps(report,indent=2)+'\n')
 print(json.dumps({k:v for k,v in report.items() if k!='entries'},indent=2))
 raise SystemExit(bool(report['failures']))
