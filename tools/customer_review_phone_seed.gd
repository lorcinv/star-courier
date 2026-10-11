extends SceneTree
## QA-only offline synthetic outcomes. Generates ordinary real economy saves;
## does not claim that these deliveries were played by a person or a controller.
const Econ=preload("res://scripts/economy.gd")
const Profile=preload("res://scripts/pilot_extreme_profile.gd")
func _initialize() -> void:
 if FileAccess.file_exists("user://savegame.json"):push_error("Fixture requires a fresh isolated user directory");quit(2);return
 var e=Econ.new();e.enable_extreme_mode();e.enable_story_mode()
 var design:Array=Profile.starter_design();var launcher:Array=Profile.starter_launcher();e.starter_stock(design,launcher)
 var settings:Dictionary={"volume":0.0,"reduced_motion":false,"pixel_density":"auto"}
 for unused in 16:
  var id:String=str(e.available_contracts()[0].contract_id)
  if not e.accept_contract(id).ok:quit(3);return
  e.mark_story_seen(id,id+"/accept");e.mark_cargo_loaded(id)
  if not e.begin_dispatch(design,launcher).ok:quit(4);return
  var integrity:float=1.0 if unused%3==0 else (.9 if unused%3==1 else .55)
  var elapsed:float=8.0 if unused%4<2 else float(e.active_contract().deadline)+4.0
  if not e.settle_contract_and_save(id,{"integrity":integrity,"energy_used":12.0,"ammo_cost":0.0,"repair_cost":0.0,"lost_cost":0.0},elapsed,unused%5!=4,design,launcher,settings).ok:quit(5);return
  e.mark_story_seen(id,id+"/result");e.mark_story_seen(id,id+"/return");e.close_day()
  if not e.next_day_and_save(design,launcher,settings).ok:quit(6);return
 print("PHONE_QA_FIXTURE synthetic_delivery_outcomes=true played_delivery=false day=",e.day," published=",e.customer_reviews().size());quit()
