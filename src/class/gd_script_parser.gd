#! import

const UClassDetail = preload("res://addons/addon_lib/brohd/alib_editor/utils/src/u_class_detail.gd")
const USort = preload("res://addons/addon_lib/brohd/alib_runtime/utils/src/u_sort.gd")
const UString = preload("res://addons/addon_lib/brohd/alib_runtime/utils/src/u_string.gd")
const GlobalChecker = preload("res://addons/addon_lib/brohd/alib_runtime/misc/global_checker.gd")
const VariantChecker = preload("res://addons/addon_lib/brohd/alib_runtime/misc/variant_checker.gd")

const DataAccessSearch = preload("res://addons/code_completions/src/class/data_access_search.gd")
const CacheHelper = DataAccessSearch.CacheHelper

const TimeFunction = ALibRuntime.Utils.UProfile.TimeFunction

var data_access_search:DataAccessSearch

var code_completion_singleton

var _indent_size:int

var _current_script:GDScript
var _current_code_edit:CodeEdit
var _current_code_edit_text:String

var last_caret_line = -1

var script_data = {}
var _last_func = ""
var current_class = ""
var current_func = ""


var data_cache = {}
var completion_cache = {}

func _init() -> void:
	data_access_search = DataAccessSearch.new()
	_init_set_settings()


func _init_set_settings():
	var editor_settings = EditorInterface.get_editor_settings()
	_set_settings()
	editor_settings.settings_changed.connect(_set_settings)

func _set_settings():
	var editor_settings = EditorInterface.get_editor_settings()
	_indent_size = editor_settings.get_setting(EditorSet.INDENT_SIZE)


func on_script_changed(script):
	_current_code_edit = EditorInterface.get_script_editor().get_current_editor().get_base_editor()
	_current_script = EditorInterface.get_script_editor().get_current_script()
	_current_code_edit_text = _current_code_edit.text
	last_caret_line = -1
	
	if script != null:
		_get_script_inherited_members(script)
		map_script_members.call_deferred()


func on_completion_requested():
	_current_code_edit_text = _current_code_edit.get_text_for_code_completion()
	
	completion_cache.clear()
	var script_editor:CodeEdit = _get_code_edit()
	var current_caret_line = script_editor.get_caret_line()
	
	# do this everytime, it is fairly cheap
	_set_current_func_and_class(current_caret_line)


#region API

func get_global_class_path(_class_name:String):
	return data_cache[_Keys.GLOBAL_CLASS_REGISTRY].get(_class_name, "")

func get_func_args_and_return(_class:String, _func:String, infer_types:=false):
	if _class == null:
		_class = current_class
	if _func == null:
		_func = current_func
	
	var t = TimeFunction.new("Get func args anbd return")
	
	var valid_check = _check_var_in_body_valid(_func, _class)
	if valid_check == 0:
		return {}
	var vars_dict = _get_body_and_local_vars(_class, _func)
	var body_vars = vars_dict.body
	var source_check = _check_script_source_member_valid(_func, _class)
	if source_check != null:
		return source_check
	
	var func_data = body_vars.get(_func, {})
	var new_data = get_member_declaration(_func, func_data)
	
	if infer_types:
		var args = new_data.get(_Keys.FUNC_ARGS, {})
		for _nm in args.keys():
			var type = args.get(_nm)
			var inferred = _get_type_hint(type, _class, _func)
			args[_nm] = inferred
		
		new_data[_Keys.FUNC_ARGS] = args
	t.stop()
	if new_data == null:
		new_data = {}
	return new_data

func get_func_args(_class:String, _func:String):
	var infer = true
	var args = get_func_args_and_return(_class, _func, infer)
	if args.has(_Keys.FUNC_ARGS):
		return args.get(_Keys.FUNC_ARGS, {})
	return args # if not key, is property info

func get_func_return(_class:String, _func:String):
	var args = get_func_args_and_return(_class, _func)
	if args.has(_Keys.FUNC_RETURN):
		return args.get(_Keys.FUNC_RETURN, "")
	return args # if not key, is property info

func get_enum_members(enum_name:String, _class=null):
	if _class == null:
		_class = current_class
	var script_constants = get_script_constants(_class)
	var enum_data = script_constants.get(enum_name)
	if enum_data == null:
		printerr("Could not find enum: ", enum_name)
		return null
	var enum_member_data = get_member_declaration(enum_name, enum_data)
	if enum_member_data == null:
		return null
	return enum_member_data.get(_Keys.ENUM_MEMBERS, null)

func get_script_inherited_members():
	return _get_script_inherited_members(_get_current_script())

func get_script_constants(_class:String=""):
	if not script_data.has(_class):
		return {}
	if _class == "":
		return script_data[_class].get(_Keys.CONST, {})
	
	var constants = script_data[""].get(_Keys.CONST, {})
	var parts = _class.split(".")
	var working_path = ""
	for access_path in parts:
		if working_path == "":
			working_path = access_path
		else:
			working_path += "." + access_path
		
		constants.merge(script_data[working_path].get(_Keys.CONST, {}), true)
	
	return constants


func class_has_func(_func:String, _class:String) -> bool:
	if not script_data.has(_class):
		return false
	var class_data = script_data[_class][_Keys.CLASS_BODY]
	return class_data.has(_func)


#endregion


func map_script_members():
	_map_script_members()

