extends EditorCodeCompletion

const ENABLE_SETTING = &"plugin/code_completion/unicode/enable"
const MARKER = "\\u"
const SYMBOLS = {
	0x2190: "left_arrow",
	0x2192: "right_arrow",
	0x2191: "up_arrow",
	0x2193: "down_arrow",
	0x2194: "left_right_arrow",
	0x2195: "up_down_arrow",
	0x2022: "bullet",
	0x2026: "ellipsis",
	0x2013: "en_dash",
	0x2014: "em_dash",
	0x2713: "checkmark",
	0x2717: "cross",
	0x00B0: "degree",
	0x00D7: "multiplication",
	0x00F7: "division",
	0x00B1: "plus_minus",
	0x2260: "not_equal",
	0x2264: "less_than_or_equal",
	0x2265: "greater_than_or_equal",
	0x221E: "infinity",
	0x00A0: "nonbreaking_space",
}

var _enable:bool = true
var _active_code_edit:CodeEdit
var _cleaned_up:bool = false


func _get_completion_settings() -> Dictionary:
	return {"priority": 0}


func register_editor_settings(settings_helper:SettingHelperEditor):
	settings_helper.subscribe_property(self, &"_enable", ENABLE_SETTING, true)


func _singleton_ready() -> void:
	if not _cleaned_up:
		ScriptEditorRef.subscribe(ScriptEditorRef.Event.TEXT_CHANGED, _on_text_changed)


func clean_up() -> void:
	_cleaned_up = true
	_clear_completion()
	var editor_ref = ScriptEditorRef.get_instance()
	if is_instance_valid(editor_ref) and editor_ref.text_changed.is_connected(_on_text_changed):
		editor_ref.text_changed.disconnect(_on_text_changed)
	super.clean_up()


func _on_text_changed() -> void:
	if not _enable:
		_clear_completion()
		return
	var code_edit = get_code_edit()
	if not is_instance_valid(code_edit) or get_request(code_edit).is_empty():
		_clear_completion()
		return
	code_edit.code_completion_requested.emit()


func _on_editor_script_changed(_script) -> void:
	_clear_completion()


func _clear_completion() -> void:
	if is_instance_valid(_active_code_edit):
		_active_code_edit.cancel_code_completion()
	_active_code_edit = null


func _on_code_completion_requested(script_editor:CodeEdit) -> bool:
	_active_code_edit = null
	if not _enable:
		return false
	if get_request(script_editor).is_empty():
		return false
	var options = collect_options(script_editor)
	for option in options:
		var completion = get_code_complete_dict(CodeEdit.KIND_PLAIN_TEXT,
				option.display_text, option.insert_text, "String")
		add_completion_option(script_editor, completion)
	update_completion_options(true)
	if not options.is_empty():
		_active_code_edit = script_editor
	return true


## Read the raw line: in comments CodeEdit's completion word starts after the backslash.
static func get_request(code_edit:CodeEdit) -> Dictionary:
	if code_edit.get_caret_count() != 1 or code_edit.has_selection():
		return {}
	var line_index = code_edit.get_caret_line()
	var column = code_edit.get_caret_column()
	var line = code_edit.get_line(line_index)
	var head = line.left(column)
	var marker_index = head.rfind(MARKER)
	if marker_index == -1:
		return {}
	var slash_start = marker_index
	while slash_start > 0 and head[slash_start - 1] == "\\":
		slash_start -= 1
	if (marker_index - slash_start) % 2 != 0:
		return {}
	var query = head.substr(marker_index + MARKER.length())
	if query.length() == 4 and query.is_valid_hex_number():
		return {}
	for character in query:
		if not character.to_lower() in "abcdefghijklmnopqrstuvwxyz0123456789_":
			return {}

	if code_edit.is_in_comment(line_index, column) != -1:
		return {"prefix": "", "marker": "u", "query": query}
	var delimiter = code_edit.is_in_string(line_index, column)
	if delimiter == -1:
		return {}
	var quote = code_edit.get_delimiter_start_key(delimiter)
	if quote != "\"" and quote != "'":
		return {}
	var start = code_edit.get_delimiter_start_position(line_index, column)
	if int(start.y) != line_index or marker_index < int(start.x):
		return {}
	var quote_index = int(start.x) - 1
	if quote_index > 0 and line[quote_index - 1] in "rR&^":
		return {}
	# Native string completion replaces from the opening quote and supplies a closing quote.
	if column < line.length() and line[column] != quote:
		return {}
	return {"prefix": line.substr(int(start.x), marker_index - int(start.x)),
			"marker": MARKER, "query": query}


static func collect_options(code_edit:CodeEdit) -> Array[Dictionary]:
	var options:Array[Dictionary] = []
	var request = get_request(code_edit)
	if request.is_empty():
		return options
	var query:String = request.query.to_lower()
	# Shorter replacements can duplicate the closing quote in native merge mode.
	if request.marker == MARKER and query.length() > 4:
		return options
	for codepoint:int in SYMBOLS:
		var hex_code = "%04X" % codepoint
		var symbol_name:String = SYMBOLS[codepoint]
		if not query.is_empty() and not hex_code.to_lower().begins_with(query) and not symbol_name.contains(query):
			continue
		var insert:String = request.prefix + request.marker + hex_code
		options.append({"display_text": "%s  %s  %s" % [insert, String.chr(codepoint), symbol_name],
				"insert_text": insert})
	return options
