extends SceneTree
## Presentation-only dev15 contract. No engine physics, saves or native input.
## Totals are actual cumulative telemetry; a short cue needs a newly observed,
## simultaneous increase in both funded absorption and its shield energy cost.
const Receipt=preload("res://scripts/flight_receipt.gd")
const COUNTERS:Array[String]=["impact_absorbed","impact_shield_energy"]
var passed:int=0
var failed:int=0

func check(ok:bool,title:String) -> void:
 if ok:passed+=1
 else:failed+=1;push_error("FAIL "+title)

func frame(elapsed:float=0.0,absorbed:float=0.0,spent:float=0.0) -> Dictionary:
 return {"elapsed":elapsed,"control_version":"pilot-free-v2","flight_status":"running","charging":false,"paused":false,"impact_absorbed":absorbed,"impact_shield_energy":spent,"events":[],"destination_navigation":{"status":"running","charging":false}}

func cue(receipt,data:Dictionary,title:String) -> String:
 var before:PackedByteArray=var_to_bytes(data)
 var result:Variant=receipt.shield_receipt(data)
 check(result is String,title+" returns a string")
 check(var_to_bytes(data)==before,title+" preserves every input byte")
 return str(result)

func quiet(receipt,data:Dictionary,title:String) -> void:
 check(cue(receipt,data,title).is_empty(),title+" stays quiet")

func shown(receipt,data:Dictionary,title:String) -> void:
 var expected:String="护盾已抵消少量撞击" if float(data.impact_absorbed)<.05 else "护盾已抵消 %.1f HP"%float(data.impact_absorbed)
 check(cue(receipt,data,title)==expected,title+" displays actual cumulative absorption")

func seeded(absorbed:float=0.0,spent:float=0.0,elapsed:float=0.0):
 var receipt=Receipt.new()
 quiet(receipt,frame(elapsed,absorbed,spent),"first observation establishes a baseline")
 return receipt

func active():
 var receipt=seeded()
 shown(receipt,frame(1.0,2.5,12.5),"fresh funded contact")
 return receipt

func totals(data:Dictionary,title:String) -> Dictionary:
 var before:PackedByteArray=var_to_bytes(data)
 var result:Dictionary=Receipt.shield_totals(data)
 check(var_to_bytes(data)==before,title+" totals preserve every input byte")
 return result

func totals_contract() -> void:
 for pair in [[0,0],[0.0,0.0],[3,15],[2.5,12.5],[.001,.005]]:
  var data:Dictionary=frame();data.impact_absorbed=pair[0];data.impact_shield_energy=pair[1]
  var expected:Dictionary={"impact_absorbed":pair[0],"impact_shield_energy":pair[1]}
  check(totals(data,"valid pair "+str(pair))==expected,"totals return only the two actual numeric fields without estimating or rescaling: "+str(pair))
 for pair in [[0,1],[1,0],[-1,1],[1,-1]]:
  check(totals(frame(0.0,float(pair[0]),float(pair[1])),"inconsistent pair "+str(pair)).is_empty(),"totals reject partial or negative funding "+str(pair))
 for key in COUNTERS:
  for value in [null,"2.5","0","NaN",NAN,INF,-INF,-1.0,true,false,{},[],Vector2.ONE]:
   var data:Dictionary=frame(2.0,2.5,12.5);data[key]=value
   check(totals(data,"invalid "+key+" "+str(value)).is_empty(),"totals reject untrusted field "+key+" "+str(value))
  var missing:Dictionary=frame(2.0,2.5,12.5);missing.erase(key)
  check(totals(missing,"missing "+key).is_empty(),"missing counter is not inferred: "+key)
 for version in ["","pilot-free-v1","pilot-v3","pilot-v4-wormhole","pilot-v5-protected-bird","pilot-free-v2-nearby",null,2]:
  var data:Dictionary=frame(2.0,2.5,12.5);data.control_version=version
  check(totals(data,"version "+str(version)).is_empty(),"totals are current free-v2 only "+str(version))
 # A report may copy validated final totals even though a terminal flight must
 # never announce a newly occurring impact. This is not an energy estimate.
 for status in ["running","success","failed"]:
  var data:Dictionary=frame(30.0,7.5,37.5);data.flight_status=status
  check(totals(data,"report status "+status)=={"impact_absorbed":7.5,"impact_shield_energy":37.5},"final report retains exact actual totals "+status)
 var unrelated:Dictionary=frame();unrelated.erase("impact_absorbed");unrelated.erase("impact_shield_energy")
 unrelated.energy_used=500.0;unrelated.energy_remaining=5500.0;unrelated.shield_count=1;unrelated.shield_active=true
 check(totals(unrelated,"ordinary energy is not shield evidence").is_empty(),"no shield statistics are invented from batteries or installed shield")

