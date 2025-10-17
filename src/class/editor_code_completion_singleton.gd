extends Singleton.RefCount
#! remote

const SCRIPT = preload("res://addons/code_completions/src/class/editor_code_completion_singleton.gd") #! ignore-remote

const UClassDetail = preload("res://addons/addon_lib/brohd/alib_editor/utils/src/u_class_detail.gd")
const USort = preload("res://addons/addon_lib/brohd/alib_runtime/utils/src/u_sort.gd")

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

enum TagLocation {
	START,
	END,
	ANY,
}

var _current_code_edit:CodeEdit
var _sort_queued:= false

var code_completions:Dictionary = {}

var peristent_cache:Dictionary = {}
var script_cache:Dictionary = {}
var completion_cache:Dictionary = {}

var last_caret_line:= -1

var assignment_regex:RegEx

func _init(plugin) -> void:
	_singleton_init()

func _ready() -> void:
	await get_tree().create_timer(1).timeout
	_set_code_edit(null)
	_connect_editor()


func _singleton_init():
	if not peristent_cache.has("tags"):
		peristent_cache["tags"] = {}
	if not peristent_cache.has("preload_typed_vars"):
		peristent_cache["preload_typed_vars"] = {}


func register_tag(prefix:String, tag:String, location:TagLocation=TagLocation.ANY):
	if not peristent_cache.tags.has(prefix):
		peristent_cache.tags[prefix] = {}
	
	if not peristent_cache.tags[prefix].has(tag):
		peristent_cache.tags[prefix][tag] = location
	else:
		print("Tag already registered: %s %s" % [prefix, tag])

func unregister_tag(prefix:String, tag:String):
	if not peristent_cache.tags.has(prefix):
		peristent_cache.tags[prefix] = {}
	
	if peristent_cache.tags[prefix].has(tag):
		peristent_cache.tags[prefix].erase(tag)
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
	EditorInterface.get_resource_filesystem().filesystem_changed.connect(_get_preload_typed_vars_fs_changed)

func _disconnect_editor():
	EditorInterface.get_script_editor().editor_script_changed.disconnect(_set_code_edit)
	EditorInterface.get_resource_filesystem().filesystem_changed.disconnect(_get_preload_typed_vars_fs_changed)

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


func _on_editor_script_changed(script):
	if script != null:
		get_preload_typed_vars(script)
	
	last_caret_line = -1
	script_cache.clear()
	script_cache["local_vars"] = {}
	
	for editor_code_completion in code_completions.keys():
		editor_code_completion._on_editor_script_changed(script)


func _on_code_completion_requested(script_editor:CodeEdit) -> void:
	var current_caret_line = script_editor.get_caret_line()
	if current_caret_line != last_caret_line:
		last_caret_line = current_caret_line
		var current_func_block = _scan_current_func_block_for_local_vars()
		script_cache["current_func"] = current_func_block
	
	completion_cache.clear()
	
	var has_tag = _tag_completion(script_editor)
	if has_tag:
		return
	
	for editor_code_completion in code_completions.keys():
		var handled = editor_code_completion._on_code_completion_requested(script_editor)
		if handled:
			return


func _tag_completion(script_editor:CodeEdit):
	var current_line = script_editor.get_caret_line()
	var caret_col = script_editor.get_caret_column()
	var current_line_text = script_editor.get_line(current_line)
	var tags = peristent_cache.tags.keys()
	if tags.is_empty():
		return false
	var tag_present = ""
	var tag_idx = -1
	for tag in tags:
		tag_idx = current_line_text.find(tag)
		if tag_idx > -1:
			tag_present = tag
			break
	if tag_idx == -1:
		return false
	
	if not string_safe_is_index_after_string(tag_present, current_line_text, caret_col):
		return
	
	var stripped = current_line_text.substr(tag_idx).strip_edges()
	var parts = stripped.split(" ", false)
	
	if parts.size() > 2:
		return false
	
	var icon = EditorInterface.get_editor_theme().get_icon("Script", "EditorIcons")
	var declared_tag_members = peristent_cache.tags.get(tag_present, {})
	for tag in declared_tag_members.keys():
		var location = declared_tag_members[tag]
		if location == TagLocation.START and tag_idx > 0:
			continue
		elif location == TagLocation.END and tag_idx == 0:
			continue
		script_editor.add_code_completion_option(CodeEdit.KIND_CONSTANT, tag, tag, Color.GRAY, icon)
	script_editor.update_code_completion_options(false)
	return true


const TimeFunction = ALibRuntime.Utils.UProfile.TimeFunction

func _get_preload_typed_vars_fs_changed():
	var current_script = EditorInterface.get_script_editor().get_current_script()
	get_preload_typed_vars(current_script)

