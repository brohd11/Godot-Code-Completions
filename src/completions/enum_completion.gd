@tool
extends EditorCodeCompletion
#! import

const CacheHelper = EditorCodeCompletionSingleton.CacheHelper

var data_cache = {}

func _singleton_ready():
	pass


func _on_code_completion_requested(script_editor:CodeEdit) -> bool:
	
	var current_state := get_state()
	if current_state == State.ASSIGNMENT:
		var t = EditorCodeCompletionSingleton.TimeFunction.new("ASSIGN ALL", EditorCodeCompletionSingleton.TimeFunction.TimeScale.USEC)
		var a = _var_assign()
		t.stop()
		return a
	elif current_state == State.FUNC_ARGS:
		var t = EditorCodeCompletionSingleton.TimeFunction.new("FUNC ALL", EditorCodeCompletionSingleton.TimeFunction.TimeScale.USEC)
		var f = _func_call()
		t.stop()
		return f
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
		#var var_data = UString.get_var_name_and_type_hint_in_line(left)
		#if var_data == null:
			#return false
		#var type_hint = var_data[1]
		var left_typed = assignment_data.get("left_typed", "")
		return _process_to_enum_data(left_typed)
		#return _process_to_enum_data(type_hint)
	else:
		var left_typed = assignment_data.get("left_typed", "")
		if left_typed.ends_with(")") and operator == "==": # converts to dict
			return _process_to_enum_data(_func_comparison(left_typed))
		return _process_to_enum_data(left_typed)

func _func_call() -> bool:
	var t = EditorCodeCompletionSingleton.TimeFunction.new("GET FUNC CALL DATA", EditorCodeCompletionSingleton.TimeFunction.TimeScale.USEC)
	var current_script = get_current_script()
	var func_call_data = get_func_call_data()
	var full_call:String = func_call_data.get("full_call")
	var full_call_typed:String
	var current_arg_idx = func_call_data.get("current_arg_index")
	var current_args = func_call_data.get("args")
	print(func_call_data)
	t.stop()
	if current_arg_idx < current_args.size():
		var arg_text = current_args[current_arg_idx]
		if arg_text != "":
			return false
	
	var external_method = false
	var access_name = "" # for class body
	var func_method = full_call
	
	if full_call.find(".") > -1:
		func_call_data = get_func_call_data(true)
		full_call_typed = func_call_data.get("full_call_typed")
		print("FULL CALL TYPED ", full_call_typed)
		var rfind_idx = full_call_typed.rfind(".")
		func_method = full_call_typed.substr(rfind_idx + 1)
		access_name = full_call_typed.substr(0, rfind_idx)
		
		if access_name != "": # not script_var_map.has(access_name):
			external_method = true
	
	#print("FUNC NAME: ", access_name, " METHOD: ", func_method)
	#print("EXTERNAL ",external_method)
	var t2 = EditorCodeCompletionSingleton.TimeFunction.new("PROCESS FUNC CALL DATA", EditorCodeCompletionSingleton.TimeFunction.TimeScale.USEC)
	var data
	if not external_method: # internal method
		var current_class = get_current_class()
		if class_has_func(func_method, current_class):
			var func_args = get_func_args(current_class, func_method)
			if func_args.has("args"):
				print("GOT ARGS")
				data = func_args # set to data to process below, property info
			else:
				if func_args.is_empty():
					return false
				var arg_names = func_args.keys()
				if arg_names.size() > current_arg_idx:
					var current_arg_name = arg_names[current_arg_idx]
					var current_arg_type = func_args[current_arg_name]
					t2.stop()
					return _process_to_enum_data(current_arg_type, current_arg_idx == 0)
			
		else: # not in current script, thus inherited
			data = UClassDetail.get_member_info_by_path(current_script, func_method, ["property", "method", "const"])
			#print("INHERITED DATA ", data)
	else: # external method, func call has "." in it
		data = _get_cached_data(current_script.resource_path, full_call, data_cache)
		#print("CACHED DATA ", data)
		if data == null:
			var func_script = UClassDetail.get_member_info_by_path(current_script, access_name, UClassDetail._MEMBER_ARGS, false, true)#, ["property", "const"])
			print("FUNC SCRIPT ", func_script)
			
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
	#print("FINAL DATA ", data)
	if data == null:
		return false
	#singleton.gdscript_parser.data_access_search.set_global_check_setting()
	var args = data.get("args", [])
	if args.size() > current_arg_idx:
		var arg_data = args[current_arg_idx]
		if not _is_property_info_enum(arg_data):
			return false
		print("ADDING")
		t2.stop()
		var _class = arg_data.get("class_name")
		#var other_options = _get_script_enum_vars(_class) # unsure yet
		return _process_to_enum_data(arg_data, current_arg_idx == 0)
	
	return false




