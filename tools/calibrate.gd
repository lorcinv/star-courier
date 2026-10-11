extends SceneTree
const Sim = preload("res://scripts/pilot_extreme_simulation.gd")
const Profile = preload("res://scripts/pilot_extreme_profile.gd")
const Ascent = preload("res://scripts/pilot_ascent_profile.gd")
func _initialize():
 for weight in [1.0,1.5,2.0]:
  var r=Profile.route({"weight":weight});r.distance=740.0;r.deadline=60.0
  var s=Sim.new();s.configure(Profile.starter_design(),Profile.starter_launcher(),r,42)
  var axis=0;var crossed=false;var snapshots=[]
  for tick in range(4200):
   if FileAccess.file_exists("/tmp/courier-meteor-pause"):print("PAUSED");quit(75);return
   if tick%12==0:axis=guidance(s)
   s.set_pilot_input(axis,false,false);s.step(1.0/60.0)
   if not crossed and s.cargo_position().x>=600:
    crossed=true;print("CENTER ",weight," ",JSON.stringify({"time":s.elapsed,"x":s.cargo_position().x,"y":s.cargo_position().y,"energy":s.total_energy(),"v":str(s._cargo_body().velocity),"contacts":s.telemetry.swept_contacts}))
   if tick%120==119 and s.cargo_position().x>470:snapshots.append({"t":s.elapsed,"x":s.cargo_position().x,"y":s.cargo_position().y})
   if s.status!="running":break
  print("RESULT ",weight," ",JSON.stringify({"t":s.elapsed,"status":s.status,"integrity":s.telemetry.integrity,"energy":s.total_energy(),"snapshots":snapshots}))
 quit(0)
static func guidance(s,offset_override=0.0):
 var pos=s.cargo_position();var offset=offset_override
 for gate in s.route.pilot_gates:
  if pos.x<float(gate.x)+6.5:offset=float(gate.lane_offset);break
 var normal=Ascent.path_tangent(pos.x,s.route).orthogonal()*-1.0
 var body=s._cargo_body();var velocity:Vector2=body.get("velocity",Vector2.ZERO)
 var lateral_speed=velocity.dot(normal);var acceleration=30.0/maxf(1.0,body.mass)
 var preview=lateral_speed*(0.45+absf(lateral_speed)/(2.0*acceleration*0.9))
 var error=Ascent.path_y(pos.x,s.route)+offset-pos.y-preview
 return int(signf(error))*1000 if absf(error)>0.9 else 0
