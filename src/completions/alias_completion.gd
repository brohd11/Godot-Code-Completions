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

# CodeEdit's own delimiter for the highlighted run of a code hint; it draws the hint with these
# stripped. Written as an escape, not char(0xFFFF): a static var's initialiser doesn't run for this
# script in the editor, so the marker came back empty there while passing headless.
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
	_code_hint_line = -1 # a different script's CodeEdit never carried our hint
	_reload_if_changed()

func _clear_code_hint(script_editor:CodeEdit) -> void:
	if _code_hint_line == -1:
		return
	#if _code_hint_line == script_editor.get_caret_line():
	script_editor.set_code_hint("")
	_code_hint_line = -1

## only applies to funcs
func _set_code_hint(script_editor:CodeEdit, key:String, entry:Dictionary, typed:String) -> void:
	if entry.arg_names.is_empty():
		return
	script_editor.set_code_hint(make_code_hint(key, entry.arg_names, entry.required,
			open_arg_index(typed)))
	script_editor.set_code_hint_draw_below(false) # the popup owns the space below
	_code_hint_line = script_editor.get_caret_line()

func _on_code_completion_requested(script_editor:CodeEdit) -> bool:
	# above every early return: a hint set on the last request has to go the moment the expression
	# stops being an alias, and most of the ways that happens leave here without reaching the body
	_clear_code_hint(script_editor)
	if not _enable or _aliases.is_empty():
		return false
	var caret_context = get_caret_context()
	if caret_context.token_state != TokenState.NONE:
		return false
	if caret_context.expression_state == ExpressionState.MEMBER_ACCESS:
		return false
	
	var expression = caret_context.expression_before_caret
	if expression == "":
		return false
	# the separator is the only way in - without it the provider is inert, which keeps ordinary words
	# like "for" or "export" from consuming the request at priority 2
	if not expression.begins_with(ARG_SEPARATOR):
		return false
	var lookup = expression.substr(ARG_SEPARATOR.length())

	var key = longest_key(_aliases, lookup)
	if key == "":
		# nothing to invoke, so offer the keys still reachable from what has been typed
		return _add_menu_options(script_editor, lookup)

	var indent = get_line_indent(caret_context.current_line_text)
	var entry:Dictionary = _aliases[key]
	var typed = lookup.substr(key.length())
	var args = split_args(typed)
	var matched = false
	
	# what the user actually typed, which is what Godot filters the display against and what an
	# insert has to reproduce - the stored key carries no separator, the buffer does
	var display_key = ARG_SEPARATOR + key
	# only the arguments the alias CONSUMES join the prefix; anything past them stays out so it has
	# to match a row's body, which is what keeps "/iconact" narrowing a zero argument builder
	var prefix = display_key + split_consumed(typed, entry.slots)[0]
	
	# a builder's parameter count; a const has none
	var max_slots:int = entry.slots
	
	_set_code_hint(script_editor, key, entry, typed)

	# candidates belong to the KEY, not to an option - the argument being typed is the same for
	# every one of them, so collecting per option would just duplicate the rows
	if max_slots > 0:
		var open_parts = split_open_arg(typed)
		if not open_parts.is_empty():
			var closed = display_key + open_parts[0]
			# names never replace the finished completion any more - it is always offered too, so
			# there is always something to accept no matter how many arguments are filled
			if open_parts[1] != "":
				matched = _add_name_options(script_editor, caret_context, closed, open_parts[1])
			elif typed.contains(ARG_SEPARATOR) and filled_arg_count(args) < max_slots:
				matched = _add_name_options(script_editor, caret_context, closed, "")
	
	if entry.build is Callable:
		# an empty result just adds no rows - returning here would orphan any name options already
		# added above, leaving them in the popup with the request unconsumed
		for row in _call_builder(key, entry, args):
			var cc_dict:Dictionary
			if row is Dictionary:
				# the builder owns the body; the prefix stays ours, since it carries the typed run
				cc_dict = row
				cc_dict[&"display_text"] = make_display(prefix, cc_dict[&"display_text"])
				cc_dict[&"insert_text"] = apply_indent(cc_dict[&"insert_text"], indent)
			else:
				cc_dict = get_code_complete_dict(CodeEdit.KIND_PLAIN_TEXT,
						make_display(prefix, row),
						apply_indent(row, indent), "Shortcut", null, CodeEdit.LOCATION_LOCAL)
			add_completion_option(script_editor, cc_dict)
			matched = true
	# a const is fixed text with no arguments, so anything typed past the key isn't ours to answer.
	# arg_text, not typed: a lone separator means the list was opened and nothing supplied, which is
	# not foreign text - menu inserts always end in one
	elif arg_text(typed) == "":
		for text:String in entry.options:
			var cc_dict = get_code_complete_dict(
				CodeEdit.KIND_PLAIN_TEXT,
				make_display(prefix, text),
				apply_indent(text, indent),
				"Shortcut", null, CodeEdit.LOCATION_LOCAL)
			add_completion_option(script_editor, cc_dict)
			matched = true

	if not matched:
		return false

	update_completion_options(true)
	return true


