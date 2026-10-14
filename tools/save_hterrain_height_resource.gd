extends SceneTree


func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	if args.size() != 3:
		push_error("Usage: --script save_hterrain_height_resource.gd RAW OUTPUT RESOLUTION")
		quit(2)
		return
	var raw_path := args[0]
	var output_path := args[1]
	var resolution := args[2].to_int()
	var bytes := FileAccess.get_file_as_bytes(raw_path)
	var expected_size := resolution * resolution * 4
	if bytes.size() != expected_size:
		push_error("RF byte count is %d, expected %d" % [bytes.size(), expected_size])
		quit(3)
		return
	var image := Image.create_from_data(resolution, resolution, false, Image.FORMAT_RF, bytes)
	var error := ResourceSaver.save(image, output_path)
	if error != OK:
		push_error("Could not save height Image: " + error_string(error))
		quit(error)
		return
	print("Saved HTerrain RF height resource: ", output_path)
	quit()
