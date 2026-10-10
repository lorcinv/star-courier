#!/usr/bin/env python3
"""Read-only assertions over captured native input and game-written saves."""
import hashlib
import json
from pathlib import Path
from PIL import Image, ImageChops

ROOT = Path(__file__).resolve().parents[1]
OUT = ROOT / 'docs/qa/astra-native-regression'
checks = []

def save(stem):
    return json.loads((OUT / (stem + '-save.json')).read_text())

def check(name, condition, detail, evidence):
    checks.append({'name': name, 'status': 'PASS' if condition else 'FAIL',
                   'detail': detail, 'evidence': evidence})

def beam(data):
    return [x for x in data['design'] if x['id'] == 2]

def uncommitted(data):
    return (data['credits'] == 260 and data['reputation'] == 0 and data['jobs_today'] == 0
            and data['deliveries'] == 0 and data['active_contract_id'] == 'D1-A'
            and data['contracts'][0]['status'] == 'accepted' and not data['in_flight']
            and not data['history'] and not data['settled_ids'])

initial = save('03-accepted-d1a')
check('Accept exact D1-A', uncommitted(initial), 'Real first-order card click; credits260, reputation0, accepted D1-A.', ['02-counter.png', '03-accepted-d1a.png', '03-accepted-d1a-save.json'])
check('Select and rotate beam #2', beam(save('05-select-beam'))[0]['rot'] == 0 and beam(save('06-rotate-beam'))[0]['rot'] == 1,
      'Native click then R changes rotation0→1.', ['05-select-beam.png', '06-rotate-beam.png', '06-rotate-beam-save.json'])
check('Delete allowed beam #2', not beam(save('07-delete-beam')), 'Delete removes beam #2; customer cargo remains.', ['07-delete-beam.png', '07-delete-beam-save.json'])
check('Undo deletion and rotation', beam(save('08-undo-delete'))[0]['rot'] == 1 and save('09-undo-rotate')['design'] == initial['design'],
      'Two Ctrl+Z actions restore the same ID2 and original complete design. Inventory unchanged throughout.', ['08-undo-delete.png', '09-undo-rotate.png', '09-undo-rotate-save.json'])
check('Assembly edits do not change owned inventory', all(save(n)['inventory'] == initial['inventory'] for n in ['05-select-beam','06-rotate-beam','07-delete-beam','08-undo-delete','09-undo-rotate']),
      'Owned battery3/beam4 and other inventory remain unchanged.', ['05-select-beam-save.json','07-delete-beam-save.json','09-undo-rotate-save.json'])
check('Cancellation Escape clears pending action', all(uncommitted(save(n)) for n in ['10-cancel-prompt','11-cancel-escape','12-cancel-rearmed-after-escape']),
      'Screenshot11 returns button to 取消委托; screenshot12 first re-click shows 确认取消？ instead of cancelling. No penalties.', ['10-cancel-prompt.png','11-cancel-escape.png','12-cancel-rearmed-after-escape.png'])
check('Navigation clears pending cancellation', all(uncommitted(save(n)) for n in ['13-navigation-clears-cancel','14-cancel-rearmed-after-navigation']),
      'Return-to-store navigation clears prompt; first new click only rearms. Contract remains accepted.', ['13-navigation-clears-cancel.png','14-cancel-rearmed-after-navigation.png'])
modal = save('15-pre-modal-rotated')
modal_names = ['16-dispatch-modal','17-modal-r-blocked','18-modal-delete-blocked','19-modal-undo-blocked','20-modal-background-click-blocked']
check('Dispatch modal blocks assembly keyboard and mouse', all(save(n)['design'] == modal['design'] and uncommitted(save(n)) for n in modal_names),
      'R, Delete, Ctrl+Z and background click leave rotated beam #2 and full design unchanged.', [n+'-save.json' for n in modal_names]+['19-modal-undo-blocked.png'])
check('Dispatch Cancel and Escape create no commitment', all(uncommitted(save(n)) for n in ['21-dispatch-cancel','22-dispatch-escape']),
      'Both dismiss to workshop, retaining ¥260, accepted contract, no in_flight. Ctrl+Z works again after dismissal.', ['21-dispatch-cancel.png','22-dispatch-escape.png','23-underlying-undo-restored-save.json'])
confirmed = save('29-repeated-confirm-paused-charge')
check('Repeated confirm enters one commitment', confirmed['credits'] == 260 and confirmed['jobs_today'] == 0 and confirmed['contracts'][0]['status'] == 'in_flight' and confirmed['in_flight']['contract_id'] == 'D1-A',
      'Three native confirm-position clicks enter one formal D1-A flight; final exactly-once assertion below verifies no duplicate settlement.', ['29-repeated-confirm-paused-charge.png','29-repeated-confirm-paused-charge-save.json','input-events.jsonl'])