func _map_script_members():
	var t = TimeFunction.new("NEW MAP GD", TimeFunction.TimeScale.USEC)
	
	#var script = _get_current_script()
	var script_editor = _get_code_edit()
	
	var access_path = ""
	var access_path_parts = []
	var member_data = {}
	var current_func_name = _Keys.CLASS_BODY
	member_data[access_path] = {}
	member_data[access_path][current_func_name] = {}
	member_data[access_path][_Keys.CONST] = {}
	member_data[_Keys.CLASS_MASK] = {}
	member_data[_Keys.CONST] = {}
	
	for i:int in range(script_editor.get_line_count()):
		var line_text = script_editor.get_line(i)
		var stripped = line_text.strip_edges()
		if stripped == "":
			member_data[_Keys.CLASS_MASK][i] = access_path
			continue
		#if stripped.find("#") > -1:
		stripped = stripped.get_slice("#", 0).strip_edges()
		if stripped == "":
			continue
		
		var indent = script_editor.get_indent_level(i)
		var access_path_indent = access_path_parts.size() * _indent_size
		if stripped != "":
			if access_path_indent > 0 and indent < access_path_indent:
				var iterations = (access_path_indent - indent) / _indent_size
				for x in range(iterations):
					var last_class = access_path_parts.pop_back()
					access_path = access_path.trim_suffix(last_class).trim_suffix(".")
				access_path_indent = access_path_parts.size() * _indent_size
		
		var _class = UString.get_class_name_in_line(stripped)
		if _class != "":
			access_path_parts.append(_class)
			access_path = _map_get_access_path(access_path, _class)
			member_data[access_path] = {}
			member_data[access_path][_Keys.CLASS_BODY] = {_Keys.DECLARATION: i}
			member_data[access_path][_Keys.CONST] = {}
			member_data[_Keys.CLASS_MASK][i] = access_path
			continue
		
		member_data[_Keys.CLASS_MASK][i] = access_path
		
		var func_name = UString.get_func_name_in_line(stripped)
		if func_name != "":
			current_func_name = func_name
			stripped = _get_multiline_func_call_editor(i)
			var var_type = &"func"
			if stripped.begins_with("static"):
				var_type = &"static func"
			var func_data = {
				_Keys.SNAPSHOT: stripped,
				_Keys.DECLARATION: i,
				_Keys.VAR_TYPE: var_type,
				#_Keys.CLASS: access_path, # add to body as lookup
				_Keys.INDENT: indent,
			}
			member_data[access_path][_Keys.CLASS_BODY][current_func_name] = func_data
			member_data[access_path][current_func_name] = {} # this is to store local vars
			continue
		
		if indent != access_path_indent:
			continue
		
		var var_check = UString.get_var_name_and_type_hint_in_line(stripped)
		if var_check != null:
			if indent != access_path_indent:
				continue # only map script members, no local vars
			else:
				current_func_name = _Keys.CLASS_BODY
			var var_type = &"var"
			if stripped.begins_with("static"):
				var_type = &"static var"
			var var_name = var_check[0]
			var type = var_check[1]
			var var_data = {
				_Keys.DECLARATION: i,
				_Keys.SNAPSHOT: stripped,
				_Keys.VAR_TYPE: var_type,
				_Keys.TYPE: type,
				_Keys.INDENT: indent,
			}
			member_data[access_path][current_func_name][var_name] = var_data
			continue
		
		var const_check = UString.get_const_name_and_type_in_line(stripped)
		if const_check != null:
			if indent != access_path_indent:
				continue
			#if indent == access_path_indent: # handle vars between funcs
			else:
				current_func_name = _Keys.CLASS_BODY
			
			var const_name = const_check[0]
			var type = const_check[1]
			var const_data = {
				_Keys.DECLARATION: i,
				_Keys.SNAPSHOT: stripped,
				_Keys.VAR_TYPE: &"const",
				_Keys.TYPE: type,
				_Keys.INDENT: indent,
			}
			member_data[access_path][current_func_name][const_name] = const_data
			member_data[access_path][_Keys.CONST][const_name] = const_data # not sure about this
			if type.begins_with("res://"):
				member_data[_Keys.CONST][type] = const_name
			continue
		
		if stripped.begins_with("enum "):
			var enum_text = _get_enum_editor(i)
			var enum_name = enum_text.trim_prefix("enum ").get_slice("{", 0).strip_edges()
			var data = {
				_Keys.DECLARATION: i,
				_Keys.SNAPSHOT: enum_text,
				_Keys.VAR_TYPE: &"enum",
				_Keys.INDENT: indent,
			}
			member_data[access_path][_Keys.CLASS_BODY][enum_name] = data
			member_data[access_path][_Keys.CONST][enum_name] = data
			continue
	
	script_data = member_data
	
	t.stop()
	return member_data


func _map_get_access_path(access_path:String, member_name:String):
	if access_path == "":
		access_path = member_name
	else:
		access_path = access_path + "." + member_name
	return access_path

func _map_check_dupe_local_var_name(var_name:String, dict:Dictionary):
	if dict.has(var_name):
		var count = 1
		var name_check = var_name
		while dict.has(name_check):
			name_check = var_name + "%" + str(count)
			count += 1
		var_name = name_check
	return var_name


func _set_current_func_and_class(start_idx:int):
	var t = TimeFunction.new("set current GD")
	var script_editor = _get_code_edit()
	
	var func_line:int = -1
	var func_name:String = ""
	var found_class = ""
	var in_body = true
	var current_line = start_idx
	while current_line >= 0:
		var line_text = script_editor.get_line(current_line)
		var stripped = line_text.strip_edges()
		var _class = UString.get_class_name_in_line(stripped)
		if _class != "":
			found_class = _class
			break
		func_name = UString.get_func_name_in_line(stripped)
		if func_name != "":
			current_func = func_name
			func_line = current_line
			in_body = false
			break
		if stripped != "" and not (line_text.begins_with("\t") or line_text.begins_with(" ")):
			break
		current_line -= 1
	
	var rebuild = false
	
	if in_body or start_idx == current_line: # this is typing in the func dec, queue rebuild
		current_func = _Keys.CLASS_BODY
	if _last_func == _Keys.CLASS_BODY and current_func != _Keys.CLASS_BODY:
		rebuild = true
	_last_func = current_func # when entering a local func from the body, rescan before mapping current
	
	if rebuild:
		_map_script_members()
	
	var access_path = found_class # if a class was found, start there
	var indent = script_editor.get_indent_level(current_line)
	while indent != 0 and current_line >= 0:
		current_line -= 1
		var line_text = script_editor.get_line(current_line)
		var stripped = line_text.strip_edges()
		var _class = UString.get_class_name_in_line(stripped)
		if _class != "":
			if access_path == "":
				access_path = _class
			else:
				access_path = _class + "." + access_path
			indent -= _indent_size
	
	current_class = access_path
	
	if not in_body:
		var t2 = TimeFunction.new("SCAN FUNC", 1)
		_map_scan_current_func(func_line)
		t2.stop()
	
	t.stop()


