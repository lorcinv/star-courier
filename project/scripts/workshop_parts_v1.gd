extends RefCounted
## Explicit editor policy only. All 26 runtime IDs and saved signal fields remain
## owned by Parts and the frozen simulation protocols. Rendering never migrates.
const Parts=preload("res://scripts/parts_expanded.gd")
const SCHEMA:String="workshop-parts-core-v1"
const DEFAULT_CATEGORY:String="常用零件"
const CORE:Array[String]=["beam","battery","thruster","armor","shield","drill","teleporter","splitter","spring"]
const SHIP:Array[String]=["beam","battery","thruster","armor","shield","drill","teleporter","splitter"]
const PAD:Array[String]=["beam","battery","thruster","spring"]
const EDGE:Array[String]=["spring","coupler","bomb","teleporter","splitter","accelerator"]
const WAIT:Array[String]=["spring","coupler","bomb","teleporter","splitter"]
const LOGIC:Array[String]=["probe","collision","delay","and_gate","or_gate","not_gate"]
const GROUPS:Dictionary={"飞行基础":["beam","battery","thruster"],"保护货物":["armor","shield"],"路线工具":["drill","teleporter","splitter"],"发射台":["spring"]}
const HINTS:Dictionary={"常用零件":"已拥有的常用零件；旧零件在「旧版保留」。","飞行基础":"梁连接船体，电芯供电，喷口负责飞行。","保护货物":"装甲保护所在位置；护盾用电保护相连船体。","路线工具":"钻头碰石切割；位移和分裂按空格 / 手柄 A。","发射台":"弹簧接上电芯和结构梁，起飞时自动弹射。","旧版保留":"只显示已拥有的旧零件，原有输入、目标和属性继续保留。"}

static func is_core(kind:String) -> bool:return kind in CORE
static func sale_kinds() -> Array:return CORE.duplicate()
static func kind_of(entry:Dictionary) -> String:return str(entry.get("type",entry.get("id","")))
static func group_for(kind:String) -> String:
 for group in GROUPS:
  if kind in GROUPS[group]:return group
 return "旧版保留"
static func _owned(kind:String,parts:Array,inventory:Dictionary) -> bool:
 if int(inventory.get(kind,0))>0:return true
 for part in parts:
  if str(part.get("type",""))==kind:return true
 return false
static func _eligible(entry:Dictionary,parts:Array,inventory:Dictionary,launcher:bool) -> bool:
 var kind:String=kind_of(entry)
 if kind=="cargo":return false
 if launcher and not bool(entry.get("launcher_compatible",kind in Parts.launcher_types())):
  for installed in parts:
   if str(installed.get("type",""))==kind:return true
  return false
 if kind=="spring" and not launcher:return _owned(kind,parts,inventory)
 return is_core(kind) or _owned(kind,parts,inventory)
static func categories(entries:Array,parts:Array,inventory:Dictionary,launcher:bool) -> Array:
 var result:Array=[DEFAULT_CATEGORY]
 for group in ["飞行基础","保护货物","路线工具","发射台","旧版保留"]:
  for entry in entries:
   var kind:String=kind_of(entry)
   var actual:String="旧版保留" if kind=="spring" and not launcher else group_for(kind)
   if _eligible(entry,parts,inventory,launcher) and actual==group:
    result.append(group);break
 return result
static func visible_entries(entries:Array,parts:Array,inventory:Dictionary,category:String,launcher:bool) -> Array:
 var result:Array=[]
 for entry in entries:
  if not _eligible(entry,parts,inventory,launcher):continue
  var kind:String=kind_of(entry)
  var group:String="旧版保留" if kind=="spring" and not launcher else group_for(kind)
  if category==DEFAULT_CATEGORY:
   # A held legacy module is preserved, but ownership never promotes it into
   # the quick palette. Spring belongs to the launcher, even when owned.
   if not kind in (PAD if launcher else SHIP) or not _owned(kind,parts,inventory):continue
  elif category!=group:continue
  result.append(entry)
 return result

## Called only for a player's explicit new placement, never during load/render.
static func new_part(id:int,kind:String,x:int,y:int,parts:Array,launcher:bool,pilot:bool) -> Dictionary:
 var result:Dictionary={"id":id,"type":kind,"x":x,"y":y,"rot":0,"param":Parts.defaults(kind),"input_a":-1,"input_b":-1,"target":-1}
 if not launcher and pilot and kind in ["teleporter","splitter"]:
  result.input_a=-2
  if kind=="splitter":
   var targets:Array=target_options(result,parts)
   if not targets.is_empty():result.target=int(targets[0].id)
 return result

static func adjacent(a:Dictionary,b:Dictionary) -> bool:
 return absi(int(a.get("x",0))-int(b.get("x",0)))+absi(int(a.get("y",0))-int(b.get("y",0)))==1
