extends Node3D

@onready var skelprobes : Array[Skeleton3D]
@onready var boneattachments : Array[BoneAttachment3D]

@onready var springbone : SpringBoneSimulator3D = $davali/Armature/Skeleton3D/SpringBoneSimulator3D
var springbonespheres : Array[SpringBoneCollisionSphere3D]

func _ready():
	var vrplayer = get_node("../PlayerAvatars").get_child(0)
	skelprobes.append(vrplayer.get_node("hand_l/Armature/Skeleton3D"))

	for skelprobe in skelprobes:
		for ba in skelprobe.get_children():
			print(ba.get_path())
			if is_instance_of(ba, BoneAttachment3D):
				boneattachments.append(ba)

	for sb in springbone.get_children():
		if is_instance_of(sb, SpringBoneCollisionSphere3D):
			springbonespheres.append(sb)
	
	for i in range(len(boneattachments)):
		var ba = boneattachments[i]
		var sb = springbonespheres[i] if i < len(springbonespheres) else null
		if sb == null:
			sb = SpringBoneCollisionSphere3D.new()
			springbonespheres.append(sb)
			springbone.add_child(sb)
		var bam = ba.get_child(0)
		sb.radius = bam.mesh.radius * bam.scale.x


	for i in range(springbone.get_setting_count()):
		print(i)
		print(springbone.get_root_bone_name(i))
		print(springbone.get_end_bone_name(i))
		print(springbone.get_radius(i))
		for j in range(springbone.get_joint_count(i)):
			print(j, " ", springbone.get_joint_radius(i, j))

func _process(_delta):
	for i in range(len(boneattachments)):
		var ba = boneattachments[i]
		var sb = springbonespheres[i]
		sb.global_position = ba.get_child(0).global_position
