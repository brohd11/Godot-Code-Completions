extends EditorCodeCompletion

#! import-p UClassDetail,


func _get_completion_settings() -> Dictionary:
	return {
		"priority": 100,
	}

func _on_editor_script_changed(script):
	pass


func _on_code_completion_requested(script_editor:CodeEdit) -> bool:
	var state = get_state()
	if state != State.STRING:
		return false
	
	
	var line = script_editor.get_line(script_editor.get_caret_line())
	var stripped = line.strip_edges()
	if stripped.begins_with("const"):
		var const_data = UString.get_const_name_and_type_in_line(stripped)
		if const_data == null:
			return false
		var const_name = const_data[0] as String
		var upper = const_name.to_upper()
		var snake_case = const_name.to_snake_case()
		for case in [upper, snake_case]:
			var option = get_code_complete_dict(CodeEdit.CodeCompletionKind.KIND_PLAIN_TEXT, case, case, "const")
			add_completion_option(script_editor, option)
		return true
	
	return false
