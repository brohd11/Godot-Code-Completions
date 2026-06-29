extends EditorCodeCompletion

const SettingHelper = UtilsRemote.SettingHelperEditor
const TagParser = UtilsRemote.TagParser

const PREFIX = &"#!"
const TAG = &"keys"

const INVALID_ACCESS = "-invalid_access"

const MODIFIERS = ["clean", "sort"]

const DICT_FUNCS_TO_SHOW = ["get", "erase", "get_or_add", "has"]

#var _setting_helper:SettingHelper
var _enable:bool = true
var _prefer_lua_style:bool = false
var _prefer_string_name:bool = true

var _code_hint_line = -1


func _singleton_ready() -> void:
	EditorCodeCompletion.register_tag_static(PREFIX, TAG, EditorCodeCompletionSingleton.TagLocation.ANY)
	SyntaxPlusSingleton.register_highlight_callable(PREFIX, TAG, _syntax_highlighting, SyntaxPlusSingleton.CallableLocation.ANY)
	
	TagParser.register_tag_parser(TAG, self)

func register_editor_settings(settings_helper:SettingHelperEditor):
	settings_helper.subscribe_property(self, &"_enable", EditorSet.ENABLE, true)
	settings_helper.subscribe_property(self, &"_prefer_lua_style", EditorSet.PREFER_LUA_STYLE, false)
	settings_helper.subscribe_property(self, &"_prefer_string_name", EditorSet.PREFER_STRING_NAME, true)

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
			#if t.is_valid_ascii_identifier():
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

func _on_editor_script_changed(script) -> void:
	_code_hint_line = -1

func _on_code_completion_requested(script_editor:CodeEdit) -> bool:
	if not _enable:
		return false
	
	var caret_context = get_caret_context()
	
	if _code_hint_line > -1:
		if _code_hint_line == caret_context.caret_line:
			script_editor.set_code_hint("")
		_code_hint_line = -1
	
	if caret_context.token_state == CaretContext.TokenState.COMMENT:
		return _comment_completion(script_editor, caret_context)
	else:
		return _standard_completion(script_editor, caret_context)


func _comment_completion(script_editor:CodeEdit, caret_context:CaretContext) -> bool:
	var comment = caret_context.get_comment()
	if not comment.begins_with(PREFIX) or not comment.get_slice(PREFIX, 1).strip_edges().begins_with(TAG):
		return false
	
	var before_car_text = caret_context.current_line_text.left(caret_context.caret_column)
	var word_before_car = caret_context.word_before_caret
	var text_trimmed = before_car_text.trim_suffix(word_before_car).strip_edges()
	if text_trimmed.ends_with(":"):
		return Helpers.member_access_completion(self, Helpers.completion_params({
			"allow_builtin_type": false,
			"allow_user_type": false,
			"global_include": true,
			"global_include_class_preloads": true,
			"global_include_builtin": true,
		}))
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
	elif caret_context.current_line_text.find(";", caret_context.caret_column) > -1:
		var comment_sliced = comment.get_slice(TAG, 1)
		var current_args_str = comment_sliced.substr(0, comment_sliced.find(";"))
		var current_args = current_args_str.split(" ", false)
		for arg in MODIFIERS:
			if not arg in current_args:
				var dict = get_code_complete_dict(CodeEdit.KIND_PLAIN_TEXT, arg, arg, Helpers.TAG_ICON_NAME)
				add_completion_option(script_editor, dict)
		update_completion_options(true)
		return true
	return false


