const UClassDetail = preload("res://addons/addon_lib/brohd/alib_editor/utils/src/u_class_detail.gd")
const USort = preload("res://addons/addon_lib/brohd/alib_runtime/utils/src/u_sort.gd")
const UString = preload("res://addons/addon_lib/brohd/alib_runtime/utils/src/u_string.gd")
const GlobalChecker = preload("res://addons/addon_lib/brohd/alib_runtime/misc/global_checker.gd")
const VariantChecker = preload("res://addons/addon_lib/brohd/alib_runtime/misc/variant_checker.gd")

const DataAccessSearch = preload("res://addons/code_completions/src/class/data_access_search.gd")
const CacheHelper = DataAccessSearch.CacheHelper

const TimeFunction = ALibRuntime.Utils.UProfile.TimeFunction

var data_access_search:DataAccessSearch

var _indent_size:int

var _current_script:GDScript
var _current_code_edit:CodeEdit

var last_caret_line = -1

var script_data = {}
var _last_func = ""
var current_class = ""
var current_func = ""


var data_cache = {}

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
	last_caret_line = -1
	
	if script != null:
		print("SCRIPT CHANGEWD")
		_get_script_inherited_members(script)
		map_script_members.call_deferred()

func on_completion_requested():
	var script_editor:CodeEdit = _get_code_edit()
	var current_caret_line = script_editor.get_caret_line()
	
	# do this everytime, it is fairly cheap
	_set_current_func_and_class(current_caret_line)


func get_func_args_and_return(_class:String, _func:String, infer_types:=false):
	if _class == null:
		_class = current_class
	if _func == null:
		_func = current_func
	var vars_dict = _get_body_and_local_vars(_class, _func)
	var body_vars = vars_dict.body
	var valid_check = _check_var_in_body_valid(_func, _class, _func, body_vars)
	if valid_check == 2:
		vars_dict = _get_body_and_local_vars(_class, _func)
		body_vars = vars_dict.body
	if valid_check == 0:
		return {}
	
	var func_data = body_vars.get(_func, {})
	var new_data = get_member_declaration(_func, func_data, {})
	
	if infer_types:
		var args = new_data.get(_Keys.FUNC_ARGS, {})
		for _nm in args.keys():
			var type = args.get(_nm)
			var inferred = _get_type_hint(type, _class, _func)
			args[_nm] = inferred
		new_data[_Keys.FUNC_ARGS] = args
	
	if new_data == null:
		new_data = {}
	return new_data

func get_func_args(_class:String, _func:String):
	var infer = true
	var args = get_func_args_and_return(_class, _func, infer).get(_Keys.FUNC_ARGS, {})
	return args

func get_func_return(_class:String, _func:String):
	return get_func_args_and_return(_class, _func).get(_Keys.FUNC_RETURN, "")


func get_script_inherited_members():
	return _get_script_inherited_members(_get_current_script())

func get_script_constants(_class:String=""):
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
		
		constants.merge(script_data[working_path].get(_Keys.CONST, {}))
	
	return constants





func map_get_var_type(var_name:String):
	return get_var_type(var_name) # this can be renamed





func map_script_members():
	_map_script_members()