func get_preload_typed_vars(top_script:GDScript):
	#var t = TimeFunction.new("Get Preloads", true, null, TimeFunction.TimeScale.USEC)
	
	var top_script_path = top_script.resource_path
	var current_script = top_script
	
	var preloads = {}
	var scripts = []
	while current_script != null:
		scripts.append(current_script)
		
		var constants = UClassDetail.script_get_all_constants(current_script)
		for c in constants:
			var val = constants.get(c)
			if val is GDScript:
				if val.resource_path != "":
					preloads[c] = val
		
		current_script = current_script.get_base_script()
	
	var preloaded_vars_dict = {"preloads": preloads}
	for script in scripts:
		var preloaded_vars = _map_script_preload_vars(script, preloads)
		preloaded_vars_dict.merge(preloaded_vars)
	
	peristent_cache["preload_typed_vars"][top_script_path] = preloaded_vars_dict
	
	#t.stop()


func _map_script_preload_vars(script:GDScript, preloads_dict:Dictionary):
	var preload_names = preloads_dict.keys()
	var var_type_dict = {}
	
	var lines = script.source_code.split("\n")
	for line_text in lines:
		if not line_text.begins_with("var "):
			continue
		
		var type = _get_var_type_in_line(line_text)
		if not type:
			continue
		if not type in preload_names:
			continue
		var nm = _get_var_name_in_line(line_text)
		if not nm:
			continue
		var_type_dict[nm] = type
	
	return var_type_dict

func _get_var_name_in_line(line_text:String):
	var var_dec = line_text.get_slice("var ", 1)
	var var_nm = var_dec.get_slice(":", 0).strip_edges()
	if var_nm.is_valid_ascii_identifier():
		return var_nm

func _get_var_type_in_line(line_text:String):
	if line_text.find(":") == -1:
		return
	var var_dec = line_text.get_slice("var ", 1)
	return _get_type_hint(var_dec)


func get_func_name_of_line(script_editor:CodeEdit, start_idx:int):
	var current_line = start_idx
	while current_line > 0:
		current_line -= 1
		var func_line_text = script_editor.get_line(current_line)
		if func_line_text == "":
			return ""
		var stripped = func_line_text.strip_edges()
		if not (stripped.begins_with("func ") and stripped.begins_with("static func ")):
			continue
		var func_name = func_line_text.get_slice("func ", 1).get_slice("(", 0)
		return func_name


func _scan_current_func_block_for_local_vars():
	#var t = ALibRuntime.Utils.UProfile.TimeFunction.new("SCAN BLOCK", true, null, 1)
	var script_editor = _get_code_edit()
	var current_script = EditorInterface.get_script_editor().get_current_script()
	var current_line = script_editor.get_caret_line()
	var func_name:String = ""
	while current_line > 0:
		var func_line_text:String = script_editor.get_line(current_line)
		var stripped = func_line_text.strip_edges()
		var begins_with_func = (stripped.begins_with("func ") or stripped.begins_with("static func "))
		if func_line_text != "" and not func_line_text.begins_with("\t") and not begins_with_func:
			return func_name
		
		if not begins_with_func:
			current_line -= 1
			continue
		
		func_name = func_line_text.get_slice("func ", 1).get_slice("(", 0)
		break
	
	if func_name == "":
		return func_name
	if not script_cache.has("local_vars"):
		script_cache["local_vars"] = {}
	if script_cache.local_vars.has(func_name):
		script_cache.local_vars.get(func_name).clear()
	var func_line = current_line
	var script_length = script_editor.get_line_count()
	while true:
		#current_line += 1 # at beginning to exclude found func
		if current_line > script_length:
			return func_name
		var line_text:String = script_editor.get_line(current_line)
		var stripped = line_text.strip_edges()
		if stripped.begins_with("func ") or stripped.begins_with("static func "):
			if current_line != func_line:
				#t.stop()
				return func_name
			else:
				_get_local_var_in_func(line_text, func_name, current_script)
				current_line += 1
				continue
			
		if line_text != "" and not line_text.begins_with("\t"):
			#t.stop()
			return func_name
		
		_get_local_var_in_line(line_text, func_name)
		current_line += 1
	#t.stop()
	return func_name

func _get_local_var_in_line(line_text:String, func_name:String):
	if line_text.find("\tvar ") == -1:
		return
	var type = _get_var_type_in_line(line_text)
	if not type:
		return
	var var_nm = _get_var_name_in_line(line_text)
	if not var_nm:
		return
	
	if not script_cache.local_vars.has(func_name):
		script_cache.local_vars[func_name] = {}
	script_cache.local_vars[func_name][var_nm] = type


func _get_local_var_in_func(line_text:String, func_name:String, script):
	var member_info = UClassDetail.get_member_info_by_path(script, func_name)
	if member_info == null:
		return
	
	var arg_array = member_info.get("args")
	
	for arg in arg_array:
		var var_nm = arg.get("name")
		var _class = arg.get("class_name", "")
		var type = arg.get("type")
		var type_hint = _class
		if _class == "":
			type_hint = type_string(type)
		
		if not script_cache.local_vars.has(func_name):
			script_cache.local_vars[func_name] = {}
		script_cache.local_vars[func_name][var_nm] = type_hint


