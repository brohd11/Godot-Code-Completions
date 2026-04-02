extends EditorCodeCompletion.EditorCodeCompletionSingleton.ScriptMetadata.TagParserBase

const EditorGDScriptParser = ALibEditor.Singletons.EditorGDScriptParser

const EditorColors = UtilsRemote.EditorColors

const TAG = &"arg_location"

const TAG_ARGS = ["d", "deep"]
const _BAD_SYM_COLOR = Color.FIREBRICK

var _comment_color:Color
var _text_color:Color
var _type_color:Color
var _sym_color:Color
var _global_color:Color


func _init() -> void:
	EditorCodeCompletion.unregister_tag_static("#!", TAG)
	EditorCodeCompletion.register_tag_static("#!", TAG, ScriptMetadata.EditorCodeCompletionSingleton.TagLocation.ANY)
	
	SyntaxPlusSingleton.unregister_highlight_callable("#!", TAG)
	SyntaxPlusSingleton.register_highlight_callable("#!", TAG, _syntax_highlighting, SyntaxPlusSingleton.CallableLocation.ANY)
	
	_on_editor_settings_changed()
	EditorInterface.get_editor_settings().settings_changed.connect(_on_editor_settings_changed)

func _on_editor_settings_changed():
	_comment_color = EditorColors.get_syntax_color(EditorColors.SyntaxColor.COMMENT)
	_text_color = EditorColors.get_syntax_color(EditorColors.SyntaxColor.TEXT)
	_type_color = EditorColors.get_syntax_color(EditorColors.SyntaxColor.BASE_TYPE)
	_sym_color = EditorColors.get_syntax_color(EditorColors.SyntaxColor.SYMBOL)
	_global_color = EditorColors.get_syntax_color(EditorColors.SyntaxColor.USER_TYPE)


func parse_tag(tags:String) -> Dictionary:
	return _get_tags_in_line(tags)

func _get_tags_in_line(tag_string:String):
	var data = {}
	var working_str = tag_string
	for i in range(tag_string.count(":")):
		var col_idx = working_str.find(":")
		if col_idx == -1:
			printerr("Un matched arg: %s" % tag_string)
			break
		var arg_name = working_str.substr(0, col_idx).strip_edges()
		working_str = working_str.substr(col_idx + 1).strip_edges()
		
		var space_idx = working_str.find(" ")
		var location = working_str.substr(0, space_idx).strip_edges()
		working_str = working_str.substr(space_idx).strip_edges()
		
		data[arg_name] = location
	return data


func code_completion_requested(_script_editor:CodeEdit) -> bool:
	var caret_context = script_metadata.get_caret_context()
	if caret_context.token_state == CaretContext.TokenState.COMMENT:
		return _comment_complete(caret_context)
	elif caret_context.is_in_function_call():
		return _function_call(caret_context)
	
	return false

