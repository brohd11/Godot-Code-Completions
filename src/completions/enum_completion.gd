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

func _on_code_completion_requested(script_editor:CodeEdit) -> bool:
	if not enum_enable:
		return false
	access_object = null
	function_access_object = null
	function_object = ""
	var caret_context = get_caret_context()
	if caret_context.token_state != TokenState.NONE:
		return false
	if caret_context.expression_before_caret.length() > 5:
		return false
	if caret_context.expression_state == ExpressionState.ASSIGNMENT or caret_context.expression_state == ExpressionState.COMPARISON:
		return _operator(caret_context)
	elif caret_context.scope_state == ScopeState.MATCH_BRANCH:
		return _match_branch(caret_context)
	elif caret_context.is_in_function_call():
		return _function_call(caret_context)
	return false
	#tf_test_al()


func _operator(caret_context:CaretContext):
	var op_data = caret_context.get_operation_data()
	access_object = op_data.left_access_object
	return _process_identifier(op_data.left_type)

func _match_branch(caret_context:CaretContext):
	var match_type = caret_context.get_match_block_data()
	if not match_type.is_valid:
		return false
	if caret_context.get_line_indent() != match_type.indent + caret_context.get_indent_size():
		return false
	if  caret_context.is_in_multiline_expression() or caret_context.code_context_find(":") != -1:
		return false
	access_object = match_type.access_object
	return _process_identifier(match_type.type)


func _function_call(caret_context:CaretContext):
	var func_data = caret_context.get_function_call_data()
	var current_arg = func_data.func_get_current_arg()
	
	access_object = current_arg.access_object
	function_access_object = func_data.access_object
	function_object = func_data.function_object
	
	print("FUNC:::")
	print(func_data.function_object)
	print("ACCESS:::")
	print(function_access_object.declaration_symbol)
	print(function_access_object.access_symbol)
	print(function_access_object.type)
	
	print("ARG:::")
	print(access_object.declaration_symbol)
	print(access_object.access_symbol)
	print(access_object.type)
	return _process_identifier(current_arg.type)


