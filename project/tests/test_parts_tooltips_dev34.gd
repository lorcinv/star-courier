extends Node
## Bounded real HUD-card checks. The existing purpose provider is unchanged.
## Isolated synthetic display state only; no physics, saves, or native QA.
const HUD=preload("res://scripts/game_hud.gd")
const Parts=preload("res://scripts/parts_expanded.gd")
const WorkshopParts=preload("res://scripts/workshop_parts_v2.gd")
const CURRENT:String="pilot-delivery-v8"
const SHIP_SPRING:String="紧邻货物时缓和冲击；分裂会减少弹簧的有效储能和承载。"
const PAD_SPRING:String="与电芯、底座相连时储能弹射；多件的有效储能相加。发射角与总力度在预览中调整。"
const OLD_SPRING:String="发射台专用：接上电芯和梁或装甲，起飞时弹出飞行器；调整储能可改变弹射速度。"
const OLD_SHIP_SPRING:String="紧邻货物并直接连接，形成柔性支撑，缓和加速度和落地冲击；多件可组合承载。"
const CURRENT_TELEPORT:String="沿当前或最近驾驶方向位移整船并保留速度；每千克每米消耗6 J，重船或长距离更费电。落点须容纳整船。"
const FREE_TELEPORT:String="选中后沿驾驶方向位移整艘船；松开方向沿最近方向。落点必须放得下船，每次消耗 25 J。"
const ARROW_TELEPORT:String="按键沿箭头位移整艘船。落点必须放得下船；每次消耗 25 J。"
const RETAINED:String="\n旧版保留：原属性与控制继续有效，不再出售。"
var passed:int=0
var failed:int=0
var hud
var actions:Array=[]

func check(ok:bool,label:String)->void:
 if ok:passed+=1;print("PASS ",label)
 else:failed+=1;push_error("FAIL "+label)

func settle()->void:
 for frame in 3:await get_tree().process_frame

func data_for(kind:String,version:String,launcher:bool=false)->Dictionary:
 return {"mode":"workshop","control_version":version,"activeorder":{"control_version":version},"assembly_mode":"launcher" if launcher else "craft","catalog":Parts.catalog(),"inventory":{kind:7},"chosen_type":kind,"parts":[],"selectedpart":{},"settings":{"reduced_motion":true}}

func card_for(kind:String)->Button:
 for button in hud.content.find_children("*","Button",true,false):
  if str(button.get_meta("view_key",""))=="catalog:"+kind:return button
 return null

func label_count(node:Node,copy:String)->int:
 var count:int=0
 for label in node.find_children("*","Label",true,false):
  if label.text==copy:count+=1
 return count

func check_card(card:Button,spec:Dictionary,kind:String,purpose:String,available:int,label:String,retired:bool=false)->void:
 check(card!=null,label+" creates a real card")
 if card==null:return
 var name_text:String=str(spec.get("name",kind))
 var expected:String="%s\n%s\n质量 %.1f kg · 库存 %d"%[name_text,purpose,float(spec.get("mass",0)),available]
 if retired:expected+=RETAINED
 check(card.tooltip_text==expected,label+" tooltip has exact purpose, name, mass, inventory and retained suffix")
 check(label_count(card,name_text)==1 and label_count(card,"× %d"%available)==1,label+" preserves displayed name and stock")
 check((label_count(card,"旧件")==1)==retired,label+" preserves retired marker")
 check(card.custom_minimum_size==Vector2(96,92) and not card.disabled,label+" preserves card size and enabled selection")
 var count:int=actions.size()
 card.pressed.emit()
 check(actions.size()==count+1 and actions.back()==["select_catalog",kind],label+" click emits the same single selection event")