## The keys still reachable from what has been typed, one row each. Deliberately does NOT expand the
## aliases: that would mean calling every builder, and icon/iconed produce ~1000 rows apiece, so a
## bare separator would list thousands. Returns whether anything was added.
func _add_menu_options(script_editor:CodeEdit, prefix:String) -> bool:
	
	var keys = keys_starting_with(_aliases, prefix)
	for key:String in keys:
		var entry:Dictionary = _aliases[key]
		var single = entry.options.size() == 1 and entry.slots == 0
		# the hint goes AFTER the key so a partly typed key still matches the display contiguously
		var display = " -> " + entry.options[0] if single \
				else make_arg_hint(entry.arg_names, entry.required)
		var insert:String = entry.options[0] if single else make_menu_insert(key)
		var cc_dict = get_code_complete_dict(CodeEdit.KIND_PLAIN_TEXT,
				make_display(ARG_SEPARATOR + key, display),
				insert, "Shortcut")
		add_completion_option(script_editor, cc_dict)
	
	if keys.is_empty():
		return false
	update_completion_options(true)
	return true


## A user script can be edited into any state, so a builder that returns nothing usable is reported
## and skipped rather than left to put junk in the popup.
func _call_builder(key:String, entry:Dictionary, args:PackedStringArray) -> Array:
	# build_args sizes the call for any arity - it pads to `required` and truncates to `slots`, and
	# yields [] for a zero parameter builder, where callv([]) is exactly call()
	var result = entry.build.callv(build_args(args, entry.required, entry.slots))
	if result == null:
		printerr("Code Completions - aliases: '%s' returned nothing." % key)
		return []
	if not (result is String or result is Dictionary or result is Array or result is PackedStringArray):
		printerr("Code Completions - aliases: '%s' returned non string/array/dict: %s" % [key, result])
		return []
	return builder_options(result)


## A builder's return as rows: one for a string, one per element for an array. An element may be a
## dict in get_code_complete_dict_static's shape, which is how a long insert carries a short display
## - Godot scores the typed run against display_text, and boilerplate in front of the distinguishing
## part wrecks it. A trailing break would drop the caret onto a blank line, and empty rows are
## dropped, both the way parse_aliases does it.
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

## Fills a builder's row dict out to get_code_complete_dict_static's shape. add_completion_option
## reads all seven keys by dot access, so every one has to be present or a partial dict fails the
## call. Returns {} when there is nothing to show, so the caller can drop it.
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


