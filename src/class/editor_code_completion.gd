class_name EditorCodeCompletion

const EditorCodeCompletionSingleton = preload("res://addons/code_completions/src/class/editor_code_completion_singleton.gd")

const TagLocation = EditorCodeCompletionSingleton.TagLocation

const UtilsRemote = EditorCodeCompletionSingleton.UtilsRemote
const UClassDetail = UtilsRemote.UClassDetail
const UString = UtilsRemote.UString
const EditorColors = UtilsRemote.EditorColors

const SettingHelperEditor = UtilsRemote.SettingHelperEditor

const ParserKeys = GDScriptParser.Keys

const TokenState = CaretContext.TokenState
const ExpressionState = CaretContext.ExpressionState
const EditorGDScriptParser = UtilsRemote.EditorGDScriptParser
const GDScriptParser = EditorGDScriptParser.GDScriptParser
const CaretContext = GDScriptParser.CaretContext
const ScopeState = CaretContext.ScopeState

var singleton:EditorCodeCompletionSingleton

var editor_theme:Theme

## Holds registered tags to unregister on clean up. Not to be modified.
var _tags := {}

## Register plugin to EditorCodeCompletionSingleton and any other singletons it uses.
static func register_plugin(plugin:EditorPlugin):
	return EditorCodeCompletionSingleton.register_node(plugin)

## Unregister plugin to EditorCodeCompletionSingleton and any other singletons it uses.
static func unregister_plugin(plugin:EditorPlugin):
	EditorCodeCompletionSingleton.unregister_node(plugin)

func _init() -> void:
	var settings = _get_completion_settings()
	if not EditorCodeCompletionSingleton.instance_valid():
		printerr("Register plugin with 'EditorCodeCompletion.register_plugin()' before instancing.")
		return
	
	singleton = EditorCodeCompletionSingleton.get_instance()
	EditorCodeCompletionSingleton.register_completion(self, settings)
	EditorCodeCompletionSingleton.call_on_ready(_singleton_ready)
	
	editor_theme = EditorInterface.get_editor_theme()

## Settings for the Singleton. Current Settings:
## priority:int
func _get_completion_settings() -> Dictionary:
	return {
		"priority": 100,
	}

func _singleton_ready() -> void:
	pass

func register_editor_settings(settings_helper:SettingHelperEditor):
	return

static func call_on_ready(callable:Callable):
	EditorCodeCompletionSingleton.call_on_ready(callable)

# TODO are these used?
static func register_tag_static(prefix:String, tag:String, location:=TagLocation.ANY):
	if not EditorCodeCompletionSingleton.instance_valid():
		print("EditorCodeCompletionSingleton not instanced yet.")
		return
	EditorCodeCompletionSingleton.get_instance().register_tag(prefix, tag, location)

static func unregister_tag_static(prefix:String, tag:String, _location:=TagLocation.ANY):
	if not EditorCodeCompletionSingleton.instance_valid():
		print("EditorCodeCompletionSingleton not instanced yet.")
		return
	EditorCodeCompletionSingleton.get_instance().unregister_tag(prefix, tag)

func register_tag(prefix:String, tag:String, location:=TagLocation.ANY):
	singleton.register_tag(prefix, tag, location)
	if not _tags.has(prefix):
		_tags[prefix] = {}
	_tags[prefix][tag] = true

func clean_up() -> void:
	singleton.unregister_completion(self)
	
	for prefix:String in _tags.keys():
		var tags = _tags.get(prefix, {})
		for tag in tags:
			singleton.unregister_tag(prefix, tag)

func _on_editor_script_changed(script) -> void:
	pass

func _on_code_completion_requested(script_editor:CodeEdit) -> bool:
	return false


func get_current_script():
	return singleton.get_current_script()

func get_code_edit():
	return singleton.get_code_edit()

#region CompletionOptions

