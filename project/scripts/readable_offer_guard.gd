extends RefCounted
## Exact registered content only. Old unregistered readable QA snapshots are opaque.
## Never authors on restore; all physical coordinates remain saved snapshot data.
const T=preload("res://scripts/readable_offer_templates.gd")
const Legacy=preload("res://scripts/seeded_offer_guard.gd")
const Stories=preload("res://scripts/courier_stories.gd")
const Ascent=preload("res://scripts/pilot_ascent_profile.gd")
const Extreme=preload("res://scripts/pilot_extreme_profile.gd")
const Framing=preload("res://scripts/moon_framing_2d.gd")

static func same(a:Variant,b:Variant) -> bool:
 # JSON round trips change int to float; booleans/strings never become numbers.
 if a is bool or b is bool:return a is bool and b is bool and a==b
 if a is int or a is float:return (b is int or b is float) and is_finite(float(a)) and is_finite(float(b)) and a==b
 if a is String or b is String:return a is String and b is String and a==b
 if a is Dictionary and b is Dictionary:
  if a.size()!=b.size():return false
  for key in a:
   if not b.has(key) or not same(a[key],b[key]):return false
  return true
 if a is Array and b is Array:
  if a.size()!=b.size():return false
  for i in a.size():
   if not same(a[i],b[i]):return false
  return true
 return a==null and b==null

static func exact_keys(value:Dictionary,keys:Array) -> bool:
 if value.size()!=keys.size():return false
 for key in keys:
  if not value.has(key):return false
 return true

static func has_markers(route:Dictionary) -> bool:
 var m:Variant=route.get("generation")
 # Neither historical geometry version nor camera policy alone grants identity.
 return route.has("readable_offer_schema") or (m is Dictionary and m.has("readable_commercial_adapter"))

static func recognized(route:Dictionary) -> bool:
 return has_markers(route) and validation_error(route).is_empty()

