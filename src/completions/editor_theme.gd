extends EditorCodeCompletion

var _enable:bool = true

func register_editor_settings(settings_helper:SettingHelperEditor):
	settings_helper.subscribe_property(self, &"_enable", EditorSet.ENABLE, true)


func _on_code_completion_requested(script_editor:CodeEdit) -> bool:
	if not _enable:
		return false
	var caret_context = get_caret_context()
	if not caret_context.is_in_function_call() or caret_context.token_state == TokenState.COMMENT:
		return false
	
	var in_string = caret_context.token_state == TokenState.STRING or caret_context.token_state == TokenState.STRING_NAME
	
	var func_call_data = caret_context.get_function_call_data()
	if func_call_data.current_arg_index > 0:
		return false
	var func_name = func_call_data.get_function_name()
	if not func_name in ["get_icon", "get_color"]:
		return false
	
	var append_editor_thm = true and not in_string
	if func_call_data.current_arguments.size() > 1:
		append_editor_thm = false
	
	var dec_symb = func_call_data.symbol_data.get_current_script_access_object().declaration_symbol
	if dec_symb != "EditorInterface":
		return false
	
	match func_name:
		"get_icon": _add_icons(script_editor, in_string, append_editor_thm)
		"get_color": _add_colors(script_editor, in_string, append_editor_thm)
	return true


func _add_icons(script_editor:CodeEdit, in_string:bool=false, append_thm_type:bool=false):
	var kind = CodeEdit.KIND_FILE_PATH if in_string else CodeEdit.KIND_VARIABLE
	var icons = editor_theme.get_icon_list(&"EditorIcons")
	icons.sort()
	for icon_name in icons:
		var insert = icon_name
		if not in_string:
			insert = '&"%s"' % icon_name
		if append_thm_type:
			insert += ', &"EditorIcons"'
		var icon = editor_theme.get_icon(icon_name, &"EditorIcons")
		script_editor.add_code_completion_option(kind, icon_name, insert, Helpers.Colors.DEFAULT_COMPLETION, icon)
	
	update_completion_options(true)

func _add_colors(script_editor:CodeEdit, in_string:bool=false, append_thm_type:bool=false):
	var kind = CodeEdit.KIND_FILE_PATH if in_string else CodeEdit.KIND_VARIABLE
	var colors = editor_theme.get_color_list(&"Editor")
	var icon = editor_theme.get_icon(&"Color", &"EditorIcons")
	
	colors.sort()
	for color_name in colors:
		var insert = color_name
		if not in_string:
			insert = '&"%s"' % color_name
		if append_thm_type:
			insert += ', &"Editor"'
		var color = editor_theme.get_color(color_name, "Editor")
		script_editor.add_code_completion_option(kind, color_name, insert, color, icon)
	
	update_completion_options(true)

class EditorSet:
	const ENABLE = &"plugin/code_completion/editor_theme/enable"
