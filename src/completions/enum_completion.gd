@tool
extends EditorCodeCompletion
#! remote

const UClassDetail = preload("res://addons/addon_lib/brohd/alib_editor/utils/src/u_class_detail.gd")

var script_enums = {}

func _on_editor_script_changed(script:Script):
	script_enums.clear()
	var enums = UClassDetail.class_get_all_enums(script)
	enums.append_array(UClassDetail.script_get_all_enums(script))
	script_enums = enums


func _on_code_completion_requested(script_editor:CodeEdit) -> void:
	var current_script = EditorInterface.get_script_editor().get_current_script()
	var current_line_text = script_editor.get_line(script_editor.get_caret_line())
	if current_line_text.find("=") == -1:
		return
	
	var assignment = current_line_text.get_slice("=", 0)
	var words = assignment.strip_edges().split(" ", false)
	
	if words.size() == 0:
		return
	if assignment.find("var") > -1:
		var property_name = assignment.get_slice("var", 1)
		var type_hint = property_name.get_slice(":", 1).strip_edges()
		if type_hint in script_enums:
			var class_nm = current_script.resource_path + "." + type_hint
			_add_code_completions(script_editor, class_nm)
		else:
			_add_code_completions(script_editor, type_hint)
	else:
		var assign_var = words[words.size() - 1]
		var property_enum_class_name = _get_property_enum_class_name(current_script, assign_var)
		if property_enum_class_name == null:
			return
		_add_code_completions(script_editor, property_enum_class_name)


func _add_code_completions(script_editor, property_enum_class_name):
	var property_enum_data = _get_enum_members(property_enum_class_name)
	if property_enum_data.is_empty():
		return
	if property_enum_class_name.begins_with("res://"):
		property_enum_class_name = property_enum_class_name.get_slice(".gd.", 1)
	var enum_icon = EditorInterface.get_editor_theme().get_icon("Enum", "EditorIcons")
	for member in property_enum_data.keys():
		var full_name = property_enum_class_name + "." + member
		script_editor.add_code_completion_option(CodeEdit.KIND_ENUM, full_name, full_name, Color.GRAY, enum_icon)
	script_editor.update_code_completion_options(false)


func _get_property_enum_class_name(script:Script, member_name:String):
	var data = UClassDetail.get_member_data(script, member_name, "property")
	if data == null:
		return
	var type = data.get("type")
	type = type_string(type)
	var class_nm:String = data.get("class_name", "")
	if type == "int" and class_nm != "":
		return class_nm

func _get_enum_members(_class_name:String):
	if _class_name.begins_with("res://"):
		var enum_full_nm = _class_name.get_slice(".gd.", 1)
		var script_path = _class_name.trim_suffix(enum_full_nm).trim_suffix(".")
		var enum_script = load(script_path)
		var enum_nm = enum_full_nm
		if enum_full_nm.find(".") > -1:
			var slice_count = enum_full_nm.get_slice_count(".")
			for i in range(slice_count):
				var slice = enum_full_nm.get_slice(".", i)
				if i == enum_full_nm.get_slice_count(".") - 1:
					enum_nm = slice
					break
				
				enum_script = enum_script.get(slice)
		
		return UClassDetail.get_member_data(enum_script, enum_nm, "enum")
	else:
		var parts = _class_name.split(".")
		var global_name = parts[0]
		var enum_name = parts[parts.size() - 1]
		parts.remove_at(parts.size() - 1)
		parts.remove_at(0)
		
		var global_classes = ProjectSettings.get_global_class_list()
		var global_class_path:String
		for dict in global_classes:
			var _class = dict.get("class")
			if _class == global_name:
				global_class_path = dict.get("path")
				break
		
		var global_class_script = load(global_class_path)
		for _class in parts:
			global_class_script = global_class_script.get(_class)
		
		return UClassDetail.get_member_data(global_class_script, enum_name, "enum")
