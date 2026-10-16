extends SceneTree
## Four narrow real-solver invoices on normal new-shop light orders: unpowered
## delivery, spent-cash abort, discarded mother frame, and multi-part ammunition.
const Econ=preload("res://scripts/economy.gd")
const Profile=preload("res://scripts/pilot_delivery_profile_v6.gd")
const Sim=preload("res://scripts/pilot_delivery_simulation_v6.gd")
const Timeline=preload("res://scripts/pilot_free_timeline_v2.gd")
const Parts=preload("res://scripts/parts_expanded.gd")
const Chapter=preload("res://scripts/delivery_chapter_v3.gd")
var passed:int=0
var failed:int=0
func check(ok:bool,label:String)->void:
 if ok:passed+=1
 else:failed+=1;push_error("FAIL "+label)
func part(id:int,type:String,x:int,param:float,extra:Dictionary={})->Dictionary:
 var p:Dictionary={"id":id,"type":type,"x":x,"y":0,"rot":0,"param":param,"target":-1,"input_a":-1,"input_b":-1};p.merge(extra,true);return p
func fresh():
 for name in ["savegame.json","savegame.backup.json","savegame.tmp","savegame.shop-backup.tmp"]:
  if FileAccess.file_exists("user://"+name):DirAccess.remove_absolute("user://"+name)
 var e=Econ.new();e.enable_delivery_mode();e.starter_stock(Profile.starter_design(),Profile.starter_launcher());e.enable_story_mode()
 check(e.accept_contract("D1-A").ok,"normal new light order accepts")
 return e
