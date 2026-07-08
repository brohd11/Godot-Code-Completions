




### Registration Methods
```gdscript
static func register_plugin(plugin:EditorPlugin) -> EditorCodeCompletionSingleton
static func unregister_plugin(plugin:EditorPlugin) -> void
```
These are called when your plugin enters and exits the tree. It simply allows the singleton to keep track of plugins referencing it, so it can clean up once all are out of scope.

Must call register before instanceing your completion.

```gdscript
func _enter_tree():
	EditorCodeCompletion.register_plugin(self)

	var my_completion = MyCompletion.new() 

func _exit_tree():
	my_completion.clean_up()
    
	EditorCodeCompletion.unregister_plugin(self)
```


## Overides

```gdscript
func _on_editor_script_changed(script) -> void:
	pass
```
Called everytime editor script changes.

---
```gdscript
func _on_code_completion_requested(script_editor:CodeEdit) -> bool:
	return false
```
Called everytime a completion is requested
If a higher priority completion consumes the event (returns true via this func), this will not be reached. Only one completion can fire per cycle.

---
```gdscript
func _get_completion_settings() -> Dictionary:
	return {
		"priority": 100,
	}
```
Provide settings for the Singleton.
Currently the only setting is priority. Which determine which completion is checked first each cycle.

---
```gdscript 
func _singleton_ready() -> void:
	pass
```
`_init()` is a reserved function, overide this to if you need an init logic.

---
```gdscript
func register_editor_settings(settings_helper:SettingHelperEditor):
	settings_helper.subscribe_property(self, &"my_prop", &"editor/setting/path", "default_value")
```

For syncing to EditorSettings
Convenient method to keep properties in sync. Automatically checked everytime editor settings changes.

---


## Utilities
```gdscript

## Returns CaretContext object, has information such as current function, class, token state, etc.
func get_caret_context() -> CaretContext

## Returns current script editor's script resource
func get_current_script() -> GDScript

## Returns current script editor's code edit
func get_code_edit() -> CodeEdit

## Create a code completion dictionary for adding to options.
## Same format as the editor's completions, they can be mixed.
func get_code_complete_dict(kind, display_text, insert_text, icon_name, default_value, location, font_color) -> Dictionary

## Add the above completion to script editor.
func add_completion_option(script_editor:CodeEdit, option_dict:Dictionary) -> void

## Update the completion list
func update_completion_options(force:=false)

## Get the current GDScriptParser object
func get_gdscript_parser(path:="") -> GDScriptParser

## Get a string map of the text. StringMap includes string state map, bracket map, etc.
func get_string_map(text:String) -> UString.StringMap

## Register a comment tag to the singleton. These will be displayed for the prefix.
## Most use ‘#!’, but you can use others. 
func register_tag(prefix:String, tag:String, location:=TagLocation.ANY)
```