extends SingletonRefCount
const SingletonRefCount = Singletons.RefCount
#! remote
#! import_p UString,UClassDetail,

const PE_STRIP_CAST_SCRIPT = preload("res://addons/code_completions/src/class/editor_code_completion_singleton.gd")

const UtilsRemote = preload("res://addons/code_completions/src/class/utils_remote.gd")

const UClassDetail = UtilsRemote.UClassDetail
const USort = UtilsRemote.USort
const UString = UtilsRemote.UString
const CacheHelper = UtilsRemote.CacheHelper

const EditorGDScriptParser = UtilsRemote.EditorGDScriptParser
const CaretContext = EditorGDScriptParser.GDScriptParser.CaretContext
const SettingHelperEditor = UtilsRemote.SettingHelperEditor

#^ defaults
const EnumCompletion = preload("res://addons/code_completions/src/completions/enum_completion.gd")
const ImportCodeCompletion = preload("res://addons/code_completions/src/completions/import_code_completion.gd")
const TypeAssignmentCompletion = preload("res://addons/code_completions/src/completions/type_assignment.gd")
const HidePrivateCompletion = preload("res://addons/code_completions/src/completions/hide_private.gd")
const TagCompletion = preload("res://addons/code_completions/src/completions/tag_completion.gd")
const ConstKey = preload("res://addons/code_completions/src/completions/const_key.gd")
const ArgLocation = preload("res://addons/code_completions/src/completions/arg_location.gd")
const DictKey = preload("res://addons/code_completions/src/completions/dict_key.gd")
const ThemeCompletion = preload("res://addons/code_completions/src/completions/themes.gd")
const EditorThemeCompletion = preload("res://addons/code_completions/src/completions/editor_theme.gd")

var enum_completion:EnumCompletion
var import_code_completion:ImportCodeCompletion
var type_assignment_completion:TypeAssignmentCompletion
var hide_private_completion:HidePrivateCompletion
var tag_completion:TagCompletion
var const_key_completion:ConstKey
var arg_location:ArgLocation
var dict_key:DictKey
var theme_completion:ThemeCompletion
var editor_theme_completion:EditorThemeCompletion


const TF = preload("uid://ft7o6vspsurv") #! resolve ALibRuntime.Utils.UProfile.TimeFunction #TODO erase

static func get_singleton_name() -> String:
	return "EditorCodeCompletionSingleton"

static func get_instance() -> PE_STRIP_CAST_SCRIPT:
	return _get_instance(PE_STRIP_CAST_SCRIPT)

static func register_node(node):
	var instance = _register_node(PE_STRIP_CAST_SCRIPT, node)
	instance._register_singletons(node)
	return instance

static func unregister_node(node):
	var instance = get_instance()
	instance._unregister_singletons(node)
	_unregister_node(PE_STRIP_CAST_SCRIPT, node)
	#instance.unregister_node(plugin)

static func register_completion(completion, settings:Dictionary):
	var instance = get_instance()
	instance.code_completions[completion] = settings
	instance.code_completion_added()
	return instance

func unregister_completion(completion):
	code_completions.erase(completion)


static func instance_valid():
	return _instance_valid(PE_STRIP_CAST_SCRIPT)

static func call_on_ready(callable:Callable, printerr:=false) -> void:
	_call_on_ready(PE_STRIP_CAST_SCRIPT, callable, printerr)


enum TagLocation {
	START,
	END,
	ANY,
}

enum PersistentCache {
	TAGS,
	GLOBAL_ACCESS_PATHS,
}

enum ScriptCache {
	STRING_MAPS,
	#SCRIPT_PRELOADS,
}

var code_completions:Dictionary = {}
var _sort_queued:= false

var _editor_gdscript_parser:EditorGDScriptParser.GDScriptParser
var _caret_context:CaretContext

#var global_script_constant_map = {}
#var _global_script_constant_map_data_cache = {}

var setting_helper:SettingHelperEditor

var peristent_cache:Dictionary = {}
var script_cache:Dictionary = {}


func _init(_node) -> void:
	_singleton_init()

func _all_unregistered_callback():
	_free_plugins()

func _ready() -> void:
	await get_tree().create_timer(1).timeout
	_connect_editor()
	
	call_on_ready(_init_plugins)
	_editor_gdscript_parser = EditorGDScriptParser.get_parser()

func _singleton_init():
	_clear_cache()

# these should be simplified now, dont think it needs to be complex
func _register_singletons(plugin:EditorPlugin):
	SyntaxPlusSingleton.register_node(plugin)
	EditorGDScriptParser.register_node(plugin)

func _unregister_singletons(plugin:EditorPlugin):
	SyntaxPlusSingleton.unregister_node(plugin)
	EditorGDScriptParser.unregister_node(plugin)


func _init_plugins() -> void:
	hide_private_completion = HidePrivateCompletion.new()
	enum_completion = EnumCompletion.new()
	import_code_completion = ImportCodeCompletion.new()
	type_assignment_completion = TypeAssignmentCompletion.new()
	tag_completion = TagCompletion.new()
	const_key_completion = ConstKey.new()
	arg_location = ArgLocation.new()
	dict_key = DictKey.new()
	theme_completion = ThemeCompletion.new()
	editor_theme_completion = EditorThemeCompletion.new()
	
	setting_helper = SettingHelperEditor.new()
	var plugins = _get_plugins()
	for p in plugins:
		p.register_editor_settings(setting_helper)
	
	setting_helper.initialize()

