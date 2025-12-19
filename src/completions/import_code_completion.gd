extends EditorCodeCompletion

#! import-show-global 
#! import-g SyntaxPlus,
#! import-p UClassDetail,UString,

#^ import hints
const _IMPORT_SHOW_GLOBAL = "import-show-global"
const _IMPORT_SHOW_GLOBAL_ALL = "import-show-global-all"
const _IMPORT_PRELOADS = "import-preloads"
const _IMPORT_P = "import-p"
const _IMPORT_G = "import-g"

#^ keys
const IMPORT_MEMBERS_CURRENT = &"import_members_current"
const IMPORT_MEMBERS = &"import_members"
const IMPORTED_CLASSES = &"imported_classes"
const OPTIONS_TO_SKIP = &"options_to_skip"

#^ completion cache
const COMP_CHECKED_SCRIPTS = &"checked_scripts"
const HINT_SEARCH_SCOPE = 10
const CALL_WITH_ARGS = "(\u2026)"

#^ editor settings
var hide_global_classes_setting:= false
var hide_global_exemptions:Array = []


var data_cache:Dictionary = {}

var extended_class_names:Dictionary = {} #^ [name, bool] a set

var global_classes:Dictionary = {} #^ [name, path]
var global_paths:Dictionary = {} #^ [path, name]
var preload_paths:Dictionary = {} #^ [path, bool] a set

var imported_classes:Dictionary = {} #^ [name, script]
var imported_class_scripts:Dictionary = {} #^ [script, name]
var show_global_classes:Dictionary = {} #^ [name, script]
var hide_global_classes = false
var hide_private_members = false

var completion_cache:Dictionary = {}

const _COMMENT_TAGS = {
	"#!": {
		_IMPORT_PRELOADS:null,
		_IMPORT_SHOW_GLOBAL:"_import_syntax_hl",
		_IMPORT_SHOW_GLOBAL_ALL:"_import_syntax_hl",
		_IMPORT_P:"_import_syntax_hl",
		_IMPORT_G:"_import_syntax_hl",
	}
}


func _singleton_ready():
	_init_set_settings()
	
	for prefix in _COMMENT_TAGS.keys():
		var tag_data = _COMMENT_TAGS.get(prefix)
		for tag in tag_data.keys():
			var callable_nm = tag_data.get(tag)
			if callable_nm == null:
				SyntaxPlus.register_comment_tag(prefix, tag)
			else:
				var callable = get(callable_nm)
				SyntaxPlus.register_highlight_callable(prefix, tag, callable, SyntaxPlus.CallableLocation.START)
			register_tag(prefix, tag, TagLocation.START)


func _init_set_settings():
	var editor_settings = EditorInterface.get_editor_settings()
	if not editor_settings.has_setting(Settings.HIDE_GLOBAL_SETTING):
		editor_settings.set_setting(Settings.HIDE_GLOBAL_SETTING, false)
	if not editor_settings.has_setting(Settings.HIDE_GLOBAL_EXEMP_SETTING):
		editor_settings.set_setting(Settings.HIDE_GLOBAL_EXEMP_SETTING, [])
	if not editor_settings.has_setting(Settings.HIDE_PRIVATE_PROP_SETTINGS):
		editor_settings.set_setting(Settings.HIDE_PRIVATE_PROP_SETTINGS, false)
	
	var hide_global_exemp = Settings.HIDE_GLOBAL_EXEMP_INFO.duplicate()
	hide_global_exemp["hint_string"] = "%d:" % [TYPE_STRING]
	editor_settings.add_property_info(hide_global_exemp)
	
	_set_settings()
	editor_settings.settings_changed.connect(_set_settings)

func _set_settings():
	var editor_settings = EditorInterface.get_editor_settings()
	hide_global_classes_setting = editor_settings.get_setting(Settings.HIDE_GLOBAL_SETTING)
	hide_global_exemptions = editor_settings.get_setting(Settings.HIDE_GLOBAL_EXEMP_SETTING)
	hide_private_members = editor_settings.get_setting(Settings.HIDE_PRIVATE_PROP_SETTINGS)
	
	_on_editor_script_changed(null)


