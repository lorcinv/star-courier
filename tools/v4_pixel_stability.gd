extends SceneTree
## Real raster output. Simulation, actors and camera animation are frozen.
## Usage: godot --path . -s res://tools/v4_pixel_stability.gd -- --canvas=640
## Diagnostic-only flags: --shadow-mode=all|off|directional|positional
## --quality=standard|high|low; --diagnose-shadows runs the same frozen scene
## with shadows off, standard atlases, and high atlases in separate directories.
## --diagnose-shadow-types compares off/directional/positional/all at standard.
var game
var output_dir:String="res://docs/qa/v4/density-stability-640"
var canvas_width:int=640
var shadow_mode:String="all"
var quality:String="standard"
var diagnose_shadows:bool=false
var diagnose_shadow_types:bool=false
var original_shadows:Array=[]
var source_hashes_before:Dictionary={}
func _initialize() -> void:run.call_deferred()
func frame() -> Image:
 await process_frame;await RenderingServer.frame_post_draw
 return game.view.get_texture().get_image()
func changed(a:Image,b:Image,shift:Vector2i=Vector2i.ZERO) -> Dictionary:
 if a.get_size()!=b.get_size() or a.get_format()!=b.get_format():return {"changed_pixels":-1,"tested_pixels":0,"fraction":1.0,"error":"image shape/format mismatch"}
 var ad:PackedByteArray=a.get_data();var bd:PackedByteArray=b.get_data()
 var channels:int=ad.size()/(a.get_width()*a.get_height());var count:int=0;var tested:int=0
 var delta_one:int=0;var delta_small:int=0;var delta_large:int=0;var alpha_only:int=0;var coordinates:Array=[]
 for y in range(maxi(0,-shift.y),mini(a.get_height(),a.get_height()-shift.y)):
  for x in range(maxi(0,-shift.x),mini(a.get_width(),a.get_width()-shift.x)):
   var ai:int=((y+shift.y)*a.get_width()+x+shift.x)*channels;var bi:int=(y*b.get_width()+x)*channels
   var mismatch:bool=false;var rgb_delta:int=0
   for c in range(channels):
    mismatch=mismatch or ad[ai+c]!=bd[bi+c]
    if c<3:rgb_delta=maxi(rgb_delta,absi(int(ad[ai+c])-int(bd[bi+c])))
   if mismatch:
    count+=1
    if rgb_delta==0:alpha_only+=1
    elif rgb_delta==1:delta_one+=1
    elif rgb_delta<=16:delta_small+=1
    else:delta_large+=1
    if coordinates.size()<128:coordinates.append([x,y,rgb_delta])
   tested+=1
 return {"changed_pixels":count,"tested_pixels":tested,"fraction":float(count)/maxi(1,tested),"rgb_delta_1_pixels":delta_one,"rgb_delta_2_to_16_pixels":delta_small,"rgb_delta_gt_16_pixels":delta_large,"alpha_only_pixels":alpha_only,"first_changed_xy_max_rgb_delta":coordinates}
func place_camera(world,base:Vector3,target:Vector3,offset:Vector3) -> void:
 world.smooth_camera_position=base+offset;world.smooth_camera_look=target+offset;world._process(0)
func scene_hashes() -> Dictionary:
 var paths:Array[String]=["res://project.godot","res://scripts/main.gd","res://scripts/world_view.gd","res://scripts/pixel_stage.gd","res://scripts/game_hud.gd","res://scripts/simulation.gd","res://scripts/economy.gd","res://scripts/parts.gd","res://assets/shaders/pixel_cel.gdshader","res://assets/fonts/ChineseSans.otf"]
 for folder in ["res://assets/environment_v4","res://assets/characters_v4","res://assets/models"]:
  for filename in DirAccess.get_files_at(folder):
   if filename.ends_with(".glb"):paths.append(folder+"/"+filename)
 var hashes:Dictionary={}
 for path in paths:hashes[path]=FileAccess.get_sha256(path)
 return hashes
