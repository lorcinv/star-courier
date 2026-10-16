extends Node
const Cut=preload("res://scripts/coupler_cut_preview.gd")
const HUD=preload("res://scripts/game_hud.gd")
const World=preload("res://scripts/world_view_2d.gd")
const Parts=preload("res://scripts/parts_expanded.gd")
var passed:int=0
var failed:int=0
func check(ok:bool,label:String)->void:
 if ok:passed+=1;print("PASS ",label)
 else:failed+=1;push_error("FAIL "+label)
func part(id:int,kind:String,x:int,y:int)->Dictionary:
 return {"id":id,"type":kind,"x":x,"y":y,"rot":0,"param":Parts.defaults(kind),"target":-1,"input_a":-1,"input_b":-1}
func settle()->void:
 for frame in 4:await get_tree().process_frame
func run()->void:
 var parts:Array=[part(1,"cargo",0,0),part(2,"coupler",-1,0),part(3,"battery",-2,0),part(4,"thruster",0,-1),part(5,"thruster",0,1),part(6,"damper",1,0),part(7,"shield",1,-1),part(8,"battery",8,8)]
 parts[1].target=1;parts[1].input_a=-2
 var frozen:PackedByteArray=var_to_bytes(parts)
 var g:Dictionary=Cut.design_groups(parts[1],parts[0],parts)
 check(g.valid and g.separates and g.groups.size()==2,"single socket makes exactly two affected groups")
 check(g.groups[0].ids==[1,4,5,6,7] and g.groups[0].battery_count==0 and g.groups[1].ids==[2,3],"whole cargo side and sole detached battery identified")
 check(not g.groups[0].ids.has(8) and not g.groups[1].ids.has(8),"unrelated preexisting component excluded")
 check(Cut.from_design(parts[1],parts[0],parts)==not g.separates,"matches existing cut connectivity truth")
 var text:String=Cut.group_text(g,true)
 check("货物组没有电芯" in text and "无货物组不再接收驾驶输入" in text and "不代表剩余电量" in text,"consequences distinguish presence from charge/control")
 check(not "驾驶输入" in Cut.group_text(g,false),"nonpilot view does not claim cockpit control")
 check(var_to_bytes(parts)==frozen,"topology preview byte read-only")
 var loop:Array=parts.duplicate(true);loop.append(part(9,"beam",-1,-1))
 var connected:Dictionary=Cut.design_groups(loop[1],loop[0],loop)
 check(connected.valid and not connected.separates and Cut.group_text(connected,true).is_empty(),"bypass connection keeps original still-connected state")
 check(not Cut.design_groups(parts[1],parts[-1],parts).valid and not Cut.design_groups(parts[1],{},parts).valid,"invalid/nonadjacent target has no preview")
 var two:Array=parts.duplicate(true);two[2].type="cargo"
 var multi:Dictionary=Cut.design_groups(two[1],two[0],two)
 check(multi.groups.size()==2 and multi.groups[0].cargo_count==1 and multi.groups[1].cargo_count==1 and not "无货物组" in Cut.group_text(multi,true),"multiple cargo groups do not assume a single cockpit side")
 var hud=HUD.new();add_child(hud);get_tree().root.size=Vector2i(1280,814);hud.set_art_frame(Rect2(0,47,1280,720))
 var data:Dictionary={"mode":"workshop","control_version":"pilot-delivery-v8","activeorder":{"control_version":"pilot-delivery-v8"},"assembly_mode":"craft","catalog":Parts.catalog(),"inventory":{},"parts":parts,"selectedpart":parts[1],"settings":{"reduced_motion":true}}
 var before:PackedByteArray=var_to_bytes(data);hud.render(data);await settle()
 var label:Label=hud.content.find_child("CouplerGroupPreview",true,false);var target:OptionButton=hud.content.find_child("PartTargetChoice",true,false)
 check(label!=null and label.text==text and target!=null,"actual inspector contains exact consequence summary and existing target control")
 check(var_to_bytes(data)==before,"render keeps saved design and target unchanged")
 var world=World.new();add_child(world);await settle();world.set_meta("assembly_context","craft");world.show_design(parts,2)
 check(world.grid.coupler_groups.groups.size()==2 and world.grid.coupler_groups.groups[0].ids==g.groups[0].ids,"actual world overlay uses same affected groups")
 world.show_workshop_selection(1)
 check(world.grid.coupler_groups.is_empty(),"changing selection clears hypothetical overlay")
 world.show_design(loop,2)
 check(not world.grid.coupler_groups.separates,"loop-connected world overlay never invents detached groups")
 data.selectedpart=parts[0];hud.render(data);await settle()
 check(hud.content.find_child("CouplerGroupPreview",true,false)==null,"changing selected part clears inspector consequence")
 world.queue_free();hud.queue_free();await settle()
 print("COUPLER_GROUPS_DEV38 passed=",passed," failed=",failed," synthetic_ui_and_topology=true native=false")
 get_tree().quit(0 if failed==0 else 1)