func get_code_complete_dict(kind:CodeEdit.CodeCompletionKind, display_text:String, insert_text:String, icon_name:="",
						default_value=null, location=1024, font_color:=Helpers.Colors.DEFAULT_COMPLETION) -> Dictionary:
	var icon
	if icon_name == "":
		pass
	elif icon_name == "constructor":
		icon = editor_theme.get_icon(&"MemberConstructor", &"EditorIcons")
	elif icon_name == "const":
		icon = editor_theme.get_icon(&"MemberConstant", &"EditorIcons")
	elif icon_name == "property":
		icon = editor_theme.get_icon(&"MemberProperty", &"EditorIcons")
	elif icon_name == "signal":
		icon = editor_theme.get_icon(&"MemberSignal", &"EditorIcons")
	elif icon_name == "method":
		icon = editor_theme.get_icon(&"MemberMethod", &"EditorIcons")
	elif icon_name == "enum":
		icon = editor_theme.get_icon(&"Enum", &"EditorIcons")
	else:
		if editor_theme.has_icon(icon_name, &"EditorIcons"):
			icon = editor_theme.get_icon(icon_name, &"EditorIcons")
		else:
			icon = editor_theme.get_icon(&"Object", &"EditorIcons")
	return {
		&"kind":kind,
		&"display_text":display_text,
		&"insert_text":insert_text,
		&"font_color":font_color,
		&"icon":icon,
		&"default_value":default_value,
		&"location":location,
	}

static func get_code_complete_dict_static(kind:CodeEdit.CodeCompletionKind, display_text:String, insert_text:String, icon_name:="",
			font_color:=Helpers.Colors.DEFAULT_COMPLETION, default_value=null, location=1024) -> Dictionary:
	var edthm = EditorInterface.get_editor_theme()
	var icon
	if icon_name == "":
		pass
	elif icon_name == "constructor":
		icon = edthm.get_icon(&"MemberConstructor", &"EditorIcons")
	elif icon_name == "const":
		icon = edthm.get_icon(&"MemberConstant", &"EditorIcons")
	elif icon_name == "property":
		icon = edthm.get_icon(&"MemberProperty", &"EditorIcons")
	elif icon_name == "signal":
		icon = edthm.get_icon(&"MemberSignal", &"EditorIcons")
	elif icon_name == "method":
		icon = edthm.get_icon(&"MemberMethod", &"EditorIcons")
	elif icon_name == "enum":
		icon = edthm.get_icon(&"Enum", &"EditorIcons")
	else:
		if edthm.has_icon(icon_name, &"EditorIcons"):
			icon = edthm.get_icon(icon_name, &"EditorIcons")
		else:
			icon = edthm.get_icon(&"Object", &"EditorIcons")
	return {
		&"kind":kind,
		&"display_text":display_text,
		&"insert_text":insert_text,
		&"font_color":font_color,
		&"icon":icon,
		&"default_value":default_value,
		&"location":location,
	}


func add_completion_option(script_editor:CodeEdit, option_dict:Dictionary) -> void:
	script_editor.add_code_completion_option(option_dict.kind, option_dict.display_text,
					option_dict.insert_text, option_dict.font_color, option_dict.icon, 
					option_dict.default_value, option_dict.location)

func update_completion_options(force:=false):
	var current = get_code_edit()
	current.update_code_completion_options(force)

#endregion


func get_gdscript_parser(path:=""):
	if path == "": # could probably just run the static below
		return singleton._editor_gdscript_parser
	return EditorGDScriptParser.get_parser(path)

func get_caret_context():
	return singleton.get_caret_context()


func get_string_map(text:String):
	return singleton.get_string_map(text)


#^ cache, these may be able to be removed...
func _store_data(section, key, value, script, data_cache:Dictionary):
	singleton._store_data_in_section(section, key, value, script, data_cache)

func _get_cached_data(section, key, data_cache:Dictionary):
	return singleton._get_cached_data_in_section(section, key, data_cache)

func set_data(key, value):
	singleton.peristent_cache[key] = value

func get_data(key):
	return singleton.peristent_cache.get(key)


