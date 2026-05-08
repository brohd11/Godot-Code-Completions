extends EditorCodeCompletion

const TagParser = ALibEditor.Singletons.TagParser

const EditorGDScriptParser = preload("uid://t2dewmuth0sy") #! resolve ALibEditor.Singletons.EditorGDScriptParser

const PREFIX = &"#!"
const TAG = &"keys"

const MODIFIERS = ["clean"]

const DICT_FUNCS_TO_SHOW = ["get", "erase", "get_or_add", "has"]



func _singleton_ready() -> void:
	EditorCodeCompletion.register_tag_static(PREFIX, TAG, EditorCodeCompletionSingleton.TagLocation.ANY)
	SyntaxPlusSingleton.register_highlight_callable(PREFIX, TAG, _syntax_highlighting, SyntaxPlusSingleton.CallableLocation.ANY)
	
	TagParser.register_tag_parser(TAG, self)


func parse_tag(raw_tags:Dictionary) -> Dictionary:
	var mods_string = raw_tags.get("mods", "")
	var args_string = raw_tags.get("args", "")
	
	var mod_data = []
	for string in mods_string.split(" "):
		mod_data.append(string)
	
	var tokens = UString.Token.tokenize_string(args_string).get("tokens")
	var in_type_assign = false
	
	var keys = {}
	var last_token = ""
	for t:String in tokens:
		if t == ":":
			in_type_assign = true
		elif not in_type_assign:
			if t.is_valid_ascii_identifier():
				last_token = t
				keys[t] = ""
		else:
			in_type_assign = false
			if last_token != "":
				keys[last_token] = t
	
	return {
		"keys": keys,
		"modifiers": mod_data
	}


func _on_code_completion_requested(script_editor:CodeEdit) -> bool:
	var caret_context = get_caret_context()
	if caret_context.token_state == CaretContext.TokenState.COMMENT:
		return _comment_completion(script_editor, caret_context)
	else:
		return _standard_completion(script_editor, caret_context)

#! keys i-AnotherTest.; 
func _comment_completion(_script_editor:CodeEdit, caret_context:CaretContext) -> bool:
	
	var comment = caret_context.get_comment()
	if not comment.begins_with(PREFIX) or not comment.get_slice(PREFIX, 1).strip_edges().begins_with(TAG):
		return false
	
	print("&*&*&")
	print(caret_context.word_before_caret)
	print(caret_context.trim_last_member_access_part())
	
	var before_car_text = caret_context.current_line_text.left(caret_context.caret_column)
	var word_before_car = caret_context.word_before_caret
	var text_trimmed = before_car_text.trim_suffix(word_before_car).strip_edges()
	if text_trimmed.ends_with(":"):
		#EditorCodeCompletion.Helpers.class_completion(self, word_before_car, true)
		#return true
		print("TYPEFOR::", word_before_car)
		
		
		return Helpers.member_access_completion(self, Helpers.completion_params({
			"allow_builtin_type": false,
			"allow_user_type": false,
			"global_include": true,
			"global_include_class_preloads": true,
			"global_include_builtin": true,
			
		}))
		
		#var class_obj = caret_context.get_current_class_object()
		#return Helpers.class_completion_from_type(self, word_before_car, class_obj, Helpers.completion_params({
			#"allow_builtin_type": false,
			#"allow_user_type": false,
			#"global_include": true,
			#"global_include_class_preloads": true,
			#"global_include_builtin": true,
			#
		#}))
	elif text_trimmed.ends_with("i-"):
		return Helpers.member_access_completion(self, Helpers.completion_params({
			"allow_builtin_type": false,
			"global_include": true,
			"global_include_class_preloads": true,
			"global_include_builtin": false,
			"user_include_base_type_members": false,
			"is_instance":true,
			"insert_parens": false,
		}))
		
		
		var class_obj = caret_context.get_current_class_object()
		var trimmed_member = caret_context.trim_last_member_access_part()
		if trimmed_member == "":
			trimmed_member = class_obj.get_script_class_path()
		return Helpers.class_completion_from_type(self, trimmed_member, class_obj, Helpers.completion_params({
			"allow_builtin_type": false,
			"global_include": true,
			"global_include_class_preloads": true,
			"global_include_builtin": false,
			"user_include_base_type_members": false,
			"is_instance":true,
			"insert_parens": false,
		}))
	return false

