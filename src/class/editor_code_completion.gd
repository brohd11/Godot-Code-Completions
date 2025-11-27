class_name EditorCodeCompletion

const EditorCodeCompletionSingleton = preload("res://addons/code_completions/src/class/editor_code_completion_singleton.gd")
const UClassDetail = preload("res://addons/addon_lib/brohd/alib_editor/utils/src/u_class_detail.gd")
const UString = preload("res://addons/addon_lib/brohd/alib_runtime/utils/src/u_string.gd")
const DataAccessSearch = EditorCodeCompletionSingleton.DataAccessSearch

const TagLocation = EditorCodeCompletionSingleton.TagLocation
const State = EditorCodeCompletionSingleton.State

var singleton:EditorCodeCompletionSingleton

var editor_theme

## Holds registered tags to unregister on clean up. Not to be modified.
var _tags = {}

static func register_plugin(plugin:EditorPlugin):
	return EditorCodeCompletionSingleton.register_plugin(plugin)

static func unregister_plugin(plugin:EditorPlugin):
	EditorCodeCompletionSingleton.unregister_plugin(plugin)

func _init() -> void:
	var settings = _get_completion_settings()
	if not EditorCodeCompletionSingleton.instance_valid():
		printerr("Register plugin with 'EditorCodeCompletion.register_plugin()' before instancing.")
		return
	
	singleton = EditorCodeCompletionSingleton.get_instance()
	singleton.register_completion(self, settings)
	EditorCodeCompletionSingleton.call_on_ready(_singleton_ready)
	
	editor_theme = EditorInterface.get_editor_theme()

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

## Get current state of line. See members of [enum State] enum
func get_state() -> State:
	return singleton.get_state()


func get_current_class() -> String:
	return singleton.get_current_class()

func get_current_func() -> String:
	return singleton.get_current_func()

## Get body and local vars of current class and func. All local vars are included, not just in-scope.
## [method get_in_scope_body_and_local_vars] for in scope only.
func get_body_and_local_vars():
	return singleton.gdscript_parser.get_body_and_local_vars(get_current_class(), get_current_func())

## Get body and local vars of class and func. Filters vars that are not in scope.
func get_in_scope_body_and_local_vars():
	return singleton.gdscript_parser.get_in_scope_body_and_local_vars()

## Get enum members from GDScriptParser
func get_enum_members(enum_name:String, _class=null):
	return singleton.gdscript_parser.get_enum_members(enum_name, _class)

func class_has_func(_func:String, _class:String="") -> bool:
	return singleton.class_has_func(_func, _class)

func get_script_constants(_class:String=""):
	return singleton.get_script_constants(_class)

func get_preload_map():
	return singleton.get_preload_map()

func get_global_script_location(script:GDScript):
	return singleton.get_global_script_location(script)

func get_func_args(_class:String, _func_name:String) -> Dictionary:
	return singleton.get_func_args(_class, _func_name)

## Check if caret
func caret_in_func_call():
	return singleton.completion_cache.get(singleton.CompletionCache.CARET_IN_FUNC_CALL, false)

func caret_in_func_declaration():
	return singleton.completion_cache.get(singleton.CompletionCache.CARET_IN_FUNC_DECLARATION, false)

## Get data of current function parentheses caret is within.
func get_func_call_data(infer_type:=false):
	return singleton.get_func_call_data(infer_type)

## Get assignment data at caret. If on the left side of "=" or comparison operator,
## returns dictionary with left, left with inferred type, operator, right.
func get_assignment_at_caret():
	return singleton.get_assignment_at_caret()

func is_index_in_comment(column:int=-1, line:int=-1, code_edit=null):
	return singleton.is_index_in_comment(column, line, code_edit)

func is_index_in_string(column:int=-1, line:int=-1, code_edit=null):
	return singleton.is_index_in_string(column, line, code_edit)

func is_caret_in_dict():
	return singleton.is_caret_in_dict()

func is_caret_in_enum():
	return singleton.is_caret_in_enum()

func get_word_before_caret():
	return singleton.get_word_before_caret()

func get_char_before_caret():
	return singleton.get_char_before_caret()

#func add_completion_options(options:Array, hide_private=null):
	#singleton.add_code_completion_options(options, hide_private)

func add_completion_option(script_editor:CodeEdit, option_dict:Dictionary) -> void:
	script_editor.add_code_completion_option(option_dict.kind, option_dict.display_text,
					option_dict.insert_text, option_dict.font_color, option_dict.icon, 
					option_dict.default_value, option_dict.location)

func update_completion_options(force:=false):
	var current = get_code_edit()
	current.update_code_completion_options(force)

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

func set_data(key, value):
	singleton.peristent_cache[key] = value

func get_data(key):
	return singleton.peristent_cache.get(key)

func get_code_complete_dict(kind:CodeEdit.CodeCompletionKind, display_text, insert_text, icon_name,
						default_value=null, location=1024, font_color:Color=Color.LIGHT_GRAY):
	var icon
	if icon_name == "constructor":
		icon = editor_theme.get_icon("MemberConstructor", "EditorIcons")
	elif icon_name == "const":
		icon = editor_theme.get_icon("MemberConstant", "EditorIcons")
	elif icon_name == "property":
		icon = editor_theme.get_icon("MemberProperty", "EditorIcons")
	elif icon_name == "signal":
		icon = editor_theme.get_icon("MemberSignal", "EditorIcons")
	elif icon_name == "method":
		icon = editor_theme.get_icon("MemberMethod", "EditorIcons")
	elif icon_name == "enum":
		icon = editor_theme.get_icon("Enum", "EditorIcons")
	else:
		icon = editor_theme.get_icon(icon_name, "EditorIcons")
	return {
		"kind":kind,
		"display_text":display_text,
		"insert_text":insert_text,
		"font_color":font_color,
		"icon":icon,
		"default_value":default_value,
		"location":location,
	}


func get_current_script():
	return singleton._current_script
func get_code_edit():
	return singleton._current_code_edit

class Assignment:
	const LEFT = &"left"
	const LEFT_TYPED = &"left_typed"
	const OPERATOR = &"operator"
	const RIGHT = &"right"

class FuncCall:
	const FULL_CALL = &"full_call"
	const FULL_CALL_TYPED = &"full_call_typed"
	const ARGS = &"args"
	const ARG_INDEX = &"arg_index"
