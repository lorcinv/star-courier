extends SceneTree
var failed:int=0
var passed:int=0
func check(condition:bool,message:String) -> void:
 if condition:passed+=1;print("PASS ",message)
 else:failed+=1;push_error("FAIL "+message)
func _initialize() -> void:run.call_deferred()
func close_story(scene) -> void:
 # This synchronous legacy fixture advances the now-real clerk return before
 # closing a queued conversation. It must not bypass the production guard or
 # assume that a result/next customer can teleport the clerk to the counter.
 # Dedicated story/controller tests exercise the real input and persistence.
 for i in 1800:
  if scene.dialogue.is_open() or scene._pending_story.is_empty() or scene._story_save_attempted:break
  scene.world._process(1.0/60.0)
  scene.world.assembly_feedback._process(1.0/60.0)
  scene._try_pending_story()
 if scene.dialogue.is_open():scene.dialogue.skip_conversation()
func fly(scene) -> void:
 var iterations:int=0
 var held:int=0
 while scene.sim.status=="running" and iterations<12000:
  # Deterministic binary keyboard-intent fixture, not an autonomous game mode.
  if iterations%12==0:held=scene._smoke_guidance_axis()
  scene.pilot_keys.clear()
  if held!=0:scene.pilot_keys[KEY_S if held>0 else KEY_W]=true
  scene._step_flight();iterations+=1
 scene.finish_flight()
func run() -> void:
 var scene=load("res://scenes/main.tscn").instantiate();root.add_child(scene);await process_frame
 check(scene.catalog.size()==27,"26 parts including contact drill plus mandatory cargo")
 check(scene.design.size()==8 and scene.launcher.size()==3,"compact eight-part craft and separate three-part launcher")
 scene.navigate("workshop");scene.selected_id=4;scene.rotate_part()
 check(scene.design[3].rot==1,"keyboard rotation edits actual design")
 scene.undo_assembly();check(scene.design[3].rot==0,"undo restores rotation")
 scene.design[3].rot=0;scene.design[3].param=7;scene.design[3].input_a=2;scene.save_blueprint();scene.design[3].param=20;scene.load_blueprint()
 check(scene.design[3].param==7 and scene.design[3].input_a==2,"blueprint restores typed parameter and wire")
 scene.selected_id=2;scene.remove_part()
 check(scene.design.size()==7 and scene.design[2].input_a==-1,"remove clears dangling control references")
 scene.undo_assembly();check(scene.design.size()==8 and scene.design[3].input_a==2,"undo removal restores module and wires")
 scene.design[3].input_a=-1;scene.design[3].param=28;scene.design[5].param=28
 scene.start_flight(true);check(scene.page!="flight","trial requires an accepted real cargo specification")
 var first:String=scene.economy.available_contracts()[0].contract_id
 scene._action("accept_contract",first)
 check(scene.economy.active_contract_id==first and scene.page=="hub","counter acceptance commits unique client")
 close_story(scene)
 var before:int=scene.economy.credits
 scene.start_flight(true);fly(scene)
 check(scene.sim.status=="success","starter pilot first-route delivery with recorded keyboard intent")
 check(scene.economy.credits==before and scene.economy.history.is_empty(),"trial has no financial settlement")
 check(scene.report.has("estimated_profit") and scene.report.estimated_profit>0,"trial visibly estimates actual pilot delivery profit")
 scene.design[3].param=22;scene.design[5].param=22;scene.start_flight(true);fly(scene)
 var trials:Dictionary=scene.economy.last_trials[first]
 check(absf(trials.latest.energy_j-trials.previous.energy_j)>.01 or absf(trials.latest.elapsed-trials.previous.elapsed)>.01,"retained trials expose measurable real thrust-budget change")
 check(scene.report.comparison["本次改动"].contains("#4") and scene.report.comparison["本次改动"].contains("#6") and scene.report.has("estimated_profit"),"comparison identifies both retuned engines and measured estimate")
 scene.start_flight(false);check(not scene.economy.in_flight.is_empty(),"formal dispatch persists commitment")
 fly(scene)
 check(scene.economy.history.size()==1 and scene.economy.deliveries==1,"delivery settles once")
 var h=scene.economy.last_settlement
 check(h.profit==h.income-h.energy-h.ammo-h.repairs-h.lost,"cost categories exactly sum to profit")
 check(h.profit==trials.latest.estimated_profit,"same-design matching formal result agrees with non-mutating trial estimate")
 close_story(scene)
 scene.finish_flight();check(scene.economy.history.size()==1,"repeated callback cannot settle twice")
 scene.start_flight(false);check(scene.page!="flight","settled contract cannot be relaunched")
 scene._action("next_contract",null);scene._action("accept_contract",str(scene.economy.available_contracts()[0].contract_id));close_story(scene);scene.start_flight(true);scene.abort_flight()
 check(scene.page=="report" and scene.economy.history.size()==1,"aborted trial gives diagnosis without billing")
 scene.start_flight(false);scene.abort_flight()
 check(scene.page=="report" and scene.economy.history.size()==2,"formal abort bills exactly one failed dispatch")
 close_story(scene)
 scene._action("close_day",null);check(scene.economy.phase=="night" and scene.page=="supply","closing shop opens night procurement")
 var count:int=int(scene.economy.inventory.get("beam",0));var money:int=scene.economy.credits
 scene._action("buy","beam");check(int(scene.economy.inventory.beam)==count+1 and scene.economy.credits==money-10,"night shelf purchase changes stock and money")
 scene.economy.credits=400;scene._action("upgrade","battery");check(scene.economy.research==1 and scene.economy.credits==260,"charging upgrade has explicit140 cost")
 scene._action("next_day",null);check(scene.economy.day==2 and scene.economy.jobs_today==0 and scene.page=="hub","next morning refreshes finite customers")
 scene.save_game();var e=load("res://scripts/economy.gd").new();var data=e.load_state()
 check(e.credits==scene.economy.credits and data.design.size()==scene.design.size(),"save reload retains business and hardware")
 scene.economy.designs.workbench.design.append(scene.part(88,"beam",3,1));scene.next_id=20;scene.load_blueprint()
 check(scene.next_id>=89,"loaded blueprint reserves all restored module IDs")
 print("INTEGRATION_TESTS passed=",passed," failed=",failed)
 scene.queue_free();await process_frame;await process_frame;quit(1 if failed else 0)
