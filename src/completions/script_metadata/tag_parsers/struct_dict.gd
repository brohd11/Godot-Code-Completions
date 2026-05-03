extends EditorCodeCompletion.EditorCodeCompletionSingleton.ScriptMetadata.TagParserBase

const EditorGDScriptParser = preload("uid://t2dewmuth0sy") #! resolve ALibEditor.Singletons.EditorGDScriptParser

const PREFIX = &"#!"
const TAG = &"struct_dict"

func _init() -> void:
	#EditorCodeCompletion.unregister_tag_static(PREFIX, TAG)
	EditorCodeCompletion.register_tag_static(PREFIX, TAG, ScriptMetadata.EditorCodeCompletionSingleton.TagLocation.ANY)
	
	#SyntaxPlusSingleton.unregister_highlight_callable(PREFIX, TAG)
	SyntaxPlusSingleton.register_highlight_callable(PREFIX, TAG, _syntax_highlighting, SyntaxPlusSingleton.CallableLocation.ANY)

func parse_tag(tag_string:String) -> Dictionary:
	var data = {}
	print(tag_string)
	var tokens = UString.Token.tokenize_string(tag_string.get_slice(TAG, 1)).get("tokens")
	print(tokens)
	
	var in_type_assign = false
	
	var tag_data = {}
	var last_token = ""
	for t:String in tokens:
		if t == ":":
			in_type_assign = true
		elif not in_type_assign:
			if t.is_valid_ascii_identifier():
				last_token = t
				tag_data[t] = ""
		else:
			in_type_assign = false
			if last_token != "":
				tag_data[last_token] = t
			
	return tag_data


func code_completion_requested(script_editor:CodeEdit) -> bool:
	
	var caret_context = script_metadata.get_caret_context()
	if caret_context.token_state == CaretContext.TokenState.COMMENT:
		return _comment_completion(script_editor, caret_context)
	else:
		return _standard_completion(script_editor, caret_context)


func _comment_completion(_script_editor:CodeEdit, caret_context:CaretContext) -> bool:
	var comment = caret_context.get_comment()
	if not comment.begins_with(PREFIX) or not comment.get_slice(PREFIX, 1).strip_edges().begins_with(TAG):
		return false
	
	var before_car_text = caret_context.current_line_text.left(caret_context.caret_column)
	var word_before_car = caret_context.word_before_caret
	if before_car_text.trim_suffix(word_before_car).strip_edges().ends_with(":"):
		EditorCodeCompletion.Helpers.class_completion(script_metadata, word_before_car, true)
		return true
	return false

