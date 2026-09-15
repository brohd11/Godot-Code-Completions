extends EditorCodeCompletion

## Array "structs": `#! arr_struct [constructor]` on a class that builds plain arrays and names their
## slots with an unnamed enum; slot types are the constructor's args by index (args[ENUM]).
## On an Array from that class: `s.` offers `get(S.MEMBER)`, `s.get(` and `s[` offer `S.MEMBER`.
## `#! arr_struct arg:S` on a func marks the arg inside it, and at call sites offers `S.create(` or,
## in an array literal, a code hint of the slots. Nameless enums are scanned from the class lines.

const PRINT_DEBUG = false

const TagParser = UtilsRemote.TagParser
const HidePrivateCompletion = EditorCodeCompletionSingleton.HidePrivateCompletion

const PREFIX = &"#!"
const TAG = &"arr_struct"

const HINT_MARK = 0xFFFF # CodeEdit underlines the code hint text between two of these

var _enable:bool = true
var _code_hint_line:int = -1


func _singleton_ready() -> void:
	EditorCodeCompletion.register_tag_static(PREFIX, TAG, EditorCodeCompletionSingleton.TagLocation.ANY)
	SyntaxPlusSingleton.register_highlight_callable(PREFIX, TAG, _syntax_highlighting, SyntaxPlusSingleton.CallableLocation.ANY)

	ScriptEditorRef.subscribe(ScriptEditorRef.Event.TEXT_CHANGED, _on_text_changed)

	TagParser.register_tag_parser(TAG, self)

func register_editor_settings(settings_helper:SettingHelperEditor):
	settings_helper.subscribe_property(self, &"_enable", EditorSet.ENABLE, true)

func _on_editor_script_changed(_script) -> void:
	_code_hint_line = -1

func _on_text_changed():
	if _code_hint_line == -1:
		return
	_code_hint_line = -1
	get_code_edit().set_code_hint("")


# Always has keys: TagParser drops falsy tag data, which would make a bare class tag invisible.
func parse_tag(raw_tags:Dictionary) -> Dictionary:
	var text:String = raw_tags.get("mods", "") + " " + raw_tags.get("args", "")
	return {"args": parse_arg_types(text), "constructor": parse_constructor(text)}

## "a:S b: Outer.T" -> {"a": "S", "b": "Outer.T"}
static func parse_arg_types(text:String) -> Dictionary:
	var args:Dictionary = {}
	for part:String in _join_type_colons(text).split(" ", false):
		if not part.contains(":"):
			continue
		var arg_name:String = part.get_slice(":", 0).strip_edges()
		if arg_name != "":
			args[arg_name] = part.get_slice(":", 1).strip_edges()
	return args

## First token that isn't an arg:Type pair - the class tag's constructor name.
static func parse_constructor(text:String) -> String:
	for part:String in _join_type_colons(text).split(" ", false):
		if not part.contains(":"):
			return part
	return ""

static func _join_type_colons(text:String) -> String:
	while text.contains(": ") or text.contains(" :"):
		text = text.replace(": ", ":").replace(" :", ":")
	return text


func _on_code_completion_requested(script_editor:CodeEdit) -> bool:
	if not _enable:
		return false

	var caret_context = get_caret_context()
	if caret_context.token_state == TokenState.COMMENT:
		return _comment_completion(caret_context)
	if caret_context.token_state != TokenState.NONE:
		return false

	if caret_context.expression_state == ExpressionState.MEMBER_ACCESS:
		return _member_access_completion(script_editor, caret_context)
	# only claims get() and tagged receivers, other calls fall through so `foo(s[` still works
	if caret_context.is_in_function_call():
		if _get_call_completion(script_editor, caret_context):
			return true
		if _tagged_call_completion(script_editor, caret_context):
			return true
	if caret_context.expression_state == ExpressionState.INDEX_ACCESS:
		return _index_access_completion(script_editor, caret_context)
	return false


func _comment_completion(caret_context:CaretContext) -> bool:
	if not caret_context.current_line_text.strip_edges().begins_with(PREFIX + " " + TAG):
		return false

	var left_of_caret:String = caret_context.current_line_text.left(caret_context.caret_column)
	var comment_i = UString.string_safe_find(left_of_caret, "#")
	var expression = caret_context.get_expression_at_position(left_of_caret.substr(comment_i))
	if not left_of_caret.trim_suffix(expression).strip_edges(false, true).ends_with(":"):
		return false

	Helpers.class_completion(self, expression)
	return true


#region Array access

