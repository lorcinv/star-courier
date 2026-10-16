#!/usr/bin/env python3
"""Engine-free source guard. It does not claim runtime, render, or native passes."""
from pathlib import Path
import argparse, hashlib, json, re
parser=argparse.ArgumentParser()
parser.add_argument('--baseline', type=Path, required=True)
args=parser.parse_args()
project=Path(__file__).resolve().parents[1]
base=args.baseline.resolve()
def source(root,name): return (root/'scripts'/name).read_text()
def function(code,name):
    match=re.search(r'^(?:static )?func '+re.escape(name)+r'\(.*?(?=^(?:static )?func |\Z)',code,re.M|re.S)
    assert match,name
    lines=match.group(0).splitlines()
    while lines and (not lines[-1].strip() or lines[-1].startswith("#")): lines.pop()
    return "\n".join(lines)
def check(ok,label):
    if not ok: raise AssertionError(label)
    print('PASS',label)
old_policy=source(base,'workshop_parts_v2.gd');policy=source(project,'workshop_parts_v2.gd')
old_view=function(source(base,'world_view_2d.gd'),'show_design');view=function(source(project,'world_view_2d.gd'),'show_design')
old_ready=function(old_policy,'readiness');ready=function(policy,'readiness')
check('=="splitter":' in old_view and 'in ["splitter","coupler","accelerator"]' not in old_view,'OLD FAILURE baseline has no accelerator/coupler target preview')
check('if kind=="accelerator":result.text="装配就绪：Q / 手柄 Y' in old_ready,'OLD FAILURE baseline keyboard claim ignores saved external accelerator source')
check('弹出货舱会断开供电' not in old_ready,'OLD FAILURE baseline has no free-v2 cargo ejection risk')
check('in ["splitter","coupler","accelerator"]' in view and 'grid.tool_target_cells.append' in view and 'grid.tool_selected_target=Vector2(target.x,target.y)' in view,'new tools use exact existing target-cell and selected-cell projection')
check('(int(item.get("target",-1))<0 or int(item.target)==int(target.id))' in view,'fallback actual neighbor keeps warning color instead of valid yellow')
for name in ['target_options','effective_target']:
    check(function(source(project,'workshop_parts_v1.gd'),name)==function(policy,name),'world v1 and inspector v2 '+name+' have identical frozen projections')
for name in ['new_part','target_options','effective_target','component_ids','trigger_text','local_controls','convenience_source']:
    check(function(old_policy,name)==function(policy,name),name+' stays byte-identical, including defaults, target choices and fallback')
check('if source==-2 else "装配就绪：等待原控制信号，弹出高亮零件' in ready,'accelerator readiness now branches on actual saved trigger')
check('if pilot and version=="pilot-free-v2" and str(target.get("type",""))=="cargo":' in ready,'cargo warning requires explicit free-v2 pilot craft context')
check(ready.index('if not battery:') < ready.index('if kind=="accelerator":\n') and ready.index('if source>=0 and not source in ids:') < ready.index('if kind=="accelerator":\n'),'existing power/source failures precede positive and risk copy')
hud=source(project,'game_hud.gd')
check('WorkshopParts.readiness(part,parts,_pilot_mode(),launcher,version)' in hud and 'CORAL if not bool(readiness.ready) else YELLOW if bool(readiness.get("warning",false)) else TEAL' in hud,'actual HUD passes version and separates warning from blocked/ready color')
check(function(source(base,'game_hud.gd'),'_part_target')==function(hud,'_part_target'),'dropdown, target-edit action and invalid placeholder stay exact')
allowed={'scripts/main.gd','scripts/workshop_parts_v2.gd','scripts/world_view_2d.gd','scripts/game_hud.gd'}
new_tests={'tests/test_mechanical_target_scope_dev05.gd','tests/test_mechanical_target_feedback_dev05.gd','tests/test_mechanical_target_hud_dev05.gd','tests/test_mechanical_target_persistence_dev05.gd','tests/verify_mechanical_target_source_dev05.py'}
def files(root):
    return {str(p.relative_to(root)):hashlib.sha256(p.read_bytes()).hexdigest() for p in root.rglob('*') if p.is_file() and '.godot' not in p.parts and '__pycache__' not in p.parts and p.suffix not in {'.uid','.pyc'}}
a,b=files(base),files(project)
changed={n for n in a if n in b and a[n]!=b[n]}
check(changed==allowed,'only the four owned presentation/context scripts changed')
check(set(a)<=set(b) and set(b)-set(a)==new_tests,'no deleted source or unrelated new files')
check(all(a[n]==b[n] for n in a if n.startswith('scripts/') and n not in allowed),'all solvers, energy, input, migration and save scripts remain byte-identical')
main=source(project,'main.gd')
check(main.count('world.set_meta("assembly_context",assembly_mode)')==2,'Main render and immediate target redraw explicitly hand over assembly context')
normalized=main.replace(' world.set_meta("assembly_context",assembly_mode)\n','').replace(';world.set_meta("assembly_context",assembly_mode);',';')
check(normalized==source(base,'main.gd'),'Main differs only by two presentation-context handoffs')
check('str(get_meta("assembly_context","craft"))=="craft"' in view,'world defaults existing callers to craft and excludes launcher target cues')
manifest=project.parent/'evidence'/'source_before.json' 
check(json.loads(manifest.read_text())==a,'source lane still matches its frozen pre-edit snapshot')
print('MECHANICAL_TARGET_SOURCE_DEV05 PASS engine=NOT_RUN native_visual=NOT_RUN')
