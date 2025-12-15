@tool
extends EditorCodeCompletion
#! import-p UString,UClassDetail,Assignment,FuncCall,

const CacheHelper = EditorCodeCompletionSingleton.CacheHelper

var enum_enable:= false
var show_member_suggestions:= false
var show_alias_only:=false

var data_cache = {}

var completion_cache = {}

func _singleton_ready():
	_init_set_settings()

func _init_set_settings():
	var ed_settings = EditorInterface.get_editor_settings()
	if not ed_settings.has_setting(EditorSet.ENUM_ENABLE):
		ed_settings.set_setting(EditorSet.ENUM_ENABLE, false)
	if not ed_settings.has_setting(EditorSet.SHOW_MEMBER_SUGGESTIONS):
		ed_settings.set_setting(EditorSet.SHOW_MEMBER_SUGGESTIONS, false)
	if not ed_settings.has_setting(EditorSet.SHOW_ALIAS_ONLY):
		ed_settings.set_setting(EditorSet.SHOW_ALIAS_ONLY, false)
	
	_set_settings()
	ed_settings.settings_changed.connect(_set_settings)

func _set_settings():
	var ed_settings = EditorInterface.get_editor_settings()
	enum_enable = ed_settings.get_setting(EditorSet.ENUM_ENABLE)
	show_member_suggestions = ed_settings.get_setting(EditorSet.SHOW_MEMBER_SUGGESTIONS)
	show_alias_only = ed_settings.get(EditorSet.SHOW_ALIAS_ONLY)

func _on_code_completion_requested(script_editor:CodeEdit) -> bool:
	if not enum_enable:
		return false
	var current_state := get_state()
	if current_state == State.ASSIGNMENT:
		var a:bool = _var_assign()
		return a
	elif current_state == State.FUNC_ARGS:
		var f:bool = _func_call()
		return f
	return false

func _var_assign() -> bool:
	var assignment_data = get_assignment_at_caret()
	if assignment_data == null:
		return false
	var left = assignment_data.get(Assignment.LEFT)
	var operator = assignment_data.get(Assignment.OPERATOR)
	var right = assignment_data.get(Assignment.RIGHT)
	#if right != "" and get_word_before_caret() != "":
		#return false #^ remove so you can type what you want
	
	if left.begins_with("var"):
		var left_typed = assignment_data.get(Assignment.LEFT_TYPED, "")
		return _process_to_enum_data(left_typed)
	else:
		var left_typed = assignment_data.get(Assignment.LEFT_TYPED, "")
		if left_typed.ends_with(")") and operator == "==": # converts to dict
			printerr("FUNC COMPARISON BRANCH: ", left_typed)
			return false
			#return _process_to_enum_data(_func_comparison(left_typed))
		return _process_to_enum_data(left_typed)


func _func_call() -> bool:
	var current_script = get_current_script()
	var func_call_data = get_func_call_data()
	var full_call:String = func_call_data.get(FuncCall.FULL_CALL)
	var full_call_typed:String
	var current_arg_idx = func_call_data.get(FuncCall.ARG_INDEX)
	var current_args = func_call_data.get(FuncCall.ARGS)
	
	if current_arg_idx < current_args.size():
		var arg_text = current_args[current_arg_idx]
		#if arg_text != "":
			#return false #^ remove so you can start typing
	
	var external_method = false
	var access_name = "" # for class body
	var func_method = full_call
	
	if full_call.find(".") > -1:
		func_call_data = get_func_call_data(true)
		full_call_typed = func_call_data.get(FuncCall.FULL_CALL_TYPED)
		#print("FULL CALL TYPED ", full_call_typed)
		var rfind_idx = full_call_typed.rfind(".") #^ full call omits parenthesis in final method
		func_method = full_call_typed.substr(rfind_idx + 1) #^ doesn't need to be bracket safe
		access_name = full_call_typed.substr(0, rfind_idx)
		
		if access_name != "":
			external_method = true
	
	var data
	if not external_method: #^c internal method
		var current_class = get_current_class()
		if class_has_func(func_method, current_class):
			var func_args = get_func_args(current_class, func_method)
			if func_args.has("args"): #^ args from property info
				data = func_args #^ set to data to process below, property info
			else: #^ data from script map
				if func_args.is_empty():
					return false
				var arg_names = func_args.keys()
				if arg_names.size() > current_arg_idx:
					var current_arg_name = arg_names[current_arg_idx]
					var current_arg_type = func_args[current_arg_name]
					return _process_to_enum_data(current_arg_type, current_arg_idx == 0)
			
		else: #^c not in current script, thus inherited
			if current_class == "":
				data = get_script_member_info_by_path(current_script, func_method, ["property", "method", "const"], false)
			else:
				var inner_script = get_script_member_info_by_path(current_script, current_class, ["const"], false)
				if inner_script is GDScript:
					data = get_script_member_info_by_path(inner_script, func_method, ["property", "method", "const"], false)
			
	else: #^c external method, func call has "." in it
		data = _get_cached_data(current_script.resource_path, full_call, data_cache)
		if data == null:
			var func_script = UClassDetail.get_member_info_by_path(current_script, access_name, UClassDetail._MEMBER_ARGS, false, true)
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
		if not _is_property_info_enum(arg_data):
			return false
		
		return _process_to_enum_data(arg_data, current_arg_idx == 0)
	return false


