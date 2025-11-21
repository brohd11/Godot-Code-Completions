extends EditorCodeCompletion

func _get_completion_settings() -> Dictionary:
	return {
		"priority": 1,
	}

func _on_editor_script_changed(script):
	pass


func _on_code_completion_requested(script_editor:CodeEdit) -> bool:
	var current_state = get_state()
	if current_state != State.COMMENT:
		return false
	
	var current_line = script_editor.get_caret_line()
	var caret_col = script_editor.get_caret_column()
	var current_line_text = script_editor.get_line(current_line)
	var tags = singleton.peristent_cache[singleton.PersistentCache.TAGS].keys()
	if tags.is_empty():
		return false
	
	var string_map = get_string_map(current_line_text)
	var tag_present = ""
	var tag_idx = -1
	for tag in tags:
		tag_idx = UString.string_safe_rfind(current_line_text, tag, caret_col, string_map.string_mask)
		if tag_idx > -1:
			tag_present = tag
			break
	if tag_idx == -1:
		return false
	
	var stripped = current_line_text.substr(tag_idx).strip_edges()
	var parts = stripped.split(" ", false)
	
	if parts.size() > 1:
		if parts.size() == 2 and get_word_before_caret() == "":
			return false
		if parts.size() > 2:
			return false
	var valid_tags = []
	
	var declared_tag_members = singleton.peristent_cache[singleton.PersistentCache.TAGS].get(tag_present, {})
	for tag in declared_tag_members.keys():
		var location = declared_tag_members[tag]
		if location == TagLocation.START and tag_idx > 0:
			continue
		elif location == TagLocation.END and tag_idx == 0:
			continue
		var cc_dict = get_code_complete_dict(CodeEdit.CodeCompletionKind.KIND_CLASS, tag, tag, "BoneMapperHandleCircle")
		add_completion_option(script_editor, cc_dict)
		valid_tags.append(tag)
	
	var force = get_word_before_caret() == ""
	if force:
		var tag_string = ", ".join(valid_tags)
		print("Valid Tags: ", tag_string)
	
	update_completion_options(force)
	return true
