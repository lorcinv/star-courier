extends SceneTree
const HUD=preload("res://scripts/game_hud.gd")
const Parts=preload("res://scripts/parts_expanded.gd")
var passed:int=0
var failed:int=0
func check(ok:bool,label:String)->void:
 if ok:passed+=1
 else:failed+=1;push_error(label)
func _initialize()->void:run.call_deferred()
func run()->void:
 var hud=HUD.new();root.add_child(hud);await process_frame
 var catalog:Dictionary=Parts.catalog();var state:Dictionary={"mode":"supply","phase":"day","credits":260,"catalog":catalog,"inventory":{},"day_basic_supply":true,"activeorder":{}}
 hud.render(state);await process_frame
 var found:Array=[]
 for n in hud.content.find_children("*","Button",true,false):
  if n.has_meta("day_basic_kind"):found.append(n.get_meta("day_basic_kind"));check(not n.disabled,"affordable basic button enabled")
 check(found.size()==6 and found.has("drill") and found.has("shield") and not found.has("and_gate"),"day store exposes exactly six basic physical parts")
 state.credits=0;hud.render(state);await process_frame
 for n in hud.content.find_children("*","Button",true,false):
  if n.has_meta("day_basic_kind"):check(n.disabled,"zero balance cannot buy a free tool")
 state.day_basic_supply=false;hud.render(state);await process_frame
 var count:int=0
 for n in hud.content.find_children("*","Button",true,false):
  if n.has_meta("day_basic_kind"):count+=1
 check(count==0,"legacy day has no falsely advertised buying path")
 hud.queue_free();await process_frame
 print("DAY_BASIC_SUPPLY_UI passed=%d failed=%d"%[passed,failed]);quit(1 if failed else 0)
