extends RefCounted
## Presentation only. Existing param/input_a/input_b/target values remain the contract.
## Keep ship actions separate from the launchpad's preparation-time behavior.
const EDGE_ACTIONS:Array[String]=["spring","coupler","bomb","teleporter","splitter","accelerator"]
const WAIT_FOR_TRIGGER:Array[String]=["spring","coupler","bomb","teleporter","splitter"]
const LOGIC_PARTS:Array[String]=["probe","collision","delay","and_gate","or_gate","not_gate"]

static func describe(part:Dictionary,pilot:bool,launcher:bool) -> Dictionary:
 var kind:String=str(part.get("type",""))
 var source:int=int(part.get("input_a",-1))
 var spec:Dictionary=part.get("spec",{})
 var detail:String=str(part.get("description",spec.get("description","")))
 var result:Dictionary={"description":detail,"detail":detail,"parameter_label":"","parameter_tip":"","status":"","status_tip":"","advanced_hint":""}
 if kind=="thruster":
  result.description="箭头是安装推力方向，喷焰朝反向。需要接通电池。"
  result.parameter_label="推力强度"
  result.parameter_tip="推力越强，耗电越多。"
 elif kind=="spring":
  result.description="用电池蓄能，起飞时弹出飞行器。" if launcher else "先用电池蓄能，再由触发释放。"
  result.parameter_label="弹射力度"
  result.parameter_tip="先蓄能，再弹出；力度越大，需要的电量越多。"
 var controls:Variant=part.get("controls",{})
 var has_input:bool=int(controls.get("inputs",0))>0 if controls is Dictionary else false
 if controls is Array:
  for row in controls:
   if str(row.get("key",""))=="input_a":has_input=true
 if has_input and not kind in LOGIC_PARTS:
  if source>=0:
   result.status="启动：使用已有控制"
   result.status_tip="由 #%d 控制；断开连接后停止响应。"%source
  elif launcher:
   result.status="启动：发射时自动释放" if kind in ["spring","thruster","accelerator"] else "启动：默认运行"
   result.status_tip="电池负责蓄能，支撑梁承受弹射力。"
  elif pilot and source==-2:
   result.status="启动：按下 Space / 手柄 A" if kind in EDGE_ACTIONS else "启动：按住 Space / 手柄 A"
   result.status_tip="只在与货物相连的存活结构内生效。按住持续提供信号；一次性装置只在按下瞬间触发。"
  elif kind in WAIT_FOR_TRIGGER:
   result.status="启动：等待触发 · 在高级控制中设置"
   result.status_tip="当前没有触发输入。蓄能弹簧会自动充能，但飞行器上的弹簧不会自行释放。"
  else:
   result.status="启动：自动运行"
   result.status_tip="无需额外触发；需要供电的零件仍须接通电池。"
 if has_input:
  result.advanced_hint="信号是开 / 关指令，不是电源线。输入来自下方所选模块；接线两端须保持结构相连。"
  if pilot and not launcher:result.advanced_hint+=" 驾驶回路在按住 Space / 手柄 A 时开启。"
  if launcher:result.advanced_hint+=" 发射台在起飞准备时读取模块信号。"
 if kind=="spring" and not launcher:result.advanced_hint+=" 弹簧在信号由关变开时释放一次；还有其他结构连接时可能无法弹开。"
 result.description=simple_purpose(kind,launcher)
 if kind=="spring" and launcher:result.detail="发射台用相连的电池蓄能，需要结构梁承载；起飞时自动释放。"
 return result

static func target_hint(kind:String,launcher:bool) -> String:
 if launcher and kind=="spring":return "发射台弹射无需目标。"
 if launcher:return "发射台的转台和功率阀可以指定目标。"
 if kind=="valve":return "未指定时限制相邻用电模块；指定后只限制该模块。"
 return "未指定时，自动取连接顺序中的第一个相邻模块；并非没有目标。具体作用仍受模块类型和结构连接限制。"

# A view over the existing catalogue, never a replacement registry or unlock list.
# Cargo is delivered by the order flow and is not a placeable catalogue item.
const BASIC_GROUPS:Dictionary={
 "船体":["beam","damper"],
 "动力":["thruster","spring"],
 "能源":["battery","valve"],
 "防护工具":["armor","shield","drill"]
}
const GROUP_HINTS:Dictionary={
 "现有库存":"挑一件零件，点空格装上。",
 "船体":"连接与缓冲，让飞行器保持完整。",
 "动力":"推进与起飞弹射。",
 "能源":"储存电量，控制供电。",
 "防护工具":"保护货物，处理前方障碍。",
 "高级零件":"特殊工具与联动零件。"
}

static func group_for(kind:String) -> String:
 if kind=="cargo":return ""
 for group in BASIC_GROUPS:
  if kind in BASIC_GROUPS[group]:return group
 return "高级零件"

static func eligible(entry:Dictionary,launcher:bool) -> bool:
 var kind:String=str(entry.get("type",entry.get("id","")))
 if kind=="cargo":return false
 return not launcher or not entry.has("launcher_compatible") or bool(entry.launcher_compatible)

static func categories(entries:Array,launcher:bool) -> Array:
 var result:Array=["现有库存"]
 for group in ["船体","动力","能源","防护工具","高级零件"]:
  for entry in entries:
   if eligible(entry,launcher) and group_for(str(entry.get("type",entry.get("id",""))))==group:
    result.append(group);break
 return result

