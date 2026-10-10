extends SceneTree
## Read-only rendered-geometry analysis, not native play or a human fairness test.
## Uses the actual controller, stepped physics, camera smoothing and sprite bounds.
var game
func _initialize() -> void:run.call_deferred()
func run() -> void:
 root.size=Vector2i(1280,800)
 game=load("res://scenes/main.tscn").instantiate();root.add_child(game)
 game.set_process(false);game.world.set_process(false)
 game.economy.accept_contract("D1-A");game.start_flight(true)
 game.world.launch_age=2;game.launch_age=2
 var seen:Dictionary={};var both:Dictionary={};var crossing:Dictionary={}
 var minimum_ship:float=INF
 var axis:int=0
 for tick in range(4200):
  if tick%12==0:axis=game._smoke_guidance_axis()
  game.pilot_keys.clear()
  if axis!=0:game.pilot_keys[KEY_W if axis<0 else KEY_S]=true
  game._step_flight();game.world.show_flight(game.sim);game.world._process(1.0/60.0)
  var tx:Transform2D=game.view.get_canvas_transform()
  var safe:Rect2=Rect2(0,100,1280,550)
  var ship:Rect2=Rect2();var first:bool=true
  for p in game.sim.parts.values():
   var art:Sprite2D=game.world.flight_nodes["p"+str(p.id)]
   var rect:Rect2=tx*art.global_transform*art.get_rect()
   ship=rect if first else ship.merge(rect);first=false
  minimum_ship=minf(minimum_ship,ship.size.length())
  for gate in game.sim.route.pilot_gates:
   var i:int=int(gate.index);var visible_count:int=0
   for h in [i*2,i*2+1]:
    var art:Sprite2D=game.world.flight_nodes["h"+str(h)]
    var rect:Rect2=tx*art.global_transform*art.get_rect()
    var intersection:Rect2=rect.intersection(safe)
    if intersection.size.x>=20 and intersection.size.y>=20 and intersection.get_area()>=500:visible_count+=1
   if visible_count>0 and not seen.has(i):seen[i]=game.sim.elapsed
   if visible_count==2 and not both.has(i):both[i]=game.sim.elapsed
   if game.sim.cargo_position().x>=float(gate.x) and not crossing.has(i):crossing[i]=game.sim.elapsed
  if game.sim.status!="running":break
 var results:Array=[]
 for i in range(4):results.append({"gate":i+1,"visible_any":seen.get(i,-1),"visible_both":both.get(i,-1),"crossing":crossing.get(i,-1),"any_lead":float(crossing.get(i,-1))-float(seen.get(i,INF)),"both_lead":float(crossing.get(i,-1))-float(both.get(i,INF))})
 print("ASCENT_VISIBILITY ",JSON.stringify({"method":"real sprite bounds clipped to HUD-safe viewport, >=20x20 and500pixels; not alpha-exact or human play","window":[1280,800],"viewport":str(game.view.size),"minimum_craft_bounds_diagonal_px":minimum_ship,"gates":results},"",true,true))
 game.queue_free();await process_frame;await process_frame;quit()
