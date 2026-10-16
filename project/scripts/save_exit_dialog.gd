extends ConfirmationDialog
## Local modal owns controller input while Main and its input router are held.
## Keyboard Tab/Enter/Esc continue to use Godot's built-in dialog routing.
func _ready() -> void:
 theme=Theme.new();theme.default_font=preload("res://assets/fonts/ChineseSans.otf");theme.default_font_size=18
 get_label().autowrap_mode=TextServer.AUTOWRAP_WORD_SMART

func _input(event:InputEvent) -> void:
 if not visible or not event is InputEventJoypadButton or not event.pressed:return
 var owner:Control=gui_get_focus_owner()
 if event.button_index==JOY_BUTTON_B:
  # Use the native cancel button: its pressed signal owns hide + canceled.
  get_cancel_button().pressed.emit()
 elif event.button_index==JOY_BUTTON_A:
  # Godot connects these real button signals to its native OK/cancel/custom
  # handlers. Do not emit confirmed/canceled ourselves or skip disabled state.
  if owner is Button and not owner.disabled and owner.is_visible_in_tree():owner.pressed.emit()
 elif event.button_index in [JOY_BUTTON_DPAD_LEFT,JOY_BUTTON_DPAD_UP,JOY_BUTTON_DPAD_RIGHT,JOY_BUTTON_DPAD_DOWN]:
  if is_instance_valid(owner):
   var next:Control=owner.find_prev_valid_focus() if event.button_index in [JOY_BUTTON_DPAD_LEFT,JOY_BUTTON_DPAD_UP] else owner.find_next_valid_focus()
   if is_instance_valid(next):next.grab_focus()
 else:return
 set_input_as_handled()
