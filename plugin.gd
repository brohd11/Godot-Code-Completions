@tool
extends EditorPlugin

const EnumCompletion = preload("res://addons/code_completions/src/completions/enum_completion.gd")
var enum_completion:EnumCompletion
const ImportCodeCompletion = preload("res://addons/code_completions/src/completions/import_code_completion.gd")
var import_code_completion:ImportCodeCompletion

var syntax_plus:SyntaxPlus

func _get_plugin_name() -> String:
	return "Code Completions"

func _enable_plugin() -> void:
	pass
	#var ed_set = EditorInterface.get_editor_settings()


func _enter_tree() -> void:
	syntax_plus = SyntaxPlus.register_node(self)
	
	enum_completion = EnumCompletion.new()
	import_code_completion = ImportCodeCompletion.new()

func _exit_tree() -> void:
	if is_instance_valid(enum_completion):
		enum_completion.clean_up()
	if is_instance_valid(import_code_completion):
		import_code_completion.clean_up()
	
	if is_instance_valid(syntax_plus):
		syntax_plus.unregister_node(self)
