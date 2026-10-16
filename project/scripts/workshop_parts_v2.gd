extends RefCounted
## dev04 editor policy. Frozen runtime registries remain intact for replay.
## Only the explicit PartsMigrationV2 transaction retires old owned property.
const DeliveryUI=preload("res://scripts/delivery_ui_v3.gd")
const Parts=preload("res://scripts/parts_expanded.gd")
const CouplerCutPreview=preload("res://scripts/coupler_cut_preview.gd")
const SCHEMA:String="workshop-parts-mechanical-v2"
const DEFAULT_CATEGORY:String="常用零件"
const CORE:Array[String]=["beam","battery","thruster","armor","shield","drill","teleporter","splitter","spring"]
const ADDED:Array[String]=["coupler","damper","accelerator","heater","airbrake","solid_booster"]
const SHIP:Array[String]=["heater","airbrake","solid_booster","beam","battery","thruster","armor","shield","drill","teleporter","splitter","coupler","damper","accelerator"]
const PAD:Array[String]=["beam","battery","thruster","armor","accelerator","spring"]
const EDGE:Array[String]=["spring","coupler","bomb","teleporter","splitter","accelerator"]
const WAIT:Array[String]=["spring","coupler","bomb","teleporter","splitter"]
const LOGIC:Array[String]=["probe","collision","delay","and_gate","or_gate","not_gate"]
const GROUPS:Dictionary={"飞行基础":["beam","battery","thruster","airbrake","solid_booster"],"保护货物":["armor","shield","damper","heater"],"路线工具":["drill","teleporter","splitter","coupler","accelerator"],"发射台":["spring"]}
const HINTS:Dictionary={"常用零件":"飞行器和发射台共用库存；仅显示当前可用零件。","飞行基础":"梁连接结构，电芯供电，喷口提供推力。","保护货物":"装甲挡撞击，护盾耗电吸收伤害，缓冲器抑制旋转。","路线工具":"钻头切石；Q / 手柄 Y 选装置，空格 / A 触发。","发射台":"弹簧储能弹射；喷口短推；加速器加速。接上电芯和梁或装甲底座。"}

static func is_core(kind:String) -> bool:return kind in CORE or kind in ADDED
static func sale_kinds() -> Array:return CORE.duplicate()+ADDED.duplicate()
static func compatible(kind:String,launcher:bool,version:String="") -> bool:return kind in (PAD if launcher else SHIP) or (not launcher and version in ["pilot-delivery-v3","pilot-ascent-v4","pilot-rift-v5","pilot-delivery-v6","pilot-ascent-v6","pilot-rift-v6","pilot-delivery-v7","pilot-ascent-v7","pilot-rift-v7","pilot-delivery-v8","pilot-ascent-v8","pilot-rift-v8"] and kind=="spring")
static func placement_error(kind:String,launcher:bool,version:String="") -> String:
 if compatible(kind,launcher,version):return ""
 if kind=="spring" and not launcher:return "蓄能弹簧用于发射台，请切到发射台安装。"
 return "这件零件用于飞行器，发射台无法使用。" if is_core(kind) else "此零件已退出当前装配。请先确认整理旧库存。"
static func kind_of(entry:Dictionary) -> String:return str(entry.get("type",entry.get("id","")))
static func group_for(kind:String,version:String="",launcher:bool=false) -> String:
 if kind=="spring" and version in ["pilot-delivery-v3","pilot-ascent-v4","pilot-rift-v5","pilot-delivery-v6","pilot-ascent-v6","pilot-rift-v6","pilot-delivery-v7","pilot-ascent-v7","pilot-rift-v7","pilot-delivery-v8","pilot-ascent-v8","pilot-rift-v8"] and not launcher:return "保护货物"
 for group in GROUPS:
  if kind in GROUPS[group]:return group
 return ""
static func _owned(kind:String,parts:Array,inventory:Dictionary) -> bool:
 if int(inventory.get(kind,0))>0:return true
 for part in parts:
  if str(part.get("type",""))==kind:return true
 return false
static func _eligible(entry:Dictionary,_parts:Array,_inventory:Dictionary,launcher:bool,version:String="") -> bool:
 return compatible(kind_of(entry),launcher,version)