func _standard_completion(script_editor:CodeEdit, caret_context:CaretContext) -> bool:
	
	#var get_options = script_editor.get_code_completion_options()
	#for o in get_options:
		#print(o)
	
	var expr = caret_context.expression_before_caret
	var func_name = ""
	var accessing_struct_member:=""
	var member_path:String
	if caret_context.expression_state == CaretContext.ExpressionState.ASSIGNMENT:
		var op_data = caret_context.get_operation_data()
		member_path = GDScriptParser.Utils.type_path_get_member(op_data.left_symbol_data.type)
		print("ASSIGN", member_path)
	elif caret_context.expression_state == CaretContext.ExpressionState.MEMBER_ACCESS:
		print("MEMBER")
		var trimmed_expression = UString.trim_member_access_back(expr)
		member_path = caret_context.resolve_expression_to_type(trimmed_expression)
		print(member_path)
		if not GDScriptParser.Utils.type_path_get_type(member_path).begins_with("Dictionary"):
			accessing_struct_member =  UString.trim_member_access_front(expr)
			var first_member = UString.get_member_access_front(expr)
			member_path = caret_context.resolve_expression_to_type(first_member)
			print(first_member)
			print(accessing_struct_member)
			print(member_path)
	elif caret_context.is_in_function_call():
		print("FUNC")
		var func_call_data = caret_context.get_function_call_data()
		func_name = func_call_data.get_function_name()
		if func_name == "get" and func_name == "erase":
			member_path = func_call_data.get_function_script()
		else:
			member_path = GDScriptParser.Utils.type_path_add_member(func_call_data.get_function_script(), func_call_data.get_function_name())
		
	
	elif caret_context.is_in_dictionary_access():
		var access = caret_context.get_index_access_identifier()
		
		print("ACESS")
		print(access)
	
	if member_path == "":
		return false
	
	var member_name = ""
	if member_path.contains(GDScriptParser.Keys.MEMBER_DELIM):
		member_name = GDScriptParser.Utils.type_path_get_member(member_path)
	if member_name == "":
		return false
	
	var path = ""
	if GDScriptParser.Utils.is_absolute_path(member_path):
		path = GDScriptParser.Utils.type_path_get_non_member(member_path)
	
	var script_data = UString.get_script_path_and_suffix(path)
	if script_data.is_empty():
		return false
	var main_script_path = script_data[0]
	var class_access = script_data[1]
	member_name = UString.dot_join(class_access, member_name)
	
	var metadata = _get_tag_metadata(TAG, main_script_path)
	print("MEMBER::", member_path)
	print("FULL PATH")
	print(path)
	print("FULL PATH")
	print("META")
	
	print(metadata)
	if metadata == null:
		return false
	metadata = metadata as Dictionary
	
	var member_tag_data = metadata.get(member_name)
	if member_tag_data == null:
		return false
	
	var in_func = not func_name.is_empty()
	var in_dict = caret_context.is_in_dictionary()
	var dict_delim:=""
	
	var valid_keys = member_tag_data.keys()
	print("BREAK")
	if not in_func or func_name == "get" or func_name == "erase":
		pass
		#for key in member_tag_data.keys():
			#var type = member_tag_data[key]
			#var key_text = key
			#if in_func:
				#key_text = UString.quote(key_text)
			#var display = key_text
			#if type != "":
				#display += " [" + type + "]"
			#display += " [struct dict]"
			#var insert = key_text
			#var dict = script_metadata.get_code_complete_dict(CodeEdit.KIND_PLAIN_TEXT, display, insert, type)
			#script_metadata.add_completion_option(script_editor, dict)
	else:
		print("HERE")
		print(caret_context.code_context)
		if not in_dict:
			return false
		else:
			if caret_context.code_context[caret_context.code_context_caret_pos - 1] == ",":
				script_editor.update_code_completion_options(false)
				return false
			if caret_context.expression_state == CaretContext.ExpressionState.MEMBER_ACCESS:
				return false
			
			var dict = caret_context.code_context.substr(caret_context.code_context.find("{") + 1)
			dict = dict.substr(0, UString.rfind_index_safe(dict, "}")).strip_edges()
			var tokens = UString.Token.tokenize_string(dict).get("tokens")
			var in_assign = false
			#var used_keys = []
			print(tokens)
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
			
			print(in_assign)
			if in_assign:
				return false
			
			print(dict)
	
	if accessing_struct_member != "":
		var dict_access = UString.get_member_access_front(accessing_struct_member)
		var member_type = member_tag_data.get(dict_access)
		if member_type == null:
			return false
		var sim_call_chain = accessing_struct_member.get_slice(dict_access, 1).trim_prefix(".")
		sim_call_chain = UString.dot_join(member_type, sim_call_chain)
		sim_call_chain = UString.trim_member_access_back(sim_call_chain)
		print(sim_call_chain)
		var resolved_type = caret_context.resolve_expression_to_type(sim_call_chain)
		var type_check = GDScriptParser.Utils.type_path_get_type(resolved_type, true)
		if type_check != "":
			resolved_type = type_check
		
		if GDScriptParser.BuiltInChecker.is_builtin_class(resolved_type):
			var class_data = GDScriptParser.BuiltInChecker.get_class_data(resolved_type)
			for member:StringName in class_data.keys():
				print(class_data[member])
				var data = class_data[member]
				var class_member_type = data.get(GDScriptParser.BuiltInChecker.MEMBER_TYPE)
				
				#var is_constant = data.get("is_constant")
				var is_static = data.get("is_static", false)
				if is_static:
					continue
				var display = member
				var insert = member
				var icon = "member"
				var kind:CodeEdit.CodeCompletionKind
				var font_color = EditorCodeCompletion.Helpers.Colors.DEFAULT_COMPLETION
				if class_member_type == &"constants":
					icon = "const"
					kind = CodeEdit.KIND_CONSTANT
				elif class_member_type == &"methods":
					icon = "method"
					kind = CodeEdit.KIND_FUNCTION
					var arguments = data.get("arguments", [])
					if arguments.is_empty():
						display = member + "()"
						insert = member + "()"
					else:
						display = member + EditorCodeCompletion.Helpers.DOTS_UNICODE
						insert = member + "("
				elif class_member_type == &"members":
					icon = "property"
					kind = CodeEdit.KIND_MEMBER
					if member == "x":
						font_color = EditorCodeCompletion.Helpers.Colors.AXIS_X
					elif member == "y":
						font_color = EditorCodeCompletion.Helpers.Colors.AXIS_Y
					elif member == "z":
						font_color = EditorCodeCompletion.Helpers.Colors.AXIS_Z
					elif member == "w":
						font_color = EditorCodeCompletion.Helpers.Colors.AXIS_W
				
				var dict = script_metadata.get_code_complete_dict(kind, display, insert, icon, null, 1024, font_color)
				script_metadata.add_completion_option(script_editor, dict)
			
			script_metadata.update_completion_options(true)
		else:
			print("OTHER")
			print(resolved_type)
			var parser_for_res = script_metadata.get_gdscript_parser().get_parser_and_class_obj_for_script(resolved_type)
			if not parser_for_res:
				return false
			
			var res_member = GDScriptParser.Utils.type_path_get_member(resolved_type)
			print(res_member)
			var class_obj = parser_for_res.class_obj as GDScriptParser.ParserClass
			
			var members = class_obj.get_members()
			var inherited_members = class_obj.get_inherited_members()
			for dict in [members, inherited_members]:
				for member in dict:
					var member_data = dict[member]
					var script_member_type = member_data.get(GDScriptParser.Keys.MEMBER_TYPE)
					
					var display = member
					var insert = member
					var icon = "member"
					var kind:CodeEdit.CodeCompletionKind
					var font_color = EditorCodeCompletion.Helpers.Colors.DEFAULT_COMPLETION
					if script_member_type == GDScriptParser.Keys.MEMBER_TYPE_CONST:
						icon = "const"
						kind = CodeEdit.KIND_CONSTANT
					elif script_member_type.ends_with("func"):
						icon = "method"
						kind = CodeEdit.KIND_FUNCTION
						var func_obj = class_obj.get_function(member) as GDScriptParser.ParserFunc
						if func_obj.get_arguments().is_empty():
							display = member + "()"
							insert = member + "()"
						else:
							display = member + EditorCodeCompletion.Helpers.DOTS_UNICODE
							insert = member + "("
					else:
						icon = "property"
						kind = CodeEdit.KIND_MEMBER
						if member == "x":
							font_color = EditorCodeCompletion.Helpers.Colors.AXIS_X
						elif member == "y":
							font_color = EditorCodeCompletion.Helpers.Colors.AXIS_Y
						elif member == "z":
							font_color = EditorCodeCompletion.Helpers.Colors.AXIS_Z
						elif member == "w":
							font_color = EditorCodeCompletion.Helpers.Colors.AXIS_W
					
					var cc_dict = script_metadata.get_code_complete_dict(kind, display, insert, icon, null, 1024, font_color)
					script_metadata.add_completion_option(script_editor, cc_dict)
			
			script_metadata.update_completion_options(true)
		
		
		return true
	
	var lua_dict_syntax = false #^ dsds
	
	print("VALID")
	print(valid_keys)
	
	for key in valid_keys:
		var type = member_tag_data[key]
		var key_text = key
		
		var insert = key_text
		if in_dict:
			if dict_delim == "":
				dict_delim = "=" if lua_dict_syntax else ":"
			if dict_delim == "=":
				insert += "="
			elif dict_delim == ":":
				insert = UString.quote(insert)
				insert += ": "
			
		elif in_func:
			insert = UString.quote(insert)
		
		var display = key_text
		if insert.begins_with('"'):
			display = UString.quote(display)
		#if type != "":
			#display += " [" + type + "]"
		#display += " [struct dict]"
		
		if type.strip_edges() == "":
			type = "Variant"
		
		var dict = script_metadata.get_code_complete_dict(CodeEdit.KIND_PLAIN_TEXT, display, insert, type)
		script_metadata.add_completion_option(script_editor, dict)
	
	
	script_metadata.update_completion_options(in_func or in_dict)
	return true
	
	
	