func observation_contract() -> void:
 var receipt=seeded(10.0,50.0,20.0)
 for i in 5:quiet(receipt,frame(20.0+float(i),10.0,50.0),"restored first cumulative snapshot "+str(i))
 shown(receipt,frame(25.0,12.5,62.5),"later observed contact reports cumulative 12.5, not delta 2.5")
 shown(receipt,frame(26.0,15.0,75.0),"second fresh contact refreshes with cumulative 15.0")
 receipt=seeded(10.0,20.0)
 quiet(receipt,frame(1.0,11.0,20.0),"absorption-only growth cannot announce funded contact")
 quiet(receipt,frame(2.0,11.0,21.0),"later energy-only growth cannot complete an earlier contact")
 quiet(receipt,frame(3.0,12.0,21.0),"second absorption-only observation stays independent")
 quiet(receipt,frame(4.0,12.0,22.0),"separate observations are never combined")
 shown(receipt,frame(5.0,13.0,23.0),"both counters increase in one trusted observation")
 receipt=seeded()
 shown(receipt,frame(1.0,.001,.005),"real sub-display-precision contact is not labelled zero HP")
 shown(receipt,frame(2.0,.049,.245),"small positive cumulative absorption uses bounded qualitative copy")
 shown(receipt,frame(3.0,.05,.25),"rounding threshold may use the numeric HP copy")
 var no_shield:Dictionary=frame(1.0)
 no_shield.events=["001.0s  护盾已抵消 99.0 HP","001.0s  首次受损：货物 #1 · 碰撞 · 0.00 HP。"]
 receipt=seeded();quiet(receipt,no_shield,"a log or rounded micro-collision cannot forge actual shield funding")
 for key in COUNTERS:
  receipt=seeded();var data:Dictionary=frame(1.0);data[key]=2.0
  quiet(receipt,data,"positive "+key+" without its paired evidence")
 receipt=seeded();var integer_data:Dictionary=frame(1.0);integer_data.impact_absorbed=3;integer_data.impact_shield_energy=15
 shown(receipt,integer_data,"actual integer counters also qualify")

func lifetime_contract() -> void:
 var receipt=active()
 shown(receipt,frame(6.999,2.5,12.5),"cue survives just inside six seconds")
 shown(receipt,frame(7.0,2.5,12.5),"six-second boundary is inclusive")
 quiet(receipt,frame(7.001,2.5,12.5),"cue expires immediately after six seconds")
 for i in 20:quiet(receipt,frame(8.0+float(i),2.5,12.5),"unchanged counters cannot rejuvenate old cue "+str(i))
 shown(receipt,frame(40.0,3.5,17.5),"a new funded contact can announce after long silence")
 receipt=active();var paused:Dictionary=frame(6.0,2.5,12.5);paused.paused=true
 for i in 1000:receipt.shield_receipt(paused)
 shown(receipt,paused,"paused renders spend no simulation elapsed")
 quiet(receipt,frame(7.001,2.5,12.5),"resume ages from the original impact observation")
 receipt=active()
 shown(receipt,frame(5.0,3.5,17.5),"new funded contact renews the short cue")
 shown(receipt,frame(11.0,3.5,17.5),"renewed cue has its own six-second boundary")
 quiet(receipt,frame(11.001,3.5,17.5),"renewed cue still expires")

func discontinuity_contract() -> void:
 var receipt=active();receipt.reset()
 quiet(receipt,frame(2.0,2.5,12.5),"explicit reset cannot replay old cumulative absorption")
 shown(receipt,frame(3.0,3.5,17.5),"post-reset observed contact works")
 receipt=active()
 quiet(receipt,frame(.5,10.0,50.0),"clock rewind clears even increasing restored totals")
 shown(receipt,frame(.6,11.0,55.0),"new observations after rewind work")
 for key in COUNTERS:
  receipt=active();var rollback:Dictionary=frame(2.0,3.0,15.0);rollback[key]=1.0
  quiet(receipt,rollback,"rollback of "+key+" clears visible cue without treating other growth as a contact")
  rollback.elapsed=3.0;rollback.impact_absorbed+=1.0;rollback.impact_shield_energy+=5.0
  shown(receipt,rollback,"rebaselined "+key+" can observe later actual growth")
 receipt=active();quiet(receipt,frame(2.0),"both zero counters clear old-flight cue")
 shown(receipt,frame(3.0,1.0,5.0),"zero-counter baseline permits a fresh contact")
 for key in ["impact_absorbed","impact_shield_energy","elapsed"]:
  for value in [null,"3.0",NAN,INF,-INF,-1.0,true,{}]:
   receipt=active();var invalid:Dictionary=frame(2.0,3.0,15.0);invalid[key]=value
   quiet(receipt,invalid,"invalid observation clears cue: "+key+"="+str(value))
   quiet(receipt,frame(3.0,4.0,20.0),"first trusted observation after invalid "+key+" only rebuilds baseline")
   shown(receipt,frame(4.0,5.0,25.0),"later trusted growth after invalid "+key+" qualifies")
 for key in ["impact_absorbed","impact_shield_energy","elapsed"]:
  receipt=active();var incomplete:Dictionary=frame(2.0,3.0,15.0);incomplete.erase(key)
  quiet(receipt,incomplete,"missing "+key+" cannot retain an unsupported receipt")

