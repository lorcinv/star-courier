extends RefCounted
## Append-only commercial/readable content. Never changes a physical protocol.
const VERSION="seeded-offers-v2-readable-a1"
const POLICY="readable-fixed-envelope-a1"
const ADAPTER="readable-commercial-a1"
const ROOT_POLICY="seeded-readable-policy-a1"
const MAX_SEED=2147483646
const TEMPLATES={
 "ground":{"id":"roof-level-pairs-a1","distance":380.0,"altitude":8.0,"climb_start":140.0,"climb_end":220.0,"xs":[95.0,315.0],"offsets":[-2.0,0.0],"deadline":40.0,"time_limit":60.0,"receiver":7.0,"boundary":45.0},
 "ascent":{"id":"orbit-clear-climb-a1","distance":650.0,"altitude":150.0,"climb_start":170.0,"climb_end":440.0,"xs":[105.0,565.0],"offsets":[-2.0,0.0],"deadline":58.0,"time_limit":82.0,"receiver":9.0,"boundary":230.0}}
const COMMERCIAL=[[1.0,165,0],[1.5,220,2],[2.0,280,4]]
const OPENINGS={
 "human_courier":["小勺送到%s，外面那层布也一起留给他。","还是那把小勺，地址写的是%s。我把勺柄也包好了。"],
 "elf_archivist":["书签送到%s。借书条放在外袋，别和它一起夹进去。","%s在等这枚书签。我另外夹了张纸，写着它该放在哪本书里。"],
 "alien_botanist":["这盆幼苗去%s。垫在花盆下面的布，到了也先别抽走。","送到%s就好。幼苗还在睡，箱盖上留了透气孔。"],
 "robot_machinist":["旧哨片送到%s。旁边那颗螺丝是配套的，别弄丢。","%s要这片旧水壶哨片。我用纸包住了边，拆的时候慢一点。"]}
const READABILITY={"id":POLICY,"zoom":0.28,"cell_pixels":72.0,"logical_width":1280,"minimum_body_pixels_1280":60.0,"minimum_preview_seconds":2.5,"nominal_speed":18.0,"rotational_box_7_5_m_reference_x_speed":18.0,"compact_box_3_2_m_reference_x_speed":19.7,"reference_max_abs_y_speed_near_gate":5.0,"reference_craft_radius":3.75,"clearance_margin":1.0,"anchor_x":60.0,"gate_radius":5.0,"inner_arc_samples":9,"level_approach_distance":80.0,"level_exit_distance":20.0,"minimum_remaining_energy":600.0}

class Stream:
 extends RefCounted
 var state:int
 func _init(value:int):state=value
 func take(count:int) -> int:
  state=state*48271%2147483647
  return state%count

static func derived_seed(world_seed:int,day:int,slot:int,kind:String,domain:String) -> int:
 var value:int=5381
 for byte in ("star-courier/%s/%d/%d/%d/%s/%s"%[VERSION,world_seed,day,slot,kind,domain]).to_utf8_buffer():value=(value*33+int(byte))%2147483647
 return maxi(1,value)

static func choices(world_seed:int,day:int,slot:int,kind:String) -> Dictionary:
 # Independent streams: presentation/task choices cannot consume layout draws.
 var layout=Stream.new(derived_seed(world_seed,day,slot,kind,"layout"))
 var task=Stream.new(derived_seed(world_seed,day,slot,kind,"task"))
 var dialogue=Stream.new(derived_seed(world_seed,day,slot,kind,"dialogue"))
 var jitter:Array=[]
 for index in 2:jitter.append([[-2.0,0.0,2.0][layout.take(3)],[-0.5,0.0,0.5][layout.take(3)]])
 return {"jitter":jitter,"careful":task.take(2)==1,"weight_delta":[-0.125,0.0,0.125][task.take(3)],"dialogue":dialogue.take(2)}

static func physical_fields(kind:String) -> Dictionary:
 var t:Dictionary=TEMPLATES[kind]
 var ground:bool=kind=="ground"
 var result:Dictionary={"mode":"pilot","control_version":"pilot-v3","pilot_profile":"pilot-v3","pilot_overdrive":"mounted-output",
  "name":"城市货站 → 屋顶收件台" if ground else "城市升空 → 晨星轨道站","destination_name":"屋顶收件台" if ground else "晨星轨道站",
  "distance":t.distance,"destination_y":-t.altitude,"delivery_radius":t.receiver,"max_delivery_speed":24.0,"boundary_y":t.boundary,
  "time_limit":t.time_limit,"gravity":0.0,"wind":[0.0,0.0],"variation":0.0,"pilot_drag":0.025,"pilot_cruise_speed":18.0,"pilot_boost_speed":22.0,
  "pilot_vertical_speed":5.0,"pilot_net_force_limit":30.0,"pilot_battery_multiplier":20.0,"pilot_energy_tariff":0.025,"pilot_altitude":t.altitude,
  "pilot_climb_start":t.climb_start,"pilot_climb_end":t.climb_end,"lookahead_seconds":3.5,
  "risk":"水平石门 · 中段升空 · 收件限速 24 m/s"}
 if ground:result.merge({"route_profile":"ground-city-v1","route_kind":"ground","background_route":"city","background_ground_y_m":0.0})
 return result
