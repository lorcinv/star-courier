extends "res://scripts/pilot_delivery_rift_simulation_v6.gd"
## Explicit material-response rules for new contracts; old adapters are untouched.
const MaterialProfile=preload("res://scripts/pilot_delivery_rift_profile_v7.gd")
const Materials=preload("res://scripts/material_response_v1.gd")
var material_route_error:String=""
func configure(design:Array,launcher:Array,route_data:Dictionary,random_seed:int=1)->void:
 material_route_error=MaterialProfile.validation_error(route_data)
 if not material_route_error.is_empty():
  super.configure([],[],{},random_seed)
  route=route_data.duplicate(true);free_route_error=material_route_error;delivery_route_error=material_route_error;cell_route_error=material_route_error
  telemetry.control_version=MaterialProfile.VERSION;telemetry.route_error=material_route_error;return
 super.configure(design,launcher,MaterialProfile.compatibility_route(route_data),random_seed)
 route=route_data.duplicate(true)
 _refresh_telemetry()
func cargo_mount_properties(cargo:Dictionary,component_ids:Array=[])->Dictionary:return Materials.cargo_mount_properties(self,cargo,component_ids)
func _damp(p:Dictionary,b:Dictionary,target:Dictionary,dt:float)->void:Materials.damp(self,p,b,target,dt)
func _refresh_telemetry()->void:
 super._refresh_telemetry()
 telemetry.control_version=MaterialProfile.VERSION;telemetry.input_schema=MaterialProfile.INPUT_SCHEMA
 telemetry.material_rules_schema=Materials.SCHEMA
