extends SceneTree
## Actual Title/Main/World/Economy, API-driven fictional profile. No hardware or
## novice-usability claim. No fixture receipt, teleport, energy grant or success flag.
## Default: buy one real drill, leave it on the shelf, fly the unchanged starter.
## Optional --with-drill: mount that paid unit using the real workshop controller.
const Econ=preload("res://scripts/economy.gd")
const Title=preload("res://scripts/demo_title.gd")
const Free=preload("res://scripts/pilot_free_profile_v1.gd")
const Ground=preload("res://scripts/pilot_free_ground_route_v1.gd")
const Simulator=preload("res://scripts/pilot_free_simulation_v1.gd")
const FACTORY="res://scripts/clerk_runtime_bootstrap_observed_v4.gd"
const CID="D1-A"
const LEDGER_KEYS=["credits","day","phase","jobs_today","deliveries","inventory","history","settled_ids","last_settlement","review_state","story_state"]
var passed:int=0
var failed:int=0
var title
var game
var with_drill:bool=false

func _initialize() -> void:run.call_deferred()
func check(ok:bool,label:String) -> bool:
 if ok:passed+=1;print("PASS ",label)
 else:failed+=1;push_error("FAIL "+label)
 return ok
func frames(count:int=2) -> void:
 for unused in count:await process_frame
func saved() -> Dictionary:return JSON.parse_string(FileAccess.get_file_as_string("user://savegame.json"))
func ledger() -> Dictionary:
 var state:Dictionary=saved();var result:Dictionary={}
 for key in LEDGER_KEYS:result[key]=state.get(key)
 return result
func close_title() -> void:
 game=null
 if is_instance_valid(title):root.remove_child(title);title.free()
 title=null;await frames(3)
func finish() -> void:
 await close_title()
 print("MAIN_FREE_CORE_LOOP_V2 mode=%s passed=%d failed=%d"%["paid_drill" if with_drill else "starter_detour",passed,failed])
 quit(1 if failed else 0)

func boot(new_game:bool) -> bool:
 title=Title.new();title.clerk_pose_bootstrap_script=load(FACTORY);root.add_child(title);await frames(3)
 if DisplayServer.get_name()=="headless":title._focus_entered()
 if not check(title._preview_ready,"real title presentation is ready"):return false
 if new_game:
  check(title.game==null and not FileAccess.file_exists("user://savegame.json"),"fresh title is read-only before New Game")
  title._set_setting("volume",0.0);title._set_setting("reduced_motion",true)
  title._request_new_game();await frames()
  if not check(title.screen=="prologue" and title.game==null,"New Game opens the real prologue before constructing Main"):return false
  title._finish_prologue()
 else:title._continue_game()
 var deadline:int=Time.get_ticks_msec()+15000
 while title.screen!="game" and not title._opening_failed and Time.get_ticks_msec()<deadline:await process_frame
 if not check(title.screen=="game" and is_instance_valid(title.game),"title hands ownership to actual Main after safe entry"):return false
 game=title.game;game.set_process(false);game.world.set_process(false)
 game._on_focus_entered()
 if is_instance_valid(root.gui_get_focus_owner()):root.gui_get_focus_owner().release_focus()
 return check(not game.economy.review_load_blocked and not game.entry_defer_controls,"Main startup validation and protected save committed")

func pump_until(predicate:Callable,label:String,max_ticks:int=1800) -> bool:
 # Advance real presentation/ownership APIs, with a bounded failure instead of
 # bypassing a blocked clerk/dialogue/loading owner. Main flight uses its own loop.
 for tick in max_ticks:
  if predicate.call():return check(true,label)
  game.world._process(1.0/60.0);game._process(1.0/60.0)
  if tick%30==0:await frames(1)
 return check(bool(predicate.call()),label)

func finish_story(beat:String) -> bool:
 if not await pump_until(func():return game._dialogue_is_open(),beat+" dialogue opens from the actual durable order"):return false
 if not check(str(game._active_story.get("dialogue_id",""))==CID+"/"+beat,"matching "+beat+" dialogue owns the modal"):return false
 game.dialogue.skip_conversation();await frames()
 return check(game.economy.story_conversation(CID,beat).is_empty(),beat+" completion is saved through the real dialogue signal")

func steer(input:Vector2) -> void:
 # Synthetic analog events enter the real controller owner. Invert its deadzone
 # so the requested normalized command matches the known physical-route fixture.
 var dz:float=game.courier_input.deadzone
 for axis in [JOY_AXIS_LEFT_X,JOY_AXIS_LEFT_Y]:
  var value:float=input.x if axis==JOY_AXIS_LEFT_X else input.y
  var event:=InputEventJoypadMotion.new();event.device=0;event.axis=axis
  event.axis_value=0.0 if is_zero_approx(value) else signf(value)*(dz+absf(value)*(1.0-dz))
  game.courier_input._input(event)