func _process_to_enum_data(input_data, force_update:=false):
	#print("Input Data: ", input_data)
	var process_input = _process_input_data(input_data)
	#print("PROCESS: ", process_input)
	if process_input == null:
		return false
	
	var enum_data = process_input.enum_data
	var enum_script = process_input.enum_script
	var member_path = process_input.member_path
	
	if enum_data == null:
		return false
	if not (enum_data is Dictionary or enum_data is PackedStringArray):
		return false
	
	var alias
	if enum_script != null:
		var deep = true #^ this is set to true to allow searching inner classes, could cause issues with preloads
		var enum_access_path = UClassDetail.script_get_member_by_value(enum_script, enum_data, deep, ["const"])
		if enum_access_path == null: # should be impossible...
			#print("COULD NOT GET ENUM ACCESS, SHOULD NOT HAPPEN: ", member_path)
			#print(enum_script.resource_path)
			return false
		process_input["enum_access_path"] = enum_access_path
		
		var current_script = get_current_script()
		member_path = _get_member_path_from_data(process_input, current_script)
		
		alias = _check_inherited_preloads_for_alias(process_input, current_script)
		if alias != null:
			if show_alias_only:
				member_path = alias
				alias = null
			else:
				if alias == member_path:
					alias = null
				if member_path == null:
					member_path = alias
					alias = null
		
	else: # set to null for built in classes
		member_path = DataAccessSearch.check_for_godot_class_inheritance(member_path)
	
	if member_path == null and alias == null:
		return false
	
	var other_options = []
	if process_input.has("enum_class"):
		process_input.member_path = member_path
		other_options = _get_enum_vars(process_input)
	
	if enum_data is Dictionary:
		enum_data = enum_data.keys()
	if enum_data.is_empty():
		return false
	return _add_code_completions(member_path, enum_data, other_options, force_update, alias)

## Process member data string or dictionary.
func _process_input_data(input_data):
	#print("INPUT DATA ", input_data)
	if input_data is String:
		var processed_data = _process_input_data_string(input_data)
		#print(input_data, " MAIN CALL STRING: ", processed_data)
		if processed_data is Dictionary:
			if processed_data.has("enum_script"):
				return processed_data
			else:
				input_data = processed_data
	
	if input_data is Dictionary:
		var processed_data = _process_input_data_dict(input_data)
		#print(input_data, " MAIN CALL DICT: ", processed_data)
		if processed_data is Dictionary:
			if processed_data.has("enum_script"):
				return processed_data
	return null

