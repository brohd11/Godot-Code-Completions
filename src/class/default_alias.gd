
const EditorCodeCompletionSingleton = EditorCodeCompletion.EditorCodeCompletionSingleton
const UtilsRemote = EditorCodeCompletionSingleton.UtilsRemote
const UClassDetail = UtilsRemote.UClassDetail
const EditorColors = UtilsRemote.EditorColors
const EditorGDScriptParser = UtilsRemote.EditorGDScriptParser
const GDScriptParser = EditorGDScriptParser.GDScriptParser

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

static func fori(collection:String):
	var it = get_valid_iterator()
	if collection.is_valid_int():
		return "for %s:int in range(%s):\n\tpass" % [it, collection]
	return "for %s:int in range(len(%s)):\n\tvar item = %s[%s]" % [it, collection, collection, it]

static func forib(collection):
	var it = get_valid_iterator()
	if collection.is_valid_int():
		return "for %s:int in range(-1, -1, %s - 1):\n\tpass" % [it, collection]
	return "for %s:int in range(-1, -1, len(%s) - 1):\n\tvar item = %s[%s]" % [it, collection, collection, it]

static func get_valid_iterator():
	var cc = get_caret_context()
	var ch = 105
	while cc.local_vars.has(char(ch)):
		ch += 1
	return char(ch)

static func forloop(iterator:String, collection:String):
	if iterator == PLACEHOLDER:
		iterator = ""
	var cc = get_caret_context()
	if collection == PLACEHOLDER:
		if iterator == PLACEHOLDER:
			iterator = "x"
		var valid_loops = {}
		var function = cc.get_current_func_object()
		if not is_instance_valid(function):
			return ""
		function.map_variables()
		for v in function.in_scope_local_vars.keys():
			var v_name = function.get_local_var_unique_name_from_data(v, function.in_scope_local_vars.get(v))
			var v_type = function.get_local_var_type(v_name)
			
			var loops = _get_forloop_for_type(v_type, v, iterator)
			#print(v_name, ":", v_type, loops)
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
	var default = "for %s:Variant in %s:" % [_get_iterator(iterator, "Variant"), collection]
	if type == "":
		return []
	if not (type.begins_with("Array") or type.begins_with("Dictionary")):
	#if type.ends_with("Array") or not type.begins_with("Dictionary"):
		# indexable variants(string, colors) can hit below, this limites to only packed arrays
		if not FOR_LOOP_ALLOW_VAR:
			if not type.ends_with("Array"):
				return []
		
		var var_type = GDScriptParser.BuiltInChecker.get_variant_index_access_type(type)
		if var_type == "Variant":
			return []
		else:
			return ["for %s:%s in %s:%s" % [_get_iterator(iterator, var_type), var_type, collection, tail]]
	
	if type.find("[") == -1:
		if type.begins_with("Dict"):
			return [
				"for %s:Variant in %s.keys():%s" % [_get_iterator(iterator, "Variant"), collection, tail],
				"for %s:Variant in %s.values():%s" % [_get_iterator(iterator, "Variant"), collection, tail]
				]
		else:
			return [default + tail]
	
	if type.begins_with("Array"):
		var nested_type = type.get_slice("[", 1).trim_suffix("]")
		return ["for %s:%s in %s:%s" % [_get_iterator(iterator, nested_type), nested_type, collection, tail]]
	elif type.begins_with("Dictionary"):
		var nested_type = type.get_slice("[", 1).trim_suffix("]")
		var key = nested_type.get_slice(",", 0).strip_edges()
		var val = nested_type.get_slice(",", 1).strip_edges()
		return [
			"for %s:%s in %s.keys():%s" % [_get_iterator(iterator, key), key, collection, tail],
			"for %s:%s in %s.values():%s" % [_get_iterator(iterator, val), val, collection, tail]
			]

static func _get_iterator(iterator:String, type:String):
	if iterator == "":
		return type[0].to_lower()
	return iterator

#endregion

#region Icons

static func icon():
	var icons = EditorInterface.get_editor_theme().get_icon_list("EditorIcons")
	var sn_color = EditorColors.get_syntax_color(EditorColors.SyntaxColor.STRING_NAME)
	var constructed = []
	for i in icons:
		var full = '&"%s"' % i
		constructed.append(EditorCodeCompletion.get_code_complete_dict_static(
				CodeEdit.KIND_CONSTANT, full, full, i, sn_color))
	
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



#region Signal Signature

const SIG_FUNC_TEMPLATE = "func _on_%s(%s):\n\tpass"