func _process_to_enum_data(input_data, force_update:=false):
	var t2 = EditorCodeCompletionSingleton.TimeFunction.new("PROCESS INPUT", EditorCodeCompletionSingleton.TimeFunction.TimeScale.USEC)
	print("Input Data: ", input_data)
	var process_input = _process_input_data(input_data)
	
	if process_input == null:
		return false
	t2.stop()
	var enum_data = process_input.enum_data
	var enum_script = process_input.enum_script
	var member_path = process_input.member_path
	
	
	prints("ENUM STUFF:",enum_script, enum_data,"MEMBER_PATH:", member_path)
	
	if enum_data == null:
		return false
	if not (enum_data is Dictionary or enum_data is PackedStringArray):
		return false
	
	#if not (input_is_access_path or input_is_godot_enum):
	if enum_script != null:
		var t = EditorCodeCompletionSingleton.TimeFunction.new("Alias", EditorCodeCompletionSingleton.TimeFunction.TimeScale.USEC)
		var current_script = get_current_script()
		var alias = _check_inherited_preloads_for_alias(member_path, enum_data, enum_script, current_script)
		if alias !=  null:
			member_path = alias
		t.stop()
	else: # set to null for built in classes
		member_path = EditorCodeCompletionSingleton.DataAccessSearch.check_for_godot_class_inheritance(member_path)
	
	#var other_options = _get_script_enum_vars(_class) # unsure yet
	var other_options = []
	
	if enum_data is Dictionary:
		enum_data = enum_data.keys()
	if enum_data.is_empty():
		return false
	return _add_code_completions(member_path, enum_data, other_options, force_update)


