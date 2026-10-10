extends SceneTree
## Real v3 simulator-to-presentation contract. Synthetic malformed telemetry
## tests are labeled; no keyboard or delivery acceptance is claimed.
const World=preload("res://scripts/world_view_2d.gd")
const HUD=preload("res://scripts/game_hud.gd")
const Sim=preload("res://scripts/pilot_extreme_simulation.gd")
const Profile=preload("res://scripts/pilot_extreme_profile.gd")
const Expanded=preload("res://scripts/parts_expanded.gd")
const Probe=preload("res://tools/extreme_build_probe.gd")
var passed:int=0
var failed:int=0
var world
var hud
func _initialize() -> void:run.call_deferred()
func check(value:bool,title:String) -> void:
 if value:passed+=1;print("PASS ",title)
 else:failed+=1;push_error("FAIL "+title)
func settle() -> void:
 for i in 6:await process_frame
 if is_instance_valid(hud):
  for tween in hud._motion_tweens.values():
   if tween.is_valid():tween.custom_step(1)
 await process_frame
func fresh(design:Array=[]):
 var sim=Sim.new();sim.configure(Profile.starter_design() if design.is_empty() else design,[],Probe.open_route(),42);return sim
func live_data(sim) -> Dictionary:
 var data:Dictionary=sim.telemetry.duplicate(true)
 data.elapsed=sim.elapsed;data.distance=sim.cargo_position().x;data.total_distance=520;data.integrity=sim.telemetry.get("integrity",1)
 return data
func present(sim) -> void:
 world.start_flight(sim);world.launch_age=2;world.show_flight(sim)
 hud.render({"mode":"flight","control_version":"pilot-v3","activeorder":{"name":"极限装配 · 受控试飞","distance":520,"deadline":48,"time_limit":70},"flight":live_data(sim),"settings":{"reduced_motion":true}})
func text_content() -> String:
 var result:String=""
 for label in hud.content.find_children("*","Label",true,false):result+=label.text+"\n"
 return result
func drill_fixture(active:bool=true):
 var sim=fresh([Profile.part(1,"cargo",0),Profile.part(2,"battery",-1),Profile.part(3,"drill",1,0,{"input_a":-2})])
 sim.obstacles.append({"position":sim.part_world_position(3)+Vector2(1.255,0),"radius":.8,"health":80.0,"mass":20.0,"type":"rock","velocity":Vector2.ZERO})
 sim.set_pilot_input(0,false,active);sim.step(1.0/120.0);return sim
func check_panel_bounds(extent:Vector2i) -> void:
 root.size=extent;hud.set_art_frame(Rect2(Vector2.ZERO,Vector2(extent)));await settle()
 var panel:Control=hud.flight_labels.energy.get_parent().get_parent()
 check(panel.position==Vector2(20,198) and panel.size==Vector2(260,112),"v3 compact resource column at "+str(extent))
 var fit:bool=true
 for label in panel.find_children("*","Label",true,false):fit=fit and panel.get_global_rect().encloses(label.get_global_rect()) and label.get_minimum_size().x<=label.size.x
 check(fit,"v3 charge, thrust, integrity and circuit text fits at "+str(extent))
 var right:=Rect2(hud._size.x-304,0,304,hud._size.y*.5)
 var clear:bool=true
 for node in hud.content.get_children():
  if node is PanelContainer and node.visible:clear=clear and not node.get_rect().intersects(right)
 check(clear,"incoming top-right hazard corridor remains clear at "+str(extent))
 var band:=Rect2(0,hud._size.y*.44,hud._size.x,hud._size.y*.22)
 check(not panel.get_rect().intersects(band),"v3 resources stay outside tall craft band at "+str(extent))
 hud.update_launch(.4,"charge");await settle()
 check(hud._launch_layer.position.y==108 and not panel.get_global_rect().intersects(hud._launch_layer.get_global_rect()),"charge ribbon clears resources and preserves tall craft clearance at "+str(extent))
 hud.update_launch(1,"done");await settle()
