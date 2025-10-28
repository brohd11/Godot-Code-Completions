@tool
extends EditorCodeCompletion
#! import


var data_cache = {}

func _singleton_ready():
	pass


func _on_code_completion_requested(script_editor:CodeEdit) -> bool:
	var current_state := get_state()
	if current_state == State.ASSIGNMENT:
		return _var_assign()
	elif current_state == State.FUNC_ARGS:
		return _func_call()
	return false


func _func_call() -> bool:
	var func_call_data = get_func_call_data()
	var full_call:String = func_call_data.get("full_call")
	var full_call_typed:String = func_call_data.get("full_call_typed")
	var current_arg_idx = func_call_data.get("current_arg_index")
	var current_args = func_call_data.get("args")
	print(func_call_data)
	#if some_tag ==
	#if UString == 
	
	if current_arg_idx < current_args.size():
		var arg_text = current_args[current_arg_idx]
		if arg_text != "":
			return false
	
	var script_var_map = get_script_var_map()
	
	var external_method = false
	var access_name = "" # for class body
	var func_method = full_call
	
	if full_call.find(".") > -1:
		print("FULL CALL TYPED ", full_call_typed)
		var rfind_idx = full_call_typed.rfind(".")
		func_method = full_call_typed.substr(rfind_idx + 1)
		access_name = full_call_typed.substr(0, rfind_idx)
		
		if access_name != "": # not script_var_map.has(access_name):
			external_method = true
	
	print("FUNC NAME: ", access_name, " METHOD: ", func_method)
	print("EXTERNAL ",external_method)
	var data
	if external_method:
		var current_script = get_current_script()
		data = _get_cached_data(current_script.resource_path, full_call, data_cache)
		if data == null:
			var func_script = UClassDetail.get_member_info_by_path(current_script, access_name, ["property", "const"])
			print("FUNC SCRIPT ", func_script)
			if func_script is Dictionary: # issue with preload typed vars in nested preloads
				func_script = _get_script_from_property_info(func_script)
			
			if func_script == null or func_script is not GDScript:
				return false
			if func_method == "new":
				var method_list = func_script.get_script_method_list()
				for method in method_list:
					var name = method.get("name")
					if name == "_init":
						data = method
						break
			else:
				data = UClassDetail.get_member_info_by_path(func_script, func_method, ["property", "method", "const"])
			_store_data(current_script.resource_path, full_call, data, func_script, data_cache) # may need a better spot for?
		
		if data == null:
			return false
		
		var args = data.get("args", [])
		if args.size() > current_arg_idx:
			var arg_data = args[current_arg_idx]
			if not _is_data_enum(arg_data):
				return false
			print("ADDING")
			var _class = arg_data.get("class_name")
			#var other_options = _get_script_enum_vars(_class) # unsure yet
			return _process_to_enum_data(arg_data, current_arg_idx == 0)
	else: # internal method
		var current_class = get_current_class()
		var func_args = get_func_args(current_class, func_method)
		print("FUNC ARGS ", func_args)
		if func_args.is_empty():
			return false
		var arg_names = func_args.keys()
		if arg_names.size() > current_arg_idx:
			var current_arg_name = arg_names[current_arg_idx]
			var current_arg_type = func_args[current_arg_name]
			print("arg ", current_arg_type)
			return _process_to_enum_data(current_arg_type, current_arg_idx == 0)
	
	return false


func _var_assign() -> bool:
	var assignment_data = get_assignment_at_cursor()
	if assignment_data == null:
		return false
	var left = assignment_data.get("left")
	var operator = assignment_data.get("operator")
	var right = assignment_data.get("right")
	if right != "" and get_word_before_cursor() != "":
		return false
	
	if left.begins_with("var"):
		var var_data = UString.get_var_name_and_type_hint_in_line(left)
		if var_data == null:
			return false
		var type_hint = var_data[1]
		return _process_to_enum_data(type_hint)
	else:
		var left_typed = assignment_data.get("left_typed", "")
		if left_typed.begins_with("res://"):
			printerr("LEFT IS RES:// NEED DATA SEARCH")
		if left_typed.ends_with(")") and operator == "==": # converts to dict
			return _process_to_enum_data(_func_comparison(left_typed))
		return _process_to_enum_data(left_typed)