func toward(target:Vector2,speed:float=12.0) -> Vector2:
 var delta:Vector2=target-game.sim.cargo_position()
 return delta.normalized()*minf(speed,delta.length()*1.5)/float(game.sim.route.free_cruise_speed)

func exercise() -> void:
 if not await boot(true):return
 check(game.economy.flight_mode==Free.VERSION and game.economy.contracts.size()==2,"fresh New Game authors two free-flight orders")
 var offer:Dictionary=game.economy.contract_by_id(CID).duplicate(true)
 if not check(offer.get("control_version")==Free.VERSION and offer.get("free_ground_schema")==Ground.SCHEMA and Free.validation_error(offer).is_empty(),"first new offer is exact pilot-free-v1 / free-ground-choice-v1"):return
 var initial_credits:int=game.economy.credits
 var starter:Array=game.design.duplicate(true)
 game._action("focus_counter",null)
 if not await pump_until(func():return game.world.is_at_shop_counter(),"real clerk reaches counter"):return
 game._action("accept_contract",CID)
 if not check(game.economy.active_contract_id==CID and not game.economy.is_cargo_loaded() and game.economy.in_flight.is_empty(),"Main acceptance saves a real unloaded order before any dispatch"):return
 if not await finish_story("accept"):return
 if not await pump_until(func():return game.economy.is_cargo_loaded() and game.world.is_parcel_loaded(CID),"actual World loading callback commits the matching cargo"):return
 await frames()
 check(saved().active_contract_id==CID and bool(saved().contracts[0].cargo_loaded),"accepted/loaded state is durable before launch")
 game._action("focus_supply",null)
 var price:int=game.catalog.drill.price
 var before_stock:int=int(game.economy.inventory.get("drill",0))
 check(price==65 and initial_credits>=price and game.economy.phase=="day","daytime drill remains the real affordable 65-credit part")
 var advertised:bool=false
 for button in game.hud.content.find_children("*","Button",true,false):
  if button.get_meta("day_basic_kind","")=="drill":advertised=not button.disabled
 check(advertised,"actual daytime supply HUD exposes an enabled drill purchase")
 game._action("buy","drill")
 if not check(game.economy.credits==initial_credits-price and int(game.economy.inventory.get("drill",0))==before_stock+1,"Main purchase charges exact catalog price and adds one durable unit"):return
 check(int(saved().credits)==initial_credits-price and int(saved().inventory.drill)==before_stock+1,"paid purchase is already on disk")
 game._action("focus_workbench",null)
 var drill_id:int=-1
 if with_drill:
  game._action("select_catalog","drill");game.workshop_input.controller_begin()
  game.workshop_input.controller_step(Vector2i.RIGHT);game.workshop_input.controller_step(Vector2i.RIGHT);game.workshop_input.controller_confirm()
  var drills:Array=game.design.filter(func(p):return p.type=="drill")
  if not check(drills.size()==1 and drills[0].x==2 and drills[0].y==0,"real workshop mounts the paid drill in the forward socket"):return
  drill_id=int(drills[0].id)
 else:check(game.design==starter,"default detour keeps the fresh starter design unchanged; paid drill stays on shelf")
 game._action("dispatch",null)
 if not check(game.page=="flight" and game.sim is Simulator and not game.trial,"Main starts a formal live free-flight simulation"):return
 check(saved().in_flight.input_schema==Free.INPUT_SCHEMA and game.economy.in_flight.contract_id==CID,"formal launch persists the exact two-axis dispatch identity")
 var launch_credits:int=game.economy.credits
 var immutable_route:Dictionary=game.sim.route.duplicate(true)
 game.courier_input.synchronize();steer(Vector2.ZERO)
 var waypoints:Array=[Vector2(95,-14),Vector2(155,-14),Ground.DESTINATION]
 var waypoint:int=0
 # Diagnostic successor: original budget was 7200 Main ticks for both modes.
 # Main advances 1/60s per tick: 7200 = 120s; drill-only 12000 = 200s.
 # This changes the fixture timeout only, never route/simulator win rules.
 var flight_tick_budget:int=12000 if with_drill else 7200
 print("MAIN_FREE_TICK_BUDGET ",JSON.stringify({"original_main_ticks":7200,"main_ticks":flight_tick_budget,"main_step_seconds":1.0/60.0,"nominal_seconds":float(flight_tick_budget)/60.0}))
 for tick in flight_tick_budget:
  if game.sim.status!="running":break
  if with_drill:
   # The simple low-stick case from test_free_ground_choice_v1: no contact servo.
   steer(Ground.DESTINATION.normalized()*0.25)
  else:
   if waypoint<waypoints.size()-1 and game.sim.cargo_position().distance_to(waypoints[waypoint])<2.0:waypoint+=1
   steer(toward(waypoints[waypoint]))
  game._step_flight()
 steer(Vector2.ZERO)
 print("MAIN_FREE_PHYSICAL ",JSON.stringify({"mode":"paid_drill" if with_drill else "starter_detour","status":game.sim.status,"ticks":game.pilot_completed_ticks,"elapsed":game.sim.elapsed,"position":[game.sim.cargo_position().x,game.sim.cargo_position().y],"integrity":game.sim.telemetry.integrity,"energy_used":game.sim.telemetry.energy_used,"energy_remaining":game.sim.telemetry.energy_remaining,"rock_health":game.sim.obstacles[0].health,"drill_damage":game.sim.telemetry.drill_damage}))
 if not check(game.sim.status=="success" and game.pilot_completed_ticks>0,"actual Main command ticks physically deliver the parcel"):return
 check(game.sim.telemetry.energy_used>0.0 and game.sim.telemetry.energy_remaining>0.0 and game.sim.route==immutable_route,"delivery spends finite propulsion energy without mutating the authored route")
 if with_drill:check(game.sim.parts[drill_id].alive and game.sim.obstacles[0].health<=0.0 and game.sim.telemetry.drill_damage>0.0 and game.sim.telemetry.drill_energy_used>0.0,"mounted paid drill really cuts the rock and survives")
 else:check(game.sim.telemetry.integrity==1.0 and game.sim.telemetry.swept_contacts==0 and game.sim.obstacles[0].health==Ground.ROCK.health,"starter detour arrives intact without touching or deleting the rock")
 check(game.economy.credits==launch_credits and game.economy.history.is_empty(),"physical success alone has not invented a receipt or credit")
 game.finish_flight()
 if not check(game.page=="report" and game.report.success and game.economy.jobs_today==1 and game.economy.in_flight.is_empty(),"Main return commits one successful formal settlement"):return
 var receipt:Dictionary=game.economy.last_settlement.duplicate(true)
 var settled:Dictionary=ledger()
 _core_diagnostic_stage("authored-receipt-to-first-durable",{"last_settlement":receipt},settled,["last_settlement"])
 check(int(receipt.profit)>0 and game.economy.credits==launch_credits+int(receipt.profit) and game.economy.credits>initial_credits,"saved delivery income is positive even after the real drill purchase")
 check(int(receipt.income)-int(receipt.charged_costs)==int(receipt.profit) and int(receipt.charged_costs)<=30 and float(receipt.energy_j)>0.0,"receipt reconciles real costs, positive income and the declared charge cap")
 game.finish_flight();game.finish_flight()
 check(ledger()==settled and game.economy.history.size()==1 and game.economy.settled_ids.size()==1,"repeated Main return handler cannot pay or record the order twice")
 check(game.economy.customer_reviews().is_empty() and game.economy.review_state.pending.size()==1,"delivery captures one pending review, with no same-day publication")
 if not await finish_story("result"):return
 game.navigate("hub");await frames()
 if not await finish_story("return"):return
 check(game.economy.pending_story_returns().is_empty() and game.economy.credits==int(settled.credits) and game.economy.history.size()==1,"result and return dialogue consume their own beats without extra settlement")
 game._action("close_day",null)
 if not check(game.economy.phase=="night" and game.economy.customer_reviews().is_empty(),"closing the first day still does not publish tomorrow's review"):return
 game._action("next_day",null);await frames()
 var reviews:Array=game.economy.customer_reviews()
 if not check(game.economy.day==2 and reviews.size()==1 and game.economy.review_state.pending.is_empty(),"actual next-day action publishes the one earned review"):return
 check(str(reviews[0].settlement_id)==CID and int(reviews[0].published_day)==2,"published review belongs to the exact delivery and next morning")
 var next_morning:Dictionary=ledger()
 _core_diagnostic_stage("first-durable-to-next-morning-durable",settled,next_morning,["last_settlement"])
 print("MAIN_FREE_RECEIPT ",JSON.stringify({"opening_credits":initial_credits,"drill_price":price,"receipt":receipt,"saved_credits":game.economy.credits,"review":reviews[0]}))
 await close_title()
 if not await boot(false):return
 var continued_durable:Dictionary=ledger()
 print("MAIN_FREE_RESTART_SPLIT ",JSON.stringify({"parsed_ledger_variant_equal":continued_durable==next_morning,"authored_to_loaded_receipt_variant_equal":game.economy.last_settlement==receipt,"authored_to_loaded_receipt_exact_numeric_equal":Econ.Shape_equal(receipt,game.economy.last_settlement),"durable_to_loaded_receipt_variant_equal":next_morning.last_settlement==game.economy.last_settlement,"durable_to_loaded_receipt_exact_numeric_equal":Econ.Shape_equal(next_morning.last_settlement,game.economy.last_settlement)},"",true,true))
 _core_diagnostic_stage("next-morning-durable-to-continued-durable",next_morning,continued_durable,LEDGER_KEYS)
 _core_diagnostic_stage("next-morning-durable-to-continued-memory",next_morning,{"last_settlement":game.economy.last_settlement},["last_settlement"])
 _core_diagnostic_stage("authored-receipt-to-continued-memory",{"last_settlement":receipt},{"last_settlement":game.economy.last_settlement},["last_settlement"])
 # Preserve the original failed assertion verbatim until diagnostic evidence resolves its boundary.
 check(ledger()==next_morning and game.economy.last_settlement==receipt,"restart through actual Continue retains paid stock, money, receipt and review")
 check(game.economy.day==2 and game.economy.jobs_today==0 and game.economy.deliveries==1 and game.economy.customer_reviews().size()==1,"restart preserves next-morning progression without duplicate delivery or review")
 check(game.economy.story_conversation(CID,"result").is_empty() and game.economy.story_conversation(CID,"return").is_empty(),"restart never replays completed result or return beats")

