@tool
extends EditorCodeCompletion
#! import-p UString,UClassDetail,Assignment,FuncCall,

const CacheHelper = EditorCodeCompletionSingleton.CacheHelper

const ENUM_SUFFIX = EditorCodeCompletionSingleton.EditorGDScriptParser.GDScriptParser.Keys.ENUM_PATH_SUFFIX

var enum_enable:= false
var show_member_suggestions:= false
var show_alias_only:=false

var data_cache = {}

var completion_cache = {}

var access_object:CaretContext.AccessObject
var function_access_object:CaretContext.AccessObject
var function_object:String
var argument_access_object:CaretContext.AccessObject

var comp_object


func _singleton_ready():
	_init_set_settings()

func _init_set_settings():
	var ed_settings = EditorInterface.get_editor_settings()
	if not ed_settings.has_setting(EditorSet.ENUM_ENABLE):
		ed_settings.set_setting(EditorSet.ENUM_ENABLE, false)
	if not ed_settings.has_setting(EditorSet.SHOW_MEMBER_SUGGESTIONS):
		ed_settings.set_setting(EditorSet.SHOW_MEMBER_SUGGESTIONS, false)
	if not ed_settings.has_setting(EditorSet.SHOW_ALIAS_ONLY):
		ed_settings.set_setting(EditorSet.SHOW_ALIAS_ONLY, false)
	
	_set_settings()
	ed_settings.settings_changed.connect(_set_settings)

func _set_settings():
	var ed_settings = EditorInterface.get_editor_settings()
	enum_enable = ed_settings.get_setting(EditorSet.ENUM_ENABLE)
	show_member_suggestions = ed_settings.get_setting(EditorSet.SHOW_MEMBER_SUGGESTIONS)
	show_alias_only = ed_settings.get(EditorSet.SHOW_ALIAS_ONLY)

func _on_code_completion_requested(_script_editor:CodeEdit) -> bool:
	if not enum_enable:
		return false
	var caret_context = get_caret_context()
	if caret_context.token_state != TokenState.NONE:
		return false
	if caret_context.expression_before_caret.length() > 5:
		return false
	
	comp_object = null
	
	if caret_context.expression_state == ExpressionState.ASSIGNMENT or caret_context.expression_state == ExpressionState.COMPARISON:
		return _operator(caret_context)
	elif caret_context.scope_state == ScopeState.MATCH_BRANCH:
		return _match_branch(caret_context)
	elif caret_context.is_in_function_call():
		return _function_call(caret_context)
	return false
	


func _operator(caret_context:CaretContext):
	var op_data = caret_context.get_operation_data()
	comp_object = op_data
	return _process_identifier(op_data.left_type)

func _match_branch(caret_context:CaretContext):
	var match_type = caret_context.get_match_block_data()
	if not match_type.is_valid:
		return false
	if caret_context.get_line_indent() != match_type.indent + caret_context.get_indent_size():
		return false
	if  caret_context.is_in_multiline_expression() or caret_context.code_context_find(":") != -1:
		return false
	comp_object = match_type
	
	return _process_identifier(match_type.type)

func _is_function_call():
	return comp_object is CaretContext.FunctionCallData

func _function_call(caret_context:CaretContext):
	var func_data = caret_context.get_function_call_data()
	var current_arg = func_data.func_get_current_arg()
	comp_object = func_data
	return _process_identifier(current_arg.type)


func _process_identifier(identifier:String):
	if identifier.ends_with(ENUM_SUFFIX):
		return _process_script_enum(identifier, true)
	elif identifier.begins_with("res://"):
		return false
	
	return _process_built_in_enum(identifier, true)


#region Built in Enum

func _process_built_in_enum(identifier:String, force:=false):
	var base_type = _get_current_script_base_type()
	var access_path = ""
	var enum_name = ""
	var parts = identifier.split(".", false)
	for i in range(parts.size()):
		var part = parts[i]
		if ClassDB.class_has_enum(base_type, part):
			enum_name = part
			break
		elif ClassDB.class_exists(part) and part != base_type:
			base_type = part
			access_path = UString.dot_join(access_path, part)
	
	
	if not ClassDB.class_has_enum(base_type, enum_name):
		return false
	var enum_members = ClassDB.class_get_enum_constants(base_type, enum_name)
	print_deb(T.BUILT_IN, identifier, "->", base_type, enum_name, enum_members)
	
	return _add_enum_code_completions(access_path, enum_members, [], force)

func _is_identifier_built_in_enum(identifier:String):
	var front = identifier
	if identifier.find(".") > -1:
		front = UString.get_member_access_front(identifier)
	var base_type = _get_current_script_base_type()
	if ClassDB.class_has_enum(base_type, front):
		return front
	return ""