func _comment_complete(caret_context:CaretContext):
	var script_editor = script_metadata.get_code_edit()
	if not caret_context.current_line_text.strip_edges().begins_with("#! " + TAG):
		return false
	
	# check if the symbol before expression is ':'
	var left_of_caret = caret_context.current_line_text.left(caret_context.caret_column)
	var comment_i = UString.string_safe_find(left_of_caret, "#")
	var stripped_text = left_of_caret.substr(comment_i)
	var expression = caret_context.get_expression_at_position(stripped_text)
	print("LFET::", left_of_caret.trim_suffix(expression).strip_edges(false, true))
	if not left_of_caret.trim_suffix(expression).strip_edges(false, true).ends_with(":"):
		return false
	
	# trim the last Member.Access.[Part] to reolve the current class
	expression = UString.trim_member_access_back(expression)
	var parser = script_metadata.get_gdscript_parser()
	var resolved = parser.resolve_expression(expression, caret_context.caret_line)
	if resolved == "" or not resolved.begins_with("res://"): # resolved type is not a valid file
		var global_classes = UClassDetail.get_all_global_class_paths()
		for name in global_classes.keys():
			var dict = script_metadata.get_code_complete_dict(CodeEdit.CodeCompletionKind.KIND_CONSTANT, name, name, "Object", null, 2048)
			script_metadata.add_completion_option(script_editor, dict)
		
		var current_class_obj = caret_context.get_current_class_object()
		for c in current_class_obj.get_gdscript_constants():
			var dict = script_metadata.get_code_complete_dict(CodeEdit.CodeCompletionKind.KIND_CONSTANT, c, c, "GDScriptInternal")
			script_metadata.add_completion_option(script_editor, dict)
		
	else:
		var resolve_script_data = UString.get_script_path_and_suffix(resolved)
		var resolved_script_path = resolve_script_data[0]
		var resolved_inner_class = resolve_script_data[1]
		
		var current_parser = parser.get_parser_for_path(resolved_script_path)
		var class_obj = current_parser.get_class_object(resolved_inner_class) as GDScriptParser.ParserClass
		for c in class_obj.get_gdscript_constants():
			var member_data = class_obj.get_member(c)
			var access_path = member_data.get(ParserKeys.ACCESS_PATH)
			#if class_obj.access_path != "": # should be find without
			if not access_path.begins_with(class_obj.access_path):
				continue
			var dict = script_metadata.get_code_complete_dict(CodeEdit.CodeCompletionKind.KIND_CONSTANT, c, c, "GDScriptInternal")
			script_metadata.add_completion_option(script_editor, dict)
	
	script_metadata.update_completion_options()
	return true