func _process_input_data(input_data):
	var current_script = get_current_script()
	var enum_data = null
	var enum_script = null
	var enum_access_path = ""
	var enum_class_string = ""
	var member_path = input_data
	if input_data is String:
		print("STRING")
		if input_data.begins_with("res://"): # this is basically the same as the property info version below
			var gd_idx = input_data.find(".gd.")
			if gd_idx == -1:
				return null
			var class_path = input_data.substr(0, gd_idx + 3) # + 3 to keep ext
			enum_script = load(class_path)
			enum_access_path = input_data.substr(gd_idx + 4) # + 4 to omit ext
			enum_data = get_script_member_info_by_path(enum_script, enum_access_path, ["const"])
			if _is_dict_enum(enum_data):
				member_path = enum_access_path
				return {"enum_data":enum_data, "enum_script":enum_script, "member_path":member_path}
		else:
			var dot_idx = input_data.find(".")
			if dot_idx == -1:
				if singleton.VariantChecker.check_type(input_data):
					return null
				
				var script_enum_members = get_enum_members(input_data)
				if script_enum_members != null:
					return {"enum_data":script_enum_members, "enum_script":null, "member_path": input_data}
			else:
				var enum_name = UString.get_member_access_back(input_data)
				var enum_class = UString.trim_member_access_back(input_data)
				var script_enum_members = get_enum_members(enum_name, enum_class)
				if script_enum_members != null:
					return {"enum_data":script_enum_members, "enum_script":current_script, "member_path": input_data}
					#return {"enum_data":script_enum_members, "enum_script":null, "member_path": input_data}
				
			
			var godot_built_in_check = _check_godot_class_enum(input_data, current_script)
			if godot_built_in_check != null:
				enum_data = godot_built_in_check
				return {"enum_data":enum_data, "enum_script":null, "member_path": member_path}
			
			var member_info = get_script_member_info_by_path(current_script, input_data, ["const"], false)
			if member_info != null:
				if _is_dict_enum(member_info):
					enum_data = member_info
					return {"enum_data":enum_data, "enum_script":null, "member_path": member_path}
		
		
		
		var data_check = get_script_member_info_by_path(current_script, input_data)
		if data_check is Dictionary and _is_dict_enum(data_check):
			print("STRING TO ENUM")
			var script_access = UString.trim_member_access_back(input_data)
			enum_script = get_script_member_info_by_path(current_script, script_access, ["const"])
			if enum_script is GDScript:
				enum_access_path = UString.get_member_access_back(input_data)
			else:
				if input_data.find(".") == -1: # not sure about this section
					var const_val = _get_constant_value(current_script, input_data)
					print(const_val)
					if const_val is String:
						script_access = UString.trim_member_access_back(const_val)
						enum_script = get_script_member_info_by_path(current_script, script_access, ["const"])
					elif const_val is GDScript:
						enum_script = const_val
					else:
						print(const_val)
					if enum_script is GDScript:
						enum_access_path = UString.get_member_access_back(const_val)
				else:
					printerr("INPUT DATA UNHANDLED: ", input_data)
			
			if enum_script is GDScript:
				enum_data = get_script_member_info_by_path(enum_script, enum_access_path, ["const"])
				if _is_dict_enum(enum_data):
					#enum_script = null # set enum script to null to stop alias search
					return {"enum_data":enum_data, "enum_script":enum_script, "member_path":member_path}
			else:
				print("COULD NOT GET SCRIPT: -> ", script_access)
				pass
			
		else: # data is not enum dict, process below if applicable
			print("DATA IS NOT ENUM, PROCESSING BELOW: ", data_check)
			input_data = data_check
	
	
	if input_data is Dictionary:
		if _is_property_info_enum(input_data):
			#print("PROPERTY TO ENUM")
			var class_nm = input_data.get("class_name")
			var godot_built_in_check = _check_godot_class_enum(class_nm, current_script)
			if godot_built_in_check != null:
				enum_data = godot_built_in_check
				member_path = class_nm
				return {"enum_data":enum_data, "enum_script": null, "member_path": member_path}
			var t = TimeFunction.new("PROPERTY TO ENUM")
			
			enum_script = UClassDetail.get_script_from_property_info(input_data, current_script)
			enum_access_path = class_nm.trim_prefix(enum_script.resource_path).trim_prefix(".")
			enum_data = get_script_member_info_by_path(enum_script, enum_access_path, ["const"])
			t.stop()
			if enum_data == null:
				print(enum_script, enum_access_path)
			if _is_dict_enum(enum_data):
				member_path = enum_access_path
				
				return {"enum_data":enum_data, "enum_script":enum_script, "member_path":member_path}
	
	return null



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
		if not _is_property_info_enum(data):
			continue
		if data.get("class_name") == enum_class_string:
			vars.append(p)
	
	_store_data(current_script.resource_path, enum_class_string, vars, current_script, data_cache)
	return vars