func _standard_completion(_script_editor:CodeEdit, caret_context:CaretContext) -> bool:
	if caret_context.expression_state == CaretContext.ExpressionState.MEMBER_ACCESS:
		# check member access of the accessed dict
		var trimmed_expr = caret_context.trim_last_member_access_part()
		var dict_data = check_expression_for_meta(trimmed_expr, caret_context.caret_line)
		if dict_data:
			return process_from_meta_dict(dict_data)
		
		# hasn't been found, check if it's a dictionary in args
		var current_func_data = _get_current_func_tag_data(trimmed_expr)
		if current_func_data:
			return process_from_meta_dict(current_func_data)
		return false
	elif caret_context.is_in_function_call():
		var func_call_data = caret_context.get_function_call_data()
		var func_name = func_call_data.get_function_name()
		var function_path = func_call_data.get_function_script()
		
		# absolute path, check for data with the current accessed func
		if GDScriptParser.Utils.is_absolute_path(function_path):
			if func_name in DICT_FUNCS_TO_SHOW:
				if func_call_data.current_arg_index > 0:
					return false
			function_path = GDScriptParser.Utils.type_path_add_member(function_path, func_name)
			var meta = get_meta_for_type(function_path)
			if meta:
				return process_from_meta_dict(
					meta_dict({
						"meta": meta,
						"meta_origin": function_path,
					}))
		
		# if in a func call of a dictionary arg of current func, display keys
		var func_call_chain:String = UString.trim_member_access_back(func_call_data.expression)
		var current_func_data = _get_current_func_tag_data(func_call_chain)
		if current_func_data:
			return process_from_meta_dict(current_func_data)
		
		# last thing, if the meta can be found, resolve and display a code hint
		var call_chain_meta = check_expression_for_meta(func_call_chain, caret_context.caret_line)
		if call_chain_meta and call_chain_meta.simulated_call != INVALID_ACCESS:
			var sim_type = caret_context.resolve_expression_to_type(call_chain_meta.simulated_call).trim_suffix(ParserKeys.INS_DELIM)
			if sim_type:
				Helpers.set_code_hint(self, sim_type, func_name)
				_code_hint_line = caret_context.caret_line
		
	elif caret_context.is_in_dictionary():
		# in return raw dict declaration or in arg default param
		if caret_context.code_context_stripped.begins_with("return") or caret_context.line_declaration.ends_with("func"):
			var current_func_data = _get_current_func_tag_data("", false)
			if current_func_data:
				return process_from_meta_dict(current_func_data)
			
	elif caret_context.is_in_dictionary_access():
		# check current expression for meta, direct[access]
		var access_id:String = caret_context.get_index_access_identifier()
		var dict_data = check_expression_for_meta(access_id, caret_context.caret_line)
		if dict_data:
			return process_from_meta_dict(dict_data)
		
		# if not check for local arg dict
		var current_func_data = _get_current_func_tag_data(access_id)
		if current_func_data:
			return process_from_meta_dict(current_func_data)
	
	return false


func process_from_meta_dict(dict:Dictionary) -> bool:
	var sim_call:String = dict.get("simulated_call", INVALID_ACCESS)
	if sim_call != INVALID_ACCESS and not sim_call.is_empty():
		return _add_content_completions(dict)
	
	#if _check_member_access_length():
		#return false
	
	var meta:Dictionary = dict.get("meta")
	var mods:Array = meta.get("modifiers")
	var keys:Dictionary = meta.get("keys")
	if not keys.is_empty():
		return _add_dict_key_completions(dict)
	
	if mods.has("clean") or mods.has("sort"):
		return _clean_dict(meta)
	
	return false


# trim the expression for simulated call before it gets here
func _add_content_completions(dict_info:Dictionary):
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
	
	return Helpers.class_completion_from_type(self, resolved_type, class_obj)