func _on_editor_script_changed(script):
	editor_theme = EditorInterface.get_editor_theme()
	_get_script_imports.call_deferred()
	_get_global_and_preloads.call_deferred()


func _on_code_completion_requested(script_editor:CodeEdit) -> bool:
	data_cache.clear() #^ caching seems ok, but can get stale
	#^g test area ^^
	
	completion_cache.clear()
	completion_cache[COMP_CHECKED_SCRIPTS] = {}
	
	var current_script = get_current_script()
	if current_script == null:
		return false
	
	var current_state = get_state()
	if current_state == State.COMMENT:
		var caret_line = script_editor.get_caret_line()
		var current_line_text = script_editor.get_line(caret_line)
		var import_hint_options = _import_hint_autocomplete(current_line_text)
		if not import_hint_options.is_empty():
			for o in import_hint_options:
				add_completion_option(script_editor, o)
			update_completion_options()
			return true
		return false
	elif current_state == State.STRING:
		return false
	elif current_state == State.MEMBER_ACCESS:
		return false
	elif current_state == State.ANNOTATION:
		return false
	elif is_caret_in_enum():
		return false
	
	var word_before_cursor = get_word_before_caret()
	var existing_options = script_editor.get_code_completion_options()
	var existing_size = existing_options.size()
	if existing_size == 0: #^ early returns
		if caret_in_func_declaration():
			return false
		if _SKIP_KEYWORDS.has(word_before_cursor):
			return false
		var line = script_editor.get_line(script_editor.get_caret_line())#.strip_edges()
		var stripped = line.strip_edges()
		for word in _SKIP_DECLARTIONS:
			if stripped.begins_with(word):
				return false
		var char_before_cursor = get_char_before_caret()
		if _SKIP_CHARS.has(char_before_cursor):
			return false
	elif existing_size < 10:
		var is_enum = true
		for o in existing_options:
			if o.kind != CodeEdit.CodeCompletionKind.KIND_ENUM:
				is_enum = false
				break
		if is_enum:
			return false
	
	
	var options = []
	var options_dict:Dictionary = {}
	var cache_cc_options = _get_cached_data(IMPORT_MEMBERS_CURRENT, current_script.resource_path, data_cache)
	if cache_cc_options == null:
		cache_cc_options = _get_code_complete_options()
		_store_data(IMPORT_MEMBERS_CURRENT, current_script.resource_path, cache_cc_options, current_script, data_cache)
	
	
	var cc_options = cache_cc_options.duplicate(true) #^ duplicate so cache retains options to skip
	var options_to_skip = cc_options.get(OPTIONS_TO_SKIP, {})
	cc_options.erase(OPTIONS_TO_SKIP)
	
	for o in cc_options.values():
		add_completion_option(script_editor, o)
	
	for e in existing_options:
		var display = e.display_text
		if options_to_skip.has(display):
			continue
		if hide_global_classes:
			if global_classes.has(display) and not show_global_classes.has(display):
				continue
		add_completion_option(script_editor, e)
	
	update_completion_options()
	return true


func _get_code_complete_options():
	var cc_options = {}
	var options_to_skip = {}
	
	var current_script = EditorInterface.get_script_editor().get_current_script() #^r need this to get enum members
	if current_script == null:
		return cc_options
	var current_script_members = _get_script_member_code_complete_options(current_script, "", options_to_skip)
	for name in current_script_members.keys():
		options_to_skip[name] = true
	cc_options.merge(current_script_members)
	
	for access_path in imported_classes.keys():
		var script = imported_classes.get(access_path)
		var members = _get_script_member_code_complete_options(script, access_path, options_to_skip, ["const", "enum", "method"])
		cc_options.merge(members)
	
	cc_options[OPTIONS_TO_SKIP] = options_to_skip
	return cc_options


