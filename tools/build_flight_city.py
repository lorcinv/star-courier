"""Derive a quieter flight backdrop from our editable Blender city source."""
import bpy, os
ROOT=os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
bpy.ops.wm.open_mainfile(filepath=os.path.join(ROOT,'source_art/environment_v2/orbital_post_office_editable.blend'))
bpy.ops.object.select_all(action='DESELECT')
city=bpy.data.collections['Orbital_City']
selected=[o for o in city.objects if not o.name.startswith(('Transit_track','Transit_lightline','Transit_support'))]
for obj in selected: obj.select_set(True)
bpy.context.view_layer.objects.active=next(o for o in selected if o.type=='MESH')
bpy.ops.object.convert(target='MESH');bpy.ops.object.join()
bpy.context.object.name='Flight_City_Quiet_Skyline'
bpy.context.scene.cursor.location=(0,0,0);bpy.ops.object.origin_set(type='ORIGIN_CURSOR')
bpy.ops.export_scene.gltf(filepath=os.path.join(ROOT,'assets/environment_v2/flight_city.glb'),export_format='GLB',use_selection=True,export_apply=True,export_cameras=False,export_lights=False)
