@tool
extends EditorScript

## Exercises raw marker detection and CodeEdit's real filtering/replacement without a singleton.
const UnicodeCompletion = preload("res://addons/code_completions/src/completions/unicode_completion.gd")

static var _failures:Array[String] = []
static var _passed:int = 0


static func run_tests() -> Dictionary:
	_failures = []
	_passed = 0
	_test_detection()
	_test_matching()
	_test_catalog()
	_test_native_completion()
	_test_cancel()
	_test_long_string_query()
	if Engine.is_editor_hint():
		_test_provider()
	var output:Array[String] = ["unicode_completion: %d passed, %d failed" % [_passed, _failures.size()]]
	for failure in _failures:
		output.append("  FAIL  " + failure)
	return {"result": _failures.size(), "output": output}


func _run() -> void:
	print("\n".join(run_tests().output))


static func _editor(marked_text:String) -> CodeEdit:
	var editor = CodeEdit.new()
	editor.add_string_delimiter('"""', '"""')
	editor.add_string_delimiter("'''", "'''")
	editor.add_string_delimiter('"', '"')
	editor.add_string_delimiter("'", "'")
	editor.add_comment_delimiter("#", "", true)
	editor.auto_brace_completion_enabled = true
	var caret = marked_text.find("|")
	editor.text = marked_text.replace("|", "")
	var head = marked_text.left(caret)
	editor.set_caret_line(head.count("\n"))
	editor.set_caret_column(head.length() - head.rfind("\n") - 1)
	return editor


static func _test_detection() -> void:
	for text:String in [
		'var text = "\\u|"', 'var text = "label: \\u|"', "var text = '\\u|'",
		'var text = "\\u|', '# \\u|', '# label: \\u| suffix', '# \\uright|',
		'# \\u21|', 'var text = "first \\u2192 then \\u|"',
	]:
		var editor = _editor(text)
		_check(not UnicodeCompletion.get_request(editor).is_empty(), "detect " + text)
		editor.free()
	for text:String in [
		'var text = \\u|', 'var text = "u\\|"', '# u/|', '# \\|', '# \\U|',
		'var text = "\\\\u|"', '# \\\\u|', 'var text = "\\u2192|"', '# \\u00b0|',
		'var text = "\\uright |"', 'var text = "\\u| suffix"',
		'var text = r"\\u|"', 'var text = &"\\u|"', 'var text = ^"\\u|"',
		'var text = """\\u|"""', 'var text = """first\n\\u|"""',
		'var text = "\\u"|', '# \\u2192 done|',
	]:
		var editor = _editor(text)
		_check(UnicodeCompletion.get_request(editor).is_empty(), "ignore " + text)
		editor.free()
	var selected = _editor('# \\u|')
	selected.select(0, 2, 0, 4)
	_check(UnicodeCompletion.get_request(selected).is_empty(), "ignore selection")
	selected.deselect()
	selected.add_caret(0, 1)
	_check(UnicodeCompletion.get_request(selected).is_empty(), "ignore multiple carets")
	selected.free()


static func _test_matching() -> void:
	for query:String in ["right_arrow", "RIGHT_ARROW", "219", "00b", "infinity", "space"]:
		var editor = _editor('# \\u' + query + '|')
		var options = UnicodeCompletion.collect_options(editor)
		_check(not options.is_empty(), "matches " + query)
		editor.free()
	var editor = _editor('# \\unot_a_symbol|')
	_check(UnicodeCompletion.collect_options(editor).is_empty(), "unknown query has no options")
	editor.free()
	editor = _editor('var text = "label: \\urigh|"')
	var options = UnicodeCompletion.collect_options(editor)
	_check(options.size() == 2, "righ matches both right arrows")
	_check(options[0].insert_text == 'label: \\u2192', "string row carries prefix and one backslash")
	_check(options[0].display_text.contains("→") and options[0].display_text.contains("right_arrow"),
			"row previews character and name")
	editor.free()
	editor = _editor('# \\uright_arrow|')
	options = UnicodeCompletion.collect_options(editor)
	_check(options[0].insert_text == 'u2192', "comment row leaves backslash to native completion")
	editor.free()


static func _test_catalog() -> void:
	var editor = _editor('# \\u|')
	var options = UnicodeCompletion.collect_options(editor)
	_check(options.size() == UnicodeCompletion.SYMBOLS.size(), "bare marker offers the catalog")
	for option in options:
		var escape:String = option.insert_text
		_check(escape.length() == 5 and escape.begins_with("u") and escape.substr(1).is_valid_hex_number(),
				"four-digit escape " + escape)
	editor.free()