func diagnostic_shadow_mode(mode:String) -> void:
 for item in original_shadows:
  var light:Light3D=item.node
  var allow:bool=mode=="all" or (mode=="directional" and light is DirectionalLight3D) or (mode=="positional" and not light is DirectionalLight3D)
  light.shadow_enabled=bool(item.enabled) and allow
func camera_pose(world) -> Dictionary:
 var transform:Transform3D=world.camera.global_transform
 return {"position":[transform.origin.x,transform.origin.y,transform.origin.z],"right":[transform.basis.x.x,transform.basis.x.y,transform.basis.x.z],"up":[transform.basis.y.x,transform.basis.y.y,transform.basis.y.z],"back":[transform.basis.z.x,transform.basis.z.y,transform.basis.z.z],"size":world.camera.size}
func capture_case(world,base:Vector3,target:Vector3,right:Vector3,up:Vector3,pixel:float,mode:String,profile:String,path:String) -> bool:
 game.settings.quality=profile;game._apply_quality();diagnostic_shadow_mode(mode)
 place_camera(world,base,target,Vector3.ZERO)
 # Give atlas changes two render frames to settle before the unchanged test.
 await frame();await frame()
 var poses:Dictionary={"base":camera_pose(world)}
 var a:Image=await frame();var b:Image=await frame()
 place_camera(world,base,target,right*pixel*.24);poses.quarter_right=camera_pose(world);var quarter_right:Image=await frame()
 place_camera(world,base,target,right*pixel);poses.one_right=camera_pose(world);var whole_right:Image=await frame()
 place_camera(world,base,target,up*pixel*.24);poses.quarter_up=camera_pose(world);var quarter_up:Image=await frame()
 place_camera(world,base,target,up*pixel);poses.one_up=camera_pose(world);var whole_up:Image=await frame()
 # Independent640 recount found5 differing edge pixels.20 permits small
 # single-edge raster/lighting precision differences, not wholesale shimmer.
 # Scale with image perimeter (30 at960,40 at1280), never with pixel area.
 var edge_budget:int=ceili(20.0*float(canvas_width)/640.0)
 var lights:Array=[]
 for item in original_shadows:lights.append({"name":str(item.node.name),"class":item.node.get_class(),"shadow_enabled":item.node.shadow_enabled})
 var result={"canvas":str(game.view.size),"requested_canvas_width":canvas_width,"density_mode":game.settings.pixel_density,"renderer":RenderingServer.get_video_adapter_name(),"pixel_world_size":pixel,"edge_budget_pixels":edge_budget,"budget_basis":"640 independent recount:5; allowance20; linear perimeter scaling at higher density","shadow_mode":mode,"quality":profile,"settings":game.settings.duplicate(true),"directional_atlas_requested_px":4096 if profile=="high" else (1024 if profile=="low" else 2048),"positional_atlas_px":game.view.positional_shadow_atlas_size,"lights":lights,"source_hashes_before":source_hashes_before,"source_hashes_after":scene_hashes(),"camera_poses":poses,"frozen_visual_time":world.visual_time,"static":changed(a,b),"quarter_right":changed(a,quarter_right),"one_right":changed(a,whole_right,Vector2i(1,0)),"quarter_up":changed(a,quarter_up),"one_up":changed(a,whole_up,Vector2i(0,-1))}
 result.source_hashes_stable=result.source_hashes_before==result.source_hashes_after
 result.passed=game.view.size.x==canvas_width and result.static.changed_pixels==0 and result.quarter_right.changed_pixels==0 and result.quarter_up.changed_pixels==0 and result.one_right.changed_pixels>=0 and result.one_right.changed_pixels<=edge_budget and result.one_up.changed_pixels>=0 and result.one_up.changed_pixels<=edge_budget
 DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(path))
 for pair in [["base",a],["static",b],["quarter-right",quarter_right],["one-right",whole_right],["quarter-up",quarter_up],["one-up",whole_up]]:pair[1].save_png(path+"/stability-"+pair[0]+".png")
 var file=FileAccess.open(path+"/pixel-stability.json",FileAccess.WRITE);file.store_string(JSON.stringify(result,"  "));file.close()
 var summary:Dictionary={"canvas":result.canvas,"shadow_mode":mode,"quality":profile,"passed":result.passed,"source_hashes_stable":result.source_hashes_stable,"edge_budget_pixels":edge_budget}
 for key in ["static","quarter_right","one_right","quarter_up","one_up"]:
  summary[key]=result[key].duplicate();summary[key].erase("first_changed_xy_max_rgb_delta")
 print("PIXEL_STABILITY ",JSON.stringify(summary))
 return bool(result.passed)
