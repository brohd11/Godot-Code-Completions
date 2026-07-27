extends EditorCodeCompletion

#! import_show_global SyntaxPlusSingleton,
#! import_p UClassDetail,Settings

const HidePrivate = preload("res://addons/code_completions/src/completions/hide_private.gd")
const HLInfo = SyntaxPlusSingleton.HLInfo

const CacheHelper = UtilsRemote.CacheHelper

#^ import hints
const PREFIX = "#!"
const _IMPORT_SHOW_GLOBAL = "import_show_global"
const _IMPORT_SHOW_GLOBAL_ALL = "import_show_global_all"
const _IMPORT_PRELOADS = "import_preloads"
const _IMPORT_P = "import_p"
const _IMPORT_G = "import_g"

#^ completion cache
const HINT_SEARCH_SCOPE = 10


#^ editor settings
var _enable:bool = true
var default_imports:Array = []
var hide_global_classes_setting:= false
var hide_global_exemptions:Array = []


var _class_member_cache:Dictionary = {}

var extended_class_names:Dictionary = {} #^ [name, bool] a set

var global_classes:Dictionary = {} #^ [name, path]
var preload_paths:Dictionary = {} #^ [path, bool] a set

var show_global_classes:Dictionary = {} #^ [name, script]
var hide_global_classes = false
var hide_private_members = false


var current_import_data:ImportData

const _COMMENT_TAGS = {
	PREFIX: {
		_IMPORT_PRELOADS:null,
		_IMPORT_SHOW_GLOBAL:"_import_syntax_hl",
		_IMPORT_SHOW_GLOBAL_ALL:"_import_syntax_hl",
		_IMPORT_P:"_import_syntax_hl",
		_IMPORT_G:"_import_syntax_hl",
	}
}

func _get_completion_settings() -> Dictionary:
	return {
		"priority": 500,
	}


func _singleton_ready():
	
	for prefix in _COMMENT_TAGS.keys():
		var tag_data = _COMMENT_TAGS.get(prefix)
		for tag in tag_data.keys():
			var callable_nm = tag_data.get(tag)
			if callable_nm == null:
				SyntaxPlusSingleton.register_comment_tag(prefix, tag)
			else:
				var callable = get(callable_nm)
				SyntaxPlusSingleton.register_highlight_callable(prefix, tag, callable, SyntaxPlusSingleton.CallableLocation.START)
			register_tag(prefix, tag, TagLocation.START)


func register_editor_settings(settings_helper:SettingHelperEditor):
	settings_helper.subscribe_property(self, &"_enable", Settings.IMPORT_ENABLE, true)
	settings_helper.subscribe_property(self, &"hide_private_members", Settings.HIDE_PRIVATE_PROP_SETTINGS, true)
	settings_helper.subscribe_property(self, &"default_imports", Settings.DEFAULT_IMPORTS, [])
	settings_helper.subscribe_property(self, &"hide_global_classes_setting", Settings.HIDE_GLOBAL_SETTING, false)
	settings_helper.subscribe_property(self, &"hide_global_exemptions", Settings.HIDE_GLOBAL_EXEMP_SETTING, [])
	
	var editor_settings = EditorInterface.get_editor_settings()
	while not editor_settings.has_setting(Settings.HIDE_GLOBAL_EXEMP_SETTING):
		await EditorInterface.get_base_control().get_tree().process_frame
	
	var hide_global_exemp_pi = Settings.get_str_arr_prop_info(Settings.HIDE_GLOBAL_EXEMP_SETTING)
	editor_settings.add_property_info(hide_global_exemp_pi)
	
	var default_import_pi = Settings.get_str_arr_prop_info(Settings.DEFAULT_IMPORTS)
	editor_settings.add_property_info(default_import_pi)


func _set_settings():
	var editor_settings = EditorInterface.get_editor_settings()
	hide_global_classes_setting = editor_settings.get_setting(Settings.HIDE_GLOBAL_SETTING)
	hide_global_exemptions = editor_settings.get_setting(Settings.HIDE_GLOBAL_EXEMP_SETTING)
	hide_private_members = editor_settings.get_setting(Settings.HIDE_PRIVATE_PROP_SETTINGS)
	
	_on_editor_script_changed(null)


func _on_editor_script_changed(_script):
	
	editor_theme = EditorInterface.get_editor_theme()
	_get_script_imports.call_deferred()
	_get_global_and_preloads.call_deferred()



