# Keyboard and controller input

The production input owner is `CourierInput`, added after the modal layers so it
observes input before native GUI controls. Godot 4.6.3's installed standardized
joypad button/axis symbols are used. No flight physics, save format, input-timeline
version, price, or energy tariff has changed.

## Controls

| Context | Controller | Keyboard / mouse |
| --- | --- | --- |
| Shop | Left stick / D-pad move; keep direction to run. A nearby interaction. Menu enters menu navigation. | A / D move; keep direction to run. E / Enter nearby interaction. Tab enters menus. |
| Menus | Left stick / D-pad choose; A activate; B back. Right stick scrolls. Left / right adjusts sliders, numbers and choices. | Existing native focus, clicks and scrolling. Fresh A / D closes a nonmodal drawer and walks, except when a text field owns typing. |
| Workbench menus | X enters grid mode. Palette, inspector, craft / launcher, and trial / dispatch remain normal focused UI. | Existing clicks, drag, wheel, middle-button pan and editing shortcuts. |
| Workbench grid | Direction moves cursor; A selects or places a stocked part. Y picks up an installed part; A commits at destination. X rotates. LB removes. RB undoes. R3 fits. L3 cycles installed parts, including retained out-of-tier parts. Right stick pans. B cancels pickup first, then returns to menu navigation. | Existing editor controls. A fresh A / D returns to the shop. |
| Dialogue / loading | A confirm / continue / skip loading; B skip. Dialogue audio controls are focusable. | Existing Enter / Space / Escape and buttons. |
| Flight | Left stick Y gives continuous vertical control. D-pad overrides with full up / down. RB requests funded full-power boost. A activates the cockpit circuit. Menu pauses; B also pauses. | W / S or up / down; Shift boost; Space circuit; P / Escape pause. |
| Paused flight | Menu / B resumes. A activates the focused native pause / abort control. | Existing pause and mouse controls. |

A/B/X/Y labels use the standardized Xbox-style layout: A is the bottom face
button, B right, X left, Y top. This pass verifies synthesized standardized events;
a physical gamepad was not connected or exercised.

## Ownership and freshness

Priority is unfocused / closing, dialogue, loading, blocking modal, flight,
explicit workbench grid, menu navigation, free shop movement. Modal events are
consumed before gameplay. Ordinary menu navigation never mutates the grid.

Context/page transitions quarantine held buttons, keys and displaced axes until
release/neutral. A single fresh keyboard A / D may deliberately close a nonmodal
drawer and start walking; it cannot dismiss settings, a confirmation, dialogue or
loading. Text fields, including SpinBox's LineEdit, keep ownership of typing.

Input outside the focused window is ignored. Physical controller disconnection
clears that device's held state, pauses a flight, and uses the existing checkpoint
path. Resuming does not restore physically held commands. Pending controller
pickup is canceled on focus loss, modal/page/assembly changes, and resize. A
changed assembly snapshot invalidates a stale move proposal.

The deadzone defaults to 0.22 and is adjustable from 0.10 to 0.45 in settings.
Outside it, analog input is rescaled to the full range and quantized to the existing
integer `axis_q` range -1000..1000 immediately before the ordinary PilotTimeline
record / simulation step. D-pad opposing directions cancel. Buttons do not repeat
destructive actions. Navigation repeats after 0.34 seconds, then every 0.10 seconds,
independent of OS key echo, with bounded work after a slow frame.

Prompts switch after meaningful activity with a 0.32-second hysteresis. Real
controller navigation ownership changes immediately on valid controller intent,
independently of those cosmetic labels. Keyboard/mouse intent immediately returns
ownership, so lingering pad labels cannot auto-focus a keyboard post-loading
screen. Neutral stick noise does not switch device prompts. Only the nearby E/A action is shown
in free roam; full mappings are in the Help drawer. Controller action strips use
HUD-compatible integer 1x/2x/3x scale and stay within the actual art frame.

## Verification

- `test_courier_input.gd`: real Godot event pipeline with synthesized
  InputEventJoypadMotion/Button; menu focus/repeat, persistent deadzone, editor
  transactions, dialogue, fractional pilot commands, funded energy, exact replay,
  pause/focus/disconnect, and bounded retained nodes/tweens.
- `test_courier_contexts.gd`: close-and-walk vs text/modal ownership, real
  counter order accept → dialogue → loading skip → workbench, held skip barriers,
  safe dispatch cancellation, out-of-tier recovery, interrupted pickup, and
  1280×720 / 1920×1080 / 3840×2160 action-strip/cursor bounds.
- `test_courier_input_ownership.gd`: rapid keyboard/controller switch matrix for
  hub/workbench menus, settings/dispatch modals, dialogue and flight pause, plus
  reverse switching, keyboard post-loading focus preservation and ownership reset.
- `test_pilot_input_lifecycle.gd`: existing keyboard/replay regression strengthened
  to require focus re-entry before a pause key can resume flight.

All tests use isolated XDG save locations. Synthesized input is not a substitute
for controller hardware, driver, hotplug or operating-system focus testing.
