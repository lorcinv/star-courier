extends SceneTree
## OFFLINE ONLY: builds a wall-time keyboard macro or audits a game-written save.
## Never loaded by the live game. Usage: --script ... -- --spec /absolute/spec.json
const Sim = preload("res://scripts/pilot_simulation.gd")
const Profile = preload("res://scripts/pilot_profile.gd")
const AscentSim=preload("res://scripts/pilot_ascent_simulation.gd")
const AscentProfile=preload("res://scripts/pilot_ascent_profile.gd")
const Timeline = preload("res://scripts/pilot_timeline.gd")

func _initialize() -> void:
 var args:=OS.get_cmdline_user_args()
 var spec:Dictionary={}
 for i in range(args.size()-1):
  if args[i]=="--spec":spec=JSON.parse_string(FileAccess.get_file_as_string(args[i+1]))
 var snapshot:Dictionary=spec.get("snapshot",{})
 var route:Dictionary=spec.get("route",Profile.route({"weight":float(spec.get("weight",1.0))}))
 var craft:Array=spec.get("design",Profile.starter_design())
 var launcher:Array=spec.get("launcher",Profile.starter_launcher())
 var seed_value:int=int(spec.get("seed",100))
 if not snapshot.is_empty():
  route=snapshot.route;craft=snapshot.design;launcher=snapshot.launcher;seed_value=int(snapshot.seed)
 var ascent:bool=str(route.get("control_version",""))==AscentProfile.CONTROL_VERSION
 var s=AscentSim.new() if ascent else Sim.new();s.configure(craft,launcher,route,seed_value)
 var start_tick:int=int(snapshot.get("ticks",0))
 var timeline=Timeline.new()
 if not snapshot.is_empty():
  if not timeline.restore(snapshot.get("input_commands",[]),start_tick):
   push_error(timeline.error);quit(2);return
  for tick in range(start_tick):
   var input:Dictionary=timeline.state_at(tick)
   s.set_pilot_input(int(input.axis_q),bool(input.boost),bool(input.active));s.step(1.0/60.0)
 var checkpoint:Dictionary={"elapsed":s.elapsed,"energy_used":s.telemetry.energy_used,"position":[s.cargo_position().x,s.cargo_position().y],"events":s.events.duplicate()}
 var commands:Array=[];var last:Dictionary={}
 var mode:String=str(spec.get("mode","guide"))
 var held_ascent_axis:int=0
 for frame in range(start_tick,4200 if ascent else 3900):
  var pos:Vector2=s.cargo_position()
  var command:Dictionary
  if mode=="replay":
   var input:Dictionary=timeline.state_at(frame)
   command={"axis":int(input.axis_q),"boost":bool(input.boost),"active":bool(input.active)}
  elif ascent:
   if (frame-start_tick)%12==0:
    var offset:float=0
    for gate in s.route.pilot_gates:
     if pos.x<float(gate.x)+6.5:offset=float(gate.lane_offset);break
    var normal:Vector2=AscentProfile.path_tangent(pos.x,s.route).orthogonal()*-1.0
    var velocity:Vector2=s._cargo_body().get("velocity",Vector2.ZERO)
    var error:float=AscentProfile.path_y(pos.x,s.route)+offset-pos.y-velocity.dot(normal)*.9
    held_ascent_axis=int(signf(error))*1000 if absf(error)>.9 else 0
   command={"axis":held_ascent_axis,"boost":frame>=int(spec.get("boost_start_tick",210)) and frame<int(spec.get("boost_end_tick",210)),"active":false}
  else:
   var target:float=0.0
   for gate in s.route.pilot_gates:
    if pos.x<float(gate.x)+4.0:target=float(gate.y);break
   var forecast:float=pos.y+s.telemetry.vertical_speed*.85
   var delta:float=target-forecast
   command={"axis":int(signf(delta))*1000 if absf(delta)>.32 else 0,"boost":frame>=int(spec.get("boost_start_tick",210)) and frame<int(spec.get("boost_end_tick",210)),"active":false}
  if command!=last:
   commands.append({"time":frame/60.0,"axis":command.axis,"boost":command.boost,"active":command.active,"x":pos.x,"y":pos.y});last=command.duplicate()
  s.set_pilot_input(command.axis,command.boost,command.active);s.step(1.0/60.0)
  if s.status!="running":break
 s.finalize_settlement()
 print("REFERENCE_JSON:",JSON.stringify({"mode":mode,"seed":seed_value,"weight":route.get("weight",1.0),"status":s.status,"elapsed":s.elapsed,"remaining_energy":s.total_energy(),"energy_used":s.telemetry.energy_used,"telemetry":s.telemetry,"integrity":s.ship_integrity(),"events":s.events,"checkpoint":checkpoint,"commands":commands}))
 quit(0 if s.status=="success" else 1)