func render_case(data:Dictionary,kind:String,purpose:String,label:String)->void:
 var frozen:PackedByteArray=var_to_bytes(data)
 var count:int=actions.size()
 hud.palette_open=true;hud.palette_category=WorkshopParts.DEFAULT_CATEGORY
 hud.render(data);await settle()
 var card:Button=card_for(kind)
 check(card!=null and card.is_visible_in_tree(),label+" is available through the actual workshop tray")
 check(var_to_bytes(data)==frozen and var_to_bytes(hud.state)==frozen and actions.size()==count,label+" rendering leaves input and catalog unchanged and emits no actions")
 var version:String=str(data.get("control_version",data.get("activeorder",{}).get("control_version","")))
 var launcher:bool=str(data.get("assembly_mode","craft"))=="launcher"
 check(WorkshopParts.purpose(kind,launcher,version)==purpose,label+" retains exact existing inspector-purpose semantics")
 check_card(card,data.catalog[kind],kind,purpose,7,label)

func retained_cards()->void:
 # Legacy incompatible cards are not falsely claimed to be normal tray entries.
 # Exercise the retained rendering branch directly without changing eligibility.
 var data:Dictionary=data_for("spring","pilot-free-v2")
 hud.render(data);await settle()
 check(card_for("spring")==null,"historical ship spring remains excluded by existing palette eligibility")
 var parent:=HBoxContainer.new();hud.content.add_child(parent)
 var spring:Dictionary=Parts.catalog().spring.duplicate(true);spring.type="spring";spring.available=3
 hud._part_card(parent,spring)
 check_card(parent.get_child(0),spring,"spring",OLD_SPRING,3,"retained ship spring",true)
 var probe:Dictionary=Parts.catalog().probe.duplicate(true);probe.id="probe";probe.available=2
 hud._part_card(parent,probe)
 check_card(parent.get_child(1),probe,"probe",str(probe.description),2,"retained id-key legacy part",true)

func run()->void:
 if OS.get_environment("SC_PARTS_TOOLTIPS_ISOLATED")!="1" or OS.get_environment("XDG_DATA_HOME").is_empty():get_tree().quit(2);return
 get_tree().root.size=Vector2i(1280,814)
 hud=HUD.new();add_child(hud);hud.set_art_frame(Rect2(0,47,1280,720))
 hud.action_requested.connect(func(action,payload):actions.append([action,payload]))
 var data:Dictionary=data_for("spring",CURRENT)
 data.activeorder.control_version="pilot-free-v2"
 await render_case(data,"spring",SHIP_SPRING,"v8 ship spring overrides older order fallback")
 data.assembly_mode="launcher"
 await render_case(data,"spring",PAD_SPRING,"same current state switched to launcher")
 data.assembly_mode="craft"
 await render_case(data,"spring",SHIP_SPRING,"same current state switched back to ship")
 await render_case(data_for("spring","pilot-delivery-v3"),"spring",OLD_SHIP_SPRING,"historical v3 ship spring")
 await render_case(data_for("spring","pilot-free-v2",true),"spring",OLD_SPRING,"historical free-v2 launcher spring")
 await render_case(data_for("teleporter",CURRENT),"teleporter",CURRENT_TELEPORT,"v8 driving-direction teleporter")
 await render_case(data_for("teleporter","pilot-free-v2"),"teleporter",FREE_TELEPORT,"historical free-v2 driving-direction teleporter")
 await render_case(data_for("teleporter","pilot-v3"),"teleporter",ARROW_TELEPORT,"historical arrow-direction teleporter")
 data=data_for("spring",CURRENT);data.erase("control_version");data.erase("assembly_mode")
 await render_case(data,"spring",SHIP_SPRING,"order-version and default-craft fallback")
 data=data_for("spring",CURRENT);data.erase("activeorder")
 await render_case(data,"spring",SHIP_SPRING,"current display version without an active order")
 data=data_for("teleporter",CURRENT);data.erase("activeorder");data.erase("control_version")
 await render_case(data,"teleporter",ARROW_TELEPORT,"no order and no display version preserves empty fallback")
 data=data_for("teleporter",CURRENT);data.control_version=""
 await render_case(data,"teleporter",ARROW_TELEPORT,"explicit empty display version keeps existing precedence")
 await retained_cards()
 hud.queue_free();await settle()
 print("PARTS_TOOLTIPS_DEV34 passed=%d failed=%d real_ui_cards=true physics=NOT_RUN native_visual=NOT_RUN"%[passed,failed])
 get_tree().quit(1 if failed else 0)
