extends EditorCodeCompletion

const UNode = UtilsRemote.UNode

const DEFAULT_ALIAS_DIR = "res://aliases/"
const ALIAS_SCRIPT_NAME = "aliases.gd"
const DISPLAY_MAX = 60
const ELLIPSIS = "…"
const PLACEHOLDER = "placeholder"
const BLANK_ARG = "_" # a lone underscore asks for an empty substitution
const ARG_SEPARATOR = "/" # the parser counts '/' as an identifier char, so it survives to us intact
const HELPER_PREFIX = "_" # never an alias

# delimiter for the highlighted run of a code hint; draws the hint with these stripped
const HINT_MARKER = "\uFFFF"

var _enable:bool = true
var _alias_dir:String = DEFAULT_ALIAS_DIR

var modified_times:= {}
var _aliases:= {}

var _code_hint_line:int = -1



func _get_completion_settings() -> Dictionary:
	return {
		"priority": 2, # tag_completion(1) is comment only, everything else runs after
	}

func register_editor_settings(settings_helper:SettingHelperEditor):
	settings_helper.subscribe_property(self, &"_enable", EditorSet.ENABLE, true)
	settings_helper.subscribe_property(self, &"_alias_dir", EditorSet.DIRECTORY, DEFAULT_ALIAS_DIR)
	settings_helper.settings_changed.connect(_on_editor_settings_changed)

func _on_editor_settings_changed():
	_reload_if_changed()

func _on_text_changed():
	if not _enable or _aliases.is_empty():
		return
	_clear_code_hint(get_code_edit())
	var code_edit = get_code_edit()
	var col = code_edit.get_caret_column()
	var text = code_edit.get_line(code_edit.get_caret_line())
	if col > 0 and text.length() > 0 and text[col - 1] == ARG_SEPARATOR:
		code_edit.code_completion_requested.emit()

func _singleton_ready() -> void:
	ExampleAlias.write_file()
	_reload_if_changed()
	ScriptEditorRef.subscribe(ScriptEditorRef.Event.TEXT_CHANGED, _on_text_changed)

func _on_editor_script_changed(_script) -> void:
	_code_hint_line = -1
	_reload_if_changed()

func _clear_code_hint(script_editor:CodeEdit) -> void:
	if _code_hint_line == -1:
		return
	#if _code_hint_line == script_editor.get_caret_line():
	script_editor.set_code_hint("")
	_code_hint_line = -1

# only applies to funcs
func _set_code_hint(script_editor:CodeEdit, key:String, entry:Dictionary, typed:String) -> void:
	if entry.arg_names.is_empty():
		return
	script_editor.set_code_hint(make_code_hint(key, entry.arg_names, entry.required, open_arg_index(typed)))
	script_editor.set_code_hint_draw_below(false) # the popup owns the space below
	_code_hint_line = script_editor.get_caret_line()