static func categories(entries:Array,parts:Array,inventory:Dictionary,launcher:bool,version:String="") -> Array:
 var result:Array=[DEFAULT_CATEGORY]
 for group in GROUPS:
  for entry in entries:
   if _eligible(entry,parts,inventory,launcher,version) and group_for(kind_of(entry),version,launcher)==group:
    result.append(group);break
 return result
static func visible_entries(entries:Array,parts:Array,inventory:Dictionary,category:String,launcher:bool,version:String="") -> Array:
 var result:Array=[]
 for entry in entries:
  if not _eligible(entry,parts,inventory,launcher,version):continue
  var kind:String=kind_of(entry)
  if category==DEFAULT_CATEGORY:
   if not _owned(kind,parts,inventory):continue
  elif category!=group_for(kind,version,launcher):continue
  result.append(entry)
 return result

## Called only for a player's explicit new placement, never during load/render.
static func new_part(id:int,kind:String,x:int,y:int,parts:Array,launcher:bool,pilot:bool,version:String="") -> Dictionary:
 var result:Dictionary={"id":id,"type":kind,"x":x,"y":y,"rot":0,"param":Parts.defaults(kind),"input_a":-1,"input_b":-1,"target":-1}
 if not compatible(kind,launcher,version):return {}
 if launcher and kind=="spring":result.param=60.0
 if not launcher and pilot and kind in ["teleporter","splitter","coupler","accelerator","airbrake","solid_booster"]:
  result.input_a=-2
  if kind in ["splitter","coupler","accelerator"]:
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
## The frozen solver may resolve a missing/self saved ID to the first socket.
## Report that projection without changing the saved target or blocking its use.
static func target_warning(part:Dictionary,target:Dictionary) -> String:
 if int(part.get("target",-1))>=0 and not target.is_empty() and int(part.target)!=int(target.get("id",-1)):
  return "原目标不可用，将作用于%s；请重新选定。"%reference_label(target)
 return ""
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
static func trigger_text(part:Dictionary,parts:Array,pilot:bool,launcher:bool,version:String="pilot-free-v2") -> String:
 var kind:String=str(part.get("type",""));var source:int=int(part.get("input_a",-1))
 if kind in ["battery","beam","armor","cargo"]:return "安装后生效，无需按键。"
 if version in ["pilot-delivery-v3","pilot-ascent-v4","pilot-rift-v5","pilot-delivery-v6","pilot-ascent-v6","pilot-rift-v6","pilot-delivery-v7","pilot-ascent-v7","pilot-rift-v7","pilot-delivery-v8","pilot-ascent-v8","pilot-rift-v8"] and not launcher and kind=="spring":return "与货物直接相连时自动缓冲；无需按键，不消耗电量。"
 if kind=="damper":return "自动抑制旋转；与货物直接相连时缓和货物冲击，不耗电。" if version in ["pilot-delivery-v3","pilot-ascent-v4","pilot-rift-v5","pilot-delivery-v6","pilot-ascent-v6","pilot-rift-v6","pilot-delivery-v7","pilot-ascent-v7","pilot-rift-v7","pilot-delivery-v8","pilot-ascent-v8","pilot-rift-v8"] else "自动抑制旋转，不耗电；无需按键。"
 if launcher:
  if kind in ["spring","thruster","accelerator"]:
   return "发射时自动释放；与飞行器共用库存，使用台上电芯。"
  if kind not in Parts.launcher_types():return "此零件不参与发射台工作，原件已保留。"
 if kind=="probe":return "自动检测箭头方向的外部物体，并输出距离信号。"
 if kind=="collision":return "外部接触时输出短暂信号，无需按键。"
 if kind in LOGIC:
  var message:String="旧信号：输入 A = "+("空（假）" if source==-1 else "驾驶按键" if source==-2 and pilot else _reference(source,parts))
  if kind in ["and_gate","or_gate"]:message+="；输入 B = "+("空（假）" if int(part.get("input_b",-1))==-1 else _reference(int(part.input_b),parts))
  return message
 if source>=0:return "沿用控制：%s；须保持结构相连。"%_reference(source,parts)
 if kind=="solid_booster":return "Q选择/空格一次点火；燃烧不能关停，燃尽不能重启。"
 if pilot and source==-2 and version in ["pilot-free-v2","pilot-delivery-v3","pilot-ascent-v4","pilot-rift-v5","pilot-delivery-v6","pilot-ascent-v6","pilot-rift-v6","pilot-delivery-v7","pilot-ascent-v7","pilot-rift-v7","pilot-delivery-v8","pilot-ascent-v8","pilot-rift-v8"] and kind=="accelerator":return "Q / 手柄 Y 选择此装置，再按空格 / A；一次航程发射一次。"
 if pilot and source==-2 and version in ["pilot-free-v2","pilot-delivery-v3","pilot-ascent-v4","pilot-rift-v5","pilot-delivery-v6","pilot-ascent-v6","pilot-rift-v6","pilot-delivery-v7","pilot-ascent-v7","pilot-rift-v7","pilot-delivery-v8","pilot-ascent-v8","pilot-rift-v8"]:return "Q / 手柄 Y 选择此装置，再按空格 / A；松开后可再触发。" if kind in EDGE else "选中此装置后，按住空格 / A 工作。"
 if pilot and source==-2:return "空格 / A 同时触发所有手动装置；松开后可再按。" if kind in EDGE else "按住空格 / A 工作，同键手动装置也会启动。"
 if kind in WAIT:return "尚未设置触发，当前不会自行启动。"
 return "自动运行；需要用电的零件须接通电芯。"
