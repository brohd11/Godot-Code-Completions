extends EditorCodeCompletion

#! import-p UClassDetail,
const UFile = ALibRuntime.Utils.UFile

func _get_completion_settings() -> Dictionary:
	return {
		"priority": 10,
	}

func _on_editor_script_changed(script):
	pass


func _on_code_completion_requested(script_editor:CodeEdit) -> bool:
	if not get_state() == State.TYPE_ASSIGNMENT:
		return false
	if is_caret_in_dict():
		return false
	
	var import_data = get_data("import_data")
	var hide_global_classes = import_data.get("hide_global_classes_setting", false)
	var show_global_classes = import_data.get("show_global_classes", {})
	#var imported_classes = import_data.get("imported_classes")
	var global_classes = import_data.get("global_classes", {})
	
	var type_string = singleton.completion_cache.get(singleton.CompletionCache.TYPE_ASSIGNMENT)
	
	var current_script = get_current_script()
	var class_script = current_script
	if type_string.find(".") > -1:
		var class_check = type_string.substr(0, type_string.rfind("."))
		var nested_class_script = get_script_member_info_by_path(current_script, class_check, ["const"])
		if nested_class_script is GDScript:
			class_script = nested_class_script
		else:
			return false
	
	var options:Dictionary
	if class_script == current_script:
		options = _get_all_current_script_options()
	else:
		options = _get_gdscript_constants(class_script)
	
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


func _get_gdscript_constants(script):
	var options = {}
	var constants = UClassDetail.script_get_all_constants(script, UClassDetail.IncludeInheritance.SCRIPTS_ONLY)
	for c in constants:
		var val = constants.get(c)
		var add = false
		var icon_name = "Object"
		var type = CodeEdit.CodeCompletionKind.KIND_CLASS
		if val is GDScript:
			add = true
		if val is Dictionary and UClassDetail.check_dict_is_enum(val):
			add = true
			icon_name = "enum"
			type = CodeEdit.CodeCompletionKind.KIND_ENUM
		if add:
			options[c] = get_code_complete_dict(type, c, c, icon_name, null, 0)
	return options

func _get_all_current_script_options():
	var options = _get_current_script_constants()
	var current_script = get_current_script()
	var base_script = current_script.get_base_script()
	if base_script:
		var base_options = _get_gdscript_constants(base_script)
		options.merge(base_options)
	return options

func _get_current_script_constants():
	var current_script = get_current_script()
	var options = {}
	var constants = get_script_constants(get_current_class())
	for c in constants:
		var add = false
		var icon_name = "Object"
		var type = CodeEdit.CodeCompletionKind.KIND_CLASS
		var data = constants.get(c)
		var var_type = data.get(singleton.GDScriptParser._Keys.TYPE)
		if UFile.file_exists(var_type, current_script):
			var script = load(var_type)
			if script is GDScript:
				add = true
		else:
			var member_info = UClassDetail.get_member_info_by_path(current_script, var_type)
			if member_info is GDScript:
				add = true
			if member_info is Dictionary and UClassDetail.check_dict_is_enum(member_info):
				add = true
				icon_name = "enum"
				type = CodeEdit.CodeCompletionKind.KIND_ENUM
		if add:
			options[c] = get_code_complete_dict(type, c, c, icon_name, null, 0)
	return options
