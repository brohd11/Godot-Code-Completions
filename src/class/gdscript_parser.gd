#! import-p UString,UClassDetail,

const UFile = preload("res://addons/addon_lib/brohd/alib_runtime/utils/src/u_file.gd")
const UClassDetail = preload("res://addons/addon_lib/brohd/alib_editor/utils/src/u_class_detail.gd")
const UString = preload("res://addons/addon_lib/brohd/alib_runtime/utils/src/u_string.gd")
const GlobalChecker = preload("res://addons/addon_lib/brohd/alib_runtime/misc/global_checker.gd")
const VariantChecker = preload("res://addons/addon_lib/brohd/alib_runtime/misc/variant_checker.gd")

const CacheHelper = preload("res://addons/addon_lib/brohd/alib_runtime/cache_helper/cache_helper.gd")

var code_completion_singleton

var _indent_size:int

var _current_script:GDScript
var _current_code_edit:CodeEdit
var _current_code_edit_text:String
var _current_code_edit_text_caret:int

var last_caret_line = -1
var _last_func = ""
var current_class = ""
var current_func = ""
var script_data = {}

#^ cache
var data_cache = {}
var completion_cache = {}

func _init() -> void:
	_init_set_settings()
	ScriptEditorRef.subscribe(ScriptEditorRef.Event.TEXT_CHANGED, _on_text_changed)

func _init_set_settings():
	var editor_settings = EditorInterface.get_editor_settings()
	_set_settings()
	editor_settings.settings_changed.connect(_set_settings)

func _set_settings():
	var editor_settings = EditorInterface.get_editor_settings()
	_indent_size = editor_settings.get_setting(EditorSet.INDENT_SIZE)

func on_script_changed(script):
	var script_editor = ScriptEditorRef.get_current_code_edit()
	if not is_instance_valid(script_editor):
		return
	_current_code_edit = ScriptEditorRef.get_current_code_edit()
	_current_script = ScriptEditorRef.get_current_script()
	_current_code_edit_text = _current_code_edit.get_text_for_code_completion()
	last_caret_line = -1
	if script != null:
		_get_script_inherited_members(script)
		map_script_members.call_deferred()

func _on_text_changed():
	var script_editor:CodeEdit = _get_code_edit()
	var current_caret_line = script_editor.get_caret_line()
	_set_current_func_and_class(current_caret_line, true) #^ set bool to true so only current func and class are updated


func on_completion_requested():
	_current_code_edit_text = _current_code_edit.get_text_for_code_completion()
	_current_code_edit_text_caret = _current_code_edit_text.find("\uFFFF")
	
	completion_cache.clear()
	var script_editor:CodeEdit = _get_code_edit()
	var current_caret_line = script_editor.get_caret_line()
	_set_current_func_and_class(current_caret_line)


#region API

## Function data from script or script editor if stale.
func get_func_args_and_return(_class:String, _func:String, infer_types:=false):
	if _class == null:
		_class = current_class
	if _func == null:
		_func = current_func
	
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
	
	if new_data == null:
		new_data = {}
	return new_data

## Get args of function from class. 
func get_func_args(_class:String, _func:String):
	var infer = true
	var args = get_func_args_and_return(_class, _func, infer)
	if args.has(_Keys.FUNC_ARGS):
		return args.get(_Keys.FUNC_ARGS, {})
	return args # if not key, is property info

## Get return of function from class. 
func get_func_return(_class:String, _func:String):
	var args = get_func_args_and_return(_class, _func)
	if args.has(_Keys.FUNC_RETURN):
		return args.get(_Keys.FUNC_RETURN, "")
	return args # if not key, is property info

## Get members of enum from declaration.
func get_enum_members(enum_name:String, _class=null):
	if _class == null:
		_class = current_class
	var script_constants = get_script_constants(_class)
	var enum_data = script_constants.get(enum_name)
	if enum_data == null:
		return null
	var enum_member_data = get_member_declaration(enum_name, enum_data)
	if enum_member_data == null:
		return null
	return enum_member_data.get(_Keys.ENUM_MEMBERS, null)


## Get constants for script. Acounts for inner classes.
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

## Check if class has function name.
func class_has_func(_func:String, _class:String) -> bool:
	if not script_data.has(_class):
		return false
	var class_data = script_data[_class][_Keys.CLASS_BODY]
	return class_data.has(_func)

#endregion

## Map members into tree. Runs when script is changed.
## Class -> Func -> Member
func map_script_members():
	_map_script_members()

