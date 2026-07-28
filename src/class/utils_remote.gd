#! remote

const UClassDetail = preload("uid://gyx3o6jv751x") #! resolve ALibEditor.Utils.UClassDetail
const UString = preload("uid://cwootkivqiwq1") #! resolve ALibRuntime.Utils.UString
const USort = preload("uid://dtrbpu04wxss0") #! resolve ALibRuntime.Utils.USort
const UTexture = preload("uid://ddu76iygjkxih") #! resolve ALibRuntime.Utils.UTexture
const UNode = preload("uid://dsywt12xnn7oh") #! resolve ALibRuntime.Utils.UNode

const EditorColors = preload("uid://bhb1vgeh8ibjq") #! resolve ALibEditor.Colors
const EditorGDScriptParser = preload("uid://t2dewmuth0sy") #! resolve ALibEditor.Singleton.EditorGDScriptParser
const TagParser = preload("uid://gmbyxd0dnujb") #! resolve ALibEditor.Singleton.TagParser

const CacheHelper = preload("res://addons/addon_lib/brohd/alib_runtime/cache_helper/cache_helper.gd")
const YAMLParser = preload("uid://c72xsbxjoy2kl") # addons/addon_lib/yaml_parser/yaml.gd
const SettingHelperEditor = preload("uid://c4l4v4eufkmtx") #! resolve ALibEditor.Settings.SettingHelperEditor