static func part_name(part:Dictionary) -> String:
 var kind:String=str(part.get("type",""))
 return str(Parts.catalog().get(kind,Parts.cargo_spec() if kind=="cargo" else {}).get("name",kind))
static func reference_label(part:Dictionary) -> String:
 return "%s（%d，%d）"%[part_name(part),int(part.get("x",0)),int(part.get("y",0))]
static func target_options(part:Dictionary,parts:Array) -> Array:
 var result:Array=[]
 var kind:String=str(part.get("type",""))
 var connected:Array=component_ids(part,parts) if kind=="valve" else []
 for candidate in parts:
  if kind=="valve" and not int(candidate.get("id",-1)) in connected:continue
  if int(candidate.get("id",-1))==int(part.get("id",-1)):continue
  if kind not in ["valve","damper"] and not adjacent(part,candidate):continue
  if kind=="splitter" and str(candidate.get("type","")) in ["cargo","splitter"]:continue
  result.append({"id":int(candidate.id),"label":reference_label(candidate),"part":candidate.duplicate(true)})
 return result

## Match the frozen _target order, including an invalid explicit target. Never
## silently substitute a valid neighbor for an invalid saved selection.
static func effective_target(part:Dictionary,parts:Array) -> Dictionary:
 var target:int=int(part.get("target",-1))
 if target>=0:
  for candidate in parts:
   if int(candidate.get("id",-1))==target and target!=int(part.get("id",-1)):return candidate
 # Links are built by pair order; for one receiver this is design order.
 for candidate in parts:
  if int(candidate.get("id",-1))!=int(part.get("id",-1)) and adjacent(part,candidate):return candidate
 return {}
static func component_ids(part:Dictionary,parts:Array) -> Array:
 var ids:Array=[int(part.get("id",-1))];var queue:Array=[part]
 while not queue.is_empty():
  var current:Dictionary=queue.pop_front()
  for candidate in parts:
   var id:int=int(candidate.get("id",-1))
   if not id in ids and adjacent(current,candidate):ids.append(id);queue.append(candidate)
 return ids
static func _reference(id:int,parts:Array) -> String:
 for part in parts:
  if int(part.get("id",-1))==id:return reference_label(part)
 return "已失去的零件 #%d"%id
static func trigger_text(part:Dictionary,parts:Array,pilot:bool,launcher:bool) -> String:
 var kind:String=str(part.get("type",""));var source:int=int(part.get("input_a",-1))
 if kind in ["battery","beam","armor","cargo"]:return "安装后生效，无需按键。"
 if launcher:
  if kind in ["spring","thruster","accelerator"]:
   return "发射时自动释放。" if source<0 else "发射准备由%s控制。"%_reference(source,parts)
  if kind not in Parts.launcher_types():return "此零件不参与发射台工作，原件已保留。"
 if kind=="probe":return "自动检测箭头方向的外部物体，并输出距离信号。"
 if kind=="collision":return "外部接触时输出短暂信号，无需按键。"
 if kind in LOGIC:
  var message:String="旧信号：输入 A = "+("空（假）" if source==-1 else "驾驶按键" if source==-2 and pilot else _reference(source,parts))
  if kind in ["and_gate","or_gate"]:message+="；输入 B = "+("空（假）" if int(part.get("input_b",-1))==-1 else _reference(int(part.input_b),parts))
  return message
 if source>=0:return "沿用控制：%s；须保持结构相连。"%_reference(source,parts)
 if pilot and source==-2:return "空格 / A 同时触发所有手动装置；松开后可再按。" if kind in EDGE else "按住空格 / A 工作，同键手动装置也会启动。"
 if kind in WAIT:return "尚未设置触发，当前不会自行启动。"
 return "自动运行；需要用电的零件须接通电芯。"
static func purpose(kind:String,launcher:bool,version:String) -> String:
 match kind:
  "beam":return "连接船体。过强的拉扯会使连接断裂。"
  "battery":return "为同一船体供电；多装电芯可增加续航，也会增加重量。"
  "thruster":return "按方向飞行，松开方向会耗电减速。" if version=="pilot-free-v1" and not launcher else "沿安装箭头施力，喷焰朝反向。"
  "spring":return "接上电芯和结构梁，起飞时自动弹射。" if launcher else "旧船上弹簧：先蓄能，再触发弹开所选连接。"
  "armor":return "耐撞但较重。装在碰撞方向，只保护它挡住的位置；不会用电。"
  "shield":return "用电抵挡攻击和部分撞击；船体仍会受到冲击。" if version in ["pilot-v3","pilot-free-v1","pilot-v4-wormhole","pilot-v5-protected-bird","pilot-pirate-drill-v1","pilot-pirate-drill-v2"] else "这份旧航线中，护盾只抵挡攻击，不能减轻撞击。"
  "drill":return "钻穿前方石头，耗电较快；绕行更省电。" if version in ["pilot-v3","pilot-free-v1","pilot-v4-wormhole","pilot-v5-protected-bird","pilot-pirate-drill-v1","pilot-pirate-drill-v2"] else "这份旧航线不支持钻头，会按结构梁运行。"
  "teleporter":return "按键沿箭头位移整艘船。落点必须放得下船；每次消耗 25 J。"
  "splitter":return "把相邻零件分成两份更小、更弱的零件，不能复制货物。"
  _:return str(Parts.catalog().get(kind,{}).get("description",""))