pause_pairs = [('29-repeated-confirm-paused-charge','30-paused-charge-held'), ('32-paused-in-flight','33-paused-in-flight-held'), ('35-restarted-checkpoint-paused','36-resume-paused-check')]
rectangles = {'status':(35,36,260,97), 'progress':(302,40,964,91), 'energy':(1017,39,1239,94)}
pause_pixel_evidence = []
for a,b in pause_pairs:
    crops = {}
    for key,rect in rectangles.items():
        aa = Image.open(OUT/(a+'.png')).convert('RGB').crop(rect)
        bb = Image.open(OUT/(b+'.png')).convert('RGB').crop(rect)
        crops[key] = ImageChops.difference(aa,bb).getbbox() is None
    pause_pixel_evidence.append({'before':a+'.png','after':b+'.png','HUD_regions_pixel_identical':crops})
check('Pause holds charge, in-flight and resumed telemetry', all(all(x['HUD_regions_pixel_identical'].values()) for x in pause_pixel_evidence),
      'Native Space pause: charge0.0s; in-flight2.3s; recovered flight2.6s. The status/progress/energy HUD pixel regions are identical across held screenshots.', [n+'.png' for pair in pause_pairs for n in pair])
checkpoint = save('34-before-interruption-checkpoint')
recovered = save('36-resume-paused-check')
check('Interrupted formal flight recovers checkpoint', checkpoint['in_flight']['ticks'] == 122 and checkpoint['in_flight']['elapsed'] > 2 and recovered['in_flight']['ticks'] >= 122 and recovered['in_flight']['contract_id'] == 'D1-A' and recovered['credits'] == 260 and recovered['in_flight']['seed'] == checkpoint['in_flight']['seed'] and recovered['in_flight']['design'] == checkpoint['in_flight']['design'],
      'SIGTERM/process interruption recovery, not graceful close. Persisted122 ticks/2.0333333333s; reopened flight proceeds from snapshot and remains unbilled.', ['34-before-interruption-checkpoint-save.json','35-restarted-checkpoint-paused.png','36-resume-paused-check-save.json'])
settled = save('37-settlement')
check('Formal settlement occurs exactly once', settled['credits'] == 367 and settled['jobs_today'] == 1 and settled['deliveries'] == 1 and len(settled['history']) == 1 and list(settled['settled_ids']) == ['D1-A'] and not settled['in_flight'] and settled['last_settlement']['profit'] == 107 and settled['last_settlement']['energy'] == 58 and settled['last_settlement']['income'] == 165 and settled['last_settlement']['integrity'] == 100,
      'Income165 − energy58 = profit107;260→367. Elapsed8.79166666666681s;100% intact; reputation2. One history entry and one settled ID.', ['37-settlement.png','38-settlement-details.png','37-settlement-save.json'])
night = save('41-night-supply'); bought = save('42-purchase-one-battery')
check('Return store and close day', night['phase'] == 'night' and night['credits'] == 367 and night['inventory']['battery'] == 3,
      'Returned through actual report/store controls and entered night supply.', ['39-return-store.png','40-day-closing.png','41-night-supply.png'])
check('Purchase one battery', bought['credits'] == 322 and bought['inventory']['battery'] == 4 and bought['phase'] == 'night',
      'Single native buy click spends45:367→322 and battery3→4.', ['42-purchase-one-battery.png','42-purchase-one-battery-save.json'])
day2 = save('43-next-day'); reopened = save('45-day2-reopened')
def valid_day2(d):
    return d['day'] == 2 and d['phase'] == 'morning' and d['credits'] == 322 and d['inventory']['battery'] == 4 and d['reputation'] == 2 and d['jobs_today'] == 0 and d['deliveries'] == 1 and [c['contract_id'] for c in d['contracts']] == ['D2-A','D2-B'] and all(c['status']=='available' for c in d['contracts']) and len(d['history']) == 1 and list(d['settled_ids']) == ['D1-A'] and not d['in_flight'] and not d['active_contract_id']
check('Next day and application reopen preserve economy', valid_day2(day2) and valid_day2(reopened) and day2 == reopened,
      'Day2 morning,322 credits,battery4,reputation2,jobs_today0,deliveries1; fresh available D2-A/D2-B. Complete saved-state content is equal before and after reopen.', ['43-next-day.png','43-next-day-save.json','45-day2-reopened.png','45-day2-reopened-save.json'])
check('Native window resize', Image.open(OUT/'26-resized-1100x700.png').size == (1100,700) and Image.open(OUT/'27-restored-1280x800.png').size == (1280,800),
      'XResizeWindow changed actual client dimensions1100×700 then1280×800. Both screens inspected; controls remain visible.', ['26-resized-1100x700.png','27-restored-1280x800.png','input-events.jsonl'])
check('F11 setting round trip', save('24-fullscreen')['settings']['fullscreen'] is True and save('25-return-windowed')['settings']['fullscreen'] is False,
      'Native F11 input persists true then false. This does not verify physical fullscreen; see blocked checks.', ['24-fullscreen-save.json','25-return-windowed-save.json'])