## Process string to enum data.
func _process_input_data_string(input_data:String):
	var member_path = input_data
	var script_editor_current_script = get_current_script()
	var current_script = script_editor_current_script
	var current_class = get_current_class()
	if current_class != "":
		current_script = get_script_member_info_by_path(current_script, current_class, ["const"])
		if current_script == null:
			return null
	
	if input_data.begins_with("res://"):
		var gd_idx = input_data.find(".gd.")
		if gd_idx == -1:
			return null
		var class_path = input_data.substr(0, gd_idx + 3) # + 3 to keep ext
		var enum_script = load(class_path)
		var enum_access_path = input_data.substr(gd_idx + 4) # + 4 to omit ext
		var in_current_class = false
		if enum_access_path.find(".") > -1:
			var inner_class_path = UString.trim_member_access_back(enum_access_path)
			enum_access_path = UString.get_member_access_back(enum_access_path)
			enum_script = get_script_member_info_by_path(enum_script, inner_class_path, ["const"])
			
			if script_editor_current_script.resource_path == class_path and inner_class_path == current_class:
				in_current_class = true #^ will this cause issues?
		
		var enum_data = get_script_member_info_by_path(enum_script, enum_access_path, ["const"])
		if enum_data is Dictionary and _is_dict_enum(enum_data):
			member_path = enum_access_path
			if in_current_class:
				enum_script = null
			return {"enum_data":enum_data, "enum_script":enum_script, "member_path":member_path, "enum_class": input_data}
		else:
			return null
	
	var godot_built_in_check = _check_godot_class_enum(input_data, current_script)
	if godot_built_in_check != null: #^ check for built ins
		var enum_data = godot_built_in_check
		return {"enum_data":enum_data, "enum_script":null, "member_path": member_path, "enum_class": input_data}
	
	var is_global = false
	var dot_idx = input_data.find(".")
	if dot_idx > -1:
		var first_name = UString.get_member_access_front(input_data)
		var path = UClassDetail.get_global_class_path(first_name)
		if path != "":
			is_global = true
	
	if not is_global:
		if dot_idx == -1: #^ no dot, check for variants or if enum in current script
			if singleton.VariantChecker.check_type(input_data):
				return null
			
			var enum_data = get_enum_members(input_data)
			if enum_data != null:
				return {"enum_data":enum_data, "enum_script":null, "member_path": input_data, "enum_class": input_data}
			
			enum_data = get_script_member_info_by_path(current_script, input_data, ["const"], false)
			if enum_data != null:
				return {"enum_data":enum_data, "enum_script":null, "member_path": input_data, "enum_class": input_data}
			
		else:
			var enum_name = UString.get_member_access_back(input_data)
			var enum_class = UString.trim_member_access_back(input_data)
			var enum_data = get_enum_members(enum_name, enum_class)
			if enum_data != null:
				return {"enum_data":enum_data, "enum_script":current_script, "member_path": input_data, "enum_class": input_data}
	
	var member_info = get_script_member_info_by_path(current_script, input_data) #^ must be all hints to traverse properties!
	if member_info != null:
		if member_info is Dictionary:
			if _is_dict_enum(member_info):
				var enum_data = member_info
				if dot_idx == -1:
					return {"enum_data":enum_data, "enum_script":null, "member_path": member_path, "enum_class": input_data}
				else:
					var enum_script_path = UString.trim_member_access_back(input_data)
					var enum_script = get_script_member_info_by_path(current_script, enum_script_path)
					if enum_script is Dictionary: #^ ensure property info converted to script in chained members
						enum_script = UClassDetail.get_script_from_property_info(enum_script)
					if enum_script != null:
						return {"enum_data":enum_data, "enum_script":enum_script, "member_path": member_path, "enum_class": input_data}
			else:
				var processed_data = _process_input_data_dict(member_info)
				#printerr(input_data, " PROCESS STRING CALL DICT", processed_data)
				return processed_data
		#else:
			#printerr("Enum Member info not dict: ", member_info)
	
	return null

## Process dictionary to enum data.
func _process_input_data_dict(input_data):
	var current_script = get_current_script()
	if _is_property_info_enum(input_data):
		var class_nm = input_data.get("class_name")
		var processed_data = _process_input_data_string(class_nm)
		if processed_data is Dictionary:
			#printerr(input_data, " PROCESS DICT CALL STRING: ", processed_data)
			return processed_data
	
	return null


## Access path is a path of classes ie. SomeClass.MyEnum, to access the enum member.
## Enum Data is an array of enum member names.
func _add_code_completions(access_path:String, enum_members:Array, other_options:= [], force_update:=false, alias=null) -> bool:
	var script_editor = get_code_edit()
	
	var enum_icon = EditorInterface.get_editor_theme().get_icon("Enum", "EditorIcons")
	
	for member in enum_members: # TODO options can be added via inherited method
		var full_name = member
		if access_path != "":
			full_name = access_path + "." + member
		script_editor.add_code_completion_option(CodeEdit.KIND_ENUM, full_name, full_name, Color.GRAY, enum_icon)
	
	if alias != null:
		for member in enum_members:
			var full_name = member
			if alias != "":
				full_name = alias + "." + member
			var display_name = full_name + "[script alias]"
			script_editor.add_code_completion_option(CodeEdit.KIND_ENUM, display_name, full_name, Color.GRAY, enum_icon, null, 256)
	
	if not other_options.is_empty():
		var prop_icon = EditorInterface.get_editor_theme().get_icon("MemberProperty", "EditorIcons")
		for option in other_options:
			script_editor.add_code_completion_option(CodeEdit.KIND_VARIABLE, option, option, Color.GRAY, prop_icon)
	
	script_editor.update_code_completion_options(force_update)
	return true