func _process_identifier(identifier:String):
	print("PROCESS ENUM:::", identifier)
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
	
	prints("BUILT IN ENUM::", identifier, "->", base_type, enum_name)
	if not ClassDB.class_has_enum(base_type, enum_name):
		return false
	var enum_members = ClassDB.class_get_enum_constants(base_type, enum_name)
	
	#test_base()
	prints(base_type, enum_name, enum_members)
	
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
	print(script_data)
	
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
	
	var enum_main_script = load(enum_main_script_path) as GDScript
	var enum_global_name = enum_main_script.get_global_name()
	var enum_is_global = enum_global_name != ""
	
	var current_script = get_current_script()
	var current_script_path = current_script.resource_path
	
	var enum_parent_script = enum_main_script
	if enum_access != "":
		enum_parent_script = get_script_member_info_by_path(enum_main_script, enum_access)
	
	var path_to_enum = UString.dot_join(enum_access, enum_name)
	
	var enum_in_current_script = enum_main_script_path.begins_with(current_script_path)
	var enum_members
	if enum_in_current_script:
		print("ENUM IN CURRENT SCRIPT")
		var parser = get_gdscript_parser()
		var class_obj = parser.get_class_object(enum_access) as GDScriptParser.ParserClass
		enum_members = class_obj.get_enum_members(enum_name)
	else:
		enum_members = get_script_member_info_by_path(enum_parent_script, enum_name)
	#print("ACCESS OBJ::ENUM_MEMBERS::", enum_members)
	if enum_members == null:
		return false
	
	var access_symbol = access_object.access_symbol
	var declaration_symbol = access_object.declaration_symbol
	var access_obj_type = access_object.type
	
	var caret_context = get_caret_context()
	var class_obj = caret_context.get_current_class_object()
	
	#caret_context.expression_state == 
	print(access_symbol)
	print(declaration_symbol)
	print(access_obj_type)
	
	#var n := NewScript3.new()
	#n.tf_test_simple(NewScript3.T.TimeScale.USEC, NewScript3.TS.MSEC)
	##n.test_nest(NewScript3.NestedClass.MyNum.TEST)
	##n.test_nest_re(NewScript3.NestedClass.MyNum.TEST)
	#var nest = n.get_nest()
	#nest.tf_test2(NewScript3.T.TimeScale.USEC)
	##nest.test(NewScript3.NestedClass.MyNum.TEST)
	#nest.test_rename(Num.TEST)
	##nest.tf_test2(TS.MSEC)
	#
	#if n.tf_var == TS.MSEC:
		#pass
	#nest.test(NewScript3.NestedClass.MyNum.TEST)
	#nest.test_rename(NewScript3.NestedClass.Num.TEST)
	
	#if nest.num_var == NewScript3.NestedClass.MyNum.TEST:
	
	
	var is_function_call = function_access_object != null
	
	var path_set:= false
	
	
	if enum_in_current_script:
		path_set = true
		pass # the enum is declared in the current script, can just use enum_access + enum_name
	elif enum_is_global:
		path_to_enum = UString.dot_joinv([enum_global_name, enum_access, enum_name])
		path_set = true
	elif access_obj_type.ends_with(ENUM_SUFFIX): # not in current_script, but directly accessed in parent script
		print("ACCESS OBJECT IS ENUM TYPE::", access_obj_type, "::", enum_full_path)
		var stripped_obj_type = access_obj_type.trim_suffix(ENUM_SUFFIX)
		if stripped_obj_type == enum_full_path:
			var access_script_data = UString.get_script_path_and_suffix(stripped_obj_type.trim_suffix(enum_name).trim_suffix("."))
			var access_script_path = access_script_data[0]
			var inner_access = access_script_data[1]
			print("ACCESS OBJECT IS CURRENT ENUM::INNER ACCESS::", inner_access)
			if is_function_call: # function prepends the function declaration symbol to ensure access
				var access_script = load(access_script_path) as GDScript
				if access_script.get_global_name() != "":
					path_to_enum = UString.dot_joinv([access_script.get_global_name(), inner_access, declaration_symbol])
					path_set = true
				else:
					path_to_enum = UString.dot_joinv([function_access_object.declaration_symbol, inner_access, declaration_symbol])
					path_set = true
			else:
				path_to_enum = UString.dot_joinv([declaration_symbol, inner_access, enum_name])
				path_to_enum = UString.dot_joinv([declaration_symbol])
				path_set = true
		else:
			print("ACCESS OBJECT IS NOT CURRENT ENUM")
			#access_obj_type = function_access_object.type
			#declaration_symbol = function_access_object.declaration_symbol
		
	
	if not path_set and access_obj_type != "":
		var access_script_data = UString.get_script_path_and_suffix(access_obj_type)
		var access_script_path = access_script_data[0]
		var access_class_path = access_script_data[1] # don't need for a search by val
		enum_access = enum_access.trim_prefix(access_class_path).trim_prefix(".")
		print("EXTERNAL ACCESS OBJ", access_script_data)
		var access_script = load(access_script_path)
		
		
		var path_handled = false
		if access_script != enum_main_script:
			var access = UClassDetail.script_get_member_by_value(access_script, enum_parent_script, true)
			print("EXTERNAL ACCESS::", access)
			if access != null:
				path_to_enum = UString.dot_joinv([declaration_symbol, access, enum_name])
				path_handled = true
		
		else: # access script is enum main script
			if is_function_call: # function prepends the function declaration symbol to ensure access
				if access_script.get_global_name() != "":
					path_to_enum = UString.dot_joinv([access_script.get_global_name(), declaration_symbol, enum_access, enum_name])
				else:
					path_to_enum = UString.dot_joinv([function_access_object.declaration_symbol, declaration_symbol, enum_access, enum_name])
				#path_to_enum = UString.dot_joinv([function_access_object.declaration_symbol, declaration_symbol, enum_name])
			else:
				path_to_enum = UString.dot_joinv([declaration_symbol, enum_access, enum_name])
				#path_to_enum = UString.dot_joinv([declaration_symbol, enum_name])
			path_handled = true
		
		if not path_handled:
			print("ENUM UNHANDLED CASE::", declaration_symbol, "::", enum_main_script_path)
			return false
	
	
	
	
	
	
	
	
	
	
	
	
	
	#if enum_in_current_script:
		#pass # the enum is declared in the current script, can just use enum_access + enum_name
	#elif access_obj_type.ends_with(ENUM_SUFFIX): # not in current_script, but directly accessed in parent script
		#print("ACCESS OBJECT IS ENUM TYPE::", access_obj_type, "::", enum_full_path)
		#var stripped_obj_type = access_obj_type.trim_suffix(ENUM_SUFFIX)
		#if stripped_obj_type == enum_full_path:
			#var access_script_data = UString.get_script_path_and_suffix(stripped_obj_type.trim_suffix(enum_name).trim_suffix("."))
			#var access_script_path = access_script_data[0]
			#var inner_access = access_script_data[1]
			#print("ACCESS OBJECT IS CURRENT ENUM::INNER ACCESS::", inner_access)
			#if is_function_call: # function prepends the function declaration symbol to ensure access
				#path_to_enum = UString.dot_joinv([function_access_object.declaration_symbol, inner_access, declaration_symbol])
			#else:
				#path_to_enum = UString.dot_joinv([declaration_symbol, inner_access, enum_name])
				#path_to_enum = UString.dot_joinv([declaration_symbol])
		#else:
			#print("ACCESS OBJECT IS NOT CURRENT ENUM")
			##access_obj_type = function_access_object.type
			##declaration_symbol = function_access_object.declaration_symbol
		#
	#else:
		#
		#var access_script_data = UString.get_script_path_and_suffix(access_obj_type)
		#var access_script_path = access_script_data[0]
		#var access_class_path = access_script_data[1] # don't need for a search by val
		#enum_access = enum_access.trim_prefix(access_class_path).trim_prefix(".")
		#print("EXTERNAL ACCESS OBJ", access_script_data)
		#var access_script = load(access_script_path)
		#
		#var path_handled = false
		#if access_script != enum_main_script:
			#var access = UClassDetail.script_get_member_by_value(access_script, enum_parent_script, true)
			#print("EXTERNAL ACCESS::", access)
			#if access != null:
				#path_to_enum = UString.dot_joinv([declaration_symbol, access, enum_name])
				#path_handled = true
		#
		#else: # access script is enum main script
			#if is_function_call: # function prepends the function declaration symbol to ensure access
				#path_to_enum = UString.dot_joinv([function_access_object.declaration_symbol, declaration_symbol, enum_access, enum_name])
				##path_to_enum = UString.dot_joinv([function_access_object.declaration_symbol, declaration_symbol, enum_name])
			#else:
				#path_to_enum = UString.dot_joinv([declaration_symbol, enum_access, enum_name])
				##path_to_enum = UString.dot_joinv([declaration_symbol, enum_name])
			#path_handled = true
		#
		#if not path_handled:
			#print("ENUM UNHANDLED CASE::", declaration_symbol, "::", enum_main_script_path)
			#return false
	
	
	print("MEMBERS::", enum_members)
	
	print("PATH ", path_to_enum)
	
	var alias = class_obj.has_preload(enum_full_path + ENUM_SUFFIX)
	if alias == null:
		alias = class_obj.has_preload(enum_main_script_path)
		if alias != null:
			alias = UString.dot_joinv([alias, enum_access, enum_name])
	print("ALIAS::", alias)
	
	
	return _add_enum_code_completions(path_to_enum, enum_members.keys(), [], force, alias)