func run() -> void:
 if OS.get_environment("XDG_DATA_HOME").is_empty() or FileAccess.file_exists("user://savegame.json") or FileAccess.file_exists("user://savegame.backup.json"):
  printerr("Refusing an existing/unisolated profile. Use a NEW empty XDG_DATA_HOME.");quit(2);return
 with_drill="--with-drill" in OS.get_cmdline_user_args()
 await exercise()
 await finish()

# Temporary exact-value diagnostics. No epsilon/rounding and no assertion change.
func _core_diagnostic_stage(stage:String,left:Dictionary,right:Dictionary,fields:Array) -> void:
 for field in fields:
  var counts:Dictionary={"numeric_type_only":0,"value_changes":0,"type_changes":0,"shape_changes":0}
  var numeric_examples:Array=[];var changed_examples:Array=[]
  _core_diagnostic_diff(left.get(field),right.get(field),field,counts,numeric_examples,changed_examples)
  print("MAIN_FREE_DIAGNOSTIC ",JSON.stringify({"stage":stage,"field":field,"variant_equal":left.get(field)==right.get(field),"exact_numeric_equal":Econ.Shape_equal(left.get(field),right.get(field)),"counts":counts,"numeric_examples":numeric_examples,"changed_examples":changed_examples},"",true,true))

