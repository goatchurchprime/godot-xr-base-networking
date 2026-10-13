class_name PotreeHierarchy
extends RefCounted

const RECORD_SIZE := 22

func parse_chunk(data: PackedByteArray, root: PotreeOctreeNode, hierarchy_file_offset := 0, density_data := PackedByteArray()) -> String:
	if data.size() == 0 or data.size() % RECORD_SIZE != 0:
		return "hierarchy chunk size must be a positive multiple of 22"
	var record_count := int(data.size() / RECORD_SIZE)
	var queue: Array[PotreeOctreeNode] = [root]
	var queue_index := 0
	for record_index in range(record_count):
		if queue_index >= queue.size():
			return "hierarchy chunk contains more records than its child masks describe"
		var node := queue[queue_index]
		queue_index += 1
		var cursor := record_index * RECORD_SIZE
		node.density_byte_offset = (int(hierarchy_file_offset / RECORD_SIZE) + record_index) * 4
		if density_data.size() >= (record_index + 1) * 4:
			node.density = density_data.decode_float(record_index * 4)
		var node_type := int(data[cursor])
		if node_type < PotreeOctreeNode.NodeType.NORMAL or node_type > PotreeOctreeNode.NodeType.PROXY:
			return "hierarchy record %d has unknown node type %d" % [record_index, node_type]
		node.node_type = node_type
		node.child_mask = int(data[cursor + 1])
		node.num_points = int(data.decode_u32(cursor + 2))
		var first_u64 := int(data.decode_u64(cursor + 6))
		var second_u64 := int(data.decode_u64(cursor + 14))
		if node_type == PotreeOctreeNode.NodeType.PROXY:
			node.hierarchy_byte_offset = first_u64
			node.hierarchy_byte_size = second_u64
		else:
			node.byte_offset = first_u64
			node.byte_size = second_u64
		node.children.clear()
		if node_type != PotreeOctreeNode.NodeType.PROXY:
			for child_index in range(8):
				if node.child_mask & (1 << child_index):
					queue.append(node.make_child(child_index))
	root.hierarchy_loaded = true
	if queue_index != queue.size():
		return "hierarchy chunk ended before all described children were defined"
	return ""
