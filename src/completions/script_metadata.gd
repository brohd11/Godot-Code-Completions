extends EditorCodeCompletion

const CacheHelper = preload("res://addons/addon_lib/brohd/alib_runtime/cache_helper/cache_helper.gd")

const TagParserBase = preload("res://addons/code_completions/src/completions/script_metadata/tag_parsers/base/tag_parser_base.gd")

#const ArgLocation = preload("res://addons/code_completions/src/completions/script_metadata/tag_parsers/arg_location.gd")
#const StructDict = preload("res://addons/code_completions/src/completions/script_metadata/tag_parsers/struct_dict.gd")

var parsers:Dictionary[String, TagParserBase] = {}

var meta_regex:RegEx
var member_regex:RegEx

var _cache = {}

func _singleton_ready() -> void:
	_instance_parsers()

func _instance_parsers():
	var parser_array = [
		#ArgLocation,
		#StructDict
	]
	for p in parser_array:
		var ins = p.new()
		if not "TAG" in p:
			printerr("Script Metadata: Parser '%s' should have 'TAG' defined." % p)
			continue
		parsers[p.TAG] = ins
		ins.script_metadata = self

func _get_completion_settings() -> Dictionary:
	return {
		"priority": 1,
	}

func _on_editor_script_changed(script):
	pass

func _on_code_completion_requested(script_editor:CodeEdit) -> bool:
	
	for p in parsers.values():
		var handled = p.code_completion_requested(script_editor)
		if handled:
			return true
	
	#test_method()
	#test_method()
	return false

func get_script_metadata(path:String):
	var current_script = get_current_script()
	var is_current_script = path == current_script.resource_path
	if not is_current_script:
		var cached_data = CacheHelper.get_cached_data(path, _cache)
		#if cached_data != null:
			#return cached_data
	
	print("GET SCRTIP META::", path)
	var parser:GDScriptParser = get_gdscript_parser()
	if is_current_script:
		parser = get_gdscript_parser()
	else:
		parser = parser.get_parser_for_path(path)
	
	var metadata = parse_script_metadata(parser)
	CacheHelper.store_data(path, metadata, _cache, [path])
	return metadata


func parse_script_metadata(gdscript_parser: GDScriptParser) -> Dictionary:
	var metadata_cache = {}
	
	# Captures "arg_location" as 'tag' and "line:Keys context:SubSpace" as 'args'
	if not is_instance_valid(meta_regex):
		meta_regex = RegEx.new()
		meta_regex.compile("^\\s*#!\\s*(?<tag>\\w+)(?:\\s+(?<args>.*))?$")

	# Captures the keyword (func/var/const/signal) as 'type' and the name as 'name'.
	# It safely ignores any @ annotations or 'static' keywords before it.
	if not is_instance_valid(member_regex):
		member_regex = RegEx.new()
		member_regex.compile("^\\s*(?:@[a-zA-Z0-9_]+(?:\\([^)]*\\))?\\s*)*(?:static\\s+)?(?<type>func|var|const|signal|class)\\s+(?<name>\\w+)")
	
	#if not gdscript_parser:
		#return {}
	var code_edit_parser = gdscript_parser.code_edit_parser
	
	# pending_tags format: {"tag_name": "args string"}
	var pending_tags = {}
	#var source_code_lines = source_code.split("\n")
	
	for i in range(code_edit_parser.code_edit.get_line_count()):
		var line = code_edit_parser.get_line(i)
		# 1. Check for Meta Tags
		var meta_match = meta_regex.search(line)
		if meta_match:
			var tag = meta_match.get_string("tag")
			var args = meta_match.get_string("args").strip_edges()
			
			# If a tag is used multiple times on the same member, append with a space
			if pending_tags.has(tag):
				pending_tags[tag] += " " + args
			else:
				pending_tags[tag] = args
			continue
			
		# 2. Check for Member Declarations (func, var, const, etc.)
		var member_match = member_regex.search(line)
		if member_match:
			if not pending_tags.is_empty():
				var class_access_path = gdscript_parser.get_class_at_line(i)
				var member_name = UString.dot_join(class_access_path, member_match.get_string("name"))
				
				
				# NOTE: You mentioned you have your own inner-class handling logic.
				# You would apply your "member_name" path logic here. 
				# e.g., if inside an inner class: member_name = "InnerClass." + member_name
				
				# Process each collected tag
				for tag in pending_tags.keys():
					if parsers.has(tag):
						var raw_args = pending_tags[tag]
						var tag_parser = parsers.get(tag) as TagParserBase
						var parsed_data = tag_parser.parse_tag(raw_args)
						
						# Ensure the tag category exists in the root cache
						if not metadata_cache.has(tag):
							metadata_cache[tag] = {}
							
						# Store the data under the member name
						metadata_cache[tag][member_name] = parsed_data
					else:
						pass
						#push_warning("Script Metadata: No parser defined for tag: #! " + tag)
				
				# Clear pending tags for the next member
				pending_tags.clear()
			continue
			
		# 3. Code/Comment Reset Rule
		var stripped = line.strip_edges()
		if not stripped.begins_with("#") and not stripped.is_empty():
			# We hit standard code, so clear any floating tags that 
			# didn't attach to a recognized member to prevent misattribution.
			pending_tags.clear()

	return metadata_cache
