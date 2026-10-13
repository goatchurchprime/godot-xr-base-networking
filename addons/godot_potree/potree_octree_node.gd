class_name PotreeOctreeNode
extends RefCounted

enum NodeType { NORMAL = 0, LEAF = 1, PROXY = 2 }

var node_name := "r"
var node_type := NodeType.PROXY
var child_mask := 0
var num_points := 0
var byte_offset := 0
var byte_size := 0
var child_index := -1
var hierarchy_byte_offset := 0
var hierarchy_byte_size := 0
var depth := 0
var spacing := 0.0
var density := 0.0
var density_byte_offset := -1
var bounds := AABB()
var parent: WeakRef
var children: Array[PotreeOctreeNode] = []
var hierarchy_loaded := false
var loading := false
var mesh_instance: MeshInstance3D
var carried_point_count := 0
var render_point_count := 0
var visible_child_mask := 0
var last_used_frame := 0

func make_child(index: int) -> PotreeOctreeNode:
	var child := PotreeOctreeNode.new()
	child.parent = weakref(self)
	child.child_index = index
	child.node_name = node_name + str(index)
	child.depth = depth + 1
	child.spacing = spacing * 0.5
	child.bounds = child_bounds(index)
	children.append(child)
	return child

func child_bounds(index: int) -> AABB:
	var half := bounds.size * 0.5
	var position := bounds.position
	if index & 4:
		position.x += half.x
	if index & 2:
		position.y += half.y
	if index & 1:
		position.z += half.z
	return AABB(position, half)

func is_proxy() -> bool:
	return node_type == NodeType.PROXY and not hierarchy_loaded

func parent_node() -> PotreeOctreeNode:
	return parent.get_ref() as PotreeOctreeNode if parent != null else null