func _map_scan_current_func(line:int):
	var script_editor = _get_code_edit()
	var c_class = current_class
	var c_func_name = current_func
	
	if not script_data.has(c_class):
		script_data[c_class] = {_Keys.CLASS_BODY:{}}
	
	script_data[c_class][_Keys.CLASS_BODY][c_func_name] = {_Keys.DECLARATION:line, _Keys.FUNC_ARGS:{}}
	if c_func_name != _Keys.CLASS_BODY:
		script_data[c_class][c_func_name] = {}
	
	var temp_func_vars = {}
	var line_count = script_editor.get_line_count()
	var func_found = false
	var current_line = line
	while current_line < line_count:
		var line_text = script_editor.get_line(current_line)
		var stripped = line_text.strip_edges()
		var indent = script_editor.get_indent_level(current_line)
		var var_data = UString.get_var_name_and_type_hint_in_line(stripped)
		if var_data != null:
			var var_name = var_data[0]
			var_name = _map_check_dupe_local_var_name(var_name, temp_func_vars)
			var type_hint = var_data[1]
			if type_hint.find(".new(") > -1:
				type_hint = type_hint.substr(0, type_hint.rfind(".new("))
			var data:= {
				_Keys.DECLARATION: current_line,
				_Keys.SNAPSHOT: stripped,
				_Keys.VAR_TYPE: &"var",
				_Keys.TYPE: type_hint,
				_Keys.INDENT: indent,
			}
			script_data[c_class][c_func_name][var_name] = data
			temp_func_vars[var_name] = true
			current_line += 1
			continue
		
		var _class = UString.get_class_name_in_line(stripped)
		if _class != "":
			break
		var func_name = UString.get_func_name_in_line(stripped)
		if func_name != "":
			if not func_found:
				func_found = true
				stripped = _get_multiline_func_call_editor(current_line)
				var func_arg_data = _get_func_args_in_line(stripped)
				var func_args = func_arg_data.get(_Keys.FUNC_ARGS, {})
				for arg in func_args:
					var data = {
						_Keys.TYPE: func_args.get(arg),
						_Keys.VAR_TYPE: &"func_arg",
					}
					script_data[c_class][c_func_name][arg] = data
				
				script_data[c_class][_Keys.CLASS_BODY][c_func_name][_Keys.DECLARATION] = current_line
				script_data[c_class][_Keys.CLASS_BODY][c_func_name][_Keys.SNAPSHOT] = stripped
				script_data[c_class][_Keys.CLASS_BODY][c_func_name][_Keys.VAR_TYPE] = &"func"
				script_data[c_class][_Keys.CLASS_BODY][c_func_name][_Keys.INDENT] = indent
				
				script_data[c_class][c_func_name][_Keys.FUNC_ARGS] = func_arg_data.get(_Keys.FUNC_ARGS, {}) # can I do this different? Do I need to store?
				script_data[c_class][c_func_name][_Keys.FUNC_RETURN] = func_arg_data.get(_Keys.FUNC_RETURN, "")
				current_line += 1
				continue
			else:
				break
		
		current_line += 1



func _get_multiline_func_call_editor(current_line:int):
	var script_editor = _get_code_edit()
	var line_count = script_editor.get_line_count()
	var func_text = script_editor.get_line(current_line)
	func_text = UString.remove_comment(func_text).strip_edges()
	var open_count = func_text.count("(")
	var close_count = func_text.count(")")
	if open_count == close_count:
		return func_text.strip_edges()
	
	var i = current_line + 1
	while (open_count - close_count != 0) and i < line_count:
		var next_line = script_editor.get_line(i)
		next_line = UString.remove_comment(next_line).strip_edges()
		open_count += next_line.count("(")
		close_count += next_line.count(")")
		func_text += next_line
		i += 1
	
	var colon_i = func_text.rfind(":") + 1
	func_text = func_text.substr(0, colon_i)
	return func_text.strip_edges()

func _get_multiline_func_call_string(source_code:String):
	var new_line_i = source_code.find("\n")
	var func_text = source_code.substr(0, new_line_i)
	func_text = UString.remove_comment(func_text).strip_edges()
	var open_count = func_text.count("(")
	var close_count = func_text.count(")")
	if open_count == close_count:
		return func_text
	
	while (open_count - close_count != 0) and new_line_i > -1:
		var next_new_line_i = source_code.find("\n", new_line_i + 1)
		# handle error?
		var next_line = source_code.substr(new_line_i, next_new_line_i - new_line_i)
		next_line = UString.remove_comment(next_line).strip_edges()
		open_count += next_line.count("(")
		close_count += next_line.count(")")
		func_text += next_line
		new_line_i = next_new_line_i
	
	var colon_i = func_text.rfind(":") + 1
	func_text = func_text.substr(0, colon_i)
	
	return func_text.strip_edges()