class Helpers:
	class Colors:
		const DEFAULT_COMPLETION = Color(1,1,1,0.75)
		const AXIS_X = Color(0.96, 0.2, 0.32, 1.0)
		const AXIS_Y = Color(0.53, 0.84, 0.01, 1.0)
		const AXIS_Z = Color(0.16, 0.55, 0.96, 1.0)
		const AXIS_W = Color(0.55, 0.55, 0.55, 1.0)
	
	const DOTS_UNICODE = "(\u2026)"
	const TAG_ICON_NAME = "BoneMapperHandleCircle"
	
	static func complete_function_display(insert:String):
		if not insert.ends_with("("):
			return insert
		return insert.trim_suffix("(") + DOTS_UNICODE
	
	static func get_string_color(caret_context:CaretContext, ensure_string:=TokenState.STRING_NAME):
		if caret_context.token_state == TokenState.STRING:
			return EditorColors.get_syntax_color(EditorColors.SyntaxColor.STRING)
		elif caret_context.token_state == TokenState.STRING_NAME:
			return EditorColors.get_syntax_color(EditorColors.SyntaxColor.STRING_NAME)
		elif caret_context.token_state == TokenState.NODE_PATH_LITERAL:
			return EditorColors.get_syntax_color(EditorColors.SyntaxColor.NODE_PATH)
		else:
			if ensure_string == TokenState.STRING_NAME:
				return EditorColors.get_syntax_color(EditorColors.SyntaxColor.STRING_NAME)
			elif ensure_string == TokenState.STRING:
				return EditorColors.get_syntax_color(EditorColors.SyntaxColor.STRING)
			elif ensure_string == TokenState.NODE_PATH_LITERAL:
				return EditorColors.get_syntax_color(EditorColors.SyntaxColor.NODE_PATH)
			return Colors.DEFAULT_COMPLETION
	
	## Pass the full class path before the caret.
	static func class_completion(code_completion:EditorCodeCompletion, class_path:String, include_built_ins:=false, update:=true):
		var script_editor = code_completion.get_code_edit()
		var caret_context = code_completion.get_caret_context()
		
		if include_built_ins and not class_path.contains("."):
			var built_ins = GDScriptParser.BuiltInChecker.get_class_names()
			for b in built_ins:
				var dict = code_completion.get_code_complete_dict(CodeEdit.KIND_CLASS, b, b, b)
				code_completion.add_completion_option(script_editor, dict)
			
		
		# trim the last Member.Access.[Part] to resolve the current class
		var expression = UString.trim_member_access_back(class_path)
		var parser = code_completion.get_gdscript_parser()
		var resolved = parser.resolve_expression_to_type(expression, caret_context.caret_line)
		if resolved == "" or not resolved.begins_with("res://"): # resolved type is not a valid file
			var global_classes = UClassDetail.get_all_global_class_paths()
			for name in global_classes.keys():
				var dict = code_completion.get_code_complete_dict(CodeEdit.CodeCompletionKind.KIND_CONSTANT, name, name, "Object", null, 2048)
				code_completion.add_completion_option(script_editor, dict)
			
			var current_class_obj = caret_context.get_current_class_object()
			for c in current_class_obj.get_gdscript_constants():
				var dict = code_completion.get_code_complete_dict(CodeEdit.CodeCompletionKind.KIND_CONSTANT, c, c, "GDScriptInternal")
				code_completion.add_completion_option(script_editor, dict)
			
		else:
			var resolve_script_data = UString.get_script_path_and_suffix(resolved)
			var resolved_script_path = resolve_script_data[0]
			var resolved_inner_class = resolve_script_data[1]
			
			var current_parser = parser.get_parser_for_path(resolved_script_path)
			var class_obj = current_parser.get_class_object(resolved_inner_class) as GDScriptParser.ParserClass
			for c in class_obj.get_gdscript_constants():
				var member_data = class_obj.get_member(c)
				if not member_data:
					continue
				var access_path = member_data.get(ParserKeys.ACCESS_PATH)
				#if class_obj.access_path != "": # should be find without
				if not access_path.begins_with(class_obj.access_path):
					continue
				var dict = code_completion.get_code_complete_dict(CodeEdit.CodeCompletionKind.KIND_CONSTANT, c, c, "GDScriptInternal")
				code_completion.add_completion_option(script_editor, dict)
		
		if update: # add to params
			code_completion.update_completion_options()
	
	
	#! keys type:String class_obj:GDScriptParser.ParserClass
	#! keys is_instance:bool insert_parens:bool
	#! keys allow_user_type:bool user_include_base_type_members:bool
	#! keys allow_builtin_type:bool
	#! keys global_include:bool  global_include_builtin:bool global_include_class_preloads:bool
	#! keys update:bool update_force:bool
	static func completion_params(params:={}) -> Dictionary:
		params.get_or_add("type", "")
		params.get_or_add("class_obj", null)
		
		#params.get_or_add("is_instance", false) # optional
		params.get_or_add("insert_parens", true)
		
		params.get_or_add("allow_user_type", true)
		params.get_or_add("allow_builtin_type", true)
		
		params.get_or_add("user_include_base_type_members", true)
		
		params.get_or_add("global_include", false)
		params.get_or_add("global_include_class_preloads", true)
		params.get_or_add("global_include_builtin", false)
		
		params.get_or_add("update", true)
		params.get_or_add("update_force", false)
		
		
		
		return params
	
	
	#! keys i-completion_params;
	static func member_access_completion(code_completion:EditorCodeCompletion, params:=completion_params()):
		var caret_context = code_completion.get_caret_context()
		var member_access_type_rich = caret_context.get_trimmed_member_access_type_rich()
		var type = member_access_type_rich.type
		if type == "":
			if caret_context.trim_last_member_access_part() != "":
				return false # not empty text, bad destination
			else:
				type = caret_context.get_current_class_object().get_script_class_path()
			
			
		#print("TRIMMED::", type)
		return class_completion_from_type(code_completion, type, caret_context.get_current_class_object(), params)
	
	static func class_completion_from_type(code_completion:EditorCodeCompletion, type:String, class_obj:GDScriptParser.ParserClass, params:=completion_params()):
		
		var caret_context = code_completion.get_caret_context()
		var parser = GDScriptParser.Utils.ParserRef.get_parser(class_obj)
		#var resolved_type = parser.resolve_expression_to_type(type, class_obj.declaration_line)
		var resolved_type = caret_context.resolve_expression_to_type(type)
		var type_check = GDScriptParser.Utils.type_path_get_type(resolved_type, true)
		if type_check != "":
			resolved_type = type_check
		
		var is_instance = resolved_type.ends_with(GDScriptParser.Keys.INS_DELIM) or GDScriptParser.BuiltInChecker.is_variant_type(resolved_type)
		resolved_type = resolved_type.trim_suffix(GDScriptParser.Keys.INS_DELIM)
		if params.has("is_instance"):
			is_instance = params.is_instance
		
		var update = params.get("update", true)
		params.erase("update")
		
		
		
		
		var exit = false
		if GDScriptParser.BuiltInChecker.is_builtin_class(resolved_type):
			if params.allow_builtin_type:
				exit = built_in_completion(code_completion, resolved_type, is_instance, params)
		elif GDScriptParser.Utils.is_absolute_path(resolved_type):
			if params.allow_user_type:
				#print("ADD USER")
				exit = user_class_completion(code_completion, resolved_type, is_instance, false, params)
		
		
		if params.global_include:
			#print("ADD GLOBVSAL")
			add_global_classes_completion(code_completion, params)
			exit = true
		
		if exit and update:
			code_completion.update_completion_options(params.update_force)
		
		return exit
	
	#! keys i-completion_params;
	static func built_in_completion(code_completion:EditorCodeCompletion, type:String, is_instance:bool, params:={}):
		
		var insert_parens = params.get("insert_parens", true)
		
		var script_editor = code_completion.get_code_edit()
		var class_data_array = GDScriptParser.BuiltInChecker.get_class_data(type, true)
		var is_variant = GDScriptParser.BuiltInChecker.is_variant_type(type)
		for i in range(class_data_array.size()):
			
			var class_data = class_data_array[i]
			for member in class_data.keys():
				if member == GDScriptParser.BuiltInChecker.CLASS_NAME:
					continue
				var member_data:Dictionary = class_data[member]
				var class_member_type:StringName = member_data.get(GDScriptParser.BuiltInChecker.MEMBER_TYPE)
				#print(member_data)
				
				var display = member
				var insert = member
				var icon = "member"
				var kind:CodeEdit.CodeCompletionKind = CodeEdit.KIND_MEMBER
				var location:int = CodeEdit.LOCATION_OTHER | i
				var font_color = EditorCodeCompletion.Helpers.Colors.DEFAULT_COMPLETION
				if class_member_type == GDScriptParser.BuiltInChecker.CONSTANTS:
					if is_variant:
						continue
					icon = "const"
					kind = CodeEdit.KIND_CONSTANT
				elif class_member_type == GDScriptParser.BuiltInChecker.ENUMS:
					icon = "enum"
					kind = CodeEdit.KIND_ENUM
				elif class_member_type == GDScriptParser.BuiltInChecker.METHODS:
					if not is_instance and not member_data.get("is_static", false):
						continue
					icon = "method"
					kind = CodeEdit.KIND_FUNCTION
					var arguments = member_data.get("arguments", [])
					if insert_parens:
						if arguments.is_empty():
							display = member + "()"
							insert = member + "()"
						else:
							display = member + EditorCodeCompletion.Helpers.DOTS_UNICODE
							insert = member + "("
				elif class_member_type == GDScriptParser.BuiltInChecker.MEMBERS:
					if not is_instance:
						continue
					icon = "property"
					kind = CodeEdit.KIND_MEMBER
					font_color = get_font_color_for_option(member)
				elif class_member_type == GDScriptParser.BuiltInChecker.PROPERTIES:
					if not is_instance:
						continue
					icon = "property"
					kind = CodeEdit.KIND_MEMBER
				elif class_member_type == GDScriptParser.BuiltInChecker.SIGNALS:
					if not is_instance:
						continue
					icon = "signal"
					kind = CodeEdit.KIND_SIGNAL
			
				var dict = code_completion.get_code_complete_dict(kind, display, insert, icon, null, location, font_color)
				code_completion.add_completion_option(script_editor, dict)
		
		if params.get("update", false):
			code_completion.update_completion_options(params.get("update_force", false))
		
		return true
	
	#! keys i-completion_params;
	static func user_class_completion(code_completion:EditorCodeCompletion, type:String, is_instance:bool, include_builtin:bool=true, params:={}):
		
		var script_editor = code_completion.get_code_edit()
		var parser_for_res = code_completion.get_gdscript_parser().get_parser_and_class_obj_for_script(type)
		if not parser_for_res:
			return false
		
		var insert_parens = params.get("insert_parens", true)
		
		#var res_member = GDScriptParser.Utils.type_path_get_member(type)
		var parser = parser_for_res.parser as GDScriptParser
		var class_obj = parser_for_res.class_obj as GDScriptParser.ParserClass
		
		var constants_to_hide = []
		if params.get("global_include") and params.get("global_include_class_preloads"):
			constants_to_hide = class_obj.get_gdscript_constants()
		
		var main_class_path = class_obj.get_script_class_path()
		
		var inherited_scripts = class_obj.get_inherited_scripts()
		var inh_script_size = inherited_scripts.size()
		var parent_mask_map = {}
		for i in range(inh_script_size):
			parent_mask_map[inherited_scripts[i]] = i
		
		var members = class_obj.get_members()
		var inherited_members = class_obj.get_inherited_members()
		for dict in [members, inherited_members]:
			for member in dict:
				if member in constants_to_hide:
					continue
				var member_data = dict[member]
				var script_member_type = member_data.get(GDScriptParser.Keys.MEMBER_TYPE)
				if not is_instance and not GDScriptParser.Utils.member_is_valid_static(script_member_type):
					continue
				#print(member, "::", script_member_type)
				var script_path = member_data.get(GDScriptParser.Keys.SCRIPT_PATH)
				var parent_mask_i = parent_mask_map.get(script_path, inh_script_size)
				var location:CodeEdit.CodeCompletionLocation = CodeEdit.LOCATION_PARENT_MASK | parent_mask_i
				var display = member
				var insert = member
				var icon = "member"
				var kind:CodeEdit.CodeCompletionKind
				var font_color = Colors.DEFAULT_COMPLETION
				if script_member_type == GDScriptParser.Keys.MEMBER_TYPE_CONST:
					icon = "const"
					kind = CodeEdit.KIND_CONSTANT
				elif script_member_type == GDScriptParser.Keys.MEMBER_TYPE_CLASS:
					icon = "Object"
					kind = CodeEdit.KIND_CLASS
				elif script_member_type == GDScriptParser.Keys.MEMBER_TYPE_ENUM:
					icon = "enum"
					kind = CodeEdit.KIND_ENUM
				elif script_member_type.ends_with("func"):
					icon = "method"
					kind = CodeEdit.KIND_FUNCTION
					
					if insert_parens:
						var func_class_obj = class_obj
						var full_access_path = UString.dot_join(script_path, member_data.get(ParserKeys.ACCESS_PATH))
						if full_access_path != main_class_path:
							var next_parser = parser.get_parser_and_class_obj_for_script(full_access_path)
							func_class_obj = next_parser.class_obj
							#print(class_obj.get_script_class_path(), " -> ", func_class_obj.get_script_class_path())
						
						var func_obj = func_class_obj.get_function(member) as GDScriptParser.ParserFunc
						if func_obj.get_arguments().is_empty():
							display = member + "()"
							insert = member + "()"
						else:
							display = member + EditorCodeCompletion.Helpers.DOTS_UNICODE
							insert = member + "("
				else:
					icon = "property"
					kind = CodeEdit.KIND_MEMBER
					font_color = get_font_color_for_option(member)
				
				var cc_dict = code_completion.get_code_complete_dict(kind, display, insert, icon, null, location, font_color)
				code_completion.add_completion_option(script_editor, cc_dict)
		
		var update = params.get("update", false)
		params.erase("update")
		
		if params.get("user_include_base_type_members", false):
			built_in_completion(code_completion, class_obj.script_base_type, is_instance)
		
		if update:
			code_completion.update_completion_options(params.get("update_force", false))
		
		return true
		
	
	#! keys i-completion_params;
	static func add_global_classes_completion(code_completion:EditorCodeCompletion, params:={}):
		var script_editor = code_completion.get_code_edit()
		var parser = code_completion.get_gdscript_parser()
		var caret_context = code_completion.get_caret_context()
		var expression = caret_context.trim_last_member_access_part()
		
		if expression == "":
			if params.get("global_include_builtin", false):
				var built_ins = GDScriptParser.BuiltInChecker.get_class_names()
				for b in built_ins:
					var dict = code_completion.get_code_complete_dict(CodeEdit.KIND_CLASS, b, b, b)
					code_completion.add_completion_option(script_editor, dict)
			
			var global_classes = UClassDetail.get_all_global_class_paths()
			for name in global_classes.keys():
				var dict = code_completion.get_code_complete_dict(CodeEdit.CodeCompletionKind.KIND_CONSTANT, name, name, "Object", null, 2048)
				code_completion.add_completion_option(script_editor, dict)
		
		var include_preloads = params.get("global_include_class_preloads", false)
		if not include_preloads:
			return
		
		# trim the last Member.Access.[Part] to resolve the current class
		#var expression = UString.trim_member_access_back(class_path)
		
		var resolved = caret_context.resolve_expression_to_type(expression)
		#print("GLOBAL RESOLVED::", resolved)
		if GDScriptParser.BuiltInChecker.is_variant_type(resolved) or GDScriptParser.BuiltInChecker.is_builtin_class(resolved):
			pass
		elif GDScriptParser.Utils.type_path_get_member(resolved) != "":
			pass # this would be resolved to a member, so no preloads necessary
		else:
			var target_class_obj
			if resolved == "" or not resolved.begins_with("res://"): # resolved type is not a valid file
				target_class_obj = caret_context.get_current_class_object()
			else:
				var target_parser_data = parser.get_parser_and_class_obj_for_script(resolved)
				target_class_obj = target_parser_data.class_obj as GDScriptParser.ParserClass
			
			for c in target_class_obj.get_gdscript_constants():
				var member_data = target_class_obj.get_member(c)
				if not member_data:
					member_data = target_class_obj.get_inherited_member(c)
				var access_path = member_data.get(ParserKeys.ACCESS_PATH)
				#if target_class_obj.access_path != "": # should be find without
				if not access_path.begins_with(target_class_obj.access_path):
					continue
				#print("ADDING GLOBAL::", c)
				var dict = code_completion.get_code_complete_dict(CodeEdit.CodeCompletionKind.KIND_CONSTANT, c, c, "GDScriptInternal")
				code_completion.add_completion_option(script_editor, dict)
	
	
	static func get_font_color_for_option(option_name:String):
		if option_name == "x":
			return Colors.AXIS_X
		elif option_name == "y":
			return Colors.AXIS_Y
		elif option_name == "z":
			return Colors.AXIS_Z
		elif option_name == "w":
			return Colors.AXIS_W
		else:
			return Colors.DEFAULT_COMPLETION
	
	
	enum MemberFilter { METHODS, PROPERTIES }

	## Declared member types come back as type PATHS ("Node2D$$INS", "res://x.gd::Inner##Class").
	## Anything that feeds the type back in - subpath walking, receiver resolution - needs the
	## plain type instead.
	static func normalize_member_type(type:String) -> String:
		if type == "":
			return ""
		var type_check = GDScriptParser.Utils.type_path_get_type(type, true)
		if type_check != "":
			type = type_check
		return type.trim_suffix(GDScriptParser.Keys.INS_DELIM)

	## Flat {name: {"kind":…, "location":…, "type":…}} table of a resolved type's members.
	## built_in_completion/user_class_completion add options directly, so they can't serve callers
	## that need the raw names first - anything completing inside a string literal has to requote
	## them. Own members win over inherited ones, and a script's native base is folded in.
	static func collect_type_members(code_completion:EditorCodeCompletion, type:String,
							filter:MemberFilter, include_private:=false) -> Dictionary:
		var out := {}
		_collect_type_members(code_completion, type, filter, include_private, out)
		return out

	static func _collect_type_members(code_completion:EditorCodeCompletion, type:String,
							filter:MemberFilter, include_private:bool, out:Dictionary) -> void:
		if type == "":
			return
		if GDScriptParser.BuiltInChecker.is_builtin_class(type):
			_collect_built_in_members(type, filter, include_private, out)
		elif GDScriptParser.Utils.is_absolute_path(type):
			_collect_user_members(code_completion, type, filter, include_private, out)

	static func _collect_built_in_members(type:String, filter:MemberFilter, include_private:bool, out:Dictionary) -> void:
		var BIC = GDScriptParser.BuiltInChecker
		var class_data_array = BIC.get_class_data(type, true)
		for i in range(class_data_array.size()):
			var class_data:Dictionary = class_data_array[i]
			for member in class_data.keys():
				if member == BIC.CLASS_NAME or out.has(member):
					continue
				if not include_private and member.begins_with("_"):
					continue
				var member_type = class_data[member].get(BIC.MEMBER_TYPE)
				if filter == MemberFilter.METHODS:
					if member_type != BIC.METHODS:
						continue
					out[member] = {
						&"kind": CodeEdit.KIND_FUNCTION,
						&"location": CodeEdit.LOCATION_OTHER | i,
						&"type": "",
					}
				else:
					if member_type != BIC.MEMBERS and member_type != BIC.PROPERTIES:
						continue
					out[member] = {
						&"kind": CodeEdit.KIND_MEMBER,
						&"location": CodeEdit.LOCATION_OTHER | i,
						&"type": normalize_member_type(BIC.get_member_type(type, member)),
					}

	static func _collect_user_members(code_completion:EditorCodeCompletion, type:String,
							filter:MemberFilter, include_private:bool, out:Dictionary) -> void:
		var parser_data = code_completion.get_gdscript_parser().get_parser_and_class_obj_for_script(type)
		if not parser_data:
			return
		var class_obj = parser_data.class_obj as GDScriptParser.ParserClass
		if not is_instance_valid(class_obj):
			return

		var inherited_scripts = class_obj.get_inherited_scripts()
		var inh_script_size = inherited_scripts.size()
		var parent_mask_map := {}
		for i in range(inh_script_size):
			parent_mask_map[inherited_scripts[i]] = i

		for dict in [class_obj.get_members(), class_obj.get_inherited_members()]:
			for member in dict:
				if out.has(member):
					continue
				if not include_private and member.begins_with("_"):
					continue
				var member_data:Dictionary = dict[member]
				var member_type = member_data.get(GDScriptParser.Keys.MEMBER_TYPE)
				var kind:CodeEdit.CodeCompletionKind
				if filter == MemberFilter.METHODS:
					if not member_type.ends_with("func"):
						continue
					kind = CodeEdit.KIND_FUNCTION
				else:
					# consts/classes/enums/signals are not settable via set()/get()
					if member_type != GDScriptParser.Keys.MEMBER_TYPE_VAR and member_type != GDScriptParser.Keys.MEMBER_TYPE_STATIC_VAR:
						continue
					kind = CodeEdit.KIND_MEMBER

				var script_path = member_data.get(GDScriptParser.Keys.SCRIPT_PATH)
				var parent_mask_i = parent_mask_map.get(script_path, inh_script_size)
				out[member] = {
					&"kind": kind,
					&"location": CodeEdit.LOCATION_PARENT_MASK | parent_mask_i,
					&"type": normalize_member_type(class_obj.get_member_type(member, true)) if filter == MemberFilter.PROPERTIES else "",
				}

		# a script's native members are reachable through set()/call() too
		_collect_type_members(code_completion, class_obj.script_base_type, filter, include_private, out)

	static func set_code_hint(code_completion:EditorCodeCompletion, base_type:String, func_name:String):
		var func_data = GDScriptParser.BuiltInChecker.get_func_data(base_type, func_name)
		var script_editor = code_completion.get_code_edit()
		var func_call_data = code_completion.get_caret_context().get_function_call_data()
		#print(base_type, func_name)
		#print(func_data)
		
		if func_data:
			# Both of these are type PATHS now ("Node::ProcessMode##Enum"), so render them as a human
			# would write them. The arg used to be de-prefixed by hand here because BuiltInChecker handed
			# back the api's raw "enum::" notation; it no longer does, and the return - which never got
			# that treatment - is no longer displayed raw either.
			var func_args = func_data.get(ParserKeys.FUNC_ARGS)
			var func_ret = GDScriptParser.Utils.type_path_to_display(func_data.get(ParserKeys.FUNC_RETURN))
			if func_args.size() > func_call_data.current_arg_index:
				var current_arg = func_args.keys()[func_call_data.current_arg_index]
				var current_arg_data = func_args[current_arg]
				var current_arg_type = GDScriptParser.Utils.type_path_to_display(current_arg_data.get(GDScriptParser.Keys.TYPE))
				var code_hint = "%s %s(%s: %s)" % [func_ret, func_name, current_arg, current_arg_type]
				script_editor.set_code_hint(code_hint)
		
		
	
	