func _free_plugins() -> void:
	var plugins = _get_plugins()
	for p in plugins:
		if is_instance_valid(p):
			p.clean_up()

func _get_plugins() -> Array[EditorCodeCompletion]:
	return [
		hide_private_completion,
		enum_completion,
		import_code_completion,
		type_assignment_completion,
		tag_completion,
		const_key_completion,
		arg_location,
		dict_key,
		theme_completion,
		editor_theme_completion,
		]

func register_tag(prefix:String, tag:String, location:TagLocation=TagLocation.ANY):
	if not peristent_cache[PersistentCache.TAGS].has(prefix):
		peristent_cache[PersistentCache.TAGS][prefix] = {}
	
	if not peristent_cache[PersistentCache.TAGS][prefix].has(tag):
		peristent_cache[PersistentCache.TAGS][prefix][tag] = location
	else:
		print("Tag already registered: %s %s" % [prefix, tag])

func unregister_tag(prefix:String, tag:String):
	if not peristent_cache[PersistentCache.TAGS].has(prefix):
		peristent_cache[PersistentCache.TAGS][prefix] = {}
	
	if peristent_cache[PersistentCache.TAGS][prefix].has(tag):
		peristent_cache[PersistentCache.TAGS][prefix].erase(tag)
	else:
		print("Tag not present: %s %s" % [prefix, tag])

func clear_cache():
	_clear_cache()
	if is_inside_tree():
		sort_completions()

func _clear_cache():
	peristent_cache.clear()
	script_cache.clear()
	
	peristent_cache[PersistentCache.TAGS] = {}
	script_cache[ScriptCache.STRING_MAPS] = {}



func code_completion_added():
	sort_completions()

func sort_completions():
	if _sort_queued:
		return
	_sort_queued = true
	await get_tree().process_frame
	
	var key_priority_dict = {}
	for editor_code_completion in code_completions.keys():
		var settings = code_completions.get(editor_code_completion, {})
		var priority = settings.get("priority", 100)
		key_priority_dict[editor_code_completion] = priority
	
	var sorted_dict = USort.sort_priority_dict(key_priority_dict)
	var new_dict = {}
	for editor_code_completion in sorted_dict:
		new_dict[editor_code_completion] = code_completions[editor_code_completion]
	
	code_completions = new_dict
	_sort_queued = false


func _connect_editor():
	ScriptEditorRef.subscribe(ScriptEditorRef.Event.CODE_COMPLETION_REQUESTED, _on_code_completion_requested)
	ScriptEditorRef.subscribe(ScriptEditorRef.Event.EDITOR_SCRIPT_CHANGED, _on_editor_script_changed)
	
	EditorInterface.get_resource_filesystem().filesystem_changed.connect(_on_file_system_changed)

func _disconnect_editor():
	EditorInterface.get_resource_filesystem().filesystem_changed.disconnect(_on_file_system_changed)


func _on_editor_script_changed(script):
	_prep_script(script)

func _on_file_system_changed():
	var current_script = get_current_script()
	_prep_script(current_script)

func _prep_script(script):
	script_cache.clear()
	script_cache[ScriptCache.STRING_MAPS] = {}
	
	if is_instance_valid(script):
		for editor_code_completion in code_completions.keys():
			editor_code_completion._on_editor_script_changed(script)


func _on_code_completion_requested() -> void:
	var script_editor = get_code_edit()
	_reset_caret_context()
	
	var t = TF.new("MAIN CONTEXT")
	_caret_context = _editor_gdscript_parser.get_caret_context()
	#t.stop()
	for editor_code_completion in code_completions.keys():
		var t2 = TF.new(str(editor_code_completion.get_script().resource_path.get_file()))
		var handled = editor_code_completion._on_code_completion_requested(script_editor)
		#t2.stop()
		if handled:
			_reset_caret_context()
			return
	
	_reset_caret_context()



func _reset_caret_context():
	_caret_context = null
	_editor_gdscript_parser.reset_caret_context()

#region API

func get_current_script():
	return ScriptEditorRef.get_current_script()

func get_code_edit() -> CodeEdit:
	return ScriptEditorRef.get_current_code_edit()

func get_caret_context():
	return _caret_context


func get_string_map(text:String, mode:UString.StringMap.Mode=UString.StringMap.Mode.FULL, print_err:=false) -> UString.StringMap:
	if script_cache[ScriptCache.STRING_MAPS].has(text):
		return script_cache[ScriptCache.STRING_MAPS].get(text)
	var string_map = UString.get_string_map(text, mode, print_err)
	script_cache[ScriptCache.STRING_MAPS][text] = string_map
	return string_map

#endregion



#^ cache
func _store_data_in_section(section, key, value, script, data_cache:Dictionary):
	if not data_cache.has(section):
		data_cache[section] = {}
	var section_data = data_cache.get(section)
	
	if script is String:
		script = load(script)
	var inh_scripts = UClassDetail.script_get_inherited_script_paths(script)
	CacheHelper.store_data(key, value, section_data, inh_scripts)

func _get_cached_data_in_section(section, key, data_cache:Dictionary):
	if not data_cache.has(section):
		return null
	var section_data = data_cache.get(section)
	
	return CacheHelper.get_cached_data(key, section_data)