func _get_type_hint(var_str:String): # for local vars
	if var_str.find(":") == -1:
		return
	var type_hint = var_str.get_slice(":", 1).strip_edges()
	var eq_idx = type_hint.find("=")
	if eq_idx == 0:
		type_hint = type_hint.get_slice("=", 1).strip_edges()
	elif eq_idx > -1:
		type_hint = type_hint.get_slice("=", 0).strip_edges()
	elif type_hint.find(" ") > -1:
		type_hint = type_hint.get_slice(" ", 0).strip_edges()
	
	if type_hint.find(".new(") > -1:
		type_hint = type_hint.substr(0, type_hint.rfind(".new("))
	elif type_hint.ends_with(")"):
		var method_call = type_hint.get_slice("(", 0)
		var current_script = EditorInterface.get_script_editor().get_current_script()
		var member_data = UClassDetail.get_member_info_by_path(current_script, method_call)
		if member_data == null:
			return
		var _return = member_data.get("return", {})
		var _class_name = _return.get("class_name", "")
		type_hint = _class_name
	
	return type_hint

func get_func_call_data(current_line_text:String):
	if completion_cache.has("func_call"):
		return completion_cache.get("func_call")
	var script_editor = _get_code_edit()
	if not is_instance_valid(script_editor):
		return {}
	var caret_col = script_editor.get_caret_column()
	
	var data = {}
	var open_i = current_line_text.rfind("(", caret_col)
	var closed_i = current_line_text.find(")", caret_col)
	if not (open_i != -1 and open_i < caret_col and closed_i != -1 and closed_i >= caret_col):
		return {}
	
	var func_name = current_line_text.substr(0, open_i)
	if func_name.find(" ") > -1:
		func_name = func_name.get_slice(" ", func_name.get_slice_count(" ") - 1)
	func_name = func_name.strip_edges()
	
	if open_i == 0 or not func_name.replace(".", "_").is_valid_ascii_identifier(): # should stop false 
		return {}
	
	var current_args = current_line_text.substr(open_i, closed_i)
	
	var current_arg_index = 0
	var adjusted_caret_col = caret_col - open_i
	while adjusted_caret_col >= 0:
		var char = current_args[adjusted_caret_col]
		if char == ",":
			current_arg_index += 1
		adjusted_caret_col -= 1
	
	current_args = current_args.trim_prefix("(").trim_suffix(")")#.strip_edges()
	if current_args.find(",") > -1:
		current_args = current_args.split(",", false)
	else:
		if current_args != "":
			current_args = [current_args]
		else:
			current_args = []
	for i in range(current_args.size()):
		var arg = current_args[i]
		arg = arg.strip_edges()
		current_args[i] = arg
	
	data["name"] = func_name
	data["args"] = current_args
	data["current_arg_index"] = current_arg_index
	completion_cache["func_call"] = data
	return data



func get_assignment_at_cursor(line_text: String, caret_col: int):
	if not is_instance_valid(assignment_regex):
		assignment_regex = RegEx.new()
		# LHS (Group 1): Optional 'var', the variable name, and an optional type hint.
		# Operator (Group 2): Handles '==', ':=', and '='.
		# RHS (Group 3): Everything up to the next semicolon.
		var pattern = "((?:var\\s+)?[\\w\\d_.]+(?:\\s*:\\s*[\\w\\d_]+)?)\\s*(==|:=|=)\\s*(.*?)(?=\\s+(?:or|and)\\s+|;|:|$)"
		assignment_regex.compile(pattern)
	
	var matches = assignment_regex.search_all(line_text)
	if matches.is_empty():
		return null
		
	for i in range(matches.size() - 1, -1, -1):
		var _match = matches[i]
		if _match.get_start() < caret_col:
			var lhs = _match.get_string(1).strip_edges()
			var operator = _match.get_string(2).strip_edges()
			var rhs = _match.get_string(3).strip_edges()
			return { "lhs": lhs, "operator": operator, "rhs": rhs }
	return null

static func string_safe_is_index_after_string(str_to_find:String, line_text:String, index_to_check:int):
	var found_index = line_text.rfind(str_to_find, index_to_check)
	if found_index == -1:
		return false
	
	var in_string = false
	var string_type = null
	var index = 0
	while index < found_index:
		var char = line_text[index]
		index += 1
		if char == "#" and not in_string:
			break
		if char == '"' or char == "'":
			if in_string:
				if char == string_type:
					in_string = false
				
			else:
				string_type = char
				in_string = true
	
	return not in_string # if in string, not a comment


static func _get_code_edit():
	if EditorInterface.get_script_editor().get_current_editor():
		return EditorInterface.get_script_editor().get_current_editor().get_base_editor()
