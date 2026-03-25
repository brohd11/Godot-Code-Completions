extends SingletonRefCount
const SingletonRefCount = Singleton.RefCount
#! remote
#! import-p UString,UClassDetail,

const PE_STRIP_CAST_SCRIPT = preload("res://addons/code_completions/src/class/editor_code_completion_singleton.gd")

const UtilsRemote = preload("res://addons/code_completions/src/class/utils_remote.gd")

const UClassDetail = UtilsRemote.UClassDetail
const USort = UtilsRemote.USort
const UString = UtilsRemote.UString
const CacheHelper = UtilsRemote.CacheHelper

const EditorGDScriptParser = UtilsRemote.EditorGDScriptParser
const CaretContext = EditorGDScriptParser.GDScriptParser.CaretContext

#^ defaults
const EnumCompletion = preload("res://addons/code_completions/src/completions/enum_completion.gd")
const ImportCodeCompletion = preload("res://addons/code_completions/src/completions/import_code_completion.gd")
const TypeAssignmentCompletion = preload("res://addons/code_completions/src/completions/type_assignment.gd")
const HidePrivateCompletion = preload("res://addons/code_completions/src/completions/hide_private.gd")
const TagCompletion = preload("res://addons/code_completions/src/completions/tag_completion.gd")
const ConstKey = preload("res://addons/code_completions/src/completions/const_key.gd")
const ScriptMetadata = preload("res://addons/code_completions/src/completions/script_metadata.gd")

var enum_completion:EnumCompletion
var import_code_completion:ImportCodeCompletion
var type_assignment_completion:TypeAssignmentCompletion
var hide_private_completion:HidePrivateCompletion
var tag_completion:TagCompletion
var const_key_completion:ConstKey
var script_metadata:ScriptMetadata


const TimeFunction = ALibRuntime.Utils.UProfile.TimeFunction #TODO erase

static func get_singleton_name() -> String:
	return "EditorCodeCompletion"

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

var global_script_constant_map = {}
var _global_script_constant_map_data_cache = {}





var peristent_cache:Dictionary = {}
var script_cache:Dictionary = {}

#^ editor settings
var hide_private_members:=false


func _init(_node) -> void:
	_singleton_init()
	_init_set_settings()

func _all_unregistered_callback():
	_free_plugins()

func _ready() -> void:
	await get_tree().create_timer(1).timeout
	_connect_editor()
	
	call_on_ready(_init_plugins)
	_build_global_script_constant_map()
	_editor_gdscript_parser = EditorGDScriptParser.get_instance().get_parser()

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
	enum_completion = EnumCompletion.new()
	import_code_completion = ImportCodeCompletion.new()
	type_assignment_completion = TypeAssignmentCompletion.new()
	hide_private_completion = HidePrivateCompletion.new()
	tag_completion = TagCompletion.new()
	const_key_completion = ConstKey.new()
	script_metadata = ScriptMetadata.new()

func _free_plugins() -> void:
	var plugins = [
		enum_completion,
		import_code_completion,
		type_assignment_completion,
		hide_private_completion,
		tag_completion,
		const_key_completion,
		script_metadata
		]
	for p in plugins:
		if is_instance_valid(p):
			p.clean_up()


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


func _init_set_settings():
	var editor_settings = EditorInterface.get_editor_settings()
	if not editor_settings.has_setting(EditorSet.HIDE_PRIVATE_PROP_SETTING):
		editor_settings.set_setting(EditorSet.HIDE_PRIVATE_PROP_SETTING, false)
	
	#^ these should be checked to see if needed
	#if not editor_settings.has_setting(EditorSet.GLOBAL_CHECK_SETTING):
		#editor_settings.set_setting(EditorSet.GLOBAL_CHECK_SETTING, DataAccessSearch.GlobalCheck.GLOBAL)
	#if not editor_settings.has_setting(EditorSet.SCRIPT_ALIAS_SETTING):
		#editor_settings.set_setting(EditorSet.SCRIPT_ALIAS_SETTING, DataAccessSearch.ScriptAlias.INHERITED)
	
	editor_settings.add_property_info(EditorSet.GLOBAL_CHECK_INFO)
	editor_settings.add_property_info(EditorSet.SCRIPT_ALIAS_INFO)
	
	_set_settings()
	editor_settings.settings_changed.connect(_set_settings)

func _set_settings():
	var editor_settings = EditorInterface.get_editor_settings()
	
	hide_private_members = editor_settings.get_setting(EditorSet.HIDE_PRIVATE_PROP_SETTING)


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
	_build_global_script_constant_map()

func _prep_script(script):
	script_cache.clear()
	script_cache[ScriptCache.STRING_MAPS] = {}
	
	if is_instance_valid(script):
		for editor_code_completion in code_completions.keys():
			editor_code_completion._on_editor_script_changed(script)