static func validation_error(route:Dictionary) -> String:
 var error:String=Legacy.generic_snapshot_error(route)
 if not error.is_empty():return error
 if not same(route.get("readable_offer_schema"),1):return "Missing readable commercial registration."
 var m:Variant=route.get("generation")
 if not m is Dictionary:return "Missing readable provenance."
 if not exact_keys(m,["version","policy","readable_commercial_adapter","authoring_policy","world_seed","day","slot","kind","layout_template","fallback","fallback_reason","base_id","base_rep","base_weight","base_reward","weight_delta","task_template","readability","dialogue","seed","layout_seed","task_seed","dialogue_seed"]):return "Incomplete or mixed readable provenance."
 if not same([m.version,m.policy,m.readable_commercial_adapter,m.authoring_policy],[T.VERSION,T.POLICY,T.ADAPTER,T.ROOT_POLICY]):return "Unsupported registered readable identity."
 if not Legacy.integer_in(m.world_seed,0,T.MAX_SEED) or not Legacy.integer_in(m.day,1,1000000) or not Legacy.integer_in(m.slot,0,1):return "Invalid readable request seed/day/slot."
 if not m.kind is String or not m.kind in T.TEMPLATES:return "Unknown readable geometry."
 if not m.fallback is bool or not same(m.fallback_reason,"candidate_rejected" if m.fallback else ""):return "Invalid readable fallback provenance."
 if not Legacy.integer_in(m.base_id,0,2):return "Invalid original catalog identity."
 var row:Array=T.COMMERCIAL[int(m.base_id)]
 if not same([route.id,route.rep,m.base_rep,m.base_weight,m.base_reward],[m.base_id,row[2],row[2],row[0],row[1]]) or (m.kind=="ground")!=(int(m.base_id)==0):return "Original catalog terms/unlock changed."
 for domain in ["offer","layout","task","dialogue"]:
  var key:String="seed" if domain=="offer" else domain+"_seed"
  if not same(m[key],T.derived_seed(int(m.world_seed),int(m.day),int(m.slot),m.kind,domain)):return "Readable seed provenance changed: "+key
 var t:Dictionary=T.TEMPLATES[m.kind]
 var c:Dictionary=T.choices(int(m.world_seed),int(m.day),int(m.slot),m.kind)
 var heavy:bool=int(m.slot)==1
 if not same(m.layout_template,t.id) or not same(m.readability,T.READABILITY):return "Readable geometry/reference contract changed."
 if not same(m.weight_delta,c.weight_delta) or not same(m.task_template,("bulk" if heavy else "standard")+("-careful" if c.careful else "-steady")):return "Task selection disagrees with its private stream."
 if not same([route.weight,route.reward,route.required,route.deadline],[snappedf(row[0]*(1.55 if heavy else 1.0)+c.weight_delta,0.125),int(row[1])+(55 if heavy else 0)+(10 if c.careful else 0)+int(c.weight_delta*40.0),90.0 if c.careful else 85.0,t.deadline+(3.0 if heavy else 0.0)+(2.0 if c.careful else 0.0)]):return "Saved commercial weight/reward/quality/deadline changed."
 if not same([route.contract_id,route.get("accepted_day"),route.get("variant")],["D%d-%s"%[int(m.day),"A" if not heavy else "B"],m.day,"重货件" if heavy else "标准件"]):return "Contract day/slot identity changed."
 if not route.status in ["available","accepted","in_flight","settled","declined","cancelled"]:return "Unsupported saved contract status."
 var fields:Dictionary=T.physical_fields(m.kind)
 for key in fields:
  if not same(route.get(key),fields[key]):return "Non-authored physical/presentation field: "+key
 var allowed:Array=fields.keys()+["id","rep","weight","reward","required","deadline","contract_id","status","accepted_day","variant","client","cargo","appearance_id","story_id","story","readable_offer_schema","pilot_gates","hazards","generation","cargo_loaded","appearance_seed","species","accessory_id","story_node","battery_capacity_multiplier","seed","success"]
 for key in route:
  if not key in allowed:return "Unexpected registered route field: "+str(key)
 if route.has("success") and (not route.success is bool or route.status!="settled"):return "Invalid settlement outcome flag."
 if route.has("cargo_loaded") and not route.cargo_loaded is bool:return "Invalid cargo loading flag."
 if route.has("battery_capacity_multiplier") and not Legacy.number_in(route.battery_capacity_multiplier,1.0,1.45):return "Invalid saved research capacity."
 if route.has("seed") and not same(route.seed,int(m.day)*100+int(m.base_id)*3+int(m.slot)):return "Trial seed differs from this accepted offer."
 if not route.get("pilot_gates") is Array or route.pilot_gates.size()!=2 or route.hazards.size()!=4:return "Incomplete mandatory physical gate pairs."
 for index in 2:
  var g:Variant=route.pilot_gates[index]
  if not g is Dictionary or not exact_keys(g,["index","x","y","half_gap","lane_offset","heading"]):return "Malformed gate fields."
  var x:float=t.xs[index]+(0.0 if m.fallback else c.jitter[index][0])
  var offset:float=t.offsets[index]+(0.0 if m.fallback or index==1 else c.jitter[index][1])
  var y:float=(0.0 if index==0 else -t.altitude)+offset
  if not same(g,{"index":index,"x":x,"y":y,"half_gap":8.0,"lane_offset":offset,"heading":0.0}):return "Saved gate does not match exact bounded private choices."
  if not same(g.y,Ascent.path_y(g.x,route)+g.lane_offset) or not same(Ascent.path_heading(g.x,route),0.0):return "Mandatory gate is not on a level approach."
  var full_radius:float=5.0+T.READABILITY.reference_craft_radius
  if index==0 and (g.x-full_radius<T.READABILITY.level_approach_distance or g.x+full_radius+T.READABILITY.level_exit_distance>route.pilot_climb_start):return "First gate lacks a full-body level preview/exit."
  if index==1 and (g.x-full_radius-T.READABILITY.level_approach_distance<route.pilot_climb_end or route.distance-g.x-full_radius<50.0):return "Final gate lacks level preview/receiver clearance."
  if g.half_gap-absf(g.lane_offset)-T.READABILITY.reference_craft_radius<T.READABILITY.clearance_margin:return "Insufficient full-craft aperture."
  for j in 2:
   var collider:Dictionary={"x":x,"y":y+(-1.0 if j==0 else 1.0)*13.0,"radius":5.0,"type":"rock","health":1000000.0,"mass":1000000.0,"pilot_gate":true,"gate_index":index}
   if not same(route.hazards[index*2+j],collider):return "Actual circular collider differs from mandatory inward faces."
 var d:Variant=m.dialogue
 if not d is Dictionary or not d.get("appearance_id") is String or not d.appearance_id in Stories.IDS:return "Unknown readable client."
 var actor:String=d.appearance_id
 var p:Dictionary=Stories.PROFILES[actor]
 var opening:String=T.OPENINGS[actor][c.dialogue]%fields.destination_name
 var expected:Dictionary={"id":"%s-readable-address-%d"%[actor,c.dialogue],"appearance_id":actor,"story_id":p.story_id,"cargo":p.cargo,"destination_name":fields.destination_name,"accept_lines":[{"speaker":"npc","text":opening,"expression":"neutral"},{"speaker":"clerk","text":"地址核对好了。我先把箱子固定稳。","expression":"warm_smile"}]}
 if not same(d,expected) or not same([route.client,route.cargo,route.story,route.get("appearance_id"),route.get("story_id")],[p.name,("加急补货 · " if heavy else "")+str(p.cargo),opening,actor,p.story_id]):return "Saved client/parcel/appearance/story identity changed."
 # Cosmetics are the separate persisted story roster, never a route RNG draw.
 if route.has("appearance_seed") and not Legacy.integer_in(route.appearance_seed,0,T.MAX_SEED):return "Invalid appearance seed."
 if route.has("species") and not same(route.species,p.species):return "Saved client species changed."
 if route.has("accessory_id") and (not route.accessory_id is String or not route.accessory_id in p.accessories):return "Saved client accessory changed."
 if route.has("story_node") and not Legacy.integer_in(route.story_node,0,3):return "Invalid story progression."
 return reference_preview_error()