static func purpose(kind:String,launcher:bool,version:String) -> String:
 if kind=="shield" and version in DeliveryUI.SHIELD_VERSIONS:return "只保护同电路且格心在局部圈内的部件；分裂后保护面积缩小。实际吸收才耗电，不免疫冷损、乱流或发射加速度。"
 if version in DeliveryUI.MATERIAL_VERSIONS:
  if not launcher and kind=="spring":return "紧邻货物时缓和冲击；分裂会减少弹簧的有效储能和承载。"
  if not launcher and kind=="damper":return "被动减轻旋转和货物冲击；重载更难缓住，分裂后阻尼减弱。"
  if kind=="splitter":return "将相邻零件分成两份；材料、储能和阻尼随之分配，不能复制货物。"
 if version in DeliveryUI.CELL_VERSIONS:
  if not launcher and kind=="accelerator":return "切开所选接口，将目标侧整组弹出，载体承受反冲；有旁路连接时不发射。裸货也能合法滑行收件。"
  if kind=="battery":return "同电路电芯按可用电量比例供电；断开后只给各自连通组供电。多装会增加重量。"
 if version in ["pilot-delivery-v3","pilot-ascent-v4","pilot-rift-v5","pilot-delivery-v6","pilot-ascent-v6","pilot-rift-v6","pilot-delivery-v7","pilot-ascent-v7","pilot-rift-v7","pilot-delivery-v8","pilot-ascent-v8","pilot-rift-v8"]:
  if launcher:
   if kind=="spring":return "与电芯、底座相连时储能弹射；多件的有效储能相加。发射角与总力度在预览中调整。"
   if kind=="thruster":return "将推力转为一次发射做功，与台上其他驱动件合计；受电量和底座承载限制。"
   if kind=="accelerator":return "把设定速度对应的能量加入发射总量；共用发射角，受电量和底座承载限制。"
  else:
   if kind=="spring":return "紧邻货物并直接连接，形成柔性支撑，缓和加速度和落地冲击；多件可组合承载。"
   if kind=="damper":return "抑制船体旋转；紧邻货物时进一步摊开加速度和碰撞冲击，不耗电。"
   if kind=="teleporter":return "沿当前或最近驾驶方向位移整船并保留速度；每千克每米消耗6 J，重船或长距离更费电。落点须容纳整船。"
 if launcher:
  match kind:
   "beam":return "支撑发射台。加装梁能承受更强的弹射。"
   "armor":return "用作更稳固的底座，让发射台能弹得更有力。"
   "battery":return "给相连台上零件供电；不消耗船上电芯。"
   "thruster":return "沿箭头给飞行器一次短推；推力强度越高，起步越快。"
   "accelerator":return "沿箭头将飞行器加速到设定速度，受电量和底座承载限制。"
 match kind:
  "cargo":return "委托货物，保护它并送到收件处。"
  "beam":return "连接船体。过强的拉扯会使连接断裂。"
  "battery":return "为同一船体供电；多装电芯可增加续航，也会增加重量。"
  "thruster":
   if version in ["pilot-free-v2","pilot-delivery-v3","pilot-ascent-v4","pilot-rift-v5","pilot-delivery-v6","pilot-ascent-v6","pilot-rift-v6","pilot-delivery-v7","pilot-ascent-v7","pilot-rift-v7","pilot-delivery-v8","pilot-ascent-v8","pilot-rift-v8"]:return "按方向持续推进，松开滑行；Ctrl / 手柄左扳机耗电刹车。"
   return "按方向飞行，松开方向会耗电减速。" if version=="pilot-free-v1" and not launcher else "沿安装箭头施力，喷焰朝反向。"
  "spring":return "发射台专用：接上电芯和梁或装甲，起飞时弹出飞行器；调整储能可改变弹射速度。"
  "armor":return "耐撞但较重。装在碰撞方向，只保护它挡住的位置；不会用电。"
  "shield":return "用电抵挡攻击和部分撞击；船体仍会受到冲击。" if version in ["pilot-v3","pilot-free-v1","pilot-free-v2","pilot-delivery-v3","pilot-ascent-v4","pilot-rift-v5","pilot-delivery-v6","pilot-ascent-v6","pilot-rift-v6","pilot-delivery-v7","pilot-ascent-v7","pilot-rift-v7","pilot-delivery-v8","pilot-ascent-v8","pilot-rift-v8","pilot-v4-wormhole","pilot-v5-protected-bird","pilot-pirate-drill-v1","pilot-pirate-drill-v2"] else "这份旧航线中，护盾只抵挡攻击，不能减轻撞击。"
  "drill":return "钻穿前方石头，耗电较快；绕行更省电。" if version in ["pilot-v3","pilot-free-v1","pilot-free-v2","pilot-delivery-v3","pilot-ascent-v4","pilot-rift-v5","pilot-delivery-v6","pilot-ascent-v6","pilot-rift-v6","pilot-delivery-v7","pilot-ascent-v7","pilot-rift-v7","pilot-delivery-v8","pilot-ascent-v8","pilot-rift-v8","pilot-v4-wormhole","pilot-v5-protected-bird","pilot-pirate-drill-v1","pilot-pirate-drill-v2"] else "这份旧航线不支持钻头，会按结构梁运行。"
  "coupler":return "按键断开与所选相邻零件的连接；仍有其他连接时不会分开。"
  "damper":return "自动减轻船体旋转，损失的运动变成热；不耗电。"
  "accelerator":return "按键将所选相邻零件弹出；船体承受反冲，一次航程发射一次。"
  "teleporter":return "选中后沿驾驶方向位移整艘船；松开方向沿最近方向。落点必须放得下船，每次消耗 25 J。" if version in ["pilot-free-v2","pilot-delivery-v3","pilot-ascent-v4","pilot-rift-v5","pilot-delivery-v6","pilot-ascent-v6","pilot-rift-v6","pilot-delivery-v7","pilot-ascent-v7","pilot-rift-v7","pilot-delivery-v8","pilot-ascent-v8","pilot-rift-v8"] else "按键沿箭头位移整艘船。落点必须放得下船；每次消耗 25 J。"
  "splitter":return "把相邻零件分成两份更小、更弱的零件，不能复制货物。"
  _:return str(Parts.catalog().get(kind,{}).get("description",""))
