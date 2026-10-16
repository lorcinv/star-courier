extends SceneTree
## One real native-owned ship, normal day progression, physical gate + threats,
## finalized component losses and saved receipt. No progress or stock injection.
const Econ=preload("res://scripts/economy.gd")
const Sim=preload("res://scripts/pilot_delivery_rift_simulation_v5.gd")
const Timeline=preload("res://scripts/pilot_free_timeline_v2.gd")
const Chapter=preload("res://scripts/delivery_chapter_v3.gd")
var passed:int=0
var failed:int=0
func check(ok:bool,label:String)->void:
 if ok:passed+=1
 else:failed+=1;push_error("FAIL "+label)
func _initialize()->void:
 var source:String=OS.get_environment("COURIER_NATIVE_MOON_SAVE")
 if OS.get_environment("XDG_DATA_HOME").is_empty() or source.is_empty():quit(2);return
 var bytes:PackedByteArray=FileAccess.get_file_as_bytes(source)
 var raw:Dictionary=JSON.parse_string(bytes.get_string_from_utf8())
 var file=FileAccess.open("user://savegame.json",FileAccess.WRITE);file.store_buffer(bytes);file.close()
 var e=Econ.new();e.load_state();e.enable_story_mode()
 var ship:Array=raw.design;var pad:Array=raw.launcher;var settings:Dictionary=raw.settings
 check(not e.review_load_blocked and e.delivery_chapter_state.unlocked_level==5,"native moon progress enters unchanged")
 check(e.close_day_and_save(ship,pad,settings).ok and e.next_day_and_save(ship,pad,settings).ok,"ordinary next day creates fifth formal order")
 check(e.accept_contract("D6-A").ok and e.mark_cargo_loaded("D6-A").ok,"accept and load actual biological order")
 check(e.missing_parts(ship,pad).is_empty(),"physical sample owns its actual native ship and pad")
 check(e.begin_dispatch(ship,pad,{"angle_degrees":0.0,"power_fraction":1.0}).ok,"formal v5 snapshot captures owned build")
 var sim=Sim.new();sim.configure(ship,pad,e.in_flight.route,int(e.in_flight.seed));sim.release_launcher(0.0,1.0)
 e.in_flight.launch_released=true;e.in_flight.erase("launch_preparation")
 var timeline=Timeline.new();var completed:int=0;var waypoint:int=0
 var goals:Array[Vector2]=[Vector2(115,16),Vector2(178,16),Vector2(200,0)]
 for tick in 60*90:
  if sim.status!="running":break
  var crossed:bool=sim.telemetry.region=="greenhouse"
  var goal:Vector2=Vector2(29,0)
  if crossed:
   if sim.cargo_position().distance_to(goals[waypoint])<5.0 and waypoint<goals.size()-1:waypoint+=1
   goal=goals[waypoint]
  var delta:Vector2=goal-sim.cargo_position();var body:Dictionary=sim.body_for_part(1)
  var wanted:Vector2=delta.normalized()*minf(10.0 if crossed else 7.0,sqrt(4.0*maxf(0.0,delta.length()-1.0)))
  var error:Vector2=wanted-Vector2(body.velocity)
  var x:int=1000 if error.x>0.2 else (-1000 if error.x< -0.2 else 0)
  var y:int=1000 if error.y>0.2 else (-1000 if error.y< -0.2 else 0)
  timeline.record(tick,{"axis_x_q":x,"axis_q":y,"boost":false,"active":false,"device_id":-1,"brake":false})
  sim.set_free_flight_input(x,y,false,false,-1,false);sim.step(1.0/60.0);completed+=1
 e.in_flight.ticks=completed;e.in_flight.input_commands=timeline.snapshot();e.in_flight.elapsed=sim.elapsed
 var final:Dictionary=sim.finalize_settlement()
 check(sim.status=="success" and final.portal_crossings.size()==1 and final.portal_crossing_tick>0,"actual cargo passes physical portal and receiver")
 check(int(final.rift_pirate.shots_fired)==2,"real flight encounters finite pirate emissions")
 var capture:Dictionary=Chapter.capture_portal_evidence(e.in_flight.route,e.in_flight,final,true)
 check(capture.ok,"actual physical body-envelope witness passes economic validator")
 var before:int=e.credits;var inventory:Dictionary=e.inventory.duplicate(true)
 var receipt:Dictionary=e.settle_contract_and_save("D6-A",final,sim.elapsed,sim.status=="success",ship,pad,settings)
 check(receipt.ok,"actual physical finalization commits formal receipt")
 if receipt.ok:
  var r:Dictionary=e.last_settlement
  check(r.energy==ceili(float(final.energy_used)*float(e.contract_by_id("D6-A").pilot_energy_tariff)),"actual finalized energy charged once")
  check(r.repairs==ceili(float(final.repair_cost)) and r.lost==ceili(float(final.lost_cost)) and r.ammo==ceili(float(final.ammo_cost)),"all actual repair/lost/consumed components charged")
  check(r.compensation==Chapter.cargo_damage(int(e.contract_by_id("D6-A").cargo_value),float(final.delivery_integrity)),"actual biological and impact HP produce single cargo compensation")
  check(r.charged_costs==r.actual_costs and e.credits==before+int(r.profit),"no old cash cap or hidden second portal charge")
  check(e.inventory==inventory and e.delivery_chapter_state.unlocked_level==6,"success advances once without adding owned assets")
  var loaded=Econ.new();loaded.load_state()
  check(not loaded.review_load_blocked and loaded.credits==e.credits and loaded.in_flight.is_empty() and loaded.delivery_chapter_state.unlocked_level==6,"real completion proof and money survive restart")
  print("RIFT_FORMAL_SAMPLE ",JSON.stringify({"elapsed":sim.elapsed,"integrity":final.delivery_integrity,"energy_j":final.energy_used,"energy":r.energy,"repair":r.repairs,"lost":r.lost,"ammo":r.ammo,"compensation":r.compensation,"costs":r.actual_costs,"profit":r.profit,"credits":e.credits,"portal_tick":r.portal_delivery_evidence.portal_crossing_tick}))
 check(FileAccess.get_file_as_bytes(source)==bytes,"original native completion remains untouched")
 print("DELIVERY_RIFT_ECONOMY_V5_MECHANICS passed=%d failed=%d total=%d"%[passed,failed,passed+failed]);quit(1 if failed else 0)
