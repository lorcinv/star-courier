from pathlib import Path
import sys,json,math,hashlib,collections
ROOT=Path(__file__).resolve().parents[1]
DATA=json.loads((ROOT/'contract/candidate-rig-registration-fg01.json').read_text(encoding='utf-8'))
def sub(a,b):return [a[0]-b[0],a[1]-b[1]]
def add(a,b):return [a[0]+b[0],a[1]+b[1]]
def mul(a,k):return [a[0]*k,a[1]*k]
def norm(a):return math.hypot(*a)
def rot(a,t):return [a[0]*math.cos(t)-a[1]*math.sin(t),a[0]*math.sin(t)+a[1]*math.cos(t)]
def finite(v):
 if isinstance(v,(int,float)):return math.isfinite(v)
 if isinstance(v,dict):return all(finite(x) for x in v.values())
 if isinstance(v,list):return all(finite(x) for x in v)
 return True
def upper(p,s):
 if 'upper_body' in p:return p['upper_body']
 sign=1 if p['facing_right'] else -1;pivot=add(p['hip'],p['shoulder_offset'])
 offsets={side:DATA['parts'][side+'_arm']['attachment_offset'] for side in ['near','far']}
 return {'pelvis_world_angle':0,'torso_world_angle':0,'head_world_angle':p['head_angle']*sign,'torso_pivot_world':pivot,'neck_world':add(pivot,mul([DATA['parts']['head']['attachment_offset'][0]*sign,DATA['parts']['head']['attachment_offset'][1]],s)),'shoulder_world':{k:add(pivot,mul([v[0]*sign,v[1]],s)) for k,v in offsets.items()},'arm_world_angle':{'near':p['arm_angle']*sign,'far':-p['arm_angle']*sign},'head_scale':s}
def fresh():
 return {'samples':0,'max':{},'min':{},'violations':collections.Counter(),'worst':{},'first_failures':{},'landing_count':collections.Counter(),'stop_entry_phase':None}
def maximum(m,k,v,row,context=None):
 if v>m['max'].get(k,-math.inf):m['max'][k]=v;m['worst'][k]={'tick':row['tick'],'clock':row['clock'],'value':v,'context':context}
def minimum(m,k,v):m['min'][k]=min(v,m['min'].get(k,math.inf))
def fail(m,k,row,detail):
 m['violations'][k]+=1
 if k not in m['first_failures']:m['first_failures'][k]={'row':row,'detail':detail}