#! keys i-;
func _standard_completion(script_editor:CodeEdit, caret_context:CaretContext) -> bool:
	
	var expr = caret_context.expression_before_caret
	if caret_context.expression_state == CaretContext.ExpressionState.MEMBER_ACCESS:
		#if caret_context.get_last_member_access_part().length() > 2:
			#return false
		var trimmed_expr = UString.trim_member_access_back(expr)
		var dict_data = check_expression_for_meta(trimmed_expr, caret_context.caret_line)
		print("STRUCT DICT")
		print(dict_data)
		if dict_data:
			return process_from_meta_dict(dict_data)
		
		var current_func_data = _get_current_func_tag_data(trimmed_expr)
		if current_func_data:
			return process_from_meta_dict(current_func_data)
		return false
	elif caret_context.is_in_function_call():
		print("FUNC")
		var func_call_data = caret_context.get_function_call_data()
		var func_name = func_call_data.get_function_name()
		var function_path = func_call_data.get_function_script()
		if func_name in DICT_FUNCS_TO_SHOW:
			if func_call_data.current_arg_index > 0:
				return false
		function_path = GDScriptParser.Utils.type_path_add_member(function_path, func_name)
			#member_path = func_call_data.get_function_script()
		
		print("FUNC PATH::", function_path)
		var meta = get_meta_for_type(function_path)
		if meta:
			return process_from_meta_dict(
				meta_dict({
					"meta": meta,
					"meta_origin": function_path,
				}))
		
		var func_call_chain = UString.trim_member_access_back(func_call_data.expression)
		var current_func_data = _get_current_func_tag_data(func_call_chain)
		if current_func_data:
			return process_from_meta_dict(current_func_data)
		
	elif caret_context.is_in_dictionary():
		if caret_context.code_context_stripped.begins_with("return"):
			var current_func_data = _get_current_func_tag_data("", false)
			if current_func_data:
				return process_from_meta_dict(current_func_data)
		elif caret_context.line_declaration.ends_with("func"):
			var current_func_data = _get_current_func_tag_data("", false)
			if current_func_data:
				return process_from_meta_dict(current_func_data)
			
			pass
		
	
	return false

func _get_current_func_tag_data(expression="", limit_to_args:=true):
	var caret_context = get_caret_context()
	var current_class_obj = caret_context.get_current_class_object()
	var current_func = caret_context.get_current_func_object()
	if not current_func:
		return
	
	if limit_to_args:
		var type_rich = caret_context.resolve_expression_to_type_rich(UString.trim_member_access_back(expression))
		if type_rich.member_stack.is_empty():
			return
		var back_member = type_rich.member_stack.back()
		var local_var_data = GDScriptParser.Utils.type_path_get_local_var(back_member)
		if not local_var_data:
			return
		#print(local_var_data)
		if not current_func.arguments.has(local_var_data.member_name):
			return
	
	var function_path = GDScriptParser.Utils.type_path_add_member(current_class_obj.get_script_class_path(), current_func.name)
	var meta = get_meta_for_type(function_path)
	if meta:
		return {
			"meta": meta,
			"meta_origin": function_path,
			}
	

func process_from_meta_dict(dict:Dictionary):
	var sim_call = dict.get("simulated_call", "")
	if sim_call != "":
		return _add_content_completions(dict)
	
	if get_caret_context().get_last_member_access_part().length() > 2:
		return false
	
	var meta = dict.get("meta")
	var mods = meta.get("modifiers")
	if mods.has("clean"):
		return _clean_dict(meta)
	
	var keys = meta.get("keys")
	if not keys.is_empty():
		return _add_dict_key_completions(meta)
	
	return false


