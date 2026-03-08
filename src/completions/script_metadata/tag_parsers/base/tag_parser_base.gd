
const UtilsRemote = preload("res://addons/code_completions/src/class/utils_remote.gd")
const UClassDetail = UtilsRemote.UClassDetail
const UString = UtilsRemote.UString

const ScriptMetadata = preload("res://addons/code_completions/src/completions/script_metadata.gd")

const State = ScriptMetadata.State

var script_metadata:ScriptMetadata


func code_completion_requested(script_editor:CodeEdit) -> bool:
	return false


func parse_tag(tags:String) -> Dictionary:
	return {}