func _map_script_members():
	var t = TimeFunction.new("NEW MAP GD", TimeFunction.TimeScale.USEC)
	
	var script = _get_current_script()
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
		if stripped.find("#") > -1:
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
			var func_data = {
				_Keys.SNAPSHOT: line_text,
				_Keys.DECLARATION: i,
				_Keys.CLASS: access_path, # add to body as lookup
				_Keys.INDENT: indent,
			}
			member_data[access_path][_Keys.CLASS_BODY][current_func_name] = func_data # why 2 different?
			#member_data[access_path][current_func_name] = func_data
			continue
		
		if indent != access_path_indent:
			continue
		
		var var_check = UString.get_var_name_and_type_hint_in_line(stripped)
		if var_check != null:
			if indent != access_path_indent:
				continue
			#if indent == access_path_indent: # handle vars between funcs
			else:
				current_func_name = _Keys.CLASS_BODY
			
			#var var_name = _map_check_dupe_local_var_name(var_check[0], member_data[access_path][current_func_name])
			var var_name = var_check[0]
			var type = var_check[1]
			var var_data = {
				_Keys.DECLARATION: i,
				_Keys.SNAPSHOT: line_text,
				_Keys.CLASS: access_path,
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
				_Keys.SNAPSHOT: line_text,
				_Keys.CLASS: access_path,
				_Keys.TYPE: type,
				_Keys.INDENT: indent,
			}
			member_data[access_path][current_func_name][const_name] = const_data
			member_data[access_path][_Keys.CONST][const_name] = const_data # not sure about this
			if type.begins_with("res://"):
				member_data[_Keys.CONST][type] = const_name
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
	var t = TimeFunction.new("set current GD", 1)
	var script_editor = _get_code_edit()
	
	var func_line:int = -1
	var func_name:String = ""
	var found_class = ""
	var in_body = true
	var current_line = start_idx
	while current_line >= 0:
		var line_text = script_editor.get_line(current_line)
		#print("Line: %s, %s" % [current_line, line_text])
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
	
	
	if not in_body:
		var t2 = TimeFunction.new("SCAN FUNC", 1)
		_map_scan_current_func(current_line)
		t2.stop()
	
	var access_path = found_class # if a class was found, start there
	var indent = script_editor.get_indent_level(current_line)
	while indent != 0 and current_line >= 0:
		current_line -= 1
		var line_text = script_editor.get_line(current_line)
		var stripped = line_text.strip_edges()
		print(stripped)
		var _class = UString.get_class_name_in_line(stripped)
		
		if _class != "":
			if access_path == "":
				access_path = _class
			else:
				access_path = _class + "." + access_path
			indent -= _indent_size
	
	print("SCAN ACCESS PATH=", "body" if access_path == "" else access_path)
	current_class = access_path
	
	
	#if not in_body:
		#script_data[access_path][func_name][_Keys.DECLARATION] = func_line
	
	t.stop()