func _get_script_member_code_complete_options(script:GDScript, access_name:String, 
				options_to_skip:Dictionary, member_hints:=UClassDetail._MEMBER_ARGS):
	
	if imported_class_scripts.has(script) and access_name.find(".") > -1:
		return {}
	if completion_cache[COMP_CHECKED_SCRIPTS].has(script):
		return {}
	completion_cache[COMP_CHECKED_SCRIPTS][script] = true
	
	var cache_key = script.resource_path if script.resource_path != "" else script
	var cc_options = _get_cached_data(IMPORT_MEMBERS, cache_key, data_cache)
	if cc_options == null:
		cc_options = {}
		cc_options[access_name] = get_code_complete_dict(CodeEdit.CodeCompletionKind.KIND_CLASS,access_name, access_name, "Object")
		options_to_skip[access_name] = true
		
		for hint in member_hints:
			var options:Dictionary
			if hint == "enum":
				options = _get_enum_options(script, access_name)
			elif hint ==  "const":
				options = _get_const_options(script, access_name)
			elif hint == "property":
				options = _get_property_options(script, access_name)
			elif hint == "signal":
				options = _get_signal_options(script, access_name)
			elif hint == "method":
				options = _get_method_options(script, access_name, true)
			
			if options != null:
				if options.has(OPTIONS_TO_SKIP):
					options_to_skip.merge(options[OPTIONS_TO_SKIP])
					options.erase(OPTIONS_TO_SKIP)
				cc_options.merge(options)
		
		_store_data(IMPORT_MEMBERS, cache_key, cc_options, script, data_cache)
	
	return cc_options


func _get_property_options(script:GDScript, access_name:String):
	var properties = UClassDetail.script_get_all_properties(script)#, true)
	var cc_options = {}
	for p in properties:
		if p.ends_with(".gd"):
			continue
		if hide_private_members and p.begins_with("_"):
			continue
		var data = properties.get(p)
		var cc_nm = access_name + "." + p if access_name != "" else p
		cc_options[cc_nm] = get_code_complete_dict(CodeEdit.CodeCompletionKind.KIND_MEMBER,cc_nm,cc_nm,"property")
	return cc_options
	

func _get_const_options(script:GDScript, access_name:String):
	
	var options_to_skip = {}
	var constants = UClassDetail.script_get_all_constants(script, UClassDetail.IncludeInheritance.SCRIPTS_ONLY)
	var cc_options = {}
	for c in constants:
		if hide_private_members and c.begins_with("_"):
			continue
		var icon = "const"
		var val = constants.get(c)
		if val is GDScript:
			if imported_class_scripts.has(val):
				continue
			if preload_paths.has(val.resource_path):
				continue
			icon = "Object"
		
		var cc_nm = access_name + "." + c if access_name != "" else c
		cc_options[cc_nm] = get_code_complete_dict(CodeEdit.CodeCompletionKind.KIND_CONSTANT,cc_nm,cc_nm,icon)
		
		if val is GDScript:
			if imported_class_scripts.has(val) or completion_cache[COMP_CHECKED_SCRIPTS].has(val):
				continue
			var nested_methods = _get_class_new_method(val, cc_nm)
			cc_options.merge(nested_methods)
		
		#if val is GDScript:# and val.resource_path == "": #^r deep logic
			#var nested_options = _get_script_member_code_complete_options(val, cc_nm, options_to_skip, ["const", "method", "enum"])
			#if nested_options.has(OPTIONS_TO_SKIP):
				#options_to_skip.merge(nested_options[OPTIONS_TO_SKIP])
				#nested_options.erase(OPTIONS_TO_SKIP)
			#cc_options.merge(nested_options)
	
	cc_options[OPTIONS_TO_SKIP] = options_to_skip
	return cc_options


