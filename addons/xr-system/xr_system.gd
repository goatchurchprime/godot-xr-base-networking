extends Node3D

@onready var origin : XROrigin3D = $XROrigin3D
@onready var camera : XRCamera3D = $XROrigin3D/XRCamera3D
@onready var left_controller : XRController3D = $XROrigin3D/XRController3D_left
@onready var right_controller : XRController3D = $XROrigin3D/XRController3D_right
