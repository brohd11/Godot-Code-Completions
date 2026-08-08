extends EditorCodeCompletion

#! import_show_global SyntaxPlusSingleton
#! import_p UClassDetail,Settings,UString,

const HidePrivate = preload("res://addons/code_completions/src/completions/hide_private.gd")
const HLInfo = SyntaxPlusSingleton.HLInfo

const CacheHelper = UtilsRemote.CacheHelper

#^ import hints
const PREFIX = "#!"
const _IMPORT_SHOW_GLOBAL = "import_show_global"
const _IMPORT_P = "import_p"
const _IMPORT_G = "import_g"

const ALL_KEYWORD = "<all>"
const HINT_SEARCH_SCOPE = 10

#^ editor settings
var _enable:bool = true
var default_imports:Array = []
var hide_global_classes_setting:= false
var hide_global_exemptions:Array = []
var hide_private_members = false

#^ caches
var _misc_cache:Dictionary = {}
var _class_member_cache:Dictionary = {}

#^ set on current script
var extended_class_names:Dictionary = {} #^ [name, bool] a set
var current_import_data:ImportData

const _COMMENT_TAGS = {
	PREFIX: {
		_IMPORT_SHOW_GLOBAL:"_import_syntax_hl",
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
	
	EditorInterface.get_resource_filesystem().filesystem_changed.connect(_on_filesystem_changed)


func register_editor_settings(settings_helper:SettingHelperEditor):
	settings_helper.subscribe_property(self, &"_enable", Settings.IMPORT_ENABLE, true)
	settings_helper.subscribe_property(self, &"hide_private_members", Settings.HIDE_PRIVATE_PROP_SETTINGS, true)
	settings_helper.subscribe_property(self, &"default_imports", Settings.DEFAULT_IMPORTS, [])
	settings_helper.subscribe_property(self, &"hide_global_classes_setting", Settings.HIDE_GLOBAL_SETTING, false)
	settings_helper.subscribe_property(self, &"hide_global_exemptions", Settings.HIDE_GLOBAL_EXEMP_SETTING, [])
	
	_on_project_settings_changed()
	ProjectSettings.add_property_info(Settings.get_str_arr_prop_info(Settings.DEFAULT_IMPORTS))
	ProjectSettings.settings_changed.connect(_on_project_settings_changed)
	
	# add prop infos once added
	var editor_settings = EditorInterface.get_editor_settings()
	while not editor_settings.has_setting(Settings.HIDE_GLOBAL_EXEMP_SETTING):
		await EditorInterface.get_base_control().get_tree().process_frame
	
	var hide_global_exemp_pi = Settings.get_str_arr_prop_info(Settings.HIDE_GLOBAL_EXEMP_SETTING)
	editor_settings.add_property_info(hide_global_exemp_pi)
	

func _on_project_settings_changed():
	if not ProjectSettings.has_setting(Settings.DEFAULT_IMPORTS):
		ProjectSettings.set_setting(Settings.DEFAULT_IMPORTS, [])
	default_imports = ProjectSettings.get_setting(Settings.DEFAULT_IMPORTS, [])
	

func _on_filesystem_changed():
	_set_extended_names()

func _on_editor_script_changed(_script):
	current_import_data = null
	editor_theme = EditorInterface.get_editor_theme()
	_set_extended_names.call_deferred()


func _on_code_completion_requested(script_editor:CodeEdit) -> bool:
	if not _enable:
		return false
	
	var current_script = get_current_script()
	if current_script == null:
		return false
	
	var caret_context = get_caret_context()
	if caret_context.token_state == TokenState.COMMENT:
		return _import_hint_autocomplete(script_editor)
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
	
	var completions = _get_options_import_completions()
	
	for e in existing_options:
		var display = e.display_text
		if completions.has(display):
			printerr("COMPLETION HAS!!", display)
			continue
		if current_import_data.hide_global_classes:
			if singleton.global_classes.has(display) and not current_import_data.visible_global_classes.has(display):
				continue
		add_completion_option(script_editor, e)
	
	for c in completions.keys():
		add_completion_option(script_editor, completions[c])
	
	update_completion_options()
	return true


func _get_options_import_completions():
	var current_parser = get_gdscript_parser()
	var completions = {}
	
	ensure_import_data()
	
	for access_path in current_import_data.imported_classes.keys():
		_import_members(
			access_path,
			_get_class_members(
				current_parser,
				current_import_data.imported_classes[access_path]
			),
			completions
		)
	
	return completions


func _import_members(access_path:String, members:Dictionary, completions:Dictionary):
	for m in members:
		if _should_hide_member(m): # check setting and underscore beginning
			continue
		var data = members[m]
		var full_path = UString.dot_join(access_path, m)
		var insert = full_path
		var display = full_path
		display = Helpers.complete_function_display(insert)
		completions[display] = get_code_complete_dict(data[0], display, insert, data[1])


func _get_class_members(parser:GDScriptParser, path:String):
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
		var insert = func_name + "()" if func_obj.arguments.is_empty() else func_name + "("
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


#region ImportData

func ensure_import_data():
	if not is_instance_valid(current_import_data) or current_import_data.script_path != get_current_script().resource_path:
		_set_import_data()

func _set_import_data():
	current_import_data = null
	var import_data_cache = singleton.peristent_cache.get_or_add(&"import_data", {})
	
	var parser = get_gdscript_parser()
	var parser_script = parser.get_script_path()
	var cached = CacheHelper.get_cached_data(parser_script, import_data_cache)
	if cached != null:
		current_import_data = cached
		return
	
	var current_import_dict = _get_current_import_data()
	if current_import_dict.is_empty():
		return
	
	var import_data = current_import_dict.get("import_data")
	current_import_data = import_data
	CacheHelper.store_data(parser_script, import_data, import_data_cache, [parser_script])


func _get_current_import_data() -> Dictionary:
	var script_editor = get_code_edit()
	if script_editor == null:
		return {}
	
	var parser = get_gdscript_parser()
	var class_obj:GDScriptParser.ParserClass = parser.get_class_object("")
	if not is_instance_valid(class_obj):
		return {}
	
	var current_hints = _get_current_hints(script_editor)
	
	var import_preloads:bool = current_hints.import_all_preloads
	var preload_imports:Array = current_hints.preload_imports
	var import_all_globals:bool = current_hints.import_all_globals
	var global_imports:Array = current_hints.global_imports
	var show_all_globals:bool = current_hints.show_all_globals
	var globals_to_show:Array = current_hints.globals_to_show
	
	var all_imports = []
	var all_imported_classes = {}
	
	if import_preloads:
		var gd_constants = class_obj.get_gdscript_constants(true)
		for c in gd_constants:
			var type = gd_constants[c]
			if type.ends_with(GDScriptParser.Keys.ENUM_PATH_SUFFIX):
				continue
			all_imported_classes[c] = type
	
	if import_all_globals:
		append_array_no_dupe(all_imports, singleton.global_classes.keys())
	
	append_array_no_dupe(all_imports, preload_imports)
	append_array_no_dupe(all_imports, global_imports)
	append_array_no_dupe(all_imports, default_imports)
	
	for access_path in all_imports:
		if access_path.is_empty() or all_imported_classes.has(access_path) or extended_class_names.has(access_path):
			continue
		var resolved = ""
		if class_obj.has_script_member(access_path) or class_obj.has_inherited_member(access_path):
			resolved = class_obj.get_member_type(access_path, true)
		else:
			resolved = parser.resolve_expression_to_type(access_path)
		
		if resolved != "" and resolved.is_absolute_path():
			all_imported_classes[access_path] = resolved
	
	var hide_global_classes = true
	if not hide_global_classes_setting or show_all_globals:
		hide_global_classes = false
	else:
		for _class in globals_to_show:
			var path = UClassDetail.get_global_class_path(_class)
			if path == "":
				globals_to_show.erase(_class)
		
		for _class in global_imports:
			var path = UClassDetail.get_global_class_path(_class)
			if path != "":
				globals_to_show.append(_class)
		
		for _class in hide_global_exemptions:
			var path = UClassDetail.get_global_class_path(_class)
			if path != "":
				globals_to_show.append(_class)
			#else:
				#printerr("Hide global class editor setting class not found: ", _class)
	
	
	var import_data = ImportData.new()
	import_data.script_path = parser.get_script_path()
	import_data.hide_global_classes = hide_global_classes
	import_data.visible_global_classes = globals_to_show
	import_data.imported_classes = all_imported_classes
	
	return {
		"import_data": import_data
	}

#endregion

#region SyntaxHL

func _import_syntax_hl(script_editor:CodeEdit, current_line_text:String, _line:int, comment_tag_idx:int):
	var current_script = get_current_script()
	var sp_ins = SyntaxPlusSingleton.get_instance()
	var hl_info = {}
	var global_class_color = sp_ins.user_type_color
	var preload_class_color = sp_ins.global_function_color
	var fail_color = Color.FIREBRICK
	
	var comment_text = current_line_text.substr(comment_tag_idx)
	hl_info.merge(HLInfo.highlight_prefix(PREFIX, comment_text))
	
	var substr = current_line_text.substr(comment_tag_idx + 2).strip_edges()
	var hint = substr.get_slice(" ", 0).strip_edges()
	
	var show_global_hint = hint == _IMPORT_SHOW_GLOBAL # list globals to show
	if not hide_global_classes_setting and show_global_hint:
		hl_info.merge(HLInfo.highlight_tag(hint, comment_text, fail_color))
		return hl_info
	
	var global_hint = hint == _IMPORT_G
	var preload_hint = hint == _IMPORT_P
	if not (global_hint or preload_hint or show_global_hint):
		return hl_info #^ empty
	
	# highlight import hint tag
	hl_info.merge(HLInfo.highlight_tag(hint, comment_text))
	
	var name_data = _get_valid_and_current_names_for_line(hint, script_editor)
	
	var current_classes = name_data.current
	var in_scope_class_names:Array = name_data.valid
	var class_color:Color = preload_class_color if preload_hint else global_class_color
	
	_add_color(hl_info, comment_text, ALL_KEYWORD, SyntaxPlusSingleton.DEFAULT_TAG_COLOR, sp_ins)
	for _class_name in current_classes:
		var is_valid = _class_name in in_scope_class_names
		if _class_name.contains("."):
			is_valid = UClassDetail.get_member_info_by_path(current_script, _class_name) != null
		if is_valid:
			var hl_color = class_color
			if extended_class_names.has(_class_name) and not show_global_hint: #^ show global hint to allow showing self
				hl_color = fail_color
			_add_color(hl_info, comment_text, _class_name, hl_color, sp_ins)
	
	return hl_info

func _add_color(hl_info:Dictionary, comment_text:String, word:String, color:Color, sp_ins:SyntaxPlusSingleton):
	var word_idx = find_indentifier_in_line(comment_text, word)
	if word_idx == -1:
		return
	
	hl_info[word_idx] = HLInfo.get_color_dict(color)
	var comma_idx = comment_text.find(",", word_idx)
	if comma_idx != -1:
		HLInfo.add_color(hl_info, sp_ins.symbol_color, comma_idx, comma_idx + 1)
	else:
		HLInfo.add_color(hl_info, sp_ins.comment_color, word_idx + word.length())

#endregion

#region Completion

func _import_hint_autocomplete(script_editor:CodeEdit):
	# Triggers on any comment, aborts on no prefix or hint
	var current_line_text =  script_editor.get_line(script_editor.get_caret_line())
	var hint_type = _get_hint_type_from_line(current_line_text)
	if hint_type == "":
		return false
	
	var name_data = _get_valid_and_current_names_for_line(hint_type, get_code_edit())
	var options = []
	
	if not current_line_text.contains(ALL_KEYWORD):
		options.append(get_code_complete_dict(CodeEdit.KIND_CLASS, ALL_KEYWORD, ALL_KEYWORD, Helpers.TAG_ICON_NAME, null, 0))
	
	for _name in name_data.valid:
		if _name in name_data.current:
			continue
		options.append(get_code_complete_dict(
				CodeEdit.KIND_CLASS,
				_name,
				_name + ",",
				"Object"
			))
	
	if options.is_empty():
		return false
	
	for o in options:
		add_completion_option(script_editor, o)
	update_completion_options()
	return true

#endregion

#! keys valid:Array current:Array
func _get_valid_and_current_names_for_line(hint_type:String, script_editor:CodeEdit):
	var current_hints = _get_current_hints(script_editor)
	var valid_names = []
	var current_names = []
	match hint_type:
		_IMPORT_SHOW_GLOBAL, _IMPORT_G:
			valid_names = singleton.global_classes.keys()
			current_names = current_hints.global_imports if hint_type == _IMPORT_G else current_hints.globals_to_show
		_IMPORT_P:
			valid_names = _get_script_preloads()
			current_names = current_hints.preload_imports
	
	return {
		&"valid": valid_names,
		&"current": current_names
	}


#! keys import_all_preloads:bool import_all_globals:bool show_all_globals:bool
#! keys preload_imports:Array global_imports:Array globals_to_show:Array
func _get_current_hints(script_editor:CodeEdit):
	var import_all_preloads := false
	var import_all_globals := false
	var show_all_globals := false
	var preload_imports = []
	var global_imports = []
	var globals_to_show = []
	
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
		var hint = _get_hint_type_from_line(line)
		if not hint in [_IMPORT_SHOW_GLOBAL, _IMPORT_G, _IMPORT_P]:
			print("Unrecognized import hint: ", hint)
			continue
		
		var classes = _get_classes_in_line(line.get_slice(hint, 1).strip_edges())
		var target:Array
		if hint == _IMPORT_SHOW_GLOBAL:
			target = globals_to_show
			if ALL_KEYWORD in classes:
				show_all_globals = true
		elif hint == _IMPORT_G:
			target = global_imports
			if ALL_KEYWORD in classes:
				import_all_globals = true
		elif hint == _IMPORT_P:
			target = preload_imports
			if ALL_KEYWORD in classes:
				import_all_preloads = true
		
		classes.erase(ALL_KEYWORD)
		append_array_no_dupe(target, classes)
	
	return {
		"import_all_preloads": import_all_preloads,
		"import_all_globals": import_all_globals,
		"show_all_globals": show_all_globals,
		"preload_imports": preload_imports,
		"global_imports": global_imports,
		"globals_to_show": globals_to_show,
	}

func _get_classes_in_line(text:String):
	var current_classes = text.split(",",false)
	for i_slice in range(current_classes.size()):
		var nm = current_classes[i_slice]
		nm = nm.strip_edges()
		current_classes[i_slice] = nm
	return current_classes


## finds the first instance, check before and after to ensure full word
static func find_indentifier_in_line(line_text:String, identifier:String) -> int:
	var line_length = line_text.length()
	var idx = line_text.find(identifier)
	var i = idx + identifier.length()
	while idx != -1 and i < line_length:
		#var valid_front = idx == 0 or not (line_text[idx - 1] + identifier).is_valid_ascii_identifier()
		#var valid_back = not (identifier + line_text[i]).is_valid_ascii_identifier()
		var valid_front = idx == 0 or not line_text[idx - 1] in UString.INDENTIFIER_CHARS
		var valid_back = not line_text[i] in UString.INDENTIFIER_CHARS
		if valid_front and valid_back:
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


func _get_hint_type_from_line(line_text:String) -> String:
	if not line_text.begins_with(PREFIX):
		return ""
	var hint = line_text.trim_prefix(PREFIX).strip_edges().get_slice(" ", 0).strip_edges()
	if hint == _IMPORT_G or hint == _IMPORT_SHOW_GLOBAL or hint == _IMPORT_P:
		return hint
	return ""

func _set_extended_names():
	extended_class_names.clear()
	var inh_scripts = UClassDetail.script_get_inherited_script_paths(get_current_script())
	for path in inh_scripts:
		var script = load(path) as Script
		if not is_instance_valid(script):
			continue
		if script.get_global_name() != "":
			extended_class_names[script.get_global_name()] = true


func _get_script_preloads():
	var current_script = get_current_script()
	var path = current_script.resource_path
	var pre_cache = _misc_cache.get_or_add(&"script_preloads", {})
	var cached = CacheHelper.get_cached_data(path, pre_cache)
	if cached != null:
		return cached
	var preloads = UClassDetail.script_get_preloads(current_script, false, true).keys()
	CacheHelper.store_data(path, preloads, pre_cache, [path])
	return preloads

func append_array_no_dupe(target:Array, from:Array):
	for f in from:
		if not f in target:
			target.append(f)

func _should_hide_member(member:String):
	if not hide_private_members:
		return false
	return member.begins_with("_")

static func get_instance():
	return EditorCodeCompletionSingleton.get_instance().import_code_completion

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
	var script_path:String = ""
	
	var hide_global_classes:bool = false
	var hide_global_exemption:Array = []
	var visible_global_classes:Array = []
	var imported_classes:Dictionary = {}

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