func _add_dict_key_completions(_meta_dict:Dictionary):
	var caret_context = get_caret_context()
	var script_editor = get_code_edit()
	var meta = _meta_dict.get("meta")
	var keys_dict = meta.get("keys")
	var valid_keys = keys_dict.keys()
	
	var mods:Array = meta.get("modifiers", [])
	var clean:bool = mods.has("clean")
	var sort:bool = mods.has("sort")
	
	var member_access = caret_context.expression_state == ExpressionState.MEMBER_ACCESS
	var func_name = ""
	if caret_context.is_in_function_call():
		var func_call_data = caret_context.get_function_call_data()
		func_name = func_call_data.get_function_name()
	var in_func = not func_name.is_empty()
	var in_dict = caret_context.is_in_dictionary()
	var in_dict_index_access = caret_context.is_in_dictionary_access()
	var dict_delim:=""
	
	if member_access or in_dict_index_access:
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
	
	var show_extra_info = false # temp var, should be a setting.. this can probably be removed...
	var key_location = CodeEdit.LOCATION_LOCAL
	
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
			
			var dict = get_code_complete_dict(CodeEdit.KIND_PLAIN_TEXT, display, key, type, null, key_location)
			add_completion_option(script_editor, dict)
	else:
		if in_dict and dict_delim == "":
			dict_delim = "=" if _prefer_lua_style else ":"
		
		var in_string = caret_context.token_state == TokenState.STRING or caret_context.token_state == TokenState.STRING_NAME
		var needs_quote = (dict_delim and dict_delim == ":") or in_func or in_dict_index_access
		
		var color = Helpers.Colors.DEFAULT_COMPLETION
		if not (in_dict and dict_delim == "=") and (in_string or needs_quote):
			if _prefer_string_name and not caret_context.token_state == TokenState.STRING:
				color = UtilsRemote.EditorColors.get_syntax_color(UtilsRemote.EditorColors.SyntaxColor.STRING_NAME)
			else:
				color = UtilsRemote.EditorColors.get_syntax_color(UtilsRemote.EditorColors.SyntaxColor.STRING)
		
		for key in valid_keys:
			var type = keys_dict[key]
			var key_text = key
			
			var insert = key_text
			if in_dict and not in_string:
				if dict_delim == "=":
					insert += "="
				elif dict_delim == ":":
					insert = UString.quote(insert)
					if _prefer_string_name:
						insert = "&" + insert
					insert += ": "
				
			elif in_func or in_dict_index_access:
				if not in_string:
					insert = UString.quote(insert)
					if _prefer_string_name:
						insert = "&" + insert
			
			var display = key_text
			if insert.begins_with('"') or insert.begins_with('&"'):
				display = UString.quote(display)
				if _prefer_string_name:
					display = "&" + display
			
			if show_extra_info:
				if type != "":
					if type.is_absolute_path():
						display += " [" + type.get_file() + "]"
					else:
						display += " [" + type + "]"
				display += " [struct dict]"
			
			if type.strip_edges() == "":
				type = "Variant"
			
			var dict = get_code_complete_dict(CodeEdit.KIND_VARIABLE, display, insert, type, null, key_location, color)
			add_completion_option(script_editor, dict)
	
	if not clean and not (in_dict or in_dict_index_access):
		_add_dict_methods()
	
	update_completion_options(in_func or in_dict)
	return true



func _clean_dict(_meta_dict:Dictionary):
	#if _check_member_access_length():
		#return false
	
	var mods:Array = _meta_dict.get("modifiers", [])
	var clean:bool = mods.has("clean")
	var sort:bool = mods.has("sort")
	
	var script_editor = get_code_edit()
	var existing = script_editor.get_code_completion_options()
	var valid = []
	for e in existing:
		if e.get("kind") == CodeEdit.KIND_MEMBER:
			e.location = CodeEdit.LOCATION_LOCAL
			valid.append(e)
	
	for e in valid:
		add_completion_option(script_editor, e)
	
	if not clean or sort:
		_add_dict_methods()
	
	update_completion_options()
	return true


func _add_dict_methods():
	Helpers.built_in_completion(self, "Dictionary", true, {
		"update": false,
	})

func _check_member_access_length():
	return get_caret_context().get_last_member_access_part().length() > 2


#! keys meta_origin:String meta:Dictionary simulated_call:String
func meta_dict(params:={}):
	if not params.has("meta_origin"):
		params["meta_origin"] = ""
	if not params.has("simulated_call"):
		params["simulated_call"] = INVALID_ACCESS
	if not params.has("meta"):
		params["meta"] = {}
	return params

