@tool

signal connected()
signal packet_received(packet:PackedByteArray)

var stream:StreamPeerTCP
var is_connected:bool = false
var json_rpc := JSONRPC.new()


func _init() -> void:
	var absolute_path_to_project = _get_uri("res://")
	connected.connect(func():
		print("CONNECTED")
		var request = json_rpc.make_request("initialize", {
			processId = null,
			rootUri = absolute_path_to_project, # starting with file:/// 
			capabilities = {}
		}, 0)
		print(JSON.stringify(request))
		_make_request(request)
	)
	#packet_received.connect(func(packet:PackedByteArray):
		#print("Packet!")
		#print(packet.get_string_from_utf8())
	#)
	is_connected = false
	var editor_settings = EditorInterface.get_editor_settings()
	var host = editor_settings.get_setting("network/language_server/remote_host")
	var port = editor_settings.get_setting("network/language_server/remote_port")
	stream = StreamPeerTCP.new()
	stream.connect_to_host(host, port)
	stream.set_no_delay(true) #^ try it


func disconnect_lsp() -> void:
	if stream:
		stream.disconnect_from_host()
		stream = null

	for connection in connected.get_connections():
		connected.disconnect(connection.callable)

	for connection in packet_received.get_connections():
		packet_received.disconnect(connection.callable)


func process() -> void:
	var status = stream.get_status()
	match status:
		StreamPeerTCP.STATUS_NONE:
			return
		StreamPeerTCP.STATUS_ERROR:
			print("ERROR!")
		_:
			if stream.poll() == OK:
				var available_bytes = stream.get_available_bytes()
				if available_bytes > 0:
					var data = stream.get_data(available_bytes)
					if data[0] == OK:
						packet_received.emit(data[1])
					else:
						print("Error when getting data: %s" % error_string(data[0]))
			else:
				print("Failed to poll()")
			
			if not is_connected and status == StreamPeerTCP.STATUS_CONNECTED:
				is_connected = true
				connected.emit()

func current_did_open():
	var script = ScriptEditorRef.get_current_script()
	var code_edit = ScriptEditorRef.get_current_code_edit()
	_did_open(script.resource_path, code_edit.text)

func _did_open(file_path:String, text:String) -> void:
	var uri = _get_uri(file_path)
	var request = json_rpc.make_request("textDocument/didOpen", {
		"textDocument": {
			"uri": uri,
			"languageId": "gdscript",
			"version": 4,
			"text": text
		}}, 0)
	_make_request(request)

func current_hover(caret_line:int, caret_col:int):
	var script = ScriptEditorRef.get_current_script()
	_hover(script.resource_path, caret_line, caret_col)

func _hover(file_path:String, caret_line:int, caret_col:int) -> void:
	var uri = _get_uri(file_path)
	var request = json_rpc.make_request("textDocument/resolve", {
		"textDocument": {"uri": uri},
		"position": {"line": caret_line, "character": caret_col}
	}, 0)
	_make_request(request)


func _make_request(request:Dictionary) -> void:
	var json = JSON.stringify(request)
	var length = json.to_utf8_buffer().size()
	var content = """Content-Length: {length}\r\n\r\n{json}""".format({
		length = length,
		json = json
	})
	var packet = content.to_utf8_buffer()
	var result = stream.put_data(packet)

func _get_uri(file_path:String) -> String:
	return "file://" + ProjectSettings.globalize_path(file_path)
