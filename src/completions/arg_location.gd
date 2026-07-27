extends EditorCodeCompletion

const TagParser = UtilsRemote.TagParser

const HLInfo = preload("uid://cfbf3hc1q2j3f") #! resolve SyntaxPlusSingleton.HLInfo

const ARG_LOCATION_ENABLE = &"plugin/code_completion/arg_location/enable"

const TAG = &"arg_location"

const TAG_ARGS = ["d", "deep"]
const _BAD_SYM_COLOR = Color.FIREBRICK

var _enable:bool = true

var _comment_color:Color
var _text_color:Color
var _type_color:Color
var _sym_color:Color
var _global_color:Color


func _singleton_ready() -> void:
	EditorCodeCompletion.register_tag_static("#!", TAG, EditorCodeCompletionSingleton.TagLocation.ANY)
	SyntaxPlusSingleton.register_highlight_callable("#!", TAG, _syntax_highlighting, SyntaxPlusSingleton.CallableLocation.ANY)
	
	TagParser.register_tag_parser(TAG, self)
	
	_on_editor_settings_changed()
	EditorInterface.get_editor_settings().settings_changed.connect(_on_editor_settings_changed)

func register_editor_settings(settings_helper:SettingHelperEditor):
	settings_helper.subscribe_property(self, &"_enable", ARG_LOCATION_ENABLE, true)

func _on_editor_settings_changed():
	_comment_color = EditorColors.get_syntax_color(EditorColors.SyntaxColor.COMMENT)
	_text_color = EditorColors.get_syntax_color(EditorColors.SyntaxColor.TEXT)
	_type_color = EditorColors.get_syntax_color(EditorColors.SyntaxColor.BASE_TYPE)
	_sym_color = EditorColors.get_syntax_color(EditorColors.SyntaxColor.SYMBOL)
	_global_color = EditorColors.get_syntax_color(EditorColors.SyntaxColor.USER_TYPE)


func parse_tag(raw_tags:Dictionary) -> Dictionary:
	var mods_string = raw_tags.get("mods", "")
	var args_string = raw_tags.get("args", "")
	return _get_tags_in_line(args_string)

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
		
		var flags = []
		if location.contains("-"): # target arg delimited by '-', not a valid char for identifier
			var args_string:String = location.get_slice("-", 1)
			location = location.get_slice("-", 0)
			flags = [args_string]
			if args_string.contains(","):
				flags = args_string.split(",", false)
		
		
		data[arg_name] = {
			Keys.LOCATION: location,
			Keys.FLAGS: flags,
		}
	return data


func _on_code_completion_requested(_script_editor:CodeEdit) -> bool:
	if not _enable:
		return false
	var caret_context = get_caret_context()
	if caret_context.token_state == CaretContext.TokenState.COMMENT:
		return _comment_complete(caret_context)
	elif caret_context.is_in_function_call():
		return _function_call(caret_context)
	
	return false


func _comment_complete(caret_context:CaretContext):
	if not caret_context.current_line_text.strip_edges().begins_with("#! " + TAG):
		return false
	
	# check if the symbol before expression is ':'
	var left_of_caret = caret_context.current_line_text.left(caret_context.caret_column)
	var comment_i = UString.string_safe_find(left_of_caret, "#")
	var stripped_text = left_of_caret.substr(comment_i)
	var expression = caret_context.get_expression_at_position(stripped_text)
	#print("LFET::", left_of_caret.trim_suffix(expression).strip_edges(false, true))
	if not left_of_caret.trim_suffix(expression).strip_edges(false, true).ends_with(":"):
		return false
	
	EditorCodeCompletion.Helpers.class_completion(self, expression)
	return true


