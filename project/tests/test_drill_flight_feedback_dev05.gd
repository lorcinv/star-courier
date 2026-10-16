extends SceneTree
## Read-only selected-card projection + real solver ticks; no native-input claim.
const View=preload("res://scripts/selected_device_presentation_v2.gd")
const HUD=preload("res://scripts/game_hud.gd")
const Parts=preload("res://scripts/parts_expanded.gd")
const Sim=preload("res://scripts/pilot_free_simulation_v2.gd")
const Profile=preload("res://scripts/pilot_free_profile_v2.gd")
const Extreme=preload("res://scripts/pilot_extreme_profile.gd")
const IDLE="按住启动 · 慢推破岩"
const WORKING="钻头运转"
const PARTIAL="钻头运转 · 供电不足"
var passed:int=0
var failed:int=0
func check(ok:bool,label:String) -> void:
 if ok:passed+=1;print("PASS ",label)
 else:failed+=1;push_error("FAIL "+label)
func part(id:int,kind:String,x:int,y:int=0,extra:Dictionary={}) -> Dictionary:
 var p:Dictionary={"id":id,"type":kind,"x":x,"y":y,"rot":0,"param":Parts.defaults(kind),"input_a":-1,"input_b":-1,"target":-1}
 p.merge(extra,true);return p
func make_sim(extra:Array=[]):
 var route:Dictionary=Profile.route(Extreme.route({"weight":1.0}))
 route.hazards=[];route.pilot_gates=[];route.distance=10000.0;route.destination_y=-1000.0;route.pilot_drag=0.0
 var design:Array=[part(1,"cargo",0),part(2,"battery",-1),part(3,"drill",1,0,{"input_a":-2})]
 design.append_array(extra)
 var sim=Sim.new();sim.configure(design,[],route,42);return sim
func step(sim,held:bool=false,id:int=3) -> void:
 sim.set_free_flight_input(0,0,false,held,id);sim.step(sim.FIXED_DT)
func snapshot(sim) -> PackedByteArray:
 return var_to_bytes({"parts":sim.parts,"bodies":sim.bodies,"links":sim.links,"route":sim.route,"obstacles":sim.obstacles,"telemetry":sim.telemetry,"elapsed":sim.elapsed,"paid":sim._paid_drills,"input":[sim.pilot_axis_x_q,sim.pilot_axis_q,sim.pilot_aim_x_q,sim.pilot_aim_y_q,sim.pilot_active,sim.pilot_device_id,sim._active_edge_device_id]})
func project(sim,label:String) -> Dictionary:
 var before:PackedByteArray=snapshot(sim)
 var actual:Dictionary=View.state(sim)
 check(snapshot(sim)==before,label+" projection mutates no physical, power, route, or input state")
 return actual
func _initialize() -> void:run.call_deferred()
func run() -> void:
 runtime()
 await hud_checks()
 print("DRILL_FLIGHT_FEEDBACK_DEV05 passed=%d failed=%d native_input=NOT_RUN"%[passed,failed]);quit(1 if failed else 0)
