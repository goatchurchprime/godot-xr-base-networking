extends Node3D

@onready var skelprobes : Array[Skeleton3D]
@onready var springbone : SpringBoneSimulator3D = $davali/Armature/Skeleton3D/SpringBoneSimulator3D

var boneattachmentspheres : Array[Node3D]
var springbonespheres : Array[SpringBoneCollisionSphere3D]

var boneattachmentcapsules : Array[Node3D]
var springbonecapsules : Array[SpringBoneCollisionCapsule3D]

func _ready():
	var vrplayer = get_node("../PlayerAvatars").get_child(0)
	skelprobes.append(vrplayer.get_node("hand_l/Armature/Skeleton3D"))
	skelprobes.append(vrplayer.get_node("hand_r/Armature/Skeleton3D"))

	for skelprobe in skelprobes:
		for ba in skelprobe.get_children():
			if is_instance_of(ba, BoneAttachment3D):
				var m : MeshInstance3D = ba.get_child(0)
				if is_instance_of(m.mesh, SphereMesh):
					boneattachmentspheres.append(m)
				elif is_instance_of(m.mesh, CapsuleMesh):
					boneattachmentcapsules.append(m)
	for sb in springbone.get_children():
		if is_instance_of(sb, SpringBoneCollisionSphere3D):
			springbonespheres.append(sb)
		elif is_instance_of(sb, SpringBoneCollisionCapsule3D):
			springbonecapsules.append(sb)
	
	for i in range(len(boneattachmentspheres)):
		var ba = boneattachmentspheres[i]
		var sb = springbonespheres[i] if i < len(springbonespheres) else null
		if sb == null:
			sb = SpringBoneCollisionSphere3D.new()
			springbonespheres.append(sb)
			springbone.add_child(sb)
		sb.collide_mode = SpringBoneCollision3D.COLLIDE_MODE_CHAIN
		sb.radius = ba.mesh.radius * ba.scale.x

	for i in range(len(boneattachmentcapsules)):
		var ba = boneattachmentcapsules[i]
		var sb = springbonecapsules[i] if i < len(springbonecapsules) else null
		if sb == null:
			sb = SpringBoneCollisionCapsule3D.new()
			springbonecapsules.append(sb)
			springbone.add_child(sb)
		sb.collide_mode = SpringBoneCollision3D.COLLIDE_MODE_CHAIN
		sb.radius = ba.mesh.radius * ba.scale.x
		sb.height = ba.mesh.height * ba.scale.x

	var sbvc = load("res://springbonevisible.tscn")
	for i in range(springbone.get_setting_count()):
		print(i)
		print(springbone.get_root_bone_name(i))
		print(springbone.get_end_bone_name(i))
		print(springbone.get_radius(i))
		for j in range(springbone.get_joint_count(i) + 1):
			var jointrad = springbone.get_joint_radius(i, j-1) if springbone.is_config_individual(i) else springbone.get_radius(i)
			prints(j, springbone.get_joint_bone_name(i, j), "rad", jointrad, springbone.get_joint_radius(i, j))
			var sbv = sbvc.instantiate()
			sbv.get_child(0).scale = Vector3.ONE*jointrad
			sbv.bone_idx = springbone.get_joint_bone(i, j)
			springbone.get_parent().add_child(sbv)
	print("done")

func _process(_delta):
	for i in range(len(boneattachmentspheres)):
		var ba = boneattachmentspheres[i]
		var sb = springbonespheres[i]
		sb.global_position = ba.global_position
	for i in range(len(boneattachmentcapsules)):
		var ba = boneattachmentcapsules[i]
		var sb = springbonecapsules[i]
		sb.global_position = ba.global_position
		sb.global_basis = ba.global_basis.orthonormalized()