func _get_method_options(script:GDScript, access_name:String, include_new:bool=false):
	var methods = UClassDetail.script_get_all_methods(script, UClassDetail.IncludeInheritance.SCRIPTS_ONLY)
	var cc_options = {}
	
	if include_new:
		var new_options = _get_class_new_method(script, access_name, methods)
		cc_options.merge(new_options)
	
	for m in methods:
		var data = methods.get(m)
		var name = data.get("name")
		if hide_private_members and m.begins_with("_"):
			continue
		else:
			if name == "_init":
				continue
		
		var flags = data.get("flags")
		if not (flags & METHOD_FLAG_STATIC):
			continue
		var args = data.get("args")
		var cc_nm = access_name + "." + m if access_name != "" else m
		var cc_ins = cc_nm + "("
		if args.is_empty():
			cc_nm = cc_nm + "()"
			cc_ins = cc_nm
		else:
			cc_nm = cc_nm + CALL_WITH_ARGS
		cc_options[cc_nm] = get_code_complete_dict(CodeEdit.CodeCompletionKind.KIND_FUNCTION,cc_nm,cc_ins,"method")
	
	return cc_options

func _get_class_new_method(script:GDScript, access_name:String, methods=null):
	if access_name == "": #^ if the main script, don't want
		return {}
	if methods == null:
		methods = UClassDetail.script_get_all_methods(script, UClassDetail.IncludeInheritance.SCRIPTS_ONLY)
	var cc_options = {}
	var init_method_data = methods.get("_init")
	var has_args = false
	if init_method_data != null:
		var init_args = init_method_data.get("args", [])
		if not init_args.is_empty():
			has_args = true
	
	var new_call = access_name + ".new()"
	var new_call_ins = new_call
	if has_args:
		new_call = access_name + ".new" + CALL_WITH_ARGS
		new_call_ins = access_name + ".new("
	cc_options[new_call] = get_code_complete_dict(CodeEdit.CodeCompletionKind.KIND_FUNCTION,new_call,new_call_ins,"constructor")
	return cc_options

func _get_signal_options(script:GDScript, access_name:String):
	var signals = UClassDetail.script_get_all_signals(script)
	var cc_options = {}
	for s in signals:
		if hide_private_members and s.begins_with("_"):
			continue
		var cc_nm = access_name + "." + s if access_name != "" else s
		cc_options[cc_nm] = get_code_complete_dict(CodeEdit.CodeCompletionKind.KIND_SIGNAL,cc_nm,cc_nm,"signal")
	return cc_options

func _get_enum_options(script:GDScript, access_name:String):
	var enums = UClassDetail.script_get_all_enums(script)#, true)
	var cc_options = {}
	for e in enums:
		if hide_private_members and e.begins_with("_"):
			continue
		var cc_nm = access_name + "." + e if access_name != "" else e
		cc_options[cc_nm] = get_code_complete_dict(CodeEdit.CodeCompletionKind.KIND_ENUM,cc_nm,cc_nm,"enum")
		
		var enum_members = get_enum_members(e) #^ check if in current script, if so parse directly
		if enum_members == null:
			enum_members = enums.get(e)
		for em in enum_members.keys():
			var em_nm = cc_nm + "." + em
			cc_options[em_nm] = get_code_complete_dict(CodeEdit.CodeCompletionKind.KIND_ENUM,em_nm,em_nm,"enum")
	
	return cc_options


