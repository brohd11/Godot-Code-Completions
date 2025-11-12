extends Singleton.RefCount
#! remote
#! import-p UString,UClassDetail,

const SCRIPT = preload("res://addons/code_completions/src/class/editor_code_completion_singleton.gd") #! ignore-remote

const UClassDetail = preload("res://addons/addon_lib/brohd/alib_editor/utils/src/u_class_detail.gd")
const USort = preload("res://addons/addon_lib/brohd/alib_runtime/utils/src/u_sort.gd")
const UString = preload("res://addons/addon_lib/brohd/alib_runtime/utils/src/u_string.gd")
const GlobalChecker = preload("res://addons/addon_lib/brohd/alib_runtime/misc/global_checker.gd")
const VariantChecker = preload("res://addons/addon_lib/brohd/alib_runtime/misc/variant_checker.gd")

const DataAccessSearch = preload("res://addons/code_completions/src/class/data_access_search.gd")
const CacheHelper = DataAccessSearch.CacheHelper

const GDScriptParser = preload("res://addons/code_completions/src/class/gdscript_parser.gd")

#^b{ LSP
#const GDScriptLSPParser = preload("res://addons/code_completions/src/class/gdscript_lsp_parser.gd")
#var gdscript_lsp_parser:GDScriptLSPParser
#
#func _create_lsp_parser():
	#gdscript_lsp_parser = GDScriptLSPParser.new()
#
#func _process(delta: float) -> void:
	#if is_instance_valid(gdscript_lsp_parser):
		#gdscript_lsp_parser.process()

#^}

const TimeFunction = ALibRuntime.Utils.UProfile.TimeFunction

static func get_singleton_name() -> String:
	return "EditorCodeCompletion"

static func get_instance() -> SCRIPT:
	return _get_instance(SCRIPT)

static func _register_completion(completion, settings:Dictionary):
	var instance = _register_node(SCRIPT, completion)
	instance.code_completions[completion] = settings
	instance.code_completion_added()
	return instance

func unregister_completion(completion):
	code_completions.erase(completion)
	unregister_node(completion)


static func instance_valid():
	return _instance_valid(SCRIPT)

static func call_on_ready(callable:Callable, printerr:=false) -> void:
	_call_on_ready(SCRIPT, callable, printerr)

enum State {
	NONE,
	COMMENT,
	STRING,
	ASSIGNMENT,
	FUNC_ARGS,
	MEMBER_ACCESS,
	SCRIPT_BODY,
}

enum TagLocation {
	START,
	END,
	ANY,
}

enum PersistentCache {
	TAGS,
	GLOBAL_ACCESS_PATHS,
}

enum ScriptCache {
	STRING_MAPS,
	#SCRIPT_PRELOADS,
}

enum CompletionCache {
	WORD_BEFORE_CARET,
	CHAR_BEFORE_CARET,
	CARET_IN_FUNC_CALL,
	FUNC_CALL,
	FUNC_CALL_TYPED,
	ASSIGNMENT,
}

var data_access_search:DataAccessSearch
var gdscript_parser:GDScriptParser


var hide_private_members:=false

var _current_script:GDScript
var _current_code_edit:CodeEdit
var _sort_queued:= false

var code_completions:Dictionary = {}

var peristent_cache:Dictionary = {}
var script_cache:Dictionary = {}
var completion_cache:Dictionary = {}

var current_state:State = State.NONE

var assignment_regex:RegEx

func _init(plugin) -> void:
	_singleton_init()
	_init_set_settings()

func _ready() -> void:
	await get_tree().create_timer(1).timeout
	_set_code_edit(null)
	_connect_editor()



func _singleton_init():
	_clear_cache()
	data_access_search = DataAccessSearch.new()
	gdscript_parser = GDScriptParser.new()
	gdscript_parser.code_completion_singleton = self


func clear_cache():
	_clear_cache()
	if is_inside_tree():
		sort_completions()

func _clear_cache():
	peristent_cache.clear()
	script_cache.clear()
	completion_cache.clear()
	
	peristent_cache[PersistentCache.TAGS] = {}
	#peristent_cache[PersistentCache.GLOBAL_ACCESS_PATHS] = {}
	
	script_cache[ScriptCache.STRING_MAPS] = {}


