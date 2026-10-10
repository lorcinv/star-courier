extends SceneTree
## Actual production controller/HUD, synthetic physical-window input. The native
## mouse/keyboard acceptance run remains a separate gate, never implied here.
const Main=preload("res://scenes/main.tscn")
const Profile=preload("res://scripts/workshop_profile.gd")
var game
var passed:int=0
var failed:int=0
func _initialize() -> void:run.call_deferred()
func check(ok:bool,label:String) -> void:
 if ok:passed+=1;print("PASS ",label)
 else:failed+=1;push_error(label)
func disk() -> Dictionary:return JSON.parse_string(FileAccess.get_file_as_string("user://savegame.json"))
func settle() -> void:
 for i in 4:await process_frame
 if is_instance_valid(game):
  for tween in game.hud._motion_tweens.values():
   if tween.is_valid():tween.custom_step(1.0)
func fresh(erase:bool=true) -> void:
 if is_instance_valid(game):game.queue_free();await settle()
 if erase:
  for file in ["savegame.json","savegame.backup.json","savegame.tmp"]:
   if FileAccess.file_exists("user://"+file) or DirAccess.dir_exists_absolute("user://"+file):DirAccess.remove_absolute("user://"+file)
 game=Main.instantiate();root.add_child(game);game.set_process(false);game.world.set_process(false);await settle()
func point(cell:Vector2i) -> Vector2:return game.world._screen_point(game.world.assembly_origin+Vector2(cell)*72)
func mouse(at:Vector2,down:bool,which:int=MOUSE_BUTTON_LEFT) -> void:
 var event:=InputEventMouseButton.new();event.position=at;event.global_position=at;event.button_index=which;event.pressed=down
 event.button_mask=MOUSE_BUTTON_MASK_LEFT if down and which==MOUSE_BUTTON_LEFT else 0
 root.push_input(event);await settle()
func motion(at:Vector2,held:bool) -> void:
 var event:=InputEventMouseMotion.new();event.position=at;event.global_position=at;event.button_mask=MOUSE_BUTTON_MASK_LEFT if held else 0
 root.push_input(event);await settle()
func click_cell(cell:Vector2i) -> void:
 var at:Vector2=point(cell);await motion(at,false);await mouse(at,true);await mouse(at,false)
func drag_cell(from:Vector2i,to:Vector2i) -> void:
 var a:Vector2=point(from);await motion(a,false);await mouse(a,true);var b:Vector2=point(to);await motion(b,true);await mouse(b,false)
func key(code:int,ctrl:bool=false) -> void:
 for down in [true,false]:
  var event:=InputEventKey.new();event.keycode=code;event.physical_keycode=code;event.pressed=down;event.ctrl_pressed=ctrl
  root.push_input(event);await settle()
func at(cell:Vector2i) -> Dictionary:
 for p in game.design:
  if Vector2i(int(p.x),int(p.y))==cell:return p
 return {}
func button_named(name:String) -> Button:
 return game.hud.content.find_child(name,true,false) as Button
func model() -> Dictionary:
 return {"design":game.design.duplicate(true),"launcher":game.launcher.duplicate(true),"inventory":game.economy.inventory.duplicate(true),"story":game.economy.story_state.duplicate(true),"settled":game.economy.settled_ids.duplicate(true)}