func _on_code_completion_requested() -> void:
	var script_editor = get_code_edit()
	_reset_caret_context()
	
	var t = TimeFunction.new("MAIN CONTEXT")
	_caret_context = _editor_gdscript_parser.get_caret_context()
	t.stop()
	for editor_code_completion in code_completions.keys():
		var t2 = TimeFunction.new(str(editor_code_completion.get_script().resource_path.get_file()))
		var handled = editor_code_completion._on_code_completion_requested(script_editor)
		t2.stop()
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

func get_script_member_info_by_path(script:GDScript, member_path:String, member_hints:=UClassDetail._MEMBER_ARGS, check_global:=true):
	return UClassDetail.get_member_info_by_path(script, member_path, member_hints, false, false, false, check_global)


func get_global_script_location(script:GDScript):
	return global_script_constant_map.get(script)

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



#func _build_global_script_constant_map():
	#global_script_constant_map.clear()
	#var global_classes = UClassDetail.get_all_global_class_paths()
	#for _name in global_classes.keys():
		#var global_path = global_classes.get(_name)
		#if global_path.get_extension() == "cs":
			#continue
		#var cached = CacheHelper.get_cached_data(global_path, _global_script_constant_map_data_cache)
		#if cached != null:
			#for script in cached.keys():
				#if not global_script_constant_map.has(script):
					#global_script_constant_map[script] = {}
				#global_script_constant_map[script].merge(cached[script])
			#continue
		#
		#var global_script = load(global_path)
		#var class_hint = _name
		#var temp_cache_dict = {}
		#var preloads = UClassDetail.script_get_preloads(global_script, true, true)
		#for p_member_access in preloads.keys():
			#var script = preloads[p_member_access]
			#if not global_script_constant_map.has(script):
				#global_script_constant_map[script] = {}
			#if not temp_cache_dict.has(script):
				#temp_cache_dict[script] = {}
			#
			#var hint_data = {
				#"global_script": global_script,
				#"member_access": p_member_access
			#}
			#global_script_constant_map[script][class_hint] = hint_data
			#temp_cache_dict[script][class_hint] = hint_data
		#
		#var global_inh_paths = UClassDetail.script_get_inherited_script_paths(global_script)
		#CacheHelper.store_data(global_path, temp_cache_dict, _global_script_constant_map_data_cache, global_inh_paths)


func _build_global_script_constant_map():
	global_script_constant_map.clear()
	var global_classes = UClassDetail.get_all_global_class_paths()
	for _name in global_classes.keys():
		var global_path = global_classes.get(_name)
		if global_path.get_extension() == "cs":
			continue
		var cached = CacheHelper.get_cached_data(global_path, _global_script_constant_map_data_cache)
		if cached != null:
			for script in cached.keys():
				if not global_script_constant_map.has(script):
					global_script_constant_map[script] = {}
				global_script_constant_map[script].merge(cached[script])
			continue
		
		var global_script = load(global_path)
		var class_hint = _name
		var temp_cache_dict = {}
		var preloads = UClassDetail.script_get_preloads(global_script, true, true)
		for p_member_access in preloads.keys():
			var script = preloads[p_member_access]
			if not global_script_constant_map.has(script):
				global_script_constant_map[script] = {}
			if not temp_cache_dict.has(script):
				temp_cache_dict[script] = {}
			
			var hint_data = {
				"global_script": global_script,
				"member_access": p_member_access
			}
			global_script_constant_map[script][class_hint] = hint_data
			temp_cache_dict[script][class_hint] = hint_data
		
		var global_inh_paths = UClassDetail.script_get_inherited_script_paths(global_script)
		CacheHelper.store_data(global_path, temp_cache_dict, _global_script_constant_map_data_cache, global_inh_paths)


static func test():
	var t = ALibRuntime.Utils.UProfile.TimeFunction.new("INNER")
	get_instance()._build_inner_class_map()
	t.stop()
	
	var t2 = ALibRuntime.Utils.UProfile.TimeFunction.new("INNER")
	get_instance()._build_inner_class_mapU()
	t2.stop()
	
	var t23 = ALibRuntime.Utils.UProfile.TimeFunction.new("INNER")
	var manager = InnerClassManager.new()
	manager.build_inner_class_cache()
	manager.queue_free()
	t23.stop()

func _build_inner_class_map():
	var files = UFile.scan_for_files("res://", ["gd"])
	var count = 0
	
	for f in files:
		count += 1
		var script = load(f)
		var parser = _editor_gdscript_parser.get_parser_for_path(f)
		
		
		for inner_class in parser.get_class_object().inner_classes.keys():
			var class_object = parser.get_class_object(inner_class) as EditorGDScriptParser.GDScriptParser.ParserClass
			var inner_script = class_object.get_script_resource()
			inner_script.set_meta(&"outer_path", UString.dot_join(f, class_object.access_path))
	
	print(count, " Files Checked")