func _member_access_completion(script_editor:CodeEdit, caret_context:CaretContext) -> bool:
	if caret_context.get_last_member_access_part().begins_with("_"):
		return false
	var target:Dictionary = _get_array_struct_target(caret_context.trim_last_member_access_part())
	if target.is_empty():
		return false
	var data:Dictionary = get_struct_data(target.class_path)
	if data.is_empty():
		return false

	# adding options replaces the native list, so it is captured first and re-added after
	var natives = script_editor.get_code_completion_options()
	for member:String in data.types:
		var text:String = get_option_text(target.prefix, member)
		var dict = get_code_complete_dict(CodeEdit.KIND_FUNCTION, text, text, _icon_type(data.types[member]), null, CodeEdit.LOCATION_LOCAL)
		add_completion_option(script_editor, dict)

	HidePrivateCompletion.filter(self, natives)
	return true


func _get_call_completion(script_editor:CodeEdit, caret_context:CaretContext) -> bool:
	var call_data = caret_context.get_function_call_data()
	if call_data.get_function_name() != "get" or call_data.current_arg_index != 0:
		return false
	var target:Dictionary = _get_array_struct_target(UString.trim_member_access_back(call_data.expression))
	if target.is_empty():
		return false
	var data:Dictionary = get_struct_data(target.class_path)
	if data.is_empty():
		return false

	_add_enum_options(script_editor, target.prefix, data.types)
	update_completion_options(call_data.get_current_arg_text() == "")
	return true


func _index_access_completion(script_editor:CodeEdit, caret_context:CaretContext) -> bool:
	var target:Dictionary = _get_array_struct_target(caret_context.get_index_access_identifier())
	if target.is_empty():
		return false
	var data:Dictionary = get_struct_data(target.class_path)
	if data.is_empty():
		return false

	_add_enum_options(script_editor, target.prefix, data.types)
	update_completion_options(true)
	return true


func _add_enum_options(script_editor:CodeEdit, prefix:String, member_types:Dictionary) -> void:
	for member:String in member_types:
		var full_name:String = UString.dot_join(prefix, member)
		var dict = get_code_complete_dict(CodeEdit.KIND_ENUM, full_name, full_name, _icon_type(member_types[member]), null, CodeEdit.LOCATION_LOCAL)
		add_completion_option(script_editor, dict)

static func get_option_text(prefix:String, member:String) -> String:
	return "get(%s)" % UString.dot_join(prefix, member)

static func _icon_type(type:String) -> String:
	return "Variant" if type == "" else type

#endregion


#region Tagged receiver

## `send(|)` offers the constructor, `send([|])` sets the slot hint and lets other providers run.
func _tagged_call_completion(script_editor:CodeEdit, caret_context:CaretContext) -> bool:
	var in_array:bool = caret_context.is_in_array()
	if not in_array and caret_context.closest_bracket_type != "(":
		return false
	var call_data = caret_context.get_function_call_data()
	if not call_data.is_valid:
		return false
	var tagged:Dictionary = _get_tagged_call_struct(call_data)
	if tagged.is_empty():
		return false
	var data:Dictionary = get_struct_data(tagged.class_path)
	if data.is_empty():
		return false

	if in_array:
		_set_struct_hint(caret_context, data)
		return false

	if data.constructor == "":
		return false
	var natives = script_editor.get_code_completion_options()
	for path:String in tagged.paths:
		var insert:String = "%s.%s(" % [path, data.constructor]
		var dict = get_code_complete_dict(CodeEdit.KIND_FUNCTION, insert + tagged.paths[path], insert, "method", null, CodeEdit.LOCATION_LOCAL)
		add_completion_option(script_editor, dict)
	# every native is kept - hide_private's filter would drop `_` locals here
	for option in natives:
		add_completion_option(script_editor, option)

	update_completion_options(call_data.get_current_arg_text() == "")
	return true


## {class_path, paths} for the arg at the caret, paths being {typable path: display suffix}.
## The tag's type is spelled in the declaring script, so it is resolved and translated from there.
func _get_tagged_call_struct(call_data) -> Dictionary:
	var function_script:String = call_data.get_function_script()
	if not GDScriptParser.Utils.is_absolute_path(function_script):
		return {}
	var metadata = TagParser.get_metadata_for_type(call_data.get_function_origin(), TAG)
	if not metadata is Dictionary or not metadata.has(TAG):
		return {}
	var written_type:String = metadata[TAG].get("args", {}).get(call_data.get_current_arg_name(), "")
	if written_type == "":
		return {}

	var parser = get_gdscript_parser()
	var script_data = GDScriptParser.Utils.type_path_get_script_data(function_script)
	var class_path:String = parser.resolve_expression_in_script(written_type, script_data[0], script_data[1]).trim_suffix(ParserKeys.INS_DELIM)
	if not has_struct_tag(class_path):
		return {}

	var access_object = parser.resolve_to_access_object_in_script(written_type, script_data[0], script_data[1])
	var options = call_data.get_type_access_path(class_path, access_object)
	var paths:Dictionary = {}
	if options.global != "": paths[options.global] = " [Global]"
	if options.script_alias != "": paths[options.script_alias] = " [Script Alias]"
	if options.standard != "": paths[options.standard] = ""
	if PRINT_DEBUG:
		print("ArrStruct - tagged call: ", written_type, " -> ", class_path, " -> ", paths)
	return {"class_path": class_path, "paths": paths}