func _on_code_completion_requested(script_editor:CodeEdit) -> bool:
	if not _enable:
		return false
	
	var current_script = get_current_script()
	if current_script == null:
		return false
	
	var caret_context = get_caret_context()
	if caret_context.token_state == TokenState.COMMENT:
		var caret_line = script_editor.get_caret_line()
		var current_line_text = script_editor.get_line(caret_line)
		var import_hint_options = _import_hint_autocomplete(current_line_text)
		if not import_hint_options.is_empty():
			for o in import_hint_options:
				add_completion_option(script_editor, o)
			update_completion_options()
			return true
		return false
	elif caret_context.token_state != TokenState.NONE:
		return false
	
	var has_declaration = caret_context.line_declaration != ""
	var expression_state = caret_context.expression_state
	if has_declaration and expression_state == ExpressionState.NONE:
		return false
	elif expression_state == ExpressionState.MEMBER_ACCESS:
		return false
	elif expression_state == ExpressionState.TYPE_HINT:
		return false
	elif caret_context.is_in_enum():
		return false
	elif caret_context.code_context_stripped.begins_with("func") or caret_context.code_context_stripped.begins_with("static func"):
		return false
	
	
	var existing_options = script_editor.get_code_completion_options()
	
	# check if the current options are enum completions. If they all are, don't alter
	if _existing_is_enum(existing_options):
		return false
	
	if existing_options.size() < 20:
		if _SKIP_KEYWORDS.has(caret_context.expression_before_caret):
			return false
		if _SKIP_CHARS.has(caret_context.char_before_caret):
			return false
	
	var completions = _get_options_v2()
	
	for e in existing_options:
		var display = e.display_text
		if completions.has(display):
			printerr("COMPLETION HAS!!", display)
			continue
		if current_import_data.hide_global_classes:
			if current_import_data.global_classes.has(display) and not current_import_data.visible_global_classes.has(display):
				continue
		add_completion_option(script_editor, e)
	
	for c in completions.keys():
		add_completion_option(script_editor, completions[c])
	
	update_completion_options()
	return true


func _get_options_v2():
	var t = GDScriptParser.TF.new("IMPORT V2")
	var current_parser = get_gdscript_parser()
	var completions = {}
	
	
	for access_path in current_import_data.imported_classes.keys():
		_import_members(
			access_path,
			_get_class_members(
				current_parser,
				current_import_data.imported_classes[access_path]
			),
			completions
		)
	
	t.stop()
	return completions


func _import_members(access_path:String, members:Dictionary, completions:Dictionary):
	for m in members:
		var data = members[m]
		var full_path = UString.dot_join(access_path, m)
		#trim_
		var insert = full_path
		var display = full_path
		if insert.ends_with("("):
			display = insert.trim_suffix("(") + Helpers.DOTS_UNICODE
		#print(display, ";", data)
		#trim
		completions[display] = get_code_complete_dict(data[0], display, insert, data[1])


func _get_class_members(parser:GDScriptParser, path:String):
	#_class_member_cache = {}
	
	var cached = CacheHelper.get_cached_data(path, _class_member_cache)
	if cached != null:
		return cached
	var members = {}
	var path_data = GDScriptParser.Utils.type_path_get_script_data(path)
	var access_path = path_data[1]
	var parser_data = parser.get_parser_and_class_obj_for_script(path)
	var class_obj = parser_data.class_obj
	for func_name in class_obj.functions.keys():
		var func_obj = class_obj.functions[func_name] as GDScriptParser.ParserFunc
		if not func_obj.is_static():
			continue
		var has_args = not func_obj.arguments.is_empty()
		var insert = func_name + "()"
		#var display = insert
		if has_args:
			insert = func_name + "("
			#display = func_name + "(%s)" % Helpers.DOTS_UNICODE
		members[insert] = [CodeEdit.KIND_FUNCTION, "method"]
	
	for c in class_obj.constants.keys():
		var data = class_obj.constants[c]
		if not data.get(ParserKeys.ACCESS_PATH) == access_path:
			continue # ensure only actual members are listed
		if data.get(ParserKeys.MEMBER_TYPE) == ParserKeys.ENUM_MEMBERS:
			members[c] = [CodeEdit.KIND_ENUM, "enum"]
			var enum_members = class_obj.get_enum_members(c)
			for e in enum_members:
				members[UString.dot_join(c, e)] = [CodeEdit.KIND_ENUM, "enum"]
		else:
			var type = class_obj.get_member_type(c)
			if type.is_absolute_path():
				continue
			members[c] = [CodeEdit.KIND_CONSTANT, "const"]
	
	for m in class_obj.members.keys():
		var data = class_obj.members[m]
		if data.get(ParserKeys.MEMBER_TYPE) == ParserKeys.MEMBER_TYPE_STATIC_VAR:
			members[m] = [CodeEdit.KIND_MEMBER, "property"]
	
	#for ic in class_obj.inner_classes.keys():
		#members[ic] = [CodeEdit.KIND_CLASS, "Object"]
	
	CacheHelper.store_data(path, members, _class_member_cache, [path_data[0]])
	return members



