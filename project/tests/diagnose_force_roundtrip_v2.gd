extends "res://tests/test_force_offer_upgrade_v2.gd"
## Original assertion remains; emit exact type/leaf proof before it fails.
func same(a:Variant,b:Variant,label:String) -> void:
 if JSON.stringify(a,"",true,true)!=JSON.stringify(b,"",true,true):
  var differences:Array=[];_type_differences(a,b,"",differences)
  print("FORCE_EXACT_DIAGNOSTIC ",JSON.stringify({"label":label,"differences":differences,"current_json":JSON.stringify(a,"",true,true),"prior_json":JSON.stringify(b,"",true,true),"json_normalized_equal":JSON.stringify(JSON.parse_string(JSON.stringify(a,"",true,true)),"",true,true)==JSON.stringify(JSON.parse_string(JSON.stringify(b,"",true,true)),"",true,true)},"",true,true))
 super.same(a,b,label)
func _type_differences(a:Variant,b:Variant,path:String,result:Array) -> void:
 if a is Dictionary and b is Dictionary:
  for key in a:
   if b.has(key):_type_differences(a[key],b[key],path+"/"+str(key),result)
   else:result.append({"path":path+"/"+str(key),"missing":"prior"})
  for key in b:
   if not a.has(key):result.append({"path":path+"/"+str(key),"missing":"current"})
 elif a is Array and b is Array:
  if a.size()!=b.size():result.append({"path":path,"current_size":a.size(),"prior_size":b.size()})
  for i in mini(a.size(),b.size()):_type_differences(a[i],b[i],path+"/"+str(i),result)
 elif typeof(a)!=typeof(b) or a!=b:result.append({"path":path,"current_type":type_string(typeof(a)),"prior_type":type_string(typeof(b)),"current":a,"prior":b,"exact_value_equal":a==b})