func _on_code_completion_requested(script_editor:CodeEdit) -> bool:
	_clear_code_hint(script_editor)
	if not _enable or _aliases.is_empty():
		return false
	
	var caret_context = get_caret_context()
	if caret_context.token_state != TokenState.NONE:
		return false
	if caret_context.expression_state == ExpressionState.MEMBER_ACCESS:
		return false
	
	var expression = caret_context.expression_before_caret
	# must start with "/"
	if not expression.begins_with(ARG_SEPARATOR):
		return false
	
	var lookup = expression.substr(ARG_SEPARATOR.length())
	var key = longest_key(_aliases, lookup)
	if key == "": # adds all aliases as options if key not found
		return _add_menu_options(script_editor, lookup)

	var indent = get_line_indent(caret_context.current_line_text)
	var entry:Dictionary = _aliases[key]
	var typed = lookup.substr(key.length())
	var args = split_args(typed)
	var matched = false
	
	# display is what the popup filters
	var display_key = ARG_SEPARATOR + key
	# /my_alias/substr/[som] <- uncompleted arg is split
	var prefix = display_key + split_consumed(typed, entry.slots)[0]
	
	
	var max_slots:int = entry.slots # a builder's parameter count; a const has none
	_set_code_hint(script_editor, key, entry, typed)
	
	# add member suggestions from script/local vars
	if max_slots > 0:
		var open_parts = split_open_arg(typed)
		if not open_parts.is_empty():
			var closed = display_key + open_parts[0]
			if open_parts[1] != "":
				matched = _add_name_options(script_editor, caret_context, closed, open_parts[1])
			elif typed.contains(ARG_SEPARATOR) and filled_arg_count(args) < max_slots:
				matched = _add_name_options(script_editor, caret_context, closed, "")
	
	if entry.build is Callable:
		# an empty result just adds no rows - returning would orphan any name options already added
		var builder_rows = _call_builder(key, entry, args)
		# if the result contains a completion slice, ditch the name completions, assume user knows best
		var first_option_text:= ""
		if not builder_rows.is_empty():
			var first_row = builder_rows[0]
			if first_row is String:
				first_option_text = first_row
			elif first_row is Dictionary:
				first_option_text = first_row.get(&"display_text")
		
		if first_option_text.begins_with("/%s/" % key):
			script_editor.update_code_completion_options(false)
		
		for row in builder_rows:
			var cc_dict:Dictionary
			if row is Dictionary:
				# builder's texts get wrap and indent treatment, no need to worry on impl side
				cc_dict = row
				cc_dict[&"display_text"] = make_display(prefix, cc_dict[&"display_text"])
				cc_dict[&"insert_text"] = apply_indent(cc_dict[&"insert_text"], indent)
			else:
				cc_dict = get_code_complete_dict(CodeEdit.KIND_PLAIN_TEXT,
						make_display(prefix, row),
						apply_indent(row, indent), "Shortcut", null, CodeEdit.LOCATION_LOCAL)
			add_completion_option(script_editor, cc_dict)
			matched = true
	
	else: # const can have placeholders, if it does, calculate arg sizes
		for i:int in range(len(args)):
			args[i] = resolve_arg(args[i])
		
		for text:String in entry.options:
			var slots = text.count("%s")
			var args_for_option:Array = args.duplicate()
			var args_sz = args_for_option.size()
			if args_sz > 0 and args_for_option[args_sz - 1] == PLACEHOLDER:
				args_for_option.remove_at(args_sz - 1)
				args_sz -= 1
			
			if args_sz < slots:
				for i in range(args_sz, slots):
					if args_sz == 1:
						args_for_option.append(args_for_option[0])
					else:
						args_for_option.append(PLACEHOLDER)
			elif args_sz > slots:
				text = text + "/ invalid args"
				slots = 0
			
			var new_text = text
			if slots > 0:
				new_text = text % args_for_option
			
			var cc_dict = get_code_complete_dict(
				CodeEdit.KIND_PLAIN_TEXT,
				make_display(prefix, new_text),
				apply_indent(new_text, indent),
				"Shortcut", null, CodeEdit.LOCATION_LOCAL)
			
			add_completion_option(script_editor, cc_dict)
			matched = true
	
	if not matched:
		return false

	update_completion_options(true)
	return true


## The keys still reachable from what has been typed, one row each.
## Returns whether anything was added.
func _add_menu_options(script_editor:CodeEdit, prefix:String) -> bool:
	var keys = keys_starting_with(_aliases, prefix)
	for key:String in keys:
		var entry:Dictionary = _aliases[key]
		
		var single = entry.options.size() == 1 and entry.slots == 0
		# the hint goes AFTER the key so a partly typed key still matches the display contiguously
		var display = "= " + entry.options[0] if single else make_arg_hint(entry.arg_names, entry.slots, entry.required)
		# insert /key/ so that next completion is triggered automatically
		var insert:String = entry.options[0] if single else ARG_SEPARATOR + key + ARG_SEPARATOR
		var cc_dict = get_code_complete_dict(
			CodeEdit.KIND_PLAIN_TEXT,
			make_display(ARG_SEPARATOR + key, display),
			insert,
			"Shortcut"
		)
		add_completion_option(script_editor, cc_dict)
	
	if keys.is_empty():
		return false
	update_completion_options(true)
	return true


