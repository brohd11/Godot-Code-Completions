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
	var caret_context = get_caret_context()
	if caret_context.token_state != TokenState.NONE:
		return false
	if caret_context.expression_before_caret.length() > 5:
		return false
	
	access_object = null
	argument_access_object = null
	function_access_object = null
	function_object = ""
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

func _is_function_call():
	return argument_access_object != null

func _function_call(caret_context:CaretContext):
	var func_data = caret_context.get_function_call_data()
	var current_arg = func_data.func_get_current_arg()
	
	access_object = func_data.access_object
	argument_access_object = current_arg.access_object
	#function_access_object = func_data.access_object
	function_object = func_data.function_object
	
	print("FUNC:::")
	print(func_data.function_object)
	print("ACCESS:::")
	print(access_object.declaration_symbol)
	print(access_object.type)
	print(access_object.access_symbol)
	print(access_object.access_type)
	
	print("ARG:::")
	print(argument_access_object.declaration_symbol)
	print(argument_access_object.type)
	print(argument_access_object.access_symbol)
	print(argument_access_object.access_type)
	
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
	
	
	if not ClassDB.class_has_enum(base_type, enum_name):
		return false
	var enum_members = ClassDB.class_get_enum_constants(base_type, enum_name)
	prints("BUILT IN ENUM::", identifier, "->", base_type, enum_name)
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
	
	var caret_context = get_caret_context()
	var class_obj = caret_context.get_current_class_object()
	
	var is_function_call = argument_access_object != null
	print_deb(T.ACCESS_PATH, "FUNCTION", is_function_call)
	
	var enum_type_path = enum_full_path + ENUM_SUFFIX
	
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
		class_obj = get_gdscript_parser().get_class_object(enum_access)
		enum_members = class_obj.get_enum_members(enum_name)
	else:
		enum_members = get_script_member_info_by_path(enum_parent_script, enum_name)
	
	print("ACCESS OBJ::ENUM_MEMBERS::", enum_members)
	if enum_members == null:
		return false
	
	var access_cleaned = false
	var arg_cleaned = false
	for e in enum_members.keys():
		if not access_cleaned and access_object.declaration_symbol.ends_with(e):
			access_cleaned = true
			access_object.declaration_symbol = access_object.declaration_symbol.trim_suffix(e).trim_suffix(".")
		if is_instance_valid(argument_access_object):
			if not arg_cleaned and argument_access_object.declaration_symbol.ends_with(e):
				arg_cleaned = true
				argument_access_object.declaration_symbol = argument_access_object.declaration_symbol.trim_suffix(e).trim_suffix(".")
	
	
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
	
	
	var access_symbol = access_object.access_symbol
	var declaration_symbol = access_object.declaration_symbol
	var access_obj_type = access_object.type
	var access_obj_is_enum = access_obj_type.ends_with(ENUM_SUFFIX)
	
	if is_function_call:
		
		
		pass
	
	
	path_to_enum = _find_path_to_type(_get_access_object(enum_main_script, {}), enum_type_path)
	print_deb(T.ACCESS_PATH, "NEW PATH", path_to_enum)
	
	#caret_context.expression_state == 
	
	
	
	
	#var access_script_data = UString.get_script_path_and_suffix(access_obj_type)
	#var access_script_path = access_script_data[0]
	#var access_script = load(access_script_path) as GDScript
	#var access_class_path = access_script_data[1] # don't need for a search by val
	
	#print(access_symbol)
	#print(declaration_symbol)
	#print(access_obj_type)
	
	
	
	
	#var path_set:= false
	#if enum_is_global:
		#print_deb(T.ACCESS_PATH, "ENUM SCRIPT IS GLOBAL")
		#path_to_enum = _get_global_path(enum_global_name, script_data)
		#path_set = true
	#elif access_obj_is_enum:
		#print_deb(T.ACCESS_PATH, "ACCESS OBJECT IS ENUM")
	#elif access_script_path.begins_with(current_script_path):
		#print_deb(T.ACCESS_PATH, "ACCESS OBJECT IS CURRENT SCRIPT")
		#if not is_function_call:
			#var access = UClassDetail.script_get_member_by_value(access_script, enum_main_script, true)
			#if access == null:
				#print_deb(T.ACCESS_PATH, "COULD NOT GET ENUM SCRIPT IN", access_script)
			#
			#path_to_enum = UString.dot_joinv([access, enum_name])
			#path_set = true
		#
		#
		#
		#
		#
	#
	#
	#if not path_set and access_obj_type != "":
		#print_deb(T.ACCESS_PATH, "ATTEMPT EXTERNAL ACCESS OBJ", access_script_data)
		#var path_handled = false
		#if access_script != enum_main_script: # access script is not enum script, just search for the enum script
			#var access = UClassDetail.script_get_member_by_value(access_script, enum_parent_script, true)
			#print_deb(T.ACCESS_PATH, "EXTERNAL ACCESS", access)
			#if access != null:
				#path_to_enum = UString.dot_joinv([declaration_symbol, access, enum_name])
				#path_handled = true
		#
		#else: # access script is enum main script
			#enum_access = enum_access.trim_prefix(access_class_path).trim_prefix(".")
			#if is_function_call: # function prepends the function declaration symbol to ensure access
				#print_deb(T.ACCESS_PATH, "IS FUNCTION", "GLOBAL", access_script.get_global_name())
				#if access_script.get_global_name() != "":
					#path_to_enum = UString.dot_joinv([access_script.get_global_name(), declaration_symbol, enum_access, enum_name])
				#else:
					#path_to_enum = UString.dot_joinv([function_access_object.declaration_symbol, declaration_symbol, enum_access, enum_name])
				##path_to_enum = UString.dot_joinv([function_access_object.declaration_symbol, declaration_symbol, enum_name])
			#else:
				#path_to_enum = UString.dot_joinv([declaration_symbol, enum_access, enum_name])
				##path_to_enum = UString.dot_joinv([declaration_symbol, enum_name])
			#path_handled = true
		#
		#if not path_handled:
			#print_deb(T.ACCESS_PATH, "ENUM UNHANDLED CASE", declaration_symbol, enum_main_script_path)
			#return false
	
	
	
	
	
	
	
	#test_num()
	
	
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
	
	
	#print_deb(T.ACCESS_PATH, "MEMBERS", enum_members)
	
	if alias != null:
		if alias_is_enum_script:
			alias = UString.dot_joinv([alias, enum_access, enum_name])
		print_deb(T.ACCESS_PATH, "ALIAS RESET", alias)
	
	print_deb(T.ACCESS_PATH, "PATH", path_to_enum)
	
	path_to_enum = path_to_enum.trim_suffix(ENUM_SUFFIX)
	return _add_enum_code_completions(path_to_enum, enum_members.keys(), [], force, alias)


