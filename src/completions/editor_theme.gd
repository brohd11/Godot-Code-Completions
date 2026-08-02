extends EditorCodeCompletion

const UTexture = UtilsRemote.UTexture

var _enable:bool = true
var _type_variation_enable:bool = true

var _color_icon_cache:= {}

func register_editor_settings(settings_helper:SettingHelperEditor):
	settings_helper.subscribe_property(self, &"_enable", EditorSet.ENABLE, true)
	settings_helper.subscribe_property(self, &"_type_variation_enable", EditorSet.TYPE_VARIATION_ENABLE, true)


func _on_code_completion_requested(script_editor:CodeEdit) -> bool:
	if not _enable:
		return false
	var caret_context = get_caret_context()
	if caret_context.token_state == TokenState.COMMENT:
		return false
	
	var in_string = caret_context.token_state == TokenState.STRING or caret_context.token_state == TokenState.STRING_NAME
	
	if _type_variation_enable and caret_context.expression_state == ExpressionState.ASSIGNMENT:
		if _add_type_variations(script_editor, caret_context, caret_context.token_state):
			return true
	
	if not caret_context.is_in_function_call():
		return false
	
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
		"get_icon": _add_icons(script_editor, caret_context.token_state, append_editor_thm)
		"get_color": _add_colors(script_editor, caret_context.token_state, append_editor_thm)
	return true


func _add_icons(script_editor:CodeEdit, in_string:=TokenState.NONE, append_thm_type:bool=false):
	var kind = CodeEdit.KIND_FILE_PATH if in_string else CodeEdit.KIND_VARIABLE
	var icons = editor_theme.get_icon_list(&"EditorIcons")
	var comp_color = _get_string_color(in_string)
	icons.sort()
	for icon_name in icons:
		var ins_disp = _get_display_and_insert(icon_name, in_string, "EditorIcons" if append_thm_type else "")

		var icon = editor_theme.get_icon(icon_name, &"EditorIcons")
		script_editor.add_code_completion_option(kind, ins_disp[0], ins_disp[1], comp_color, icon)
	
	update_completion_options(true)

func _add_colors(script_editor:CodeEdit, in_string:=TokenState.NONE, append_thm_type:bool=false):
	var kind = CodeEdit.KIND_FILE_PATH if in_string else CodeEdit.KIND_VARIABLE
	var colors = editor_theme.get_color_list(&"Editor")
	var comp_color = _get_string_color(in_string)
	
	colors.sort()
	for color_name in colors:
		var ins_disp = _get_display_and_insert(color_name, in_string, "Editor" if append_thm_type else "")
		var color = editor_theme.get_color(color_name, "Editor")
		var sq = _color_icon_cache.get(color)
		if sq == null:
			sq = UTexture.create_rect_texture(color, int(16 * EditorInterface.get_editor_scale()))
		script_editor.add_code_completion_option(kind, ins_disp[0], ins_disp[1], comp_color, sq)
	
	update_completion_options(true)

## Offers editor theme type variations on `theme_type_variation = |` assignments. The instance
## type comes from the receiver expression, or this script's own base type for the bare property.
func _add_type_variations(script_editor:CodeEdit, caret_context:CaretContext, in_string:=TokenState.NONE) -> bool:
	var op_data = caret_context.get_operation_data()
	if not op_data.is_valid:
		return false
	var left = op_data.left_text.strip_edges()
	if left != "theme_type_variation" and not left.ends_with(".theme_type_variation"):
		return false
	
	var base_type = ""
	if left == "theme_type_variation": # implicit self
		base_type = op_data.class_obj.script_base_type
	else:
		var receiver = left.trim_suffix(".theme_type_variation")
		var resolved = caret_context.resolve_expression_to_type(receiver)
		var type_check = GDScriptParser.Utils.type_path_get_type(resolved, true)
		if type_check != "":
			resolved = type_check
		resolved = resolved.trim_suffix(ParserKeys.INS_DELIM)
		if GDScriptParser.Utils.is_absolute_path(resolved): # script class - theme types key on the native base
			var parser_data = get_gdscript_parser().get_parser_and_class_obj_for_script(resolved)
			if not parser_data or not is_instance_valid(parser_data.class_obj):
				return false
			resolved = parser_data.class_obj.script_base_type
		base_type = resolved
	
	if not (ClassDB.class_exists(base_type) and ClassDB.is_parent_class(base_type, "Control")):
		return false
	
	var variations = {}
	var type = base_type
	while true: # direct lookup, then walk the Control ancestry (Button -> BaseButton -> Control)
		for variation in editor_theme.get_type_variation_list(type):
			variations[variation] = true
		if type == "Control":
			break
		type = ClassDB.get_parent_class(type)
	
	if variations.is_empty():
		return false
	
	var comp_color = _get_string_color(in_string)
	var comp_icon = EditorInterface.get_editor_theme().get_icon(base_type, &"EditorIcons")
	var names = variations.keys()
	names.sort()
	for variation_name in names:
		var disp_ins = _get_display_and_insert(variation_name, in_string)
		script_editor.add_code_completion_option(CodeEdit.KIND_VARIABLE, disp_ins[0], disp_ins[1], comp_color, comp_icon)
	
	update_completion_options(true)
	return true

func _get_display_and_insert(insert, in_string:=TokenState.NONE, theme_type:String=""):
	var display = insert
	var new_insert = insert
	var string_name = in_string != TokenState.STRING
	if in_string:
		return [display, insert]
	if theme_type != "":
		new_insert = '"%s", &"%s"' % [insert, theme_type]
		if string_name:
			new_insert = "&" + new_insert
		display = new_insert
	else:
		new_insert = '"%s"' % insert
		if string_name:
			new_insert = "&" + new_insert
		display = new_insert
	return [display, new_insert]

func _get_string_color(string:TokenState):
	if string == TokenState.STRING:
		return EditorColors.get_syntax_color(EditorColors.SyntaxColor.STRING)
	else:
		return EditorColors.get_syntax_color(EditorColors.SyntaxColor.STRING_NAME)


class EditorSet:
	const ENABLE = &"plugin/code_completion/editor_theme/enable"
	const TYPE_VARIATION_ENABLE = &"plugin/code_completion/editor_theme/theme_type_variation_enable"
