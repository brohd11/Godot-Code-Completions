@tool
extends EditorCodeCompletion
#! import_p UString,UClassDetail

const CacheHelper = EditorCodeCompletionSingleton.CacheHelper

const ENUM_SUFFIX = ParserKeys.ENUM_PATH_SUFFIX

var enum_enable:= false
var show_member_suggestions:= false
var show_alias_only:=false

#var data_cache = {}

#var completion_cache = {}

#var access_object:CaretContext.AccessObject
#var function_access_object:CaretContext.AccessObject
#var function_object:String
#var argument_access_object:CaretContext.AccessObject

func test():
	var c = get_caret_context().char_before_caret
	pass


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
	
	print_deb(T.ENUM, "OPERATOR", op_data.left_symbol_data.type)
	return _process_identifier(op_data.left_symbol_data.type)

func _match_branch(caret_context:CaretContext):
	var match_type = caret_context.get_match_block_data()
	if not match_type.is_valid:
		return false
	if caret_context.get_line_indent() != match_type.indent + caret_context.get_indent_size():
		return false
	if  caret_context.is_in_multiline_expression() or caret_context.code_context_find(":") != -1:
		return false
	comp_object = match_type
	
	return _process_identifier(match_type.symbol_data.type)

func _is_function_call():
	return comp_object is CaretContext.FunctionCallData

func _function_call(caret_context:CaretContext):
	var func_data = caret_context.get_function_call_data()
	var current_arg = func_data.func_get_current_arg()
	comp_object = func_data
	
	print_deb(T.ENUM, "FUNC", current_arg.type)
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
	
	return _add_builtin_enum_code_completions(access_path, enum_members, [], force)

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


func _add_builtin_enum_code_completions(access_path:String, enum_members:Array, other_options:= [], force_update:=false) -> bool:
	var script_editor = get_code_edit()
	if enum_members.is_empty():
		return false
	
	var enum_icon = EditorInterface.get_editor_theme().get_icon("Enum", "EditorIcons")
	for member in enum_members: # TODO options can be added via inherited method
		var full_name = UString.dot_join(access_path, member)
		script_editor.add_code_completion_option(CodeEdit.KIND_ENUM, full_name, full_name, Color.GRAY, enum_icon)
	
	if not other_options.is_empty():
		var prop_icon = EditorInterface.get_editor_theme().get_icon("MemberProperty", "EditorIcons")
		for option in other_options:
			script_editor.add_code_completion_option(CodeEdit.KIND_VARIABLE, option, option, Color.GRAY, prop_icon)
	
	script_editor.update_code_completion_options(force_update)
	return true

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
	
	var enum_class_path = GDScriptParser.Utils.type_path_get_non_member(class_path)
	var script_data = split_path(enum_class_path)
	var script_path = script_data[0]
	var enum_access = script_data[1]
	var enum_name = GDScriptParser.Utils.type_path_get_member(class_path)
	
	
	#var path_data = split_path(class_path) # need to fix this probably
	#print(class_path)
	#if path_data.is_empty():
		#return {}
	#var script_path = path_data[0]
	#var suffix = path_data[1]
	#var enum_access = ""
	#var enum_name = suffix
	#if suffix.find(".") > -1:
		#enum_name = UString.get_member_access_back(suffix)
		#enum_access = UString.trim_member_access_back(suffix)
	
	return {"enum_full_path": class_path, "enum_script_path": script_path, "enum_access":enum_access, "enum_name":enum_name}