func _init_set_settings():
	var editor_settings = EditorInterface.get_editor_settings()
	if not editor_settings.has_setting(EditorSet.HIDE_PRIVATE_PROP_SETTING):
		editor_settings.set_setting(EditorSet.HIDE_PRIVATE_PROP_SETTING, false)
	if not editor_settings.has_setting(EditorSet.GLOBAL_CHECK_SETTING):
		editor_settings.set_setting(EditorSet.GLOBAL_CHECK_SETTING, DataAccessSearch.GlobalCheck.GLOBAL)
	if not editor_settings.has_setting(EditorSet.SCRIPT_ALIAS_SETTING):
		editor_settings.set_setting(EditorSet.SCRIPT_ALIAS_SETTING, DataAccessSearch.ScriptAlias.INHERITED)
	
	editor_settings.add_property_info(EditorSet.GLOBAL_CHECK_INFO)
	editor_settings.add_property_info(EditorSet.SCRIPT_ALIAS_INFO)
	
	_set_settings()
	editor_settings.settings_changed.connect(_set_settings)

func _set_settings():
	var editor_settings = EditorInterface.get_editor_settings()
	
	hide_private_members = editor_settings.get_setting(EditorSet.HIDE_PRIVATE_PROP_SETTING)
	data_access_search.set_global_check_setting(editor_settings.get_setting(EditorSet.GLOBAL_CHECK_SETTING))
	data_access_search.set_script_alias_setting(editor_settings.get_setting(EditorSet.SCRIPT_ALIAS_SETTING))
	

func register_tag(prefix:String, tag:String, location:TagLocation=TagLocation.ANY):
	if not peristent_cache[PersistentCache.TAGS].has(prefix):
		peristent_cache[PersistentCache.TAGS][prefix] = {}
	
	if not peristent_cache[PersistentCache.TAGS][prefix].has(tag):
		peristent_cache[PersistentCache.TAGS][prefix][tag] = location
	else:
		print("Tag already registered: %s %s" % [prefix, tag])

func unregister_tag(prefix:String, tag:String):
	if not peristent_cache[PersistentCache.TAGS].has(prefix):
		peristent_cache[PersistentCache.TAGS][prefix] = {}
	
	if peristent_cache[PersistentCache.TAGS][prefix].has(tag):
		peristent_cache[PersistentCache.TAGS][prefix].erase(tag)
	else:
		print("Tag not present: %s %s" % [prefix, tag])


func code_completion_added():
	sort_completions()



func sort_completions():
	if _sort_queued:
		return
	_sort_queued = true
	await get_tree().process_frame
	
	var key_priority_dict = {}
	for editor_code_completion in code_completions.keys():
		var settings = code_completions.get(editor_code_completion, 100)
		key_priority_dict[editor_code_completion] = 100
	
	var sorted_dict = USort.sort_priority_dict(key_priority_dict)
	var new_dict = {}
	for editor_code_completion in sorted_dict:
		new_dict[editor_code_completion] = code_completions[editor_code_completion]
	
	code_completions = new_dict
	_sort_queued = false


func _connect_editor():
	EditorInterface.get_script_editor().editor_script_changed.connect(_set_code_edit)
	EditorInterface.get_resource_filesystem().filesystem_changed.connect(_on_file_system_changed)

func _disconnect_editor():
	EditorInterface.get_script_editor().editor_script_changed.disconnect(_set_code_edit)
	EditorInterface.get_resource_filesystem().filesystem_changed.disconnect(_on_file_system_changed)

func _set_code_edit(script):
	if is_instance_valid(_current_code_edit):
		if _current_code_edit.code_completion_requested.is_connected(_on_code_completion_requested):
			_current_code_edit.code_completion_requested.disconnect(_on_code_completion_requested)
	
	var current_editor = EditorInterface.get_script_editor().get_current_editor()
	if not is_instance_valid(current_editor):
		return
	_current_code_edit = current_editor.get_base_editor()
	
	if is_instance_valid(_current_code_edit):
		if not _current_code_edit.code_completion_requested.is_connected(_on_code_completion_requested):
			_current_code_edit.code_completion_requested.connect(_on_code_completion_requested.bind(_current_code_edit))
	
	if script != null:
		_on_editor_script_changed(script)
		_current_script = script


func _on_editor_script_changed(script):
	_prep_script(script)

func _on_file_system_changed():
	var current_script = _get_current_script()
	_prep_script(current_script)

func _prep_script(script):
	script_cache.clear()
	script_cache[ScriptCache.STRING_MAPS] = {}
	
	if script != null:
		gdscript_parser.on_script_changed(script)
	
	for editor_code_completion in code_completions.keys():
		editor_code_completion._on_editor_script_changed(script)



