extends SceneTree
## Rendered component proof with actual final species assets; no native-input claim.
const Stories=preload("res://scripts/courier_stories.gd")
const DialoguePanel=preload("res://scripts/dialogue_panel.gd")
func _initialize() -> void:run.call_deferred()
func run() -> void:
 root.size=Vector2i(1280,720)
 var art:=TextureRect.new();art.texture=load("res://assets/2d_v5/environment/shop-shell.png");art.expand_mode=TextureRect.EXPAND_IGNORE_SIZE;art.stretch_mode=TextureRect.STRETCH_KEEP_ASPECT_COVERED;art.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT);root.add_child(art)
 var panel:=DialoguePanel.new();root.add_child(panel)
 for i in 4:
  var binding:=Stories.bind_contract({}, {"contract_id":"SPECIES-%d"%i,"status":"available","appearance_id":Stories.IDS[i]},1,i)
  var conversation:=Stories.conversation_for(binding.state,binding.contract,"accept")
  panel.begin(conversation,binding.actor,{"reduced_motion":true,"dialogue_muted":true});panel.advance()
  await process_frame;await RenderingServer.frame_post_draw
  var texture:Texture2D=panel._left_portrait.texture
  print("SPECIES_PORTRAIT_ACTUAL ",Stories.IDS[i]," ",texture.resource_path)
  root.get_texture().get_image().save_png("res://source_art/2d_v5/dialogue/runtime-species-"+Stories.IDS[i]+".png")
  panel.cancel(false)
 panel.queue_free();await process_frame;quit(0)
