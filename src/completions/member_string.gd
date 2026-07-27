extends EditorCodeCompletion

## Completes method and property names written as string arguments - call("…"),
## set_deferred("…"), Callable(obj, "…"), tween_property(node, "position:x", …).
## Godot only manages this when it can see the receiver directly; the parser resolves it
## through variables, user scripts, and sibling arguments.

const EditorColors = UtilsRemote.EditorColors

const PREFIX = &"prefix"
const ALLOW_QUOTE = &"allow_quote"

const ARG = &"arg"
const METHODS = &"methods"
const ARG_0_REC = &"arg_0_receiver"
const SUBPATH = &"subpath"
const NODE_PATH = &"node_path"

## func name -> where the member name sits and what belongs there.
## arg_0_receiver: the object is argument 0 rather than the call's own receiver.
## subpath: the argument is a property PATH, so "position:x" resolves segment by segment.
const CALL_TABLE = {
	"call":                       {ARG: 0, METHODS: true,  ARG_0_REC: false, SUBPATH: false},
	"call_deferred":              {ARG: 0, METHODS: true,  ARG_0_REC: false, SUBPATH: false},
	"callv":                      {ARG: 0, METHODS: true,  ARG_0_REC: false, SUBPATH: false},
	"call_thread_safe":           {ARG: 0, METHODS: true,  ARG_0_REC: false, SUBPATH: false},
	"call_deferred_thread_group": {ARG: 0, METHODS: true,  ARG_0_REC: false, SUBPATH: false},
	"has_method":                 {ARG: 0, METHODS: true,  ARG_0_REC: false, SUBPATH: false},
	"rpc":                        {ARG: 0, METHODS: true,  ARG_0_REC: false, SUBPATH: false},
	"rpc_id":                     {ARG: 1, METHODS: true,  ARG_0_REC: false, SUBPATH: false},
	"Callable":                   {ARG: 1, METHODS: true,  ARG_0_REC: true,  SUBPATH: false},

	"set":                        {ARG: 0, METHODS: false, ARG_0_REC: false, SUBPATH: false},
	"get":                        {ARG: 0, METHODS: false, ARG_0_REC: false, SUBPATH: false},
	"set_deferred":               {ARG: 0, METHODS: false, ARG_0_REC: false, SUBPATH: false},
	"set_indexed":                {ARG: 0, METHODS: false, ARG_0_REC: false, SUBPATH: true, NODE_PATH:true},
	"get_indexed":                {ARG: 0, METHODS: false, ARG_0_REC: false, SUBPATH: true, NODE_PATH:true},
	"tween_property":             {ARG: 1, METHODS: false, ARG_0_REC: true,  SUBPATH: true},
}

var _enable:bool = true
var _prefer_string_name:bool = true
var _include_private:bool = false


func _get_completion_settings() -> Dictionary:
	return {
		"priority": 110, #^ after dict_key (100) - it claims get() on tagged dictionaries
	}


func register_editor_settings(settings_helper:SettingHelperEditor):
	settings_helper.subscribe_property(self, &"_enable", EditorSet.ENABLE, true)
	settings_helper.subscribe_property(self, &"_prefer_string_name", EditorSet.PREFER_STRING_NAME, true)
	settings_helper.subscribe_property(self, &"_include_private", EditorSet.INCLUDE_PRIVATE, false)


func _on_code_completion_requested(script_editor:CodeEdit) -> bool:
	if not _enable:
		return false
	var caret_context = get_caret_context()
	if caret_context.token_state == TokenState.COMMENT:
		return false
	if not caret_context.is_in_function_call():
		return false

	var func_data = caret_context.get_function_call_data()
	if not func_data.is_valid:
		return false

	var entry = CALL_TABLE.get(func_data.get_function_name())
	if entry == null:
		return false
	if func_data.current_arg_index != entry.get(ARG):
		return false

	var type = _resolve_receiver(func_data, caret_context, entry.get(ARG_0_REC))
	if type == "":
		return false
	if type == "Dictionary" or type.begins_with("Dictionary["):
		return false # dict_key.gd owns dictionary keys

	var prefix = _string_prefix_at_caret(caret_context)
	if entry.get(SUBPATH) and prefix.contains(":"):
		return _add_subpath_completions(script_editor, caret_context, type, prefix, entry.get(NODE_PATH, false))
	
	var filter = Helpers.MemberFilter.METHODS if entry.get(METHODS) else Helpers.MemberFilter.PROPERTIES
	var members = Helpers.collect_type_members(self, type, filter, _include_private)
	if members.is_empty():
		return false
	return _add_member_completions(script_editor, caret_context, members, {
		ALLOW_QUOTE: true,
		NODE_PATH: entry.get(NODE_PATH, false),
	})


