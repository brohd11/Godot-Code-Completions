# Godot Code Completions

This plugin provides a class with hooks to trigger a code completion request in the Godot script editor. You can create your own or there are some built ins you can use.

### Install
Download the package in releases, and unzip into addons/.

Optional dependency: [Tree-sitter](https://github.com/brohd11/Godot-TreeSitter-Wrapper) used by the underlying parser. Increases performance, but not necessary to function.

Alternatively, you can use: [gdaddon - Addon Manager](https://github.com/brohd11/gdaddon) to install and manage plugins and their dependencies.

### Setup
After install, some of the features are off by default. the settings can be found in EditorSettings -> plugin/code_completion/.

Ensure the EditorSettings advanced settings toggle is on if you can’t see them.


## Built-In Completions
All of these completions are toggleable.

 - hide private - when accessing a member, hide names with leading underscore
 - new - classes have “Class.new()” as a suggestion
 - enum - if a member, or argument is typed as an enum, finds the enum and lists the members
 - extended type hints - the editor doesn’t handle preloaded types in every situation, attempts to extend to all valid places
 - const key - when defining a const string, suggests strings based on const name, and location in script
 - alias - user defined shorthands, read from `aliases.yml` in the directory set by `plugin/code_completion/alias/directory` (default `res://aliases/`; point it at a directory with neither file present and the feature does nothing). Each `key: replacement` pair offers `(key) replacement` in the popup once the key is fully typed, and inserts the replacement alone. Values may be multi-line YAML block scalars, in which case the popup shows a truncated first line and the insert is re-indented to the caret line. The file is reloaded whenever the filesystem changes; a missing file is a no-op. A value containing `%s` is a template — text typed past the key fills every `%s`, so `setgetmyvar` offers the `setget` snippet already named `myvar`, and the bare key substitutes `placeholder`. A lone `_` past the key substitutes empty, for templates whose variable part is usually absent (`dropdata_` → `_get_drop_data`, `dropdataon_control_` → `_on_control_get_drop_data`); any other argument, including a leading-underscore private name, is taken verbatim. `/` separates positional arguments (`forloop/i/aliases` → `for i in range(aliases.size())`); a list shorter than the placeholder count repeats its last entry, so a template whose slots all want the same string still works from one argument. While an argument is open (`forloop/i/alia`) the popup offers names in scope instead — locals, function arguments and the class's properties — and accepting one closes the argument and re-triggers, so `forloop/i/alia` → `forloop/i/_aliases/` → the finished snippet.

   For anything a template can't express, add `aliases.gd` beside the yml. Every member of that script is an alias and the member **name** is the key: a `const` string is one option, a `const` array is several, and a `static func` is a builder whose return value is the inserted text. Anything else is invisible — constants that aren't strings or arrays (preloads, data tables) and any name starting with `_`. A builder's signature is its contract: the parameter count is the argument count and default values fill arguments you haven't typed, so `static func setget(name, type := "int")` takes two arguments and reports `(expects 2)` with nothing to declare. Keys in the script win over the same key in the yml. There is no escape for a literal `%s` in a snippet
 - member string - completes method and property names written as string arguments: `call("…")`, `set_deferred("…")`, `has_method("…")`, `rpc("…")`, `Callable(obj, "…")`. Resolves the receiver through variables and user scripts, and reads it from argument 0 where that's the object. `set_indexed`/`get_indexed`/`tween_property` also complete property paths past the colon (`"modulate:a"`)

### Tag based
 - dict key - define keys for dictionaries, they will be suggested in a variety of scenarios
 - arg location - define a location to list constants as arguments
 - import (WIP) - tag preloads and global classes to have static functions and constants listed. The insert is “Class.my_static_member"
 - tag parser - completes registered tags, such as for dict key, tags can be registered by plugins



## Custom Completions
It is easy to add your own by creating a class that extends `EditorCodeCompletion`, then instancing it in your plugin.
### More details on usage [here.](export_ignore/doc/editor_code_completion.md)

## Example Images

### Enum
![enum](export_ignore/doc/enum.jpg)

### Dict Key
![dict](export_ignore/doc/dict_key.jpg)

### Import
![import](export_ignore/doc/import.jpg)