func _get_func_args_in_line(stripped_text:String):
	var func_data = {_Keys.FUNC_ARGS:{}}
	var open_paren = stripped_text.find("(")
	var close_paren = stripped_text.rfind(")")
	if stripped_text.count("(") > 1:
		#var string_map = UString.get_string_map(stripped_text)
		var string_map = get_string_map(stripped_text)
		open_paren = stripped_text.find("(")
		close_paren = string_map.bracket_map.get(open_paren)
		if close_paren == null:
			return {}
	
	open_paren += 1
	var args = stripped_text.substr(open_paren, close_paren - open_paren)
	if args.find(",") > -1:
		args = args.split(",", false)
	else:
		args = [args]
	for arg in args:
		if arg == "":
			continue
		var dummy_string = "var " + arg.strip_edges()
		var var_data = UString.get_var_name_and_type_hint_in_line(dummy_string)
		var var_nm = var_data[0]
		var type_hint = var_data[1]
		func_data[_Keys.FUNC_ARGS][var_nm] = type_hint
	
	var return_idx = stripped_text.find("->")
	if return_idx > -1:
		var return_type = stripped_text.get_slice("->", 1)
		return_type = return_type.get_slice(":", 0).strip_edges()
		func_data[_Keys.FUNC_RETURN] = return_type
	return func_data

func _get_enum_editor(current_line:int):
	var script_editor = _get_code_edit()
	var line_count = script_editor.get_line_count()
	var enum_text = script_editor.get_line(current_line)
	enum_text = UString.remove_comment(enum_text).strip_edges()
	var open_count = enum_text.count("{")
	var close_count = enum_text.count("}")
	if open_count == close_count:
		return enum_text.strip_edges()
	
	var found_close = false
	var i = current_line + 1
	while not found_close and i < line_count:
		var next_line = script_editor.get_line(i)
		next_line = UString.remove_comment(next_line).strip_edges()
		var close_idx = next_line.find("}")
		if close_idx > -1:
			found_close = true
			next_line = next_line.substr(0, close_idx + 1)
		enum_text += next_line
		i += 1
	
	return enum_text.strip_edges()

func _get_enum_string(source_code:String):
	var new_line_i = source_code.find("\n")
	var enum_text = source_code.substr(0, new_line_i)
	enum_text = UString.remove_comment(enum_text).strip_edges()
	var open_count = enum_text.count("{")
	var close_count = enum_text.count("}")
	if open_count == close_count:
		return enum_text.strip_edges()
	
	var found_close = false
	while not found_close and new_line_i > -1:
		var next_new_line_i = source_code.find("\n", new_line_i + 1)
		var next_line = source_code.substr(new_line_i, next_new_line_i - new_line_i)
		next_line = UString.remove_comment(next_line).strip_edges()
		var close_idx = next_line.find("}")
		if close_idx > -1:
			found_close = true
			next_line = next_line.substr(0, close_idx + 1)
		enum_text += next_line
		new_line_i = next_new_line_i
	
	return enum_text.strip_edges()

func _get_enum_members_in_line(stripped_text:String) -> Dictionary:
	var members = stripped_text.get_slice("{", 1)
	members = members.get_slice("}", 0).strip_edges()
	var members_array
	if members.find(",") > -1:
		members_array = members.split(",", false)
	else:
		members_array = [members]
	
	var enum_data = {}
	for i in range(members_array.size()):
		var m = members_array[i]
		m.strip_edges()
		enum_data[m] = i
		#members_array[i] = m
	
	#return PackedStringArray(members_array)
	return enum_data


#region Var Lookup

func get_var_type(var_name:String, _func=null, _class=null):
	if _class == null:
		_class = current_class
	if _func == null:
		_func = current_func
	
	var dot_idx = var_name.find(".")
	var string_map
	
	var first_var = var_name
	if dot_idx != -1:
		string_map = get_string_map(var_name)
		first_var = UString.get_member_access_front(var_name, string_map)
		if first_var == var_name: # false alarm, likely due to brackets, dealt with in UString
			dot_idx = -1
	
	var t = TimeFunction.new("SOURCE CHECK")
	
	var source_check = _check_script_source_member_valid(first_var, _class)
	if source_check != null:
		var prop_string = _property_info_to_type(source_check)
		if prop_string == "":
			return var_name
		print("VALID SOURCE")
		if dot_idx != -1:
			var_name = prop_string + "." + UString.trim_member_access_front(var_name, string_map)
		else:
			var_name = prop_string
		return var_name
	t.stop()
	
	var t2 = TimeFunction.new("RAW TYPE")
	var type_hint = _get_raw_type(first_var, _func, _class)
	t2.stop()
	if type_hint == "":
		return var_name
	
	var t3 = TimeFunction.new("TYPE HINT")
	#print("GET VAR TYPE RAW: ", type_hint, " VarName: %s, Class: %s, Func: %s" % [var_name, _class, _func])
	type_hint = _get_type_hint(type_hint, _class, _func)
	t3.stop()
	if dot_idx != -1:
		var_name = type_hint + "." + UString.trim_member_access_front(var_name, string_map)
	else:
		var_name = type_hint
	
	#print("GET VAR TYPE INFERRED: ", type_hint, " FINAL ", var_name)
	return var_name