def analyze(path):
 cases={};previous={};stop_start={};fail_rows={}
 for line in path.open(encoding='utf-8'):
  row=json.loads(line);p=row['pose'];r=row['root'];s=row['height']/240;sign=1 if p['facing_right'] else -1
  key=f"{row['version']}/h{row['height']}/s{row['stride']}/{row['case']}"
  m=cases.setdefault(key,fresh());m['samples']+=1;u=upper(p,s);prev=previous.get(key)
  if not finite(row):fail(m,'nonfinite',row,None)
  if not row['extra']['hidden'] and norm(sub(p['origin'],r['position']))>0.001:fail(m,'root_modified',row,None)
  if not any(f['planted'] for f in p['feet'].values()):fail(m,'double_air',row,None)
  if not p.get('reach_feasible',True):fail(m,'empty_reach_intersection',row,None)
  if not p.get('rest_comfort_feasible',True):m['rest_comfort_unavailable_samples']=m.get('rest_comfort_unavailable_samples',0)+1
  for side in ['near','far']:
   j=p['joints'][side];leg=DATA['legs'][side];foot=p['feet'][side]
   errs=[abs(norm(sub(j['knee'],j['hip']))-leg['thigh_length']*s),abs(norm(sub(j['ankle'],j['knee']))-leg['shin_length']*s)]
   maximum(m,'bone_error_parent',max(errs),row,side)
   if max(errs)>0.001:fail(m,'bone_length',row,{'side':side,'errors':errs})
   expected=add(p['hip'],rot(mul([leg['hip_offset'][0]*sign,leg['hip_offset'][1]],s),u['pelvis_world_angle']))
   err=norm(sub(expected,j['hip']));maximum(m,'socket_error_parent',err,row,side)
   if err>0.001:fail(m,'socket',row,{'side':side,'error':err})
   expected_sole=add(j['ankle'],mul([leg['sole_from_ankle'][0]*sign,leg['sole_from_ankle'][1]],s))
   err=norm(sub(expected_sole,foot['position']));maximum(m,'boot_attachment_error_parent',err,row,side)
   if err>0.001:fail(m,'boot_attachment',row,{'side':side,'error':err})
   reach=norm(sub(j['ankle'],j['hip']));reach_error=max(0,reach-(leg['thigh_length']+leg['shin_length'])*s,abs(leg['thigh_length']-leg['shin_length'])*s-reach)
   maximum(m,'reach_error_parent',reach_error,row,side)
   if reach_error>0.001:fail(m,'reach',row,{'side':side,'error':reach_error})
   a=sub(j['knee'],j['hip']);b=sub(j['ankle'],j['knee'])
   bend=math.degrees(math.acos(max(-1,min(1,(a[0]*b[0]+a[1]*b[1])/(norm(a)*norm(b))))))
   maximum(m,side+'_knee_flex_degrees',bend,row);minimum(m,side+'_knee_flex_degrees',bend)
   bucket='initial_standing' if '/idle/' in row['case'] else ('moving' if r['state'] in ['start','move','inertial_stop'] else 'stopped_standing')
   maximum(m,bucket+'_'+side+'_knee_flex_degrees',bend,row);minimum(m,bucket+'_'+side+'_knee_flex_degrees',bend)
   if prev and r['state']=='idle' and not p['settling'] and p['settled'] and norm(sub(r['position'],prev['root']['position']))<1e-7 and norm(sub(j['hip'],prev['pose']['joints'][side]['hip']))<0.0001 and norm(sub(j['knee'],prev['pose']['joints'][side]['knee']))<0.0001:
    maximum(m,'quiet_standing_'+side+'_knee_flex_degrees',bend,row);minimum(m,'quiet_standing_'+side+'_knee_flex_degrees',bend)
   angle=math.degrees(math.atan2(b[1],b[0]));maximum(m,side+'_upper_boot_mount_shin_angle_degrees',angle,row);minimum(m,side+'_upper_boot_mount_shin_angle_degrees',angle)
   if prev:
    old=prev['pose']['feet'][side]
    maximum(m,side+'_foot_world_delta_native',norm(sub(foot['position'],old['position']))/s,row)
    if foot['planted'] and old['planted'] and foot['landing_id']==old['landing_id']:
     drift=norm(sub(foot['position'],old['position']));maximum(m,'same_landing_drift_parent',drift,row,side)
     if drift>0.001:fail(m,'planted_drift',row,{'side':side,'drift':drift,'previous':prev})
    if foot['landing_id']!=old['landing_id']:m['landing_count'][side]+=1
  maximum(m,'flight_reach_correction_native',p.get('flight_reach_correction_native',0),row)
  if p.get('support_transfer',''):m['support_transfers']=m.get('support_transfers',0)+1
  local=mul(sub(p['hip'],p['origin']),1/s)
  for i,name in enumerate(['hip_local_x_native','hip_local_y_native']):maximum(m,name,local[i],row);minimum(m,name,local[i])
  if r['state']=='move' and abs(r['velocity'])>154.99 and r['distance']>2*row['stride']*s and 'reverse' not in row['case'] and 'connector' not in row['case']:
   maximum(m,'steady_hip_y_native',local[1],row);minimum(m,'steady_hip_y_native',local[1])
  for name in ['pelvis_world_angle','torso_world_angle','head_world_angle']:
   maximum(m,name+'_abs_degrees',abs(math.degrees(u[name])),row)
  maximum(m,'arm_world_angle_abs_degrees',max(abs(math.degrees(x)) for x in u['arm_world_angle'].values()),row)
  maximum(m,'shoulder_residual_native',norm(p['shoulder_offset'])/s,row)
  if abs(u['head_scale']-s)>1e-9:fail(m,'head_scale',row,u['head_scale'])
  if r['state'] in ['start','move','inertial_stop'] and p['eye_state']=='gaze':fail(m,'moving_side_eye',row,None)
  # This is a geometric hip projection onto registered boot heel/toe spans,
  # not a physical or inferred center of mass.
  contacts=[]
  for side in ['near','far']:
   if p['feet'][side]['planted']:
    part=DATA['parts'][side+'_boot']
    for mark in ['heel','toe']:contacts.append(p['joints'][side]['ankle'][0]+(part[mark][0]-part['root'][0])*sign*s)
  if contacts:maximum(m,'hip_projection_outside_support_native',max(0,min(contacts)-p['hip'][0],p['hip'][0]-max(contacts))/s,row)
  if prev and not row['extra']['hidden']:
   op=prev['pose'];ou=upper(op,s);dr=sub(p['origin'],op['origin']);stationary=norm(dr)<1e-7
   points={'hip':p['hip'],'neck':u['neck_world'],'near_shoulder':u['shoulder_world']['near'],'far_shoulder':u['shoulder_world']['far']}
   oldpoints={'hip':op['hip'],'neck':ou['neck_world'],'near_shoulder':ou['shoulder_world']['near'],'far_shoulder':ou['shoulder_world']['far']}
   mirrored=p['facing_right']!=op['facing_right']
   events=row['extra'].get('owner_orientation_events',[])
   authorized=mirrored and len(events)==1 and events[0]['authorized'] and events[0]['from_right']==op['facing_right'] and events[0]['to_right']==p['facing_right']
   if mirrored and not authorized:fail(m,'unauthorized_orientation_switch',row,events)
   if p.get('upper_body',{}).get('facing_changed',mirrored)!=mirrored:fail(m,'orientation_declaration',row,None)
   if authorized:m['authorized_reflection_frames']=m.get('authorized_reflection_frames',0)+1
   for name,point in points.items():
    delta=sub(point,oldpoints[name]);raw=norm(sub(delta,dr))/s
    reflection=[0.0,0.0]
    if authorized and name!='hip':
     part=DATA['parts']['head' if name=='neck' else name.replace('_shoulder','_arm')]
     oldsign=1 if op['facing_right'] else -1
     reflection=rot([part['attachment_offset'][0]*(sign-oldsign)*s,0.0],ou['torso_world_angle'])
    res=norm(sub(sub(delta,dr),reflection))/s
    maximum(m,name+'_raw_residual_native',raw,row,{'authorized_reflection':authorized})
    maximum(m,name+'_reflection_corrected_residual_native',res,row,{'expected_reflection_parent':reflection,'raw_native':raw,'authorized':authorized})
    maximum(m,name+'_world_delta_parent',norm(delta),row,{'root_delta_parent':dr,'mirrored':mirrored})
    maximum(m,name+'_residual_native',res,row,{'world_delta_parent':delta,'root_delta_parent':dr,'mirrored':mirrored,'authorized_reflection':authorized,'expected_reflection_parent':reflection,'raw_residual_native':raw,'previous_tick':prev['tick']})
    if not mirrored:maximum(m,name+'_residual_without_mirror_native',res,row)
    if res>2.0+1e-5:fail(m,'continuity_'+name,row,{'residual_native':res,'world_delta_parent':delta,'root_delta_parent':dr,'mirrored':mirrored,'authorized_reflection':authorized,'expected_reflection_parent':reflection,'raw_residual_native':raw,'previous':prev})
   if stationary and r['state'] in ['stop','idle'] and key not in stop_start and m.get('seen_travel',False):
    stop_start[key]=(op['hip'][:],sign);m['stop_entry_phase']=p['step_fraction']
   if stationary and key in stop_start and r['state'] in ['stop','idle']:
    at,direction=stop_start[key]
    maximum(m,'stationary_stop_backward_hip_native',max(0,(at[0]-p['hip'][0])*direction)/s,row)
    maximum(m,'stationary_stop_hip_distance_native',norm(sub(at,p['hip']))/s,row)
    m['max']['stationary_stop_hip_travel_native']=m['max'].get('stationary_stop_hip_travel_native',0)+norm(sub(p['hip'],op['hip']))/s
    for side in ['near','far']:
     metric='stationary_stop_'+side+'_foot_travel_native'
     m['max'][metric]=m['max'].get(metric,0)+norm(sub(p['feet'][side]['position'],op['feet'][side]['position']))/s
   if not stationary:stop_start.pop(key,None);m['seen_travel']=True
   if stationary and r['state'] in ['start','move','inertial_stop'] and abs(p['step_distance']-op['step_distance'])>1e-8:fail(m,'blocked_gait_advance',row,None)
  if not row['extra']['freeze_exact']:fail(m,'hidden_freeze',row,None)
  if not row['extra']['hidden']:previous[key]=row
 for key,m in cases.items():
  if 'steady_hip_y_native' in m['max']:
   m['steady_hip_peak_to_peak_native']=m['max']['steady_hip_y_native']-m['min']['steady_hip_y_native']
   if m['steady_hip_peak_to_peak_native']>4.00001:m['violations']['steady_hip_range']+=1
  if m['max'].get('stationary_stop_backward_hip_native',0)>4.00001:m['violations']['stop_backward_range']+=1
  for code,detail in m.pop('first_failures').items():
   if code not in fail_rows:fail_rows[code]={'case_key':key,**detail}
  m['violations']=dict(m['violations']);m['landing_count']=dict(m['landing_count'])
 groups={}
 for key,m in cases.items():
  group='/'.join(key.split('/')[:3]);g=groups.setdefault(group,{'samples':0,'cases':0,'max':{},'violations':collections.Counter(),'stop_phases':set()})
  g['samples']+=m['samples'];g['cases']+=1;g['violations'].update(m['violations'])
  for k,v in m['max'].items():g['max'][k]=max(v,g['max'].get(k,-math.inf))
  g['max']['steady_hip_peak_to_peak_native']=max(g['max'].get('steady_hip_peak_to_peak_native',0),m.get('steady_hip_peak_to_peak_native',0))
  if '/stops/' in key and m['stop_entry_phase'] is not None:g['stop_phases'].add(round(m['stop_entry_phase'],6))
 for g in groups.values():g['violations']=dict(g['violations']);g['stop_phase_count']=len(g.pop('stop_phases'))
 report={'status':'PASS' if not any(m['violations'] for m in cases.values()) else 'FAIL','trace_file':path.name,'trace_bytes':path.stat().st_size,'trace_sha256':hashlib.sha256(path.read_bytes()).hexdigest(),'formula':'norm(joint_delta-root_delta-reflection_only_delta)/(height/240); reflection only on one owner-authorized declared facing frame for neck/shoulders; zero otherwise and always zero for hip','reflection_formula':'R(previous_torso_world_angle) * [offset_x*(new_sign-old_sign)*(height/240),0]','support_drift_formula':'true world displacement for consecutive planted samples with identical landing ID','groups':groups,'cases':cases}
 out=path.with_suffix('.metrics.json');out.write_text(json.dumps(report,ensure_ascii=False,indent=2),encoding='utf-8')
 path.with_suffix('.first-failures.json').write_text(json.dumps(fail_rows,ensure_ascii=False,indent=2),encoding='utf-8')
 print(json.dumps({'status':report['status'],'metrics':str(out),'groups':{k:{'samples':v['samples'],'phases':v['stop_phase_count'],'bone':v['max'].get('bone_error_parent'),'drift':v['max'].get('same_landing_drift_parent'),'steady_p2p':v['max'].get('steady_hip_peak_to_peak_native'),'stop_back':v['max'].get('stationary_stop_backward_hip_native'),'residuals':{n:v['max'].get(n+'_residual_native') for n in ['hip','neck','near_shoulder','far_shoulder']},'without_mirror':{n:v['max'].get(n+'_residual_without_mirror_native') for n in ['hip','neck','near_shoulder','far_shoulder']},'violations':v['violations']} for k,v in groups.items()}}),flush=True)
if __name__=='__main__':
 for argument in sys.argv[1:]:analyze(Path(argument))
