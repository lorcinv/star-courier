extends SceneTree
## Expected failures demonstrate the old physics cannot satisfy the new PDR.
const OldSim=preload("res://scripts/pilot_free_simulation_v2.gd")
const OldProfile=preload("res://scripts/pilot_free_profile_v2.gd")
const Open=preload("res://scripts/pilot_extreme_profile.gd")
var failed:int=0
func check(ok:bool,label:String)->void:
 if ok:print("PASS ",label)
 else:failed+=1;print("EXPECTED_RED ",label)
func make(weight:float=1.0,pad:Array=[]):
 var r:Dictionary=OldProfile.route(Open.route({"weight":weight}));r.hazards=[];r.pilot_gates=[];r.distance=1000.0;r.destination_y=0.0;r.pilot_drag=0.0;r.min_delivery_integrity=0.9
 var design:Array=OldProfile.starter_design();design.append({"id":9,"type":"teleporter","x":2,"y":0,"param":8.0,"input_a":-2})
 var s=OldSim.new();s.configure(design,pad,r,42);return s
func _initialize()->void:
 var prepared=make(1.0,OldProfile.starter_launcher())
 check(prepared.body_for_part(1).velocity.length()<0.000001,"preparation must not release before visible release frame")
 check(prepared.has_method("release_launcher"),"one-shot release API must exist")
 var light=make();var heavy=make(6.0)
 light._act(light.parts[9],light.body_for_part(9),1.0/120.0,true)
 heavy._act(heavy.parts[9],heavy.body_for_part(9),1.0/120.0,true)
 check(float(heavy.telemetry.energy_used)>float(light.telemetry.energy_used),"teleport cost must increase with carried mass")
 var invalid=make();invalid.parts[1].hp=70.0
 var b:Dictionary=invalid.body_for_part(1);b.position+=Vector2(1000,0)-invalid.cargo_position();b.velocity=Vector2.ZERO
 invalid._check_status()
 check(invalid.status=="failed","70 percent cargo must fail a 90 percent arrival requirement")
 print("DELIVERY_V3_LEGACY_RED expected_failures=",failed)
 quit(1 if failed else 0)
