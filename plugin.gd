@tool
extends EditorPlugin

func _get_plugin_name() -> String:
	return "Code Completions"

func _enable_plugin() -> void:
	pass
	#var ed_set = EditorInterface.get_editor_settings()


func _enter_tree() -> void:
	EditorCodeCompletion.register_plugin(self)

func _exit_tree() -> void:
	EditorCodeCompletion.unregister_plugin(self)
