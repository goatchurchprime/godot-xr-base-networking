class_name EptPointDecoder
extends RefCounted

func decode(data: PackedByteArray, metadata: EptMetadata, expected_points: int) -> Dictionary:
	if metadata.point_stride <= 0 or data.size() < expected_points * metadata.point_stride:
		return {"error": "EPT root point payload is shorter than its hierarchy count"}
	var positions := PackedVector3Array()
	var colors := PackedColorArray()
	positions.resize(expected_points)
	colors.resize(expected_points)
	for point_index in range(expected_points):
		var cursor := point_index * metadata.point_stride
		var encoded := Vector3(
			data.decode_s32(cursor + metadata.position_offsets[0]),
			data.decode_s32(cursor + metadata.position_offsets[1]),
			data.decode_s32(cursor + metadata.position_offsets[2])
		)
		positions[point_index] = encoded * metadata.position_scales + metadata.position_origins - metadata.local_origin()
		if -1 not in metadata.color_offsets:
			var red := float(data.decode_u16(cursor + metadata.color_offsets[0]))
			var green := float(data.decode_u16(cursor + metadata.color_offsets[1]))
			var blue := float(data.decode_u16(cursor + metadata.color_offsets[2]))
			var divisor := 65535.0 if max(red, max(green, blue)) > 255.0 else 255.0
			colors[point_index] = Color(red / divisor, green / divisor, blue / divisor, 1.0)
		else:
			colors[point_index] = Color.WHITE
	return {"error": "", "positions": positions, "colors": colors}