func _map_script_members():
	var script_editor = _get_code_edit()
	#if not is_instance_valid(script_editor): #^ this is checked on script changed
		#script_data.clear()
		#return {}
	var access_path = ""
	var access_path_parts = []
	var member_data = {}
	var current_func_name = _Keys.CLASS_BODY
	member_data[access_path] = {}
	member_data[access_path][current_func_name] = {}
	member_data[access_path][_Keys.CONST] = {}
	member_data[_Keys.CLASS_MASK] = {}
	
	for i:int in range(script_editor.get_line_count()):
		var line_text = script_editor.get_line(i)
		var stripped = line_text
		stripped = stripped.get_slice("#", 0).strip_edges() # not string safe
		if stripped == "":
			member_data[_Keys.CLASS_MASK][i] = access_path
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
			stripped = _get_func_declaration_editor(i)
			var var_type = _Keys.VAR_TYPE_FUNC
			if stripped.begins_with("static"):
				var_type = _Keys.VAR_TYPE_STATIC_FUNC
			var func_data = {
				_Keys.SNAPSHOT: stripped,
				_Keys.DECLARATION: i,
				_Keys.VAR_TYPE: var_type,
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
			var var_type = _Keys.VAR_TYPE_VAR
			if stripped.begins_with("static"):
				var_type = _Keys.VAR_TYPE_STATIC_VAR
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
			else:
				current_func_name = _Keys.CLASS_BODY
			
			var const_name = const_check[0]
			var type = const_check[1]
			var const_data = {
				_Keys.DECLARATION: i,
				_Keys.SNAPSHOT: stripped,
				_Keys.VAR_TYPE: _Keys.VAR_TYPE_CONST,
				_Keys.TYPE: type,
				_Keys.INDENT: indent,
			}
			member_data[access_path][current_func_name][const_name] = const_data
			member_data[access_path][_Keys.CONST][const_name] = const_data
			continue
		
		if stripped.begins_with("enum "):
			var enum_text = _get_enum_editor(i)
			var enum_name = enum_text.trim_prefix("enum ").get_slice("{", 0).strip_edges()
			var data = {
				_Keys.DECLARATION: i,
				_Keys.SNAPSHOT: enum_text,
				_Keys.VAR_TYPE: _Keys.VAR_TYPE_ENUM,
				_Keys.TYPE: enum_name, # Just use name, it will be the type
				_Keys.INDENT: indent,
			}
			member_data[access_path][_Keys.CLASS_BODY][enum_name] = data
			member_data[access_path][_Keys.CONST][enum_name] = data
			continue
	
	script_data = member_data
	return member_data

## Add another member to access path.
func _map_get_access_path(access_path:String, member_name:String):
	if access_path == "":
		access_path = member_name
	else:
		access_path = access_path + "." + member_name
	return access_path

## Check if var name is present and increment if needed.
func _map_check_dupe_local_var_name(var_name:String, dict:Dictionary):
	if dict.has(var_name):
		var count = 1
		var name_check = var_name
		while dict.has(name_check):
			name_check = var_name + "%" + str(count)
			count += 1
		var_name = name_check
	return var_name

## Set current func and class, then scan the func for data.
func _set_current_func_and_class(start_idx:int, text_changed:=false):
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
		if stripped != "" and not (line_text.begins_with("\t") or line_text.begins_with(" ") or line_text.begins_with("#")):
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
	if current_line > 0:
		var indent = script_editor.get_indent_level(current_line)
		while indent != 0 and current_line > 0:
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
	
	if not text_changed: #^ text changed allow rebuild, but no need to scan func
		if not in_body:
			_map_scan_current_func(func_line, func_name)
	

## Scan current func for local vars and func data.
func _map_scan_current_func(line:int, current_func_name:String):
	var script_editor = _get_code_edit()
	var c_class = current_class
	var c_func_name = current_func_name # current_func
	
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
				_Keys.VAR_TYPE: _Keys.VAR_TYPE_VAR,
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
				stripped = _get_func_declaration_editor(current_line)
				var func_arg_data = _get_func_data_from_declaration(stripped)
				var func_args = func_arg_data.get(_Keys.FUNC_ARGS, {})
				for arg in func_args:
					var data = {
						_Keys.TYPE: func_args.get(arg),
						_Keys.VAR_TYPE: _Keys.VAR_TYPE_FUNC_ARG,
					}
					script_data[c_class][c_func_name][arg] = data
				
				script_data[c_class][_Keys.CLASS_BODY][c_func_name][_Keys.DECLARATION] = current_line
				script_data[c_class][_Keys.CLASS_BODY][c_func_name][_Keys.SNAPSHOT] = stripped
				script_data[c_class][_Keys.CLASS_BODY][c_func_name][_Keys.VAR_TYPE] = _Keys.VAR_TYPE_FUNC
				script_data[c_class][_Keys.CLASS_BODY][c_func_name][_Keys.INDENT] = indent
				
				script_data[c_class][c_func_name][_Keys.FUNC_ARGS] = func_arg_data.get(_Keys.FUNC_ARGS, {}) # can I do this different? Do I need to store?
				script_data[c_class][c_func_name][_Keys.FUNC_RETURN] = func_arg_data.get(_Keys.FUNC_RETURN, "")
				current_line += 1
				continue
			else:
				break
		
		current_line += 1

## Get func declaration string from script editor, accounts for multiline.
func _get_func_declaration_editor(current_line:int):
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

## Get func declaration string from file as text, accounts for multiline.
func _get_func_declaration_string(source_code:String):
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

## Get func args and return from declaration text.
func _get_func_data_from_declaration(stripped_text:String):
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

## Get enum declaration from script editor, accounts for multiline.
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

## Get enum declaration from file as text, accounts for multiline.
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

## Get members of an enum in it's declaration text.
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
	return enum_data


#region Var Lookup
## Get var type of member string. Break into parts then process if needed.
## ie. my_class.some_var.my_func() will have [method _get_var_type] ran on the first part, "my_class".
## The rest will be added to the string and checked that it has property info.
func get_var_type(var_name:String, _func=null, _class=null):
	if _class == null:
		_class = current_class
	if _func == null:
		_func = current_func
	
	var_name = var_name.trim_prefix("self.")
	var dot_idx = var_name.find(".")
	if dot_idx == -1: #^ simple case
		var var_type = _get_var_type(var_name, _func, _class)
		return var_type
	else: #^ infer the first, then add members, but get return of any method calls between
		var current_script = _get_current_script()
		var string_map = get_string_map(var_name)
		var member_parts = UString.split_member_access(var_name, string_map)
		var final_type_hint = ""
		for i in range(member_parts.size()):
			var part = member_parts[i]
			if i == 0:
				var var_type = _get_var_type(part, _func, _class)
				if var_type.begins_with("res://"):
					var tail = UString.trim_member_access_front(var_name, string_map)
					return var_type + "." + tail
				
				final_type_hint = var_type
				continue
			
			if part.find("(") > -1:
				part = part.get_slice("(", 0)
			else:
				var check = final_type_hint + "." + part
				var member_info = get_script_member_info_by_path(current_script, check)
				if member_info != null:
					final_type_hint = check
					continue
				else:
					#if part == "new": #^ assumes this is the new method, dealt with in get func call data
						#final_type_hint = check
					break
			
			var working_func_call = final_type_hint + "." + part
			print("WORK ", working_func_call)
			var member_info = get_script_member_info_by_path(current_script, working_func_call)
			if member_info == null:
				printerr("COULD NOT FIND MEMBER INFO: ", working_func_call)
				break
			
			var type = property_info_to_type(member_info) #^r can I clean this up a bit?
			if type == "": #^ is this ok? For if an enum is end of string, or other non property member
				printerr("type is blank")
				break
			elif type.begins_with("res://"):
				final_type_hint = type
				break #^ this break hasnt been an issue yet.. but could be
			else:
				if type.find(".") == -1:
					var global_path = UClassDetail.get_global_class_path(type)
					if global_path != "":
						final_type_hint = type
				else: #^ handle inner classes
					var first = UString.get_member_access_front(type)
					var global_path = UClassDetail.get_global_class_path(first)
					if global_path != "":
						final_type_hint = type
		
		return final_type_hint
	return var_name #^ should this be empty?

## Get raw type, then infer if possible.
func _get_var_type(var_name:String, _func, _class):
	var vars_dict = _get_body_and_local_vars(_class, _func)
	var local_var_in_scope = _check_local_var_scope(var_name, vars_dict.local)
	if not local_var_in_scope:
		var source_check = _check_script_source_member_valid(var_name, _class)
		if source_check != null: # early exit
			var prop_string = _property_info_to_type(source_check)
			if prop_string == "":
				return var_name
			return prop_string
	
	var type_hint = _get_raw_type(var_name, _func, _class)
	if type_hint == "":
		return "" #^ return empty string so a local var will not trigger a body var in lookup
	print("RAW ", type_hint)
	type_hint = _get_type_hint(type_hint, _class, _func)
	if type_hint == "":
		return var_name
	return type_hint


## Get raw type of var. This could be the raw decalaration as text or from property info.
##  ie. "var x = y", returns "y"
func _get_raw_type(var_name:String, _func:String, _class:String):
	var in_body_valid = _check_var_in_body_valid(var_name, _class)
	var vars_dict = _get_body_and_local_vars(_class, _func)
	var body_vars = vars_dict.body
	var local_vars = vars_dict.local
	var in_body_vars = in_body_valid > 0
	#^ Vars are valid at this point.
	#print("GET RAW TYPE ", var_name)
	if var_name.find("(") > -1: #^ this seems to only trigger with functions that are not in the source code yet
		var_name = var_name.substr(0, var_name.find("("))
		var func_return = _get_func_return_type(var_name, body_vars)
		return func_return
	
	var var_access_name = _get_local_var_access_name(var_name, local_vars)
	var in_scope_vars = _get_in_scope_body_and_local_vars(_class, _func)
	local_vars = in_scope_vars.local
	var in_local_vars = local_vars.has(var_access_name)
	if in_local_vars:
		var data = local_vars.get(var_access_name)
		var dec_line = data.get(_Keys.DECLARATION)
		var var_type = data.get(_Keys.VAR_TYPE)
		if var_type == _Keys.VAR_TYPE_FUNC_ARG: #^ this means local var from func args
			return data.get(_Keys.TYPE)
		var script_editor = _get_code_edit()
		if dec_line <= script_editor.get_caret_line(): # if not, it may be body var
			var member_data = get_member_declaration(var_name, data)
			if member_data == null:
				printerr("Could not get: ", var_name)
				return ""
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

## Convert raw type hint to actual type. ie. "var x = y", attempts to convert y -> Type
func _get_type_hint(type_hint:String, _class:String, _func:String):
	var in_body_valid = _check_var_in_body_valid(type_hint, _class)
	var var_dict = _get_body_and_local_vars(_class, _func)
	var access_name = _get_local_var_access_name(type_hint, var_dict.local)
	var in_scope_vars = _get_in_scope_body_and_local_vars(_class, _func)
	var body_vars = in_scope_vars.body
	var local_vars = in_scope_vars.local # local not used, can remove?
	var in_body_vars = in_body_valid > 0
	var in_local_vars = local_vars.has(access_name)
	#^ Vars are valid at this point.
	print("GET TYPE HINT ", type_hint)
	if type_hint.find(" as ") > -1:
		type_hint = type_hint.get_slice(" as ", 1).strip_edges()
	
	if VariantChecker.check_type(type_hint):
		return type_hint
	if type_hint.begins_with("res://"):
		return type_hint
	if type_hint.begins_with("uid:"):
		return UFile.uid_to_path(type_hint)
	
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
	
	if _is_class_name_valid(type_hint):
		return type_hint
	
	var dot_idx = type_hint.find(".")
	if dot_idx > -1:
		return get_var_type(type_hint, _func, _class)
	
	if type_hint.ends_with(")"):
		var raw_func_call = type_hint.substr(0, type_hint.find("("))
		return _get_func_return_type(raw_func_call, body_vars)
	
	#^ original _is_class_name_valid location
	#^ end easy checks
	
	if in_local_vars:
		var map_data = local_vars.get(access_name)
		var type = map_data.get(_Keys.TYPE) #^ get simple var type, call get_var_type?
		if type != null:
			type = get_var_type(type)
			return type
		return ""
	
	var constant_map = get_script_constants(current_class)
	if constant_map.has(type_hint):
		var resolved = resolve_full_const_type(type_hint)
		return resolved
	
	var current_script = _get_current_script()
	if _class != "":
		current_script = get_script_member_info_by_path(current_script, current_class)
		if current_script is not GDScript:
			return type_hint
	
	var member_info = get_script_member_info_by_path(current_script, type_hint)#, ["property", "const"])
	if member_info != null:
		var type = property_info_to_type(member_info)
		if type == "":
			return type_hint
		return type
	
	return type_hint


## Get property info of inherited var, return type as string.
func _get_inherited_member_type(var_name:String):
	var current_script = _get_current_script()
	if current_class != "":
		current_script = get_script_member_info_by_path(current_script, current_class)
		if current_script is not GDScript:
			return var_name
		printerr("GET INHERITED INNER CLASS: ", current_script.resource_path)
	
	var inherited_members = _get_script_inherited_members(current_script)
	var member_info = inherited_members.get(var_name)
	if member_info == null:
		return var_name
	var type = property_info_to_type(member_info)
	if type == "":
		return var_name
	return type

## Get func return from script editor text.
func _get_func_return_type(raw_func_call:String, body_vars):
	var global_check = GlobalChecker.get_global_return_type(raw_func_call)
	if global_check != null:
		return global_check
	
	if not body_vars.has(raw_func_call):
		var inherited = _get_inherited_member_type(raw_func_call)
		return inherited
	
	var func_data = body_vars.get(raw_func_call)
	var check_data = get_member_declaration(raw_func_call, func_data)
	if check_data == null: #^ old one returned func name here when calling from raw type
		return ""
	return check_data.get(_Keys.FUNC_RETURN, "")

## Check if other vars have same name in local vars. Determine which is the current.
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
			if var_nm_check != null:
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

## Get body and local vars of class and func. All local vars are included, not just in-scope.
## [method get_in_scope_body_and_local_vars] for in scope only.
func get_body_and_local_vars(_class:String, _func:String):
	return _get_body_and_local_vars(_class, _func)

func _get_body_and_local_vars(_class:String, _func:String):
	if not script_data.has(_class):
		_map_script_members()
	var class_vars = script_data.get(_class)
	var body_vars = class_vars.get(_Keys.CLASS_BODY)
	var local_vars:Dictionary
	if _func != _Keys.CLASS_BODY:
		var func_vars = class_vars.get(_func, {})
		local_vars = func_vars
	else:
		local_vars = {}
	return {"body":body_vars, "local":local_vars}

## Check if local var is in scope at current line.
func _check_local_var_scope(var_name:String, local_vars:Dictionary):
	var code_edit = _get_code_edit()
	var current_line = code_edit.get_caret_line()
	var current_indent = code_edit.get_indent_level(current_line)
	var current_access_indent = _get_current_access_indent() + _indent_size #^ + 4 to account for func body
	var current_branch_start = _get_current_branch_start()
	
	var access_name = _get_local_var_access_name(var_name, local_vars)
	var start_idx = 0
	if access_name.find("%") > -1:
		start_idx = access_name.get_slice("%", 1).to_int()
	
	for i in range(start_idx, -1, -1):
		var access = var_name
		if i > 0:
			access = access + "%" + str(i)
		if local_vars.has(access):
			var data = local_vars.get(access)
			var declaration = data.get(_Keys.DECLARATION)
			if declaration == null:
				continue
			if declaration <= current_line:
				var indent = data.get(_Keys.INDENT)
				if indent > current_access_indent and declaration < current_branch_start:
					continue
				if current_indent >= indent:
					return true
	return false


## Get where the current branch forks from the func body.
func _get_current_branch_start():
	var code_edit = _get_code_edit()
	var current_line = code_edit.get_caret_line()
	var current_indent = code_edit.get_indent_level(current_line)
	var current_access_indent = _get_current_access_indent() + _indent_size
	if current_indent == current_access_indent:
		return current_line
	
	var i = current_line
	while i >= 0:
		var line_text = code_edit.get_line(i)
		var stripped = line_text.strip_edges()
		if stripped == "":
			i -= 1
			continue
		stripped = stripped.get_slice("#", 0)
		if stripped == "":
			i -= 1
			continue
		var indent = code_edit.get_indent_level(i)
		if indent > current_indent:
			break
		current_indent = indent
		if current_indent == current_access_indent:
			break
		i -= 1
	return i


## Get body and local vars of class and func. Filters vars that are not in scope.
func get_in_scope_body_and_local_vars():
	return _get_in_scope_body_and_local_vars(current_class, current_func)

func _get_in_scope_body_and_local_vars(_class, _func): #^ possibly pass a varname? Could return it in dict with access name
	if completion_cache.has(_Keys.IN_SCOPE_VARS):
		return completion_cache[_Keys.IN_SCOPE_VARS]
	var vars = get_body_and_local_vars(_class, _func)
	var in_scope_vars = {}
	var code_edit = _get_code_edit()
	var current_line = code_edit.get_caret_line()
	var current_line_indent = code_edit.get_indent_level(current_line)
	var current_access_indent = _get_current_access_indent() + _indent_size
	var current_branch_start = _get_current_branch_start()
	for var_name in vars.local.keys():
		var data = vars.local.get(var_name)
		if data is not Dictionary:
			continue
		var var_type = data.get(_Keys.VAR_TYPE)
		if var_type == _Keys.VAR_TYPE_FUNC_ARG:
			in_scope_vars[var_name] = data
			continue
		var declaration = data.get(_Keys.DECLARATION)
		if declaration == null:
			continue
		var indent = data.get(_Keys.INDENT)
		#if indent > current_access_indent and declaration < current_branch_start:
		if indent > current_line_indent and declaration < current_branch_start: #^ switch to current line indent, I believe correct
			continue
		if declaration <= current_line:
			in_scope_vars[var_name] = data
	vars.local = in_scope_vars
	completion_cache[_Keys.IN_SCOPE_VARS] = vars
	return vars


## 0 = Not in body. 1 = In body and valid. 2 = In body, but not valid.
func _check_var_in_body_valid(var_name, _class):
	var body_vars = script_data[_class][_Keys.CLASS_BODY]
	var in_body_vars = body_vars.has(var_name) # only local vars will have modified name
	if var_name.find("(") > -1:
		var_name = var_name.substr(0, var_name.find("("))
		in_body_vars = body_vars.has(var_name)
	if in_body_vars:
		var data = body_vars.get(var_name)
		#var indent = data.get(_Keys.INDENT)
		#if indent == null: #^ this was to make sure func args were not passed, but should be fixed
			#var current_line_text = _get_current_line_text() 
			#if current_line_text.begins_with("func ") or current_line_text.begins_with("static func"):
				#return 0
		var valid_declaration = check_member_declaration_valid(var_name, data)
		if not valid_declaration:
			printerr("TRIGGERING REBUILD")
			_map_script_members() # signal dirty?
			_set_current_func_and_class(_get_code_edit().get_caret_line())
			return 2
		return 1
	return 0


## Check member declaration is the same in source code and script editor.
func check_member_declaration_valid(member_name:String, map_data):
	var snapshot = map_data.get(_Keys.SNAPSHOT, "")
	var var_type = map_data.get(_Keys.VAR_TYPE)
	var indent = map_data.get(_Keys.INDENT)
	var stripped = _get_member_declaration_from_text(member_name, _current_code_edit_text, indent, var_type, &"editor")
	if snapshot != stripped:
		return false
	return true

## Check that var declaration in script is equal to script editor text. If it is, return property info
## and early exit the parsing.
func _check_script_source_member_valid(first_var:String, _class:String):
	if first_var == "":
		return null
	var access_name = first_var
	if first_var.find("(") > -1:
		access_name = first_var.substr(0, first_var.find("("))
	
	var script_checks = completion_cache.get_or_add(_Keys.SCRIPT_SOURCE_CHECK, {})
	var _class_dict = script_checks.get_or_add(_class, {})
	if _class_dict.has(first_var):
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
	
	var source_snapshot = _get_member_declaration_from_text(access_name, current_script.source_code, indent, var_type)
	if snapshot == source_snapshot:
		if _class != "":
			current_script = get_script_member_info_by_path(current_script, _class, ["const"], false)
		var property_info = get_script_member_info_by_path(current_script, access_name)
		completion_cache[_Keys.SCRIPT_SOURCE_CHECK][_class][access_name] = property_info
		return property_info
	
	completion_cache[_Keys.SCRIPT_SOURCE_CHECK][_class][access_name] = null
	return null

## Get member declaration and parse for relevant data.
func get_member_declaration(member_name:String, map_data:Dictionary):
	var var_type = map_data.get(_Keys.VAR_TYPE)
	var indent = map_data.get(_Keys.INDENT)
	if indent == null:
		return null
	
	var declarations = completion_cache.get_or_add(_Keys.SCRIPT_DECLARATIONS_DATA, {})
	var member_name_dict = declarations.get_or_add(member_name, {})
	if member_name_dict.has(indent):
		return member_name_dict[indent]
	
	var stripped = _get_member_declaration_from_text(member_name, _current_code_edit_text, indent, var_type, &"editor", true)
	var data
	if var_type == _Keys.VAR_TYPE_VAR:
		var var_data = UString.get_var_name_and_type_hint_in_line(stripped)
		if var_data != null:
			var type_hint = var_data[1]
			data = {
				#_Keys.DECLARATION: current_line,
				_Keys.SNAPSHOT: stripped,
				_Keys.TYPE: type_hint,
			}
	elif var_type == _Keys.VAR_TYPE_CONST:
		var const_data = UString.get_const_name_and_type_in_line(stripped)
		if const_data != null:
			var type_hint = const_data[1]
			data = {
				#_Keys.DECLARATION: current_line,
				_Keys.SNAPSHOT: stripped,
				_Keys.TYPE: type_hint,
			}
	elif var_type == _Keys.VAR_TYPE_FUNC:
		var func_name = UString.get_func_name_in_line(stripped)
		if func_name != "":
			var func_args = _get_func_data_from_declaration(stripped)
			data = {
				#_Keys.DECLARATION: current_line,
				_Keys.SNAPSHOT: stripped,
				_Keys.FUNC_ARGS: func_args.get(_Keys.FUNC_ARGS, {}),
				_Keys.FUNC_RETURN: func_args.get(_Keys.FUNC_RETURN, ""),
			}
	elif var_type == _Keys.VAR_TYPE_ENUM:
		if stripped.begins_with("enum "):
			var enum_name = stripped.get_slice("enum ", 1).get_slice("{", 0).strip_edges()
			var enum_members = _get_enum_members_in_line(stripped)
			data = {
				_Keys.SNAPSHOT: stripped,
				_Keys.ENUM_MEMBERS: enum_members,
				_Keys.TYPE: enum_name,
			}
	
	completion_cache[_Keys.SCRIPT_DECLARATIONS_DATA][member_name][indent] = data
	return data


## Get the member's declaration from either source code or script editor.
func _get_member_declaration_from_text(var_name:String, text:String, indent:int, member_hint:=_Keys.VAR_TYPE_VAR, text_source:=&"source", reverse:=false):
	var declarations = completion_cache.get_or_add(_Keys.SCRIPT_DECLARATIONS_TEXT, {})
	var source_dict = declarations.get_or_add(text_source, {})
	var member_name_dict = source_dict.get_or_add(var_name, {})
	if member_name_dict.has(indent):
		return member_name_dict[indent]
	
	var prefix:String
	var search_string:String
	if member_hint == _Keys.VAR_TYPE_VAR:
		prefix = "var "
	elif member_hint == _Keys.VAR_TYPE_STATIC_VAR:
		prefix = "static var "
	elif member_hint == _Keys.VAR_TYPE_CONST:
		prefix = "const "
	elif member_hint == _Keys.VAR_TYPE_FUNC:
		prefix = "func "
	elif member_hint == _Keys.VAR_TYPE_STATIC_FUNC:
		prefix = "static func "
	elif member_hint == _Keys.VAR_TYPE_ENUM:
		prefix = "enum "
	
	if prefix == null:
		return ""
	search_string = prefix + var_name
	
	var indent_space = ""
	for i in range(_indent_size):
		indent_space += " "
	
	var var_declaration_idx:int = -1
	if reverse:
		if text_source == &"source":
			printerr("Can't run reverse member declaration search on source code. Need caret char from code edit method.")
			return ""
		#var caret_idx = text.find("\uFFFF") # from cursor check behind for latest
		var caret_idx = _current_code_edit_text_caret
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
		if candidate_check.is_valid_ascii_identifier():
			if not reverse:
				var_declaration_idx = text.find(search_string, var_declaration_idx + search_len)
			else:
				var_declaration_idx = text.rfind(search_string, var_declaration_idx - 1)
		else:
			var new_line_idx = text.rfind("\n", var_declaration_idx) + 1
			var white_space:String = text.substr(new_line_idx, var_declaration_idx - new_line_idx)
			white_space = white_space.replace("\t", indent_space)
			var indent_count = white_space.count(" ")
			if indent_count != indent:
				if not reverse:
					var_declaration_idx = text.find(search_string, var_declaration_idx + search_len)
				else:
					var_declaration_idx = text.rfind(search_string, var_declaration_idx - 1)
			else:
				break
	
	var new_line_idx = text.rfind("\n", var_declaration_idx)
	if new_line_idx == -1:
		new_line_idx = 0
	
	var var_declaration:String
	if member_hint == _Keys.VAR_TYPE_FUNC:
		var source_at_var = text.substr(new_line_idx + 1) # 1 to go on the other side of the \n
		var_declaration = _get_func_declaration_string(source_at_var)
	elif member_hint == _Keys.VAR_TYPE_ENUM:
		var source_at_var = text.substr(new_line_idx + 1) # 1 to go on the other side of the \n
		var_declaration = _get_enum_string(source_at_var)
	else:
		var_declaration = text.substr(new_line_idx, text.find("\n", new_line_idx + 1) - new_line_idx + 1)
		if var_declaration.find(";") > -1:
			var_declaration = var_declaration.get_slice(";", 0)
	var no_com = var_declaration.get_slice("#", 0) #^ may need string map?
	var stripped = no_com.strip_edges()
	completion_cache[_Keys.SCRIPT_DECLARATIONS_TEXT][text_source][var_name][indent] = stripped
	return stripped


#endregion

## Get a class_name from property info and convert to a type if possible.
## If method data, uses return data.
func property_info_to_type(property_info) -> String:
	var type = _property_info_to_type(property_info)
	return type

func _property_info_to_type(property_info) -> String:
	var preload_map = get_preload_map()
	if property_info is Dictionary:
		if property_info.has("return"):
			property_info = property_info.get("return", {})
		
		if property_info.has("class_name"):
			var _class = property_info.get("class_name")
			if _class == "":
				var type = property_info.get("type")
				return type_string(type)
			
			if not _class.begins_with("res://"):
				return _class
			
			var class_path = _class
			var const_name = preload_map.get(class_path)
			if const_name:
				return const_name
			
			#var class_path = _class #^ old version
			#var access_name = ""
			##if _class.find(".gd.") > -1: #^ maybe able comment this with preload map modified
				##class_path = _class.substr(0, _class.find(".gd.") + 3) # + 3 to keep ext
				##access_name = _class.substr(_class.find(".gd.") + 4) # + 4 to omit ext
			#var const_name = preload_map.get(class_path)
			#if const_name:
				#if access_name == "":
					#return const_name
				#else:
					#return const_name + "." + access_name
			
			return _class # return class name as path or class to process elsewhere
		
	elif property_info is GDScript:
		var member_path = UClassDetail.script_get_member_by_value(_get_current_script(), property_info)
		if member_path != null:
			return member_path
		
		var path = property_info.resource_path
		var const_name = preload_map.get(path)
		if const_name:
			return const_name
	
	printerr("UNHANDLED PROPERTY INFO OR UNFOUND: ", property_info)
	return ""



#region Script Inherited Members

## Get and cache the preloads of current scripts ancestors.
func _get_script_inherited_members(script:GDScript):
	var inherited_section = data_cache.get_or_add(_Keys.SCRIPT_INHERITED_MEMBERS, {})
	var cached_data = CacheHelper.get_cached_data(script.resource_path, inherited_section)
	if cached_data != null:
		return cached_data
	
	var base_script = script.get_base_script()
	if base_script == null:
		return {}
	
	var inherited_members = UClassDetail.script_get_all_members(base_script, UClassDetail.IncludeInheritance.SCRIPTS_ONLY)
	var inh_paths = UClassDetail.script_get_inherited_script_paths(base_script)
	CacheHelper.store_data(script.resource_path, inherited_members, inherited_section, inh_paths)
	return inherited_members

## Return dictionary of preload in current script [path, name]
func get_preload_map():
	var cached = completion_cache.get(_Keys.SCRIPT_FULL_PRELOAD_MAP)
	if cached != null:
		return cached
	
	var script = _get_current_script()
	var inh_preloads = _get_inherited_preload_map(script) #^ doesnt account for inner classes
	
	var constants = get_script_constants(current_class)
	for nm in constants.keys():
		var const_data = constants.get(nm)
		var type = const_data.get(_Keys.TYPE, "") as String
		if type == nm: #^ mainly for enums
			continue
		var resolved = _resolve_full_type(nm, constants)
		if resolved.begins_with("res://"):
			inh_preloads[resolved] = nm
		elif _is_class_name_valid(resolved):
			inh_preloads[resolved] = nm
	
	#for keys in inh_preloads.keys():
		#print(inh_preloads[keys], " -> ", keys)
	
	completion_cache[_Keys.SCRIPT_FULL_PRELOAD_MAP] = inh_preloads
	return inh_preloads

func resolve_full_const_type(var_name):
	var constants = get_script_constants(current_class)
	if not constants.has(var_name):
		return null
	var type = _resolve_full_type(var_name, constants)
	return type

func _resolve_full_type(var_name:String, constants_dict:Dictionary) -> String:
	var suffix = ""
	var current_alias = var_name
	var visited_aliases = {}
	while constants_dict.has(current_alias):
		if visited_aliases.has(current_alias): # If we have seen this alias before, we're in a loop.
			#printerr("Cycle detected in constant resolution! Alias '", current_alias, "' is part of a loop.")
			return "[CYCLE_ERROR:" + current_alias + "]" + suffix
		visited_aliases[current_alias] = true
		
		var data = constants_dict[current_alias]
		var full_definition: String = data.get(_Keys.TYPE)
		var dot_pos = full_definition.find(".")
		if dot_pos > -1:
			var next_alias = full_definition.substr(0, dot_pos)
			var new_suffix = full_definition.substr(dot_pos)
			suffix = new_suffix + suffix
			current_alias = next_alias
		else:
			if current_alias == full_definition:
				return current_alias + suffix
			current_alias = full_definition
	
	return current_alias + suffix

## Get preloads and convert to path as key dictionary.
func _get_inherited_preload_map(script:GDScript):
	var preload_section = data_cache.get_or_add(_Keys.SCRIPT_PRELOAD_MAP, {})
	var cached_data = CacheHelper.get_cached_data(script.resource_path, preload_section)
	if cached_data != null:
		return cached_data
	
	script = script.get_base_script()
	if script == null:
		return {}
	
	var map := {}
	var preloads = UClassDetail.script_get_preloads(script)
	for nm in preloads.keys():
		var pl_script = preloads[nm]
		map[pl_script.resource_path] = nm
	var inh_paths = UClassDetail.script_get_inherited_script_paths(script)
	CacheHelper.store_data(script.resource_path, map, preload_section, inh_paths)
	return map

## Get script member info, ignores Godot Native class inheritance properties.
func get_script_member_info_by_path(script:GDScript, member_path:String, member_hints:=UClassDetail._MEMBER_ARGS, check_global:=true):
	return UClassDetail.get_member_info_by_path(script, member_path, member_hints, false, false, false, check_global)

#endregion

## Get current class base indent.
func _get_current_access_indent():
	if current_class == "":
		return 0
	if current_class.find(".") == 0:
		return _indent_size
	else:
		return (current_class.count(".") + 1) * _indent_size

func _get_current_line_text():
	var script_editor = _get_code_edit()
	return script_editor.get_line(script_editor.get_caret_line())

func _get_current_script():
	if _current_script == null:
		_current_script = ScriptEditorRef.get_current_script()
	return _current_script

func _get_code_edit():
	if _current_code_edit == null:
		var script_ed = ScriptEditorRef.get_current_code_edit()
		if is_instance_valid(script_ed):
			_current_code_edit = script_ed
	return _current_code_edit

## Check that class name is Godot Native or member of the class. A valid user global class will also return true.
func _is_class_name_valid(_class_name, check_global:=true):
	if _class_name.find(".") > -1:
		_class_name = _class_name.substr(0, _class_name.find("."))
	if ClassDB.class_exists(_class_name):
		return true
	var base = _get_current_script().get_instance_base_type()
	if (ClassDB.class_has_enum(base, _class_name) or ClassDB.class_has_integer_constant(base, _class_name) or 
	ClassDB.class_has_method(base, _class_name) or ClassDB.class_has_signal(base, _class_name)):
		return true
	if check_global:
		if UClassDetail.get_global_class_path(_class_name) != "":
			return true
	return false

#^ utils - would put this in singleton but don't want to copy text again
## Return int, 0=false, 1=dict, 2=enum 
func is_caret_in_dict_or_enum():
	var caret = _current_code_edit_text_caret
	var open_idx = _current_code_edit_text.rfind("{", caret)
	if open_idx == -1:
		return 0
	var close_idx = _current_code_edit_text.rfind("}", caret)
	if close_idx < open_idx: #^ need to handle nested dictionaries
		var new_idx = _current_code_edit_text.rfind("\n", open_idx)
		var dict_declar = _current_code_edit_text.substr(new_idx, open_idx - new_idx).strip_edges()
		if dict_declar.begins_with("enum "):
			return 2
		return 1
	return 0



#^ singleton
## Get string map from singleton. Caches for duration of completion cycle.
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
	
	# var type
	const VAR_TYPE_FUNC_ARG = &"func_arg"
	const VAR_TYPE_STATIC_FUNC = &"static func"
	const VAR_TYPE_FUNC = &"func"
	const VAR_TYPE_STATIC_VAR = &"static var"
	const VAR_TYPE_VAR = &"var"
	const VAR_TYPE_CONST = &"const"
	const VAR_TYPE_ENUM = &"enum"
	
	
	# data cache keys
	const SCRIPT_PRELOAD_MAP = &"ScriptPreloadMap"
	const SCRIPT_INHERITED_MEMBERS = &"ScriptInheritedMembers"
	
	# code completion keys
	const SCRIPT_SOURCE_CHECK = &"ScriptSourceChecks"
	const SCRIPT_DECLARATIONS_TEXT = &"ScriptDeclarationsText"
	const SCRIPT_DECLARATIONS_DATA = &"ScriptDeclarationsData"
	const IN_SCOPE_VARS = &"InScopeVars"
	const SCRIPT_FULL_PRELOAD_MAP = &"FullPreloadMap"
	


class EditorSet:
	# Editor
	const INDENT_SIZE = &"text_editor/behavior/indent/size"