## builder that returns nothing usable is reported
## and skipped rather than left to put junk in the popup.
func _call_builder(key:String, entry:Dictionary, args:PackedStringArray) -> Array:
	# build_args sizes the call for any arg count; pads to `required` and truncates to `slots`, and
	# yields [] for a zero parameter builder, where callv([]) is exactly call()
	var result = entry.build.callv(build_args(args, entry.required, entry.slots))
	if result == null:
		printerr("Code Completions - aliases: '%s' returned nothing." % key)
		return []
	if not (result is String or result is Dictionary or result is Array or result is PackedStringArray):
		printerr("Code Completions - aliases: '%s' returned non string/array/dict: %s" % [key, result])
		return []
	return builder_options(result)


## builder's return is converted from String, Array or dict, to proper array form
static func builder_options(result) -> Array:
	var out := []
	if result is String or result is Dictionary:
		result = [result]
	elif not (result is Array or result is PackedStringArray):
		return out
	for option in result:
		if option is Dictionary:
			var row = normalize_row(option)
			if not row.is_empty():
				out.append(row)
			continue
		var text = str(option).rstrip("\n")
		if text != "":
			out.append(text)
	return out

## fills a builder's row dict out to get_code_complete_dict_static's shape. 
static func normalize_row(row:Dictionary) -> Dictionary:
	var insert = str(row.get(&"insert_text", "")).rstrip("\n")
	var display = str(row.get(&"display_text", insert))
	if insert == "":
		insert = display
	if display == "" and insert == "":
		return {}
	var out = row.duplicate()
	out[&"display_text"] = display
	out[&"insert_text"] = insert
	out[&"kind"] = row.get(&"kind", CodeEdit.KIND_PLAIN_TEXT)
	out[&"font_color"] = row.get(&"font_color", Helpers.Colors.DEFAULT_COMPLETION)
	out[&"icon"] = row.get(&"icon", null)
	out[&"default_value"] = row.get(&"default_value", null)
	out[&"location"] = row.get(&"location", 1024)
	return out


## Offers the names in scope for the argument being typed. Returns whether anything matched
func _add_name_options(script_editor:CodeEdit, caret_context:CaretContext, closed:String, open_arg:String) -> bool:
	var added = false
	var names = _collect_names(caret_context)
	for name:String in names:
		# containsn, not begins_with: "alia" has to reach a private "_aliases". An empty segment is
		# a freshly closed slot, so everything in scope is a candidate.
		if open_arg != "" and not name.containsn(open_arg):
			continue
		var data:Dictionary = names[name]
		var cc_dict = get_code_complete_dict(
			data.kind,
			make_name_display(closed, name),
			make_name_insert(closed, name),
			"property", null, maxi(data.location, 1)
		)
		add_completion_option(script_editor, cc_dict)
		added = true
	return added

## collect variables
func _collect_names(caret_context:CaretContext) -> Dictionary:
	var out := {}
	var class_obj = caret_context.get_current_class_object()
	if is_instance_valid(class_obj):
		var members = Helpers.collect_type_members(self, class_obj.get_script_class_path(),
				Helpers.MemberFilter.PROPERTIES, true)
		for name in members:
			if not out.has(name):
				out[name] = members[name]
	
	var func_obj = caret_context.get_current_func_object()
	if is_instance_valid(func_obj):
		for name in func_obj.get_in_scope_local_vars(caret_context.caret_line):
			out[name] = {&"kind": CodeEdit.KIND_VARIABLE, &"location": CodeEdit.LOCATION_LOCAL}
	return out