## The object the members are read from - argument 0 for Callable/tween_property, otherwise
## whatever the call is chained off of. Implicit self resolves to the script, not its base type,
## so the script's own members are listed too.
func _resolve_receiver(func_data:CaretContext.FunctionCallData, caret_context:CaretContext, arg_0_receiver:bool) -> String:
	if arg_0_receiver:
		if func_data.current_arguments.is_empty():
			return ""
		return _resolve_type(caret_context, func_data.current_arguments[0].strip_edges())
	
	if not func_data.expression.contains("."):
		return caret_context.get_current_class_object().get_script_class_path()
	return _resolve_type(caret_context, UString.trim_member_access_back(func_data.expression))


func _resolve_type(caret_context:CaretContext, expression:String) -> String:
	if expression == "":
		return ""
	return Helpers.normalize_member_type(caret_context.resolve_expression_to_type(expression))


## Text typed so far inside the string literal at the caret, "" when the caret is not in one.
func _string_prefix_at_caret(caret_context:CaretContext) -> String:
	if not caret_context.is_in_string():
		return ""
	var line:String = caret_context.current_line_text
	var head = line.substr(0, mini(caret_context.caret_column, line.length()))
	var quote_index = maxi(head.rfind("\""), head.rfind("'"))
	if quote_index == -1:
		return ""
	return head.substr(quote_index + 1)


## Walks the completed segments of a property path ("modulate:a") to find the type the
## still-being-typed tail belongs to.
func _add_subpath_completions(script_editor:CodeEdit, caret_context:CaretContext, type:String, prefix:String, node_path:bool) -> bool:
	var segments = prefix.split(":")
	segments.remove_at(segments.size() - 1) # the segment still being typed

	var current_type = type
	for segment in segments:
		var members = Helpers.collect_type_members(self, current_type, Helpers.MemberFilter.PROPERTIES, _include_private)
		var member_data = members.get(segment)
		if member_data == null:
			return false
		current_type = member_data.type
		if current_type == "":
			return false

	var tail_members = Helpers.collect_type_members(self, current_type, Helpers.MemberFilter.PROPERTIES, _include_private)
	if tail_members.is_empty():
		return false

	# the editor filters on the whole typed string, so options carry the path walked so far
	return _add_member_completions(script_editor, caret_context, tail_members, {
		PREFIX: prefix.substr(0, prefix.rfind(":") + 1),
		NODE_PATH: node_path,
	})


## opts: prefix:String - accessor walked so far, node_path:bool, allow_quote:bool
func _add_member_completions(script_editor:CodeEdit, caret_context:CaretContext, members:Dictionary, opts:={}) -> bool:
	var prefix:String = opts.get(PREFIX, "")
	var node_path:bool = opts.get(NODE_PATH, false)

	var quote_option = opts.get(ALLOW_QUOTE, false) and not caret_context.is_in_string()
	var use_string_name = _prefer_string_name and caret_context.token_state != TokenState.STRING
	
	var color = Helpers.get_string_color(caret_context, TokenState.NODE_PATH_LITERAL if node_path else TokenState.STRING_NAME)

	for member in members.keys():
		var member_data:Dictionary = members[member]
		var insert = prefix + member
		if quote_option:
			if node_path:
				insert = "^" + UString.quote(insert)
			else:
				insert = UString.quote(insert, use_string_name)

		var icon = "method" if member_data.kind == CodeEdit.KIND_FUNCTION else "property"
		var dict = get_code_complete_dict(member_data.kind, insert, insert, icon, null, member_data.location, color)
		add_completion_option(script_editor, dict)

	update_completion_options(true)
	return true


class EditorSet:
	const ENABLE = &"plugin/code_completion/member_string/enable"
	const PREFER_STRING_NAME = &"plugin/code_completion/member_string/prefer_string_name"
	const INCLUDE_PRIVATE = &"plugin/code_completion/member_string/include_private"