func _on_code_completion_requested(script_editor:CodeEdit) -> void:
	completion_cache.clear()
	_pre_request_checks(script_editor)
	
	var has_tag = _tag_completion(script_editor)
	if has_tag:
		return
	
	for editor_code_completion in code_completions.keys():
		var t = TimeFunction.new(str(editor_code_completion.get_script().resource_path.get_file()))
		var handled = editor_code_completion._on_code_completion_requested(script_editor)
		t.stop()
		if handled:
			return
	
	add_code_completion_options(script_editor)


func _pre_request_checks(script_editor:CodeEdit):
	var current_caret_line = script_editor.get_caret_line()
	var current_caret_col = script_editor.get_caret_column()
	var current_line_text:String = script_editor.get_line(current_caret_line)
	
	gdscript_parser.on_completion_requested() #^ this needs to be before for get_current_func to work
	
	current_state = State.NONE
	if is_index_in_string(current_caret_col, current_caret_line, script_editor):
		current_state = State.STRING
	elif is_index_in_comment(current_caret_col, current_caret_line, script_editor):
		current_state = State.COMMENT
	elif get_word_before_caret().find(".") > -1:
		current_state = State.MEMBER_ACCESS
	elif _in_func_call_check(current_line_text, current_caret_col):
		current_state = State.FUNC_ARGS
	elif _get_assignment_at_caret(current_line_text, current_caret_col) != null:
		current_state = State.ASSIGNMENT
	elif get_current_func() == GDScriptParser._Keys.CLASS_BODY:
		current_state = State.SCRIPT_BODY


func _tag_completion(script_editor:CodeEdit):
	if current_state != State.COMMENT:
		return false
	
	var current_line = script_editor.get_caret_line()
	var caret_col = script_editor.get_caret_column()
	var current_line_text = script_editor.get_line(current_line)
	var tags = peristent_cache[PersistentCache.TAGS].keys()
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
	
	var icon = EditorInterface.get_editor_theme().get_icon("Script", "EditorIcons")
	var declared_tag_members = peristent_cache[PersistentCache.TAGS].get(tag_present, {})
	for tag in declared_tag_members.keys():
		var location = declared_tag_members[tag]
		if location == TagLocation.START and tag_idx > 0:
			continue
		elif location == TagLocation.END and tag_idx == 0:
			continue
		script_editor.add_code_completion_option(CodeEdit.KIND_CONSTANT, tag, tag, Color.GRAY, icon)
	script_editor.update_code_completion_options(false)
	return true



func _hide_private_completions(script_editor:CodeEdit, completions:Array):
	if current_state != State.MEMBER_ACCESS: # only hide when accessing a member, want to see private in own class
		return completions
	var word_at_cursor = get_word_before_caret()
	var last_part = UString.get_member_access_back(word_at_cursor)
	if last_part.begins_with("_"):
		return completions
	
	var valid = []
	for option in completions:
		var display_text = option.get("display_text")
		if display_text.begins_with("_"):
			continue
		valid.append(option)
	return valid

func add_code_completion_options(script_editor:CodeEdit, options=null, hide_private=null):
	if hide_private == null:
		hide_private = hide_private_members
	if options == null:
		options = script_editor.get_code_completion_options()
	
	if hide_private:
		options = _hide_private_completions(script_editor, options)
	
	for o in options:
		script_editor.add_code_completion_option(o.kind, o.display_text, o.insert_text, o.font_color, o.icon, o.default_value)
	script_editor.update_code_completion_options(false)



#region API

func get_state() -> State:
	return current_state

func get_current_class() -> String:
	return gdscript_parser.current_class

func get_current_func() -> String:
	return gdscript_parser.current_func

func class_has_func(_func:String, _class:String):
	return gdscript_parser.class_has_func(_func, _class)

func get_func_args_and_return(_class:String, _func:String):
	return gdscript_parser.get_func_args_and_return(_class, _func)

func get_func_args(_class:String, _func:String):
	return gdscript_parser.get_func_args(_class, _func)

func get_func_return(_class:String, _func:String):
	return gdscript_parser.get_func_return(_class, _func)


func get_script_constants(_class:String=""):
	return gdscript_parser.get_script_constants(_class)

func get_preload_map():
	return gdscript_parser.get_preload_map()


func get_var_type(var_name:String):
	return gdscript_parser.get_var_type(var_name)

func property_info_to_type(property_info) -> String:
	var type = gdscript_parser.property_info_to_type(property_info)
	return type