## Offers the names in scope for the argument being typed. Returns whether anything matched - a miss
## falls back to the ordinary snippet row rather than consuming the request for an empty popup.
func _add_name_options(script_editor:CodeEdit, caret_context:CaretContext, closed:String, open_arg:String) -> bool:
	var added = false
	var names = _collect_names(caret_context)
	for name:String in names:
		# containsn, not begins_with: "alia" has to reach a private "_aliases". An empty segment is
		# a freshly closed slot, so everything in scope is a candidate.
		if open_arg != "" and not name.containsn(open_arg):
			continue
		var data:Dictionary = names[name]
		# never 0: the finished completion sits at LOCATION_LOCAL and should out-sort the names
		var cc_dict = get_code_complete_dict(data.kind, make_name_display(closed, name),
				make_name_insert(closed, name), "property", null, maxi(data.location, 1))
		add_completion_option(script_editor, cc_dict)
		added = true
	return added

## Locals (which already carry the function's arguments) shadow the class's properties.
func _collect_names(caret_context:CaretContext) -> Dictionary:
	var out := {}
	var func_obj = caret_context.get_current_func_object()
	if is_instance_valid(func_obj):
		for name in func_obj.get_in_scope_local_vars(caret_context.caret_line):
			out[name] = {&"kind": CodeEdit.KIND_VARIABLE, &"location": CodeEdit.LOCATION_LOCAL}

	var class_obj = caret_context.get_current_class_object()
	if is_instance_valid(class_obj):
		# include_private: the whole point is reaching names like _aliases
		var members = Helpers.collect_type_members(self, class_obj.get_script_class_path(),
				Helpers.MemberFilter.PROPERTIES, true)
		for name in members:
			if not out.has(name):
				out[name] = members[name]
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


## A const entry: fixed text, so there are no arguments and nothing to substitute.
static func options_entry(options:Array[String]) -> Dictionary:
	return {&"options": options, &"build": null, &"slots": 0, &"required": 0,
			&"arg_names": PackedStringArray()}

## A builder entry: the signature IS the contract - the parameter names drive both hints, their
## count is the slot count, and the ones without defaults must not be left unfilled.
static func builder_entry(build:Callable, arg_names:PackedStringArray, required:int) -> Dictionary:
	return {&"options": [] as Array[String], &"build": build, &"slots": arg_names.size(),
			&"required": required, &"arg_names": arg_names}


## Members are the aliases: the member NAME is the key and its kind decides the shape. Constants that
## are neither strings nor arrays are data or preloads, so skipping them by type is what keeps
## helper tables out of the popup without any opt-out marker.
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


## Maps typed arguments onto a builder's parameters. The trailing empty element that a closing
## separator leaves behind has to go first - passing "" would override the parameter's default
## instead of letting it apply. Required parameters are padded so a call can never fail on a
## missing argument, and extras are dropped so it can never fail on too many.
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

## Keys the typed text is still a prefix OF - the browse direction, the opposite of longest_key's
## invoke direction, which is why that one can't serve the menu. An empty prefix is a prefix of
## everything, so a bare separator lists the lot.
static func keys_starting_with(aliases:Dictionary, prefix:String) -> PackedStringArray:
	var out := PackedStringArray()
	for key:String in aliases:
		if key.to_lower().begins_with(prefix.to_lower()):
			out.append(key)
	out.sort()
	return out

## A menu row completes the key, always with a trailing separator so the insert re-triggers the
## popup - an alias with no arguments needs that just as much, to show its rows.
static func make_menu_insert(key:String) -> String:
	return ARG_SEPARATOR + key + ARG_SEPARATOR

## The most specific key the expression starts with. Overlapping keys are normal once a key holds
## variants (for / fori / forib), and the longest is always the one meant - picking the first match
## instead would make the result depend on the order they happen to sit in the file.
static func longest_key(aliases:Dictionary, expression:String) -> String:
	var best = ""
	for key:String in aliases:
		if expression.begins_with(key) and key.length() > best.length():
			best = key
	return best