func _set_struct_hint(caret_context:CaretContext, data:Dictionary) -> void:
	var string_map = caret_context.code_context_string_map
	var square_idx:int = caret_context.closest_bracket_index_square
	if not is_direct_array_arg(string_map.bracket_map, caret_context.closest_bracket_index_paren, square_idx, caret_context.code_context):
		return
	var index:int = array_element_index(caret_context.code_context, string_map.bracket_map, string_map.string_mask, square_idx, caret_context.code_context_caret_pos)
	get_code_edit().set_code_hint(build_struct_hint(data.members, data.types, index))
	_code_hint_line = caret_context.caret_line


## The `[` must be the arg itself: `f([|` and `f(x, [|` pass, `f([[|` and `f([a, [|` don't.
static func is_direct_array_arg(bracket_map:Dictionary, paren_idx:int, square_idx:int, code_context:String) -> bool:
	if paren_idx == -1 or square_idx <= paren_idx:
		return false
	var i:int = square_idx - 1
	while i > paren_idx and code_context[i] in [" ", "\t", "\n"]:
		i -= 1
	if i != paren_idx and code_context[i] != ",":
		return false
	# bracket_map holds both directions, opens are the keys below their value
	for open:int in bracket_map:
		var close:int = bracket_map[open]
		if open < close and open > paren_idx and open < square_idx and close > square_idx:
			return false
	return true

## Top-level commas between the `[` and the caret, skipping strings and nested brackets.
static func array_element_index(code_context:String, bracket_map:Dictionary, string_mask, square_idx:int, caret_pos:int) -> int:
	var index:int = 0
	var i:int = square_idx + 1
	while i < caret_pos:
		if string_mask[i] == 1:
			i += 1
			continue
		var c:String = code_context[i]
		if c in ["(", "[", "{"] and bracket_map.get(i, -1) > i:
			i = bracket_map[i] # lands on the close, which the next pass steps over
			continue
		if c == ",":
			index += 1
		i += 1
	return index

## "MEMBER: int, MEMBER2: int" in declaration order, with the slot at `index` marked.
static func build_struct_hint(members:Dictionary, types:Dictionary, index:int) -> String:
	var parts:Array[String] = []
	for member:String in members:
		var text:String = "%s: %s" % [member, _icon_type(types.get(member, ""))]
		if members[member] is int and members[member] == index:
			text = char(HINT_MARK) + text + char(HINT_MARK)
		parts.append(text)
	return ", ".join(parts)

#endregion


#region Target

## {class_path, prefix} or {}. Unhinted `return [...]` funcs may not resolve a type, so an empty
## type is allowed through - the tag is the real guard.
func _get_array_struct_target(expression:String) -> Dictionary:
	if expression == "":
		return {}
	var type:String = get_caret_context().resolve_expression_to_type(expression)
	if type != "" and not is_array_type(type):
		return {}

	var target:Dictionary = _get_arg_tag_target(expression)
	if target.is_empty():
		target = _get_class_tag_target(expression)
	if PRINT_DEBUG:
		print("ArrStruct - ", expression, " -> ", type, " -> ", target)
	return target


## Only a bare arg of the func the caret is in; the tag's type is written in this scope, so it is
## also the access prefix.
func _get_arg_tag_target(expression:String) -> Dictionary:
	if not expression.is_valid_ascii_identifier():
		return {}
	var caret_context = get_caret_context()
	var func_obj = caret_context.get_current_func_object()
	if not func_obj or not func_obj.get_arguments().has(expression):
		return {}
	var class_obj = caret_context.get_current_class_object()
	var func_path = GDScriptParser.Utils.type_path_add_member(class_obj.get_script_class_path(), func_obj.name)
	var metadata = TagParser.get_metadata_for_type(func_path, TAG)
	if not metadata is Dictionary or not metadata.has(TAG):
		return {}

	var written_type:String = metadata[TAG].get("args", {}).get(expression, "")
	if written_type == "":
		return {}
	var class_path:String = caret_context.resolve_expression_to_type(written_type).trim_suffix(ParserKeys.INS_DELIM)
	if not has_struct_tag(class_path):
		return {}
	return {"class_path": class_path, "prefix": written_type}


