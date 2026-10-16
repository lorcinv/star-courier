extends SceneTree
## Headless direct render calls only. No native OS input or screenshot claim.
const HUD=preload("res://scripts/game_hud.gd")
const Econ=preload("res://scripts/economy.gd")
var passed:int=0
var failed:int=0
func _initialize() -> void:run.call_deferred()
func check(ok:bool,label:String) -> void:
 if ok:passed+=1;print("PASS ",label)
 else:failed+=1;push_error("FAIL "+label)
func shown_text(hud) -> String:
 var result:String=""
 for node in hud.content.find_children("*","Label",true,false):
  if node.is_visible_in_tree():result+=node.text+"\n"
 return result
func settle(hud) -> void:
 for i in 3:await process_frame
 for tween in hud._motion_tweens.values():
  if tween.is_valid():tween.custom_step(1.0)
 await process_frame
func run() -> void:
 root.size=Vector2i(1280,720)
 var hud=HUD.new();root.add_child(hud);hud.set_art_frame(Rect2(0,0,1280,720));hud.report_costs_open=true
 var e=Econ.new();e.ensure_contracts();var id:String=e.contracts[0].contract_id;e.accept_contract(id);e.begin_dispatch([],[])
 var settled:Dictionary=e.settle_contract(id,{"integrity":1.0,"energy_used":12.0},8.0,true)
 var receipt:Dictionary=settled.report.duplicate(true);receipt.trial=false;receipt.cause="货物已签收。"
 var raw:PackedByteArray=var_to_bytes(receipt)
 var state:Dictionary={"mode":"report","day":1,"credits":e.credits,"reputation":e.reputation,"phase":e.phase,"report":receipt,"daily_reviews_enabled":true,"settings":{"reduced_motion":true}}
 hud.render(state);await settle(hud)
 var text:String=shown_text(hud)
 check(not text.contains("客户回信") and not text.contains(str(receipt.review)),"same-day formal report suppresses legacy evaluative customer letter")
 check(text.contains("本单净收益") and text.contains("订单收入") and text.contains("能源消耗"),"same-day report retains factual financial receipt totals")
 check(text.contains("货物已签收。") and text.contains("整备说明"),"same-day report retains actual result and replenishment facts")
 check(e.customer_reviews().is_empty() and e.review_state.pending.size()==1,"rendering report never discloses or publishes pending phone review")
 check(var_to_bytes(receipt)==raw,"suppression leaves original ledger receipt fields unchanged")
 # Even accidentally supplied future copy cannot reach the same-day report.
 receipt.review="明日才可见的唯一测试评价";state.report=receipt;hud.render(state);await settle(hud)
 check(not shown_text(hud).contains("明日才可见") and not shown_text(hud).contains("客户回信"),"future review copy cannot leak through old report.review field")
 state.daily_reviews_enabled=false;hud.render(state);await settle(hud)
 check(shown_text(hud).contains("客户回信"),"legacy disabled-mode fixture retains its pre-feature UI behavior")
 hud.queue_free();await process_frame
 print("REVIEW_HUD passed=%d failed=%d total=%d"%[passed,failed,passed+failed])
 quit(1 if failed else 0)