#! keys i-meta_dict;
func check_expression_for_meta(expression:String, line:int=-1):
	var editor_parser:EditorGDScriptParser.GDScriptParser = EditorGDScriptParser.get_parser()

	var parts:Array = UString.split_member_access(expression)
	var working_path:String = ""
	
	for i:int in range(parts.size()):
		var p:Variant = parts[i]
		var index:String = ""
		if p.find("[") > 0: # greater than 0, so it can't start with
			index = p.substr(p.find("["))
			p = p.substr(0, p.find("["))
		
		working_path = UString.dot_join(working_path, p)
		var type_rich:Dictionary = editor_parser.resolve_expression_to_type_rich(working_path, line)
		var origin = type_rich.origin
		
		var meta
		if origin != "":
			if origin == "Dictionary" and not type_rich.member_stack.is_empty():
				var local_var_check = _get_local_var_function_data(type_rich)
				if local_var_check != "":
					origin = local_var_check
			
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
			var member_data = editor_parser.get_member_data_from_origin(origin)
			if not member_data:
				return {}
			var member_type = member_data.get(ParserKeys.MEMBER_TYPE)
			# if this is a const and it is not the last in the chain, can process the autocomplete through the built in
			if member_type == ParserKeys.MEMBER_TYPE_CONST and i != parts.size() - 1:
				return {}
			
			var tail:String = ""
			var key:String = ""
			if index != "":
				key = index
				if parts.size() > i + 1:
					for ti:int in range(i + 1, parts.size()):
						tail = UString.dot_join(tail, parts[ti])
			elif parts.size() > i + 1:
				key = parts[i + 1]
				if parts.size() > i + 2:
					for ti:int in range(i + 2, parts.size()):
						tail = UString.dot_join(tail, parts[ti])
			
			
			key = _get_meta_key(key)
			var keys = meta.get("keys")
			var key_type = keys.get(key, "")
			var assembled_tail = ""
			if key == "":
				pass # no key means end of chain
			elif key_type != "":
				key_type = key_type + ParserKeys.INS_DELIM
				assembled_tail = UString.dot_join(key_type, tail)
			else:
				assembled_tail = INVALID_ACCESS
			
			return meta_dict({
				"meta_origin": origin,
				"meta": meta,
				"simulated_call": assembled_tail,
			})
	return {}


func _get_meta_key(full_part:String):
	if full_part.ends_with(")"):
		var func_name = full_part.substr(0, full_part.find("(")).strip_edges()
		if func_name == "get" or func_name == "get_or_add":
			var trimmed = full_part.trim_prefix(func_name + "(").trim_suffix(")")
			if UString.is_string_or_string_name(trimmed):
				return UString.unquote(trimmed)
	elif full_part.ends_with("]"):
		var trimmed = full_part.trim_suffix("]").trim_prefix("[")
		if UString.is_string_or_string_name(trimmed):
			return UString.unquote(trimmed)
	
	return full_part


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
	if not member_meta:
		return
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


func _get_current_func_tag_data(expression="", limit_to_args:=true):
	var caret_context = get_caret_context()
	var current_class_obj = caret_context.get_current_class_object()
	var current_func = caret_context.get_current_func_object()
	if not current_func:
		return
	
	var function_path:String
	if limit_to_args:
		var type_rich = caret_context.resolve_expression_to_type_rich(expression)
		var local_var_check = _get_local_var_function_data(type_rich)
		if local_var_check == "":
			return
		function_path = local_var_check
	else:
		function_path = GDScriptParser.Utils.type_path_add_member(current_class_obj.get_script_class_path(), current_func.name)
	
	var meta = get_meta_for_type(function_path)
	if meta:
		return {
			"meta": meta,
			"meta_origin": function_path,
			}

#! keys i-GDScriptParser.resolve_expression_to_type_rich;
func _get_local_var_function_data(type_rich:Dictionary, limit_to_arg:=true):
	if type_rich.origin != "Dictionary" or type_rich.member_stack.is_empty():
		return ""
	var back = type_rich.member_stack.back().get_slice(ParserKeys.MEMBER_STACK_DELIM, 0)
	var local_var_data = GDScriptParser.Utils.type_path_get_local_var(back)
	if not local_var_data:
		return ""
	var parser_data = EditorGDScriptParser.get_parser().get_parser_and_class_obj_for_script(back)
	var class_obj = parser_data.class_obj as GDScriptParser.ParserClass
	var func_obj = class_obj.get_function(class_obj.get_function_at_line(local_var_data.line))
	if limit_to_arg:
		if not func_obj.get_arguments().has(local_var_data.member_name):
			return ""
	return GDScriptParser.Utils.type_path_add_member(class_obj.get_script_class_path(), func_obj.name)