func _get_global_path(enum_global_name:String, script_data:Dictionary):
	var enum_main_script_path = script_data.get("enum_script_path") as String
	var enum_access = script_data.get("enum_access")
	var enum_name = script_data.get("enum_name")
	var path_to_enum = UString.dot_joinv([enum_global_name, enum_access, enum_name])
	if _is_function_call():
		pass
	
	return path_to_enum


func _get_access_object(enum_main_script:GDScript, _script_data:Dictionary):
	#var enum_main_script_path = script_data.get("enum_script_path") as String
	#var enum_access = script_data.get("enum_access")
	#var enum_name = script_data.get("enum_name")
	
	var current_script = get_current_script()
	var current_script_path = current_script.resource_path
	
	if not _is_function_call():
		print_deb(T.ACCESS_PATH, "NEW PATH", "ACCESS")
		return access_object
	
	var access_script_data = UString.get_script_path_and_suffix(access_object.type)
	var access_script_path = access_script_data[0]
	
	var func_access_is_current_script = access_script_path.begins_with(current_script_path)
	if func_access_is_current_script and enum_main_script.resource_path != access_script_path:
		print_deb(T.ACCESS_PATH, "NEW PATH", "ARG")
		return argument_access_object # if access is current script but enum outside, must have accessed by arg?
	elif UClassDetail.get_global_class_path(argument_access_object.access_symbol) != "":
		return argument_access_object
	else:
		print_deb(T.ACCESS_PATH, "NEW PATH", "ACCESS")
		return access_object
		



