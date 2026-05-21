extends EditorCodeCompletion

func _get_completion_settings() -> Dictionary:
	return {
		"priority": 1,
	}

func _on_code_completion_requested(script_editor:CodeEdit) -> bool:
	var caret_context = get_caret_context()
	if caret_context.token_state != CaretContext.TokenState.COMMENT:
		return false
	var tags = singleton.peristent_cache[singleton.PersistentCache.TAGS].keys()
	if tags.is_empty():
		return false
	
	var caret_col = caret_context.caret_column
	var current_line_text = caret_context.current_line_text
	
	var string_map = caret_context.get_string_map(current_line_text)
	var tag_present = ""
	var tag_idx = -1
	for tag in tags: # find tag in line
		tag_idx = UString.string_safe_rfind(current_line_text, tag, caret_col, string_map)
		if tag_idx > -1:
			tag_present = tag
			break
	if tag_idx == -1: # no tag found, abort
		return false
	
	var stripped = current_line_text.substr(tag_idx).strip_edges()
	var parts = stripped.split(" ", false)
	
	var word_before_caret = caret_context.word_before_caret
	# think this could be handled better?
	if parts.size() > 1:
		if parts.size() == 2 and word_before_caret == "":
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
		var cc_dict = get_code_complete_dict(CodeEdit.CodeCompletionKind.KIND_CLASS, tag, tag, Helpers.TAG_ICON_NAME)
		add_completion_option(script_editor, cc_dict)
		valid_tags.append(tag)
	
	var force = word_before_caret == ""
	if force: # can't seem to force completion when no word at caret, instead print valid tags
		var tag_string = ", ".join(valid_tags)
		print("Valid Tags: ", tag_string)
	
	update_completion_options(force)
	return true