func resolve_tagged_expression(expression:String, line:int=-1):
	var editor_parser = EditorGDScriptParser.get_parser()
	var meta = check_expression_for_meta(expression, line)
	
	var sim_call = meta.get("simulated_call", INVALID_ACCESS)
	if sim_call != INVALID_ACCESS:
		var resolved = editor_parser.resolve_expression_to_type(sim_call, line)
		#print("SIM CALL::", sim_call, "::", resolved)
		return resolved
	return ""



func _syntax_highlighting(_script_editor:CodeEdit, current_line_text:String, line_idx:int, comment_tag_idx:int):
	var comment_text = current_line_text.substr(comment_tag_idx)
	var hl_info = SyntaxPlusSingleton.HLInfo.highlight_prefix(PREFIX, comment_text)
	hl_info.merge(SyntaxPlusSingleton.HLInfo.highlight_tag(TAG, comment_text))
	
	var prefix_end = SyntaxPlusSingleton.HLInfo.get_tag_end_index(PREFIX, TAG, comment_text)
	
	#var gdscript_parser = EditorGDScriptParser.get_parser()
	var gdscript_parser = SyntaxPlusSingleton.get_gdscript_parser() # use this one since it just needs the members, no type inference
	if not is_instance_valid(gdscript_parser):
		return {}
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
	
	for t in tokens:
		idx = stripped_comment.find(t, idx)
		var adj_idx = idx + prefix_end
		var adj_token_end = adj_idx + t.length()
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
				hl_info.merge(SyntaxPlusSingleton.HLInfo.check_const_path(t, script_class_path, adj_idx))
				SyntaxPlusSingleton.HLInfo.add_color(hl_info, sp_ins.comment_color, adj_token_end)
				in_inh_statement = false
			elif t in MODIFIERS:
				SyntaxPlusSingleton.HLInfo.add_color(hl_info, sp_ins.DEFAULT_TAG_COLOR, adj_idx, adj_token_end, null, false)
			
		elif t == ":":
			SyntaxPlusSingleton.HLInfo.add_color(hl_info, sp_ins.symbol_color, adj_idx, -1, null, false)
			in_type_assign = true
		elif not in_type_assign:
			SyntaxPlusSingleton.HLInfo.add_color(hl_info, sp_ins.default_text_color, adj_idx, adj_token_end)
		else:
			in_type_assign = false
			if GDScriptParser.BuiltInChecker.is_builtin_class(t):
				SyntaxPlusSingleton.HLInfo.add_color(hl_info, sp_ins.engine_type_color, adj_idx, adj_token_end)
			else:
				hl_info.merge(SyntaxPlusSingleton.HLInfo.check_const_path(t, script_class_path, adj_idx))
	
	SyntaxPlusSingleton.HLInfo.add_color(hl_info, sp_ins.comment_color, current_line_text.length(), -1, null, false)
	return hl_info

class EditorSet:
	const ENABLE = &"plugin/code_completion/dict_key/enable"
	const PREFER_LUA_STYLE = &"plugin/code_completion/dict_key/prefer_lua_style"
	const PREFER_STRING_NAME = &"plugin/code_completion/dict_key/prefer_string_name"


# examples
#! keys clean;
const Dict = {
	"key1": "",
	"key2": "",
	"key3": "",
	"key4": "",
	"key5": "",
}

#! keys sort;
const SortedDict = {
	"key1": "",
	"key2": "",
	"key3": "",
	"key4": "",
	"key5": "",
}

#! keys string:String vec:Vector2 material:StandardMaterial3D
static func get_dict(params:Dictionary={}):
	if not params.has("string"):
		params["string"] = "DefaultVal"
	return params

#! keys i-NewScript.create_dict; another_key:String
var inh_dict = {}

func test():
	get_dict({
		
	})
	
	var data = get_dict()
	#data.vec
	
	#var d = AnotherTest.NestStruct.get_struct({
		#
	#})
	
	
	pass