func get_script_member_info_by_path(script:GDScript, member_path:String, member_hints:=UClassDetail._MEMBER_ARGS, check_global:=true):
	return UClassDetail.get_member_info_by_path(script, member_path, member_hints, false, false, false, check_global)

func get_script_alias(access_path:String, data=null):
	return gdscript_parser.data_access_search.check_for_script_alias(access_path, data)

#endregion


func get_assignment_at_caret():
	var script_editor = _get_code_edit()
	var caret_col = script_editor.get_caret_column()
	var line_text = script_editor.get_line(script_editor.get_caret_line())
	var assignment_data = _get_assignment_at_caret(line_text, caret_col)
	if assignment_data == null:
		return null
	var left = assignment_data.get(EditorCodeCompletion.Assignment.LEFT, "")
	var left_typed = ""
	if left.begins_with("var "):
		var trimmed = left.trim_prefix("var ")
		var data = UString.get_var_name_and_type_hint_in_line(left)
		if data != null:
			left_typed = get_var_type(data[1])
	else:
		left_typed = get_var_type(left)
	
	assignment_data[EditorCodeCompletion.Assignment.LEFT_TYPED] = left_typed
	return assignment_data


func _get_assignment_at_caret(line_text: String, caret_col: int):
	if completion_cache.has(CompletionCache.ASSIGNMENT):
		return completion_cache[CompletionCache.ASSIGNMENT]
	if line_text.rfind("=", caret_col) == -1: # alternative to above, if not on right side no need to do
		completion_cache[CompletionCache.ASSIGNMENT] = null
		return null
	
	if not is_instance_valid(assignment_regex):
		assignment_regex = RegEx.new()
		var pattern = r"((?:var\s+)?\w+(?:\(.*?\))?(?:\.\w+(?:\(.*?\))?)*(?:\s*:\s*[\w.]+)?)\s*(=\s*=|:\s*=|!\s*=|=)(.*?)(?=\s*(?:or|and|&&|\|\|)|$)"
		assignment_regex.compile(pattern)
	
	var matches = assignment_regex.search_all(line_text)
	if not matches.is_empty():
		for i in range(matches.size() - 1, -1, -1):
			var _match = matches[i] as RegExMatch
			if _match.get_start(2) <= caret_col:
				var best_match = _match
				var rhs = best_match.get_string(3).strip_edges()
				if rhs.find("=") > -1: #^ search for a 2nd assignment
					var nested_matches = assignment_regex.search_all(rhs)
					for nm in range(nested_matches.size() - 1, -1, -1):
						var nested_match = nested_matches[nm]
						if nested_match.get_start(2) <= caret_col:
							best_match = nested_match
							rhs = best_match.get_string(3).strip_edges()
				
				var lhs = best_match.get_string(1).strip_edges()
				var last_char_idx = best_match.get_end(1) - 1
				var operator = best_match.get_string(2).strip_edges()
				
				var and_index = lhs.rfind(" and ", caret_col)
				if and_index > -1:
					lhs = lhs.substr(and_index + 5)
				var or_index = lhs.rfind(" or ", caret_col)
				if or_index > -1:
					lhs = lhs.substr(or_index + 4)
				var bitwise_index = lhs.rfind("&&", caret_col)
				if bitwise_index > -1:
					lhs = lhs.substr(bitwise_index + 2)
				
				lhs = lhs.trim_prefix("self.") #^ simple sub
				
				var data = {
					EditorCodeCompletion.Assignment.LEFT: lhs,
					EditorCodeCompletion.Assignment.OPERATOR: operator,
					EditorCodeCompletion.Assignment.RIGHT: rhs }
				
				completion_cache[CompletionCache.ASSIGNMENT] = data
				return data
	
	completion_cache[CompletionCache.ASSIGNMENT] = null
	return null


#region Func Call

func _in_func_call_check(current_line_text:String, current_caret_col:int):
	var stripped = current_line_text.strip_edges()
	var in_declar = stripped.begins_with("func") or stripped.begins_with("static func")
	var func_data = _get_func_call_data(current_line_text, current_caret_col)
	if func_data.is_empty() or in_declar:
		completion_cache[CompletionCache.CARET_IN_FUNC_CALL] = false
		return false
	var arg_text = func_data[EditorCodeCompletion.FuncCall.ARGS][func_data[EditorCodeCompletion.FuncCall.ARG_INDEX]]
	if arg_text.rfind("=", current_caret_col) > -1:
		completion_cache[CompletionCache.CARET_IN_FUNC_CALL] = false
		return false
	
	completion_cache[CompletionCache.CARET_IN_FUNC_CALL] = true
	return true

