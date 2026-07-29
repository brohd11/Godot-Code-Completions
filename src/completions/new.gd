extends EditorCodeCompletion


const CALL_WITH_ARGS = "(…)"

var _enable:bool = true


func _get_completion_settings() -> Dictionary:
	return {
		"priority": 5, #^ must run before import completion (500) to preempt on "new"
	}


func register_editor_settings(settings_helper:SettingHelperEditor):
	settings_helper.subscribe_property(self, &"_enable", EditorSet.ENABLE, true)


func _on_code_completion_requested(script_editor:CodeEdit) -> bool:
	if not _enable:
		return false
	var caret_context = get_caret_context()
	if caret_context.token_state != TokenState.NONE:
		return false
	if caret_context.expression_state == ExpressionState.MEMBER_ACCESS:
		return false
	
	var word = caret_context.word_before_caret
	if not word.ends_with("new"):
		return false
	
	var options = {}
	var parser = get_gdscript_parser()
	
	#^ preloads / inner classes of the class at the caret line
	var class_obj = caret_context.get_current_class_object()
	if is_instance_valid(class_obj):
		var gdscript_constants = class_obj.get_gdscript_constants(true)
		for c in gdscript_constants.keys():
			var type = gdscript_constants[c]
			if type.ends_with(ParserKeys.ENUM_PATH_SUFFIX):
				continue
			_add_new_option(options, c, _script_has_init_args(parser, type), 0)
	
	#^ global user classes
	var global_classes = UClassDetail.get_all_global_class_paths()
	for name in global_classes.keys():
		if options.has(name):
			continue
		_add_new_option(options, name, _script_has_init_args(parser, global_classes[name]), 1024)
	
	#^ engine classes
	for name in ClassDB.get_class_list():
		if global_classes.has(name): #^ shadowed by a user class
			continue
		if not ClassDB.can_instantiate(name):
			continue
		_add_new_option(options, name, false, 2048, name)
	
	if options.is_empty():
		return false
	
	for o in options.values():
		add_completion_option(script_editor, o)
	
	update_completion_options(true)
	return true


func _script_has_init_args(parser, type_path:String) -> bool:
	var parser_data = parser.get_parser_and_class_obj_for_script(type_path)
	if not parser_data or not is_instance_valid(parser_data.class_obj):
		return false
	var init_func = parser_data.class_obj.get_function("_init")
	if not is_instance_valid(init_func):
		return false
	return not init_func.get_arguments().is_empty()


func _add_new_option(options:Dictionary, name:String, has_args:bool, location:int, icon_name:="Object"):
	var display = name + ".new()"
	var insert = display
	if has_args:
		display = name + ".new" + CALL_WITH_ARGS
		insert = name + ".new("
	options[name] = get_code_complete_dict(CodeEdit.CodeCompletionKind.KIND_FUNCTION, display, insert, icon_name, null, location)


class EditorSet:
	const ENABLE = &"plugin/code_completion/new/enable"