func _func_comparison(comp_text:String):
	var current_script = get_current_script()
	var string_map = get_string_map(comp_text)
	var count = comp_text.length() - 1
	while count >= 0:
		var char = comp_text[count]
		if char == ")":
			if string_map.bracket_map.has(count):
				count = string_map.bracket_map[count]
				break
			else:
				print("BRACK MAP DOESNT HAVE: ", count, " : ", string_map.bracket_map, " ", string_map.string)
		count -= 1
	
	var func_name = comp_text.substr(0, count)
	print("FUNC COMPARISON -> ", comp_text, " ", func_name)
	var member_info = UClassDetail.get_member_info_by_path(current_script, func_name)
	if member_info != null:
		var return_info = member_info.get("return") # looking for enum data
		if return_info != null:
			return return_info
	return comp_text

const TimeFunction = EditorCodeCompletionSingleton.TimeFunction

func _check_inherited_preloads_for_alias(access_path:String, enum_data, enum_script:GDScript, script:GDScript):
	var global_classes = UClassDetail.get_all_global_class_paths()
	var first_part = UString.get_member_access_front(access_path)
	if enum_script.resource_path == script.resource_path:
		if global_classes.has(first_part):
			#print("ENUM IN GLOBAL SCRIPT: ", UString.trim_member_access_front(access_path))
			return UString.trim_member_access_front(access_path)
		#print("ENUM SCRIPT == SCRIPT: ", access_path)
		return access_path # if the enum is in current script, no need to check alias
	var original_access_path = access_path
	var dot_idx = access_path.find(".")
	if dot_idx == -1:
		var member_info = UClassDetail.get_member_info(script, access_path, ["const"])
		if member_info != null and _is_dict_enum(member_info):
			#print("ENUM IN SCRIPT, NO DOT: ", access_path)
			return access_path
	
	var deep = true #^ this is set to true to allow searching inner classes, could cause issues with preloads
	var enum_access_path = UClassDetail.script_get_member_by_value(enum_script, enum_data, deep, ["const"])
	if enum_access_path == null: # should be impossible...
		print("COULD NOT GET ENUM ACCESS, SHOULD NOT HAPPEN: ", original_access_path)
		print(enum_script.resource_path)
		return original_access_path
	
	var preload_map = get_preload_map() # path is key
	if preload_map.has(enum_script.resource_path):
		var const_name = preload_map.get(enum_script.resource_path)
		var new_access_path = const_name + "." + enum_access_path
		#print("ALIAS IN PRELOAD MAP")
		return new_access_path
	
	var script_preloads = UClassDetail.script_get_preloads(script) # works
	for p in script_preloads.keys():
		var preload_script = script_preloads.get(p)
		if preload_script.resource_path == enum_script.resource_path:
			#print("alias in hard preloads ", access_path)
			return p + "." + enum_access_path
	
	
	var script_constants = get_script_body_constants(get_current_class())
	if script_constants.has(access_path):
		var const_data = script_constants.get(access_path)
		var type = const_data.get(singleton.GDScriptParser._Keys.TYPE)
		if global_classes.has(UString.get_member_access_front(type)):
			access_path = type
		#return type
	for c in script_constants.keys():# TODO this is not right, doens't work with global classes that have been loade by property info
		var const_data = script_constants.get(c)
		var type = const_data.get(singleton.GDScriptParser._Keys.TYPE)
		if type == original_access_path:
			print("alias in script_map ", c)
			return c # c is constant name
	
	
	var access_path_is_global = false
	if global_classes.has(first_part):
		print("CLASS IS GLOBAL")
		access_path_is_global = true
		access_path = first_part
	#if global_classes.has(UString.get_member_access_front(access_path)):
		#print("CLASS IS GLOBAL")
		#access_path_is_global = true
		#access_path = UString.trim_member_access_front(access_path)
	
	
	# check for preloaded alias in inherited
	var cached_alias = _get_cached_data("ScriptAlias", enum_script, data_cache)
	if cached_alias == null:
		
		#var immediate_alias = EditorCodeCompletionSingleton.DataAccessSearch.script_alias_search_static(access_path, enum_data, false, script)
		#if immediate_alias != null: # this could cause issues with duplicate enums in the current class
			#var alias_path = immediate_alias
			#_store_data("ScriptAlias", enum_script, alias_path, script, data_cache)
			#return alias_path
		
		var script_alias = EditorCodeCompletionSingleton.DataAccessSearch.script_alias_search_static(access_path, enum_script, false, script)
		if script_alias != null: # search current script for enums parent script preloaded
			var alias_path = script_alias + "." + enum_access_path
			_store_data("ScriptAlias", enum_script, alias_path, script, data_cache)
			return alias_path
		
		var preloads = UClassDetail.script_get_preloads(script, true, true)
		for _name in preloads:
			var pl_script = preloads.get(_name)
			script_alias = EditorCodeCompletionSingleton.DataAccessSearch.script_alias_search_static(access_path, enum_script, false, pl_script)
			if script_alias != null: # search preloads and inner classes for enums parent script preloaded
				var alias_path = _name + "." + script_alias + "." + enum_access_path
				_store_data("ScriptAlias", enum_script, alias_path, script, data_cache)
				return alias_path
		
		_store_data("ScriptAlias", enum_script, &"%NO_PATH%", script, data_cache) # store no path until current script is saved
	else:
		print("IS CACHED")
		if cached_alias != &"%NO_PATH%":
			return cached_alias
	
	if access_path_is_global:
		print("RETURNING CUZ GLOBAL")
		return original_access_path
	
	# get global path
	var cached_global_path = _get_cached_data("GlobalPaths", enum_script, data_cache)
	if cached_global_path != null:
		print("CACHED GLOBAL: ", cached_global_path)
		return cached_global_path
	
	
	var global_path_data = EditorCodeCompletionSingleton.DataAccessSearch.get_global_access_path_static(enum_script, global_classes)
	if global_path_data != null:
		global_path_data = global_path_data as Array
		var global_access_path = global_path_data[0]
		var global_script = global_path_data[1]
		var full_global_path = global_access_path + "." + enum_access_path
		var inh_paths = UClassDetail.script_get_inherited_script_paths(global_script)
		_store_data("GlobalPaths", enum_script, full_global_path, global_script, data_cache)
		print("GOT GLOBAL: ", full_global_path)
		return full_global_path
	
	#print("COULD NOT FIND ALIAS")
	return original_access_path

