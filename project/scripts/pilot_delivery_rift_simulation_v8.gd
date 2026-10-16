extends "res://scripts/pilot_delivery_rift_simulation_v7.gd"
## New contracts opt into local struck-centre shield coverage; old paths stay frozen.
const ShieldProfile=preload("res://scripts/pilot_delivery_rift_profile_v8.gd")
const SpatialShield=preload("res://scripts/spatial_shield_v1.gd")
var shield_route_error:String=""
func configure(design:Array,launcher:Array,route_data:Dictionary,random_seed:int=1)->void:
 shield_route_error=ShieldProfile.validation_error(route_data)
 if not shield_route_error.is_empty():
  super.configure([],[],{},random_seed)
  route=route_data.duplicate(true);free_route_error=shield_route_error;delivery_route_error=shield_route_error;cell_route_error=shield_route_error;material_route_error=shield_route_error
  telemetry.control_version=ShieldProfile.VERSION;telemetry.route_error=shield_route_error;return
 super.configure(design,launcher,ShieldProfile.compatibility_route(route_data),random_seed)
 route=route_data.duplicate(true)
 _refresh_telemetry()
func _damage_part(p:Dictionary,amount:float,source:String)->void:
 if source in ["attack","collision"]:SpatialShield.damage_part(self,p,amount,source)
 else:super._damage_part(p,amount,source)
func shield_coverage_snapshot(shield_id:int=-1)->Dictionary:return SpatialShield.snapshot(self,shield_id)
func _refresh_telemetry()->void:
 super._refresh_telemetry()
 telemetry.control_version=ShieldProfile.VERSION;telemetry.input_schema=ShieldProfile.INPUT_SCHEMA
 telemetry.spatial_shield_schema=SpatialShield.SCHEMA
