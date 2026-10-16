#!/usr/bin/env python3
"""Automated native XTest business-day acceptance gate; never human-play evidence.
All gameplay changes come from real OS pointer/keyboard events. The offline
simulator only prepares macros and audits read-only game-written checkpoints.
"""
import json,math,os,pathlib,sys,time
ROOT=pathlib.Path(__file__).resolve().parents[1]
sys.path.insert(0,str(ROOT/'tools'))
from capture_native_pilot_delivery import NativePilotCapture
checks=[]
def check(test,condition,detail=None):
 row={'test':test,'passed':bool(condition),'detail':detail};checks.append(row)
 print(json.dumps(row,ensure_ascii=False),flush=True)
 if not condition:raise AssertionError(test)

def ledger(state):return {k:state[k] for k in ['credits','day','deliveries','jobs_today','reputation','history','settled_ids','active_contract_id','in_flight']}

def bill(c,name,result,contract):
 state=result['state'];receipt=state['settled_ids'][contract]
 snapshot=json.load(open(result['last_input_checkpoint']))['in_flight']
 reference=c.reference({'snapshot':snapshot,'mode':'replay'},name+'-bill-audit')
 expected=math.ceil(reference['energy_used']*.18)
 check(name+' exact timeline elapsed',abs(reference['elapsed']-receipt['elapsed'])<1e-8,{'native':receipt['elapsed'],'replay':reference['elapsed']})
 check(name+' exact energy bill',receipt['energy']==expected,{'joules':reference['energy_used'],'bill':receipt['energy'],'expected':expected})
 expected_profit=receipt['income']-expected-sum(receipt[k] for k in ['ammo','repairs','lost'])
 check(name+' exact net profit',receipt['profit']==expected_profit,receipt)
 check(name+' successful intact deadline',receipt['success'] and receipt['integrity']==100 and receipt['elapsed']<receipt['deadline'])
 check(name+' one launch impulse',sum('完成压缩供能' in x for x in reference['events'])==1,reference['events'])
 return receipt

c=NativePilotCapture()
try:
 check('fresh save',c.ready['state']=={'saved':False})
 c.send({'click':[90,715],'shot':'02-counter'})
 c.send({'actions':[{'click':[1010,523]},{'click':[270,715]},{'click':[1135,713]}],'shot':'03-confirmation','snapshot':'03-before-confirm'})
 before=json.load(open(c.out/'03-before-confirm-save.json'))
 c.send({'actions':[{'key':'Return'},{'key':'Return'},{'click':[1135,713]},{'key':'Escape'},{'click':[1223,83]},{'key':'Escape'}],'shot':'04-confirm-cancel-guards','snapshot':'04-after-guards'})
 after=json.load(open(c.out/'04-after-guards-save.json'))
 check('repeat-confirm and cancel guards preserve ledger',before==after)
 c.send({'click':[1135,713]})
 c.deliver({'name':'05-standard-a-launch','reference':{'weight':1.0,'seed':100,'boost_end_tick':240},'stop_at':8.5,'seconds':16,'repeat_launch':True})
 t=time.monotonic()
 closed=c.send({'close':True,'snapshot':'06-graceful-close','state':True,'sleep':0})
 check('native WM_DELETE graceful exit',not closed['running'],{'wall_seconds':time.monotonic()-t})
 snapshot=closed['state']['in_flight'];ticks=snapshot['ticks']
 check('close persisted current paused checkpoint',500<=ticks<=530,{'ticks':ticks,'elapsed':snapshot['elapsed']})
 c.send({'start':5,'shot':'07-resumed-paused','snapshot':'07-resumed-paused','sleep':1})
 first=json.load(open(c.out/'07-resumed-paused-save.json'))
 c.send({'sleep':1.2,'snapshot':'08-paused-stable','shot':'08-paused-stable'})
 second=json.load(open(c.out/'08-paused-stable-save.json'))
 check('restart remains paused and exact checkpoint unchanged',first['in_flight']==snapshot and second['in_flight']==snapshot)
 a=c.deliver({'name':'09-standard-a-resumed','reference':{'snapshot':snapshot},'resume':'p','seconds':27})
 receipt_a=bill(c,'standard-a',a,'D1-A')
 check('A settled once',len(a['state']['history'])==1 and a['state']['jobs_today']==1 and a['state']['deliveries']==1 and a['state']['credits']==260+receipt_a['profit'])
 c.send({'actions':[{'click':[800,688]},{'click':[800,688]}],'shot':'10-next-contract-guard','snapshot':'10-after-repeat-receipt'})
 check('repeat receipt actions cannot settle A again',ledger(json.load(open(c.out/'10-after-repeat-receipt-save.json')))==ledger(a['state']))
 # Native inspected coordinates: a completed receipt's next-contract button
 # opens the sole available order card. Its accept button remains at y523.
 c.send({'click':[1010,523],'shot':'11-heavy-accepted','snapshot':'11-heavy-accepted','state':True})
 state=c.send({'state':True,'sleep':0})['state']
 check('heavy order accepted',state['active_contract_id']=='D1-B',state['active_contract_id'])
 c.send({'actions':[{'click':[270,715]},{'click':[1135,713]}],'shot':'12-heavy-confirmation'})
 b=c.deliver({'name':'13-heavy-b','seconds':36})
 receipt_b=bill(c,'heavy-b',b,'D1-B')
 state=b['state']
 check('two unique settlements and exact credits',set(state['settled_ids'])=={'D1-A','D1-B'} and len(state['history'])==2 and state['jobs_today']==2 and state['deliveries']==2 and state['credits']==260+receipt_a['profit']+receipt_b['profit'])
 c.send({'click':[450,688],'shot':'14-return-hub'})
 c.send({'click':[440,715],'shot':'15-close-day'})
 c.send({'click':[1030,700],'shot':'16-night-supply','snapshot':'16-night'})
 night=c.send({'state':True,'sleep':0})['state'];check('closed day enters night',night['phase']=='night')
 c.send({'click':[1190,285],'shot':'17-night-purchase','snapshot':'17-after-purchase'})
 purchased=c.send({'state':True,'sleep':0})['state']
 diffs={k:purchased['inventory'].get(k,0)-v for k,v in night['inventory'].items() if purchased['inventory'].get(k,0)!=v}
 check('one paid night purchase',diffs=={'battery':1} and purchased['credits']==night['credits']-45,{'inventory_difference':diffs,'charge':night['credits']-purchased['credits']})
 c.send({'click':[1030,700],'shot':'18-next-day','snapshot':'18-next-day'})
 next_day=c.send({'state':True,'sleep':0})['state']
 check('next day has two fresh orders and reset quota',next_day['day']==2 and next_day['jobs_today']==0 and next_day['phase']=='morning' and {x['contract_id'] for x in next_day['contracts']}=={'D2-A','D2-B'})
 c.send({'close':True,'snapshot':'19-final-close'})
 c.send({'start':5,'shot':'20-final-restart','snapshot':'20-final-restart'})
 final=c.send({'state':True,'sleep':0})['state']
 check('restart does not duplicate settlement or purchase',ledger(final)==ledger(next_day) and final['inventory']==next_day['inventory'])
 c.send({'finish_record':True,'sleep':0})
 c.send({'close':True,'quit':True,'sleep':0})
finally:
 c.close()
 (c.out/'validation-summary.json').write_text(json.dumps({'method':'automated native XTest; read-only offline replay audit','engine_fps_claim':False,'human_play_claim':False,'checks':checks},ensure_ascii=False,indent=2)+'\n')
