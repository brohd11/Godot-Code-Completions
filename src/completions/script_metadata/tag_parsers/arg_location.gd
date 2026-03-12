extends EditorCodeCompletion.EditorCodeCompletionSingleton.ScriptMetadata.TagParserBase

const EditorColors = UtilsRemote.EditorColors

const TAG = &"arg_location"

func _init() -> void:
	EditorCodeCompletion.unregister_tag_static("#!", TAG)
	EditorCodeCompletion.register_tag_static("#!", TAG, ScriptMetadata.EditorCodeCompletionSingleton.TagLocation.ANY)
	
	SyntaxPlusSingleton.unregister_highlight_callable("#!", TAG)
	SyntaxPlusSingleton.register_highlight_callable("#!", TAG, _syntax_highlighting, SyntaxPlusSingleton.CallableLocation.ANY)


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
		#print(arg_name)
		#print(working_str)
		
		var space_idx = working_str.find(" ")
		var location = working_str.substr(0, space_idx).strip_edges()
		working_str = working_str.substr(space_idx).strip_edges()
		#print(location)
		#print(working_str)
		data[arg_name] = location
	return data
#! arg_location script_editor:Nest
func code_completion_requested(script_editor:CodeEdit) -> bool:
	var current_script = script_metadata.get_current_script()
	
	var caret_context = script_metadata.get_caret_context()
	if caret_context.token_state == CaretContext.TokenState.COMMENT:
		print("IN COMMENT")
		if not _is_caret_in_tag_type_declaration(caret_context):
			return false
		print("IN COMMENT TYPE")
		var word_before_cursor = caret_context.expression_before_caret
		
		var current_class = caret_context.current_class
		
		if current_class != "":
			current_script = UClassDetail.get_member_info_by_path(current_script, current_class)
		
		var script_to_list = current_script
		if word_before_cursor == "" or not word_before_cursor.contains("."):
			pass
		else:
			var trimmed_back = UString.trim_member_access_back(word_before_cursor)
			script_to_list = UClassDetail.get_member_info_by_path(current_script, trimmed_back)
			if script_to_list is not GDScript:
				return false
		var preloads = UClassDetail.script_get_preloads(script_to_list, false, true)
		for path in preloads.keys():
			var dict = script_metadata.get_code_complete_dict(CodeEdit.CodeCompletionKind.KIND_CONSTANT, path, path)
			script_metadata.add_completion_option(script_editor, dict)
		script_metadata.update_completion_options()
		return true
		#test_method()
	
	elif caret_context.is_in_function_call():
		var function_call_data = caret_context.get_function_call_data()
		var data = UClassDetail.get_member_info_by_path(current_script, function_call_data.full_call)
		
		if data != null:
			var metadata = get_arg_location_metadata()
			print("META ", metadata)
			if metadata == null:
				return false
			var method_data = metadata.get(function_call_data.full_call)
			if not method_data:
				return false
			var current_arg_idx = function_call_data.current_arg_index
			var args = data.get("args")
			var arg_data = args[current_arg_idx]
			if not method_data.has(arg_data.name):
				return false
			
			var target = method_data[arg_data.name]
			var all_constants = {}
			var target_script = UClassDetail.get_member_info_by_path(current_script, target)
			var constants = UClassDetail.script_get_all_constants(target_script, UClassDetail.IncludeInheritance.NONE)
			all_constants[target] = constants
			var inner_scripts = UClassDetail.script_get_preloads(target_script, true, true)
			for script_path in inner_scripts.keys():
				var script = inner_scripts[script_path]
				var inner_constants = UClassDetail.script_get_all_constants(script, UClassDetail.IncludeInheritance.NONE)
				
				all_constants[target + "." + script_path] = inner_constants
			
			for access_path in all_constants.keys():
				var const_dict = all_constants[access_path]
				for const_name in const_dict.keys():
					var val = const_dict[const_name]
					if not (val is String or val is StringName):
						continue
					
					var full_path = const_name
					if access_path != "":
						full_path = access_path + "." + const_name
					#print(full_path)
					var cc_dict = script_metadata.get_code_complete_dict(CodeEdit.CodeCompletionKind.KIND_CONSTANT, full_path, full_path, "String")
					script_metadata.add_completion_option(script_editor, cc_dict)
			
			script_metadata.update_completion_options(function_call_data.get_text_current_arg() == "")
			return true
	
	return false





