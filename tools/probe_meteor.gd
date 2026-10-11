extends SceneTree
const Sim=preload("res://scripts/pilot_extreme_simulation.gd")
const Profile=preload("res://scripts/pilot_extreme_profile.gd")
const Catalog=preload("res://scripts/orbital_meteor_catalog.gd")
const Guide=preload("res://tools/calibrate.gd")
func _initialize():
 for id in [1,2]:
  for evade in [false,true]:
   var base={"id":id,"weight":1.5 if id==1 else 2.0,"reward":220 if id==1 else 280,"rep":2 if id==1 else 4}
   var authored=Catalog.author(base,42)
   if not authored.ok:print("ERROR ",authored);quit(1);return
   var r:Dictionary=authored.route
   var sim=Sim.new();sim.configure(Profile.starter_design(),Profile.starter_launcher(),r,42)
   var event:Dictionary=r.orbital_event.events[0];var axis=0;var hit={};var vis=-1.0;var contact_envelope=-1.0
   var manifest:Dictionary=JSON.parse_string(FileAccess.get_file_as_string("res://assets/2d_v5/events/meteor/manifest.json"))
   var sprite:Dictionary=manifest.assets[0]
   for tick in range(4800):
    if FileAccess.file_exists("/tmp/courier-meteor-pause"):print("PAUSED");quit(75);return
    if tick%12==0:axis=Guide.guidance(sim)
    if sim.cargo_position().x>500.0:
     axis=0
     if evade and sim.elapsed>=event.center_crossing_seconds-2.6 and sim.elapsed<event.center_crossing_seconds-0.4:axis=-1000
     if sim.cargo_position().x>event.initial_position[0]+15:axis=Guide.guidance(sim)
    var h=sim.obstacles[8];var pos:Vector2=sim.cargo_position()
    if vis<0 and silhouette_visible(pos,h.position,sprite):vis=sim.elapsed
    if contact_envelope<0 and pos.distance_to(h.position)<=3.3:contact_envelope=sim.elapsed
    var old=int(sim.telemetry.swept_contacts)
    sim.set_pilot_input(axis,false,false);sim.step(1.0/60.0)
    if int(sim.telemetry.swept_contacts)>old and hit.is_empty():hit={"time":sim.elapsed,"x":sim.cargo_position().x,"y":sim.cargo_position().y,"meteor":str(sim.obstacles[8].position)}
    if sim.status!="running":break
   print("PROBE ",JSON.stringify({"id":id,"evade":evade,"event":event,"status":sim.status,"time":sim.elapsed,"integrity":sim.telemetry.integrity,"energy":sim.total_energy(),"hit":hit,"silhouette_visible":vis,"envelope":contact_envelope,"warning":event.warning_start_seconds,"meteor_hp":sim.obstacles[8].health,"contacts":sim.telemetry.swept_contacts}))
 quit(0)
static func silhouette_visible(cargo:Vector2,hazard:Vector2,sprite:Dictionary) -> bool:
 # Current ordinary ascent camera at forward_speed >=18m/s (.27 zoom),
 # preserving the real horizontal lead and vertical HUD clearance.
 var zoom=0.27;var cell=72.0;var lead=1280.0*0.34/(zoom*cell)
 var cy=cargo.y-clampf(cargo.y+150.0,-180.0/cell,180.0/cell)-88.0/(zoom*cell)
 var rect=Rect2(Vector2(cargo.x+lead-640.0/(zoom*cell),cy-360.0/(zoom*cell)),Vector2(1280.0,720.0)/(zoom*cell))
 var scale=0.8/float(sprite.occupied_circumradius_px)
 var anchor=Vector2(sprite.anchor_px[0],sprite.anchor_px[1])
 for row in sprite.silhouette_runs:
  var y=hazard.y+(float(row[0])+0.5-anchor.y)*scale
  if y<rect.position.y or y>rect.end.y:continue
  for run in row[1]:
   var xmin=hazard.x+(float(run[0])-anchor.x)*scale
   var xmax=hazard.x+(float(run[1])-anchor.x)*scale
   if xmax>=rect.position.x and xmin<=rect.end.x:return true
 return false
