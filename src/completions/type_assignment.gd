extends EditorCodeCompletion


#! import_p UClassDetail,
const UFile = preload("res://addons/addon_lib/brohd/alib_runtime/utils/u_file.gd")
const Import = preload("res://addons/code_completions/src/completions/import_code_completion.gd")

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
	var import_data = get_data("import_data") as Import.ImportData
	if import_data == null:
		import_data = Import.ImportData.new()
		import_data = {}
	var hide_global_classes = false
	var visible_global_classes = {}
	#var imported_classes = import_data.get("imported_classes")
	var global_classes = {}
	if is_instance_valid(import_data):
		hide_global_classes = import_data.hide_global_classes
		visible_global_classes = import_data.visible_global_classes
		global_classes = import_data.global_classes
		
	
	var class_obj:GDScriptParser.ParserClass
	var type_hint_text = caret_context.get_type_hint_text()
	if not type_hint_text.contains("."):
		type_hint_text = ""
		class_obj = caret_context.get_current_class_object()
	else:
		type_hint_text = UString.trim_member_access_back(type_hint_text)
		var type_hint_resolved = caret_context.resolve_expression_to_type(type_hint_text)
		if not GDScriptParser.Utils.is_absolute_path(type_hint_resolved):
			return false
		
		var parser = get_gdscript_parser()
		var target_parser = parser.get_parser_and_class_obj_for_script(type_hint_resolved)
		if not target_parser:
			return false
		class_obj = target_parser.class_obj

	if not is_instance_valid(class_obj):
		return false
	var options:Dictionary = _get_class_obj_completion_options(class_obj)
	for o in options.values():
		add_completion_option(script_editor, o)
	#^ adds the global types to the list, stops already loaded from being double listed
	if type_hint_text == "":
		var existing = script_editor.get_code_completion_options()
		for o in existing:
			var display = o.display_text
			if hide_global_classes:
				if global_classes.has(display) and not visible_global_classes.has(display):
					continue
			if not options.has(display):
				add_completion_option(script_editor, o)
	
	update_completion_options()
	return true


func _get_class_obj_completion_options(class_obj:GDScriptParser.ParserClass):
	var options = {}
	var class_script = class_obj.script_resource
	#if not is_instance_valid(class_script):
		#return options
	
	var parser = get_gdscript_parser()
	var gdscript_constants = class_obj.get_gdscript_constants(true)
	for c in gdscript_constants.keys():
		var type = gdscript_constants[c]
		var icon_name = ""
		if type.ends_with(ParserKeys.ENUM_PATH_SUFFIX):
			icon_name = "enum"
		else:
			if type.is_absolute_path():
				var new_parser = parser.get_parser_and_class_obj_for_script(type)
				icon_name = new_parser.class_obj.script_base_type
		
		_add_dict_entry(options, c, icon_name)
	
	return options


func _add_dict_entry(options_dict:Dictionary, name:String, icon_name:String):
	var type = CodeEdit.CodeCompletionKind.KIND_CLASS
	var location = 0
	if icon_name == "enum":
		#icon_name = "enum"
		type = CodeEdit.CodeCompletionKind.KIND_ENUM
		location = 1024
	options_dict[name] = get_code_complete_dict(type, name, name, icon_name, null, location)