func _get_script_imports():
	global_classes = UClassDetail.get_all_global_class_paths()
	
	current_import_data = null
	
	var script_editor = get_code_edit()
	if script_editor == null:
		return []
	
	
	var parser = get_gdscript_parser()
	
	
	var parser_script = parser.get_script_path()
	var cached = get_import_data(parser_script)
	if cached != null:
		current_import_data = cached
		return
	
	var import_preloads := false
	
	var preload_imports = []
	var global_imports = []
	
	var show_all_globals := false
	var globals_to_show = {}
	
	var all_imports = []
	
	var max_count = mini(script_editor.get_line_count(), HINT_SEARCH_SCOPE)
	var i = -1
	var found_import:=false
	while i < max_count:
		i += 1
		var line = script_editor.get_line(i)
		if not line.begins_with("#! import"):
			if found_import:
				break
			else:
				continue
		found_import = true
		max_count += 1
		var hint = line.get_slice(PREFIX, 1).strip_edges().get_slice(" ", 0).strip_edges()
		if hint == _IMPORT_SHOW_GLOBAL_ALL:
			show_all_globals = true
		elif hint == _IMPORT_PRELOADS:
			import_preloads = true
		elif hint == _IMPORT_SHOW_GLOBAL:
			var classes = _get_classes_in_line(line.get_slice(_IMPORT_SHOW_GLOBAL, 1).strip_edges())
			for c in classes:
				globals_to_show[c] = true
		elif hint == _IMPORT_G:
			var classes = _get_classes_in_line(line.get_slice(_IMPORT_G, 1).strip_edges())
			global_imports.append_array(classes)
		elif hint == _IMPORT_P:
			var classes = _get_classes_in_line(line.get_slice(_IMPORT_P, 1).strip_edges())
			preload_imports.append_array(classes)
	
	
	var all_imported_classes = {}
	show_global_classes.clear()
	
	var class_obj:GDScriptParser.ParserClass = parser.get_class_object("")
	if import_preloads:
		var gd_constants = class_obj.get_gdscript_constants(true)
		for c in gd_constants:
			var type = gd_constants[c]
			if type.ends_with(GDScriptParser.Keys.ENUM_PATH_SUFFIX):
				continue
			all_imported_classes[c] = type
	
	all_imports.append_array(global_imports)
	all_imports.append_array(preload_imports)
	all_imports.append_array(default_imports)
	
	for access_path in all_imports:
		if access_path.is_empty() or all_imported_classes.has(access_path) or extended_class_names.has(access_path):
			continue
		var resolved = ""
		if class_obj.has_script_member(access_path) or class_obj.has_inherited_member(access_path):
			resolved = class_obj.get_member_type(access_path, true)
		else:
			resolved = parser.resolve_expression_to_type(access_path)
		
		if resolved != "":
			all_imported_classes[access_path] = resolved
	
	print(globals_to_show)
	print(global_imports)
	if not hide_global_classes_setting or show_all_globals:
		hide_global_classes = false
	else:
		hide_global_classes = true
		for _class in globals_to_show.keys():
			var path = UClassDetail.get_global_class_path(_class)
			if path == "":
				globals_to_show.erase(_class)
		
		for _class in global_imports:
			var path = UClassDetail.get_global_class_path(_class)
			if path != "":
				globals_to_show[_class] = true
		
		for _class in hide_global_exemptions:
			var path = UClassDetail.get_global_class_path(_class)
			if path != "":
				globals_to_show[_class] = true
			else:
				pass
				#printerr("Hide global class editor setting class not found: ", _class)
				
	
	
	var import_data = ImportData.new()
	import_data.hide_global_classes = hide_global_classes
	import_data.visible_global_classes = globals_to_show
	import_data.imported_classes = all_imported_classes
	
	current_import_data = import_data
	#singleton.peristent_cache.erase(&"import_data")
	var import_data_cache = singleton.peristent_cache.get_or_add(&"import_data", {})
	CacheHelper.store_data(parser_script, import_data, import_data_cache, [parser_script])
	
	#set_data("import_data", import_data)