static func detail(kind:String,version:String="") -> String:
 if version in DeliveryUI.MATERIAL_VERSIONS:
  if kind=="spring":return "标称0–60 J；有效储能随剩余材料和完好程度减少。船上直接连接货物，按真实承载与货物质量重算柔性响应；台上仍受电量与底座限制。"
  if kind=="damper":return "阻尼随剩余材料减少；平动衰减取决于两侧质量，消旋取决于实际转动惯量。损失的动能变成热，不回充；不能消除持续过载。"
  if kind=="splitter":return "每次需完整10 J；质量、电量、耐久和材料均分，副本脱离。弹簧容量和阻尼随材料减少，柔性响应重新计算；不会增加总资源，不能分裂货物或分裂核。"
 if version in DeliveryUI.CELL_VERSIONS and kind=="accelerator":return "按载荷组和载体的真实质量支付动能并产生反冲；有限行程产生货物冲击。保留组内连接、电量与货物状态；旁路、缺电或净空不足时不拆件、不扣能。台上仍计入发射总能量。"
 if version in ["pilot-delivery-v3","pilot-ascent-v4","pilot-rift-v5","pilot-delivery-v6","pilot-ascent-v6","pilot-rift-v6","pilot-delivery-v7","pilot-ascent-v7","pilot-rift-v7","pilot-delivery-v8","pilot-ascent-v8","pilot-rift-v8"]:
  if kind=="spring":return "每件0–60 J。台上按有效储能叠加，实际输出受相连电芯与底座承载限制；船上直接连货物时提供柔性支撑，零储能不产生缓冲。"
  if kind=="damper":return "阻尼值越高，旋转衰减越强；直接连到货物时还会延长冲击传递时间。多件实际阻尼相加，不能消除持续过载。"
  if kind=="teleporter":return "实际消耗=当前连通刚体质量×位移距离×6 J/(kg·m)。不抵消已有速度，不绕过出口净空检查。"
  if kind=="accelerator":return "台上按本件质量及设定速度计入可释放动能，与其他驱动件合计；船上仍按所选相邻零件计算实际弹出动能及反冲。"
 if kind=="beam":return "船体连接承载32 N；在发射台上，每件提供32 N底座承载。"
 if kind=="armor":return "飞行器上有150 HP局部耐久；在发射台上，每件提供90 N底座承载。"
 if kind=="spring":return "台上弹簧可设0–60 J；电芯只支付实际输出的能量，承载不足时限制推力，不损坏零件。"
 if kind=="coupler":return "无需能量；每次按键只断开选中的一个接口。多条连接须分别拆开。"
 if kind=="damper":return "同体目标将角速度按阻尼系数衰减；可连接目标不增加能量。"
 if kind=="accelerator":return "消耗弹射所需动能；弹出非货物按弹药计费，货物不能被复制。"
 if kind=="drill":return "持续消耗 60 J/s；前端接触可破坏障碍时，每秒最多造成 100 HP 损伤。不可破坏的关卡塔不能钻穿。"
 if kind=="splitter":return "每次需完整 10 J；目标须直接相邻，且不能是货物或分裂核。质量、电量、容量、强度、耐久和输出均分，副本脱离；不会凭空增加资源。"
 return ""