func context_contract() -> void:
 for version in ["","pilot-free-v1","pilot-v3","pilot-v4-wormhole","pilot-v5-protected-bird","pilot-free-v2-nearby",null]:
  var receipt=active();var data:Dictionary=frame(2.0,3.0,15.0);data.control_version=version
  quiet(receipt,data,"old or unrecognized protocol "+str(version))
  quiet(receipt,frame(3.0,4.0,20.0),"return to current protocol starts a fresh baseline")
 var blockers:Array=[{"flight_status":"success"},{"flight_status":"failed"},{"flight_status":"charging"},{"flight_status":"idle"},{"status":"success"},{"status":"failed"},{"arrival_state":"received"},{"delivered":true},{"charging":true},{"destination_navigation":{"status":"success","charging":false}},{"destination_navigation":{"status":"failed","charging":false}},{"destination_navigation":{"status":"running","charging":true}}]
 for blocker in blockers:
  var receipt=active();var data:Dictionary=frame(2.0,3.0,15.0);data.merge(blocker,true)
  quiet(receipt,data,"non-running or terminal context "+str(blocker))
  quiet(receipt,frame(3.0,4.0,20.0),"leaving blocked context does not invent an intervening contact")
  shown(receipt,frame(4.0,5.0,25.0),"a later actual running contact works again")
 var receipt=active();var missing_status:Dictionary=frame(2.0,3.0,15.0)
 missing_status.erase("flight_status");missing_status.erase("destination_navigation")
 quiet(receipt,missing_status,"no positive running evidence")

func original_receipt_contract() -> void:
 # Exercise the same co-located presenter in either call order. Its existing
 # event projection must remain byte-identical, including dev13 split metadata.
 var split:String="001.9s  模块分裂：质量、储能、强度与耐久均分，未复制货物。"
 var hit:String="001.9500s  首次受损：分裂核 #1005 · 碰撞 · 0.00 HP。"
 for shield_first in [false,true]:
  var receipt=seeded();var original=Receipt.new();var data:Dictionary=frame(2.0,2.5,12.5);data.events=[split,hit]
  var expected:Array[Dictionary]=original.update_free(data,1)
  var actual:Array[Dictionary]=[]
  if shield_first:
   shown(receipt,data,"shield called before event update");actual=receipt.update_free(data,1)
  else:
   actual=receipt.update_free(data,1);shown(receipt,data,"shield called after event update")
  check(var_to_bytes(actual)==var_to_bytes(expected),"shield projection preserves existing dev13 event receipt order "+str(shield_first))
  check(var_to_bytes(receipt.update(data,1))==var_to_bytes(original.update(data,1)),"legacy update result remains exact "+str(shield_first))
  var rewind:Dictionary=frame(.5,10.0,50.0)
  if shield_first:
   quiet(receipt,rewind,"shield-first rewind clears cue");receipt.update_free(rewind,1)
  else:
   receipt.update_free(rewind,1);quiet(receipt,rewind,"event-first rewind clears cue")
  var next:Dictionary=frame(.6,11.0,55.0)
  if shield_first:
   shown(receipt,next,"shield-first growth after rewind");receipt.update_free(next,1)
  else:
   receipt.update_free(next,1);shown(receipt,next,"event-first growth after rewind")
 var receipt=active();var reference:WeakRef=weakref(receipt);receipt=null
 check(reference.get_ref()==null,"receipt remains a non-retaining RefCounted projection")

func _initialize() -> void:
 totals_contract();observation_contract();lifetime_contract();discontinuity_contract();context_contract();original_receipt_contract()
 print("SHIELD_RECEIPT_DEV15 passed=%d failed=%d native_gui=NOT_RUN"%[passed,failed])
 quit(1 if failed else 0)
