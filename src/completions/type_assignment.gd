extends EditorCodeCompletion


#! import-p UClassDetail,
const UFile = preload("res://addons/addon_lib/brohd/alib_runtime/utils/u_file.gd")

func _get_completion_settings() -> Dictionary:
	return {
		"priority": 10,
	}

func _on_editor_script_changed(script):
	pass



func _on_code_completion_requested(script_editor:CodeEdit) -> bool:
	var caret_context = get_caret_context()
	if caret_context.token_state == TokenState.COMMENT:
		return false
	if not caret_context.expression_state == CaretContext.ExpressionState.TYPE_HINT:
		return false
	if caret_context.is_in_dictionary():
		return false
	
	# import data grabbed from import_code_completion
	var import_data = get_data("import_data")
	var hide_global_classes = import_data.get("hide_global_classes_setting", false)
	var show_global_classes = import_data.get("show_global_classes", {})
	#var imported_classes = import_data.get("imported_classes")
	var global_classes = import_data.get("global_classes", {})
	
	var type_hint_text = caret_context.get_type_hint_text()
	
	
	var current_script = get_current_script()
	var class_script = current_script
	if type_hint_text.find(".") > -1: # find the script of the 
		var class_check = type_hint_text.substr(0, type_hint_text.rfind("."))
		var nested_class_script = get_script_member_info_by_path(current_script, class_check, ["const"])
		if nested_class_script is GDScript:
			class_script = nested_class_script
		else:
			return false
	
	var class_obj = caret_context.get_current_class_object()
	var options:Dictionary
	if class_script == current_script:
		#return false # in 4.6 this is still necessary for "as"
		var t = ALibRuntime.Utils.UProfile.TimeFunction.new("TYPE::TIME")
		options = _get_current_class_completion_options(class_obj)
		t.stop()
	else:
		options = _get_valid_constants_from_script(class_script)
	
	for o in options.values():
		add_completion_option(script_editor, o)
	
	if class_script == current_script: #^ this will stop nested classes from displaying full class list
		var existing = script_editor.get_code_completion_options()
		for o in existing:
			var display = o.display_text
			if hide_global_classes:
				if global_classes.has(display) and not show_global_classes.has(display):
					continue
			if not options.has(display):
				add_completion_option(script_editor, o)
	
	update_completion_options()
	return true


func _get_valid_constants_from_script(script:GDScript):
	var options = {}
	var constants = UClassDetail.script_get_all_constants(script, UClassDetail.IncludeInheritance.SCRIPTS_ONLY)
	for c in constants:
		var val = constants.get(c)
		var add = false
		var is_enum = false
		if val is GDScript:
			add = true
		elif val is Dictionary and UClassDetail.check_dict_is_enum(val):
			is_enum = true
			add = true
		if add:
			_add_dict_entry(options, c, is_enum)
	
	var script_type = script.get_instance_base_type()
	var enums = ClassDB.class_get_enum_list(script_type)
	for e in enums:
		_add_dict_entry(options, e, true)
	
	return options



func _get_current_class_completion_options(class_obj:GDScriptParser.ParserClass):
	var options = {}
	var class_script = class_obj.script_resource
	if not is_instance_valid(class_script):
		return options
	
	var parser = get_gdscript_parser()
	
	for c in class_obj.constants.keys():
		var data = class_obj.constants.get(c)
		var member_type = data.get(GDScriptParser.Keys.MEMBER_TYPE)
		if member_type == GDScriptParser.Keys.MEMBER_TYPE_ENUM:
			_add_dict_entry(options, c, true)
		else:
			var type = parser.resolve_expression(c)
			if type.ends_with(GDScriptParser.Keys.ENUM_PATH_SUFFIX):
				_add_dict_entry(options, c, true)
			elif type.begins_with("res://"):
				_add_dict_entry(options, c, false)
	
	for ic in class_obj.inner_classes.keys():
		_add_dict_entry(options, ic)
	
	var class_base_script = class_script.get_base_script()
	if class_base_script != null: # getting the inherited via UClassDetail, this could probably be switched to parser now
		options.merge(_get_valid_constants_from_script(class_base_script))
	
	return options



func _add_dict_entry(options_dict:Dictionary, name:String, is_enum:bool=false):
	var icon_name = "Object"
	var type = CodeEdit.CodeCompletionKind.KIND_CLASS
	var location = 0
	if is_enum:
		icon_name = "enum"
		type = CodeEdit.CodeCompletionKind.KIND_ENUM
		location = 1024
	options_dict[name] = get_code_complete_dict(type, name, name, icon_name, null, location)