func _check_script_source_member_valid(first_var:String, _class:String):
	if first_var == "":
		return null
	var access_name = first_var
	if first_var.find("(") > -1:
		access_name = first_var.substr(0, first_var.find("("))
	
	var script_checks = completion_cache.get_or_add(_Keys.SCRIPT_SOURCE_CHECK, {})
	var _class_dict = script_checks.get_or_add(_class, {})
	if _class_dict.has(first_var):
		print("GET CACHED SCRIPT CHECK")
		return _class_dict[access_name]
	
	var in_body_valid = _check_var_in_body_valid(first_var, _class)
	var in_body_vars = in_body_valid > 0
	if not in_body_vars:
		completion_cache[_Keys.SCRIPT_SOURCE_CHECK][_class][access_name] = null
		return null
	
	var vars_dict = _get_body_and_local_vars(_class, _Keys.CLASS_BODY)
	var body_vars = vars_dict.body
	var local_vars = vars_dict.local
	var data = body_vars.get(access_name)
	if data == null:
		printerr("IN BODY VAR BUT DATA NULL: ", access_name)
		completion_cache[_Keys.SCRIPT_SOURCE_CHECK][_class][access_name] = null
		return null
	
	var current_script = _get_current_script()
	var snapshot = data.get(_Keys.SNAPSHOT)
	var var_type = data.get(_Keys.VAR_TYPE)
	var indent = data.get(_Keys.INDENT)
	var source_snapshot = _check_script_source_member_declaration(access_name, current_script.source_code, indent, var_type)
	var t = TimeFunction.new("SOURCE INTERNAL")
	
	if snapshot == source_snapshot:
		if _class != "":
			current_script = get_script_member_info_by_path(current_script, _class, ["const"], false)
		var property_info = get_script_member_info_by_path(current_script, access_name)
		completion_cache[_Keys.SCRIPT_SOURCE_CHECK][_class][access_name] = property_info
		t.stop()
		return property_info
	
	completion_cache[_Keys.SCRIPT_SOURCE_CHECK][_class][access_name] = null
	return null


func _get_raw_type(var_name:String, _func:String, _class:String):
	var in_body_valid = _check_var_in_body_valid(var_name, _class)
	var vars_dict = _get_body_and_local_vars(_class, _func)
	var body_vars = vars_dict.body
	var local_vars = vars_dict.local
	var in_body_vars = in_body_valid > 0
	# Vars are valid at this point.
	
	if var_name.find("(") > -1:
		var_name = var_name.substr(0, var_name.find("("))
		var func_return = _get_func_return_type(var_name, body_vars)
		return func_return
	
	
	var var_access_name = _get_local_var_access_name(var_name, local_vars)
	var in_local_vars = local_vars.has(var_access_name)
	
	if in_local_vars:
		var data = local_vars.get(var_access_name)
		var dec_line = data.get(_Keys.DECLARATION)
		var var_type = data.get(_Keys.VAR_TYPE)
		if var_type == &"func_arg": # this means local var from func args
			return data.get(_Keys.TYPE)
		var script_editor = _get_code_edit()
		if dec_line <= script_editor.get_caret_line(): # if not, it may be body var
			var member_data = get_member_declaration(var_name, data)
			if member_data == null:
				printerr("Could not get: ", var_name)
				return var_name
			return member_data.get(_Keys.TYPE, "")
	if in_body_vars:
		var data = body_vars.get(var_name)
		var member_data = get_member_declaration(var_name, data)
		if member_data == null:
			printerr("Could not get: ", var_name)
			return var_name
		return member_data.get(_Keys.TYPE, "")
	
	if not (in_local_vars or in_body_vars):
		if _is_class_name_valid(var_name):
			return var_name
		return _get_inherited_member_type(var_name)
	
	return ""

func _get_inherited_member_type(var_name:String):
	var inherited_members = _get_script_inherited_members(_get_current_script())
	var member_info = inherited_members.get(var_name)
	if member_info == null:
		return var_name
	return property_info_to_type(member_info)

func _get_inherited_member_property_info(var_name:String):
	var inherited_members = _get_script_inherited_members(_get_current_script())
	return inherited_members.get(var_name, var_name)

func _get_func_return_type(raw_func_call, body_vars):
	var global_check = GlobalChecker.get_global_return_type(raw_func_call)
	if global_check != null:
		return global_check
	var data = body_vars.get(raw_func_call, {}) # default {} allows check line to run the rescan
	var func_data = get_member_declaration(raw_func_call, data)
	if func_data == null:
		return ""
	var type = func_data.get(_Keys.FUNC_RETURN, "")
	return type


func _get_type_hint(type_hint:String, _class:String, _func:String):
	var in_body_valid = _check_var_in_body_valid(type_hint, _class)
	var vars_dict = _get_body_and_local_vars(_class, _func)
	var body_vars = vars_dict.body
	var local_vars = vars_dict.local # local not used, can remove?
	var in_body_vars = in_body_valid > 0
	var in_local_vars = local_vars.has(type_hint)
	
	# Vars are valid at this point.
	
	if VariantChecker.check_type(type_hint):
		return type_hint
	if type_hint == "true" or type_hint == "false":
		return "bool"
	elif type_hint.is_valid_int():
		return "int"
	elif type_hint.is_valid_float():
		return "float"
	elif type_hint.begins_with("["):
		return "Array"
	elif type_hint.begins_with("{"):
		return "Dictionary"
	elif type_hint.begins_with("&"):
		return "StringName"
	elif type_hint.begins_with("^"):
		return "NodePath"
	elif type_hint.begins_with('"') or type_hint.begins_with("'"):
		return "String"
	
	if type_hint.find(".new(") > -1:
		type_hint = type_hint.substr(0, type_hint.rfind(".new("))
		return type_hint
	
	var is_func_call = false
	if type_hint.ends_with(")"):
		is_func_call = true
	
	if not is_func_call:
		if _is_class_name_valid(type_hint):
			return type_hint
	# end easy checks
	
	
	if is_func_call:
		var b = _infer_func_type(type_hint, body_vars)
		return b
	
	var dot_idx = type_hint.find(".")
	
	var constant_map = get_script_constants(current_class)
	print(constant_map)
	if constant_map.has(type_hint):
		var map_data = constant_map.get(type_hint)
		#var data = constant_map.get(type_hint)
		var data = get_member_declaration(type_hint, map_data)
		var type = data.get(_Keys.TYPE, type_hint)
		return type
		return type_hint
	
	var current_script = _get_current_script()
	var member_info = get_script_member_info_by_path(current_script, type_hint)#, ["property", "const"])
	print("YOU GOT THIS FAR NOW WHAT ", type_hint, " MEMBER INFO ", member_info)
	if member_info != null: # is local
		#if member_info is Dictionary:
			#var class_check = UClassDetail.get_script_from_property_info(member_info, current_script)
			#print(class_check)
			#pass
		return type_hint
	if dot_idx > -1: # hacky
		var string_map = get_string_map(type_hint)
		var first = UString.get_member_access_front(type_hint, string_map)
		member_info = get_script_member_info_by_path(current_script, first)
		print("YOU TRIED THIS, NOW WHAT ", type_hint, " MEMBER INFO ", member_info)
		if member_info != null: # is local
			#return first # why is this first?
			return type_hint
	
	#var constant_map = get_script_constants(current_class)
	#print(constant_map)
	#if constant_map.has(type_hint):
		#return type_hint
	
	return type_hint


