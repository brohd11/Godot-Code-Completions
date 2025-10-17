class_name EditorCodeCompletion

const EditorCodeCompletionSingleton = preload("res://addons/code_completions/src/class/editor_code_completion_singleton.gd")
const UClassDetail = preload("res://addons/addon_lib/brohd/alib_editor/utils/src/u_class_detail.gd")

var singleton:EditorCodeCompletionSingleton

var _tags = {}


func _init() -> void:
	var settings = _get_completion_settings()
	singleton = EditorCodeCompletionSingleton._register_completion(self, settings)
	_singleton_ready()

func _get_completion_settings() -> Dictionary:
	return {
		"priority": 100,
	}

func _singleton_ready() -> void:
	pass


func register_tag(prefix:String, tag:String, location:=EditorCodeCompletionSingleton.TagLocation.ANY):
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

func get_script_preload_vars(script=null, force_rebuild:=false):
	if script == null:
		script = EditorInterface.get_script_editor().get_current_script()
	var path = script.resource_path
	if not singleton.peristent_cache.preload_typed_vars.has(path) or force_rebuild:
		singleton.get_preload_typed_vars(script)
	return singleton.peristent_cache.preload_typed_vars.get(path, {})

func get_preload_constant(preload_script_path:String, script=null):
	var preloads = get_script_preload_vars(script).get("preloads")
	for name in preloads.keys():
		var const_script = preloads.get(name)
		if const_script is not GDScript:
			continue
		if preload_script_path == const_script.resource_path:
			return name



func get_local_var_type(var_name:String):
	var type_hint = singleton.script_cache.local_vars.get(var_name, "")
	return type_hint

func get_func_name_of_line(line:int):
	return singleton.get_func_name_of_line(_get_code_edit(), line)

func get_current_func_name():
	return singleton.script_cache.get("current_func", "")

func get_func_local_vars(func_name:String=""):
	if func_name == "":
		func_name = get_current_func_name()
	return singleton.script_cache.local_vars.get(func_name, {})

func get_func_call_data(current_line_text:String):
	return singleton.get_func_call_data(current_line_text)

func get_assignment_at_cursor(script_editor:CodeEdit=null):
	if script_editor == null:
		script_editor = _get_code_edit()
	var line_text = script_editor.get_line(script_editor.get_caret_line())
	return singleton.get_assignment_at_cursor(line_text, script_editor.get_caret_column())

func sub_var_type(_name:String, var_type_dict:Dictionary):
	var dot_idx = _name.find(".")
	var first_word = _name
	if dot_idx > -1:
		first_word = _name.substr(0, _name.find("."))
	var type
	if first_word in var_type_dict.keys():
		type = var_type_dict.get(first_word)
	if type != null:
		if dot_idx > -1:
			return type + _name.trim_prefix(first_word)
		else:
			return type
	return _name

func is_caret_in_comment(line_text:String, caret_column:int):
	var in_comment = singleton.string_safe_is_index_after_string("#", line_text, caret_column - 1)
	return in_comment



static func _get_code_edit():
	if EditorInterface.get_script_editor().get_current_editor():
		return EditorInterface.get_script_editor().get_current_editor().get_base_editor()