func _process_to_enum_data(input_data, force_update:=false):
	var current_script = get_current_script()
	var input_data_is_enum = false
	var input_is_property_info = false
	print("Input Data: ", input_data)
	var member_path = input_data
	if input_data is String:
		print("STRING")
		input_data = UClassDetail.get_member_info_by_path(current_script, input_data)
	if input_data is Dictionary:
		if input_data.has("class_name"):
			input_is_property_info = true
			member_path = property_info_to_type(input_data)
			print("CLASS NAME: ", member_path)
		if _is_dict_enum(input_data):
			input_data_is_enum = true
			
		print("DICT")
		if not _is_data_enum(input_data):
			print("NOT ENUM DATA")
			
		
	
	
	
	print("MEMBER_PATH: ", member_path)
	var enum_data
	if input_data_is_enum:
		enum_data = input_data
	elif input_is_property_info:
		enum_data = _property_info_to_enum_data(input_data)
	else:
		enum_data = _member_path_to_enum_data(member_path)
	
	print("Input Data: ", input_data, " Member Path: ", member_path, " Enum Data: ", enum_data)
	if enum_data == null:
		return false
	if not (enum_data is Dictionary or enum_data is PackedStringArray):
		return false
	
	var alias = _check_inherited_preloads_for_alias(member_path, enum_data, current_script)
	if alias !=  null:
		member_path = alias
	member_path = DataAccessSearch.check_for_godot_class_inheritance(member_path)
	
	#var other_options = _get_script_enum_vars(_class) # unsure yet
	
	if enum_data is Dictionary:
		enum_data = enum_data.keys()
	if enum_data.is_empty():
		return false
	
	return _add_code_completions(member_path, enum_data, [], force_update)


## Access path is a path of classes ie. SomeClass.MyEnum, to access the enum member.
## Paths starting with "res://" should be converted before getting here.
func _add_code_completions(member_path, enum_data, other_options:= [], force_update:=false) -> bool:
	print("ADD CODE C")
	var access_path = member_path
	var script_editor = get_code_edit()
	
	var enum_icon = EditorInterface.get_editor_theme().get_icon("Enum", "EditorIcons")
	for member in enum_data: # TODO options can be added via inherited method
		var full_name = member
		if access_path != "":
			full_name = access_path + "." + member
		script_editor.add_code_completion_option(CodeEdit.KIND_ENUM, full_name, full_name, Color.GRAY, enum_icon)
	
	if not other_options.is_empty():
		var prop_icon = EditorInterface.get_editor_theme().get_icon("MemberProperty", "EditorIcons")
		for option in other_options:
			script_editor.add_code_completion_option(CodeEdit.KIND_VARIABLE, option, option, Color.GRAY, prop_icon)
	
	script_editor.update_code_completion_options(force_update)
	return true

func _get_script_map_enum_vars(access_path:String):
	var vars = []
	var current_scope_vars = {}
	#print(access_path)
	#print(current_scope_vars.keys())
	for v in current_scope_vars.keys():
		if v.begins_with("%"):
			continue
		var data = current_scope_vars.get(v, {})
		var type = data.get(EditorCodeCompletionSingleton.GDScriptParser._Keys.TYPE, "")
		#prints(v,type)
		if type == access_path:
			vars.append(v)
	print("SCRIPT MAP ENUM VARS: ", vars)
	return vars

func _get_script_enum_vars(enum_class_string):
	var current_script = EditorInterface.get_script_editor().get_current_script()
	#var cached = _get_cached_data(current_script.resource_path, enum_class_string, data_cache)
	#if cached != null:
		#return cached
	
	
	
	return []
	
	
	var vars = []
	var local_vars = {}
	
	var properties = UClassDetail.script_get_all_properties(current_script, UClassDetail.IncludeInheritance.ALL)
	for p in properties.keys():
		var data = properties.get(p)
		if not _is_data_enum(data):
			continue
		if data.get("class_name") == enum_class_string:
			vars.append(p)
	
	_store_data(current_script.resource_path, enum_class_string, vars, current_script, data_cache)
	return vars


func _func_comparison(comp_text:String):
	var current_script = EditorInterface.get_script_editor().get_current_script()
	var string_map = get_string_map(comp_text)
	var count = comp_text.length() - 1
	while count >= 0:
		var char = comp_text[count]
		if char == ")":
			count = string_map.bracket_map[count]
			break
		count -= 1
	
	var func_name = comp_text.substr(0, count)
	print("FUNC COMPARISON -> ", comp_text)
	var member_info = UClassDetail.get_member_info_by_path(current_script, func_name)
	if member_info != null:
		var return_info = member_info.get("return") # looking for enum data
		if return_info != null:
			return return_info
	
	return comp_text


func _get_script_from_property_info(data):
	var _class = data.get("class_name", "")
	if _class != "":
		if _class.begins_with("res://"):
			if _class.find(".gd.") > -1:
				_class = _class.substr(0, _class.find(".gd.") + 3) # + 3 for the extension
			return load(_class)
		else:
			var path = UClassDetail.get_global_class_path(_class)
			if path != "":
				return load(path)
	return null


