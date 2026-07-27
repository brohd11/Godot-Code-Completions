extends EditorCodeCompletion

const YAMLParser = UtilsRemote.YAMLParser

const ALIAS_PATH = "res://.addons/code_completions/aliases.yml"
const DISPLAY_MAX = 60
const ELLIPSIS = "…"
const PLACEHOLDER_TOKEN = "%s"
const PLACEHOLDER = "placeholder"
const BLANK_ARG = "_" # a lone underscore asks for an empty substitution
const ARG_SEPARATOR = "/" # the parser counts '/' as an identifier char, so it survives to us intact

var _enable:bool = true

var _aliases:= {}
var _last_modified:int = 0

func _get_completion_settings() -> Dictionary:
	return {
		"priority": 2, # tag_completion(1) is comment only, everything else runs after
	}

func register_editor_settings(settings_helper:SettingHelperEditor):
	settings_helper.subscribe_property(self, &"_enable", EditorSet.ENABLE, true)

func _on_text_changed():
	if not _enable:
		return
	var code_edit = get_code_edit()
	var col = code_edit.get_caret_column()
	var text = code_edit.get_line(code_edit.get_caret_line())
	if text.length() > 0 and text[col - 1] == "/":
		code_edit.code_completion_requested.emit()

func _singleton_ready() -> void:
	_reload_if_changed()
	ScriptEditorRef.subscribe(ScriptEditorRef.Event.TEXT_CHANGED, _on_text_changed)

## The singleton's _prep_script fires this on both filesystem_changed and script change. The
## hidden .addons dir isn't scanned, so an external edit lands on the next scan for any reason.
func _on_editor_script_changed(_script) -> void:
	_reload_if_changed()

func _on_code_completion_requested(script_editor:CodeEdit) -> bool:
	if not _enable or _aliases.is_empty():
		return false
	var caret_context = get_caret_context()
	if caret_context.token_state != TokenState.NONE:
		return false
	if caret_context.expression_state == ExpressionState.MEMBER_ACCESS:
		return false

	var expression = caret_context.expression_before_caret
	if expression == "":
		return false
	
	#forloop
	
	var indent = get_line_indent(caret_context.current_line_text)
	var matched = false
	for key:String in _aliases:
		if not expression.begins_with(key):
			continue
		var text:String = _aliases[key]
		var typed = expression.substr(key.length())
		var display_arg = "" # plain aliases have no argument, so they stay a bare "(key)"
		var expects = 0
		if text.contains(PLACEHOLDER_TOKEN):
			var args = split_args(typed)
			# only nag when they're clearly going positional and came up short - a template whose
			# slots all want the same string is complete with one argument
			if typed.contains(ARG_SEPARATOR) and args.size() < placeholder_count(text):
				expects = placeholder_count(text)
			text = substitute(text, args)
			# the display carries what was TYPED, separators and all: Godot subsequence matches the
			# typed run against it, so dropping them would filter the option out of the popup
			display_arg = typed if typed != "" else PLACEHOLDER
		elif typed != "": # plain alias, the trailing text isn't ours - leave it to the chain
			continue

		var cc_dict = get_code_complete_dict(CodeEdit.KIND_PLAIN_TEXT, make_display(key, text, display_arg, expects),
				apply_indent(text, indent), "Shortcut")
		add_completion_option(script_editor, cc_dict)
		matched = true

	if not matched:
		return false
	
	update_completion_options(true)
	return true

func _reload_if_changed() -> void:
	if not FileAccess.file_exists(ALIAS_PATH):
		_aliases.clear()
		_last_modified = 0
		return
	var modified = FileAccess.get_modified_time(ALIAS_PATH)
	if modified == _last_modified:
		return
	_last_modified = modified

	_aliases.clear()
	var errors = parse_aliases(FileAccess.get_file_as_string(ALIAS_PATH), _aliases)
	for error in errors:
		printerr("Code Completions - %s: %s" % [ALIAS_PATH.get_file(), error])


## Fills `out` with {alias_key: insert_text}, returns any problems as message strings. Static so
## the parse/display/indent rules can be tested without a live singleton.
static func parse_aliases(yaml_text:String, out:Dictionary) -> Array:
	var errors = []
	var parser = YAMLParser.new()
	if parser.parse(yaml_text) != OK:
		errors.append(parser.get_error_message())
		return errors
	if not parser.data is Dictionary:
		errors.append("expected a top level mapping of alias keys.")
		return errors

	for key in parser.data:
		var value = parser.data[key]
		if value is Dictionary or value is Array:
			errors.append("alias '%s' must be a string." % key)
			continue
		# a `|` block keeps its trailing break, which would drop the caret onto a blank line
		var text = str(value).rstrip("\n")
		if text == "":
			continue
		out[str(key)] = text

	return errors

## "" means nothing typed past the key yet, so fall back to the visible default; a lone underscore
## is the explicit blank. Anything else - including a leading-underscore private name - is verbatim.
static func resolve_arg(typed:String) -> String:
	if typed == "":
		return PLACEHOLDER
	if typed == BLANK_ARG:
		return ""
	return typed

## Positional arguments from the text typed past the key. The leading separator is optional, so
## "forloop/i/aliases" and "forloopi/aliases" both give ["i", "aliases"].
static func split_args(typed:String) -> PackedStringArray:
	if typed == "":
		return PackedStringArray()
	return typed.trim_prefix(ARG_SEPARATOR).split(ARG_SEPARATOR)

static func placeholder_count(text:String) -> int:
	return text.count(PLACEHOLDER_TOKEN)

## Placeholders are positional, but a short argument list repeats its last entry - that is what lets
## a template whose slots all want the same string (dropdata) still work from a single argument.
## Split on the token rather than String.replace so each slot can take a different value, and so a
## snippet's own % (modulo, %UniqueNode) is never touched.
static func substitute(text:String, args:PackedStringArray) -> String:
	var parts = text.split(PLACEHOLDER_TOKEN)
	var out = parts[0]
	for i in range(1, parts.size()):
		out += _arg_at(args, i - 1) + parts[i]
	return out

static func _arg_at(args:PackedStringArray, index:int) -> String:
	if args.is_empty():
		return PLACEHOLDER
	return resolve_arg(args[mini(index, args.size() - 1)])

static func make_display(key:String, insert:String, arg:String="", expects:int=0) -> String:
	var first = insert.get_slice("\n", 0)
	if first.length() > DISPLAY_MAX:
		first = first.substr(0, DISPLAY_MAX).rstrip(" \t") + ELLIPSIS
	elif insert.contains("\n"):
		first += " " + ELLIPSIS
	var prefix = "(%s %s)" % [key, arg] if arg != "" else "(%s)" % key
	var display = "%s %s" % [prefix, first]
	if expects > 0:
		display += " (expects %d)" % expects
	return display

## Multi line inserts land verbatim, so every line past the first needs the caret line's indent.
static func apply_indent(text:String, indent:String) -> String:
	if indent == "" or not text.contains("\n"):
		return text
	var lines = text.split("\n")
	for i in range(1, lines.size()):
		if lines[i] == "":
			continue
		lines[i] = indent + lines[i]
	return "\n".join(lines)

static func get_line_indent(line_text:String) -> String:
	return line_text.substr(0, line_text.length() - line_text.lstrip(" \t").length())


class EditorSet:
	const ENABLE = &"plugin/code_completion/alias/enable"