func _core_diagnostic_diff(a:Variant,b:Variant,path:String,counts:Dictionary,numeric:Array,changed:Array) -> void:
 var a_number:bool=a is int or a is float
 var b_number:bool=b is int or b is float
 if a_number and b_number:
  if a==b:
   if typeof(a)!=typeof(b):
    counts.numeric_type_only+=1
    if numeric.size()<6:numeric.append(_core_diagnostic_value(path,a,b))
  else:
   counts.value_changes+=1
   if changed.size()<16:changed.append(_core_diagnostic_value(path,a,b))
  return
 if a is Dictionary and b is Dictionary:
  for key in a:
   if b.has(key):_core_diagnostic_diff(a[key],b[key],path+"."+str(key),counts,numeric,changed)
   else:
    counts.shape_changes+=1
    if changed.size()<16:changed.append({"path":path+"."+str(key),"change":"removed_key"})
  for key in b:
   if not a.has(key):
    counts.shape_changes+=1
    if changed.size()<16:changed.append({"path":path+"."+str(key),"change":"added_key"})
  return
 if a is Array and b is Array:
  if a.size()!=b.size():
   counts.shape_changes+=1
   if changed.size()<16:changed.append({"path":path,"change":"array_size","left":a.size(),"right":b.size()})
  for index in mini(a.size(),b.size()):_core_diagnostic_diff(a[index],b[index],path+"["+str(index)+"]",counts,numeric,changed)
  return
 if typeof(a)!=typeof(b):
  counts.type_changes+=1
  if changed.size()<16:changed.append(_core_diagnostic_value(path,a,b))
 elif a!=b:
  counts.value_changes+=1
  if changed.size()<16:changed.append(_core_diagnostic_value(path,a,b))

func _core_diagnostic_value(path:String,a:Variant,b:Variant) -> Dictionary:
 var value:Dictionary={"path":path,"left_type":type_string(typeof(a)),"right_type":type_string(typeof(b)),"left":a,"right":b}
 if a is int or a is float:value.left_float64_bits=PackedFloat64Array([float(a)]).to_byte_array().hex_encode()
 if b is int or b is float:value.right_float64_bits=PackedFloat64Array([float(b)]).to_byte_array().hex_encode()
 return value
