class_name EditorCodeCompletion

const EditorCodeCompletionSingleton = preload("res://addons/code_completions/src/class/editor_code_completion_singleton.gd")
const UClassDetail = preload("res://addons/addon_lib/brohd/alib_editor/utils/src/u_class_detail.gd")
const UString = preload("res://addons/addon_lib/brohd/alib_runtime/utils/src/u_string.gd")

const TagLocation = EditorCodeCompletionSingleton.TagLocation
const DataAccessSearch = EditorCodeCompletionSingleton.DataAccessSearch
const State = EditorCodeCompletionSingleton.State

var singleton:EditorCodeCompletionSingleton

var _tags = {}

var some_tag:TagLocation



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

func get_script_body_vars(_class:String="") -> Dictionary:
	return singleton.get_script_body_vars(_class)

func get_script_body_constants(_class:String=""):
	return singleton.get_script_constants(_class)

func get_func_args(_class:String, _func_name:String) -> Dictionary:
	return singleton.get_func_args(_class, _func_name)



func get_first_var_name(var_name:String):
	var dot_idx:= var_name.find(".")
	if dot_idx > -1:
		var_name = var_name.substr(0, dot_idx)
	return var_name

func convert_property_to_type(var_name:String):
	return singleton.map_get_var_type(var_name)


func caret_in_func_call(): # TODO can be eliminated? use state instead, the are not mutually exclusive though...
	return singleton.completion_cache.get(singleton.CompletionCache.CARET_IN_FUNC_CALL, false)

func get_func_call_data():
	return singleton.get_func_call_data()

func get_func_name_of_line(line:int):
	return singleton.get_func_name_of_line(get_code_edit(), line)


func get_assignment_at_cursor():
	return singleton.get_assignment_at_cursor()

func property_info_to_type(property_info):
	return singleton.property_info_to_type(property_info)

func get_string_map(text:String):
	return singleton.get_string_map(text)

func is_index_in_comment(column:int=-1, line:int=-1, code_edit=null):
	return singleton.is_index_in_comment(column, line, code_edit)

func is_index_in_string(column:int=-1, line:int=-1, code_edit=null):
	return singleton.is_index_in_string(column, line, code_edit)

func get_word_before_cursor():
	return singleton.get_word_before_cursor()

func add_completion_options(options:Array, hide_private=null):
	var current = get_code_edit()
	singleton.add_code_completion_options(current, options, hide_private)

func _store_data(section, key, value, script, data_cache:Dictionary):
	singleton._store_data_in_section(section, key, value, script, data_cache)

func _get_cached_data(section, key, data_cache:Dictionary):
	return singleton._get_cached_data_in_section(section, key, data_cache)

func get_member_path_by_value(data, deep:=false, member_hints:=UClassDetail._MEMBER_ARGS, breadth_first:=true):
	var member_path = UClassDetail.script_get_member_by_value(get_current_script(), data, deep, member_hints, breadth_first)
	if member_path != null:
		return member_path
	print("HADD TO DO BIG SEARCH")
	return singleton.get_access_path(data, member_hints, "")

func get_access_path(data, member_hints:=UClassDetail._MEMBER_ARGS, class_hint:=""):
	return singleton.get_access_path(data, member_hints)

func get_script_alias(access_path:String, data=null):
	return singleton.get_script_alias(access_path, data)


func get_current_script():
	return singleton._current_script
func get_code_edit():
	return singleton._current_code_edit