func _infer_func_type(func_call:String, body_vars):
	var dot_idx = func_call.find(".")
	var raw_func_call = func_call.substr(0, func_call.rfind("(")) # may need to make a stringmap
	var global_check = GlobalChecker.get_global_return_type(raw_func_call)
	if global_check != null:
		return global_check
	
	if dot_idx == -1:
		if not body_vars.has(raw_func_call):
			var inherited = _get_inherited_member_type(raw_func_call)
			#print("Script func not mapped: ", raw_func_call, " inherited: ", inherited)
			return inherited
		var func_data = body_vars.get(raw_func_call)
		var check_data = get_member_declaration(raw_func_call, func_data)
		if check_data == null:
			return ""
		return check_data.get(_Keys.FUNC_RETURN, "")
	else:
		#print("INFER FUNC CALL: ", raw_func_call)
		raw_func_call = get_var_type(raw_func_call)
		#print("INFER FUNC CALL: ", raw_func_call)
		var member_info = get_script_member_info_by_path(_get_current_script(), raw_func_call, ["property", "const", "method"])
		if member_info == null:
			return ""
		var _class_name = member_info.get("return", {}).get("class_name", "")
		return _class_name
	return ""

func _get_local_var_access_name(var_name:String, local_vars:Dictionary):
	var script_editor = _get_code_edit()
	var var_access_name = var_name
	if local_vars.has(var_access_name + "%1"):
		var current_line = script_editor.get_caret_line()
		var count = -1
		while current_line >= 0:
			var line_text = script_editor.get_line(current_line)
			var stripped = line_text.strip_edges()
			var var_nm_check = UString.get_var_name_and_type_hint_in_line(stripped)
			if var_nm_check == null:
				current_line -= 1
				continue
			var found_name = var_nm_check[0]
			if found_name != "" and found_name == var_name:
				count += 1
				current_line -= 1
				continue
			if UString.get_func_name_in_line(stripped) != "":
				break
			current_line -= 1
		
		if count > 0:
			var_access_name = var_name + "%" + str(count)
	
	return var_access_name


func _get_body_and_local_vars(_class:String, _func:String):
	var class_vars = script_data.get(_class)
	var body_vars = class_vars.get(_Keys.CLASS_BODY)
	var local_vars:Dictionary
	if _func != _Keys.CLASS_BODY:
		var func_vars = class_vars.get(_func, {})
		local_vars = func_vars
	else:
		local_vars = {}
	return {"body":body_vars, "local":local_vars}


## 0 = Not in body. 1 = In body and valid. 2 = In body, but not valid.
func _check_var_in_body_valid(var_name, _class):
	var body_vars = script_data[_class][_Keys.CLASS_BODY]
	var in_body_vars = body_vars.has(var_name) # only local vars will have modified name
	if var_name.find("(") > -1:
		var_name = var_name.substr(0, var_name.find("("))
		in_body_vars = body_vars.has(var_name)
	if in_body_vars:
		var data = body_vars.get(var_name)
		var valid_declaration = check_member_declaration(var_name, data)
		if not valid_declaration:
			printerr("TRIGGERING REBUILD")
			_map_script_members() # signal dirty?
			_set_current_func_and_class(_get_code_edit().get_caret_line())
			return 2
		return 1
	return 0


func check_member_declaration(member_name:String, map_data):
	var t = TimeFunction.new("CHECK MEMBER")
	var snapshot = map_data.get(_Keys.SNAPSHOT, "")
	var var_type = map_data.get(_Keys.VAR_TYPE)
	var indent = map_data.get(_Keys.INDENT)
	
	var stripped = _check_script_source_member_declaration(member_name, _current_code_edit_text, indent, var_type, &"editor")
	t.stop()
	
	print("SNAPPY MATCH ",snapshot == stripped)
	print(snapshot)
	print(stripped)
	if snapshot != stripped:
		return false
	return true


func get_member_declaration(member_name:String, map_data:Dictionary):
	var var_type = map_data.get(_Keys.VAR_TYPE)
	var indent = map_data.get(_Keys.INDENT)
	if indent == null:
		print("INDENT NULL ", member_name)
		return null
	print(map_data)
	var declarations = completion_cache.get_or_add(_Keys.SCRIPT_DECLARATIONS_DATA, {})
	var member_name_dict = declarations.get_or_add(member_name, {})
	if member_name_dict.has(indent):
		return member_name_dict[indent]
	
	var stripped = _check_script_source_member_declaration(member_name, _current_code_edit_text, indent, var_type, &"editor", true)
	print(stripped)
	var data
	if var_type == &"var":
		var var_data = UString.get_var_name_and_type_hint_in_line(stripped)
		if var_data != null:
			var type_hint = var_data[1]
			data = {
				#_Keys.DECLARATION: current_line,
				_Keys.SNAPSHOT: stripped,
				_Keys.TYPE: type_hint,
			}
	elif var_type == &"const":
		var const_data = UString.get_const_name_and_type_in_line(stripped)
		if const_data != null:
			var type_hint = const_data[1]
			data = {
				#_Keys.DECLARATION: current_line,
				_Keys.SNAPSHOT: stripped,
				_Keys.TYPE: type_hint,
			}
	elif var_type == &"func":
		var func_name = UString.get_func_name_in_line(stripped)
		if func_name != "":
			var func_args = _get_func_args_in_line(stripped)
			data = {
				#_Keys.DECLARATION: current_line,
				_Keys.SNAPSHOT: stripped,
				_Keys.FUNC_ARGS: func_args.get(_Keys.FUNC_ARGS, {}),
				_Keys.FUNC_RETURN: func_args.get(_Keys.FUNC_RETURN, ""),
			}
	elif var_type == &"enum":
		if stripped.begins_with("enum "):
			var enum_members = _get_enum_members_in_line(stripped)
			data = {
				_Keys.SNAPSHOT: stripped,
				_Keys.ENUM_MEMBERS: enum_members,
			}
	
	
	
	completion_cache[_Keys.SCRIPT_DECLARATIONS_DATA][member_name][indent] = data
	return data