## Origin is tried first; the member stack covers vars assigned from the struct's funcs.
func _get_class_tag_target(expression:String) -> Dictionary:
	var type_rich:Dictionary = get_caret_context().resolve_expression_to_type_rich(expression)
	if PRINT_DEBUG:
		print("ArrStruct - origin: ", type_rich.get("origin"), " stack: ", type_rich.get("member_stack"))

	var candidates:Array = [type_rich.get("origin", "")]
	for entry:String in type_rich.get("member_stack", []):
		candidates.append_array(entry.split(ParserKeys.MEMBER_STACK_DELIM, false))

	for candidate:String in candidates:
		if not GDScriptParser.Utils.is_absolute_path(candidate):
			continue
		var class_path:String = GDScriptParser.Utils.type_path_get_non_member(candidate)
		if class_path == "" or not has_struct_tag(class_path):
			continue
		var prefix = _get_access_prefix(class_path)
		if prefix == null:
			return {}
		return {"class_path": class_path, "prefix": prefix}
	return {}


static func has_struct_tag(class_path:String) -> bool:
	return _get_class_tag_data(class_path) != null

static func _get_class_tag_data(class_path:String) -> Variant:
	var tag_path:String = class_tag_path(class_path)
	if tag_path == "":
		return null
	var metadata = TagParser.get_metadata_for_type(tag_path, TAG)
	if not metadata is Dictionary or not metadata.has(TAG):
		return null
	return metadata[TAG]

## The `class X:` line belongs to X itself, so the tag is stored as "X::X" inside that class.
## "res://a.gd.Outer.S" -> "res://a.gd.Outer.S::S". Main scripts have no class line: "".
static func class_tag_path(class_path:String) -> String:
	var script_data:Array = UString.get_script_path_and_suffix(class_path)
	if script_data.size() < 2 or script_data[1] == "":
		return ""
	var access:String = script_data[1]
	var class_name_part:String = access.get_slice(".", access.get_slice_count(".") - 1)
	return GDScriptParser.Utils.type_path_add_member(class_path, class_name_part)


## "" inside the struct, the shortest resolving class chain otherwise, null if it can't be named.
func _get_access_prefix(class_path:String) -> Variant:
	var caret_context = get_caret_context()
	var current_class_obj = caret_context.get_current_class_object()
	if is_instance_valid(current_class_obj) and current_class_obj.get_script_class_path() == class_path:
		return ""

	var parts:PackedStringArray = UString.get_script_path_and_suffix(class_path)[1].split(".", false)
	for i in range(parts.size() - 1, -1, -1):
		var candidate:String = ".".join(parts.slice(i))
		var resolved:String = caret_context.resolve_expression_to_type(candidate)
		if resolved.trim_suffix(ParserKeys.INS_DELIM) == class_path:
			return candidate
	return null

#endregion


#region Members

## {members: {MEMBER: value}, types: {MEMBER: type}, constructor: name} or {}.
func get_struct_data(class_path:String) -> Dictionary:
	var parser = get_gdscript_parser()
	if not is_instance_valid(parser):
		return {}
	var parser_data = parser.get_parser_and_class_obj_for_script(class_path)
	if not parser_data:
		return {}
	var class_obj = parser_data.class_obj as GDScriptParser.ParserClass
	if not is_instance_valid(class_obj):
		return {}
	var members:Dictionary = _get_struct_members(parser_data.parser, class_obj)
	if members.is_empty():
		return {}

	var constructor:String = _get_constructor_name(class_path, class_obj)
	var arg_types:Array = []
	var func_obj = class_obj.get_function(constructor) if constructor != "" else null
	if func_obj:
		var args:Dictionary = func_obj.get_arguments()
		for a:String in args:
			arg_types.append(display_type(args[a].get(ParserKeys.TYPE, "")))

	return {
		"members": members,
		"types": member_types_by_index(members, arg_types),
		"constructor": constructor,
	}

## Named in the class tag, otherwise the first static func.
func _get_constructor_name(class_path:String, class_obj:GDScriptParser.ParserClass) -> String:
	var tag_data = _get_class_tag_data(class_path)
	if tag_data is Dictionary and tag_data.get("constructor", "") != "":
		return tag_data.constructor
	for func_name:String in class_obj.functions:
		if class_obj.functions[func_name].is_static():
			return func_name
	return ""