func _get_current_script_base_type():
	var current_script = get_current_script()
	return current_script.get_instance_base_type()

#endregion


#region Script Enums


func _process_script_enum(enum_path:String, force:=false):
	if not enum_path.ends_with(ENUM_SUFFIX):
		return false
	enum_path = enum_path.trim_suffix(ENUM_SUFFIX)
	var script_data = get_enum_script_data(enum_path)
	print_deb(T.OBJECT_DATA, script_data)
	
	if script_data.is_empty():
		return false
	script_data["force"] = force
	return _add_custom_enum_members(script_data)

func get_enum_script_data(class_path:String):
	var path_data = split_path(class_path)
	if path_data.is_empty():
		return {}
	var script_path = path_data[0]
	var suffix = path_data[1]
	var enum_access = ""
	var enum_name = suffix
	if suffix.find(".") > -1:
		enum_name = UString.get_member_access_back(suffix)
		enum_access = UString.trim_member_access_back(suffix)
	
	return {"enum_full_path": class_path, "enum_script_path": script_path, "enum_access":enum_access, "enum_name":enum_name}



func _add_custom_enum_members(script_data:Dictionary):
	var enum_full_path = script_data.get("enum_full_path")
	var enum_main_script_path = script_data.get("enum_script_path") as String
	var enum_access = script_data.get("enum_access")
	var enum_name = script_data.get("enum_name")
	
	var force = script_data.get("force", false)
	
	var caret_context = get_caret_context()
	var class_obj = caret_context.get_current_class_object()
	
	var is_function_call = comp_object is CaretContext.FunctionCallData
	print_deb(T.ACCESS_PATH, "FUNCTION", is_function_call)
	
	var enum_type_path = enum_full_path + ENUM_SUFFIX
	
	var current_script = get_current_script()
	var current_script_path = current_script.resource_path
	
	# this seems to be working well
	var gdscript_parser = get_gdscript_parser()
	var enum_script_parser = gdscript_parser.get_parser_for_path(enum_main_script_path)
	
	var enum_class_obj = enum_script_parser.get_class_object(enum_access) as GDScriptParser.ParserClass
	var enum_members = enum_class_obj.get_enum_members(enum_name)
	
	if enum_members == null:
		return false
	
	var path_to_enum = UString.dot_join(enum_access, enum_name)
	var enum_in_current_script = enum_main_script_path.begins_with(current_script_path)
	
	var alias_is_enum_script = false
	var alias = class_obj.has_preload(enum_type_path)
	if alias == null:
		alias = class_obj.has_preload(enum_main_script_path)
		#if alias != null:
		alias_is_enum_script = true
	print_deb(T.ACCESS_PATH, "ALIAS", alias)
	
	if enum_in_current_script:
		if is_function_call:
			var arg_dec = argument_access_object.declaration_symbol
			if arg_dec != enum_name and class_obj.has_constant_or_class(arg_dec):
				path_to_enum = arg_dec # not sure about this
		
		if alias == path_to_enum:
			alias = null
		return _add_enum_code_completions(path_to_enum, enum_members.keys(), [], force, alias)
	
	if comp_object is CaretContext.OperationData:
		path_to_enum = comp_object.get_type_access_path(current_script_path)
	elif comp_object is CaretContext.MatchBlockData:
		path_to_enum = comp_object.get_type_access_path(current_script_path)
	elif comp_object is CaretContext.FunctionCallData:
		path_to_enum = comp_object.get_type_access_path(current_script_path)
	
	if path_to_enum.begins_with("self."):
		path_to_enum = path_to_enum.trim_prefix("self.")
	
	for e in enum_members.keys():
		if path_to_enum.ends_with(e) and e != enum_name:
			path_to_enum = path_to_enum.trim_suffix(e).trim_suffix(".")
			break
	
	if alias != null:
		if alias_is_enum_script:
			alias = UString.dot_joinv([alias, enum_access, enum_name])
		if alias == path_to_enum:
			alias = null
	
	#path_to_enum = path_to_enum.trim_suffix(ENUM_SUFFIX) # should not be necessary now
	print_deb(T.ACCESS_PATH, "PATH", path_to_enum)
	return _add_enum_code_completions(path_to_enum, enum_members.keys(), [], force, alias)

#endregion





