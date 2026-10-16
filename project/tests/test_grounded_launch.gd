extends SceneTree
## Presentation registration and controller interruption gates. No physics-version
## or ledger changes. Native pointer/keyboard motion is validated separately.
const World=preload("res://scripts/world_view_2d.gd")
const Profile=preload("res://scripts/pilot_extreme_profile.gd")
const Sim=preload("res://scripts/pilot_extreme_simulation.gd")
var passed:int=0
var failed:int=0
func _initialize() -> void:run.call_deferred()
func check(ok:bool,label:String) -> void:
 if ok:passed+=1;print("PASS ",label)
 else:failed+=1;push_error(label)
func fresh_sim(design:Array):
 var sim=Sim.new();sim.configure(design,Profile.starter_launcher(),Profile.route(),3);return sim
func settle() -> void:
 await process_frame;await process_frame
func run() -> void:
 var vp=SubViewport.new();vp.size=Vector2i(960,540);root.add_child(vp)
 var world=World.new();vp.add_child(world);world.set_process(false);world.assembly_feedback.set_process(false)
 for design in [Profile.starter_design(),Profile.reinforced_design()]:
  world.show_design(design);world.focus("workshop",true)
  var before_bg:Dictionary=world.ascent_backdrop.debug_snapshot()
  var camera_start:Vector2=world.camera.position
  var sim=fresh_sim(design);var bodies:Array=sim.bodies.duplicate(true);var energy:float=sim.total_energy()
  world.start_flight(sim)
  check(world.workshop_root.visible and world.actors_root.visible and world.foreground_root.visible,"same physical shop remains visible at dispatch for "+str(design.size())+" modules")
  check(not world.ship_root.visible and world.flight_root.visible,"one live assembled representation replaces editor sprites")
  for p in design:
   check(world.flight_nodes["p"+str(p.id)].position.distance_to(world.assembly_origin+Vector2(p.x,p.y)*72)<.8,"same module starts on exact assembly cell: "+str(p.id))
  check(world.camera.position.distance_to(camera_start)<.8,"dispatch preserves the existing camera before transfer")
  var after_bg:Dictionary=world.ascent_backdrop.debug_snapshot()
  check(before_bg.sky_scroll==after_bg.sky_scroll and before_bg.city_scroll==after_bg.city_scroll and before_bg.cloud_scroll==after_bg.cloud_scroll,"shop/launch use identical ordinary-wrap parallax registration")
  check(world.sky_tiles.all(func(tile):return not tile.visible),"no mirrored legacy city sprites are shown")
  var pad=world.flight_nodes.launch_pad;var fixed:Array=[];var feet:int=0
  for node in pad.get_children():
   if node.has_meta("fixed_launcher_position"):fixed.append(node.position)
   if node.has_meta("floor_anchor"):
    check(is_equal_approx(node.get_meta("floor_anchor").y,world.SHOP_FLOOR_Y),"actual launcher support foot stays on shop deck")
    feet+=1
  check(feet==sim.launcher_parts.size(),"every actual launcher module has a generated grounded support")
  world.launch_transfer_progress=.5;world.show_flight(sim)
  check(sim.bodies==bodies and sim.total_energy()==energy and sim.elapsed==0.0,"transfer is presentation-only, never an altitude or energy mutation")
  world.launch_transfer_progress=1.0;world.show_flight(sim)
  var bottom:float=-INF
  for p in sim.parts.values():bottom=maxf(bottom,world.flight_nodes["p"+str(p.id)].position.y+72*.49)
  check(absf(bottom-world.CRADLE_CONTACT_Y)<.8,"whole craft underside contacts the generated pad deck")
  var cradle_left:float=INF;var cradle_right:float=-INF;var deck_grounded:bool=true
  for node in pad.get_children():
   if node is Sprite2D and str(node.get_meta("art_id",""))=="props/launch-cradle-pixel" and node.region_enabled:
    cradle_left=minf(cradle_left,node.position.x);cradle_right=maxf(cradle_right,node.position.x+node.region_rect.size.x)
    deck_grounded=deck_grounded and node.scale==Vector2.ONE and is_equal_approx(node.position.y+node.region_rect.size.y,world.SHOP_FLOOR_Y)
  check(cradle_left<=world.flight_origin.x+world._launch_bounds.position.x and cradle_right>=world.flight_origin.x+world._launch_bounds.end.x and deck_grounded,"actual unscaled cradle regions span the whole craft and stay on the deck")
  world.launch_age=.8;world.show_flight(sim)
  var at:int=0
  for node in pad.get_children():
   if node.has_meta("fixed_launcher_position"):
    check(node.position==fixed[at],"launcher remains bolted at ignition");at+=1
  for i in 120:sim.step(1.0/60.0)
  var physics_before:Array=sim.bodies.duplicate(true)
  world.settle_resumed_flight(sim)
  check(world.launch_transfer_progress==1.0 and world.launch_age==1.35 and world.smooth_center==world.target_center,"resumed presentation skips transfer and settles camera immediately")
  check(sim.bodies==physics_before,"resumed camera registration leaves deterministic physical state unchanged")
  world.leave_flight();await settle()
  check(world.flight_nodes.is_empty() and not world.effect_node.visible and world.shop_cradle.visible,"return clears live ship, effects and restores one grounded shop pad")
 world.queue_free();vp.queue_free();await settle()
 var game=load("res://scenes/main.tscn").instantiate();root.add_child(game);game.set_process(false);game.world.set_process(false)
 game.economy.accept_contract("D1-A");game.economy.mark_story_seen("D1-A","D1-A/accept");game.navigate("workshop")
 game.start_flight(true)
 check(game.launch_transfer_remaining>0.0 and game.sim.elapsed==0.0,"new dispatch begins with a finite unbilled transfer")
 game._process(.2);var remaining:float=game.launch_transfer_remaining;var position:Vector2=game.world.flight_nodes.p1.position
 game._set_paused(true);game._process(.3)
 check(game.launch_transfer_remaining==remaining and game.world.flight_nodes.p1.position==position and game.sim.elapsed==0.0,"pause freezes transfer and physics together")
 game._set_paused(false);game._process(remaining)
 check(game.launch_transfer_remaining==0.0 and game.launch_age==0.0 and game.sim.elapsed==0.0,"arrival rests on pad before charging starts")
 game._process(.69)
 check(game.sim.elapsed==0.0 and not game.launch_sfx_played,"charge cannot release physics or launch audio early")
 game._process(.04)
 check(game.sim.elapsed>0.0 and game.launch_sfx_played,"ignition releases the unchanged simulation once")
 check(not game.hud.flight_labels.status.text.contains("移送"),"completed transfer is no longer shown as current status")
 game.abort_flight()
 check(game.economy.credits==260 and game.economy.in_flight.is_empty(),"trial interruption cannot create a paid dispatch or debit")
 game.start_flight(true);game._process(.1);game._on_focus_exited()
 remaining=game.launch_transfer_remaining;game._process(.5)
 check(game.paused and game.launch_transfer_remaining==remaining and game.pilot_keys.is_empty(),"focus loss during transfer pauses and releases keys")
 game._on_focus_entered();game.abort_flight();game.start_flight(true);game._process(.1)
 game._action("settings",{"reduced_motion":true});game._process(.01)
 check(game.launch_transfer_remaining==0.0 and game.world.launch_transfer_progress==1.0 and game.sim.elapsed==0.0,"enabling reduced motion during transfer settles at the pad without skipping ignition")
 game.abort_flight();game.start_flight(true)
 check(game.launch_transfer_remaining==0.0 and game.world.launch_transfer_progress==1.0,"reduced-motion dispatch immediately reaches the same grounded final registration")
 game.abort_flight();game.queue_free();await settle()
 print("GROUNDED_LAUNCH_TESTS passed=",passed," failed=",failed);quit(1 if failed else 0)