# trim the expression for simulated call before it gets here
func _add_content_completions(dict_info:Dictionary):
	#var current_script = get_current_script()
	var caret_context = get_caret_context()
	
	var type_origin = dict_info.get("meta_origin")
	var parser = get_gdscript_parser()
	var class_obj = caret_context.get_current_class_object()
	if GDScriptParser.Utils.is_absolute_path(type_origin):
		var new_parser = parser.get_parser_and_class_obj_for_script(type_origin)
		if new_parser:
			parser = new_parser.parser
			class_obj = new_parser.class_obj
		else:
			print("Could not get parser::", type_origin)
			return false
	
	var simulated_call = dict_info.get("simulated_call")
	var resolved_type = parser.resolve_expression_to_type(simulated_call, class_obj.declaration_line)
	var type_check = GDScriptParser.Utils.type_path_get_type(resolved_type, true)
	if type_check != "":
		resolved_type = type_check
	
	return Helpers.class_completion_from_type(self, simulated_call, class_obj)


func _add_dict_key_completions(tag_data:Dictionary):
	var caret_context = get_caret_context()
	var script_editor = get_code_edit()
	
	var keys_dict = tag_data.get("keys")
	var valid_keys = keys_dict.keys()
	
	var member_access = caret_context.expression_state == ExpressionState.MEMBER_ACCESS
	var func_name = ""
	if caret_context.is_in_function_call():
		var func_call_data = caret_context.get_function_call_data()
		func_name = func_call_data.get_function_name()
	var in_func = not func_name.is_empty()
	var in_dict = caret_context.is_in_dictionary()
	var dict_delim:=""
	
	if member_access:
		pass # if in member access, we are operating on keys of that object not dict
	elif (func_name in DICT_FUNCS_TO_SHOW):# and not in_func:
		pass # if not in func then we can just skio
	elif not in_dict:
		return false
	else: # when in a dict, process the existing keys and only recommend the appropriate ones
		if caret_context.code_context[caret_context.code_context_caret_pos - 1] == ",":
			script_editor.update_code_completion_options(false)
			return false
		
		var dict = caret_context.code_context.substr(caret_context.code_context.find("{") + 1)
		dict = dict.substr(0, UString.rfind_index_safe(dict, "}")).strip_edges()
		var tokens = UString.Token.tokenize_string(dict).get("tokens")
		var in_assign = false
		for t in tokens:
			if t == ":" or t == "=":
				if dict_delim == "":
					dict_delim = t
				else:
					if t != dict_delim:
						continue
				in_assign = true
			elif t == ",":
				in_assign = false
			elif in_assign:
				#in_assign = false
				pass
			else:
				valid_keys.erase(UString.unquote(t))
		
		if in_assign: # if in the dict and not member access, then we can leave
			return false
	
	
	var lua_dict_syntax = false # temp var, should be a setting
	var show_extra_info = false # temp var, should be a setting
	
	if member_access:
		for key in valid_keys:
			var type = keys_dict[key]
			var display = key
			if show_extra_info:
				if type != "":
					if type.is_absolute_path():
						display += " [" + type.get_file() + "]"
					else:
						display += " [" + type + "]"
				display += " [struct dict]"
			
			if type.strip_edges() == "":
				type = "Variant"
			
			var dict = get_code_complete_dict(CodeEdit.KIND_PLAIN_TEXT, display, key, type)
			add_completion_option(script_editor, dict)
	else:
		var is_quoted = caret_context.token_state == TokenState.STRING or caret_context.token_state == TokenState.STRING_NAME
		
		if in_dict and dict_delim == "":
			dict_delim = "=" if lua_dict_syntax else ":"
		
		for key in valid_keys:
			var type = keys_dict[key]
			var key_text = key
			
			var insert = key_text
			if in_dict and not is_quoted:
				if dict_delim == "=":
					insert += "="
				elif dict_delim == ":":
					insert = UString.quote(insert)
					insert += ": "
				
			elif in_func:
				if not is_quoted:
					insert = UString.quote(insert)
			
			var display = key_text
			if insert.begins_with('"'):
				display = UString.quote(display)
			
			if show_extra_info:
				if type != "":
					if type.is_absolute_path():
						display += " [" + type.get_file() + "]"
					else:
						display += " [" + type + "]"
				display += " [struct dict]"
			
			if type.strip_edges() == "":
				type = "Variant"
			
			var dict = get_code_complete_dict(CodeEdit.KIND_VARIABLE, display, insert, type)
			add_completion_option(script_editor, dict)
	
	
	update_completion_options(in_func or in_dict)
	return true