func run() -> void:
 root.content_scale_mode=Window.CONTENT_SCALE_MODE_DISABLED;root.size=Vector2i(1280,720)
 var viewport:=SubViewport.new();viewport.size=Vector2i(1280,720);root.add_child(viewport)
 world=World.new();world.catalog=Expanded.catalog();world.catalog.cargo=Expanded.cargo_spec();viewport.add_child(world)
 hud=HUD.new();root.add_child(hud)
 var design:Array=[];var index:int=0
 for kind in world.catalog:
  design.append(Profile.part(index+1,kind,index%9-4,index/9-1));index+=1
 world.show_design(design)
 check(Expanded.catalog().size()==26 and design.size()==27,"expanded art coverage is26 functional modules plus cargo")
 var icon_parent:=Control.new();root.add_child(icon_parent)
 for p in design:
  var sprite:Sprite2D=world.ship_root.get_node("Part"+str(p.id))
  check(sprite.texture!=null and sprite.texture.get_size()==Vector2(72,72),"generated72px world texture: "+p.type)
  var icon=hud._part_icon(icon_parent,p.type,Vector2(48,48))
  check(icon is TextureRect and icon.texture!=null,"generated HUD texture: "+p.type)
 check(world.missing_assets.is_empty() and hud._missing_icon_reports.is_empty(),"all27 module/cargo sprites resolve without fallback")
 icon_parent.queue_free()
 var sim=fresh();sim.set_pilot_input(0,true,false)
 for i in 120:sim.step(1.0/120.0)
 present(sim);await settle()
 check(hud._pilot_mode() and hud._ascent_mode() and hud._extreme_mode(),"v3 selects pilot and ascent presentation")
 check(world.ascent_backdrop.visible and not world.flight_backdrop.visible,"v3 renders actual ascent route layers")
 check(hud.flight_labels.thrust.text.contains("全功率") and hud.flight_labels.thrust.text.contains("%.1f"%sim.telemetry.thrust_actual),"full-power caption includes actual funded nozzle output")
 check(hud.flight_labels.energy.text.contains(hud._flight_energy(sim.telemetry.energy_remaining)),"remaining charge is real simulator telemetry")
 check(text_content().contains("Shift  全功率") and not text_content().contains("22 m/s") and not text_content().contains("30 N"),"v3 controls never promise legacy target or global thrust cap")
 for p in sim.parts.values():
  if p.type=="thruster":check(world.flight_nodes["p"+str(p.id)].get_node("Exhaust").visible==bool(p.pilot_throttle>.001),"engine plume follows actual funded throttle: "+str(p.id))
 var bodies_before:Array=sim.bodies.duplicate(true);var energy_before:float=sim.total_energy()
 for i in 10:world.show_flight(sim,true);hud.update_flight(live_data(sim))
 check(sim.bodies==bodies_before and sim.total_energy()==energy_before,"paused presentation does not change physical state or spend energy")
 var engine:Dictionary=sim.parts[4] if sim.parts.get(4,{}).get("type","")=="thruster" else {}
 for p in sim.parts.values():
  if p.type=="thruster":engine=p;break
 engine.erase("pilot_throttle");engine.active=true;world.show_flight(sim)
 check(not world.flight_nodes["p"+str(engine.id)].get_node("Exhaust").visible,"missing pilot throttle never borrows another circuit's charge")
 var drilling=drill_fixture();present(drilling);await settle()
 var drill:Sprite2D=world.flight_nodes.p3;var meter=drill.get_node("PoweredDrillCue")
 check(drilling.telemetry.drill_energy_used>0 and meter.visible and meter.power>0,"drill motor ring is driven by paid drill_power_ratio")
 check(drill.texture.resource_path.ends_with("drill-pixel.png") and drill.texture.get_size()==Vector2(72,72),"drill keeps generated registered72px sprite")
 check(drilling.telemetry.drill_contacts>0 and world.visible_effect_count>0,"real drill contact renders bounded existing particle")
 check(world._effect_pool[0].get_meta("effect_type","")=="drill" and world._effect_pool[0].position==(world.flight_origin+drilling.effects[0].from*72).round(),"contact particle uses actual cutter contact coordinates")
 var pool_count:int=world.effect_node.get_child_count()
 for i in 180:world.show_flight(drilling)
 check(world.effect_node.get_child_count()==pool_count and pool_count==32,"repeated drill frames reuse fixed32-sprite pool")
 world.reduced_motion=true;world.show_flight(drilling)
 check(world._effect_pool[0].modulate.a<=.551 and is_equal_approx(drill.rotation,float(drilling.bodies[0].angle)+float(drilling.parts[3].local_angle)),"reduced-motion contact is quiet and drill housing follows physics")
 var saved_effects:Array=drilling.effects.duplicate(true)
 drilling.effects=[]
 for i in 192:drilling.effects.append({"type":"drill","from":Vector2(i,0),"to":Vector2(i,1),"ttl":.12})
 world.show_flight(drilling)
 check(world.visible_effect_count==32 and world.effect_node.get_child_count()==32,"synthetic192-contact burst cannot expand the fixed effect pool")
 drilling.effects=saved_effects
 var partial=drill_fixture(false);partial.parts[2].energy=.25;partial.set_pilot_input(0,false,true);partial.step(1.0/120.0);present(partial)
 check(is_equal_approx(world.flight_nodes.p3.get_node("PoweredDrillCue").power,.5),"partial charge shows exactly half funded drill motor power")
 partial.step(1.0/120.0);world.show_flight(partial)
 check(not world.flight_nodes.p3.get_node("PoweredDrillCue").visible,"exhausted drill charge turns motor ring off on the next real tick")
 var off=drill_fixture(false);present(off)
 check(not world.flight_nodes.p3.get_node("PoweredDrillCue").visible and world.visible_effect_count==0,"disabled drill has no paid motor or false contact cue")
 off.parts[3].drill_power_ratio=NAN;world.show_flight(off)
 check(not world.flight_nodes.p3.get_node("PoweredDrillCue").visible,"unknown drill power remains visually off")
 var shield=fresh([Profile.part(1,"cargo",0),Profile.part(2,"shield",-1,1,{"input_a":-2}),Profile.part(3,"battery",-1)])
 shield.set_pilot_input(0,false,true);present(shield);await settle()
 check(hud.flight_labels.impact.text.is_empty(),"merely mounting or enabling shield gives no absorption cue")
 shield._damage_part(shield.parts[1],20,"collision");hud.update_flight(live_data(shield))
 check(hud.flight_labels.impact.text.contains("13.0 HP") and hud.flight_labels.impact.text.contains("20 J"),"actual funded shield impact reports HP and real rounded joules")
 check(hud.flight_labels.impact.get_theme_color("font_color")==HUD.TEAL,"funded absorption gives a steady short receipt highlight")
 var stable:Dictionary=live_data(shield);stable.elapsed=1;hud.update_flight(stable)
 check(hud.flight_labels.impact.get_theme_color("font_color")==HUD.DIM and hud.flight_labels.impact.text.contains("13.0 HP"),"shield cue settles into truthful cumulative receipt without flashing")
 stable.impact_absorbed=90;stable.impact_shield_energy=0;hud.update_flight(stable)
 check(not hud.flight_labels.impact.text.contains("90"),"synthetic unfunded absorption cannot claim successful protection")
 hud.update_flight({})
 check(hud.flight_labels.thrust.text=="推力 — N" and hud.flight_labels.energy.text=="电量 — / —" and hud.flight_labels.impact.text.is_empty(),"missing v3 telemetry stays unknown without fabricated power or protection")
 hud.update_flight({"thrust_actual":NAN,"thrust_requested":INF,"impact_absorbed":NAN,"impact_shield_energy":INF,"overdrive":true})
 check(not text_content().contains("nan") and not text_content().contains("inf"),"nonfinite telemetry never prints unusable numeric values")
 for active in [false,true]:
  var dry_shield=fresh([Profile.part(1,"cargo",0),Profile.part(2,"shield",-1,1,{"input_a":-2}),Profile.part(3,"battery",-1)])
  dry_shield.set_pilot_input(0,false,active)
  if active:dry_shield.parts[3].energy=0
  present(dry_shield);dry_shield._damage_part(dry_shield.parts[1],20,"collision");hud.update_flight(live_data(dry_shield))
  check(hud.flight_labels.impact.text.is_empty(),"actual disabled or empty shield never advertises absorption: "+str(active))
 var eight=fresh(Profile.reinforced_design());eight.set_pilot_input(0,true,false)
 for i in 120:eight.step(1.0/120.0)
 present(eight);await settle()
 for extent in [Vector2i(1280,720),Vector2i(1920,1080)]:await check_panel_bounds(extent)
 var empty:Dictionary=live_data(eight);empty.energy_remaining=0;empty.thrust_actual=0;empty.thrust_requested=224;hud.update_flight(empty);await settle()
 check(hud.flight_labels.energy.text.contains("耗尽") and hud.flight_labels.thrust.text=="全功率 · 推力 0.0 N","held full power with empty cells shows zero funded thrust")
 check(hud._motion_tweens.is_empty(),"continuous v3 telemetry does not allocate animation resources")
 hud.render({"mode":"help","control_version":"pilot-v3","settings":{"reduced_motion":true}});await settle()
 var help:=text_content()
 check(help.contains("Shift 全功率") and help.contains("空转也耗电") and help.contains("吸收部分碰撞伤害"),"v3 help documents paid motor, finite shields and full-power control")
 check(not help.contains("22 m/s") and not help.contains("30 N"),"v3 help has no obsolete speed target or universal cap")
 for version in ["pilot-v1","pilot-v2"]:
  hud.render({"mode":"flight","control_version":version,"flight":{},"settings":{"reduced_motion":true}});await settle()
  check(not hud._extreme_mode() and not hud.flight_labels.has("thrust") and text_content().contains("Shift  冲刺"),"legacy HUD keeps existing semantics: "+version)
 world.leave_flight();check(world.ascent_backdrop.visible and world.ascent_backdrop.debug_snapshot().route_kind=="city" and world.flight_nodes.is_empty() and not world.effect_node.visible,"v3 exit clears flight visuals while retaining coherent shop sky")
 hud.queue_free();viewport.queue_free();await settle()
 check(get_processed_tweens().is_empty(),"presentation teardown releases all tweens")
 print("EXTREME_PRESENTATION passed=%d failed=%d"%[passed,failed]);quit(1 if failed else 0)
