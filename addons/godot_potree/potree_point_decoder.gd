class_name PotreePointDecoder
extends RefCounted

func decode(data: PackedByteArray, metadata: PotreeMetadata, expected_points: int, node_bounds := AABB(), compute_density := true) -> Dictionary:
	if metadata.point_stride <= 0:
		return {"error": "invalid point stride"}
	var available_points := int(data.size() / metadata.point_stride)
	if available_points < expected_points:
		return {"error": "point payload contains %d points; expected %d" % [available_points, expected_points]}
	var positions := PackedVector3Array()
	var colors := PackedColorArray()
	positions.resize(expected_points)
	colors.resize(expected_points)
	var occupancy := PackedByteArray()
	occupancy.resize(32 * 32 * 32)
	var occupied_cells := 0
	var origin := metadata.local_origin()
	for point_index in range(expected_points):
		var cursor := point_index * metadata.point_stride
		var position_cursor := cursor + metadata.position_offset
		var encoded := Vector3(
			float(data.decode_s32(position_cursor)),
			float(data.decode_s32(position_cursor + 4)),
			float(data.decode_s32(position_cursor + 8))
		)
		var source_position := encoded * metadata.scale + metadata.offset
		positions[point_index] = source_position - origin
		if compute_density and node_bounds.size != Vector3.ZERO:
			var relative := source_position - node_bounds.position
			var cell := Vector3i(
				clampi(int(32.0 * relative.x / maxf(node_bounds.size.x, 1.0e-9)), 0, 31),
				clampi(int(32.0 * relative.y / maxf(node_bounds.size.y, 1.0e-9)), 0, 31),
				clampi(int(32.0 * relative.z / maxf(node_bounds.size.z, 1.0e-9)), 0, 31)
			)
			var grid_index := cell.x + cell.y * 32 + cell.z * 32 * 32
			if occupancy[grid_index] == 0:
				occupancy[grid_index] = 1
				occupied_cells += 1
		if metadata.color_offset >= 0 and metadata.color_size >= 6:
			var color_cursor := cursor + metadata.color_offset
			var red := float(data.decode_u16(color_cursor))
			var green := float(data.decode_u16(color_cursor + 2))
			var blue := float(data.decode_u16(color_cursor + 4))
			var divisor := 65535.0 if max(red, max(green, blue)) > 255.0 else 255.0
			colors[point_index] = Color(red / divisor, green / divisor, blue / divisor, 1.0)
		else:
			colors[point_index] = Color.WHITE
	return {
		"positions": positions,
		"colors": colors,
		# Potree's DecoderWorker truncates this average with parseInt().
		"density": float(int(expected_points / occupied_cells)) if occupied_cells > 0 else 0.0,
		"error": ""
	}
