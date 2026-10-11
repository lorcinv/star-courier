"""Portable, no-window reproduction of the FG01 pure pose evidence."""
from pathlib import Path
import argparse,datetime,hashlib,json,os,subprocess,sys
ap=argparse.ArgumentParser();ap.add_argument('--godot',required=True);ap.add_argument('--out');ap.add_argument('--suite',choices=['edges','baseline','candidate','candidate-replay','focus','c1r1'],default='edges')
args=ap.parse_args();project=Path(__file__).resolve().parents[1]
out=Path(args.out).resolve() if args.out else project/'.qa'/datetime.datetime.now(datetime.timezone.utc).strftime('%Y%m%dT%H%M%S%fZ')
out.mkdir(parents=True,exist_ok=True);env=os.environ.copy()
for key in ['APPDATA','LOCALAPPDATA','XDG_DATA_HOME','XDG_CONFIG_HOME','XDG_CACHE_HOME']:
 d=out/'engine_data'/key;d.mkdir(parents=True,exist_ok=True);env[key]=str(d)
flags={'creationflags':subprocess.CREATE_NO_WINDOW} if os.name=='nt' else {}
version=subprocess.run([args.godot,'--headless','--version'],capture_output=True,text=True,env=env,check=True,**flags).stdout.strip()
if not version.startswith('4.6.3.'):raise SystemExit('Expected Godot 4.6.3: '+version)
script='res://tests/test_edges.gd' if args.suite=='edges' else 'res://tests/trace_pose.gd'
command=[args.godot,'--headless','--path',str(project),'--log-file',str(out/(args.suite+'.engine.log')),'--script',script]
if args.suite!='edges':command+=['--',str(out/(args.suite+'.jsonl')),args.suite]
r=subprocess.run(command,capture_output=True,text=True,encoding='utf-8',errors='replace',env=env,timeout=180,**flags)
(out/(args.suite+'.stdout.log')).write_text(r.stdout,encoding='utf-8');(out/(args.suite+'.stderr.log')).write_text(r.stderr,encoding='utf-8')
manifest={'engine':version,'command':command,'returncode':r.returncode,'script_error':'SCRIPT ERROR' in r.stderr or 'ERROR:' in r.stderr,'files':{str(f.relative_to(project)).replace('\\','/'):hashlib.sha256(f.read_bytes()).hexdigest() for folder in ['scripts','tests','contract'] for f in (project/folder).glob('*') if f.is_file()}}
(out/(args.suite+'.execution.json')).write_text(json.dumps(manifest,indent=2),encoding='utf-8')
print(r.stdout,end='');print(r.stderr,end='',file=sys.stderr)
sys.exit(r.returncode or (1 if manifest['script_error'] else 0))
