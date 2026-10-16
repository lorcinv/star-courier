extends SceneTree
## Existing runtime mechanics + explicit v2 editor policy. NOT RUN by author.
const Policy=preload("res://scripts/workshop_parts_v2.gd")
const Parts=preload("res://scripts/parts_expanded.gd")
const Sim=preload("res://scripts/pilot_free_simulation_v1.gd")
const Profile=preload("res://scripts/pilot_free_profile_v1.gd")
const Extreme=preload("res://scripts/pilot_extreme_profile.gd")
var failures:int=0
func check(value:bool,label:String) -> void:
 if value:print("PASS ",label)
 else:failures+=1;push_error("FAIL "+label)
func part(id:int,kind:String,x:int,extra:Dictionary={}) -> Dictionary:
 var value:Dictionary={"id":id,"type":kind,"x":x,"y":0,"rot":0,"param":Parts.defaults(kind),"input_a":-1,"input_b":-1,"target":-1};value.merge(extra,true);return value
func sim(kind:String):
 var r:Dictionary=Profile.route(Extreme.route({"weight":1.0}));r.hazards=[];r.pilot_gates=[];r.distance=10000.0;r.destination_y=-1000.0;r.pilot_drag=0.0
 var s=Sim.new();s.configure([part(1,"cargo",0),part(2,"battery",-1),part(3,kind,1,{"input_a":-2,"target":4}),part(4,"beam",2)],[],r,42);return s
func _initialize() -> void:
 var spring_controls:Array=Policy.local_controls(Policy.new_part(9,"spring",0,0,[],true,true),true)
 check(spring_controls.size()==1 and spring_controls[0].max==60.0 and spring_controls[0].value==60.0 and Parts.sanitize_parameter("spring",60.0)==60.0,"60J starter is authorable by the same real0–60J slider and catalog validator")
 check(Policy.CORE.size()==9 and Policy.ADDED.size()==3 and Policy.sale_kinds().size()==12,"nine retained core plus three real mechanical types")
 var entries:Array=[]
 for kind in Parts.catalog():entries.append({"type":kind,"launcher_compatible":kind in Parts.launcher_types()})
 var inventory:Dictionary={"not_gate":5,"coupler":1,"damper":1,"accelerator":1,"armor":2}
 var shown:Array=Policy.visible_entries(entries,[],inventory,Policy.DEFAULT_CATEGORY,false)
 check(not shown.any(func(p):return p.type in Policy.LOGIC),"owned logic gates never leak into current palette")
 check(not "旧版保留" in Policy.categories(entries,[],inventory,false),"there is no legacy parts category")
 for kind in Policy.SHIP:
  check(Policy.compatible(kind,true)==(kind in Policy.PAD),kind+" shared pad permission is explicit")
 for kind in ["shield","drill","teleporter","splitter","coupler","damper"]:
  check(Policy.new_part(9,kind,2,0,[],true,true).is_empty() and not Policy.placement_error(kind,true).is_empty(),kind+" cannot become a nonfunctional pad placement")
 for kind in Policy.ADDED:
  var fresh:Dictionary=Policy.new_part(3,kind,1,0,[part(1,"cargo",0),part(4,"beam",2)],false,true)
  check(fresh.input_a==(-1 if kind=="damper" else -2),kind+" has understandable direct control")
 var separate=sim("coupler");var budget:float=separate.total_energy();separate._act(separate.parts[3],separate.body_for_part(3),1.0/120.0,true)
 check(not separate._linked(3,4) and separate.total_energy()==budget,"coupler actually opens chosen socket without power")
 var damp=sim("damper");var body:Dictionary=damp.body_for_part(1);body.angular_velocity=2.0;budget=damp.total_energy()
 damp._act(damp.parts[3],body,0.5,false)
 check(body.angular_velocity<2.0 and damp.telemetry.heat>0.0 and damp.total_energy()==budget,"damper actually dissipates spin as heat without consuming battery")
 var accelerator=sim("accelerator");budget=accelerator.total_energy();var momentum:Vector2=accelerator.total_momentum()
 accelerator._act(accelerator.parts[3],accelerator.body_for_part(3),1.0/120.0,true)
 check(accelerator.body_for_part(3).id!=accelerator.body_for_part(4).id and accelerator.parts[3].spent,"accelerator actually launches target into separate body once")
 check(accelerator.total_energy()<budget and accelerator.total_momentum().distance_to(momentum)<0.00001,"accelerator pays energy and preserves craft/projectile momentum")
 check(accelerator.parts[4].replacement_kind=="ammo","noncargo projectile records existing single ammo replacement")
 budget=accelerator.total_energy();accelerator._act(accelerator.parts[3],accelerator.body_for_part(3),1.0/120.0,true)
 check(accelerator.total_energy()==budget,"spent accelerator cannot repeatedly bill or launch")
 var p:Dictionary=Policy.new_part(9,"teleporter",1,0,[],false,true)
 check("选择" in Policy.trigger_text(p,[],true,false) and not "同时触发所有" in Policy.trigger_text(p,[],true,false),"v2 text says select one gadget before firing")
 print("MECHANICAL_PARTS_V2 failures=",failures," native_gui=NOT_RUN");quit(1 if failures else 0)
