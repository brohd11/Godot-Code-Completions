#! import
const UClassDetail = preload("res://addons/addon_lib/brohd/alib_editor/utils/src/u_class_detail.gd")
const CacheHelper = preload("res://addons/addon_lib/brohd/alib_runtime/cache_helper/cache_helper.gd")

enum GlobalCheck{
		GLOBAL,
		NAMESPACE,
		OFF
}
enum ScriptAlias{
	INHERITED,
	PRELOADS,
	OFF
}


var _script_alias_setting:= ScriptAlias.INHERITED
var _global_check_setting:= GlobalCheck.GLOBAL
var _data_cache:Dictionary


func set_data_cache(dictionary:Dictionary)  -> void:
	_data_cache = dictionary

func set_global_check_setting(global_check:GlobalCheck):
	_global_check_setting = global_check

func set_script_alias_setting(script_alias:ScriptAlias):
	_script_alias_setting = script_alias

## For paths starting with "res://": Gets the enum data of the passed class, checks if it is present in the current script,
## if not, check's if any global classes have it preloaded.
func get_access_path(data, member_hints:=["const"], class_hint:=""):
	
	if data is Dictionary:
		var _class_name = data.get("class_name")
		if _class_name != null:
			if not _class_name.begins_with("res://"):
				return _class_name
			var script_member = _class_name.get_slice(".gd.", 1)
			var _class_access_path = script_member
			var path = _class_name.get_slice(".gd.", 0) + ".gd"
			var data_script = load(path)
			data = UClassDetail.get_member_info_by_path(data_script, script_member, member_hints)
	
	var current_script = EditorInterface.get_script_editor().get_current_script()
	if _script_alias_setting != ScriptAlias.OFF:
		if class_hint == "":
			var script_alias_search = _script_alias_search(current_script, data)
			if script_alias_search != null:
				return script_alias_search
	
	if _global_check_setting == GlobalCheck.GLOBAL:
		var global_check = get_global_access_path(data, member_hints, class_hint)
		if global_check != null:
			return global_check
	

## ALERT not sure about this one...
func check_for_script_alias(access_path:String, data=null):
	if _script_alias_setting == ScriptAlias.OFF:
		return access_path
	
	var current_script = EditorInterface.get_script_editor().get_current_script()
	if data == null:
		data = UClassDetail.get_member_info_by_path(current_script, access_path, ["const"])
		if data == null:
			return access_path
	
	var alias_search = _script_alias_search(current_script, data)
	if alias_search != null:
		return alias_search
	
	return access_path

func _script_alias_search(script:GDScript, data, member_hints:=["const"]):
	if _script_alias_setting == ScriptAlias.PRELOADS:
		var script_access_path = UClassDetail.script_get_member_by_value(script, data, true, member_hints)
		if script_access_path != null:
			return script_access_path
	elif _script_alias_setting == ScriptAlias.INHERITED:
		var top_script_access_path = UClassDetail.script_get_member_by_value(script, data, false, member_hints)
		print("TOP SCRIPT ", top_script_access_path)
		if top_script_access_path != null:
			return top_script_access_path
		#var preloads = UClassDetail.script_get_preloads(script)
		#for _name in preloads:
			#var pl_script = preloads.get(_name)
			#var script_access_path = UClassDetail.script_get_member_by_value(pl_script, data, false, member_hints)
			#if script_access_path != null:
				#return _name + "." + script_access_path
	return null


static func script_alias_search_static(access_path:String, data=null, deep:=false, current_script=null):
	if current_script == null:
		current_script = EditorInterface.get_script_editor().get_current_script()
	if data == null:
		data = UClassDetail.get_member_info_by_path(current_script, access_path, ["const"])
		if data == null:
			return access_path
	
	var script_access_path = UClassDetail.script_get_member_by_value(current_script, data, deep, ["const"], true)
	#print("STATIC ALIAS SEARCH: ", access_path, " -> ", script_access_path)
	if script_access_path != null:
		return script_access_path
	return null


func get_global_access_path(data, member_hints:=["const"], class_hint:=""):
	if _data_cache != null:
		var cached_access_path = CacheHelper.get_cached_data(data, _data_cache)
		if cached_access_path != null:
			printerr("NOT AN ERROR, RETURN CACHED GLOBAL: ", cached_access_path)
			return cached_access_path
	
	var classes_to_check:= {}
	var namespace_builder_path = UClassDetail.get_global_class_path("NamespaceBuilder")
	if _global_check_setting == GlobalCheck.GLOBAL or namespace_builder_path == "":
		classes_to_check = UClassDetail.get_all_global_class_paths()
	elif _global_check_setting == GlobalCheck.NAMESPACE:
		var namespace_builder = load(namespace_builder_path)
		classes_to_check = namespace_builder.get_namespace_classes()
	
	var access_path_data = get_global_access_path_static(data, classes_to_check, member_hints, class_hint)
	if access_path_data != null:
		var access_path = access_path_data[0]
		if _data_cache != null:
			var final_script = access_path_data[1]
			var inh_paths = UClassDetail.script_get_inherited_script_paths(final_script)
			CacheHelper.store_data(data, access_path, _data_cache)
		
		return access_path

## Search classes for value. Returns Array [access_path, script]
static func get_global_access_path_static(data, classes_to_check:Dictionary={}, member_hints:=["const"], class_hint:=""):
	if classes_to_check.is_empty():
		classes_to_check = UClassDetail.get_all_global_class_paths()
	if class_hint != "":
		var class_path = classes_to_check.get(class_hint, "")
		if class_path != "":
			classes_to_check.erase(class_hint)
			var script = load(class_path)
			var member = UClassDetail.script_get_member_by_value(script, data, true, member_hints)
			if member != null:
				var access_path = class_hint + "." + member
				return [access_path, script]
	
	for global_class_name in classes_to_check:
		var global_class_path = classes_to_check.get(global_class_name)
		var global_class_script = load(global_class_path)
		var member = UClassDetail.script_get_member_by_value(global_class_script, data, true, member_hints)
		if member != null:
			var access_path = global_class_name + "." + member
			return [access_path, global_class_script]
	
	return null

static func check_for_godot_class_inheritance(access_path:String, current_script=null):
	if current_script == null:
		current_script = EditorInterface.get_script_editor().get_current_script()
	var base_instance_type = current_script.get_instance_base_type()
	if base_instance_type == null:
		return access_path
	var cl_nm = access_path
	var enum_name = cl_nm.get_slice(".", cl_nm.get_slice_count(".") - 1)
	if ClassDB.class_has_enum(base_instance_type, enum_name):
		access_path = ""
	return access_path