static func reference_preview_error() -> String:
 # Actual starter module quads, not nominal collision radius or an avatar icon.
 var measured:Dictionary=design_bounds(Extreme.starter_design())
 if not measured.known or minf(measured.bounds.size.x,measured.bounds.size.y)*72.0*0.28<60.0:return "True reference sprite bounds fall below the reviewed footprint."
 if measured.radius>3.75:return "Reference sprite corners exceed the complete-craft envelope."
 for extent in [Vector2(1280,720),Vector2(1920,1080),Vector2(3840,2160)]:
  for sample in [[3.2,19.7],[7.5,18.0]]:
   var budget:Dictionary=preview_budget(extent,float(sample[0]),float(sample[1]))
   if not budget.fits:return "Authored physical faces fail the fixed reference screen budget."
 return ""

static func preview_budget(extent:Vector2,width_m:float,x_speed:float) -> Dictionary:
 # Analytical level-gate condition only, never a player speed governor.
 if not extent.is_finite() or extent.x<=0.0 or extent.y<=0.0 or not is_finite(width_m) or width_m<=0.0 or not is_finite(x_speed) or x_speed<0.0:return {"fits":false}
 var scene:Vector2=extent*1280.0/extent.x
 var unit:float=clampf(floorf(extent.y/720.0),1.0,3.0)*1280.0/extent.x
 var ppm:float=72.0*0.28
 var anchor:float=maxf(60.0,12.0*unit+18.0+width_m*ppm*0.5)
 var right:float=anchor+(x_speed*2.5+width_m*0.5+5.0+5.0/sqrt(2.0))*ppm
 var vertical:float=(16.0+10.0*(1.0-1.0/sqrt(2.0))+2.0)*ppm
 var available:float=scene.y-188.0*unit-24.0
 return {"fits":right<=scene.x-12.0*unit-1.0 and vertical<=available,"right":right,"right_limit":scene.x-12.0*unit-1.0,"vertical":vertical,"vertical_limit":available,"anchor":anchor,"physical_module_px":0.98*ppm*extent.x/1280.0,"physical_body_px":2.98*ppm*extent.x/1280.0,"note":"Level reference geometry only; actual trajectory, HUD and launch/release require separate evidence."}

static func design_bounds(design:Array,angle:float=0.0) -> Dictionary:
 # Informational only; never rejects/edits a legal blueprint. Actual connected
 # in-flight groups use Framing.craft_bounds instead (detached pieces excluded).
 if design.is_empty() or not is_finite(angle):return {"known":false}
 var cargo:Vector2=Vector2.ZERO
 var found:bool=false
 for part in design:
  if part.get("type")=="cargo":cargo=Vector2(part.get("x",0),part.get("y",0));found=true;break
 if not found:return {"known":false}
 var bounds:Rect2
 var first:bool=true
 var radius:float=0.0
 for part in design:
  var center:Vector2=Vector2(part.get("x",0),part.get("y",0))-cargo
  var local_angle:float=float(part.get("rot",0))*PI*0.5
  for sx in [-1.0,1.0]:
   for sy in [-1.0,1.0]:
    var point:Vector2=center+Vector2(sx,sy)*0.49*float(part.get("scale",1.0))
    # Square corners rotate around each actual module's own centre.
    point=center+(point-center).rotated(local_angle)
    radius=maxf(radius,point.length());point=point.rotated(angle)
    if first:bounds=Rect2(point,Vector2.ZERO);first=false
    else:bounds=bounds.expand(point)
 return {"known":true,"bounds":bounds,"radius":radius,"reference_envelope":radius<=3.75,"note":"Geometry is informational; energy, connectivity and handling are not certified."}

static func connected_preview(sim,extent:Vector2) -> Dictionary:
 var body:Rect2=Framing.craft_bounds(sim,Vector2.ZERO,1.0)
 var velocity:Vector2=sim._cargo_body().get("velocity",Vector2.ZERO)
 var budget:Dictionary=preview_budget(extent,body.size.x,maxf(0.0,velocity.x))
 budget.connected_body_m=body
 budget.within_size_speed_reference=body.size.x<=7.5 and body.size.y<=7.5 and absf(velocity.y)<=5.0 and budget.fits
 budget.actual_visibility_verified=false # Size/speed alone cannot certify the live trajectory.
 return budget