static func local_controls(part:Dictionary,launcher:bool,version:String="") -> Array:
 var result:Array=[];var kind:String=str(part.get("type",""))
 var schema:Dictionary=Parts.parameter_schema(kind)
 if bool(schema.get("editable",false)):
  var row:Dictionary=schema.duplicate(true);row.kind="slider";row.key="param";row.value=float(part.get("param",schema.default))
  row.label=str({"thruster":"推力强度","spring":"弹射力度","teleporter":"位移距离","damper":"缓冲强度","accelerator":"弹出速度"}.get(kind,schema.label))
  if version in ["pilot-delivery-v3","pilot-ascent-v4","pilot-rift-v5","pilot-delivery-v6","pilot-ascent-v6","pilot-rift-v6","pilot-delivery-v7","pilot-ascent-v7","pilot-rift-v7","pilot-delivery-v8","pilot-ascent-v8","pilot-rift-v8"] and kind=="spring":row.label="储能" if launcher else "柔性储能"
  result.append(row)
 if bool(Parts.controls(kind).get("accepts_target",false)) and kind!="damper" and not (version in ["pilot-delivery-v3","pilot-ascent-v4","pilot-rift-v5","pilot-delivery-v6","pilot-ascent-v6","pilot-rift-v6","pilot-delivery-v7","pilot-ascent-v7","pilot-rift-v7","pilot-delivery-v8","pilot-ascent-v8","pilot-rift-v8"] and kind=="spring") and not (launcher and kind in ["spring","accelerator"]):
  result.append({"kind":"target","key":"target","label":"分裂哪一件" if kind=="splitter" else "断开哪一件" if kind=="coupler" else ("弹出哪侧整组" if version in DeliveryUI.CELL_VERSIONS else "弹出哪一件") if kind=="accelerator" else "作用目标"})
 return result