func get_func_call_data(infer_type:=false):
	var script_editor = _get_code_edit()
	var caret_col = script_editor.get_caret_column()
	var current_line_text = script_editor.get_line(script_editor.get_caret_line())
	var func_call_data = _get_func_call_data(current_line_text, caret_col)
	if func_call_data.is_empty():
		return null
	if not infer_type:
		return func_call_data
	if completion_cache.has(CompletionCache.FUNC_CALL_TYPED):
		return completion_cache[CompletionCache.FUNC_CALL_TYPED]
	
	var full_call = func_call_data.get(EditorCodeCompletion.FuncCall.FULL_CALL, "")
	if full_call.find(".") > -1:
		var string_map = get_string_map(full_call) #^ trim method so we can just infer object types
		var trimmed = UString.trim_member_access_back(full_call, string_map)
		var method_call = UString.get_member_access_back(full_call, string_map)
		var full_call_typed = get_var_type(trimmed)# + "()")
		full_call_typed = full_call_typed + "." + method_call
		func_call_data[EditorCodeCompletion.FuncCall.FULL_CALL_TYPED] = full_call_typed
	
	completion_cache[CompletionCache.FUNC_CALL_TYPED] = func_call_data
	return func_call_data

func _get_func_call_data(current_line_text:String, caret_col:int) -> Dictionary:
	if completion_cache.has(CompletionCache.FUNC_CALL):
		return completion_cache.get(CompletionCache.FUNC_CALL)
	
	if current_line_text.rfind("(", caret_col) == -1:
		return {} # if not in a bracket no need to check
	
	var string_map = get_string_map(current_line_text)
	var bracket_map = string_map.bracket_map
	var string_indexes = string_map.string_mask
	if string_map.has_errors or bracket_map.is_empty():
		return {}
	
	var open_bracket_index = 0
	var closed_bracket_index = current_line_text.length()
	var bracket_map_keys = bracket_map.keys()
	bracket_map_keys.sort()
	for open in bracket_map_keys:
		if open > caret_col:
			break
		var char = current_line_text[open]
		if char != "(":
			continue
		var close = bracket_map.get(open)
		if not (open <= caret_col and close >= caret_col):
			continue
		if close - open < closed_bracket_index - open_bracket_index:
			open_bracket_index = open
			closed_bracket_index = close
	
	var func_full_call = _parse_identifier_at_position(current_line_text, open_bracket_index - 1, string_map)
	if func_full_call == "":
		return {}
	
	func_full_call = func_full_call.trim_prefix("self.") #^ simple check
	
	var arg_idxs = []
	var current_arg_index = 0
	var count = closed_bracket_index
	while count >= open_bracket_index:
		count -= 1
		if string_indexes[count] == 1:
			continue
		var char = current_line_text[count]
		if char == ")" or char == "}" or char == "]":
			count = bracket_map[count]
		
		if char == ",":
			if caret_col > count:
				current_arg_index += 1
			arg_idxs.append(count)
	
	arg_idxs.reverse()
	var arg_array = []
	var start_index = open_bracket_index + 1
	for i in arg_idxs:
		var substr_length = i - start_index
		var arg = current_line_text.substr(start_index, substr_length).strip_edges()
		arg_array.append(arg)
		start_index = i + 1
	
	var last_arg = current_line_text.substr(start_index, closed_bracket_index - start_index).strip_edges()
	arg_array.append(last_arg)
	
	var data = {
		EditorCodeCompletion.FuncCall.FULL_CALL: func_full_call,
		EditorCodeCompletion.FuncCall.ARGS: arg_array,
		EditorCodeCompletion.FuncCall.ARG_INDEX: current_arg_index}
	completion_cache[CompletionCache.FUNC_CALL] = data
	return data

func _parse_identifier_at_position(text:String, start_pos:int, string_map):
	var current_pos = start_pos
	var name_start_pos = start_pos + 1
	var last_char = ""
	while current_pos >= 0:
		if string_map.string_mask[current_pos] == 1:
			current_pos -= 1
			continue
		
		var char = text[current_pos]
		if char == ")" or char == "]" or char == "}":
			current_pos = string_map.bracket_map.get(current_pos, current_pos)
		
		if not char.is_valid_ascii_identifier() and char != ".":
			var valid = false
			if char == ")" and last_char == ".":
				valid = true
			if char in UString.NUMBERS:
				valid = true
			
			if not valid:
				break
		
		last_char = char
		name_start_pos = current_pos
		current_pos -= 1
	
	return text.substr(name_start_pos, start_pos - name_start_pos + 1)