func _clean_dict(tag_data:Dictionary):
	if get_caret_context().get_last_member_access_part().length() > 2:
		return false
	var script_editor = get_code_edit()
	var existing = script_editor.get_code_completion_options()
	var valid = []
	for e in existing:
		if e.get("kind") == CodeEdit.KIND_MEMBER:
			valid.append(e)
	
	for e in valid:
		add_completion_option(script_editor, e)
	update_completion_options()
	return true





#! keys meta_origin:String meta:Dictionary simulated_call:String
func meta_dict(params:={}):
	if not params.has("meta_origin"):
		params["meta_origin"] = ""
	if not params.has("simulated_call"):
		params["simulated_call"] = ""
	if not params.has("meta"):
		params["meta"] = {}
	return params

#! keys i-AnotherTest.;
func check_expression_for_meta(expression:String, line:int=-1):
	var editor_parser = EditorGDScriptParser.get_parser()
	
	var parts = UString.split_member_access(expression)
	var working_path = ""
	
	for i in range(parts.size()):
		var p = parts[i]
		working_path = UString.dot_join(working_path, p)
		var type_rich:Dictionary = editor_parser.resolve_expression_to_type_rich(working_path, line)
		var origin = type_rich.origin
		
		var meta
		if origin != "":
			meta = get_meta_for_type(origin)
		
		#else: # maybe just erase this branch... if you need to access structs in structs, not a great idea
			#var front = type_rich.member_stack.front().get_slice(ParserKeys.MEMBER_STACK_DELIM, 1)
			#var back = type_rich.member_stack.back().get_slice(ParserKeys.MEMBER_STACK_DELIM, 0)
			#if front == back:
				#return {}
			#var data = check_expression_for_meta(front)
			#type_rich = editor_parser.resolve_expression_to_type_rich(data.simulated_call)
			#if type_rich.origin == "":
				#return {}
			#origin = type_rich.origin
			#meta = get_meta_for_type(type_rich.origin)
		
		if meta:
			var tail = ""
			var key = ""
			if parts.size() > i + 1:
				key = parts[i + 1]
				if parts.size() > i + 2:
					for ti in range(i + 2, parts.size()):
						tail = UString.dot_join(tail, parts[ti])
			
			var keys = meta.get("keys")
			var key_type = keys.get(key, "")
			var assembled_tail = ""
			if key_type != "":
				key_type = key_type + ParserKeys.INS_DELIM
				assembled_tail = UString.dot_join(key_type, tail)
			return meta_dict({
				"meta_origin": origin,
				"meta": meta,
				"simulated_call": assembled_tail,
			})
	return {}


func get_meta_for_type(type_origin_string:String):
	if not GDScriptParser.Utils.is_absolute_path(type_origin_string):
		return
	
	var metadata = TagParser.get_metadata_for_type(type_origin_string)
	if not metadata:
		return
	var parser = EditorGDScriptParser.get_parser()
	var next_parser_data = parser.get_parser_and_class_obj_for_script(type_origin_string)
	if not next_parser_data:
		return
	parser = next_parser_data.parser as EditorGDScriptParser.GDScriptParser
	var class_obj = next_parser_data.class_obj
	
	var member_meta = metadata.get(TAG)
	var keys = member_meta.get("keys")
	var mods = member_meta.get("modifiers")
	for m in mods:
		if m.begins_with("i-"):
			var inherited = m.get_slice("i-", 1)
			var resolved = parser.resolve_expression_to_type_rich(inherited, class_obj.declaration_line)
			if not resolved:
				continue
			if resolved.origin == type_origin_string:
				continue
			var recur_meta = get_meta_for_type(resolved.origin)
			if recur_meta:
				keys.merge(recur_meta.get("keys"))
	
	return metadata.get(TAG)


func resolve_tagged_expression(expression:String, line:int=-1):
	var editor_parser = EditorGDScriptParser.get_parser()
	var meta = check_expression_for_meta(expression, line)
	
	
	var sim_call = meta.get("simulated_call", "")
	
	if sim_call != "":
		var resolved = editor_parser.resolve_expression_to_type(sim_call, line)
		print("SIM CALL::", sim_call, "::", resolved)
		return resolved
	return ""


