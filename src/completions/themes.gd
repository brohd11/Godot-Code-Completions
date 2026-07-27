extends EditorCodeCompletion


const CATEGORIES = ["color", "constant", "font", "font_size", "icon", "stylebox"]

var _enable:bool = true
var _prefer_string_name:bool = true


func register_editor_settings(settings_helper:SettingHelperEditor):
	settings_helper.subscribe_property(self, &"_enable", EditorSet.ENABLE, true)
	settings_helper.subscribe_property(self, &"_prefer_string_name", EditorSet.PREFER_STRING_NAME, true)


func _on_code_completion_requested(script_editor:CodeEdit) -> bool:
	if not _enable:
		return false
	var caret_context = get_caret_context()
	if caret_context.token_state == TokenState.COMMENT:
		return false
	if not caret_context.is_in_function_call():
		return false
	
	
	var func_data = caret_context.get_function_call_data()
	if not func_data.is_valid:
		return false
	
	var category = _get_theme_category(func_data.get_function_name())
	if category == "":
		return false
	if func_data.current_arg_index != 0: # only complete the 'name' argument
		return false
	
	var theme_type = _get_theme_type(func_data, caret_context)
	if theme_type == "":
		return false
	
	return _add_theme_item_completions(script_editor, caret_context, category, theme_type)


## Maps a Control theme accessor (`get_theme_color`) or Theme accessor (`set_color`)
## to its Theme item category, or "" if the function is not a theme accessor.
func _get_theme_category(func_name:String) -> String:
	for cat in CATEGORIES:
		if func_name in ["get_theme_" + cat, "has_theme_" + cat, "add_theme_" + cat + "_override",
				"remove_theme_" + cat + "_override", "set_" + cat, "get_" + cat, "has_" + cat, "clear_" + cat]:
			return cat
	return ""


## The class name the theme item list is keyed by: the receiver's class for Control
## accessors, the literal `theme_type` second argument for Theme accessors.
func _get_theme_type(func_data:CaretContext.FunctionCallData, caret_context:CaretContext) -> String:
	var func_name = func_data.get_function_name()
	if not func_name.contains("_theme_"): # Theme family
		if func_data.current_arguments.size() < 2:
			return ""
		var arg = func_data.current_arguments[1].strip_edges()
		if not UString.is_string_or_string_name(arg):
			return ""
		return UString.unquote(arg)
	
	# handle simple Class::my_func
	var func_origin = func_data.get_function_origin()
	if ClassDB.class_exists(func_origin):
		return func_origin
	elif func_origin.is_absolute_path():
		var type = GDScriptParser.Utils.type_path_get_type(func_origin)
		if ClassDB.class_exists(type):
			return type
	
	print("themes.gd::_get_theme_type - NGMI")
	return ""
	# Below should be redundant now...
	#
	#
	## Control family - resolve the receiver's instance type
	#if not func_data.expression.contains("."): # implicit self
		#return caret_context.get_current_class_object().script_base_type
	#
	#var chain = UString.trim_member_access_back(func_data.expression)
	#var resolved = caret_context.resolve_expression_to_type(chain)
	#var type_check = GDScriptParser.Utils.type_path_get_type(resolved, true)
	#if type_check != "":
		#resolved = type_check
	#resolved = resolved.trim_suffix(ParserKeys.INS_DELIM)
	#if GDScriptParser.Utils.is_absolute_path(resolved): # script class - theme types key on the native base
		#var parser_data = get_gdscript_parser().get_parser_and_class_obj_for_script(resolved)
		#if not parser_data or not is_instance_valid(parser_data.class_obj):
			#return ""
		#resolved = parser_data.class_obj.script_base_type
	#
	#if not (ClassDB.class_exists(resolved) and ClassDB.is_parent_class(resolved, "Control")):
		#return ""
	#return resolved


func _add_theme_item_completions(script_editor:CodeEdit, caret_context:CaretContext, category:String, theme_type:String) -> bool:
	var theme = ThemeDB.get_default_theme()
	if theme == null:
		return false
	
	var list_method = "get_" + category + "_list"
	var items = {}
	var type = theme_type
	while true: # direct lookup, then walk the Control ancestry (Button -> BaseButton -> Control)
		for item in theme.call(list_method, type):
			items[item] = true
		if not ClassDB.class_exists(type) or type == "Control" or not ClassDB.is_parent_class(type, "Control"):
			break
		type = ClassDB.get_parent_class(type)
	
	if items.is_empty():
		return false
	
	var in_string = caret_context.token_state == TokenState.STRING or caret_context.token_state == TokenState.STRING_NAME
	var use_string_name = _prefer_string_name and caret_context.token_state != TokenState.STRING
	
	var color = Helpers.Colors.DEFAULT_COMPLETION
	if not in_string:
		if use_string_name:
			color = EditorColors.get_syntax_color(EditorColors.SyntaxColor.STRING_NAME)
		else:
			color = EditorColors.get_syntax_color(EditorColors.SyntaxColor.STRING)
	
	for item in items.keys():
		var insert = item
		if not in_string:
			insert = UString.quote(item)
			if use_string_name:
				insert = "&" + insert
		
		var dict = get_code_complete_dict(CodeEdit.KIND_VARIABLE, insert, insert, "StringName", null, CodeEdit.LOCATION_LOCAL, color)
		add_completion_option(script_editor, dict)
	
	update_completion_options(true)
	return true


class EditorSet:
	const ENABLE = &"plugin/code_completion/theme/enable"
	const PREFER_STRING_NAME = &"plugin/code_completion/theme/prefer_string_name"