static func _test_native_completion() -> void:
	var cases = [
		['var text = "\\u|"', 'var text = "\\u2192"'],
		['var text = "label: \\u|"', 'var text = "label: \\u2192"'],
		["var text = 'label: \\u|'", "var text = 'label: \\u2192'"],
		['var text = "label: \\urigh|"', 'var text = "label: \\u2192"'],
		['var text = "label: \\uRIGH|"', 'var text = "label: \\u2192"'],
		['var text = "label: \\u219|"', 'var text = "label: \\u2192"'],
		['var text = "\\u|', 'var text = "\\u2192"'],
		['var text = "say \\"hi\\" \\u|"', 'var text = "say \\"hi\\" \\u2192"'],
		['# \\u|', '# \\u2192'],
		['# label: \\uright_arrow| suffix', '# label: \\u2192 suffix'],
		['# \\u219|', '# \\u2192'],
	]
	for entry:Array in cases:
		for replace:bool in [false, true]:
			var editor = _editor(entry[0])
			_submit_options(editor)
			var chosen = -1
			var options = editor.get_code_completion_options()
			for index in options.size():
				if options[index].display_text.contains("  right_arrow"):
					chosen = index
			_check(chosen != -1, "native filter retains right_arrow: " + entry[0])
			if chosen != -1:
				editor.set_code_completion_selected_index(chosen)
				editor.confirm_code_completion(replace)
				_check(editor.text == entry[1], "native accept (replace=%s): %s -> %s" % [replace, entry[0], editor.text])
				editor.undo()
				_check(editor.text == entry[0].replace("|", ""), "one undo restores the query")
				editor.redo()
				_check(editor.text == entry[1], "redo restores the escape")
			editor.free()


static func _test_cancel() -> void:
	for text:String in ['var text = "label: \\u|"', '# \\u|']:
		var editor = _editor(text)
		var original = editor.text
		var column = editor.get_caret_column()
		_submit_options(editor)
		editor.cancel_code_completion()
		_check(editor.text == original and editor.get_caret_column() == column, "cancel preserves text and caret")
		editor.free()


static func _test_long_string_query() -> void:
	var editor = _editor('var text = "\\urigh|"')
	_submit_options(editor)
	_check(not editor.get_code_completion_options().is_empty(), "four-character string query is offered")
	editor.insert_text_at_caret("t")
	_submit_options(editor)
	_check(editor.get_code_completion_options().is_empty(), "longer string query dismisses old options")
	_check(editor.text == 'var text = "\\uright"', "dismissal preserves the query")
	editor.free()


static func _test_provider() -> void:
	var provider = ProbeCompletion.new()
	provider._singleton_ready()
	_check(provider._enable, "provider enabled by default")
	for text:String in ['var text = "\\|"', '# \\|']:
		var editor = _editor(text)
		provider.code_edit = editor
		editor.text_changed.connect(provider._on_text_changed)
		editor.code_completion_requested.connect(provider._on_code_completion_requested.bind(editor))
		editor.insert_text_at_caret("u")
		_check(not UnicodeCompletion.get_request(editor).is_empty(), "provider marker recognized: " + text)
		editor.text_changed.emit()
		_check(editor.get_code_completion_options().size() == UnicodeCompletion.SYMBOLS.size(),
				"provider opens popup on text change: %s (rows=%d)" % [text, editor.get_code_completion_options().size()])
		editor.insert_text_at_caret("not_a_symbol")
		editor.text_changed.emit()
		_check(editor.get_code_completion_options().is_empty(), "provider clears unmatched options")
		editor.free()
	var editor = _editor('var text = "\\urigh|"')
	provider.code_edit = editor
	editor.code_completion_requested.connect(provider._on_code_completion_requested.bind(editor))
	provider._on_code_completion_requested(editor)
	_check(not editor.get_code_completion_options().is_empty(), "provider offers short string searches")
	editor.insert_text_at_caret("t")
	provider._on_text_changed()
	_check(editor.get_code_completion_options().is_empty(), "provider dismisses long string searches")
	editor.free()
	editor = _editor('# \\u219|')
	provider.code_edit = editor
	provider._on_code_completion_requested(editor)
	editor.insert_text_at_caret("2")
	provider._on_text_changed()
	_check(editor.get_code_completion_options().is_empty(), "provider closes popup for completed escapes")
	editor.free()
	editor = _editor('# \\u|')
	provider.code_edit = editor
	provider._on_code_completion_requested(editor)
	provider._enable = false
	provider._on_text_changed()
	_check(editor.get_code_completion_options().is_empty(), "disabled provider leaves popup closed")
	_check(not provider._on_code_completion_requested(editor), "disabled provider declines request")
	provider.clean_up()
	provider._singleton_ready()
	var editor_ref = ScriptEditorRef.get_instance()
	_check(not editor_ref.text_changed.is_connected(provider._on_text_changed), "cleanup disconnects even before ready callback")
	editor.free()


class ProbeCompletion extends UnicodeCompletion:
	var code_edit:CodeEdit

	func get_code_edit():
		return code_edit

	func update_completion_options(force:=false):
		code_edit.update_code_completion_options(force)


static func _submit_options(editor:CodeEdit) -> void:
	for option in UnicodeCompletion.collect_options(editor):
		editor.add_code_completion_option(CodeEdit.KIND_PLAIN_TEXT, option.display_text, option.insert_text)
	editor.update_code_completion_options(true)


static func _check(condition:bool, message:String) -> void:
	if condition:
		_passed += 1
	else:
		_failures.append(message)