#endregion

func get_word_before_caret():
	if completion_cache.has(CompletionCache.WORD_BEFORE_CARET):
		return completion_cache[CompletionCache.WORD_BEFORE_CARET]
	var script_editor = _get_code_edit() as CodeEdit
	var caret_col = script_editor.get_caret_column()
	var line_text = script_editor.get_line(script_editor.get_caret_line())
	var string_map = get_string_map(line_text)
	var identifier = _parse_identifier_at_position(line_text, caret_col - 1, string_map)
	completion_cache[CompletionCache.WORD_BEFORE_CARET] = identifier
	#print("WORD BEFORE CARET: ", identifier)
	return identifier

func get_char_before_caret():
	var script_editor = _get_code_edit() as CodeEdit
	var caret_col = script_editor.get_caret_column()
	var line_text = script_editor.get_line(script_editor.get_caret_line())
	var i = caret_col - 1
	var char = ""
	while i >= 0:
		char = line_text[i]
		if char != " ":
			break
		i -= 1
	completion_cache[CompletionCache.CHAR_BEFORE_CARET] = char
	#print("CHAR BEFORE CARET: ", char)
	return char


func is_index_in_comment(column:int=-1, line:int=-1, code_edit=null):
	if code_edit == null:
		code_edit = _get_code_edit() as CodeEdit
	if line == -1:
		line = code_edit.get_caret_line()
	if column == -1:
		column = code_edit.get_caret_column()
	return code_edit.is_in_comment(line, column) > -1

func is_index_in_string(column:int=-1, line:int=-1, code_edit=null):
	if code_edit == null:
		code_edit = _get_code_edit() as CodeEdit
	if line == -1:
		line = code_edit.get_caret_line()
	if column == -1:
		column = code_edit.get_caret_column()
	return code_edit.is_in_string(line, column) > -1



func get_string_map(text:String, mode:UString.StringMap.Mode=UString.StringMap.Mode.FULL, print_err:=false) -> UString.StringMap:
	if script_cache[ScriptCache.STRING_MAPS].has(text):
		return script_cache[ScriptCache.STRING_MAPS].get(text)
	var string_map = UString.get_string_map(text, mode, print_err)
	script_cache[ScriptCache.STRING_MAPS][text] = string_map
	return string_map

func _get_current_script():
	#if _current_script == null:
	_current_script = ScriptEditorRef.get_current_script()
	return _current_script

func _get_code_edit():
	if _current_code_edit == null:
		_current_code_edit = ScriptEditorRef.get_current_code_edit()
	return _current_code_edit


func _store_data_in_section(section, key, value, script, data_cache:Dictionary):
	if not data_cache.has(section):
		data_cache[section] = {}
	var section_data = data_cache.get(section)
	
	if script is String:
		script = load(script)
	var inh_scripts = UClassDetail.script_get_inherited_script_paths(script)
	CacheHelper.store_data(key, value, section_data, inh_scripts)

func _get_cached_data_in_section(section, key, data_cache:Dictionary):
	if not data_cache.has(section):
		return null
	var section_data = data_cache.get(section)
	
	return CacheHelper.get_cached_data(key, section_data)


class EditorSet:
	
	# Custom
	const HIDE_PRIVATE_PROP_SETTING = &"plugin/code_completion/property/hide_private_properties"
	
	const GLOBAL_CHECK_SETTING = &"plugin/code_completion/class_search/check_global_scripts"
	const GLOBAL_CHECK_INFO = {
	"name": GLOBAL_CHECK_SETTING,
	"type": TYPE_INT,
	"hint": PROPERTY_HINT_ENUM,
	"hint_string": "Global,Namespace,Off"
	}
	const SCRIPT_ALIAS_SETTING = &"plugin/code_completion/class_search/script_alias"
	const SCRIPT_ALIAS_INFO = {
	"name": SCRIPT_ALIAS_SETTING,
	"type": TYPE_INT,
	"hint": PROPERTY_HINT_ENUM,
	"hint_string": "Inherited Only,Recursive Preload,Off"
	}
	
	enum GlobalCheck{ # can be removed, but uesing for test duplicated enums
		GLOBAL,
		NAMESPACE,
		OFF
	}
	enum ScriptAlias{ # can be removed, but uesing for test duplicated enums
		INHERITED,
		PRELOADS,
		OFF
	}
	
