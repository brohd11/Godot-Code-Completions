extends EditorCodeCompletion

const _HIDE_PRIVATE_PROP_SETTING = &"plugin/code_completion/member_access/hide_private_properties"

var _enable:bool = true

func _get_completion_settings() -> Dictionary:
	return {
		"priority": 1000,
	}

func register_editor_settings(settings_helper:SettingHelperEditor):
	settings_helper.subscribe_property(self, &"_enable", _HIDE_PRIVATE_PROP_SETTING, true)

func _on_code_completion_requested(script_editor:CodeEdit) -> bool:
	if not _enable:
		return false
	
	var caret_context = get_caret_context()
	if caret_context.expression_state != ExpressionState.MEMBER_ACCESS:
		return false
	
	var word_at_cursor = caret_context.expression_before_caret
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