func _member_path_to_enum_data(member_path:String):
	var current_script = EditorInterface.get_script_editor().get_current_script()
	var dot_idx = member_path.find(".")
	# Godot class check
	if dot_idx > -1:
		var first_access_part = member_path.substr(0, dot_idx)
		if ClassDB.class_exists(first_access_part):
			print("CLASS EXISTS: ", member_path)
			var last_access = member_path.substr(dot_idx + 1)
			print(first_access_part, last_access)
			var member_info = ClassDB.class_get_enum_constants(first_access_part, last_access)
			return member_info
	else:
		var base_type = current_script.get_instance_base_type()
		if ClassDB.class_has_enum(base_type, member_path):
			return ClassDB.class_get_enum_constants(base_type, member_path)
	# /Godot class check
	var script_constants = get_script_body_constants(get_current_class())
	var member_to_check = member_path
	if dot_idx > -1:
		member_to_check = UString.get_member_access_front(member_path)
	if script_constants.has(member_to_check):
		print("SCRIPT VARS HAS: ", member_to_check)
		
	
	
	
	var member_info = UClassDetail.get_member_info_by_path(current_script, member_path)
	if member_info == null:
		var new_path = member_path.substr(0, member_path.rfind("."))
		print(new_path)
		member_info = UClassDetail.get_member_info_by_path(current_script, new_path)
	
	print("PATH ", member_path,  " MEMBER INFO ", member_info)
	if member_info != null:
		
		if member_info is int:
			var new_path = member_path.substr(0, member_path.rfind(".") + 1)
			print(new_path)
			member_info = UClassDetail.get_member_info_by_path(current_script, new_path)
			
		
		if member_info is not Dictionary:
			return null
		
		if member_info.has("class_name"):
			member_info = _property_info_to_enum_data(member_info)
		if member_info == null:
			printerr("Null in member to enum data ", member_path)
			return null
		if _is_dict_enum(member_info):
			return member_info
		else:
			printerr("WHAT IS THIS DATA: ", member_info)


func _property_info_to_enum_data(property_info:Dictionary):
	if property_info.has("class_name"):
		var _class_name = property_info.get("class_name")
		if _class_name.begins_with("res://"): #could convert to access path first but this works for quicker check
			var enum_full_nm = _class_name.get_slice(".gd.", 1)
			var script_path = _class_name.trim_suffix(enum_full_nm).trim_suffix(".")
			var enum_script = load(script_path)
			return UClassDetail.get_member_info_by_path(enum_script, enum_full_nm, ["enum"])
		else:
			var current_script = EditorInterface.get_script_editor().get_current_script()
			return UClassDetail.get_member_info_by_path(current_script, _class_name, ["enum"])



func _check_inherited_preloads_for_alias(access_path:String, enum_data, script:GDScript):
	var class_hint = ""
	if access_path.find(".") > -1: # TODO this is not right, doens't work with global classes that have been loade by property info
		class_hint = UString.get_member_access_front(access_path)
		var script_constants = get_script_body_constants(get_current_class())
		if script_constants.has(class_hint):
			print("alias in script_map ", access_path)
			return access_path
		#if ClassDB.class_exists(class_hint):
			#return access_path
		#
		#var global_classes = UClassDetail.get_all_global_class_paths()
		#if global_classes.has(class_hint):
			#print("global path in hint ", access_path)
			#return access_path
		pass
	else:
		var script_constants = get_script_body_constants(get_current_class())
		if script_constants.has(access_path):
			print("alias in script_map ", access_path)
			return access_path
		var preloads = UClassDetail.script_get_preloads(script)
		if preloads.has(access_path):
			print("alias in preloads ", access_path)
			return access_path
	
	var alias = DataAccessSearch.script_alias_search_static(access_path, enum_data, false, script)
	if alias != null:
		return alias
	var preloads = UClassDetail.script_get_preloads(script, true, true)
	for _name in preloads:
		var pl_script = preloads.get(_name)
		alias = DataAccessSearch.script_alias_search_static(access_path, enum_data, false, pl_script)
		if alias != null:
			return _name + "." + alias
	return null



func _is_dict_enum(dict:Dictionary):
	var count = 0
	for val in dict.values():
		if val is not int:
			return false
		if val != count:
			return false
		count += 1
	return true


func _is_data_enum(data:Dictionary):
	var type = data.get("type", -1)
	if type != 2:
		return false
	if data.get("class_name", "") != "":
		return true
	return false

class EditorSet:
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
	
