@tool
extends EditorCodeCompletion
#! import_p UString,UClassDetail

const CacheHelper = EditorCodeCompletionSingleton.CacheHelper

const ENUM_SUFFIX = ParserKeys.ENUM_PATH_SUFFIX

var enum_enable:= false

var show_member_suggestions:= false # not currently used
var show_alias_only:=false # not currently used

var comp_object:Object


func _singleton_ready():
	pass

func register_editor_settings(settings_helper:SettingHelperEditor):
	settings_helper.subscribe_property(self, &"enum_enable", EditorSet.ENUM_ENABLE, true)
	settings_helper.subscribe_property(self, &"show_member_suggestions", EditorSet.SHOW_MEMBER_SUGGESTIONS, true)
	#settings_helper.subscribe_property(self, &"show_alias_only", EditorSet.SHOW_ALIAS_ONLY, true)


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
	
	print_deb(T.ENUM, ["OPERATOR", op_data.left_symbol_data.type])
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
	comp_object = func_data
	
	#var current_arg = func_data.get_current_arg_object()
	#print_deb(T.ENUM, ["FUNC", current_arg.type])
	#return _process_identifier(current_arg.type)
	
	var current_arg_type = func_data.get_current_arg_type()
	print_deb(T.ENUM, [func_data.get_function_origin()])
	print_deb(T.ENUM, ["FUNC", current_arg_type])
	return _process_identifier(current_arg_type)


func _process_identifier(identifier:String):
	print_deb(T.ENUM, ["ID>", identifier])
	if not identifier.ends_with(ENUM_SUFFIX):
		return false
	
	if GDScriptParser.Utils.is_absolute_path(identifier):
		return _process_script_enum(identifier, true)
	return _process_built_in_enum(identifier, true)


#region Built in Enum

func _process_built_in_enum(identifier:String, force:=false):
	identifier = identifier.trim_suffix(ENUM_SUFFIX)
	var base_type = _get_current_script_base_type()
	var access_path = ""
	var enum_name = ""
	var enum_members = []
	if not identifier.contains("::"):
		var member_data = GDScriptParser.BuiltInChecker.get_member_data("", identifier)
		if not member_data:
			return false
		for v in member_data.get("values"):
			enum_members.append(v.get("name"))
		
	else:
		var parts = identifier.split("::", false)
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
		enum_members = ClassDB.class_get_enum_constants(base_type, enum_name)
	
	print_deb(T.BUILT_IN, [identifier, "->", base_type, enum_name, enum_members])
	print_deb(T.ACCESS_PATH, ["ENUM ACCESS::", access_path])
	var enum_vars = _get_enum_vars(identifier + ENUM_SUFFIX)
	return _add_builtin_enum_code_completions(access_path, enum_members, enum_vars, force)

func _is_identifier_built_in_enum(identifier:String):
	var front = identifier
	if identifier.find(".") > -1:
		front = UString.get_member_access_front(identifier)
	var base_type = _get_current_script_base_type()
	if ClassDB.class_has_enum(base_type, front):
		return front
	return ""


func _get_current_script_base_type() -> StringName:
	var current_script:GDScript = get_current_script()
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
	print_deb(T.OBJECT_DATA, [script_data])
	
	if script_data.is_empty():
		return false
	script_data["force"] = force
	return _add_custom_enum_members(script_data)

func get_enum_script_data(class_path:String):
	#var enum_class_path = GDScriptParser.Utils.type_path_get_non_member(class_path)
	#var script_data = split_path(enum_class_path)
	var script_data = GDScriptParser.Utils.type_path_get_script_data(class_path)
	var script_path = script_data[0]
	var enum_access = script_data[1]
	var enum_name = GDScriptParser.Utils.type_path_get_member(class_path)
	
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
	print_deb(T.ENUM, ["ENUM MAIN SCRIPT", enum_main_script_path, "CLASS", enum_class_obj.get_name(), enum_name])
	
	var enum_members = enum_class_obj.get_enum_members(enum_name)
	if enum_members == null:
		return false
	
	var access_options = comp_object.get_type_access_path()
	
	print_deb(T.ACCESS_PATH, ["ACCESS", access_options])
	print_deb(T.ACCESS_PATH, ["STANDARD", access_options.standard])
	print_deb(T.ACCESS_PATH, ["SCRIPT ALIAS", access_options.script_alias])
	print_deb(T.ACCESS_PATH, ["GLOBAL NAME", access_options.global])
	
	for e in enum_members:
		if access_options.standard.begins_with("self."):
			access_options.standard = access_options.standard.trim_prefix("self.")
		if access_options.standard.ends_with(e) and e != enum_name:
			access_options.standard = access_options.standard.trim_suffix(e).trim_suffix(".")
	
	# ensure the standard path is valid
	var resolved = gdscript_parser.resolve_expression_to_type(access_options.standard, get_caret_context().caret_line)
	if not resolved.ends_with(enum_name + ENUM_SUFFIX):
		access_options.standard = ""
		print_deb(T.ACCESS_PATH, ["ENUM RES CHECK", resolved])
	
	var enum_vars = _get_enum_vars(script_data.get("enum_full_path"))
	return _add_enum_code_completions(access_options.standard, enum_members.keys(), enum_vars, force, access_options.script_alias, access_options.global)

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
		for option in other_options: # 4096 will place this last
			script_editor.add_code_completion_option(CodeEdit.KIND_VARIABLE, option, option, Color.GRAY, prop_icon, null, 4096)
	
	script_editor.update_code_completion_options(force_update)
	return true



#region Needs Work

func _get_enum_vars(enum_type_path:String) -> Array:
	if not show_member_suggestions:
		return []
	
	if not enum_type_path.ends_with(ENUM_SUFFIX):
		enum_type_path += ENUM_SUFFIX
	
	# ideally this would not list the current var
	var valid = []
	var caret_context = get_caret_context()
	var current_class_obj = caret_context.get_current_class_object()
	for m in current_class_obj.get_members():
		var member_data = current_class_obj.get_member_data(m, true)
		if not member_data.get(ParserKeys.MEMBER_TYPE, "").ends_with("var"):
			continue
		var type = current_class_obj.get_member_type(m)
		if type == enum_type_path:
			valid.append(m)
	
	var current_func_obj = caret_context.get_current_func_object()
	if is_instance_valid(current_func_obj):
		for key in caret_context.local_vars.keys():
			#var member_data = caret_context.local_vars.get(key)
			var type = current_func_obj.get_local_var_type(key)
			if type == enum_type_path:
				valid.append(key)
	
	return valid

#endregion

const PrintDebug = preload("uid://d1ki8cxxh7lvb") #! resolve ALibEditor.PrintDebug
#! arg_location section:T
static func print_deb(section:String, msg:Array):
	if section in _PRINT:
		msg.push_front(section)
		PrintDebug.print(msg)

const _PRINT = [
	#T.ACCESS_PATH,
	#T.OBJECT_DATA,
	#T.BUILT_IN,
	#T.ENUM,
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