func runtime() -> void:
 var sim=make_sim();step(sim)
 var actual:Dictionary=project(sim,"idle")
 check(actual.status==IDLE and actual.hold_to_use and sim.telemetry.drill_energy_used==0.0,"idle selected manual drill discloses held use and slow approach without motor cost")
 sim.set_free_flight_input(0,0,false,true,3)
 check(project(sim,"requested").status==IDLE,"input request alone never claims paid motor work")
 sim.step(sim.FIXED_DT)
 check(project(sim,"working").status==WORKING and sim.parts[3].drill_power_ratio>0.0 and sim.telemetry.drill_energy_used>0.0,"actual paid tick shows motor running")
 check(sim.telemetry.drill_damage==0.0 and sim.telemetry.drill_contacts==0 and not "破岩" in View.state(sim).status,"empty-lane rotation never claims rock contact or cutting")
 var energy:float=sim.telemetry.energy_used
 sim.set_free_flight_input(0,0,false,false,3)
 check(sim.parts[3].drill_power_ratio>0.0 and project(sim,"release before tick").status==IDLE,"release never leaves a running claim solely from last paid tick")
 step(sim)
 check(project(sim,"release").status==IDLE and sim.parts[3].drill_power_ratio==0.0 and sim.telemetry.energy_used==energy,"release returns to idle after actual solver tick without spending")
 var devices:Array=[part(4,"teleporter",0,1,{"input_a":-2,"param":8.0}),part(5,"drill",1,1,{"input_a":-2})]
 var switching=make_sim(devices);step(switching,true,3);energy=switching.telemetry.energy_used
 step(switching,true,5)
 check(project(switching,"switch drill").status==IDLE and switching.telemetry.energy_used==energy,"switching to another drill while held shows idle rather than requested work")
 step(switching,true,4)
 check(project(switching,"switch edge").status=="可用" and not View.state(switching).get("hold_to_use",false) and switching.telemetry.energy_used==energy,"edge device keeps its original available text and gains no firing authority")
 step(switching,true,3)
 check(project(switching,"switch back").status==WORKING and switching.parts[3].drill_power_ratio>0.0,"switching back reports the original solver's paid held-device behavior exactly")
 step(switching,false,5);step(switching,true,5)
 check(project(switching,"fresh press").status==WORKING and switching.parts[3].drill_power_ratio==0.0,"release and new press report only newly selected paid motor")
 switching.set_pilot_input(0,false,false)
 check(switching.parts[5].drill_power_ratio>0.0 and project(switching,"clear before tick").status==IDLE,"pause/focus clear keeps paid history intact but immediately stops current running claim")
 switching.step(switching.FIXED_DT);switching.pilot_device_id=5
 check(project(switching,"cleared input").status==IDLE,"pause/focus-style clear cannot leave working claim after next tick")
 var limited=make_sim();limited.parts[2].energy=.25;step(limited,true)
 check(project(limited,"partial power").status==PARTIAL and is_equal_approx(limited.parts[3].drill_power_ratio,.5) and is_zero_approx(limited.parts[2].energy),"partial paid output remains running but discloses insufficient supply")
 var empty=make_sim();empty.parts[2].energy=0.0;step(empty,true)
 check(project(empty,"empty power").status=="电量不足" and empty.parts[3].drill_power_ratio==0.0,"held input without paid power never claims running")
 var low=make_sim();low.parts[2].energy=.25;step(low)
 check(project(low,"idle low power").status=="电量不足","idle insufficient supply uses existing low-energy semantics")
 var valve=make_sim([part(6,"valve",1,1,{"target":3,"param":30.0})]);step(valve,true)
 check(project(valve,"rate-limited power").status==PARTIAL and is_equal_approx(valve.parts[3].drill_power_ratio,.5),"actual valve-limited output is not mistaken for full-power motor work")
 var detached=make_sim();step(detached,true);detached._cut(1,3);detached._rebuild_bodies()
 check(project(detached,"detached").status=="已失联" and not View.state(detached).get("hold_to_use",false),"detached paid drill remains lost instead of showing stale working state")
 var dead=make_sim();step(dead,true);dead.parts[3].alive=false
 check(project(dead,"dead").status=="已失联","dead paid drill remains lost")
 var delivered=make_sim();step(delivered,true);delivered.parts[3].delivered=true
 check(project(delivered,"delivered").status=="已失联","delivered module remains outside pilot selection")
 var automatic=make_sim();automatic.parts[3].input_a=-1;step(automatic,true)
 check(project(automatic,"automatic").status=="已失联" and not View.state(automatic).get("hold_to_use",false),"automatic drill never receives a manual hold hint")
 var wired=make_sim();wired.parts[3].input_a=99;step(wired,true)
 check(project(wired,"wired").status=="已失联","wired drill retains original selection boundary")
 sim.pilot_device_id=99999
 check(project(sim,"missing").status=="已失联","missing selected module retains lost text")
 sim.pilot_device_id=3;sim.route.control_version="pilot-free-v1"
 check(project(sim,"legacy").is_empty(),"legacy route never adopts new drill projection")