func _find_path_to_type(from_access:CaretContext.AccessObject, to_find:String):
	#var access_symbol = from_access.access_symbol
	var symbol = from_access.declaration_symbol
	var access_obj_type = from_access.type
	print_deb(T.ACCESS_PATH, "NEW PATH", "DEC",  symbol, access_obj_type)
	print_deb(T.ACCESS_PATH, "NEW PATH", "ACCESS", from_access.access_symbol, from_access.access_type)
	if access_obj_type.ends_with(ENUM_SUFFIX):
		symbol = from_access.access_symbol
		access_obj_type = from_access.access_type
	print_deb(T.ACCESS_PATH, "NEW PATH", symbol, access_obj_type)
	
	var access_script_data = UString.get_script_path_and_suffix(access_obj_type)
	var access_script_path = access_script_data[0]
	var access_script = load(access_script_path) as GDScript
	var access_class_path = access_script_data[1].trim_suffix(ENUM_SUFFIX) # don't need for a search by val
	
	var to_find_script_data = UString.get_script_path_and_suffix(to_find)
	var to_find_script_path = to_find_script_data[0]
	var to_find_script = load(to_find_script_path) as GDScript
	var to_find_class_path = to_find_script_data[1] # don't need for a search by val
	print_deb(T.ACCESS_PATH, "NEW PATH", access_script, to_find_script)
	
	if not _is_function_call() or from_access == argument_access_object:
		if to_find_script.get_global_name() != "": # keep this here or rev find won't run on global classes
			return UString.dot_joinv([to_find_script.get_global_name(), to_find_class_path])
		
		if access_script_path == to_find_script_path:
			print_deb(T.ACCESS_PATH, "NEW PATH", "PATH EQ", access_obj_type)
			to_find_class_path = to_find_class_path.trim_prefix(access_class_path).trim_prefix(".")
			if access_obj_type.ends_with(ENUM_SUFFIX): # at this point, this would mean we've switched to access symbol and it is still enum
				print_deb(T.ACCESS_PATH, "NEW PATH", "OBJ IS ENUM")
				return from_access.declaration_symbol  # switch back to declaration which will have full path, i think
			return UString.dot_join(symbol, to_find_class_path)
		else:
			var access = UClassDetail.script_get_member_by_value(access_script, to_find_script, true)
			if access != null:
				return UString.dot_joinv([symbol, access, to_find_class_path])
		
		
	else:
		# EXTRACT ??
		if from_access != argument_access_object:
			var path_access = symbol
			if access_script_path != to_find_script_path: # out of script to find, get access to function object
				var func_script = load(function_object)
				var access = UClassDetail.script_get_member_by_value(access_script, func_script, true)
				if access != null:
					path_access = UString.dot_join(symbol, access)
			
			print_deb(T.ACCESS_PATH, "NEW PATH", "IS FUNC NOT ARG", argument_access_object.declaration_symbol, argument_access_object.type)
			print_deb(T.ACCESS_PATH, "NEW PATH", "IS FUNC NOT ARG", argument_access_object.access_symbol, argument_access_object.access_type)
			
			var rev_find = _reverse_search_for_member(function_object, argument_access_object.declaration_symbol)
			print_deb(T.ACCESS_PATH, "NEW PATH", "REV FIND", rev_find)
			
			if rev_find != null:
				if argument_access_object.type.ends_with(ENUM_SUFFIX):
					print_deb(T.ACCESS_PATH, "NEW PATH", "IS NUM")
					to_find_class_path = UString.dot_join(rev_find, argument_access_object.declaration_symbol)
					#return UString.dot_join(symbol, UString.dot_join(rev_find, argument_access_object.declaration_symbol))
					return UString.dot_join(path_access, UString.dot_join(rev_find, argument_access_object.declaration_symbol))
				else:
					var func_script_data = UString.get_script_path_and_suffix(function_object)
					var func_script = load(func_script_data[0])
					print_deb(T.ACCESS_PATH, "NEW PATH", "UN HANDLED")
					#var access = UClassDetail.script_get_member_by_value(func_script,)
		# EXTRACT ??
		
		
		
		
		if access_script_path == to_find_script_path:
			return UString.dot_join(symbol, to_find_class_path)
		else:
			var access = UClassDetail.script_get_member_by_value(access_script, to_find_script, true)
			if access != null:
				return UString.dot_joinv([symbol, access, to_find_class_path])
	
	
	return "NO PATH"
	
	#ALibRuntime.Utils.UProfile.TimeFunction.new("", )
	#tf_test()
	#NewScript3.NestedClass.test_nunu()


