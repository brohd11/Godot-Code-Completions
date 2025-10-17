@tool
extends EditorCodeCompletion

func _on_code_completion_requested(script_editor:CodeEdit) -> bool:
	var current_line_text = script_editor.get_line(script_editor.get_caret_line())
	var caret_col = script_editor.get_caret_column()
	if is_caret_in_comment(current_line_text, caret_col):
		return false
	
	var stripped_text = current_line_text.strip_edges()
	if not (stripped_text.begins_with("func ") or stripped_text.begins_with("static func ")):
		var func_call_data = get_func_call_data(current_line_text)
		if not func_call_data.is_empty():
			return _func_call(script_editor, current_line_text, func_call_data)
	
	if current_line_text.find("=") > -1:
		return _var_assign(script_editor, current_line_text)
	return false


func _func_call(script_editor:CodeEdit, current_line_text:String, func_call_data:Dictionary) -> bool:
	var current_script = EditorInterface.get_script_editor().get_current_script()
	var func_name:String = func_call_data.name
	var current_arg_idx = func_call_data.current_arg_index
	var current_args = func_call_data.args
	
	if current_arg_idx < current_args.size():
		var arg_text = current_args[current_arg_idx]
		if arg_text != "":
			return false
	
	func_name = _sub_var_type(func_name)
	
	var args = []
	if func_name.ends_with(".new"):
		func_name = func_name.trim_suffix(".new")
		var func_script = UClassDetail.get_member_info_by_path(current_script, func_name)
		if func_script == null or func_script is not GDScript:
			return false
		var method_list = func_script.get_script_method_list()
		for method in method_list:
			var name = method.get("name")
			if name != "_init":
				continue
			args = method.get("args", [])
			break
	else:
		var data = UClassDetail.get_member_info_by_path(current_script, func_name)
		if data == null:
			return false
		args = data.get("args", [])
		if func_name.find(".") > -1: # remove method name to get script below
			func_name = func_name.substr(0, func_name.rfind("."))
	
	
	if args.size() > current_arg_idx:
		var data = args[current_arg_idx]
		if not _is_data_enum(data):
			return false
		
		var _class = data.get("class_name")
		var access_path = _get_access_path(_class)
		if access_path == null:
			return false
		#else: ## old methd for last resort attempt
			#_class = func_name + "." + script_member # script member is slice after ".gd."
			#print("Setting class to func call: %s -> %s" % [full_class, _class])
			#pass
		
		return _add_code_completions(script_editor, access_path, current_arg_idx == 0)
	
	return false


func _var_assign(script_editor:CodeEdit, current_line_text:String) -> bool:
	var current_script = EditorInterface.get_script_editor().get_current_script()
	var caret_line = script_editor.get_caret_line()
	var caret_col = script_editor.get_caret_column()
	
	var regex_match = get_assignment_at_cursor()
	if regex_match == null:
		return false
	
	var right = regex_match.rhs
	if right != "":
		return false
	var left = regex_match.lhs
	if left.begins_with("var"):
		var property_name = left.get_slice("var", 1)
		if property_name.find(":") == -1:
			return false
		var type_hint = property_name.get_slice(":", 1).strip_edges()
		return _add_code_completions(script_editor, type_hint)
	else:
		left = _sub_var_type(left)
		var property_enum_class_name = _get_property_enum_access_path(current_script, left)
		if property_enum_class_name == null:
			return _add_code_completions(script_editor, left)
		else:
			return _add_code_completions(script_editor, property_enum_class_name)


func _add_code_completions(script_editor:CodeEdit, access_path:String, force:=false) -> bool:
	var enum_data = _get_enum_members(access_path)
	if enum_data == null:
		return false
	if not (enum_data is Dictionary or enum_data is PackedStringArray):
		return false
	
	access_path = _check_for_godot_class_inheritance(access_path)
	access_path = _check_for_script_alias(access_path, enum_data) # TEST
	
	if enum_data is Dictionary:
		enum_data = enum_data.keys()
	if enum_data.is_empty():
		return false
	
	var enum_icon = EditorInterface.get_editor_theme().get_icon("Enum", "EditorIcons")
	for member in enum_data:
		var full_name = member
		if access_path != "":
			full_name = access_path + "." + member
		script_editor.add_code_completion_option(CodeEdit.KIND_ENUM, full_name, full_name, Color.GRAY, enum_icon)
	script_editor.update_code_completion_options(force)
	return true


func _sub_var_type(_name:String):
	_name = sub_var_type(_name, get_func_local_vars())
	_name = sub_var_type(_name, get_script_preload_vars())
	return _name