static func sig(type_or_var:String, signal_name:String):
	var type = type_or_var
	if not GDScriptParser.BuiltInChecker.is_builtin_class(type_or_var):
		var cc = get_caret_context()
		type = cc.resolve_expression_to_type(type_or_var)
		if type == "":
			return "_on_%s" % signal_name
	
	type = type.trim_suffix(GDScriptParser.Keys.INS_DELIM)
	var tc = GDScriptParser.Utils.type_path_get_type(type, true)
	if tc != "":
		type = tc
	
	var completions = []
	if type.is_absolute_path(): # custom class
		var ed_parser = EditorGDScriptParser.get_parser()
		var parser_data = ed_parser.get_parser_and_class_obj_for_script(type)
		var class_obj:GDScriptParser.ParserClass = parser_data.class_obj
		var member_data = class_obj.get_member_data(signal_name, true)
		var valid = member_data != null and member_data.get(GDScriptParser.Keys.MEMBER_TYPE) == GDScriptParser.Keys.MEMBER_TYPE_SIGNAL
		if not valid:
			for m in class_obj.members:
				var md = class_obj.members[m]
				if md.get(GDScriptParser.Keys.MEMBER_TYPE) != GDScriptParser.Keys.MEMBER_TYPE_SIGNAL:
					continue
				completions.append(_signal_completion(type_or_var, m))
			
			for m in class_obj.get_inherited_members():
				var md = class_obj.members[m]
				if md.get(GDScriptParser.Keys.MEMBER_TYPE) != GDScriptParser.Keys.MEMBER_TYPE_SIGNAL:
					continue
				completions.append(_signal_completion(type_or_var, m))
			
			if completions.is_empty():
				completions.append("/sig/ no signals found")
			return completions
		# has signal
		
		var actual_path = GDScriptParser.Utils.get_class_access_path_from_member_data(member_data)
		var actual_parser = ed_parser.get_parser_and_class_obj_for_script(actual_path)
		var actual_class_obj:GDScriptParser.ParserClass = actual_parser.class_obj
		var sig_args = actual_class_obj.get_script_signal_args(signal_name)
		var arg_str = ""
		for nm in sig_args.keys():
			var arg_type = sig_args[nm]
			arg_type = arg_type.trim_suffix(GDScriptParser.Keys.INS_DELIM)
			arg_str += "%s:%s, " % [nm, arg_type]
		arg_str = arg_str.strip_edges().trim_suffix(",")
		return SIG_FUNC_TEMPLATE % [signal_name, arg_str]
	else: # node type class
		if not ClassDB.class_exists(type):
			return "not valid type:%s" % type
		if not ClassDB.class_has_signal(type, signal_name):
			var signals = ClassDB.class_get_signal_list(type)
			for s in signals:
				completions.append(_signal_completion(type_or_var, s.name))
			
			if completions.is_empty():
				completions.append("/sig/ no signals found")
			return completions
		
		var arg_str = ""
		# built in checker can't non extension_json classes ie. Terrain3D
		#var member_data = GDScriptParser.BuiltInChecker.get_member_data(type, signal_name)
		#if not member_data.is_empty():
			#var args = member_data.get("arguments", [])
			#for a in args:
				#arg_str += "%s:%s, " % [a.name, a.type]
		#else:
		
		var data = ClassDB.class_get_signal(type, signal_name)
		var args = data.get("args", [])
		for a in args:
			var a_type = a.class_name
			if a_type == "":
				a_type = type_string(a.type)
			arg_str += "%s:%s, " % [a.name, a_type]
		
		# has signal
		arg_str = arg_str.strip_edges().trim_suffix(",")
		return SIG_FUNC_TEMPLATE % [signal_name, arg_str]

static func _signal_completion(type_or_var:String, s_name:String):
	return EditorCodeCompletion.get_code_complete_dict_static(
		CodeEdit.KIND_SIGNAL,
		s_name,
		"/sig/%s/%s/" % [type_or_var, s_name],
		"signal",
		EditorCodeCompletion.Helpers.Colors.DEFAULT_COMPLETION,
		null, 0 # location: 0
	)
#endregion

#region NewClass

static func new_class():
	var caret_context = get_caret_context()
	var options = []
	var parser = GDScriptParser.Utils.ParserRef.get_parser(caret_context)
	
	#^ preloads / inner classes of the class at the caret line
	var class_obj = caret_context.get_current_class_object()
	if is_instance_valid(class_obj):
		var gdscript_constants = class_obj.get_gdscript_constants(true)
		for c in gdscript_constants.keys():
			var type = gdscript_constants[c]
			if type.ends_with(GDScriptParser.Keys.ENUM_PATH_SUFFIX):
				continue
			var disp = c + ".new(" if EditorCodeCompletion.Helpers.script_has_init_args(parser, type) else c + ".new()"
			options.append(disp)
			
	
	#^ global user classes
	var global_classes = UClassDetail.get_all_global_class_paths()
	for name in global_classes.keys():
		if options.has(name):
			continue
		var disp = name + ".new(" if EditorCodeCompletion.Helpers.script_has_init_args(parser, global_classes[name]) else name + ".new()"
		options.append(disp)
	#^ engine classes
	for name in ClassDB.get_class_list():
		if global_classes.has(name): #^ shadowed by a user class
			continue
		if not ClassDB.can_instantiate(name):
			continue
		options.append(name + ".new()")
	
	return options

#endregion

#region Misc


static func setget(name, type:= "int") -> String:
	type = type_check(type)
	return "var %s:%s = %s:\n\tset(value):\n\t\t%s = value\n\tget():\n\t\treturn %s" \
			% [name, type, default_for(type), name, name]


static func drop(name:String):
	return """func %s_can_drop_data(at_position: Vector2, data: Variant) -> bool:
	return false

func %s_drop_data(at_position: Vector2, data: Variant) -> void:
	pass

func %s_get_drag_data(at_position: Vector2) -> Variant:
	var data = {}
	return data""" % [name, name, name]
#endregion