func _reload_if_changed() -> void:
	var dir = _alias_dir.strip_edges()
	if dir == "":
		return
	var dirty = false
	var files = DirAccess.get_files_at(dir)
	for f in files:
		if f.get_extension() != "gd":
			continue
		var path = dir.path_join(f)
		var mtime = FileAccess.get_modified_time(path)
		if mtime != modified_times.get(path, 0):
			dirty = true
		modified_times[path] = mtime
	
	if not dirty and not _aliases.is_empty():
		return
	
	
	_aliases.clear()
	var errors := []
	for f in files:
		if f.get_extension() != "gd":
			continue
		var path = dir.path_join(f)
		if FileAccess.file_exists(path):
			var script = load(path)
			if script is Script:
				errors.append_array(collect_script_aliases(script, _aliases))
			else:
				errors.append("%s is not a script." % path.get_file())
	
	for error in errors:
		printerr("Code Completions - aliases: %s" % error)


## const entry: fixed text, so there are no arguments and nothing to substitute.
static func options_entry(options:Array[String]) -> Dictionary:
	var data = {&"options": options, &"build": null, &"slots": 0, &"required": 0,
			&"arg_names": PackedStringArray()}
	# only first one will be scanned, not sure required actually does anything here...
	if options.size() == 1:
		data[&"slots"] = options[0].count("%s")
		data[&"required"] = 1 if data[&"slots"] > 0 else 0
	else:
		var running_slot_count = 0
		var slot_mismatch:=false
		for o in options:
			var slot_count = o.count("%s")
			if slot_count > 0:
				if running_slot_count != 0 and running_slot_count != slot_count:
					slot_mismatch = true
				if slot_count > running_slot_count:
					running_slot_count = slot_count
		
		data[&"slots"] = running_slot_count
		data[&"required"] = running_slot_count
		# unused: not sure how to factor, default to highest
		if slot_mismatch:
			pass
	
	return data

## builder entry: parameter names drives hints, and their count is the slot count
static func builder_entry(build:Callable, arg_names:PackedStringArray, required:int) -> Dictionary:
	return {&"options": [] as Array[String], &"build": build, &"slots": arg_names.size(),
			&"required": required, &"arg_names": arg_names}


## script members(static) are the entries: NAME is the key and its kind decides the shape
## private(_) funcs are skipped, non string/array const are skipped
static func collect_script_aliases(script:Script, out:Dictionary) -> Array:
	var errors = []

	var constants = script.get_script_constant_map()
	for name:String in constants:
		if name.begins_with(HELPER_PREFIX):
			continue
		var value = constants[name]
		var texts:Array[String] = []
		if value is String:
			texts.append(value)
		elif value is Array:
			for option in value:
				if option is String and option != "":
					texts.append(option)
		else:
			continue # data table, preload, number - not an alias
		if texts.is_empty():
			continue
		
		out[name] = options_entry(texts)

	for method:Dictionary in script.get_script_method_list():
		var name:String = method.get("name", "")
		if name.begins_with(HELPER_PREFIX) or not UNode.has_static_method_compat(name, script):
			continue
		var args:Array = method.get("args", [])
		var defaults:Array = method.get("default_args", [])
		# the real parameter names, which is what both hints show
		var arg_names := PackedStringArray()
		for arg:Dictionary in args:
			arg_names.append(arg.get("name", ""))
		if out.has(name):
			errors.append("'%s' is both a constant and a function; the function wins." % name)
		out[name] = builder_entry(Callable(script, name), arg_names, args.size() - defaults.size())

	return errors


## Maps arguments onto builder(func) parameters. Default params are not passed, required
## are populated with PLACEHOLDER if not present
static func build_args(args:PackedStringArray, required:int, slots:int) -> Array:
	var out := []
	for arg in args:
		out.append(arg)
	if not out.is_empty() and out[-1] == "":
		out.remove_at(out.size() - 1)
	while out.size() < required:
		out.append(PLACEHOLDER)
	out.resize(mini(out.size(), slots))
	for i in out.size():
		out[i] = resolve_arg(out[i])
	return out