static func detail(kind:String) -> String:
 if kind=="drill":return "持续消耗 60 J/s；前端接触可破坏障碍时，每秒最多造成 100 HP 损伤。不可破坏的关卡塔不能钻穿。"
 if kind=="splitter":return "每次需完整 10 J；目标须直接相邻，且不能是货物或分裂核。质量、电量、容量、强度、耐久和输出均分，副本脱离；不会凭空增加资源。"
 return ""

static func local_controls(part:Dictionary,launcher:bool) -> Array:
 var result:Array=[];var kind:String=str(part.get("type",""))
 var schema:Dictionary=Parts.parameter_schema(kind)
 if bool(schema.get("editable",false)):
  var row:Dictionary=schema.duplicate(true);row.kind="slider";row.key="param";row.value=float(part.get("param",schema.default))
  row.label=str({"thruster":"推力强度","spring":"弹射力度","teleporter":"位移距离","damper":"缓冲强度"}.get(kind,schema.label));result.append(row)
 if bool(Parts.controls(kind).get("accepts_target",false)) and not (launcher and kind=="spring"):
  result.append({"kind":"target","key":"target","label":"分裂哪一件" if kind=="splitter" else "作用目标"})
 return result
static func convenience_source(part:Dictionary,pilot:bool,launcher:bool) -> Dictionary:
 var kind:String=str(part.get("type",""));var source:int=int(part.get("input_a",-1))
 if kind in LOGIC or int(Parts.controls(kind).get("inputs",0))<=0:return {}
 if not launcher and pilot and kind in EDGE and source!=-2:return {"label":"改为按键触发","source":-2}
 if not kind in WAIT and source!=-1:return {"label":"改为自动运行","source":-1}
 if launcher and kind=="spring" and source>=0:return {"label":"改为发射时自动释放","source":-1}
 return {}

## Assembly-time readiness, explicitly not a prediction of remaining in-flight
## charge/exit clearance. Runtime checks remain the authoritative old solver.
static func readiness(part:Dictionary,parts:Array,pilot:bool,launcher:bool) -> Dictionary:
 var kind:String=str(part.get("type",""));var ids:Array=component_ids(part,parts)
 var result:Dictionary={"ready":true,"text":"","target_id":-1,"valid_targets":target_options(part,parts).map(func(row):return int(row.id))}
 if not kind in ["splitter","teleporter"]:return result
 if launcher:result.ready=false;result.text="此装置只能在飞行器上使用。";return result
 if kind=="splitter":
  var target:Dictionary=effective_target(part,parts)
  if target.is_empty():result.ready=false;result.text="没有相邻目标。先在旁边装一件可分裂零件。";return result
  result.target_id=int(target.id)
  if str(target.get("type",""))=="cargo":result.ready=false;result.text="当前目标是货物，不能分裂。请在下方选择别的相邻零件。";return result
  if str(target.get("type",""))=="splitter":result.ready=false;result.text="分裂核不能互相复制。请选择别的相邻零件。";return result
  if not adjacent(part,target):result.ready=false;result.text="原目标已不相邻，不能分裂。请重新选择。";return result
 var battery:bool=false;var cargo:bool=false
 for candidate in parts:
  if not int(candidate.get("id",-1)) in ids:continue
  if str(candidate.get("type",""))=="battery":battery=true
  if str(candidate.get("type",""))=="cargo":cargo=true
  if str(candidate.get("type",""))=="valve" and (int(candidate.get("target",-1))==int(part.id) or (int(candidate.get("target",-1))<0 and adjacent(candidate,part))):
   result.ready=false;result.text="旧功率阀限制了瞬时供电，无法支付本次触发能量。移开该阀或更换它的作用目标。";return result
 if not battery:result.ready=false;result.text="未接通电芯，无法触发。";return result
 var source:int=int(part.get("input_a",-1))
 if source==-2 and pilot and not cargo:result.ready=false;result.text="装置未与货物相连，收不到驾驶按键。";return result
 if source<0 and not (pilot and source==-2):result.ready=false;result.text="等待设置触发。";return result
 if source>=0 and not source in ids:result.ready=false;result.text="控制零件已断开，收不到信号。";return result
 result.text="装配就绪：按空格 / 手柄 A 分裂高亮目标。" if kind=="splitter" and source==-2 else "装配就绪：按空格 / 手柄 A 位移；飞行时仍需余电和安全落点。" if source==-2 else "装配就绪：等待原控制信号；飞行时仍需余电。"
 return result
