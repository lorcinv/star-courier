extends "res://scripts/pilot_delivery_rift_simulation_v5.gd"
## Thin explicit v6 adapter. Environment and legacy mechanics stay inherited.
const CellProfile=preload("res://scripts/pilot_delivery_rift_profile_v6.gd")
const Cells=preload("res://scripts/cell_combinations_v6.gd")
var cell_route_error:String=""
func configure(design:Array,launcher:Array,route_data:Dictionary,random_seed:int=1)->void:
 cell_route_error=CellProfile.validation_error(route_data)
 if not cell_route_error.is_empty():
  super.configure([],[],{},random_seed)
  route=route_data.duplicate(true);free_route_error=cell_route_error;delivery_route_error=cell_route_error
  telemetry.control_version=CellProfile.VERSION;telemetry.route_error=cell_route_error;return
 super.configure(Cells.canonical_design(design),launcher,CellProfile.compatibility_route(route_data),random_seed)
 route=route_data.duplicate(true)
 _refresh_telemetry()
func _cargo_energy_failure_enabled()->bool:return false
func _pay_energy(body:Dictionary,used:float,consumer_id:int)->void:Cells.pay_energy(self,body,used,consumer_id)
func _accelerate(p:Dictionary,target:Dictionary,body:Dictionary,dt:float)->void:Cells.accelerate(self,p,target,body,dt)
func preview_accelerator(id:int)->Dictionary:return Cells.preview_accelerator(self,id)
func _refresh_telemetry()->void:
 super._refresh_telemetry()
 telemetry.control_version=CellProfile.VERSION;telemetry.input_schema=CellProfile.INPUT_SCHEMA
 Cells.refresh(self)