func _get_enum_vars(processed_data:Dictionary) -> Array:
	if not show_member_suggestions:
		return []
	#var t = ALibRuntime.Utils.UProfile.TimeFunction.new("Get enum vars")
	var current_class = get_current_class()
	var current_assigned = ""
	if get_state() == State.ASSIGNMENT:
		var assignment_data = get_assignment_at_caret()
		var left = assignment_data.get(Assignment.LEFT, "")
		if left.find(".") == -1 or left.begins_with("var "):
			if not left.begins_with("var "):
				left = "var " + left
			var var_data = UString.get_var_name_and_type_hint_in_line(left)
			current_assigned = var_data[0]
	
	var enum_class_string = processed_data.enum_class
	var enum_script = processed_data.enum_script
	var member_path = processed_data.member_path
	var enum_data = processed_data.enum_data
	
	var enum_script_path = ""
	if enum_script != null:
		enum_script_path = enum_script.resource_path
	var option_dict = {}
	#print("GET ENUM VARS: ", enum_class_string)
	
	var script_editor = get_code_edit()
	var current_line = script_editor.get_caret_line()
	
	var current_vars = get_in_scope_body_and_local_vars()
	var body_vars = current_vars.body
	var local_vars = current_vars.local
	for name in body_vars.keys():
		if name == current_assigned:
			continue
		if name == enum_class_string or name == member_path: # if name is the class, likely the enum defined as const
			continue
		var data = body_vars.get(name)
		if not data is Dictionary:
			continue
		if not data.has(EditorCodeCompletionSingleton.GDScriptParser._Keys.TYPE):
			continue
		var type = data.get(EditorCodeCompletionSingleton.GDScriptParser._Keys.TYPE)
		if type == enum_class_string or type == member_path:
			option_dict[name] = true
	for name in local_vars.keys():
		var data = local_vars.get(name)
		if not data is Dictionary:
			continue
		if not data.has(EditorCodeCompletionSingleton.GDScriptParser._Keys.TYPE):
			continue
		var type = data.get(EditorCodeCompletionSingleton.GDScriptParser._Keys.TYPE)
		if type == enum_class_string or type == member_path:
			if name.find("%") > -1:
				name = name.substr(0, name.find("%"))
			if name == current_assigned:
				continue
			option_dict[name] = true
	
	var current_script = get_current_script()
	if current_class != "":
		current_script = get_script_member_info_by_path(current_script, current_class)
		if current_script == null:
			return option_dict.keys()
	
	var properties = UClassDetail.script_get_all_properties(current_script, UClassDetail.IncludeInheritance.ALL)
	for p in properties.keys():
		if p == current_assigned:
			continue
		var data = properties.get(p)
		if not _is_property_info_enum(data):
			continue
		var _class_name = data.get("class_name")
		#print(_class_name, " ", enum_class_string, " ",member_path)
		if _class_name == enum_class_string:
			option_dict[p] = true
			continue
		if enum_script_path != "":
			if _class_name.begins_with(enum_script_path):
				option_dict[p] = true
	
	
	#t.stop()
	return option_dict.keys()


func _get_member_path_from_data(processed_input:Dictionary, script:GDScript):
	var t = ALibRuntime.Utils.UProfile.TimeFunction.new("GET PATH",)
	var enum_data = processed_input.enum_data
	var enum_script = processed_input.enum_script
	var access_path = processed_input.member_path
	var enum_class_string = processed_input.enum_class
	var enum_access_path = processed_input.enum_access_path
	
	var enum_script_path = enum_script.resource_path
	var current_script_path = script.resource_path
	
	if not enum_class_string.begins_with("res://"):
		var global_class_name = UString.get_member_access_front(enum_class_string)
		var path = UClassDetail.get_global_class_path(global_class_name)
		var inherited_scripts = UClassDetail.script_get_inherited_script_paths(script)
		if path in inherited_scripts:
			return UString.trim_member_access_front(enum_class_string)
		
		return enum_class_string
	
	if enum_class_string.begins_with(current_script_path):
		return enum_class_string.get_slice(".gd.", 1)
	
	var preload_alias = _get_preload_alias(access_path, enum_class_string) #^ unsure if want to have this here too
	if preload_alias != null:
		return preload_alias
	
	
	t.stop()
	var global_classes_data = get_global_script_location(enum_script)
	if global_classes_data == null:
		print("DONT HAVE GLOBAL")
		return null
	
	print("HAVE GLOBAL")
	var class_hint = ""
	var current_state = get_state()
	if current_state == State.FUNC_ARGS:
		var func_call_data = get_func_call_data(true)
		var full_call_typed = func_call_data.get(FuncCall.FULL_CALL_TYPED, "")
		class_hint = UString.get_member_access_front(full_call_typed)
	elif current_state == State.ASSIGNMENT:
		var assignment_data = get_assignment_at_caret()
		var left_typed = assignment_data.get(Assignment.LEFT_TYPED, "")
		class_hint = UString.get_member_access_front(left_typed)
	print(class_hint)
	var global_member_access_path = ""
	var global_data = {}
	if global_classes_data.has(class_hint):
		global_data = global_classes_data[class_hint]
	else:
		var first_class_hint = global_classes_data.keys()[0]
		global_data = global_classes_data[first_class_hint]
		class_hint = first_class_hint
	
	var member_access = global_data["member_access"]
	print("QUICK GRAB")
	t.stop()
	return class_hint + "." + member_access + "." + enum_access_path