func _check_for_godot_class_inheritance(access_path:String):
	var current_script = EditorInterface.get_script_editor().get_current_script()
	var base_instance_type = current_script.get_instance_base_type()
	if base_instance_type == null:
		return false
	var cl_nm = access_path
	var enum_name = cl_nm.get_slice(".", cl_nm.get_slice_count(".") - 1)
	if ClassDB.class_has_enum(base_instance_type, enum_name):
		access_path = ""
		#var prefix = cl_nm.get_slice(".", 0)
		#if prefix != enum_name:
			#access_path = cl_nm.trim_prefix(prefix).trim_prefix(".")
	
	return access_path

func _check_for_script_alias(access_path:String, enum_data=null):
	var parts = access_path.split(".", false)
	var current_script = EditorInterface.get_script_editor().get_current_script()
	var parts_working = ""
	if enum_data == null:
		enum_data = UClassDetail.get_member_info_by_path(current_script, access_path)
		if enum_data == null:
			return access_path
	
	for part in parts:
		var member_info = UClassDetail.get_member_info(current_script, part)
		var script_member = UClassDetail.script_get_member_by_value(current_script, enum_data, ["enum"])
		if script_member != null:
			access_path = script_member + access_path.get_slice(part, 1)
			access_path = access_path.trim_suffix(".")
	
	return access_path

func _get_access_path(_class_path): ## TEST NEEDS WORK REGARDING ACCESS NAME
	var current_script = EditorInterface.get_script_editor().get_current_script()
	if _class_path.begins_with("res://"):
		var path = _class_path.get_slice(".gd.", 0) + ".gd"
		var enum_script = load(path)
		var script_member = _class_path.get_slice(".gd.", 1)
		var _class_access_path = script_member
		#if script_member.find(".") > -1:
			#print("GETTING LAST MEMBER: ", script_member)
			#script_member = script_member.substr(script_member.rfind("."))
			#print(script_member)
		
		var enum_data = UClassDetail.get_member_info_by_path(enum_script, script_member, "enum")
		
		var enum_in_current_script = UClassDetail.script_get_member_by_value(current_script, enum_data, ["enum"], true)
		if enum_in_current_script != null:
			return enum_in_current_script
		
		var global_checks_enable = true # TODO implement?
		if  global_checks_enable:
			var global_check = _get_global_access_path(enum_data)
			if global_check != null:
				return global_check
				#print("Setting class to func call: %s -> %s" % [_class_path, _class])
		
		return _class_access_path
	else:
		return _class_path


func _get_global_access_path(enum_data):
	
	## GLOBAL
	var classes_to_check = []
	var namespace_enable = false # TODO implement?
	var namespace_builder_path = UClassDetail.get_global_class_path("NamespaceBuilder")
	if namespace_enable and namespace_builder_path != "":
		var namespace_builder = load(namespace_builder_path)
		classes_to_check = namespace_builder.get_namespace_classes()
	else:
		classes_to_check = UClassDetail.get_all_global_class_paths()
	
	for global_class_name in classes_to_check:
		var global_class_path = classes_to_check.get(global_class_name)
		var global_class_script = load(global_class_path)
		var member = UClassDetail.script_get_member_by_value(global_class_script, enum_data, ["enum"], true)
		if member != null:
			return global_class_name + "." + member
			
		print(enum_data)
		print("cHECK ",member)


func _get_property_enum_access_path(script:Script, member_name:String):
	var data = UClassDetail.get_member_info_by_path(script, member_name)#, "property")
	if data is not Dictionary:
		return
	if _is_data_enum(data):
		var _class = data.get("class_name")
		return _get_access_path(_class)

func _get_enum_members(_class_name:String):
	if _class_name.begins_with("res://"): #could convert to access path first but this works for quicker check
		var enum_full_nm = _class_name.get_slice(".gd.", 1)
		var script_path = _class_name.trim_suffix(enum_full_nm).trim_suffix(".")
		var enum_script = load(script_path)
		return UClassDetail.get_member_info_by_path(enum_script, enum_full_nm, "enum")
	else:
		var current_script = EditorInterface.get_script_editor().get_current_script()
		var member_info = UClassDetail.get_member_info_by_path(current_script, _class_name, "enum")
		if member_info != null:
			return member_info
		
		var first_class_name = _class_name
		var enum_name = _class_name
		if _class_name.find(".") > -1:
			first_class_name = _class_name.get_slice(".", 0)
			enum_name = _class_name.get_slice(".", 1)
		
		member_info = ClassDB.class_get_enum_constants(first_class_name, enum_name)
		return member_info

func _is_local_var_type_hint_enum(type_hint:String):
	if type_hint == "":
		return false
	var property_enum_data = _get_enum_members(type_hint)
	if property_enum_data == null:
		return false
	if not (property_enum_data is PackedStringArray or property_enum_data is Dictionary):
		return false
	if not property_enum_data.is_empty():
		return true
	return false

func _is_data_enum(data:Dictionary):
	var type = data.get("type", -1)
	if type == -1:
		return false
	type = type_string(type)
	var class_nm:String = data.get("class_name", "")
	if type == "int" and class_nm != "":
		return true
	return false