func _get_script_imports():
	var script_editor = get_code_edit()
	if script_editor == null:
		return []
	var import_hints = {
		_IMPORT_SHOW_GLOBAL_ALL: false,
		_IMPORT_PRELOADS: false,
		_IMPORT_SHOW_GLOBAL: {},
		_IMPORT_P: {},
		_IMPORT_G: {},
	}
	var line_count = script_editor.get_line_count()
	for i in range(HINT_SEARCH_SCOPE):
		if not i < line_count:
			break
		var line = script_editor.get_line(i)
		if not line.begins_with("#! import"):
			continue
		var hint = line.get_slice("#!", 1).strip_edges().get_slice(" ", 0).strip_edges()
		if hint == _IMPORT_SHOW_GLOBAL_ALL:
			import_hints[_IMPORT_SHOW_GLOBAL_ALL] = true
		elif hint == _IMPORT_PRELOADS:
			import_hints[_IMPORT_PRELOADS] = true
	
	var hints = [_IMPORT_SHOW_GLOBAL, _IMPORT_G, _IMPORT_P]
	for hint in hints:
		var current = _get_current_classes_of_hint(hint, script_editor)
		for class_nm in current:
			import_hints[hint][class_nm] = true
	
	if not hide_global_classes_setting:
		import_hints[_IMPORT_SHOW_GLOBAL_ALL] = true
	
	imported_classes.clear()
	imported_class_scripts.clear()
	show_global_classes.clear()
	
	var deep = false
	var include_inner = true
	var current_script = get_current_script()
	var preloads = UClassDetail.script_get_preloads(current_script, deep, include_inner)
	if import_hints[_IMPORT_PRELOADS] == true:
		for _class in preloads.keys():
			var pl_script = preloads[_class]
			imported_classes[_class] = pl_script
	else:
		for _class in import_hints[_IMPORT_P].keys():
			var pl_script = preloads.get(_class)
			if pl_script != null:
				imported_classes[_class] = pl_script
	
	for _class in import_hints[_IMPORT_G].keys():
		if extended_class_names.has(_class):
			continue
		var path = UClassDetail.get_global_class_path(_class)
		if path != "":
			var g_script = load(path)
			imported_classes[_class] = g_script
			show_global_classes[_class] = g_script #^ add to show if imported
	
	if import_hints[_IMPORT_SHOW_GLOBAL_ALL] == true:
		hide_global_classes = false
	else:
		hide_global_classes = true
		for _class in hide_global_exemptions:
			var path = UClassDetail.get_global_class_path(_class)
			if path == "":
				printerr("Hide global class editor setting class not found: ", _class)
			else:
				var g_script = load(path)
				show_global_classes[_class] = g_script
		
		for _class in import_hints[_IMPORT_SHOW_GLOBAL].keys():
			var path = UClassDetail.get_global_class_path(_class)
			if path != "":
				var g_script = load(path)
				show_global_classes[_class] = g_script
	
	for nm in imported_classes.keys():
		imported_class_scripts[imported_classes[nm]] = nm
	
	var import_data = {
		"hide_global_classes_setting": hide_global_classes,
		"show_global_classes": show_global_classes,
		"imported_classes":imported_classes,
		"global_classes":global_classes,
	}
	set_data("import_data", import_data)


func _get_global_and_preloads():
	global_paths.clear()
	global_classes = UClassDetail.get_all_global_class_paths()
	for nm in global_classes:
		global_paths[global_classes[nm]] = nm
	
	preload_paths.clear()
	var preloads = UClassDetail.script_get_preloads(get_current_script())
	for _name in preloads:
		var script = preloads.get(_name)
		if script.resource_path != "":
			preload_paths[script.resource_path] = true
	
	extended_class_names.clear()
	var inh_scripts = UClassDetail.script_get_inherited_script_paths(get_current_script())
	for path in inh_scripts:
		if global_paths.has(path):
			extended_class_names[global_paths[path]] = true