## filter for bare "/"
static func keys_starting_with(aliases:Dictionary, prefix:String) -> PackedStringArray:
	var out := PackedStringArray()
	for key:String in aliases:
		if key.to_lower().begins_with(prefix.to_lower()):
			out.append(key)
	out.sort()
	return out


## most specific key the expression starts with. longest not first so file order doesn't matter
static func longest_key(aliases:Dictionary, expression:String) -> String:
	var best = ""
	for key:String in aliases:
		if expression.begins_with(key) and key.length() > best.length():
			best = key
	return best

## "" -> PLACEHOLDER, _ -> ""
static func resolve_arg(typed:String) -> String:
	if typed == "":
		return PLACEHOLDER
	if typed == BLANK_ARG:
		return ""
	return typed

## positional args from text past key. leading separator is optional: "fl/i/aliases" and "fli/aliases" both give ["i", "aliases"].
static func split_args(typed:String) -> PackedStringArray:
	if typed == "":
		return PackedStringArray()
	return typed.trim_prefix(ARG_SEPARATOR).split(ARG_SEPARATOR)

## splits the typed text at the last separator ('/'): [resolved_args, arg_being_typed]
## empty means no separator
static func split_open_arg(typed:String) -> PackedStringArray:
	var slash = typed.rfind(ARG_SEPARATOR)
	if slash == -1:
		return PackedStringArray()
	return PackedStringArray([typed.substr(0, slash + 1), typed.substr(slash + 1)])

## `closed` is the alias key, so the row reads "(fl/i/) _aliases". prefix keeps display filtering with match
static func make_name_display(closed:String, name:String) -> String:
	return "(%s) %s" % [closed, name]

## trailing separator closes the argument, re-triggers completion for the next one
static func make_name_insert(closed:String, name:String) -> String:
	return closed + name + ARG_SEPARATOR

# ALERT use for the simple text setup
## A trailing separator leaves an empty final element, so the raw size overstates what was actually
## given - "forloop/i/" is one argument, not two.
static func filled_arg_count(args:PackedStringArray) -> int:
	var count = 0
	for arg in args:
		if arg != "":
			count += 1
	return count

# ALERT this is unused here, but is used in the tests
## arg text past the key with the separator that introduces it removed - "/" alone means the
## list was opened but nothing supplied, which has to read the same as nothing typed at all.
static func arg_text(typed:String) -> String:
	return typed.trim_prefix(ARG_SEPARATOR)

## Splits argument text into the part the alias consumes (arg counts) and any excess, as [consumed, rest].
static func split_consumed(typed:String, slots:int) -> PackedStringArray:
	# the separator that opened the list belongs to the consumed part: "/icon/" reads as "arguments
	# opened", so it has to sit in the prefix or the typed run stops matching
	var consumed = ARG_SEPARATOR if typed.begins_with(ARG_SEPARATOR) else ""
	var rest = typed.substr(consumed.length())
	var taken = 0
	while taken < slots and rest != "":
		var next = rest.find(ARG_SEPARATOR)
		if next == -1:
			consumed += rest
			rest = ""
		else:
			consumed += rest.substr(0, next + 1)
			rest = rest.substr(next + 1)
		taken += 1
	
	return PackedStringArray([consumed, rest])

## param as both hints write it; prefized when it has a default
static func _arg_label(arg_names:PackedStringArray, index:int, required:int) -> String:
	return arg_names[index] if index < required else "?:%s" % arg_names[index]