func _function_call(caret_context:CaretContext):
	var script_editor = script_metadata.get_code_edit()
	var parser = script_metadata.get_gdscript_parser()
	
	var function_call_data = caret_context.get_function_call_data()
	var function_full_script = function_call_data.get_function_script()
	if not function_full_script.begins_with("res://"):
		return false
	
	var script_data = UString.get_script_path_and_suffix(function_full_script)
	var function_script_path = script_data[0]
	var function_class_path = script_data[1]
	
	# check for metadata in the script where func is being called
	var metadata = get_arg_location_metadata(function_script_path)
	if metadata == null:
		return false
	
	# find the method data from the metadata, if not return
	var full_method_name = UString.dot_join(function_class_path, function_call_data.get_function_name())
	var method_data = metadata.get(full_method_name)
	if method_data == null:
		return false
	var current_arg = function_call_data.func_get_current_arg()
	if not method_data.has(current_arg.name):
		return false
	
	# this is just the declaration, it can be relative or absolute, factor that in below
	var declared_target_class = method_data[current_arg.name]
	var target_args = []
	if declared_target_class.contains("-"): # target arg delimited by '-', not a valid char for identifier
		var args_string:String = declared_target_class.get_slice("-", 1)
		declared_target_class = declared_target_class.get_slice("-", 0)
		target_args = [args_string]
		if args_string.contains(","):
			target_args = args_string.split(",", false)
	
	
	# find the function script parser and it's class object
	var function_script_parser = parser.get_parser_for_path(function_script_path)
	var func_class_obj = function_script_parser.get_class_object(function_class_path) as ScriptMetadata.GDScriptParser.ParserClass
	if not is_instance_valid(func_class_obj):
		return false
	
	# resolve the type of the target class in the function script
	var resolved_target_type = function_script_parser.resolve_expression(declared_target_class, func_class_obj.line_indexes[0])
	if not resolved_target_type.begins_with("res://"):
		return false # not a script, nothing we can do
	
	var resolved_script_data = UString.get_script_path_and_suffix(resolved_target_type)
	var target_script_path = resolved_script_data[0]
	var target_script_class_path = resolved_script_data[1]
	
	var target_script_parser = function_script_parser.get_parser_for_path(target_script_path)
	var target_class_obj = target_script_parser.get_class_object(target_script_class_path)
	
	if not is_instance_valid(target_class_obj): #^r this shouldn't trigger ever now...
		printerr("arg_location.gd - TARGET CLASS NOT FOUND, ", resolved_target_type)
		target_script_class_path = UString.dot_join(function_class_path, target_script_class_path)
		target_class_obj = target_script_parser.get_class_object(target_script_class_path)
		if not is_instance_valid(target_class_obj):
			return false
	
	var search_term = UString.dot_join(target_script_path, target_script_class_path) # may not need this now, could just pass the resolved type. Confirm the above doesn't trigger
	
	var access_object = parser.resolve_to_access_object(declared_target_class)
	var path_to_options = function_call_data.get_type_access_path(search_term, access_object)
	var valid_paths = {}
	if path_to_options.global != "": valid_paths[path_to_options.global] = " [Global]"
	if path_to_options.script_alias != "": valid_paths[path_to_options.script_alias] = " [Script Alias]"
	if path_to_options.standard != "": valid_paths[path_to_options.standard] = ""
	
	if valid_paths.is_empty(): # not valid paths, return
		print("arg_location.gd - NO VALID PATHS -> ", method_data)
		return false
	
	#print("PATH TO ", path_to_options.standard)
	#print("PATH TO ", path_to_options.script_alias)
	#print("PATH TO ", path_to_options.global)
	
	var valid_classes = []
	var deep_search = "d" in target_args or "deep" in target_args
	if deep_search:
		for access_path in target_script_parser._class_access.keys():
			if access_path.begins_with(target_class_obj.access_path):
				valid_classes.append(target_script_parser.get_class_object(access_path))
	else:
		valid_classes.append(target_class_obj)
	
	for path_to_type in valid_paths.keys():
		var tag = valid_paths[path_to_type]
		var location = 1024 # make script alias take the top results
		if tag == " [Script Alias]":
			location = 512
		elif tag == " [Global]":
			location = 2048
		for valid_class in valid_classes:
			for c in valid_class.constants.keys():
				var member_data = valid_class.get_member(c)
				var const_access_path = member_data.get(ParserKeys.ACCESS_PATH)
				if not const_access_path.begins_with(valid_class.access_path):
					continue # stop inner classes from lower class levels being listed
				
				# check type is string, this could be done differently. Could use the argument type to determine what they should be
				# also could just not do it, and list all, not sure. In a class that is just strings this will be quick, if you have a bunch of preloads it could be slow
				var type = valid_class.get_member_type(c)
				if type != "String" and type != "StringName":
					continue
				
				# trim the target class from the access path, this should be provided by the path_to_type
				var trimmed_const_path = const_access_path.trim_prefix(target_script_class_path).trim_prefix(".")
				var full_path = UString.dot_joinv([path_to_type, trimmed_const_path, c])
				var cc_dict = script_metadata.get_code_complete_dict(CodeEdit.CodeCompletionKind.KIND_CONSTANT, full_path + tag, full_path, "String", null, location)
				script_metadata.add_completion_option(script_editor, cc_dict)
	
	# if current text is nothing force the completion
	script_metadata.update_completion_options(function_call_data.get_text_current_arg() == "")
	return true