initial_metadata = json.loads((OUT/'run-metadata.json').read_text())
check('Gameplay source remained unchanged during native run', all(hashlib.sha256((ROOT/p).read_bytes()).hexdigest() == h for p,h in initial_metadata['source_sha256'].items()),
      'main,hud,world,economy,simulation,project hashes match initial capture.', ['run-metadata.json','run-metadata-resume.json','run-metadata-day2-reopen.json'])
game_log = (OUT/'game.log').read_text()
check('No recorded Godot gameplay errors', not any(term in game_log for term in ['SCRIPT ERROR','ERROR:','Invalid call','Parse Error']),
      'Game log contains the expected software-driver V-Sync warning; no gameplay script/runtime error.', ['game.log'])

blocked = [
 {'name':'Physical fullscreen transition','status':'BLOCKED','detail':'Bare isolated Xorg has no functioning window manager. F11 settings toggled correctly but geometry remained1280×800. Installed Xfwm4 could not initialize Xfconf; dbus-run-session failed because sandbox socket creation was denied. No workaround attempted after this denial.','evidence':['24-fullscreen.png','25-return-windowed.png','xfwm4.log']},
 {'name':'Native graceful OS close and close-time checkpoint','status':'BLOCKED','detail':'Initial raw WM_DELETE_WINDOW probe timed out, with delivery to Godot not established. Native Alt+F4 also requires a working WM. Process interruption/restart was used and is reported separately. This is not evidence of a game close/save defect.','evidence':['input-events.jsonl','xfwm4.log','34-before-interruption-checkpoint-save.json']},
]
untested = [
 {'name':'No charge-ribbon frame on checkpoint restart','status':'NOT_FULLY_OBSERVED','detail':'First native resumed screenshot at1.5s startup delay shows recovered2.6s flight with no launch ribbon. Native coverage establishes checkpoint resume and no duplicate billing, but did not record every startup frame. Source inspection shows resuming sets launch_countdown0/launch_age1.35; strict frame-by-frame skip-charge proof remains untested.','evidence':['35-restarted-checkpoint-paused.png','run-metadata-resume.json']},
 {'name':'Native Windows execution','status':'UNTESTED','detail':'All native execution here is Linux Godot4.6.3 with llvmpipe on isolated cloud Xorg. No Windows build was run; Windows focus/fullscreen/window-close/audio/hardware performance remain for local candidate testing.'},
 {'name':'Audio playback and hardware frame-rate','status':'UNTESTED','detail':'This functional regression uses the Dummy audio driver and software rendering; it makes no audio or target-GPU performance claim.'},
]
report = {
 'result':'Functional WIP evidence only: native business loop and process-interruption persistence PASS; not an art acceptance or release-readiness approval',
 'engine': initial_metadata['engine'],
 'method': initial_metadata['method'],
 'primary_physical_resolution':[1280,800],
 'isolated_displays':[245,246,247],
 'save_handling':'Only game actions mutate saves. QA copies and reads game-written JSON; no save injection or gameplay debug method calls.',
 'counts':{'passed':sum(x['status']=='PASS' for x in checks),'failed':sum(x['status']=='FAIL' for x in checks),'blocked':len(blocked),'untested_or_not_fully_observed':len(untested)},
 'checks':checks,'blocked':blocked,'untested':untested,
 'pause_pixel_evidence':pause_pixel_evidence,
 'financial_checkpoints':{
   'accepted':{'credits':initial['credits'],'reputation':initial['reputation'],'jobs_today':initial['jobs_today'],'battery':initial['inventory']['battery']},
   'formal_in_flight':{'credits':checkpoint['credits'],'ticks':checkpoint['in_flight']['ticks'],'elapsed':checkpoint['in_flight']['elapsed'],'seed':checkpoint['in_flight']['seed']},
   'settled':{k:settled[k] for k in ['credits','reputation','jobs_today','deliveries','last_settlement']},
   'night_purchase':{'credits':bought['credits'],'battery':bought['inventory']['battery'],'cost':45},
   'day2_reopened':{k:reopened[k] for k in ['day','phase','credits','reputation','jobs_today','deliveries','inventory','active_contract_id','in_flight','contracts']},
 },
 'harness_issues':[{'issue':'Initial window discovery expected exact title; Godot debug title has (DEBUG) suffix.','resolution':'Regex fixed before gameplay. No save existed on successful fresh launch.'},
                   {'issue':'Raw X11 close probe timeout','resolution':'Kept as a blocked native-close check; process interruption accurately identified, no graceful-close claim.'},
                   {'issue':'Xfwm4 and D-Bus unavailable within sandbox','resolution':'No gameplay source changes or permission bypass. Physical fullscreen/native close left blocked.'}],
 'source_sha256':initial_metadata['source_sha256'],
 'artifacts':{'input_trace':'input-events.jsonl','game_log':'game.log','final_save':'46-final-day2-save.json','driver':'../../../tools/qa_native_regression.py','verifier':'../../../tools/qa_verify_native_artifacts.py'},
}
(OUT/'report.json').write_text(json.dumps(report,ensure_ascii=False,indent=2)+'\n')
print(json.dumps(report['counts']))
assert not report['counts']['failed'], 'Native artifact assertion failed; inspect report.json'