## The browse row's argument hint, read from the signature: "(/setget) (name/?:type)"
static func make_arg_hint(arg_names:PackedStringArray, slots:int, required:int) -> String:
	var out = ""
	if arg_names.is_empty():
		if slots > 0:
			return "(%s placeholders)" % slots
		return ""
	for i in arg_names.size():
		out += ARG_SEPARATOR + _arg_label(arg_names, i, required)
	return "(%s)" % out.trim_prefix("/")

## which argument is being typed. split_args normalises optional leading separator, simply the last element - "" and "/" are both argument 0.
static func open_arg_index(typed:String) -> int:
	return maxi(split_args(typed).size() - 1, 0)

## HINT_MARKER delimits the highlighted run for CodeEdit, which strips both before drawing
static func make_code_hint(key:String, arg_names:PackedStringArray, required:int, index:int) -> String:
	var parts := PackedStringArray()
	for i in arg_names.size():
		var part = _arg_label(arg_names, i, required)
		parts.append(HINT_MARKER + part + HINT_MARKER if i == index else part)
	return "%s(%s)" % [key, ", ".join(parts)]

## must include prefix with current valid text, otherwise get's filtered
static func make_display(prefix:String, insert:String) -> String:
	var first = insert.get_slice("\n", 0)
	if first.length() > DISPLAY_MAX:
		first = first.substr(0, DISPLAY_MAX).rstrip(" \t") + ELLIPSIS
	elif insert.contains("\n"):
		first += " " + ELLIPSIS
	return "(%s) %s" % [prefix, first]


## Multi line inserts land verbatim, so every line past the first needs the caret line's indent.
static func apply_indent(text:String, indent:String) -> String:
	if indent == "" or not text.contains("\n"):
		return text
	var lines = text.split("\n")
	for i in range(1, lines.size()):
		if lines[i] == "":
			continue
		lines[i] = indent + lines[i]
	return "\n".join(lines)

static func get_line_indent(line_text:String) -> String:
	return line_text.substr(0, line_text.length() - line_text.lstrip(" \t").length())


class EditorSet:
	const ENABLE = &"plugin/code_completion/alias/enable"
	const DIRECTORY = &"plugin/code_completion/alias/directory"
	
	static func get_dir():
		var ed_set = EditorInterface.get_editor_settings()
		return ed_set.get_setting(DIRECTORY)




class ExampleAlias:
	static func write_file(force_write:bool=false):
		var dir = EditorSet.get_dir()
		if not force_write and DirAccess.dir_exists_absolute(dir):
			return
		var path = dir.path_join("aliases.gd")
		if not FileAccess.file_exists(path):
			var def_path = "res://addons/code_completions/src/class/default_alias.gd" #! ensure_path
			DirAccess.make_dir_recursive_absolute(dir)
			var f = FileAccess.open(path, FileAccess.WRITE)
			f.store_string(TEXT % def_path)
			f.close()
	
	
	const TEXT:String = \
"""
## aliases are defined in a script inside the aliases folder (editor settings)
## constants that are String or Array are gathered and used directly.
## placeholders (% style) can be used and will be subbed automatically
## member_name/arg/arg - this is the format to pass placeholders to 
## the member's text

## for more advanced usage, you can use a function. Args defined as above
## are passed to the function. Can return: String, Array, Dictionary
## Dictionary should be code completion shape, you can use 
## EditorCodeCompletion.get_code_complete_static() to create the dict.

const example_arr := ["option1", "option2"]
const ready := "func _ready() -> void:\n\tpass"


#region Builtins
const DefaultAliases = preload("%s")

static func fori(collection):
	return DefaultAliases.fori(collection)
static func forib(collection):
	return DefaultAliases.forib(collection)
static func forloop(iterator:String, collection:String):
	return DefaultAliases.forloop(iterator, collection)

static func icon():
	return DefaultAliases.icon()
static func edicon():
	return DefaultAliases.edicon()

static func setget(name, type:= "int") -> String:
	return DefaultAliases.setget(name, type)
static func drop(name:String):
	return DefaultAliases.drop(name)

#endregion"""