func _build_inner_class_mapU():
	var files = UFile.scan_for_files("res://", ["gd"])
	var count = 0
	
	for f in files:
		count += 1
		var script = load(f)
		var inner_classes = UClassDetail.script_get_inner_classes(script)
		
		for inner_path in inner_classes.keys():
			var inner_script = inner_classes[inner_path]
			inner_script.set_meta(&"outer_path", UString.dot_join(f, inner_path))
	
	print(count, " Files Checked")


class EditorSet:
	
	# Custom
	const HIDE_PRIVATE_PROP_SETTING = &"plugin/code_completion/property/hide_private_properties"
	
	const GLOBAL_CHECK_SETTING = &"plugin/code_completion/class_search/check_global_scripts"
	const GLOBAL_CHECK_INFO = {
	"name": GLOBAL_CHECK_SETTING,
	"type": TYPE_INT,
	"hint": PROPERTY_HINT_ENUM,
	"hint_string": "Global,Namespace,Off"
	}
	const SCRIPT_ALIAS_SETTING = &"plugin/code_completion/class_search/script_alias"
	const SCRIPT_ALIAS_INFO = {
	"name": SCRIPT_ALIAS_SETTING,
	"type": TYPE_INT,
	"hint": PROPERTY_HINT_ENUM,
	"hint_string": "Inherited Only,Recursive Preload,Off"
	}
	
	enum GlobalCheck{ # can be removed, but uesing for test duplicated enums
		GLOBAL,
		NAMESPACE,
		OFF
	}
	enum ScriptAlias{ # can be removed, but uesing for test duplicated enums
		INHERITED,
		PRELOADS,
		OFF
	}



class InnerClassManager extends Node:

	const CACHE_PATH = "res://.godot/inner_class_cache.json"

	# In-memory dictionary for instant lookups at runtime
	var _class_map: Dictionary = {}

	func _ready():
		_load_cache()

	# Call this manually when you need to rebuild (e.g., in an EditorPlugin or a dev tool)
	func build_inner_class_cache():
		print("Building Inner Class Cache...")
		var new_map = {}
		var files = _scan_directory("res://", ["gd"])
		
		# Compile Regex ONCE. 
		# (?m) = multiline. ^class\s+ = starts with 'class ' followed by spaces.
		# ([a-zA-Z0-9_]+) = Capture the class name.
		var regex = RegEx.new()
		regex.compile("(?m)^class\\s+([a-zA-Z0-9_]+)")
		
		for file_path in files:
			var script = load(file_path)
			if not script or not script is GDScript:
				continue
				
			var source = script.source_code
			var regex_matches = regex.search_all(source)
			
			# If the file has no "class X:" declarations, skip entirely
			if regex_matches.is_empty():
				continue
				
			# Extract the names of classes actually DEFINED in this file
			var defined_class_names = []
			for rm in regex_matches:
				defined_class_names.append(rm.get_string(1))
				
			# Now map them using the constant map
			var constants = script.get_script_constant_map()
			for const_name in constants:
				var val = constants[const_name]
				
				# Is it a GDScript, has no path, AND was defined in this file?
				if val is GDScript and val.resource_path == "" and const_name in defined_class_names:
					# Store a string representation (you can't save object references to JSON)
					# We use the outer path + "::" + inner name as a unique identifier
					var full_path = file_path + "::" + const_name
					new_map[full_path] = true 

		# Save to disk
		_save_to_disk(new_map)
		_class_map = new_map
		print("Cache built! Found ", new_map.size(), " inner classes.")

	# ---------------------------------------------------------
	# Utilities
	# ---------------------------------------------------------

	func locate_script(inner_script: GDScript) -> String:
		# Because inner classes drop from memory, we can't use them directly as dict keys.
		# But we CAN search our cache for them by checking their outer script properties.
		# Actually, since we want to find WHERE a script is, we have to match it.
		
		# To reverse lookup at runtime:
		# 1. Get the class name (Godot doesn't store this directly, sadly)
		# For ultra-fast lookups, you might still need a tiny loop or enforce class names.
		pass
		return ""

	func _save_to_disk(data: Dictionary):
		var file = FileAccess.open(CACHE_PATH, FileAccess.WRITE)
		if file:
			file.store_string(JSON.stringify(data, "\t"))
			file.close()

	func _load_cache():
		if FileAccess.file_exists(CACHE_PATH):
			var file = FileAccess.open(CACHE_PATH, FileAccess.READ)
			var json = JSON.parse_string(file.get_as_text())
			if typeof(json) == TYPE_DICTIONARY:
				_class_map = json

	func _scan_directory(path: String, extensions: Array) -> Array:
		var files = []
		var dir = DirAccess.open(path)
		if dir:
			dir.list_dir_begin()
			var file_name = dir.get_next()
			while file_name != "":
				if dir.current_is_dir():
					if not file_name.begins_with("."): # Skip hidden dirs like .godot
						files.append_array(_scan_directory(path + file_name + "/", extensions))
				else:
					var ext = file_name.get_extension()
					if ext in extensions:
						files.append(path + file_name)
				file_name = dir.get_next()
		return files
