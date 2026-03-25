class_name EditorCodeCompletion

const EditorCodeCompletionSingleton = preload("res://addons/code_completions/src/class/editor_code_completion_singleton.gd")

const TagLocation = EditorCodeCompletionSingleton.TagLocation

const UtilsRemote = EditorCodeCompletionSingleton.UtilsRemote
const UClassDetail = UtilsRemote.UClassDetail
const UString = UtilsRemote.UString


const ParserKeys = GDScriptParser.Keys

const TokenState = CaretContext.TokenState
const ExpressionState = CaretContext.ExpressionState
const GDScriptParser = UtilsRemote.EditorGDScriptParser.GDScriptParser
const CaretContext = GDScriptParser.CaretContext
const ScopeState = CaretContext.ScopeState

class Preloads:
	const TestPreload = preload("res://test_comp.gd")

class Class:
	const Nest = _ClassLayers.AnotherWrapper.Nest

class _ClassLayers extends NewScript3:
	class AnotherWrapper extends AnotherTest:
		class Nest extends Preloads.TestPreload:
			pass
		
			static func ye(yar:String) -> MyNum:
				return MyNum.YUP
				pass
			pass
	
	static func test_method():
		print("YUP TEST")
		pass
	
	pass

static func test_method_base():
	print("YUP")
	pass

class Another:
	pass

var singleton:EditorCodeCompletionSingleton

var editor_theme

## Holds registered tags to unregister on clean up. Not to be modified.
var _tags = {}

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

func _get_completion_settings() -> Dictionary:
	return {
		"priority": 100,
	}

func _singleton_ready() -> void:
	pass

static func call_on_ready(callable:Callable):
	EditorCodeCompletionSingleton.call_on_ready(callable)

# TODO are these used?
static func register_tag_static(prefix:String, tag:String, location:=TagLocation.ANY):
	if not EditorCodeCompletionSingleton.instance_valid():
		print("EditorCodeCompletionSingleton not instanced yet.")
		return
	EditorCodeCompletionSingleton.get_instance().register_tag(prefix, tag, TagLocation.ANY)

static func unregister_tag_static(prefix:String, tag:String, location:=TagLocation.ANY):
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

func get_code_complete_dict(kind:CodeEdit.CodeCompletionKind, display_text, insert_text, icon_name="",
						default_value=null, location=1024, font_color:Color=Color.LIGHT_GRAY):
	var icon
	if icon_name == "":
		pass
	elif icon_name == "constructor":
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

func add_completion_option(script_editor:CodeEdit, option_dict:Dictionary) -> void:
	script_editor.add_code_completion_option(option_dict.kind, option_dict.display_text,
					option_dict.insert_text, option_dict.font_color, option_dict.icon, 
					option_dict.default_value, option_dict.location)

func update_completion_options(force:=false):
	var current = get_code_edit()
	current.update_code_completion_options(force)

#endregion





func get_gdscript_parser():
	return singleton._editor_gdscript_parser

func get_caret_context():
	return singleton.get_caret_context()


#^^^^ new



#^ OLD


func get_global_script_location(script:GDScript):
	return singleton.get_global_script_location(script)





func get_string_map(text:String):
	return singleton.get_string_map(text)

func get_script_member_info_by_path(script:GDScript, member_path:String, member_hints:=UClassDetail._MEMBER_ARGS, check_global:=true):
	return UClassDetail.get_member_info_by_path(script, member_path, member_hints, false, false, false, check_global)

func split_path(script_path:String):
	return UString.get_script_path_and_suffix(script_path)


#region settings
func get_hide_private_members_setting():
	return singleton.hide_private_members

#endregion



#^ cache
func _store_data(section, key, value, script, data_cache:Dictionary):
	singleton._store_data_in_section(section, key, value, script, data_cache)

func _get_cached_data(section, key, data_cache:Dictionary):
	return singleton._get_cached_data_in_section(section, key, data_cache)

func set_data(key, value):
	singleton.peristent_cache[key] = value

func get_data(key):
	return singleton.peristent_cache.get(key)