#^r this needs work to get proper scope. Completion works but the highlighting does not use parser
func _syntax_highlighting(_script_editor:CodeEdit, current_line_text:String, line_idx:int, comment_tag_idx:int):
	#var parser = script_metadata.get_gdscript_parser()
	var path = script_metadata.get_current_script().resource_path
	#print("ARG LOC::", path)
	var parser = ALibEditor.Singletons.EditorGDScriptParser.get_parser(path)
	var current_class = parser.get_class_at_line(line_idx)
	var current_class_obj = parser.get_class_object(current_class) as GDScriptParser.ParserClass
	if not is_instance_valid(current_class_obj):
		return {}
	
	var current_script = current_class_obj.script_resource
	var hl_info = {}
	var current_line_comment = current_line_text.substr(comment_tag_idx)
	var stripped_tag = current_line_comment.trim_prefix("#!").strip_edges()
	
	SyntaxPlusSingleton.HLInfo.add_color(hl_info, SyntaxPlusSingleton.DEFAULT_TAG_COLOR, 0, TAG.length())
	
	var full_stripped = stripped_tag.trim_prefix(TAG).strip_edges()
	var tags_in_line = _get_tags_in_line(full_stripped)
	
	var completed_tags = []
	
	var tokenized = UString.Token.tokenize_string(stripped_tag)
	var tokens = tokenized.tokens
	var in_arg = false
	
	var current_idx = TAG.length() - 1
	for ti in tokens.size():
		var token:String = tokens[ti]
		current_idx = stripped_tag.find(token, current_idx + 1)
		if in_arg: # handle arg state
			var last_char = stripped_tag[current_idx - 1]
			if token == ",":
				SyntaxPlusSingleton.HLInfo.add_color(hl_info, _sym_color, current_idx, current_idx + token.length(), _comment_color, false)
				continue
			elif token in TAG_ARGS and (last_char == "-" or last_char == ","):
				SyntaxPlusSingleton.HLInfo.add_color(hl_info, SyntaxPlusSingleton.DEFAULT_TAG_COLOR, current_idx, current_idx + token.length(), _comment_color, false)
				continue
			else: # anything that isn't ',' or preceded by is a new statement
				in_arg = false
		
		if token in tags_in_line: # if already declared, fail color
			var color = _BAD_SYM_COLOR
			if not token in completed_tags:
				completed_tags.append(token)
				color = _text_color
			SyntaxPlusSingleton.HLInfo.add_color(hl_info, color, current_idx, current_idx + token.length(), _sym_color)
		elif token == "-":
			in_arg = true
			SyntaxPlusSingleton.HLInfo.add_color(hl_info, _sym_color, current_idx, current_idx + token.length(), _comment_color, false)
		elif token == ":":
			continue
		else:
			var type_array = [token]
			if token.contains("."):
				type_array = token.split(".", false)
			#print("ARG PARTS::", type_array)
			var script = current_script
			for i in range(type_array.size()): # iterate parts in chain to make sure they are a valid chain
				var part = type_array[i]
				if i > 0:
					current_idx = stripped_tag.find(part, current_idx + 1)
				
				var part_color = _type_color
				if UClassDetail.get_global_class_path(part) != "":
					if i == 0:
						part_color = _global_color
					else:
						part_color = _BAD_SYM_COLOR
				
				var member_info = UClassDetail.get_member_info_by_path(script, part)
				#print("ARG::PART::", part, script, member_info)
				if member_info == null:
					if i < type_array.size() - 1: # if not at the end, fail color so we know chain is broken
						SyntaxPlusSingleton.HLInfo.add_color(hl_info, _BAD_SYM_COLOR, current_idx, current_idx + part.length(), _BAD_SYM_COLOR)
					break
				
				var end_color = _sym_color
				if i == type_array.size() - 1:
					end_color = _comment_color
				SyntaxPlusSingleton.HLInfo.add_color(hl_info, part_color, current_idx, current_idx + part.length(), end_color)
				
				if member_info is GDScript:
					script = member_info
				else:
					break
	
	return hl_info


func get_arg_location_metadata(path:=""):
	if path == "":
		path = script_metadata.get_current_script().resource_path
	var meta = script_metadata.get_script_metadata(path)
	return meta.get(TAG)




func te():
	#test_method()
	pass
	#test_method()
	Dart.test_nest(Dart.Nested.ANOTHER_VAL)
	test_method(Dart.Nested.ANOTHER_VAL, AnotherTest.ARG, Dart.Nested.ANOTHER_VAL)


#! arg_location my_setting:Dart.Nested test_2:AnotherTest another:Dart-d 



## THIS IS A DOC COMMENT
func test_method(my_setting:String, test_2:String, another:String, one_more:String=""):
	pass

class Dart:
	#! arg_location my_string:Nested
	static func test_nest(my_string:String):
		pass
	
	const MY_VAL = &"script_metadata.test.my_val"
	class Nested:
		const ANOTHER_VAL = &"script_metadata.test.nested.another_val"
		class Keep:
			class Going:
				const SO_DEEP = &"script_metadata.test.nested.keep.going.so_deep"
