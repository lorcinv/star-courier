extends SceneTree
const Timeline=preload("res://scripts/pilot_timeline.gd")
var passed:int=0
var failed:int=0
func check(value:bool,label:String) -> void:
 if value:passed+=1;print("PASS ",label)
 else:failed+=1;push_error(label)
func _initialize() -> void:
 var timeline=Timeline.new()
 check(timeline.state_at(0)==Timeline.neutral(),"fresh input starts neutral")
 check(timeline.record(0,{"axis_q":-1000,"boost":false,"active":true}),"tick-zero press replaces neutral")
 check(timeline.record(1,{"axis_q":-1000,"boost":false,"active":true}) and timeline.commands.size()==1,"held keys are sparse")
 check(timeline.record(12,Timeline.neutral()),"release is recorded")
 check(timeline.state_at(11).axis_q==-1000 and timeline.state_at(12).axis_q==0,"command boundary precedes exact simulation tick")
 check(timeline.state_at(5).active,"rewind resets replay cursor")
 check(not timeline.record(2,Timeline.neutral()),"out-of-order live writes rejected")
 var copy=Timeline.new()
 var json:Variant=JSON.parse_string(JSON.stringify(timeline.snapshot()))
 check(copy.restore(json,18),"JSON numeric types restore safely")
 for tick in range(19):check(copy.state_at(tick)==timeline.state_at(tick),"replay state parity at tick "+str(tick))
 var malformed:Array=[null,[],[{"tick":1,"axis_q":0,"boost":false,"active":false}],[{"tick":0,"axis_q":1001,"boost":false,"active":false}],[{"tick":0,"axis_q":0.5,"boost":false,"active":false}],[{"tick":0,"axis_q":0,"boost":1,"active":false}],[{"tick":0,"axis_q":0,"boost":false,"active":false},{"tick":0,"axis_q":2,"boost":false,"active":false}]]
 for value in malformed:check(not copy.restore(value,18),"malformed timeline refused without silent reinterpretation")
 check(copy.state_at(12)==Timeline.neutral(),"failed restore preserves last valid replay")
 check(Timeline.quantize(INF,true,false).axis_q==0,"nonfinite axis becomes neutral")
 check(Timeline.quantize(3,false,false).axis_q==1000,"live axis quantization bounded")
 var snapshot:Array=timeline.snapshot();snapshot[0].axis_q=0
 check(timeline.state_at(0).axis_q==-1000,"snapshot cannot mutate active command history")
 print("PILOT_TIMELINE_TESTS passed=",passed," failed=",failed)
 quit(1 if failed else 0)