func _syntax_highlighting(_script_editor:CodeEdit, current_line_text:String, line_idx:int, comment_tag_idx:int):
	var comment_text = current_line_text.substr(comment_tag_idx)
	var hl_info = SyntaxPlusSingleton.HLInfo.highlight_prefix(PREFIX, comment_text)
	hl_info.merge(SyntaxPlusSingleton.HLInfo.highlight_tag(TAG, comment_text))
	
	var prefix_end = SyntaxPlusSingleton.HLInfo.get_tag_end_index(PREFIX, TAG, comment_text)
	
	var gdscript_parser = EditorGDScriptParser.get_parser()
	var current_class = gdscript_parser.get_class_at_line(line_idx)
	var current_class_obj = gdscript_parser.get_class_object(current_class) as GDScriptParser.ParserClass
	var script_class_path = current_class_obj.get_script_class_path()
	
	var sp_ins = SyntaxPlusSingleton.get_instance()
	var stripped_comment = comment_text.substr(prefix_end)
	var tokens = UString.Token.tokenize_string(stripped_comment).get("tokens")
	var has_arg_delim = stripped_comment.contains(";")
	var in_args = has_arg_delim
	var in_inh_statement:=false
	var in_type_assign = false
	var idx = 0
	print(tokens)
	for t in tokens:
		idx = stripped_comment.find(t, idx)
		var adj_idx = idx + prefix_end
		if in_args:
			if t == ";":
				in_args = false
				SyntaxPlusSingleton.HLInfo.add_color(hl_info, sp_ins.symbol_color, adj_idx, -1, null, false)
			elif t == "i":
				SyntaxPlusSingleton.HLInfo.add_color(hl_info, sp_ins.DEFAULT_TAG_COLOR, adj_idx, -1, null, false)
				in_inh_statement = true
			elif t == "-":
				if in_inh_statement:
					SyntaxPlusSingleton.HLInfo.add_color(hl_info, sp_ins.comment_color, adj_idx, -1, null, false)
			elif in_inh_statement:
				#hl_info.erase(adj_idx)
				hl_info.merge(SyntaxPlusSingleton.HLInfo.check_const_path(t, script_class_path, adj_idx))
				SyntaxPlusSingleton.HLInfo.add_color(hl_info, sp_ins.comment_color, adj_idx + t.length())
				in_inh_statement = false
			elif t in MODIFIERS:
				SyntaxPlusSingleton.HLInfo.add_color(hl_info, sp_ins.DEFAULT_TAG_COLOR, adj_idx, adj_idx + t.length(), null, false)
			
		elif t == ":":
			SyntaxPlusSingleton.HLInfo.add_color(hl_info, sp_ins.symbol_color, adj_idx, -1, null, false)
			in_type_assign = true
		elif not in_type_assign:
			SyntaxPlusSingleton.HLInfo.add_color(hl_info, sp_ins.default_text_color, adj_idx, adj_idx + t.length())
		else:
			in_type_assign = false
			if GDScriptParser.BuiltInChecker.is_builtin_class(t):
				SyntaxPlusSingleton.HLInfo.add_color(hl_info, sp_ins.engine_type_color, adj_idx, adj_idx + t.length())
			else:
				hl_info.merge(SyntaxPlusSingleton.HLInfo.check_const_path(t, script_class_path, adj_idx))
	
	SyntaxPlusSingleton.HLInfo.add_color(hl_info, sp_ins.comment_color, current_line_text.length(), -1, null, false)
	return hl_info



# examples
#! keys clean;
const Dict = {
	"some_val": "yes"
}

 #! keys string:String object:EditorCodeCompletion another_test:AnotherTest
 #! keys vec:Vector2 material:StandardMaterial3D
static func get_struct(params:Dictionary={}):
	if not params.has("string"):
		params["string"] = "DefaultVal"
	return params
	
	
static func test():
	var d = get_struct()
	
	return {
		
	}


#! keys string:String another:AnotherTest
static func get_ddata(params:={
	"string":"",
	"another":""
}):
	
	
	pass