func _function_call(caret_context:CaretContext):
	var script_editor = get_code_edit()
	var parser = get_gdscript_parser()
	
	var function_call_data = caret_context.get_function_call_data()

	# The tag sits above the function's DECLARATION - an ancestor's script, for an inherited call - so
	# the metadata key and the tag's location string both belong to that script's scope, not the
	# receiving object's.
	var function_script = function_call_data.get_function_script()
	if not GDScriptParser.Utils.is_absolute_path(function_script):
		return false

	var metadata = TagParser.get_metadata_for_type(function_call_data.get_function_origin(), TAG)
	if not metadata:
		return false
	
	var location_data = metadata.get(TAG)
	var arg_name = function_call_data.get_current_arg_name()
	if not location_data.has(arg_name):
		return false

	# this is just the declaration, it can be relative or absolute, factor that in below
	var target_data = location_data[arg_name]
	var target_class = target_data.get(Keys.LOCATION)
	var target_flags = target_data.get(Keys.FLAGS, [])

	# resolve the target class in the scope it was written in (the declaring script)
	var func_script_data = GDScriptParser.Utils.type_path_get_script_data(function_script)
	var resolved_target_type = parser.resolve_expression_in_script(target_class, func_script_data[0], func_script_data[1])
	if not GDScriptParser.Utils.is_absolute_path(resolved_target_type):
		return false # not a script, nothing we can do

	
	var target_parser_data = parser.get_parser_and_class_obj_for_script(resolved_target_type)
	var target_script_parser = target_parser_data.parser as GDScriptParser
	var target_class_obj = target_parser_data.class_obj
	if not is_instance_valid(target_class_obj):
		return false

	# The secondary access object is the target class AS SPELLED where the tag is written; the call
	# below translates that into something typable from the caller, verifying candidates in the
	# CALLER's scope (which is why it goes through the function call data, not a foreign parser).
	var target_access_object = parser.resolve_to_access_object_in_script(target_class, func_script_data[0], func_script_data[1])
	var path_to_options = function_call_data.get_type_access_path(resolved_target_type, target_access_object)

	var valid_paths = {}
	if path_to_options.global != "": valid_paths[path_to_options.global] = " [Global]"
	if path_to_options.script_alias != "": valid_paths[path_to_options.script_alias] = " [Script Alias]"
	if path_to_options.standard != "": valid_paths[path_to_options.standard] = ""
	
	if valid_paths.is_empty(): # not valid paths, return
		print("arg_location.gd - NO VALID PATHS -> ", location_data)
		return false
	
	#print("PATH TO ", path_to_options.standard)
	#print("PATH TO ", path_to_options.script_alias)
	#print("PATH TO ", path_to_options.global)
	
	var valid_classes = []
	var deep_search = "d" in target_flags or "deep" in target_flags
	if deep_search:
		for access_path in target_script_parser.get_classes():
			if access_path.begins_with(target_class_obj.access_path):
				valid_classes.append(target_script_parser.get_class_object(access_path))
	else:
		valid_classes.append(target_class_obj)
	
	# resolved target class path ie. res://class.gd.[MyClass] <- this
	var target_script_class_path = GDScriptParser.Utils.type_path_get_script_data(resolved_target_type)[1]
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
				var type_suffix = GDScriptParser.Utils.type_path_get_type(type)
				if type_suffix == "":
					type_suffix = type
				if type_suffix != "String" and type_suffix != "StringName":
					continue
				
				# trim the target class from the access path, this should be provided by the path_to_type
				var trimmed_const_path = const_access_path.trim_prefix(target_script_class_path).trim_prefix(".")
				var full_path = UString.dot_joinv([path_to_type, trimmed_const_path, c])
				var cc_dict = get_code_complete_dict(CodeEdit.CodeCompletionKind.KIND_CONSTANT, full_path + tag, full_path, "String", null, location)
				add_completion_option(script_editor, cc_dict)
	
	# if current text is nothing force the completion
	update_completion_options(function_call_data.get_current_arg_text() == "")
	return true


#^r this needs work to get proper scope. Completion works but the highlighting does not use parser

func _syntax_highlighting(_script_editor:CodeEdit, current_line_text:String, line_idx:int, comment_tag_idx:int):
	var parser = get_gdscript_parser(get_current_script().resource_path)
	if not is_instance_valid(parser):
		return {}
	var current_class = parser.get_class_at_line(line_idx)
	var current_class_obj = parser.get_class_object(current_class) as GDScriptParser.ParserClass
	if not is_instance_valid(current_class_obj):
		return {}
	
	var current_script = current_class_obj.get_script_resource()
	if not current_script:
		return {}
	
	var hl_info = {}
	var current_line_comment = current_line_text.substr(comment_tag_idx)
	hl_info.merge(HLInfo.highlight_prefix("#!", current_line_comment))
	hl_info.merge(HLInfo.highlight_tag(TAG, current_line_comment))
	
	var tag_offset = HLInfo.get_tag_end_index("#!", TAG, current_line_comment)
	var full_stripped = current_line_comment.substr(tag_offset)
	
	var tags_in_line = _get_tags_in_line(full_stripped)
	var completed_tags = []
	
	var tokenized = UString.Token.tokenize_string(full_stripped)
	var tokens = tokenized.tokens
	var in_arg = false
	
	var current_idx = -1
	for ti in tokens.size():
		var token:String = tokens[ti]
		current_idx = full_stripped.find(token, current_idx + 1)
		var adj_idx = tag_offset + current_idx
		if in_arg: # handle arg state
			var last_char = full_stripped[current_idx - 1]
			if token == ",":
				HLInfo.add_color(hl_info, _sym_color, adj_idx, adj_idx + token.length(), _comment_color, false)
				continue
			elif token in TAG_ARGS and (last_char == "-" or last_char == ","):
				HLInfo.add_color(hl_info, SyntaxPlusSingleton.DEFAULT_TAG_COLOR, adj_idx, adj_idx + token.length(), _comment_color, false)
				continue
			else: # anything that isn't ',' or preceded by is a new statement
				in_arg = false
		#print(token, "::",tags_in_line)
		if token in tags_in_line: # if already declared, fail color
			var color = _BAD_SYM_COLOR
			if not token in completed_tags:
				completed_tags.append(token)
				color = _text_color
			HLInfo.add_color(hl_info, color, adj_idx, adj_idx + token.length(), _sym_color)
			
		elif token == "-":
			in_arg = true
			HLInfo.add_color(hl_info, _sym_color, adj_idx, adj_idx + token.length(), _comment_color, false)
		elif token == ":":
			continue
		else:
			hl_info.merge(HLInfo.check_const_path(token, current_class_obj.get_script_class_path(), adj_idx))
	
	return hl_info


class Keys:
	const LOCATION = &"location"
	const FLAGS = &"flags"



#! arg_location dart_nest:Dart.Nested  another_test:AnotherTest dart_deep:Dart-d
## THIS IS A DOC COMMENT
func test_method(dart_nest:String, another_test:String, dart_deep:String, no_loc:String=""):
	pass


class Dart:
	
	func another():
		
		
		pass
	
	#! arg_location my_string:Nested
	static func test_nest(my_string:String):
		pass
	
	const MY_VAL = &"script_metadata.test.my_val"
	class Nested:
		
		const ANOTHER_VAL = &"script_metadata.test.nested.another_val"
		class Keep:
			class Going:
				const SO_DEEP = &"script_metadata.test.nested.keep.going.so_deep"