## Access path is a path of classes ie. SomeClass.MyEnum, to access the enum member.
## Enum Data is an array of enum member names.
func _add_enum_code_completions(access_path:String, enum_members:Array, other_options:= [], force_update:=false, alias=null) -> bool:
	var script_editor = get_code_edit()
	if enum_members.is_empty():
		return false
	
	var has_alias = alias != null
	
	var enum_icon = EditorInterface.get_editor_theme().get_icon("Enum", "EditorIcons")
	print(has_alias)
	#if has_alias and not show_alias_only:
	for member in enum_members: # TODO options can be added via inherited method
		var full_name = member
		if access_path != "":
			full_name = access_path + "." + member #^ string + int error here TODO
		script_editor.add_code_completion_option(CodeEdit.KIND_ENUM, full_name, full_name, Color.GRAY, enum_icon)
	
	if has_alias:
		for member in enum_members:
			var full_name = member
			if alias != "":
				full_name = alias + "." + member
			var display_name = full_name + "[script alias]"
			script_editor.add_code_completion_option(CodeEdit.KIND_ENUM, display_name, full_name, Color.GRAY, enum_icon, null, 256)
	
	if not other_options.is_empty():
		var prop_icon = EditorInterface.get_editor_theme().get_icon("MemberProperty", "EditorIcons")
		for option in other_options:
			script_editor.add_code_completion_option(CodeEdit.KIND_VARIABLE, option, option, Color.GRAY, prop_icon)
	
	script_editor.update_code_completion_options(force_update)
	
	return true



#region Needs Work

func _get_enum_vars(processed_data:Dictionary) -> Array:
	if not show_member_suggestions:
		return []
	#var t = ALibRuntime.Utils.UProfile.TimeFunction.new("Get enum vars")
	var current_class = get_caret_context().current_class
	var current_assigned = ""
	#if get_state() == State.ASSIGNMENT:
		#var assignment_data = get_assignment_at_caret()
		#var left = assignment_data.get(Assignment.LEFT, "")
		#if left.find(".") == -1 or left.begins_with("var "):
			#if not left.begins_with("var "):
				#left = "var " + left
			#var var_data = UString.get_var_name_and_type_hint_in_line(left)
			#current_assigned = var_data[0]
	
	var enum_class_string = processed_data.enum_class
	var enum_script = processed_data.enum_script
	var member_path = processed_data.member_path
	var enum_data = processed_data.enum_data
	
	var enum_script_path = ""
	if enum_script != null:
		enum_script_path = enum_script.resource_path
	var option_dict = {}
	#print("GET ENUM VARS: ", enum_class_string)
	
	var script_editor = get_code_edit()
	var current_line = script_editor.get_caret_line()
	
	#var current_vars = get_in_scope_body_and_local_vars()
	var current_vars = []
	var body_vars = current_vars.body
	var local_vars = current_vars.local
	for name in body_vars.keys():
		if name == current_assigned:
			continue
		if name == enum_class_string or name == member_path: # if name is the class, likely the enum defined as const
			continue
		var data = body_vars.get(name)
		if not data is Dictionary:
			continue
		if not data.has(""):
			continue
		var type = data.get("")
		if type == enum_class_string or type == member_path:
			option_dict[name] = true
	for name in local_vars.keys():
		var data = local_vars.get(name)
		if not data is Dictionary:
			continue
		if not data.has(""):
			continue
		var type = data.get("")
		if type == enum_class_string or type == member_path:
			if name.find("%") > -1:
				name = name.substr(0, name.find("%"))
			if name == current_assigned:
				continue
			option_dict[name] = true
	
	var current_script = get_current_script()
	if current_class != "":
		current_script = get_script_member_info_by_path(current_script, current_class)
		if current_script == null:
			return option_dict.keys()
	
	var properties = UClassDetail.script_get_all_properties(current_script, UClassDetail.IncludeInheritance.ALL)
	for p in properties.keys():
		if p == current_assigned:
			continue
		var data = properties.get(p)
		#if not _is_property_info_enum(data):
			#continue
		var _class_name = data.get("class_name")
		#print(_class_name, " ", enum_class_string, " ",member_path)
		if _class_name == enum_class_string:
			option_dict[p] = true
			continue
		if enum_script_path != "":
			if _class_name.begins_with(enum_script_path):
				option_dict[p] = true
	
	
	#t.stop()
	return option_dict.keys()

#endregion


#! arg_location section:T
static func print_deb(section:String, ...msg:Array):
	if section in _PRINT:
		msg.push_front(section)
		ALibEditor.PrintDebug.print(msg)

const _PRINT = [
	#T.ACCESS_PATH, 
	T.OBJECT_DATA,
	#T.BUILT_IN
	]


class T:
	const BUILT_IN = "BUILT_IN"
	const OBJECT_DATA = "OBJECT_DATA"
	const ACCESS_PATH = "ENUM ACCESS PATH"





class EditorSet:
	const ENUM_ENABLE = &"plugin/code_completion/enum/enable"
	const SHOW_MEMBER_SUGGESTIONS = &"plugin/code_completion/enum/show_member_suggestions"
	const SHOW_ALIAS_ONLY = &"plugin/code_completion/enum/show_alias_only"