func _check_script_source_member_declaration(var_name:String, text:String, indent:int, member_hint:=&"var", text_source:=&"source", reverse:=false):
	var declarations = completion_cache.get_or_add(_Keys.SCRIPT_DECLARATIONS_TEXT, {})
	var source_dict = declarations.get_or_add(text_source, {})
	var member_name_dict = source_dict.get_or_add(var_name, {})
	if member_name_dict.has(indent):
		print("GOT CACHED DECLARATION")
		return member_name_dict[indent]
	
	var prefix:String
	var search_string:String
	if member_hint == &"var":
		prefix = "var "
	elif member_hint == &"static var":
		prefix = "static var "
	elif member_hint == &"const":
		prefix = "const "
	elif member_hint == &"func":
		prefix = "func "
	elif member_hint == &"static func":
		prefix = "static func "
	elif member_hint == &"enum":
		prefix = "enum "
	
	if search_string == null:
		return ""
	search_string = prefix + var_name
	
	var t = TimeFunction.new("Check Source", TimeFunction.TimeScale.USEC)
	
	var indent_space = ""
	for i in range(_indent_size):
		indent_space += " "
	
	var var_declaration_idx:int = -1
	if reverse:
		var caret_idx = text.find("\uFFFF") # from cursor check behind for latest
		var_declaration_idx = text.rfind(search_string, caret_idx)
		if var_declaration_idx == -1:
			var_declaration_idx = text.find(search_string, caret_idx)
	else:
		var_declaration_idx = text.find(search_string)
	if var_declaration_idx == -1:
		return ""
	
	var source_code_len = text.length()
	while var_declaration_idx > -1:
		var search_len = var_name.length() + 1
		if var_declaration_idx + prefix.length() + search_len > source_code_len:
			break
		var candidate_check = text.substr(var_declaration_idx + prefix.length(), search_len)
		print(candidate_check)
		if candidate_check.is_valid_ascii_identifier():
			var_declaration_idx = text.find(search_string, var_declaration_idx + search_len)
		else:
			var new_line_idx = text.rfind("\n", var_declaration_idx) + 1
			var white_space:String = text.substr(new_line_idx, var_declaration_idx - new_line_idx)
			white_space = white_space.replace("\t", indent_space)
			var indent_count = white_space.count(" ")
			prints(indent_count, indent)
			if indent_count != indent:
				var_declaration_idx = text.find(search_string, var_declaration_idx + search_len)
			else:
				break
	
	
	var new_line_idx = text.rfind("\n", var_declaration_idx)
	if new_line_idx == -1:
		new_line_idx = 0
	
	var var_declaration:String
	if member_hint == &"func":
		var source_at_var = text.substr(new_line_idx + 1) # 1 to go on the other side of the \n
		print(var_declaration_idx)
		var_declaration = _get_multiline_func_call_string(source_at_var)
	elif member_hint == &"enum":
		var source_at_var = text.substr(new_line_idx + 1) # 1 to go on the other side of the \n
		var_declaration = _get_enum_string(source_at_var)
	else:
		var_declaration = text.substr(new_line_idx, text.find("\n", new_line_idx + 1) - new_line_idx + 1)
		if var_declaration.find(";") > -1:
			var_declaration = var_declaration.get_slice(";", 0)
	
	var stripped = var_declaration.strip_edges()
	t.stop()
	completion_cache[_Keys.SCRIPT_DECLARATIONS_TEXT][text_source][var_name][indent] = stripped
	return stripped


#endregion


func property_info_to_type(property_info) -> String:
	var type = _property_info_to_type(property_info)
	return type

func _property_info_to_type(property_info) -> String:
	print("_property_info_to_type: ", property_info)
	var search_data = property_info
	var preload_map = get_preload_map()
	if property_info is Dictionary:
		#print("PROPERTY INFO: ", property_info)
		if property_info.has("return"):
			property_info = property_info.get("return", {})
		
		if property_info.has("class_name"):
			var _class = property_info.get("class_name")
			if _class == "":
				var type = property_info.get("type")
				return type_string(type)
			
			# This may be not needed..
			if not _class.begins_with("res://"):
				return _class
			var class_path = _class
			var access_name = ""
			if _class.find(".gd.") > -1:
				class_path = _class.substr(0, _class.find(".gd.") + 3) # + 3 to keep ext
				access_name = _class.substr(_class.find(".gd.") + 4) # + 4 to omit ext
			
			var const_name = preload_map.get(class_path)
			if const_name:
				if access_name == "":
					return const_name
				else:
					return const_name + "." + access_name
			# /This may be not needed..
			
			return _class # return class name as path or class to process elsewhere
		
		return ""
	
	elif property_info is GDScript:
		var member_path = UClassDetail.script_get_member_by_value(_get_current_script(), property_info)
		if member_path != null:
			return member_path
		
		var path = property_info.resource_path
		var const_name = preload_map.get(path)
		if const_name:
			return const_name
	
	#var member_path = get_access_path(search_data, UClassDetail._MEMBER_ARGS, "")
	printerr("UNHANDLED PROPERTY INFO OR UNFOUND: ", property_info)#, " MEMBER_PATH ", )
	#return member_path
	
	return ""