## The enum value is the slot index, so it indexes the constructor's args directly.
static func member_types_by_index(members:Dictionary, arg_types:Array) -> Dictionary:
	var types:Dictionary = {}
	for member:String in members:
		var value = members[member]
		var in_range:bool = value is int and value >= 0 and value < arg_types.size()
		types[member] = arg_types[value] if in_range else ""
	return types


func _get_struct_members(parser, class_obj:GDScriptParser.ParserClass) -> Dictionary:
	var code_edit_parser = parser.get_code_edit_parser()
	# nested classes own their lines, so only this class's enums are seen
	var enum_texts:Array = []
	for line:int in class_obj.line_indexes:
		var stripped:String = code_edit_parser.get_line(line).strip_edges()
		if not stripped.begins_with("enum"):
			continue
		if stripped.count("{") != stripped.count("}"):
			var context = code_edit_parser.get_line_context(line, 0, false, {ParserKeys.CONTEXT_START: line})
			stripped = context.get(ParserKeys.CONTEXT_TEXT, stripped).strip_edges()
		enum_texts.append(stripped)

	return unnamed_enum_members(enum_texts)

## {member: value} of the unnamed enums in declaration order; named enums are not struct slots.
static func unnamed_enum_members(enum_texts:Array) -> Dictionary:
	var members:Dictionary = {}
	for text:String in enum_texts:
		var info:Array = GDScriptParser.Utils.get_enum_info(text)
		if info.size() < 2 or info[0] != "":
			continue
		members.merge(info[1])
	return members


static func is_array_type(type:String) -> bool:
	type = display_type(type)
	return type == "Array" or type.begins_with("Array[")

static func display_type(type:String) -> String:
	var type_check:String = GDScriptParser.Utils.type_path_get_type(type)
	if type_check != "":
		type = type_check
	return type.trim_suffix(ParserKeys.INS_DELIM)

#endregion


func _syntax_highlighting(_script_editor:CodeEdit, current_line_text:String, line_idx:int, comment_tag_idx:int):
	var comment_text = current_line_text.substr(comment_tag_idx)
	var hl_info = SyntaxPlusSingleton.HLInfo.highlight_prefix(PREFIX, comment_text)
	hl_info.merge(SyntaxPlusSingleton.HLInfo.highlight_tag(TAG, comment_text))

	var sp_ins = SyntaxPlusSingleton.get_instance()
	var gdscript_parser = SyntaxPlusSingleton.get_gdscript_parser() # members only, no inference needed
	if not is_instance_valid(gdscript_parser):
		return {0:SyntaxPlusSingleton.get_hl_info_dict(sp_ins.comment_color)}
	var current_class_obj = gdscript_parser.get_class_object(gdscript_parser.get_class_at_line(line_idx)) as GDScriptParser.ParserClass
	if not is_instance_valid(current_class_obj):
		return {0:SyntaxPlusSingleton.get_hl_info_dict(sp_ins.comment_color)}
	var script_class_path = current_class_obj.get_script_class_path()

	var prefix_end = SyntaxPlusSingleton.HLInfo.get_tag_end_index(PREFIX, TAG, comment_text)
	var stripped_comment = comment_text.substr(prefix_end)
	var tokens = UString.Token.tokenize_string(stripped_comment).get("tokens")
	var in_type_assign = false
	var idx = 0
	for t:String in tokens:
		idx = stripped_comment.find(t, idx)
		var adj_idx = idx + prefix_end
		var adj_token_end = adj_idx + t.length()
		if t == ":":
			SyntaxPlusSingleton.HLInfo.add_color(hl_info, sp_ins.symbol_color, adj_idx, -1, null, false)
			in_type_assign = true
		elif not in_type_assign:
			SyntaxPlusSingleton.HLInfo.add_color(hl_info, sp_ins.default_text_color, adj_idx, adj_token_end)
		else:
			in_type_assign = false
			if GDScriptParser.BuiltInChecker.is_builtin_class(t):
				SyntaxPlusSingleton.HLInfo.add_color(hl_info, sp_ins.engine_type_color, adj_idx, adj_token_end)
			else:
				hl_info.merge(SyntaxPlusSingleton.HLInfo.check_const_path(t, script_class_path, adj_idx))

	SyntaxPlusSingleton.HLInfo.add_color(hl_info, sp_ins.comment_color, current_line_text.length(), -1, null, false)
	return hl_info


class EditorSet:
	const ENABLE = &"plugin/code_completion/arr_struct/enable"