func _import_syntax_hl(script_editor:CodeEdit, current_line_text:String, line:int, comment_tag_idx:int):
	var hl_info = {}
	var default_tag_color = SyntaxPlus.get_instance().DEFAULT_TAG_COLOR
	var comment_color = SyntaxPlus.get_instance().comment_color
	
	var current_line_length = current_line_text.length()
	var substr = current_line_text.substr(comment_tag_idx + 2).strip_edges()
	var hint = substr.get_slice(" ", 0).strip_edges()
	
	var show_global_hint = hint == _IMPORT_SHOW_GLOBAL
	var show_global_all_hint = hint == _IMPORT_SHOW_GLOBAL_ALL
	if not hide_global_classes_setting and (show_global_hint or show_global_all_hint):
		hl_info[0] = SyntaxPlus.get_hl_info_dict(Color.FIREBRICK)
		hl_info[hint.length() + 1] = SyntaxPlus.get_hl_info_dict(comment_color)
		return hl_info
	elif hide_global_classes_setting and show_global_all_hint:
		hl_info[0] = SyntaxPlus.get_hl_info_dict(default_tag_color)
		hl_info[hint.length() + 1] = SyntaxPlus.get_hl_info_dict(comment_color)
		return hl_info
	
	var global_hint = hint == _IMPORT_G
	var preload_hint = hint == _IMPORT_P
	if not (global_hint or preload_hint or show_global_hint):
		return hl_info #^ empty
	
	var global_class_color = SyntaxPlus.get_instance().user_type_color
	var preload_class_color = SyntaxPlus.get_instance().global_function_color
	
	var symbol_color = SyntaxPlus.get_instance().symbol_color
	
	var current_classes = _get_current_classes_of_hint(hint, script_editor)
	hl_info[0] = SyntaxPlus.get_hl_info_dict(default_tag_color)
	hl_info[hint.length() + 1] = SyntaxPlus.get_hl_info_dict(comment_color)
	
	var in_scope_class_names:Array
	var class_color:Color
	if global_hint or show_global_hint:
		var global_classes = UClassDetail.get_all_global_class_paths()
		in_scope_class_names = global_classes.keys()
		class_color = global_class_color
	elif preload_hint:
		var current_script = get_current_script()
		var preloads = UClassDetail.script_get_preloads(current_script, true)
		in_scope_class_names = preloads.keys()
		class_color = preload_class_color
	
	for _class_name in current_classes:
		if _class_name in in_scope_class_names:
			var hl_color = class_color
			if extended_class_names.has(_class_name) and not show_global_hint: #^ show global hint to allow showing self
				hl_color = Color.FIREBRICK
			var idx = UString.find_indentifier_in_line(substr, _class_name)
			if idx == -1:
				continue
			
			hl_info[idx] = SyntaxPlus.get_hl_info_dict(hl_color)
			var comma_idx = substr.find(",", idx)
			if comma_idx != -1:
				hl_info[comma_idx] = SyntaxPlus.get_hl_info_dict(symbol_color)
				hl_info[comma_idx + 1] = SyntaxPlus.get_hl_info_dict(comment_color)
	
	return hl_info


func _get_current_classes_of_hint(hint:String, script_editor:CodeEdit):
	var classes_array = []
	var line_count = script_editor.get_line_count()
	for i in range(HINT_SEARCH_SCOPE):
		if not i < line_count:
			break
		var line = script_editor.get_line(i)
		if not line.begins_with("#!"):
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
		var preloads = UClassDetail.script_get_preloads(current_script, true)
		for _name in preloads.keys():
			if _name.find(".") > -1:
				continue
			if _name in current_classes:
				continue
			var completion = get_code_complete_dict(CodeEdit.CodeCompletionKind.KIND_CLASS, _name, _name + ",", "Object")
			options.append(completion)
	
	return options


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

const _SKIP_DECLARTIONS = [
	"static ",
	"func ",
	"const",
	"var ",
	"enum",
	"class ",
	"class_name ",
]

class Settings:
	const HIDE_GLOBAL_SETTING = &"plugin/code_completion/import/hide_global_classes"
	const HIDE_PRIVATE_PROP_SETTINGS = EditorCodeCompletion.EditorCodeCompletionSingleton.EditorSet.HIDE_PRIVATE_PROP_SETTING
	
	const HIDE_GLOBAL_EXEMP_SETTING = &"plugin/code_completion/import/hide_global_exemptions"
	const HIDE_GLOBAL_EXEMP_INFO = {
	"name": HIDE_GLOBAL_EXEMP_SETTING,
	"type": TYPE_ARRAY,
	"hint": PROPERTY_HINT_TYPE_STRING,
	"hint_string": "%d:%d"
	}
