extends EditorCodeCompletion

func _get_completion_settings() -> Dictionary:
	return {
		"priority": 100,
	}

func _on_code_completion_requested(script_editor:CodeEdit) -> bool:
	
	var caret_context = get_caret_context()
	if caret_context.expression_state != ExpressionState.ASSIGNMENT:
		return false
	var op_data = caret_context.get_operation_data()
	if not op_data.is_valid or op_data.operator != "=":
		return false
	
	var type = op_data.left_symbol_data.type
	if not type.ends_with(GDScriptParser.Keys.Delim.INS):
		return false
	type = type.trim_suffix(GDScriptParser.Keys.Delim.INS)
	if type == "":
		return false
	
	var existing = script_editor.get_code_completion_options()
	if not type.is_absolute_path():
		add_completion_option(script_editor, get_code_complete_dict_static(
				CodeEdit.KIND_CLASS,
				type + ".new()",
				type + ".new()",
				type, Helpers.Colors.DEFAULT_COMPLETION, null,
				0
			))
	else:
		var parser = get_gdscript_parser()
		var has_args = Helpers.script_has_init_args(parser, type)
		var access_opt = op_data.get_type_access_path(type)
		if not access_opt.has_valid():
			return false
		
		var new_str = ".new(" if has_args else ".new()"
		var insert = access_opt.get_nearest() + new_str
		add_completion_option(script_editor, get_code_complete_dict_static(
				CodeEdit.KIND_CLASS,
				Helpers.complete_function_display(insert),
				insert,
				"Object", Helpers.Colors.DEFAULT_COMPLETION, null,
				0
			))
	
	var add_existing = true
	if add_existing:
		for o in existing:
			add_completion_option(script_editor, o)
	
	update_completion_options(true)
	return true
