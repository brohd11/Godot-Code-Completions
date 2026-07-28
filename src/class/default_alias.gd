
const EditorCodeCompletionSingleton = EditorCodeCompletion.EditorCodeCompletionSingleton
const UtilsRemote = EditorCodeCompletionSingleton.UtilsRemote
const GDScriptParser = UtilsRemote.EditorGDScriptParser.GDScriptParser

const AliasCompletion = EditorCodeCompletionSingleton.AliasCompletion
const PLACEHOLDER = AliasCompletion.PLACEHOLDER

const FOR_LOOP_ALLOW_VAR = false

#region Utils
const DEFAULTS := {
	"int": "0", "float": "0.0", "String": "\"\"", "StringName": "&\"\"",
	"bool": "false", "Array": "[]", "Dictionary": "{}", "Vector2": "Vector2.ZERO",
}

static func type_check(type:String):
	var t_lower = type.to_lower()
	if t_lower == "dict":
		type = "Dictionary"
	elif t_lower == "arr":
		type = "Array"
	elif not DEFAULTS.has(type):
		var cap_check = type.capitalize().replace(" ", "")
		if DEFAULTS.has(cap_check):
			type = cap_check
	return type

static func default_for(type:String) -> String:
	return DEFAULTS.get(type, "null")

static func get_caret_context():
	return EditorCodeCompletion.EditorCodeCompletionSingleton.get_instance().get_caret_context()

#endregion

#region ForLoop

static func fori(collection):
	return "for i in range(len(%s)):\n\tvar item = %s[i]" % [collection, collection]

static func forib(collection):
	return "for i in range(-1, -1, len(%s) - 1):\n\tvar item = %s[i]" % [collection, collection]

static func forloop(iterator:String, collection:String):
	var cc = get_caret_context()
	if collection == PLACEHOLDER:
		if iterator == PLACEHOLDER:
			iterator = "x"
		var valid_loops = {}
		var function = cc.get_current_func_object()
		print(function)
		if not is_instance_valid(function):
			return ""
		function.map_variables()
		for v in function.in_scope_local_vars.keys():
			var v_name = function.get_local_var_unique_name_from_data(v, function.in_scope_local_vars.get(v))
			var v_type = function.get_local_var_type(v_name)
			var loops = _get_forloop_for_type(v_type, v, iterator)
			for l in loops:
				valid_loops[l] = true
		
		var class_obj = cc.get_current_class_object()
		if is_instance_valid(class_obj):
			for member in class_obj.get_members():
				if class_obj.get_member_data(member, true).get(GDScriptParser.Keys.MEMBER_TYPE).ends_with("func"):
					continue
				var type = class_obj.get_member_type(member)
				var loops = _get_forloop_for_type(type, member, iterator)
				for l in loops:
					valid_loops[l] = true
			
			for member in class_obj.get_inherited_members():
				if class_obj.get_member_data(member, true).get(GDScriptParser.Keys.MEMBER_TYPE).ends_with("func"):
					continue
				var type = class_obj.get_member_type(member, true)
				var loops = _get_forloop_for_type(type, member, iterator)
				for l in loops:
					valid_loops[l] = true
		
		return valid_loops.keys()
	
	var type = cc.resolve_expression_to_type(collection)
	var tc = GDScriptParser.Utils.type_path_get_type(type)
	if tc != "":
		type = tc
	
	var valid = _get_forloop_for_type(type, collection, iterator)
	if not valid.is_empty():
		return valid
	return "for %s:Variant in %s:\n\tpass" % [iterator, collection]


static func _get_forloop_for_type(type:String, collection:String, iterator:=""):
	var tc = GDScriptParser.Utils.type_path_get_type(type)
	if tc != "":
		type = tc
	
	var tail = "\n\tpass"
	var default = "for %s:Variant in %s:" % [iterator, collection]
	if type == "":
		return []
	if type.ends_with("Array") or not type.begins_with("Dictionary"):
		# indexable variants(string, colors) can hit below, this limites to only packed arrays
		if not FOR_LOOP_ALLOW_VAR:
			if not type.ends_with("Array"):
				return []
		
		var var_type = GDScriptParser.BuiltInChecker.get_variant_index_access_type(type)
		if var_type == "Variant":
			return []
		else:
			return ["for %s:%s in %s:%s" % [iterator, var_type, collection, tail]]
	
	if type.find("[") == -1:
		if type.begins_with("Dict"):
			return [
				"for %s:Variant in %s.keys():%s" % [iterator, collection, tail],
				"for %s:Variant in %s.values():%s" % [iterator, collection, tail]
			]
		else:
			return [default + tail]
	
	if type.begins_with("Array"):
		var nested_type = type.get_slice("[", 1).trim_suffix("]")
		return ["for %s:%s in %s:%s" % [iterator, nested_type, collection, tail]]
	elif type.begins_with("Dictionary"):
		var nested_type = type.get_slice("[", 1).trim_suffix("]")
		var key = nested_type.get_slice(",", 0).strip_edges()
		var val = nested_type.get_slice(",", 1).strip_edges()
		return [
			"for %s:%s in %s.keys():%s" % [iterator, key, collection, tail],
			"for %s:%s in %s.values():%s" % [iterator, val, collection, tail]
		]

#endregion

#region Icons

static func icon():
	var icons = EditorInterface.get_editor_theme().get_icon_list("EditorIcons")
	var constructed = []
	for i in icons:
		constructed.append('&"%s"' % i)
	return constructed

# insert must be short than the full call
static func edicon():
	var constructed = []
	for i in EditorInterface.get_editor_theme().get_icon_list("EditorIcons"):
		constructed.append(EditorCodeCompletion.get_code_complete_dict_static(
				CodeEdit.KIND_CONSTANT, i,
				'EditorInterface.get_editor_theme().get_icon(&"%s", &"EditorIcons")' % i, i))
	
	return constructed

#endregion


static func setget(name, type:= "int") -> String:
	type = type_check(type)
	return "var %s:%s = %s:\n\tset(value):\n\t\t%s = value\n\tget():\n\t\treturn %s" \
			% [name, type, default_for(type), name, name]


static func drop(name:String):
	return "func %s_can_drop_data(at_position: Vector2, data: Variant) -> bool:
	return false
  
func %s_drop_data(at_position: Vector2, data: Variant) -> void:
	pass

func %s_get_drag_data(at_position: Vector2) -> Variant:
	var data = {}
	return data" % [name, name, name]