static func test():
	var my_struct = get_struct({
		string="Some Message",
		object=Vector2.DOWN
	})
	var my_s = get_struct()
	my_s.object
	#my_s.
	if my_struct.object == null:
		print("No Obj")
	print("")


 #! struct_dict string:String object:EditorCodeCompletion
 #! struct_dict vec:Vector2
 #

static func get_struct(params:Dictionary={}):
	if not params.has("string"):
		params["string"] = "DefaultVal"
	
	return params

func _syntax_highlighting(_script_editor:CodeEdit, current_line_text:String, line_idx:int, comment_tag_idx:int):
	var comment_text = current_line_text.substr(comment_tag_idx)
	var hl_info = SyntaxPlusSingleton.HLInfo.highlight_prefix(PREFIX, comment_text)
	hl_info.merge(SyntaxPlusSingleton.HLInfo.highlight_tag(TAG, comment_text))
	
	var prefix_end = SyntaxPlusSingleton.HLInfo.get_tag_end_index(PREFIX, TAG, comment_text)
	print("PREFIX::", prefix_end)
	var gdscript_parser = script_metadata.get_gdscript_parser()
	var current_class = gdscript_parser.get_class_at_line(line_idx)
	var current_class_obj = gdscript_parser.get_class_object(current_class) as GDScriptParser.ParserClass
	var script_class_path = current_class_obj.get_script_class_path()
	
	var sp_ins = SyntaxPlusSingleton.get_instance()
	var stripped_comment = comment_text.substr(prefix_end)
	var tokens = UString.Token.tokenize_string(stripped_comment).get("tokens")
	var in_type_assign = false
	var idx = 0
	for t in tokens:
		idx = stripped_comment.find(t, idx)
		var adj_idx = idx + prefix_end
		if t == ":":
			SyntaxPlusSingleton.HLInfo.add_color(hl_info, sp_ins.symbol_color, adj_idx, -1, null, false)
			in_type_assign = true
		elif not in_type_assign:
			SyntaxPlusSingleton.HLInfo.add_color(hl_info, sp_ins.default_text_color, adj_idx, adj_idx + t.length())
		else:
			in_type_assign = false
			if GDScriptParser.BuiltInChecker.is_builtin_class(t):
				SyntaxPlusSingleton.HLInfo.add_color(hl_info, sp_ins.engine_type_color, adj_idx, adj_idx + t.length())
			else:
				print("const::", SyntaxPlusSingleton.HLInfo.check_const_path(t, script_class_path, adj_idx))
				hl_info.merge(SyntaxPlusSingleton.HLInfo.check_const_path(t, script_class_path, adj_idx))
	
	SyntaxPlusSingleton.HLInfo.add_color(hl_info, sp_ins.comment_color, current_line_text.length(), -1, null, false)
	return hl_info
	#return SyntaxPlusSingleton.HLInfo.sort_keys(hl_info)
