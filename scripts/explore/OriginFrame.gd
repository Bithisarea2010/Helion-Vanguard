class_name OriginFrame
extends RefCounted
## World positions are three 64-bit scalars. Vector3 is reserved for bounded local differences.
var origin := PackedFloat64Array([0.0, 0.0, 0.0])
var rebase_count := 0
const REBASE_DISTANCE := 512.0

func to_local(world: PackedFloat64Array) -> Vector3:
	return Vector3(world[0] - origin[0], world[1] - origin[1], world[2] - origin[2])

func to_world(local: Vector3) -> PackedFloat64Array:
	return PackedFloat64Array([origin[0] + float(local.x), origin[1] + float(local.y), origin[2] + float(local.z)])

func rebase(focus: Node3D, roots: Array[Node3D]) -> Vector3:
	if focus.position.length() < REBASE_DISTANCE:
		return Vector3.ZERO
	var offset := focus.position.snapped(Vector3.ONE * 128.0)
	for i in 3:
		origin[i] += float(offset[i])
	for root in roots:
		root.position -= offset
	# Velocity and orientation are invariant under translation. Roots must be disjoint.
	rebase_count += 1
	return offset