func _check_inherited_preloads_for_alias(processed_input:Dictionary, script:GDScript):
	var enum_data = processed_input.enum_data
	var enum_script = processed_input.enum_script
	var access_path = processed_input.member_path
	var enum_class_string = processed_input.enum_class
	var enum_access_path = processed_input.enum_access_path
	
	var dot_idx = access_path.find(".")
	if dot_idx == -1: #^ check current script if not member access
		var member_info = UClassDetail.get_member_info(script, access_path, ["const"])
		if member_info is Dictionary and _is_dict_enum(member_info):
			#print("ENUM IN SCRIPT, NO DOT: ", access_path)
			return access_path
	
	var preload_alias = _get_preload_alias(access_path, enum_class_string)
	if preload_alias != null:
		return preload_alias
	
	var immediate_alias = DataAccessSearch.script_alias_search_static(access_path, enum_data, false, script)
	if immediate_alias != null: #^ this could cause issues with duplicate enums in the current class
		var alias_path = immediate_alias
		#print("IMMEDIATE ALIAS")
		return alias_path
	
	#^ deep alias search
	var script_path = script.resource_path
	var script_alias_section = data_cache.get_or_add("ScriptAlias", {})
	var cached_alias = _get_cached_data(script_path, enum_script, script_alias_section)
	if cached_alias == null:
		var script_alias = DataAccessSearch.script_alias_search_static(access_path, enum_script, false, script)
		if script_alias != null: #^ search current script for enums parent script preloaded
			var alias_path = script_alias + "." + enum_access_path
			_store_data(script_path, enum_script, alias_path, script, script_alias_section)
			return alias_path
		
		var preloads = UClassDetail.script_get_preloads(script, true, true)
		for _name in preloads:
			var pl_script = preloads.get(_name)
			script_alias = DataAccessSearch.script_alias_search_static(access_path, enum_script, false, pl_script)
			if script_alias != null: #^ search preloads and inner classes for enums parent script preloaded
				var alias_path = _name + "." + script_alias + "." + enum_access_path
				_store_data(script_path, enum_script, alias_path, script, script_alias_section)
				return alias_path
		
		_store_data(script_path, enum_script, &"%NO_PATH%", script, script_alias_section) # store no path until current script is saved
	else:
		if cached_alias != &"%NO_PATH%":
			return cached_alias
	
	#print("COULD NOT FIND ALIAS")
	return null

func _get_preload_alias(access_path:String, enum_class_string:String):
	var best_preload_alias = ""
	var best_preload_length = 0
	var preload_map = get_preload_map() # path is key
	if preload_map.has(enum_class_string):
		#print("DIRECT PRELOAD")
		return preload_map.get(enum_class_string)
	
	for nm_or_path:String in preload_map.keys():
		if access_path.begins_with(nm_or_path) or enum_class_string.begins_with(nm_or_path):
			if nm_or_path.length() > best_preload_length:
				best_preload_alias = nm_or_path
				best_preload_length = best_preload_alias.length()
	
	if best_preload_alias != "":
		var val = preload_map.get(best_preload_alias)
		var new_path = val
		if access_path.begins_with(best_preload_alias):
			new_path = access_path.trim_prefix(best_preload_alias)
			new_path = val + new_path
		elif enum_class_string.begins_with(best_preload_alias):
			new_path = enum_class_string.trim_prefix(best_preload_alias)
			new_path = val + new_path
			pass
		#prints("PRELOAD BEGINS WITH: ", best_preload_alias,":", val, access_path, "->", new_path)
		return new_path
	
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
	const ENUM_ENABLE = &"plugin/code_completion/enum/enable"
	const SHOW_MEMBER_SUGGESTIONS = &"plugin/code_completion/enum/show_member_suggestions"
	const SHOW_ALIAS_ONLY = &"plugin/code_completion/enum/show_alias_only"