#region Script Inherited Members

func _get_script_inherited_members(script:GDScript):
	var cached_data = CacheHelper.get_cached_data(_Keys.SCRIPT_INHERITED_MEMBERS, data_cache)
	if cached_data != null:
		return cached_data
	
	var base_script = script.get_base_script()
	if base_script == null:
		return {}
	
	var inherited_members = UClassDetail.script_get_all_members(base_script, UClassDetail.IncludeInheritance.SCRIPTS_ONLY)
	var inh_paths = UClassDetail.script_get_inherited_script_paths(base_script)
	CacheHelper.store_data(_Keys.SCRIPT_INHERITED_MEMBERS, inherited_members, data_cache, inh_paths)
	return inherited_members

func get_preload_map():
	var script = _get_current_script()
	var inh_preloads = _get_inherited_preload_map(script)
	
	var constants = script_data.get(_Keys.CONST, {})
	inh_preloads.merge(constants)
	return inh_preloads

func _get_inherited_preload_map(script:GDScript):
	var cached_data = CacheHelper.get_cached_data(script.resource_path, data_cache)
	if cached_data != null:
		return cached_data
	
	var base_script = script.get_base_script()
	if base_script == null:
		return {}
	var map := {}
	var preloads = UClassDetail.script_get_preloads(base_script)
	for nm in preloads.keys():
		var pl_script = preloads[nm]
		map[pl_script.resource_path] = nm
	var inh_paths = UClassDetail.script_get_inherited_script_paths(base_script)
	CacheHelper.store_data(script.resource_path, map, data_cache, inh_paths)
	return map

func get_script_member_info_by_path(script:GDScript, member_path:String, member_hints:=UClassDetail._MEMBER_ARGS, check_global:=true):
	return UClassDetail.get_member_info_by_path(script, member_path, member_hints, false, false, false, check_global)

#endregion


#func get_access_path(data,
					#member_hints:=["const"],
					#class_hint:="",
					#script_alias_set:=DataAccessSearch.ScriptAlias.INHERITED,
					#global_check_set:=DataAccessSearch.GlobalCheck.GLOBAL):
	#
	#return _get_access_path(data, member_hints, class_hint, script_alias_set, global_check_set)
#
#func _get_access_path(data,
					#member_hints:=["const"],
					#class_hint:="",
					#script_alias_set:=DataAccessSearch.ScriptAlias.INHERITED,
					#global_check_set:=DataAccessSearch.GlobalCheck.GLOBAL):
	#
	#
	#data_access_search.set_global_check_setting(global_check_set)
	#data_access_search.set_script_alias_setting(script_alias_set)
	#
	#
	#if not data_cache.has(_Keys.GLOBAL_PATHS):
		#data_cache[_Keys.GLOBAL_PATHS] = {}
	#data_access_search.set_data_cache(data_cache[_Keys.GLOBAL_PATHS])
	#
	#var result = data_access_search.get_access_path(data, member_hints, class_hint)
	#return result

func _get_global_class_paths():
	var global_classes = UClassDetail.get_all_global_class_paths()
	data_cache[_Keys.GLOBAL_CLASS_REGISTRY] = global_classes


func _get_current_script():
	if _current_script == null:
		_current_script = EditorInterface.get_script_editor().get_current_script()
	return _current_script

func _get_code_edit():
	if _current_code_edit == null:
		_current_code_edit = EditorInterface.get_script_editor().get_current_editor().get_base_editor()
	return _current_code_edit





func _is_class_name_valid(_class_name):
	if _class_name.find(".") > -1:
		_class_name = _class_name.substr(0, _class_name.find("."))
	if ClassDB.class_exists(_class_name):
		return true
	var current_script = _get_current_script()
	var base = current_script.get_instance_base_type()
	if (ClassDB.class_has_enum(base, _class_name) or ClassDB.class_has_integer_constant(base, _class_name) or 
	ClassDB.class_has_method(base, _class_name) or ClassDB.class_has_signal(base, _class_name)):
		return true
	#var members = get_script_inherited_members() # TEST this must only check preloads maybe
	#if members.has(_class_name):
		#return true
	var global_class_list = UClassDetail.get_all_global_class_paths()
	if global_class_list.has(_class_name):
		return true
	return false

func get_string_map(text):
	return code_completion_singleton.get_string_map(text)



class _Keys:
	# map keys
	const DECLARATION = &"%dec_line%"
	const INDENT = &"%indent%"
	const SNAPSHOT = &"snapshot"
	const VAR_TYPE = &"%var_type%"
	const CLASS_BODY = &"%body%"
	const CLASS_MASK = &"%class_mask%"
	const CONST = &"%const%"
	const FUNC_ARGS = &"%func_args%"
	const FUNC_RETURN = &"%func_return%"
	const TYPE = &"%type%"
	const ENUM_MEMBERS = &"%enum_members%"
	
	# data cache keys
	const SCRIPT_PRELOADS = &"ScriptPreloads"
	const SCRIPT_INHERITED_MEMBERS = &"ScriptInheritedMembers"
	const GLOBAL_PATHS = &"GlobalPaths"
	const GLOBAL_CLASS_REGISTRY = &"GlobalClassRegistry"
	
	# code completion keys
	const SCRIPT_SOURCE_CHECK = &"ScriptSourceChecks"
	const SCRIPT_DECLARATIONS_TEXT = &"ScriptDeclarationsText"
	const SCRIPT_DECLARATIONS_DATA = &"ScriptDeclarationsData"
	
	
	#const CLASS = &"%class%"
	#const INFERRED_TYPE = &"%inferred_type%"
	
	#const LOCAL_VARS = &"%local_vars%"

class EditorSet:
	# Editor
	const INDENT_SIZE = &"text_editor/behavior/indent/size"