static func convenience_source(part:Dictionary,pilot:bool,launcher:bool,version:String="") -> Dictionary:
 var kind:String=str(part.get("type",""));var source:int=int(part.get("input_a",-1))
 if version in ["pilot-delivery-v3","pilot-ascent-v4","pilot-rift-v5","pilot-delivery-v6","pilot-ascent-v6","pilot-rift-v6","pilot-delivery-v7","pilot-ascent-v7","pilot-rift-v7","pilot-delivery-v8","pilot-ascent-v8","pilot-rift-v8"] and not launcher and kind=="spring":return {}
 if kind in LOGIC or int(Parts.controls(kind).get("inputs",0))<=0:return {}
 # An explicit current ship edit only. Loading/rendering keeps automatic and
 # externally wired drills exact; held drills are not edge-triggered devices.
 if kind=="solid_booster" and source==-1:return {"label":"改为按键点火","source":-2}
 if kind in ["drill","heater","airbrake"] and version in ["pilot-free-v2","pilot-delivery-v3","pilot-ascent-v4","pilot-rift-v5","pilot-delivery-v6","pilot-ascent-v6","pilot-rift-v6","pilot-delivery-v7","pilot-ascent-v7","pilot-rift-v7","pilot-delivery-v8","pilot-ascent-v8","pilot-rift-v8"] and pilot and not launcher and source==-1:return {"label":"改为按住启动","source":-2}
 if not launcher and pilot and kind in EDGE and source!=-2:return {"label":"改为按键触发","source":-2}
 if not kind in WAIT and source!=-1:return {"label":"改为自动运行","source":-1}
 if launcher and kind=="spring" and source>=0:return {"label":"改为发射时自动释放","source":-1}
 return {}

