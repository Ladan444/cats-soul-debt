extends Node
## Навигация врагов в большом мире — участками (весь мир 1,5 км печь слишком долго): квадрат вокруг места,
## где появляются враги. Земля — треугольники из сетки высот (HeightMapShape3D рельефа) только внутри квадрата,
## постройки, камни и мосты — коллизии тел рядом (поиск формой-коробкой), стволы деревьев — препятствия-круги.
## Печётся в фоне, затем добавляется NavigationRegion3D (на общую карту, как в Рубеже: ячейка 0,25 м).

const HALF := 36.0

@export var terrain_shape_path: NodePath
@export var nature_body_path: NodePath

var _baked: Dictionary = {}


## Испечь участок вокруг center (Godot), если он ещё не испечён.
func bake_around(key: String, center: Vector3) -> void:
	if _baked.has(key):
		return
	_baked[key] = true
	var nav := NavigationMesh.new()
	nav.geometry_parsed_geometry_type = NavigationMesh.PARSED_GEOMETRY_STATIC_COLLIDERS
	nav.agent_radius = 0.5
	nav.agent_height = 1.5
	nav.agent_max_climb = 0.5
	nav.agent_max_slope = 40.0
	nav.cell_size = 0.25
	nav.cell_height = 0.25
	var box := AABB(center - Vector3(HALF, 40, HALF), Vector3(HALF * 2, 80, HALF * 2))
	nav.filter_baking_aabb = box
	var source := NavigationMeshSourceGeometryData3D.new()
	_add_terrain(source, box)
	_add_bodies(nav, source, box)
	_add_trees(source, box)
	NavigationServer3D.bake_from_source_geometry_data_async(nav, source, _on_baked(weakref(self), nav, key))


## Колбэк запекания не привязан к узлу: если сцену успели сменить (Рэй ушёл в Рубеж), он просто ничего не делает.
static func _on_baked(owner_ref: WeakRef, nav: NavigationMesh, key: String) -> Callable:
	return func():
		var me: Node = owner_ref.get_ref()
		if me == null or not me.is_inside_tree():
			return
		var region := NavigationRegion3D.new()
		region.name = "Nav_" + key
		region.navigation_mesh = nav
		me.add_child(region)


func _add_terrain(source: NavigationMeshSourceGeometryData3D, box: AABB) -> void:
	var cs := get_node_or_null(terrain_shape_path) as CollisionShape3D
	if cs == null or not (cs.shape is HeightMapShape3D):
		return
	var hm := cs.shape as HeightMapShape3D
	var w := hm.map_width
	var d := hm.map_depth
	var step := cs.scale.x
	var ox := cs.global_position.x - (w - 1) * step / 2.0
	var oz := cs.global_position.z - (d - 1) * step / 2.0
	var i0 := clampi(int((box.position.x - ox) / step), 0, w - 2)
	var i1 := clampi(int((box.end.x - ox) / step) + 1, 0, w - 2)
	var k0 := clampi(int((box.position.z - oz) / step), 0, d - 2)
	var k1 := clampi(int((box.end.z - oz) / step) + 1, 0, d - 2)
	var data := hm.map_data
	var faces := PackedVector3Array()
	for k in range(k0, k1 + 1):
		for i in range(i0, i1 + 1):
			var a := Vector3(ox + i * step, data[k * w + i], oz + k * step)
			var b := Vector3(ox + (i + 1) * step, data[k * w + i + 1], oz + k * step)
			var c := Vector3(ox + i * step, data[(k + 1) * w + i], oz + (k + 1) * step)
			var e := Vector3(ox + (i + 1) * step, data[(k + 1) * w + i + 1], oz + (k + 1) * step)
			faces.append_array([a, b, c, b, e, c])
	source.add_faces(faces, Transform3D.IDENTITY)


## Постройки, камни мест, мосты: тела (кроме рельефа и растительности), задетые коробкой участка.
func _add_bodies(nav: NavigationMesh, source: NavigationMeshSourceGeometryData3D, box: AABB) -> void:
	var shape := BoxShape3D.new()
	shape.size = box.size
	var q := PhysicsShapeQueryParameters3D.new()
	q.shape = shape
	q.transform = Transform3D(Basis.IDENTITY, box.get_center())
	q.collision_mask = 1
	var nature := get_node_or_null(nature_body_path)
	var seen := {}
	for hit in get_viewport().get_world_3d().direct_space_state.intersect_shape(q, 256):
		var body: Node = hit.collider
		if body == null or seen.has(body) or body == nature or String(body.name).begins_with("Terrain"):
			continue
		seen[body] = true
		var part := NavigationMeshSourceGeometryData3D.new()
		NavigationServer3D.parse_source_geometry_data(nav, part, body)
		source.merge(part)


## Стволы и камни растительности — круги-препятствия (без разбора тысяч цилиндров в треугольники).
func _add_trees(source: NavigationMeshSourceGeometryData3D, box: AABB) -> void:
	var nature := get_node_or_null(nature_body_path)
	if nature == null:
		return
	for cs in nature.get_children():
		if not (cs is CollisionShape3D) or not (cs.shape is CylinderShape3D):
			continue
		var p: Vector3 = cs.global_position
		if not box.has_point(p):
			continue
		var r: float = (cs.shape as CylinderShape3D).radius
		var ring := PackedVector3Array()
		for a in 6:
			var t := TAU * a / 6.0
			ring.append(Vector3(p.x + cos(t) * r, 0, p.z + sin(t) * r))
		source.add_projected_obstruction(ring, p.y - 1.6, 3.0, true)