func _syntax_highlighting(_script_editor:CodeEdit, current_line_text:String, line_idx:int, comment_tag_idx:int):
	var parser = script_metadata.get_gdscript_parser()
	var current_class = parser.get_class_at_line(line_idx)
	var current_class_obj = parser.get_class_object(current_class)
	var current_script = current_class_obj.script_resource
	var hl_info = {}
	var current_line_comment = current_line_text.substr(comment_tag_idx)
	var stripped_tag = current_line_comment.trim_prefix("#!").strip_edges()
	
	SyntaxPlusSingleton.HLInfo.add_color(hl_info, SyntaxPlusSingleton.DEFAULT_TAG_COLOR, 0, TAG.length())
	
	var full_stripped = stripped_tag.trim_prefix(TAG).strip_edges()
	var tags_in_line = _get_tags_in_line(full_stripped)
	var tag_properties = tags_in_line.keys()
	
	tag_properties.sort_custom(
	func(a,b):
		var type_a = tags_in_line[a]
		var type_b = tags_in_line[b]
		return type_a.length() > type_b.length()
		)
	
	var comment_color = EditorColors.get_syntax_color(EditorColors.SyntaxColor.COMMENT)
	var text_color = EditorColors.get_syntax_color(EditorColors.SyntaxColor.TEXT)
	var type_color = EditorColors.get_syntax_color(EditorColors.SyntaxColor.BASE_TYPE)
	var sym_color = EditorColors.get_syntax_color(EditorColors.SyntaxColor.SYMBOL)
	
	
	for property in tag_properties:
		hl_info.merge(SyntaxPlusSingleton.HLInfo.highlight_all_occurences(stripped_tag, property, text_color, sym_color))
		var type = tags_in_line[property] as String
		var type_array = [type]
		if type.contains("."):
			type_array = type.split(".", false)
		
		var script = current_script
		for i in range(type_array.size()):
			var part = type_array[i]
			var member_info = UClassDetail.get_member_info_by_path(script, part)
			if member_info != null:
				var end_color = sym_color
				if i == type_array.size() - 1:
					end_color = comment_color
				hl_info.merge(SyntaxPlusSingleton.HLInfo.highlight_all_occurences(stripped_tag, part, type_color, end_color))
			
			if member_info is GDScript:
				script = member_info
			else:
				break
	
	#print(current_line_comment)
	#print(hl_info.keys())
	return hl_info




#! arg_location my_setting:Dart.Nested test_2:Dart.Nested.Keep.Going
## THIS IS A DOC COMMENT
func test_method(my_setting:String, test_2:String):
	#Dart.test_nest()
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






func _get_idxes_in_text(text:String, what:String) -> PackedInt32Array:
	var idxes = PackedInt32Array()
	var idx = text.find(what)
	while idx != -1:
		idxes.append(idx)
		idx = text.find(what, idx + 1)
	return idxes


func get_arg_location_metadata(path:=""):
	if path == "":
		path = script_metadata.get_current_script().resource_path
	var meta = script_metadata.get_script_metadata(path)
	return meta.get(TAG)

func _is_caret_in_tag_type_declaration(caret_context:CaretContext):
	if not caret_context.current_line_text.strip_edges().begins_with("#! " + TAG):
		return false
	var left = caret_context.current_line_text.left(caret_context.caret_column)
	print("LEFT::", left,"::EXPR::", caret_context.expression_before_caret, "::STRIPPED::", left.trim_suffix(caret_context.expression_before_caret).strip_edges())
	if left.trim_suffix(caret_context.expression_before_caret).strip_edges().ends_with(":"):
		return true
	return false