func _add_custom_enum_members(script_data:Dictionary):
	#var enum_full_path = script_data.get("enum_full_path")
	var enum_main_script_path = script_data.get("enum_script_path") as String
	var enum_access = script_data.get("enum_access")
	var enum_name = script_data.get("enum_name")
	
	var force = script_data.get("force", false)
	
	var gdscript_parser = get_gdscript_parser()
	var enum_script_parser = gdscript_parser.get_parser_for_path(enum_main_script_path)
	var enum_class_obj = enum_script_parser.get_class_object(enum_access) as GDScriptParser.ParserClass
	print("ENUM MAIN SCRIPT::", enum_main_script_path, "::CLASS::", enum_class_obj.get_name(), "::", enum_name)
	var enum_members = enum_class_obj.get_enum_members(enum_name)
	if enum_members == null:
		return false
	
	var access_options = comp_object.get_type_access_path()
	
	print_deb(T.ACCESS_PATH, "ACCESS", access_options)
	print_deb(T.ACCESS_PATH, "STANDARD", access_options.standard)
	print_deb(T.ACCESS_PATH, "SCRIPT ALIAS", access_options.script_alias)
	print_deb(T.ACCESS_PATH, "GLOBAL NAME", access_options.global)
	
	for e in enum_members:
		if access_options.standard.begins_with("self."):
			access_options.standard = access_options.standard.trim_prefix("self.")
		if access_options.standard.ends_with(e) and e != enum_name:
			access_options.standard = access_options.standard.trim_suffix(e).trim_suffix(".")
		#if access_options.script_alias.ends_with(e) and e != enum_name:
			#access_options.script_alias = access_options.script_alias.trim_suffix(e).trim_suffix(".")
		#if access_options.global.ends_with(e) and e != enum_name:
			#access_options.global = access_options.global.trim_suffix(e).trim_suffix(".")
	
	var resolved = gdscript_parser.resolve_expression_to_type(access_options.standard, get_caret_context().caret_line)
	if not resolved.ends_with(enum_name + ENUM_SUFFIX):
		access_options.standard = ""
		print_deb(T.ACCESS_PATH, "ENUM RES CHECK", resolved)
	
	return _add_enum_code_completions(access_options.standard, enum_members.keys(), [], force, access_options.script_alias, access_options.global)

#endregion


## Access path is a path of classes ie. SomeClass.MyEnum, to access the enum member.
## Enum Data is an array of enum member names.
func _add_enum_code_completions(access_path:String, enum_members:Array, other_options:= [], force_update:=false, alias="", global_path="") -> bool:
	var script_editor = get_code_edit()
	if enum_members.is_empty():
		return false
	
	if alias == access_path:
		alias = ""
	if global_path == access_path:
		global_path = ""
	
	var one_has_been_added:=false
	#var has_alias = alias != ""
	
	var enum_icon = EditorInterface.get_editor_theme().get_icon("Enum", "EditorIcons")
	if access_path != "":
		#if has_alias and not show_alias_only:
		for member in enum_members: # TODO options can be added via inherited method
			one_has_been_added = true
			var full_name = UString.dot_join(access_path, member)
			script_editor.add_code_completion_option(CodeEdit.KIND_ENUM, full_name, full_name, Color.GRAY, enum_icon)
	
	if global_path != "":
		var global_tag := ""
		if one_has_been_added:
			global_tag = "[global]"
		one_has_been_added = true
		for member in enum_members:
			var full_name = UString.dot_join(global_path, member)
			var display_name = full_name + global_tag
			script_editor.add_code_completion_option(CodeEdit.KIND_ENUM, display_name, full_name, Color.GRAY, enum_icon, null, 2048)
	
	if alias != "":
		var alias_tag := ""
		if one_has_been_added:
			alias_tag = "[script alias]"
		one_has_been_added = true
		for member in enum_members:
			var full_name = UString.dot_join(alias, member)
			var display_name = full_name + alias_tag
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
			#var var_data = UString.get_var_name_and_type_hint_in_line(left) # moved to UString.GDScriptParse
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
	T.ACCESS_PATH, 
	T.OBJECT_DATA,
	#T.BUILT_IN,
	T.ENUM,
	]


class T:
	const ENUM = "ENUM"
	const BUILT_IN = "BUILT_IN"
	const OBJECT_DATA = "OBJECT_DATA"
	const ACCESS_PATH = "ENUM ACCESS PATH"





class EditorSet:
	const ENUM_ENABLE = &"plugin/code_completion/enum/enable"
	const SHOW_MEMBER_SUGGESTIONS = &"plugin/code_completion/enum/show_member_suggestions"
	const SHOW_ALIAS_ONLY = &"plugin/code_completion/enum/show_alias_only"
