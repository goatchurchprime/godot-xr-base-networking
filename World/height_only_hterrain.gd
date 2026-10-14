@tool
class_name HeightOnlyHTerrain
extends HTerrain

## HTerrain's editor hook always starts its normal-map baker. The elevation-only
## terrain deliberately has no normal channel because its custom shader derives
## face normals with screen-space derivatives. Starting the baker in that case
## repeatedly indexes an empty map array.
##
## Keep the rest of HTerrain's editor and runtime behaviour, but omit that one
## editor-only helper. Runtime HTerrain does exactly the same set_process call.
func _enter_tree() -> void:
	set_process(true)