func test_vars():
	
	#tf_test_al()
	
	#tf_test_al()
	#ScriptEditorRef.subscribe()
	
	#var s:= ScriptEditorRef.new()
	#s.subscribe()
	
	var ts:TS = TS.USEC
	#ts ==
	
	var t:=TF.TimeScale.MSEC
	#t == 
	
	var tff = tf.new("", )
	pass


const Num = NewScript3.NestedClass.Num

enum MyNum{
	DSHJKHDSJ,
	DHJSDHJS
}

func test_num(m:MyNum):
	var n:=NewScript3.new()
	n.tf_test(ALibRuntime.Utils.UProfile.TimeFunction.TimeScale.USEC)
	n.tf_test_simple(NewScript3.T.TimeScale.USEC, NewScript3.TS.USEC)
	
	var g:= G.UProfile.TimeFunction.new("",)
	
	pass

const TS = TF.TimeScale
const TF = P.TimeFunction
const G = ALibRuntime.Utils
const P = G.UProfile

var tf:= P.TimeFunction

var a:Node.AutoTranslateMode
var t:ConnectFlags

class Nested:
	enum Gumption {
		FUNK
	}
	enum Nother {
		TEST
	}
	static func test(g:Gumption, n:Nother):
		pass
	
	static func nother(s:TF.TimeScale):
		pass

#endregion





## Access path is a path of classes ie. SomeClass.MyEnum, to access the enum member.
## Enum Data is an array of enum member names.
func _add_enum_code_completions(access_path:String, enum_members:Array, other_options:= [], force_update:=false, alias=null) -> bool:
	var script_editor = get_code_edit()
	if enum_members.is_empty():
		return false
	
	var enum_icon = EditorInterface.get_editor_theme().get_icon("Enum", "EditorIcons")
	
	for member in enum_members: # TODO options can be added via inherited method
		var full_name = member
		if access_path != "":
			full_name = access_path + "." + member #^ string + int error here TODO
		script_editor.add_code_completion_option(CodeEdit.KIND_ENUM, full_name, full_name, Color.GRAY, enum_icon)
	
	if alias != null:
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

const Pro = ALibRuntime.Utils.UProfile

func test(some:=Node.AutoTranslateMode.AUTO_TRANSLATE_MODE_DISABLED):
	pass

func test_base(some:=ConnectFlags.CONNECT_ONE_SHOT):
	pass


func tf_test(tf:ALibRuntime.Utils.UProfile.TimeFunction.TimeScale):
	pass

func tf_test_al(s:Pro.TimeFunction.TimeScale):
	match s:
		Pro.TimeFunction.TimeScale.MSEC:
			pass
		Pro.TimeFunction.TimeScale.USEC:
			pass
	pass













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





class EditorSet:
	const ENUM_ENABLE = &"plugin/code_completion/enum/enable"
	const SHOW_MEMBER_SUGGESTIONS = &"plugin/code_completion/enum/show_member_suggestions"
	const SHOW_ALIAS_ONLY = &"plugin/code_completion/enum/show_alias_only"