## Assembly-time readiness, explicitly not a prediction of remaining in-flight
## charge/exit clearance. Runtime checks remain the authoritative old solver.
static func readiness(part:Dictionary,parts:Array,pilot:bool,launcher:bool,version:String="") -> Dictionary:
 var kind:String=str(part.get("type",""));var ids:Array=component_ids(part,parts)
 var result:Dictionary={"ready":true,"warning":false,"text":"","target_id":-1,"valid_targets":target_options(part,parts).map(func(row):return int(row.id))}
 # Existing order cargo is not a sale/placement kind. Its power status is
 # presented separately; never direct it to retired-inventory conversion.
 if kind=="cargo" and not launcher:return result
 if not compatible(kind,launcher,version):result.ready=false;result.text=placement_error(kind,launcher,version);return result
 if launcher:
  if kind in ["spring","thruster","accelerator"]:
   var supports:bool=false;var power:bool=false
   for item in parts:
    if not int(item.get("id",-1)) in ids:continue
    if str(item.type) in ["beam","armor"]:supports=true
    if str(item.type)=="battery":power=true
   result.ready=supports and power
   result.text=("发射就绪：台上电芯供电，按预览角度和力度释放。" if version in ["pilot-delivery-v3","pilot-ascent-v4","pilot-rift-v5","pilot-delivery-v6","pilot-ascent-v6","pilot-rift-v6","pilot-delivery-v7","pilot-ascent-v7","pilot-rift-v7","pilot-delivery-v8","pilot-ascent-v8","pilot-rift-v8"] else "发射就绪：台上电芯供电，按箭头弹出飞行器。") if result.ready else "请连接电芯与结构梁或装甲底座。"
  return result
 if kind=="solid_booster":
  result.text="一次点火后不可关停；固定箭头28N/12秒，满罐补充20元。燃尽剩0.8kg壳，可用分离扣抛弃。"
  return result
 if kind=="heater":
  var mounted:bool=false;var battery:bool=false
  for candidate in parts:
   if str(candidate.type)=="cargo" and adjacent(part,candidate):mounted=true
   if str(candidate.type)=="battery" and int(candidate.id) in ids:battery=true
  result.ready=mounted and battery;result.warning=not result.ready
  result.text="直接连接货物且组件内有电芯；冷区实际供电才保温。" if result.ready else "须直接相邻货物，并在同一连接组件安装电芯。"
  return result
 if kind=="airbrake":
  result.text="Q选择后按住空格展开；空气中减速，真空无效。偏心安装会扭转船体。"
  return result
 if kind=="spring" and version in ["pilot-delivery-v3","pilot-ascent-v4","pilot-rift-v5","pilot-delivery-v6","pilot-ascent-v6","pilot-rift-v6","pilot-delivery-v7","pilot-ascent-v7","pilot-rift-v7","pilot-delivery-v8","pilot-ascent-v8","pilot-rift-v8"]:
  var mounted:bool=false
  for candidate in parts:
   if str(candidate.get("type",""))=="cargo" and adjacent(part,candidate) and (int(part.get("target",-1))<0 or int(part.target)==int(candidate.id)):mounted=true
  result.ready=mounted and float(part.get("param",0.0))>0.0
  result.warning=not result.ready
  result.text="柔性支撑就绪：直接连接货物，自动缓和冲击。" if result.ready else "直接装在货物相邻格，并设置大于0的柔性储能。"
  return result
 if kind=="coupler":
  var target:Dictionary=effective_target(part,parts)
  result.target_id=int(target.get("id",-1));result.ready=not target.is_empty() and adjacent(part,target)
  if not result.ready:result.text="先选择一个相邻零件。";return result
  # A valid socket alone cannot receive a trigger. Couplers need no battery,
  # but obey the same cockpit/source connectivity as the frozen live solver.
  var source:int=int(part.get("input_a",-1))
  if source==-2 and pilot:
   var cargo_connected:bool=false
   for candidate in parts:
    if int(candidate.get("id",-1)) in ids and str(candidate.get("type",""))=="cargo":cargo_connected=true;break
   if not cargo_connected:result.ready=false;result.text="未连接货物，收不到驾驶按键。";return result
   result.text="接口就绪："
  elif source<0:result.ready=false;result.text="尚未设置触发，当前不会自行启动。"
  elif not source in ids:result.ready=false;result.text="控制零件已断开，收不到信号。"
  else:result.text="接口就绪：等待原控制信号；"
  if result.ready:
   result.text+=CouplerCutPreview.text(CouplerCutPreview.from_design(part,target,parts))+"。"
   var warning:String=target_warning(part,target)
   if not warning.is_empty():result.text+="\n"+warning;result.warning=true
  return result
 if not kind in ["splitter","teleporter","accelerator"]:return result
 if launcher:result.ready=false;result.text="此装置只能在飞行器上使用。";return result
 if kind in ["splitter","accelerator"]:
  var target:Dictionary=effective_target(part,parts)
  if target.is_empty():result.ready=false;result.text="没有相邻目标。先在旁边装一件可操作零件。";return result
  result.target_id=int(target.id)
  if kind=="splitter" and str(target.get("type",""))=="cargo":result.ready=false;result.text="当前目标是货物，不能分裂。请在下方选择别的相邻零件。";return result
  if kind=="splitter" and str(target.get("type",""))=="splitter":result.ready=false;result.text="分裂核不能互相复制。请选择别的相邻零件。";return result
  if not adjacent(part,target):result.ready=false;result.text="原目标已不相邻，无法操作。请重新选择。";return result
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
 if kind=="accelerator" and version in DeliveryUI.CELL_VERSIONS:
  var target:Dictionary=effective_target(part,parts)
  if CouplerCutPreview.from_design(part,target,parts):result.ready=false;result.text="旁路仍相连，不能弹射。";return result
  result.text="目标侧整组弹出；裸货可滑行，主动装置仍需电。"
  return result
 if kind=="accelerator":
  result.text="装配就绪：按键弹出高亮零件；飞行时仍需足够电量。" if source==-2 else "装配就绪：等待原控制信号，弹出高亮零件；飞行时仍需足够电量。"
  var target:Dictionary=effective_target(part,parts)
  var warning:String=target_warning(part,target)
  if not warning.is_empty():result.text+="\n"+warning;result.warning=true
  if pilot and version in ["pilot-free-v2","pilot-delivery-v3","pilot-ascent-v4","pilot-rift-v5"] and str(target.get("type",""))=="cargo":
   result.text+="\n弹出货舱会断开供电，未在本次弹出时安全入收件圈会失败。";result.warning=true
  return result
 result.text="装配就绪：Q / 手柄 Y 选中此装置，再按空格 / A 分裂高亮目标。" if kind=="splitter" and source==-2 else "装配就绪：Q / 手柄 Y 选中此装置，再按空格 / A 位移；飞行时仍需余电和安全落点。" if source==-2 else "装配就绪：等待原控制信号；飞行时仍需余电。"
 if kind=="splitter":
  var warning:String=target_warning(part,effective_target(part,parts))
  if not warning.is_empty():result.text+="\n"+warning;result.warning=true
 return result
