extends RefCounted
## v2 quantized force command. Caller invokes solely in unpaused free flight.
## Aim is NOT read separately: simulation derives it from recorded axis commands.
## Quarantine/focus ownership remains CourierInput's existing implementation.
static func state(keys:Dictionary, courier=null, device_id:int=-1) -> Dictionary:
 var x:int=int(keys.has(KEY_D) or keys.has(KEY_RIGHT))-int(keys.has(KEY_A) or keys.has(KEY_LEFT))
 var y:int=int(keys.has(KEY_S) or keys.has(KEY_DOWN))-int(keys.has(KEY_W) or keys.has(KEY_UP))
 var key_x:bool=keys.has(KEY_A) or keys.has(KEY_D) or keys.has(KEY_LEFT) or keys.has(KEY_RIGHT)
 var key_y:bool=keys.has(KEY_W) or keys.has(KEY_S) or keys.has(KEY_UP) or keys.has(KEY_DOWN)
 var pad_x:float=0.0;var pad_y:float=0.0;var boost:bool=false;var active:bool=false;var brake:bool=false
 if is_instance_valid(courier) and courier.context=="flight" and courier.desired_context()=="flight" and courier.focused:
  var digital_x:int=int(courier.button(JOY_BUTTON_DPAD_RIGHT))-int(courier.button(JOY_BUTTON_DPAD_LEFT))
  var digital_y:int=int(courier.button(JOY_BUTTON_DPAD_DOWN))-int(courier.button(JOY_BUTTON_DPAD_UP))
  pad_x=float(digital_x) if courier.button(JOY_BUTTON_DPAD_LEFT) or courier.button(JOY_BUTTON_DPAD_RIGHT) else courier.axis(JOY_AXIS_LEFT_X)
  pad_y=float(digital_y) if courier.button(JOY_BUTTON_DPAD_UP) or courier.button(JOY_BUTTON_DPAD_DOWN) else courier.axis(JOY_AXIS_LEFT_Y)
  boost=courier.button(JOY_BUTTON_RIGHT_SHOULDER);active=courier.button(JOY_BUTTON_A)
  brake=courier.axis(JOY_AXIS_TRIGGER_LEFT)>0.0
 return {"axis_x_q":x*1000 if key_x else clampi(roundi(pad_x*1000.0),-1000,1000),"axis_q":y*1000 if key_y else clampi(roundi(pad_y*1000.0),-1000,1000),"boost":keys.has(KEY_SHIFT) or boost,"active":keys.has(KEY_SPACE) or active,"device_id":device_id,"brake":keys.has(KEY_CTRL) or brake}
