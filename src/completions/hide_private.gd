extends EditorCodeCompletion

func _get_completion_settings() -> Dictionary:
	return {
		"priority": 1000,
	}

func _on_code_completion_requested(script_editor:CodeEdit) -> bool:
	var current_state = get_state()
	if current_state != State.MEMBER_ACCESS: # only hide when accessing a member, want to see private in own class
		return false
	
	var hide_private_members = singleton.hide_private_members
	if hide_private_members == false:
		return false
	
	var word_at_cursor = get_word_before_caret()
	var last_part = UString.get_member_access_back(word_at_cursor)
	if last_part.begins_with("_"):
		return false
	
	var options = script_editor.get_code_completion_options()
	for option in options:
		var display_text = option.get("display_text")
		if display_text.begins_with("_"):
			continue
		add_completion_option(script_editor, option)
	
	update_completion_options()
	return true