static func get_import_data(path:String):
	var ins = EditorCodeCompletionSingleton.get_instance()
	var import_data_cache = ins.peristent_cache.get_or_add(&"import_data", {})
	return CacheHelper.get_cached_data(path, import_data_cache)

func _get_global_and_preloads():
	global_classes = UClassDetail.get_all_global_class_paths()
	
	#preload_paths.clear()
	#var preloads = UClassDetail.script_get_preloads(get_current_script())
	#for _name in preloads:
		#var script = preloads.get(_name)
		#if script.resource_path != "":
			#preload_paths[script.resource_path] = true
	
	extended_class_names.clear()
	var inh_scripts = UClassDetail.script_get_inherited_script_paths(get_current_script())
	for path in inh_scripts:
		var script = load(path) as Script
		if script.get_global_name() != "":
			extended_class_names[script.get_global_name()] = true


func _import_syntax_hl(script_editor:CodeEdit, current_line_text:String, _line:int, comment_tag_idx:int):
	var sp_ins = SyntaxPlusSingleton.get_instance()
	var hl_info = {}
	var global_class_color = sp_ins.user_type_color
	var preload_class_color = sp_ins.global_function_color
	var symbol_color = sp_ins.symbol_color
	
	var comment_text = current_line_text.substr(comment_tag_idx)
	hl_info.merge(HLInfo.highlight_prefix(PREFIX, comment_text))
	
	var substr = current_line_text.substr(comment_tag_idx + 2).strip_edges()
	var hint = substr.get_slice(" ", 0).strip_edges()
	
	var show_global_hint = hint == _IMPORT_SHOW_GLOBAL # list globals to show
	var show_global_all_hint = hint == _IMPORT_SHOW_GLOBAL_ALL # shows all in the file, overides editor setting
	if not hide_global_classes_setting and (show_global_hint or show_global_all_hint):
		hl_info.merge(HLInfo.highlight_tag(hint, comment_text, Color.FIREBRICK))
		return hl_info
	elif hide_global_classes_setting and show_global_all_hint:
		hl_info.merge(HLInfo.highlight_tag(hint, comment_text))
		return hl_info
	
	var global_hint = hint == _IMPORT_G
	var preload_hint = hint == _IMPORT_P
	if not (global_hint or preload_hint or show_global_hint):
		return hl_info #^ empty
	
	var current_classes = _get_current_classes_of_hint(hint, script_editor)
	hl_info.merge(HLInfo.highlight_tag(hint, comment_text))
	
	var in_scope_class_names:Array
	var class_color:Color
	if global_hint or show_global_hint:
		var global_class_paths = UClassDetail.get_all_global_class_paths()
		in_scope_class_names = global_class_paths.keys()
		class_color = global_class_color
	elif preload_hint:
		var current_script = get_current_script()
		var preloads = UClassDetail.script_get_preloads(current_script, true, true)
		in_scope_class_names = preloads.keys()
		class_color = preload_class_color
	
	for _class_name in current_classes:
		if _class_name in in_scope_class_names:
			var hl_color = class_color
			if extended_class_names.has(_class_name) and not show_global_hint: #^ show global hint to allow showing self
				hl_color = Color.FIREBRICK
			var idx = find_indentifier_in_line(comment_text, _class_name)
			if idx == -1:
				continue
			
			hl_info[idx] = HLInfo.get_color_dict(hl_color)
			var comma_idx = comment_text.find(",", idx)
			if comma_idx != -1:
				HLInfo.add_color(hl_info, symbol_color, comma_idx, comma_idx + 1)
				#hl_info[comma_idx] = SyntaxPlusSingleton.get_hl_info_dict(symbol_color)
				#hl_info[comma_idx + 1] = SyntaxPlusSingleton.get_hl_info_dict(comment_color)
	
	return hl_info

func _get_classes_in_line(text:String):
	var current_classes = text.split(",",false)
	for i_slice in range(current_classes.size()):
		var nm = current_classes[i_slice]
		nm = nm.strip_edges()
		current_classes[i_slice] = nm
	return current_classes


func _get_current_classes_of_hint(hint:String, script_editor:CodeEdit):
	var classes_array = []
	var line_count = script_editor.get_line_count()
	for i in range(HINT_SEARCH_SCOPE):
		if not i < line_count:
			break
		var line = script_editor.get_line(i)
		if not line.begins_with(PREFIX):
			continue
		if not line.find(hint) > -1:
			continue
		
		var current_classes_str = line.get_slice(hint, 1).strip_edges()
		var current_classes = current_classes_str.split(",",false)
		for i_slice in range(current_classes.size()):
			var nm = current_classes[i_slice]
			nm = nm.strip_edges()
			current_classes[i_slice] = nm
		classes_array.append_array(current_classes)
	
	return classes_array