func hud_checks() -> void:
 var hud=HUD.new();root.add_child(hud);await process_frame
 var actions:Array=[];hud.action_requested.connect(func(action,payload):actions.append([action,payload]))
 var sim=make_sim();step(sim)
 var route:Dictionary={"control_version":"pilot-free-v2","destination_name":"收件台","background_ground_y_m":0.0}
 var flight:Dictionary={"free_flight":true,"speed":2.0,"cargo_y":-8.0,"energy_remaining":80.0,"energy_capacity":100.0,"energy_fraction":.8,"flight_status":"running","selected_tool":View.state(sim),"destination_navigation":{"status":"running","charging":false,"cargo_screen":Vector2(600,360),"receiver_screen":Vector2(1400,360),"distance_m":100.0},"events":[]}
 for extent in [Vector2i(1280,720),Vector2i(1920,1080)]:
  root.size=extent;hud.set_art_frame(Rect2(Vector2.ZERO,Vector2(extent)))
  hud.render({"mode":"flight","control_version":"pilot-free-v2","activeorder":route,"flight":flight,"settings":{"reduced_motion":true}})
  for index in 3:await process_frame
  for gamepad in [false,true]:
   hud.set_input_device(gamepad)
   for status in [IDLE,WORKING,PARTIAL,"电量不足"]:
    flight.selected_tool.status=status
    var before:PackedByteArray=var_to_bytes(flight);hud.update_flight(flight)
    for index in 2:await process_frame
    check(hud.flight_labels.tool_state.text==status and hud.flight_labels.tool_keys.text==("Y 切换 · 按住 A" if gamepad else "Q 切换 · 按住 Space"),"held state and compact actual input hints: "+status+" "+str(extent)+" pad="+str(gamepad))
    check(var_to_bytes(flight)==before and actions.is_empty(),"HUD read-only update creates no source edit or action")
    var panel:Control=hud.content.get_node("SelectedFlightTool")
    for label in [hud.flight_labels.tool_name,hud.flight_labels.tool_state,hud.flight_labels.tool_keys]:
     check(panel.get_global_rect().grow(1).encloses(label.get_global_rect()),"flight text remains inside existing compact card")
    check(Rect2(Vector2.ZERO,Vector2(extent)).encloses(panel.get_global_rect()),"card remains inside viewport")
   # Preserve a stale positive paid ratio while exercising the actual control-clear boundary.
   step(sim,false);step(sim,true)
   var paid_before_clear:Dictionary=View.state(sim)
   sim.set_pilot_input(0,false,false)
   flight.selected_tool=paid_before_clear;flight.paused=true;hud.update_flight(flight)
   check(sim.parts[3].drill_power_ratio>0.0 and hud.flight_labels.tool_state.text=="已暂停","paused held card never mistakes retained paid tick for current motor activity")
   flight.selected_tool=View.state(sim);hud.update_flight(flight)
   check(hud.flight_labels.tool_state.text=="已暂停","fresh paused projection stays paused after focus-style control clear")
   flight.paused=false;hud.update_flight(flight)
   check(hud.flight_labels.tool_state.text==IDLE and sim.parts[3].drill_power_ratio>0.0,"resume before next tick shows idle despite retained paid ratio")
   step(sim,false);flight.selected_tool=View.state(sim);hud.update_flight(flight)
   check(hud.flight_labels.tool_state.text==IDLE and sim.parts[3].drill_power_ratio==0.0,"resume after unheld tick remains idle")
   step(sim,true);flight.selected_tool=View.state(sim);hud.update_flight(flight)
   check(hud.flight_labels.tool_state.text==WORKING,"fresh held paid tick after resume restores running copy")
   sim.set_free_flight_input(0,0,false,false,3);flight.selected_tool=View.state(sim);hud.update_flight(flight)
   check(hud.flight_labels.tool_state.text==IDLE and sim.parts[3].drill_power_ratio>0.0,"release after resume immediately retires stale running claim")
   step(sim,false)
   flight.selected_tool={"name":"位移器","direction":"→","status":"可用"};flight.paused=true;hud.update_flight(flight)
   check(hud.flight_labels.tool_state.text=="可用","pause override does not alter other-device presentation")
   flight.paused=false;hud.update_flight(flight)
   check(hud.flight_labels.tool_keys.text==("Y 切换 · A 使用" if gamepad else "Q 切换 · Space 使用") and hud.flight_labels.tool_state.text=="可用","other devices retain exact existing keys and ready text")
   flight.selected_tool=View.state(sim)
  flight.selected_tool={};hud.update_flight(flight)
  check(not hud.content.get_node("SelectedFlightTool").visible,"absent device never becomes a permanent tutorial card")
  flight.selected_tool=View.state(sim);flight.flight_status="failed";hud.update_flight(flight)
  check(not hud.content.get_node("SelectedFlightTool").visible,"terminal flight never exposes retained last-tick motor state as active")
  flight.flight_status="running"
 hud.render({"mode":"flight","control_version":"pilot-free-v1","activeorder":{"control_version":"pilot-free-v1"},"flight":flight})
 check(not hud.flight_labels.has("tool_keys"),"legacy HUD remains outside selected-device card")
 hud.free()