func _map_scan_current_func(line:int):
	var script_editor = _get_code_edit()
	var c_class = current_class
	var c_func_name = current_func
	#if c_func_name == "":
		#return
	
	if not script_data.has(c_class):
		print("WRITING CLASS ", c_class)
		script_data[c_class] = {_Keys.CLASS_BODY:{}}
	if not script_data[c_class].has(c_func_name):
		print("WRITING FUNC ", c_func_name)
		script_data[c_class][c_func_name] = {_Keys.DECLARATION:line, _Keys.FUNC_ARGS:{}}
	else: # just write a new one everytime?
		script_data[c_class][c_func_name] = {_Keys.DECLARATION:line, _Keys.FUNC_ARGS:{}}
	
	var temp_func_vars = {}
	var line_count = script_editor.get_line_count()
	var func_found = false
	var current_line = line
	while current_line < line_count:
		var line_text = script_editor.get_line(current_line)
		var stripped = line_text.strip_edges()
		var var_data = UString.get_var_name_and_type_hint_in_line(stripped)
		if var_data != null:
			var var_name = var_data[0]
			var_name = _map_check_dupe_local_var_name(var_name, temp_func_vars)
			var type_hint = var_data[1]
			if type_hint.find(".new(") > -1:
				type_hint = type_hint.substr(0, type_hint.rfind(".new("))
			var data:= {
				_Keys.DECLARATION: current_line,
				_Keys.SNAPSHOT: line_text,
				_Keys.TYPE: type_hint
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
				stripped = _get_multiline_func_call(current_line)
				var func_arg_data = _get_func_args_in_line(stripped)
				script_data[c_class][c_func_name][_Keys.DECLARATION] = current_line
				script_data[c_class][c_func_name][_Keys.SNAPSHOT] = stripped
				script_data[c_class][c_func_name][_Keys.FUNC_ARGS] = func_arg_data.get(_Keys.FUNC_ARGS, {})
				script_data[c_class][c_func_name][_Keys.FUNC_RETURN] = func_arg_data.get(_Keys.FUNC_RETURN, "")
				current_line += 1
				continue
			else:
				break
		
		current_line += 1



func _get_multiline_func_call(current_line:int):
	var script_editor = _get_code_edit()
	var line_count = script_editor.get_line_count()
	var func_text = script_editor.get_line(current_line)
	var open_count = func_text.count("(")
	var close_count = func_text.count(")")
	var i = current_line + 1
	while (open_count - close_count != 0) and i < line_count:
		var next_line = script_editor.get_line(i).strip_edges()
		open_count += next_line.count("(")
		close_count += next_line.count(")")
		func_text += next_line
		i += 1
	
	var string_map = UString.get_string_map(func_text)
	var idx = func_text.find("(")
	var close_paren = string_map.bracket_map.get(idx)
	if close_paren == null:
		print("MULTILINE ISSUE")
		return ""
	var colon_i = func_text.find(":", close_paren) + 1
	func_text = func_text.substr(0, colon_i)
	return func_text.strip_edges()


func _get_func_args_in_line(stripped_text:String):
	var func_data = {_Keys.FUNC_ARGS:{}}
	var open_paren = stripped_text.find("(")
	var close_paren = stripped_text.rfind(")")
	if stripped_text.count("(") > 1:
		var string_map = UString.get_string_map(stripped_text)
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


func get_var_type(var_name:String, _func=null, _class=null):
	if _class == null:
		_class = current_class
	if _func == null:
		_func = current_func
	
	var dot_idx = var_name.find(".")
	var type_hint
	if dot_idx != -1:
		var first_var = UString.get_member_access_front(var_name)
		type_hint = _get_raw_type(first_var, _func, _class)
		if type_hint == "":
			type_hint = first_var
	else:
		type_hint = _get_raw_type(var_name, _func, _class)
		if type_hint == "":
			type_hint = var_name
	
	if type_hint == "":
		return var_name
	
	print("GET VAR TYPE RAW: ", type_hint)
	type_hint = _get_type_hint(type_hint, _class, _func)
	print("GET VAR TYPE INFERRED: ", type_hint)
	
	if dot_idx != -1:
		var_name = type_hint + var_name.substr(dot_idx)
	else:
		var_name = type_hint
	
	return var_name

func _get_raw_type(var_name:String, _func:String, _class:String):
	var vars_dict = _get_body_and_local_vars(_class, _func)
	var body_vars = vars_dict.body
	var local_vars = vars_dict.local
	var in_body_valid = _check_var_in_body_valid(var_name, _class, _func, body_vars)
	if in_body_valid == 2:
		vars_dict = _get_body_and_local_vars(_class, _func)
		body_vars = vars_dict.body
		local_vars = vars_dict.local
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
		var member_data = get_member_declaration(var_name, data)
		return member_data.get(_Keys.TYPE, "")
	elif in_body_vars:
		var data = body_vars.get(var_name)
		var member_data = get_member_declaration(var_name, data)
		return member_data.get(_Keys.TYPE, "")
	
	print("IN LOCAL: %s IN BODY %s" % [in_local_vars, in_body_vars])
	
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


func _get_func_return_type(raw_func_call, body_vars):
	print("Checking a func in _map_get_var_type: ", raw_func_call)
	var global_check = GlobalChecker.get_global_return_type(raw_func_call)
	if global_check != null:
		print("FOUND GLOBAL")
		return global_check
	print("FUNC CALL ", raw_func_call, body_vars)
	var data = body_vars.get(raw_func_call, {}) # default {} allows check line to run the rescan
	var func_data = get_member_declaration(raw_func_call, data, body_vars)
	var type = func_data.get(_Keys.FUNC_RETURN, "")
	return type


func _get_type_hint(type_hint:String, _class:String, _func:String):
	var vars_dict = _get_body_and_local_vars(_class, _func)
	var body_vars = vars_dict.body
	var local_vars = vars_dict.local # local not used, can remove?
	var in_body_valid = _check_var_in_body_valid(type_hint, _class, _func, body_vars)
	if in_body_valid == 2:
		vars_dict = _get_body_and_local_vars(_class, _func)
		body_vars = vars_dict.body
		local_vars = vars_dict.local
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
	
	var dot_idx = type_hint.find(".")
	if is_func_call:
		return _infer_func_type(type_hint, body_vars)
	
	var current_script = _get_current_script()
	var member_info = UClassDetail.get_member_info_by_path(current_script, type_hint)#, ["property", "const"])
	print("YOU GOT THIS FAR NOW WHAT ", type_hint, " MEMBER INFO ", member_info, " IN SCOPE VARS: ", (local_vars.has(type_hint) or body_vars.has(type_hint)))
	if member_info != null: # is local
		return type_hint
	if dot_idx > -1: # hacky
		var first = UString.get_member_access_front(type_hint)
		member_info = UClassDetail.get_member_info_by_path(current_script, first)
		print("YOU TRIED THIS, NOW WHAT ", type_hint, " MEMBER INFO ", member_info, " IN SCOPE VARS: ", (local_vars.has(type_hint) or body_vars.has(type_hint)))
	if member_info != null: # is local
		return type_hint
	if not local_vars.has(type_hint) and not body_vars.has(type_hint):
		return ""
	return type_hint


func _infer_func_type(func_call:String, body_vars):
	var dot_idx = func_call.find(".")
	var raw_func_call = func_call.substr(0, func_call.rfind("(")) # may need to make a stringmap
	var global_check = GlobalChecker.get_global_return_type(raw_func_call)
	if global_check != null:
		return global_check
	
	if dot_idx == -1:
		if not body_vars.has(raw_func_call):
			print("Script func not mapped: ", raw_func_call)
			return ""
		var func_data = body_vars.get(raw_func_call)
		print("FUNC DATA IN INFER: ", func_data)
		var check_data = get_member_declaration(raw_func_call, func_data, {})
		if check_data == null:
			return ""
		print("Local func get: ", check_data.get(_Keys.FUNC_RETURN, ""))
		return check_data.get(_Keys.FUNC_RETURN, "")
	else:
		print("INFER FUNC CALL: ", raw_func_call)
		raw_func_call = get_var_type(raw_func_call)
		print("INFER FUNC CALL: ", raw_func_call)
		var member_info = UClassDetail.get_member_info_by_path(_get_current_script(), raw_func_call, ["property", "const", "method"])
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
		local_vars = class_vars.get(_func, {})
	else:
		local_vars = {}
	return {"body":body_vars, "local":local_vars}


## 0 = Not in body. 1 = In body and valid. 2 = In body, but not valid.
func _check_var_in_body_valid(var_name, _class, _func, body_vars):
	var in_body_vars = body_vars.has(var_name) # only local vars will have modified name
	if var_name.find("(") > -1:
		var_name = var_name.substr(0, var_name.find("("))
		in_body_vars = body_vars.has(var_name)
	if in_body_vars:
		var data = body_vars.get(var_name)
		var valid_declaration = check_member_declaration(var_name, data)
		if not valid_declaration:
			_map_script_members()
			_set_current_func_and_class(_get_code_edit().get_caret_line())
			return 2
		return 1
	return 0


func check_member_declaration(member_name:String, map_data):
	var script_editor = _get_code_edit()
	var line = map_data.get(_Keys.DECLARATION, script_editor.get_caret_line())
	var snapshot = map_data.get(_Keys.SNAPSHOT, "")
	var dec_line = script_editor.get_line(line)
	if snapshot != dec_line:
		return false
	return true

func get_member_declaration(member_name:String, map_data, in_scope_vars:={}):
	var t = TimeFunction.new("map_check_line_declaration", TimeFunction.TimeScale.USEC)
	var script_editor = _get_code_edit()
	var line = map_data.get(_Keys.DECLARATION, script_editor.get_caret_line())
	var dec_line = script_editor.get_line(line)
	var dec_line_stripped = dec_line.strip_edges()
	var member_hint = &"var"
	if dec_line_stripped.begins_with("func ") or dec_line_stripped.begins_with("static func "):
		member_hint = &"func"
	elif dec_line_stripped.begins_with("const "):
		member_hint = &"const"
	#prints("CHECK LINE", member_name, map_data, member_hint)
	var new_data = _get_member_declaration(dec_line, line, member_hint)
	t.stop()
	return new_data


func _get_member_declaration(line_text:String, current_line:int, member_hint:=&"var"):
	var stripped = line_text.strip_edges()
	if member_hint == &"var":
		var var_data = UString.get_var_name_and_type_hint_in_line(stripped)
		if var_data != null:
			var type_hint = var_data[1]
			var data = {
				_Keys.DECLARATION: current_line,
				_Keys.SNAPSHOT: line_text,
				_Keys.TYPE: type_hint,
				#_Keys.INFERRED_TYPE: inferred,
			}
			return data
	elif member_hint == &"const":
		var const_data = UString.get_const_name_and_type_in_line(stripped)
		if const_data != null:
			var type_hint = const_data[1]
			var data = {
				_Keys.DECLARATION: current_line,
				_Keys.SNAPSHOT: line_text,
				_Keys.TYPE: type_hint,
			}
			return data
	elif member_hint == &"func":
		var func_name = UString.get_func_name_in_line(stripped)
		if func_name != "":
			stripped = _get_multiline_func_call(current_line)
			# cache this?
			var func_args = _get_func_args_in_line(stripped)
			var data = {
				_Keys.DECLARATION: current_line,
				_Keys.SNAPSHOT: stripped,
				_Keys.FUNC_ARGS: func_args.get(_Keys.FUNC_ARGS, {}),
				_Keys.FUNC_RETURN: func_args.get(_Keys.FUNC_RETURN, ""),
			}
			return data


func property_info_to_type(property_info) -> String:
	var type = _property_info_to_type(property_info)
	return type

func _property_info_to_type(property_info) -> String:
	var search_data = property_info
	var preload_map = get_preload_map()
	if property_info is Dictionary:
		print("PROPERTY INFO: ", property_info)
		var _class = property_info.get("class_name")
		if _class == "":
			return ""
		if not _class.begins_with("res://"):
			return _class
		var class_path = _class
		var member_access = ""
		if class_path.rfind(".gd.") > -1:
			var sub_idx = _class.rfind(".gd.") + 3
			class_path = _class.substr(0, sub_idx)
			member_access = _class.substr(sub_idx + 1)
			print("TRIM ", class_path)
			print(member_access)
		else:
			print("NO ACCESS ", class_path)
		
		var const_name = preload_map.get(class_path)
		if const_name:
			return const_name if member_access == "" else const_name + "." + member_access
		search_data = load(class_path)
		if member_access !=  "":
			search_data = UClassDetail.get_member_info_by_path(search_data, member_access)
		
	elif property_info is GDScript:
		var path = property_info.resource_path
		var const_name = preload_map.get(path)
		if const_name:
			return const_name
	
	var member_path = get_access_path(search_data, UClassDetail._MEMBER_ARGS, "")
	printerr("UNHANDLED PROPERTY INFO OR UNFOUND: ", property_info, " MEMBER_PATH ", member_path)
	return member_path






#region Script Inherited Members

func _get_script_inherited_members(script:GDScript):
	var cached_data = CacheHelper.get_cached_data("inh", data_cache)
	if cached_data != null:
		return cached_data
	
	var base_script = script.get_base_script()
	if base_script == null:
		return {}
	
	var inherited_members = UClassDetail.script_get_all_members(base_script, UClassDetail.IncludeInheritance.SCRIPTS_ONLY)
	var inh_paths = UClassDetail.script_get_inherited_script_paths(base_script)
	CacheHelper.store_data("inh", inherited_members, data_cache, inh_paths)
	return inherited_members

func get_preload_map():
	var script = _get_current_script()
	var inh_preloads = _get_inherited_preload_map(script)
	
	var constants = script_data.get(_Keys.CONST, {})
	inh_preloads.merge(constants)
	return inh_preloads

func _get_inherited_preload_map(script:GDScript):
	var cached_data = CacheHelper.get_cached_data("preloads", data_cache)
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
	CacheHelper.store_data("preloads", map, data_cache, inh_paths)
	return map



#endregion


func get_access_path(data,
					member_hints:=["const"],
					class_hint:="",
					script_alias_set:=DataAccessSearch.ScriptAlias.INHERITED,
					global_check_set:=DataAccessSearch.GlobalCheck.GLOBAL):
	
	return _get_access_path(data, member_hints, class_hint, script_alias_set, global_check_set)

func _get_access_path(data,
					member_hints:=["const"],
					class_hint:="",
					script_alias_set:=DataAccessSearch.ScriptAlias.INHERITED,
					global_check_set:=DataAccessSearch.GlobalCheck.GLOBAL):
	
	
	data_access_search.set_global_check_setting(global_check_set)
	data_access_search.set_script_alias_setting(script_alias_set)
	
	
	if not data_cache.has("global_paths"):
		data_cache["global_paths"] = {}
	data_access_search.set_data_cache(data_cache["global_paths"])
	
	var result = data_access_search.get_access_path(data, member_hints, class_hint)
	return result



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





class _Keys:
	const DECLARATION = &"%dec_line%"
	const SNAPSHOT = &"snapshot"
	const CLASS = &"%class%"
	const CLASS_BODY = &"%body%"
	const CLASS_MASK = &"%class_mask%"
	const CONST = &"%const%"
	const FUNC_ARGS = &"%func_args%"
	const FUNC_RETURN = &"%func_return%"
	const TYPE = &"%type%"
	const INFERRED_TYPE = &"%inferred_type%"
	const INDENT = &"%indent%"
	const LOCAL_VARS = &"%local_vars%"

class EditorSet:
	# Editor
	const INDENT_SIZE = &"text_editor/behavior/indent/size"
