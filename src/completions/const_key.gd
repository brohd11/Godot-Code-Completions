extends EditorCodeCompletion

#! import-p UClassDetail,


func _get_completion_settings() -> Dictionary:
	return {
		"priority": 100,
	}

func _on_editor_script_changed(_script):
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
		var to_convert = [const_name]
		var access_name = get_current_class()
		
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
		return true
	
	return false