func run_case(kind:String)->void:
 var e=fresh();var pad:Array=Profile.starter_launcher();var ship:Array=[part(1,"cargo",0,100)]
 var is_abort:bool=kind in ["spent_cash_abort","group_ammo_abort"]
 if kind in ["cargo_ejection","group_ammo_abort"]:
  check(e.buy_part("accelerator",Parts.catalog().accelerator).ok,"accelerator is paid at full catalogue price")
  if kind=="cargo_ejection":ship=[part(1,"cargo",1,100),part(2,"accelerator",0,8,{"target":1,"input_a":-2}),part(3,"battery",-1,300)]
  else:ship=[part(1,"cargo",0,100),part(2,"accelerator",1,8,{"target":4,"input_a":-2}),part(3,"battery",-1,300),part(4,"beam",2,32),part(5,"armor",3,150)]
 if kind=="spent_cash_abort":
  for item in ["battery","battery","battery","battery","armor","armor","beam","beam","beam"]:check(e.buy_part(item,Parts.catalog()[item]).ok,"real stock purchase spends available cash")
  check(e.credits==0,"cash is genuinely spent on retained inventory before dispatch")
 check(e.missing_parts(ship,pad).is_empty(),"every physical component is owned")
 var inventory:Dictionary=e.inventory.duplicate(true);e.mark_cargo_loaded("D1-A")
 var launch:Dictionary={"angle_degrees":0.5,"power_fraction":0.3}
 check(e.begin_dispatch(ship,pad,launch).ok,"normal formal dispatch captures real component layout")
 var s=Sim.new();s.configure(ship,pad,e.in_flight.route,int(e.in_flight.seed));s.release_launcher(launch.angle_degrees,launch.power_fraction)
 e.in_flight.launch_released=true;e.in_flight.erase("launch_preparation")
 var timeline=Timeline.new();var completed:int=0;var coast_seen:bool=false
 for tick in range(60*45):
  if s.status!="running":break
  var active:bool=tick==0 and kind in ["cargo_ejection","group_ammo_abort"]
  var device:int=2 if active else -1
  timeline.record(tick,{"axis_x_q":0,"axis_q":0,"boost":false,"active":active,"device_id":device,"brake":false})
  s.set_free_flight_input(0,0,false,active,device,false);s.step(1.0/60.0);completed+=1
  coast_seen=coast_seen or bool(s.telemetry.unpowered_coasting)
  if is_abort and completed==60:
   check(s.status=="running","operator abort happens before any objective terminal failure")
   s.status="failed";s.events.append("操作员中止本次航行。");e.in_flight.terminal_intent="abort";break
 e.in_flight.ticks=completed;e.in_flight.input_commands=timeline.snapshot();e.in_flight.elapsed=s.elapsed
 var t:Dictionary=s.finalize_settlement()
 check(s.status==("failed" if is_abort else "success"),"actual solver reaches expected terminal outcome "+kind)
 if kind!="group_ammo_abort":check(coast_seen,"battery-free cargo really coasts instead of receiving hidden power")
 if kind=="cargo_ejection":
  check(t.accelerator_events.size()==1 and t.accelerator_events[0].payload_ids==[1],"real paid interface cut ejects cargo")
  check(s.parts[2].replacement_kind=="lost" and s.parts[3].replacement_kind=="lost" and float(t.lost_cost)==100.0,"unrecovered mother accelerator and battery are each billed as lost")
 if kind=="group_ammo_abort":
  check(t.accelerator_events.size()==1 and t.accelerator_events[0].payload_ids==[4,5],"one trigger ejects the actual two-part noncargo group")
  check(s.parts[4].replacement_kind=="ammo" and s.parts[5].replacement_kind=="ammo" and float(t.ammo_cost)==35.0 and float(t.lost_cost)==0.0,"both ammunition parts charged once without duplicate loss")
 var before:int=e.credits;var result:Dictionary=e.settle_contract_and_save("D1-A",t,s.elapsed,s.status=="success",ship,pad,{})
 check(result.ok,"real finalization commits actual costs "+kind)
 if not result.ok:printerr(result);return
 var r:Dictionary=e.last_settlement
 check(r.energy==ceili(float(t.energy_used)*float(s.route.pilot_energy_tariff)) and r.lost==ceili(float(t.lost_cost)) and r.ammo==ceili(float(t.ammo_cost)) and r.repairs==ceili(float(t.repair_cost)),"invoice retains every actual physical cost category")
 check(r.compensation==Chapter.cargo_damage(int(s.route.cargo_value),float(t.delivery_integrity)) and r.actual_costs==r.charged_costs and e.credits==before+int(r.profit),"single HP compensation and uncapped arithmetic")
 check(e.inventory==inventory,"settlement restores owned designs without granting new inventory")
 var loaded=Econ.new();loaded.load_state()
 check(not loaded.review_load_blocked and loaded.credits==e.credits and loaded.in_flight.is_empty(),"real v6 receipt and balance reload")
 check(not loaded.settle_contract_and_save("D1-A",t,s.elapsed,s.status=="success",ship,pad,{}).ok and loaded.credits==e.credits,"repeat physical settlement cannot award or charge twice")
 if kind=="spent_cash_abort":
  check(e.credits<0 and not loaded.recover_legacy_debt_and_save(ship,pad,{}).changed and loaded.credits==e.credits,"buying out cash does not exempt the actual unpowered abort bill")
 print("CELL_FORMAL_SAMPLE ",JSON.stringify({"kind":kind,"status":s.status,"elapsed":s.elapsed,"integrity":t.delivery_integrity,"energy_j":t.energy_used,"energy":r.energy,"ammo":r.ammo,"lost":r.lost,"repairs":r.repairs,"compensation":r.compensation,"costs":r.actual_costs,"profit":r.profit,"credits":e.credits}))
func _initialize()->void:
 if OS.get_environment("XDG_DATA_HOME").is_empty():quit(2);return
 for kind in ["bare_delivery","spent_cash_abort","cargo_ejection","group_ammo_abort"]:run_case(kind)
 print("DELIVERY_CELL_ECONOMY_V6_MECHANICS passed=%d failed=%d total=%d"%[passed,failed,passed+failed]);quit(1 if failed else 0)