func _reverse_search_for_member(full_script_path:String, to_find:String):
	var script_data = UString.get_script_path_and_suffix(full_script_path)
	var script_path = script_data[0]
	var script = load(script_path)
	var class_access = script_data[1] as String
	var search
	if class_access != "":
		for i in range(class_access.count(".") + 1):
			print_deb(T.ACCESS_PATH, "NEW PATH", class_access)
			var class_script = UClassDetail.get_member_info_by_path(script, class_access)
			print_deb(T.ACCESS_PATH, "NEW PATH", class_script)
			if class_script != null:
				search = UClassDetail.get_member_info_by_path(class_script, to_find)
				if search != null:
					break
			
			class_access = UString.trim_member_access_back(class_access)
	
	
	if search == null:
		class_access = ""
		search = UClassDetail.get_member_info_by_path(script, to_find)
	if search != null:
		return class_access

const TF = ALibRuntime.Utils
const TS = TF.UProfile.TimeFunction.TimeScale


func test_vars():
	#test_num_al()
	var n := NewScript3.new()
	n.tf_test_simple(NewScript3.T.TimeScale.MSEC, NewScript3.TS.MSEC)
	n.test_nest(NewScript3.NestedClass.MyNum.TEST)
	n.test_nest_re(NewScript3.NestedClass.Num.TEST)
	var nest = n.get_nest()
	nest.tf_test2(NewScript3.T.TimeScale.USEC)
	nest.test(NewScript3.NestedClass.MyNum.TEST)
	nest.test_rename(NewScript3.NestedClass.Num.TEST)
	nest.test_nunu(NewScript3.NuNu.TEST)
	#nest.tf_test2()
	#nest.test_static()
	
	#n.tf_test(TS.MSEC)
	
	#if n.tf_var == TS.MSEC:
		#pass
	#nest.test(NewScript3.NestedClass.MyNum.TEST)
	#nest.test_rename()
	
	if nest.num_var == NewScript3.NestedClass.MyNum.TEST:
		pass
	
	
	
	
	#tf_test_al()
	
	#tf_test_al()
	#ScriptEditorRef.subscribe()
	
	#var s:= ScriptEditorRef.new()
	#s.subscribe(ScriptEditorRef.Event.CODE_COMPLETION_REQUESTED)
	
	#var ts:TS = TS.USEC
	#ts == 
	
	var t:=TS.MSEC
	#t == 
	
	
	#test_num()
	
	pass


#const Num = NewScript3.NestedClass.Num
const NC = NewScript3.NestedClass

func num_test(n:NC.Num):
	pass

const MyNumAl = MyNum
enum MyNum{
	DSHJKHDSJ,
	DHJSDHJS
}

#const G = ALibRuntime.Utils
#const P = G.UProfile

func test_num_al(m:MyNumAl):
	pass

func test_num(m:MyNum):
	#var g:= G.UProfile.TimeFunction.new("", G.UProfile.TimeFunction.TimeScale.MSEC)
	#
	#var tf = P.TimeFunction.new("", P.TimeFunction.TimeScale.USEC)
	#
	#var n:=NewScript3.new()
	#n.tf_test(NewScript3.T.TimeScale.MSEC)
	#n.tf_test_simple(NewScript3.T.TimeScale.USEC, )
	
	
	#Nested.nother()
	pass

#const TS = TF.TimeScale
#const TF = P.TimeFunction


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
	
	#static func nother(s:TF.TimeScale):
		#pass

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

#const Pro = ALibRuntime.Utils.UProfile

func test(some:=Node.AutoTranslateMode.AUTO_TRANSLATE_MODE_DISABLED):
	pass

func test_base(some:=ConnectFlags.CONNECT_ONE_SHOT):
	#tf_test()
	pass


func tf_test(tf:ALibRuntime.Utils.UProfile.TimeFunction.TimeScale):
	pass

#func tf_test_al(s:Pro.TimeFunction.TimeScale):
	#match s:
		#Pro.TimeFunction.TimeScale.MSEC:
			#pass
		#Pro.TimeFunction.TimeScale.USEC:
			#pass
	#pass













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



#! arg_location section:T
static func print_deb(section:String, ...msg:Array):
	if section in _PRINT:
		msg.push_front(section)
		ALibEditor.PrintDebug.print(msg)

const _PRINT = [
	T.ACCESS_PATH, 
	]


class T:
	const ACCESS_PATH = "ENUM ACCESS PATH"





class EditorSet:
	const ENUM_ENABLE = &"plugin/code_completion/enum/enable"
	const SHOW_MEMBER_SUGGESTIONS = &"plugin/code_completion/enum/show_member_suggestions"
	const SHOW_ALIAS_ONLY = &"plugin/code_completion/enum/show_alias_only"