func run() -> void:
 if OS.get_environment("XDG_DATA_HOME").is_empty():quit(2);return
 root.size=Vector2i(1280,800);await fresh()
 var before:Dictionary=model();game._action("workshop_upgrade",1)
 check(game.economy.workshop_tier==0 and game.economy.credits==260,"daytime direct purchase cannot bypass the night guard")
 game._action("close_day",null);await settle()
 var buy:Button=button_named("WorkshopUpgrade")
 check(buy!=null and not buy.disabled and buy.text.contains("13 × 7") and buy.text.contains("180"),"night UI quotes the exact next tier and its price")
 var center:Vector2=buy.get_global_rect().get_center();await motion(center,false);await mouse(center,true);await mouse(center,false)
 check(game.economy.workshop_tier==1 and game.economy.credits==80 and int(disk().workshop_tier)==1,"real GUI purchase commits one tier and one exact debit to disk")
 check(model()==before,"workshop purchase preserves parts, IDs, stock, story and settlement ledger")
 check(game.world.workshop_tier==1 and game.world.assembly_origin==Profile.assembly_origin(1),"saved upgrade drives the physical expanded workbay")
 game._action("workshop_upgrade",1);game._action("workshop_upgrade",2)
 check(game.economy.workshop_tier==1 and game.economy.credits==80,"duplicate target and insufficient funds cannot buy another tier")
 await fresh(false)
 check(game.economy.workshop_tier==1 and game.economy.credits==80 and game.world.workshop_tier==1,"restart retains paid bounds without charging again")
 game.navigate("workshop");game.chosen_type="beam";game.hud.palette_open=false;game.render();game.workshop_input.fit();await settle()
 var inventory:Dictionary=game.economy.inventory.duplicate(true);var count:int=game.design.size();var undo:int=game.undo_history.size()
 await click_cell(Vector2i(8,-4))
 check(game.design.size()==count+1 and at(Vector2i(8,-4)).get("type","")=="beam","physical-window release places a spare into the newly unlocked far cell")
 check(game.undo_history.size()==undo+1 and game.economy.inventory==inventory,"placement records one undo without changing owned inventory")
 var installed:Dictionary=at(Vector2i(8,-4)).duplicate(true)
 await mouse(point(Vector2i(8,-4)),false)
 check(game.design.size()==count+1 and game.undo_history.size()==undo+1,"orphaned repeat release cannot duplicate a placement")
 await drag_cell(Vector2i(8,-4),Vector2i(7,-3))
 var moved:Dictionary=at(Vector2i(7,-3)).duplicate(true);moved.x=installed.x;moved.y=installed.y
 check(moved==installed and at(Vector2i(8,-4)).is_empty(),"drag relocation preserves actual part ID, parameters, rotation and wiring")
 check(game.undo_history.size()==undo+2 and game.economy.inventory==inventory,"relocation commits exactly once with no stock mutation")
 await key(KEY_Z,true)
 check(at(Vector2i(8,-4))==installed and at(Vector2i(7,-3)).is_empty(),"real keyboard undo restores the original cell and same part")
 var baseline:Array=game.design.duplicate(true)
 var source:Vector2=point(Vector2i(8,-4));await mouse(source,true);await motion(point(Vector2i(6,-3)),true)
 game._on_focus_exited();game._on_focus_entered();await mouse(point(Vector2i(6,-3)),false)
 check(game.design==baseline and game.workshop_input.camera.gesture.is_empty(),"focus loss cancels a drag instead of committing on return")
 await mouse(source,true);await motion(point(Vector2i(6,-3)),true);root.size=Vector2i(1920,1080);await settle();await mouse(point(Vector2i(6,-3)),false)
 check(game.design==baseline and game.workshop_input.camera.gesture.is_empty(),"resize cancels the old coordinate-space drag")
 game.workshop_input.fit();await settle()
 source=point(Vector2i(8,-4));await mouse(source,true);await motion(point(Vector2i(6,-3)),true)
 game.hud.settings_open=true;game.hud.render(game.hud.state);game.workshop_input.tick();await settle();game.hud.settings_open=false;game.hud.render(game.hud.state);await mouse(point(Vector2i(6,-3)),false)
 check(game.design==baseline and game.workshop_input.camera.gesture.is_empty(),"modal interruption cancels pending relocation")
 game.workshop_input.fit();await settle();var camera:Vector2=game.world.camera.position;var zoom:Vector2=game.world.camera.zoom
 game.render();await settle()
 check(game.world.camera.position==camera and game.world.camera.zoom==zoom,"ordinary controller render preserves fitted workshop camera")
 # Force an ordinary filesystem failure only in this isolated test save path.
 game.navigate("supply");game.economy.credits=1000;game.save_game();var saved:Dictionary=disk()
 DirAccess.make_dir_absolute("user://savegame.tmp");game._action("workshop_upgrade",2)
 check(game.economy.workshop_tier==1 and game.economy.credits==1000 and game.world.workshop_tier==1,"failed atomic save rolls back both debit and displayed tier")
 check(disk()==saved,"failed upgrade leaves the previous valid save intact")
 DirAccess.remove_absolute("user://savegame.tmp");game._action("workshop_upgrade",2)
 check(game.economy.workshop_tier==2 and game.economy.credits==580 and int(disk().workshop_tier)==2,"retry after storage recovery commits exactly one second-tier cost")
 game._action("workshop_upgrade",2)
 check(game.economy.credits==580,"repeated second-tier confirmation cannot debit twice")
 await fresh(false)
 check(game.economy.workshop_tier==2 and at(Vector2i(8,-4)).get("id",-1)==installed.id,"expanded design and tier survive another actual main restart")
 # An old save may contain a design larger than today's paid bounds. Preserve it.
 saved=disk();saved.version=4;saved.erase("workshop_tier");saved.design.append(game.part(99,"beam",12,-5))
 var file=FileAccess.open("user://savegame.json",FileAccess.WRITE);file.store_string(JSON.stringify(saved,"",true,true));file.close()
 await fresh(false)
 check(game.economy.workshop_tier==0 and not at(Vector2i(12,-5)).is_empty() and not at(Vector2i(8,-4)).is_empty(),"legacy migration never silently crops valid retained outlying parts")
 check(game.hud.toast_label.text.contains("已保留"),"legacy outlying design is explained to the player")
 game.navigate("workshop");game.hud.palette_open=false;game.render();game.workshop_input.fit();await settle()
 await click_cell(Vector2i(12,-5));check(game.selected_id==99,"retained outside part remains selectable in the real controller")
 await key(KEY_R);check(int(at(Vector2i(12,-5)).rot)==1,"retained outside part still rotates without paid-area corruption")
 await drag_cell(Vector2i(12,-5),Vector2i(3,2))
 check(at(Vector2i(3,2)).get("id",-1)==99 and at(Vector2i(12,-5)).is_empty(),"retained outside part can be recovered into an unlocked cell")
 game._configure_flight(true,game.ExtremeProfile.starter_design(),game.ExtremeProfile.starter_launcher(),game.ExtremeProfile.route())
 game._process(.1);game._set_paused(true);game._process(.1)
 check(not is_instance_valid(game.hud._launch_layer) or not game.hud._launch_layer.visible,"paused transfer cannot hold a central ribbon over the assembled craft")
 game._set_paused(false);game._process(game.launch_transfer_remaining+.2)
 check(is_instance_valid(game.hud._launch_layer) and game.hud._launch_layer.visible and game.hud._launch_phase=="charge","grounded charge still restores the visible launch stamp")
 game.queue_free();await settle()
 print("WORKSHOP_CONTROLLER passed=",passed," failed=",failed," native_input=false");quit(1 if failed else 0)