static func visible_entries(entries:Array,parts:Array,inventory:Dictionary,category:String,launcher:bool) -> Array:
 var result:Array=[]
 for entry in entries:
  if not eligible(entry,launcher):continue
  var kind:String=str(entry.get("type",entry.get("id","")))
  var group:String=group_for(kind)
  if category=="现有库存":
   if group=="高级零件":continue
   var available:int=int(entry.get("available",inventory.get(kind,0)))
   var installed:bool=false
   for part in parts:
    if str(part.get("type",""))==kind:installed=true;break
   if available<=0 and not installed:continue
  elif group!=category:continue
  result.append(entry)
 return result

# Simple presentation presets use the existing bounded parameter only.
# No preset is chosen, snapped, or saved until the player presses its button.
const Parts=preload("res://scripts/parts_expanded.gd")
const PRESETS:Dictionary={
 "thruster":{"label":"动力","labels":["低","中","高"],"values":[12.0,28.0,40.0]},
 "spring":{"label":"弹射","labels":["低","中","高"],"values":[14.0,20.0,40.0]},
 "valve":{"label":"供电","labels":["低","中","高"],"values":[12.0,30.0,60.0]},
 "rotator":{"label":"转速","labels":["慢","中","快"],"values":[30.0,45.0,90.0]},
 "damper":{"label":"缓冲","labels":["弱","中","强"],"values":[1.0,2.5,5.0]},
 "lance":{"label":"射程","labels":["近","中","远"],"values":[4.0,12.0,20.0]},
 "accelerator":{"label":"弹射","labels":["低","中","高"],"values":[4.0,8.0,16.0]},
 "arc":{"label":"射程","labels":["近","中","远"],"values":[2.0,8.0,12.0]},
 "bomb":{"label":"范围","labels":["小","中","大"],"values":[1.0,3.0,6.0]},
 "shrink":{"label":"大小","labels":["小","中","大"],"values":[0.25,0.55,0.8]},
 "enlarge":{"label":"大小","labels":["小","中","大"],"values":[1.2,1.6,2.4]},
 "teleporter":{"label":"距离","labels":["近","中","远"],"values":[4.0,8.0,16.0]},
 "probe":{"label":"感应距离","labels":["近","中","远"],"values":[4.0,8.0,16.0]},
 "delay":{"label":"等待","labels":["短","中","长"],"values":[0.2,0.5,1.0]}
}
const SIMPLE_PURPOSES:Dictionary={
 "battery":"为相连的零件供电。",
 "valve":"控制相连零件的供电。",
 "thruster":"接通电池，给飞行器提供推力。",
 "spring":"蓄好能量，再触发弹开连接。",
 "rotator":"转动相邻的零件。",
 "beam":"把零件连成船体。",
 "coupler":"触发后松开一处连接。",
 "damper":"减少船体的晃动。",
 "lance":"用光束攻击前方目标。",
 "accelerator":"把相邻零件当弹丸发射。",
 "arc":"电击前方目标，也会波及相连零件。",
 "bomb":"引爆后炸开周围，也会伤到附近货物。",
 "armor":"保护所在位置，受损后会破裂。",
 "shield":"用电量为相连的船体抵挡伤害。",
 "decoy":"吸引追踪信号的敌人。",
 "shrink":"让目标零件变小。",
 "enlarge":"让目标零件变大。",
 "teleporter":"把相连的船体向前移动一段。",
 "splitter":"把一个零件分成两份。",
 "probe":"前方有物体靠近时发出信号。",
 "collision":"碰到外部物体时发出信号。",
 "delay":"稍等片刻，再传出信号。",
 "and_gate":"两个条件都满足时启动。",
 "or_gate":"任一条件满足时启动。",
 "not_gate":"条件不满足时启动。",
 "drill":"接通电池，切开碰到的障碍。",
 "cargo":"把这份托付完整送到收件处。"
}

static func simple_purpose(kind:String,launcher:bool) -> String:
 if kind=="spring" and launcher:return "把飞行器弹出发射台。"
 return str(SIMPLE_PURPOSES.get(kind,"安装后按现有设置工作。"))

static func preset_control(part:Dictionary,control:Dictionary) -> Dictionary:
 var kind:String=str(part.get("type",""))
 if str(control.get("key","param"))!="param" or not PRESETS.has(kind):return {}
 var result:Dictionary=PRESETS[kind].duplicate(true)
 var values:Array=[]
 for value in result["values"]:values.append(Parts.sanitize_parameter(kind,value))
 result["values"]=values;result["key"]="param";result["kind"]="preset"
 result["value"]=float(control.get("value",part.get("param",Parts.defaults(kind))))
 # Exact comparison matters: a near-preset saved value is still custom.
 result["selected"]=values.find(result["value"])
 return result

static func show_advanced_control(kind:String,key:String,launcher:bool) -> bool:
 return not (launcher and kind=="spring" and key=="target")

static func usable_wire_options(options:Array,launcher:bool) -> Array:
 if not launcher:return options.duplicate(true)
 var result:Array=[]
 for option in options:
  if int(option.get("id",-1))!=-2:result.append(option.duplicate(true))
 if result.is_empty():result.append({"id":-1,"label":"— 默认运行 —"})
 return result