func run() -> void:
 for argument in OS.get_cmdline_user_args():
  if argument.begins_with("--canvas="):canvas_width=int(argument.trim_prefix("--canvas="))
  elif argument.begins_with("--output-dir="):output_dir=argument.trim_prefix("--output-dir=")
  elif argument.begins_with("--shadow-mode="):shadow_mode=argument.trim_prefix("--shadow-mode=")
  elif argument.begins_with("--quality="):quality=argument.trim_prefix("--quality=")
  elif argument=="--diagnose-shadows":diagnose_shadows=true
  elif argument=="--diagnose-shadow-types":diagnose_shadow_types=true
 if not canvas_width in [640,960,1280] or not shadow_mode in ["all","off","directional","positional"] or not quality in ["standard","high","low"]:push_error("Invalid canvas, diagnostic shadow mode, or quality");quit(2);return
 if output_dir=="res://docs/qa/v4/density-stability-640":output_dir="res://docs/qa/v4/density-stability-%d"%canvas_width
 if DisplayServer.get_name()=="headless":push_error("Pixel stability needs an actual rendering display");quit(2);return
 source_hashes_before=scene_hashes()
 game=load("res://scenes/main.tscn").instantiate();root.add_child(game)
 game.get_window().size=Vector2i(1920,1080) if canvas_width==960 else Vector2i(1280,720)
 game.settings.pixel_density="low" if canvas_width==640 else ("balanced" if canvas_width==960 else "auto")
 game.settings.quality=quality;game._apply_quality()
 await create_timer(2.0).timeout
 game.set_process(false);game.world.set_process(false)
 var world=game.world;world.focus("hub",true);world._process(0)
 for light in world.find_children("*","Light3D",true,false):original_shadows.append({"node":light,"enabled":light.shadow_enabled})
 var pixel:float=world.camera.size/float(game.view.size.y)
 # Align BOTH camera-plane axes before quarter-step comparisons.
 var base:Vector3=world.camera.position
 var target:Vector3=world.smooth_camera_look+(base-world.smooth_camera_position)
 var right:Vector3=world.camera.global_basis.x;var up:Vector3=world.camera.global_basis.y
 var passed:bool=true
 if diagnose_shadows or diagnose_shadow_types:
  # One frozen scene/camera/actor pose shared by all cases: only the two
  # diagnostic shadow switches change. Each result captures its own settings.
  var probes:Array=[["off-standard","off","standard"],["all-standard","all","standard"],["all-high","all","high"]]
  if diagnose_shadow_types:probes=[["off-standard","off","standard"],["directional-standard","directional","standard"],["positional-standard","positional","standard"],["all-standard","all","standard"]]
  for probe in probes:
   passed=await capture_case(world,base,target,right,up,pixel,probe[1],probe[2],output_dir+"/"+probe[0]) and passed
 else:passed=await capture_case(world,base,target,right,up,pixel,shadow_mode,quality,output_dir)
 await game._quit_cleanly(0 if passed else 1)
