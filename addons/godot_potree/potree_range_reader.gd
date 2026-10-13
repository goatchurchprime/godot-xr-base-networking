class_name PotreeRangeReader
extends Node

func read(source: String, byte_offset := -1, byte_size := -1) -> Dictionary:
	if source.begins_with("http://") or source.begins_with("https://"):
		return await _read_http(source, byte_offset, byte_size)
	return _read_file(source, byte_offset, byte_size)

func _read_file(source: String, byte_offset: int, byte_size: int) -> Dictionary:
	var path := source.trim_prefix("file://")
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		return {"error": "cannot open %s: %s" % [source, error_string(FileAccess.get_open_error())], "data": PackedByteArray()}
	if byte_offset >= 0:
		if byte_offset > file.get_length():
			return {"error": "byte range begins beyond end of %s" % source, "data": PackedByteArray()}
		file.seek(byte_offset)
	var count := byte_size if byte_size >= 0 else file.get_length() - file.get_position()
	var data := file.get_buffer(count)
	if data.size() != count:
		return {"error": "short read from %s: got %d bytes, expected %d" % [source, data.size(), count], "data": PackedByteArray()}
	return {"error": "", "data": data}

func _read_http(source: String, byte_offset: int, byte_size: int) -> Dictionary:
	var request := HTTPRequest.new()
	add_child(request)
	var headers := PackedStringArray()
	if byte_offset >= 0 and byte_size > 0:
		headers.append("Range: bytes=%d-%d" % [byte_offset, byte_offset + byte_size - 1])
	var start_error := request.request(source, headers)
	if start_error != OK:
		request.queue_free()
		return {"error": "cannot start request for %s: %s" % [source, error_string(start_error)], "data": PackedByteArray()}
	var response: Array = await request.request_completed
	request.queue_free()
	var result := int(response[0])
	var status := int(response[1])
	var body: PackedByteArray = response[3]
	if result != HTTPRequest.RESULT_SUCCESS:
		return {"error": "request for %s failed with transport result %d" % [source, result], "data": PackedByteArray()}
	if status < 200 or status >= 300:
		return {"error": "request for %s returned HTTP %d" % [source, status], "data": PackedByteArray()}
	if byte_size >= 0 and body.size() != byte_size:
		return {"error": "server did not honor byte range for %s: got %d bytes, expected %d" % [source, body.size(), byte_size], "data": PackedByteArray()}
	return {"error": "", "data": body}