func _get_constant_value(script:GDScript, access_path):
	var class_hint = ""
	if access_path.find(".") == -1:
		var script_constants = get_script_body_constants(get_current_class())
		if script_constants.has(access_path):
			print("alias in script_map ", access_path)
			return script_constants.get(access_path).get(EditorCodeCompletionSingleton.GDScriptParser._Keys.TYPE)
		var preloads = UClassDetail.script_get_preloads(script)
		if preloads.has(access_path):
			print("alias in preloads ", access_path)
			return preloads.get(access_path)
		
	else:
		class_hint = UString.get_member_access_front(access_path)
		var script_constants = get_script_body_constants(get_current_class())
		if script_constants.has(class_hint):
			print("alias in script_map ", access_path)
			return script_constants.get(class_hint).get(EditorCodeCompletionSingleton.GDScriptParser._Keys.TYPE)
	
	return null

func _check_godot_class_enum(member_path, script_to_check:GDScript):
	var dot_idx = member_path.find(".")
	if dot_idx > -1:
		var first_access_part = member_path.substr(0, dot_idx)
		if ClassDB.class_exists(first_access_part):
			var last_access = member_path.substr(dot_idx + 1)
			var member_info = ClassDB.class_get_enum_constants(first_access_part, last_access)
			return member_info
	else:
		var base_type = script_to_check.get_instance_base_type()
		if ClassDB.class_has_enum(base_type, member_path):
			return ClassDB.class_get_enum_constants(base_type, member_path)

func _is_dict_enum(dict:Dictionary):
	var count = 0
	for val in dict.values():
		if val is not int:
			return false
		if val != count:
			return false
		count += 1
	return true


func _is_property_info_enum(data:Dictionary):
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
	
