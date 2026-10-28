extends SceneTree
## Clean-compile headless entry for the code_completions suites, exiting with a CI code.
##     godot --headless --path . --script res://addons/code_completions/export_ignore/test/run_headless.gd

const SUITES:PackedStringArray = [
	"res://addons/code_completions/export_ignore/test/alias_completion_test.gd",
	"res://addons/code_completions/export_ignore/test/arr_struct_test.gd",
	"res://addons/code_completions/export_ignore/test/unicode_completion_test.gd",
]

func _init() -> void:
	var success = true
	var output:Array[String] = []

	for path in SUITES:
		var res:Dictionary = load(path).run_tests()
		success = success and res.result == 0
		output.append_array(res.output)

	print("\n".join(output))
	quit(0 if success else 1)