## "" means nothing typed past the key yet, so fall back to the visible default; a lone underscore
## is the explicit blank. Anything else - including a leading-underscore private name - is verbatim.
static func resolve_arg(typed:String) -> String:
	if typed == "":
		return PLACEHOLDER
	if typed == BLANK_ARG:
		return ""
	return typed

## Positional arguments from the text typed past the key. The leading separator is optional, so
## "forloop/i/aliases" and "forloopi/aliases" both give ["i", "aliases"].
static func split_args(typed:String) -> PackedStringArray:
	if typed == "":
		return PackedStringArray()
	return typed.trim_prefix(ARG_SEPARATOR).split(ARG_SEPARATOR)

## Splits the typed text at the last separator: everything through it is settled, what follows is
## the argument still being typed. Empty result means there is no separator to work from.
static func split_open_arg(typed:String) -> PackedStringArray:
	var slash = typed.rfind(ARG_SEPARATOR)
	if slash == -1:
		return PackedStringArray()
	return PackedStringArray([typed.substr(0, slash + 1), typed.substr(slash + 1)])

## `closed` already carries the alias key, so the row reads "(forloop/i/) _aliases". The prefix is
## load-bearing: Godot filters against the whole typed run, so a bare name would be dropped.
static func make_name_display(closed:String, name:String) -> String:
	return "(%s) %s" % [closed, name]

## The trailing separator closes the argument, which re-triggers completion for the next one.
static func make_name_insert(closed:String, name:String) -> String:
	return closed + name + ARG_SEPARATOR

## A trailing separator leaves an empty final element, so the raw size overstates what was actually
## given - "forloop/i/" is one argument, not two.
static func filled_arg_count(args:PackedStringArray) -> int:
	var count = 0
	for arg in args:
		if arg != "":
			count += 1
	return count

## Argument text past the key with the separator that introduces it removed - "/" alone means the
## list was opened but nothing supplied, which has to read the same as nothing typed at all.
static func arg_text(typed:String) -> String:
	return typed.trim_prefix(ARG_SEPARATOR)

## Splits argument text into the part the alias consumes and any excess, as [consumed, rest]. The
## prefix carries only the consumed part, so excess still has to match a row's BODY - that is what
## lets "/iconact" narrow a zero argument builder instead of matching every row on the prefix alone.
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

## A parameter as both hints write it - bracketed when it has a default. Now that nothing counts
## arguments on the typed run, this is the only place required-ness is visible.
static func _arg_label(arg_names:PackedStringArray, index:int, required:int) -> String:
	return arg_names[index] if index < required else "?:%s" % arg_names[index]

## The browse row's argument hint, read from the signature: "setget/name/[type]". The names sit AFTER
## the key so a partly typed key still matches the display contiguously.
static func make_arg_hint(arg_names:PackedStringArray, required:int) -> String:
	var out = ""
	if arg_names.is_empty():
		return ""
	for i in arg_names.size():
		out += ARG_SEPARATOR + _arg_label(arg_names, i, required)
	return " (%s)" % out.trim_prefix("/")

## Which argument is being typed. split_args already normalises the optional leading separator, so
## the open argument is simply the last element - "" and "/" are both argument 0.
static func open_arg_index(typed:String) -> int:
	return maxi(split_args(typed).size() - 1, 0)

## The signature above the popup, with the argument being typed marked. HINT_MARKER delimits the
## highlighted run for CodeEdit, which strips both before drawing.
static func make_code_hint(key:String, arg_names:PackedStringArray, required:int, index:int) -> String:
	var parts := PackedStringArray()
	for i in arg_names.size():
		var part = _arg_label(arg_names, i, required)
		parts.append(HINT_MARKER + part + HINT_MARKER if i == index else part)
	return "%s(%s)" % [key, ", ".join(parts)]

## The prefix is the typed run, contiguous, so Godot matches it as a plain substring rather than a
## scattered subsequence - a space in the middle is what made long argument runs score badly enough
## to drop out of the popup.
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
