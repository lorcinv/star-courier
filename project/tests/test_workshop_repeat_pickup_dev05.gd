extends "res://tests/test_workshop_drag_feedback_v2.gd"
## A selected module is the usual source of a second drag after a drop.
## Pickup must not rebuild the full world/HUD when selection has not changed.

class CurrentHost extends FakeHost:
 const WorkshopParts=preload("res://scripts/workshop_parts_v2.gd")

func create_host():
 var h=CurrentHost.new();h.adapter=Adapter.new();h.adapter.bind(h);h.adapter.after_render();return h

func run() -> void:
 repeated_pickup();placement_release()
 adapter_gestures();coordinate_matrix();presenter_state()
 print("WORKSHOP_REPEAT_PICKUP_DEV05 passed=",passed," failed=",failed," max_pointer_screen_error_px=",max_pointer_screen_error)
 quit(1 if failed else 0)

func repeated_pickup() -> void:
 var h=create_host();var a=h.adapter
 h.selected_id=5
 var before:Array=h.design.duplicate(true)
 var stock:Dictionary=h.economy.inventory.duplicate(true)
 var credits:int=h.economy.credits
 var grab:Vector2=Vector2(17,-11)
 var source:Vector2=local_pixel(h,Vector2i.ZERO,grab)
 var dest:Vector2=local_pixel(h,Vector2i(0,-1),grab+Vector2(3,2))
 var renders:int=h.renders;var camera_updates:int=h.world.updates
 a.handle(button(source,true))
 check(h.renders==renders and h.world.updates==camera_updates,"already-selected pickup does not rebuild world/HUD or reapply camera")
 check(a.camera.gesture=="move" and h.selected_id==5 and invariant(h,before,stock,credits,0,0),"fast pickup still opens a release-only move transaction")
 a.handle(motion(dest))
 var expected:Vector2=h.world.workshop_point_at(dest/2.0)-grab
 check(h.world.preview.visible and h.world.preview.pointer.distance_to(expected)<.001,"fast pickup keeps the first motion exact with the original grab offset")
 check(h.renders==renders and invariant(h,before,stock,credits,0,0),"press plus all held motion has zero rebuilds and zero model writes")
 a.handle(button(dest,false))
 check(h.renders==renders+1 and h.saves==1 and h.undo.size()==1 and h.design[0].y==-1,"successful repeat drop renders and saves once, with exactly one undo")
 check(h.undo[0]==before,"repeat drop keeps the exact pre-drag undo snapshot")
 # A click on the selected module is still selection only, not an edit.
 renders=h.renders;camera_updates=h.world.updates
 source=local_pixel(h,Vector2i(0,-1),grab)
 a.handle(button(source,true));a.handle(button(source,false))
 check(h.renders==renders and h.world.updates==camera_updates and h.saves==1 and h.undo.size()==1,"same-module click does not rebuild or create a phantom edit")
 # The no-render path must still dismiss an earlier keyboard/gamepad pickup.
 a.controller_begin();a.controller_pickup()
 check(a.controller_moving(),"fixture has an active controller pickup before mouse selection")
 renders=h.renders
 a.handle(button(source,true))
 check(not a.controller_moving() and h.renders==renders,"same selected mouse press cancels controller pickup without a rebuild")
 a.cancel()
 # Changing selection must continue to update the inspector and grid highlight.
 renders=h.renders
 source=local_pixel(h,Vector2i(1,0))
 a.handle(button(source,true))
 check(h.selected_id==6 and h.renders==renders+1,"a different module still refreshes selection presentation exactly once")
 a.handle(button(source,false))
 check(h.saves==1 and h.undo.size()==1,"changing selection remains free of persistence and undo writes")
 dispose(h)

func placement_release() -> void:
 var h=create_host();var a=h.adapter
 var before:Array=h.design.duplicate(true)
 var stock:Dictionary=h.economy.inventory.duplicate(true)
 var credits:int=h.economy.credits
 var empty:Vector2=local_pixel(h,Vector2i(0,-1))
 a.handle(button(empty,true))
 check(invariant(h,before,stock,credits,0,0),"empty-cell press cannot install before release")
 a.handle(button(empty,false))
 check(h.design.size()==before.size()+1 and h.saves==1 and h.undo.size()==1 and h.next_id==21,"empty-cell release still installs once with one undo")
 a.handle(button(empty,false))
 check(h.design.size()==before.size()+1 and h.saves==1 and h.undo.size()==1,"duplicate placement release cannot replay a commit")
 # Picking up that newly selected placement takes the same no-rebuild path.
 var renders:int=h.renders
 a.handle(button(empty,true));a.cancel();a.handle(button(empty,false))
 check(h.renders==renders and h.saves==1 and h.undo.size()==1,"pickup then cancel of a fresh placement is presentation-only")
 before=h.design.duplicate(true)
 empty=local_pixel(h,Vector2i(0,-2))
 a.handle(button(empty,true));h.economy.inventory.battery=h._installed_count("battery");a.handle(button(empty,false))
 check(h.design==before and h.saves==1 and h.undo.size()==1 and not h.notices.is_empty(),"placement release rechecks current inventory")
 h.economy.inventory=stock.duplicate(true)
 a.handle(button(empty,true));a.handle(motion(local_pixel(h,Vector2i(1,-2))));a.handle(button(local_pixel(h,Vector2i(1,-2)),false))
 check(invariant(h,before,stock,credits,1,1),"dragging from an empty cell cannot create an accidental module")
 dispose(h)