func _import_hint_autocomplete(current_line_text:String):
	var script_editor = get_code_edit()
	var options = []
	var tag = "#! "
	var full_show_global_hint = tag + _IMPORT_SHOW_GLOBAL
	var full_g_hint = tag + _IMPORT_G
	var full_p_hint = tag + _IMPORT_P
	if current_line_text.begins_with(full_g_hint):
		var current_classes = _get_current_classes_of_hint(full_g_hint, script_editor)
		_get_global_and_preloads()
		var class_names = global_classes.keys()
		for _name in class_names:
			if extended_class_names.has(_name):
				continue
			if _name in current_classes:
				continue
			var completion = get_code_complete_dict(CodeEdit.CodeCompletionKind.KIND_CLASS, _name, _name + ",", "Object")
			options.append(completion)
	elif current_line_text.begins_with(full_show_global_hint):
		var current_classes = _get_current_classes_of_hint(full_show_global_hint, script_editor)
		_get_global_and_preloads()
		var class_names = global_classes.keys()
		for _name in class_names:
			if _name in current_classes:
				continue
			if _name in hide_global_exemptions:
				continue
			var completion = get_code_complete_dict(CodeEdit.CodeCompletionKind.KIND_CLASS, _name, _name + ",", "Object")
			options.append(completion)
	elif current_line_text.begins_with(full_p_hint):
		var current_classes = _get_current_classes_of_hint(full_p_hint, script_editor)
		var current_script = get_current_script()
		var preloads = UClassDetail.script_get_preloads(current_script, true, true) #^ this may want to be changed a bit, doesn't need a deep search, also above in highlighting
		for _name in preloads.keys():
			if _name.find(".") > -1:
				continue
			if _name in current_classes:
				continue
			var completion = get_code_complete_dict(CodeEdit.CodeCompletionKind.KIND_CLASS, _name, _name + ",", "Object")
			options.append(completion)
	
	return options


static func find_indentifier_in_line(line_text:String, identifier:String) -> int:
	var line_length = line_text.length()
	var idx = line_text.find(identifier)
	var i = idx + identifier.length()
	while idx != -1 and i < line_length:
		var next_char = line_text[i]
		var full_id:String = identifier + next_char
		if not full_id.is_valid_ascii_identifier():
			break
		idx = line_text.find(identifier, idx + 1)
		i = idx + identifier.length()
	return idx

func _existing_is_enum(existing_options:Array):
	if existing_options.is_empty():
		return false
	else:
		for o in existing_options:
			if o.kind != CodeEdit.CodeCompletionKind.KIND_ENUM:
				return false
	return true

const _SKIP_KEYWORDS = {
	"pass":true,
	"return":true,
	"break":true,
	"continue":true,
	"null":true,
	"true":true,
	"false":true,
	}

const _SKIP_CHARS = {
	",":true,
}

const _SKIP_DECLARATIONS = [
	"static ",
	"func ",
	"const",
	"var ",
	"enum",
	"class ",
	"class_name ",
]

class ImportData:
	
	var global_classes:Dictionary = {}
	var hide_global_classes:bool = false
	var hide_global_exemption:Array = []
	var visible_global_classes:Dictionary = {}
	var imported_classes:Dictionary = {}
	
	func _init() -> void:
		global_classes = UtilsRemote.UClassDetail.get_all_global_class_paths()

class Settings:
	const IMPORT_ENABLE = &"plugin/code_completion/import/enable"
	const DEFAULT_IMPORTS = &"plugin/code_completion/import/default_imports"
	const HIDE_GLOBAL_SETTING = &"plugin/code_completion/import/hide_global_classes"
	const HIDE_PRIVATE_PROP_SETTINGS = HidePrivate._HIDE_PRIVATE_PROP_SETTING
	
	const HIDE_GLOBAL_EXEMP_SETTING = &"plugin/code_completion/import/hide_global_exemptions"
	
	
	const _STRING_ARRAY_PROP_INFO = {
	"name": "",
	"type": TYPE_ARRAY,
	"hint": PROPERTY_HINT_TYPE_STRING,
	"hint_string": "%d:%d"
	}
	
	static func get_str_arr_prop_info(setting_path:String, hint_string:String=""):
		if hint_string == "":
			hint_string = "%d:" % [TYPE_STRING]
		var info = _STRING_ARRAY_PROP_INFO.duplicate()
		info["name"] = setting_path
		info["hint_string"] = hint_string
		return info 
