class_name EditorCodeCompletion

const EditorCodeCompletionSingleton = preload("res://addons/code_completions/src/class/editor_code_completion_singleton.gd")
const UClassDetail = preload("res://addons/addon_lib/brohd/alib_editor/utils/src/u_class_detail.gd")
const UString = preload("res://addons/addon_lib/brohd/alib_runtime/utils/src/u_string.gd")

const TagLocation = EditorCodeCompletionSingleton.TagLocation
const State = EditorCodeCompletionSingleton.State

var singleton:EditorCodeCompletionSingleton

var _tags = {}

var some_tag:TagLocation
var some_var:ConnectFlags



func _init() -> void:
	var settings = _get_completion_settings()
	singleton = EditorCodeCompletionSingleton._register_completion(self, settings)
	EditorCodeCompletionSingleton.call_on_ready(_singleton_ready)
	

func _get_completion_settings() -> Dictionary:
	return {
		"priority": 100,
	}

func _singleton_ready() -> void:
	pass


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

func get_state() -> EditorCodeCompletionSingleton.State:
	return singleton.get_state()


func get_script_var_map() -> Dictionary:
	return singleton.get_script_var_map()

func get_current_class() -> String:
	return singleton.get_current_class()

func get_current_func() -> String:
	return singleton.get_current_func()

func get_enum_members(enum_name:String, _class=null):
	return singleton.gdscript_parser.get_enum_members(enum_name, _class)

func class_has_func(_func:String, _class:String="") -> bool:
	return singleton.class_has_func(_func, _class)

func get_script_body_vars(_class:String="") -> Dictionary:
	return singleton.get_script_body_vars(_class)

func get_script_body_constants(_class:String=""):
	return singleton.get_script_constants(_class)

func get_preload_map():
	return singleton.get_preload_map()

func get_func_args(_class:String, _func_name:String) -> Dictionary:
	return singleton.get_func_args(_class, _func_name)

func caret_in_func_call():
	return singleton.completion_cache.get(singleton.CompletionCache.CARET_IN_FUNC_CALL, false)

func get_func_call_data(infer_type:=false):
	return singleton.get_func_call_data(infer_type)

func get_assignment_at_cursor():
	return singleton.get_assignment_at_cursor()

func is_index_in_comment(column:int=-1, line:int=-1, code_edit=null):
	return singleton.is_index_in_comment(column, line, code_edit)

func is_index_in_string(column:int=-1, line:int=-1, code_edit=null):
	return singleton.is_index_in_string(column, line, code_edit)

func get_word_before_cursor():
	return singleton.get_word_before_cursor()

func add_completion_options(options:Array, hide_private=null):
	var current = get_code_edit()
	singleton.add_code_completion_options(current, options, hide_private)

func get_global_class_path(_class_name:String) -> String:
	return singleton.gdscript_parser.get_global_class_path(_class_name)

func _store_data(section, key, value, script, data_cache:Dictionary):
	singleton._store_data_in_section(section, key, value, script, data_cache)

func _get_cached_data(section, key, data_cache:Dictionary):
	return singleton._get_cached_data_in_section(section, key, data_cache)

func get_string_map(text:String):
	return singleton.get_string_map(text)

func get_script_member_info_by_path(script:GDScript, member_path:String, member_hints:=UClassDetail._MEMBER_ARGS, check_global:=true):
	return UClassDetail.get_member_info_by_path(script, member_path, member_hints, false, false, false, check_global)

func get_hide_private_members_setting():
	return singleton.hide_private_members


func get_current_script():
	return singleton._current_script
func get_code_edit():
	return singleton._current_code_edit
