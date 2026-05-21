extends EditorCodeCompletion

#! import_p UClassDetail,

const CONST_STRING_ENABLE = &"plugin/code_completion/const_string/enable"

const Utils = GDScriptParser.Utils

const TOKEN_STATES = [
	CaretContext.TokenState.STRING,
	CaretContext.TokenState.STRING_NAME,
]

var _enable:bool = true

func _get_completion_settings() -> Dictionary:
	return {
		"priority": 100,
	}

func register_editor_settings(settings_helper:SettingHelperEditor):
	settings_helper.subscribe_property(self, &"_enable", CONST_STRING_ENABLE, false)


func _on_code_completion_requested(script_editor:CodeEdit) -> bool:
	if not _enable:
		return false
	var caret_context = get_caret_context()
	if not caret_context.token_state in TOKEN_STATES:
		return false
	if caret_context.line_declaration != &"const":
		return false
	
	var stripped = caret_context.current_line_text.strip_edges()
	var const_data = Utils.get_var_or_const_info(stripped)
	if const_data == null:
		return false
	var const_name = const_data[0] as String
	var to_convert = [const_name]
	var access_name = caret_context.current_class
	
	var script:GDScript = get_current_script()
	var script_name = script.get_global_name()
	if script_name == "":
		script_name = script.resource_path.get_file().get_basename().to_pascal_case()
	
	if access_name != "":
		var full_access = access_name.path_join(const_name)
		var full_script = script_name.path_join(full_access)
		full_access = full_access.replace("/", ".")
		full_script = full_script.replace("/", ".")
		to_convert.append(full_access)
		to_convert.append(full_script)
	else:
		var full_script = script_name.path_join(const_name)
		full_script = full_script.replace("/", ".")
		to_convert.append(full_script)
	
	var options_to_add = []
	for path:String in to_convert:
		var snake = path.to_snake_case()
		options_to_add.append(snake)
		options_to_add.append(snake.to_upper())
		#options_to_add.append(path)
		
		#options_to_add.append(path.to_pascal_case())
		#options_to_add.append(path.to_camel_case())
		#options_to_add.append(path.to_kebab_case())
	
	
	for case in options_to_add:
		var location = CodeEdit.LOCATION_LOCAL
		if case.contains("."):
			location = CodeEdit.LOCATION_OTHER_USER_CODE
		
		var option = get_code_complete_dict(CodeEdit.CodeCompletionKind.KIND_PLAIN_TEXT, case, case, "const", null, location)
		add_completion_option(script_editor, option)
	
	update_completion_options()
	return true
