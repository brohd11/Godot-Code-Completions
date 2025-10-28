@tool
extends EditorPlugin

const EnumCompletion = preload("res://addons/code_completions/src/completions/enum_completion.gd")
var enum_completion:EnumCompletion


func _get_plugin_name() -> String:
	return "Code Completions"

func _enable_plugin() -> void:
	var ed_set = EditorInterface.get_editor_settings()
	
	
	pass


func _enter_tree() -> void:
	enum_completion = EnumCompletion.new()

func _exit_tree() -> void:
	enum_completion.clean_up()
