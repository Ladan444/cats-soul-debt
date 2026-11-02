class_name Lobbed
extends Node3D
## Снаряд, летящий дугой в точку (комок грязи квалда, валун голема). Летит видимо и честно: бьёт только
## по месту падения — Рэй, ушедший из круга (или рывком), не задет. Метка на земле показывает, куда упадёт.
## Тоже здесь — метка удара по площади (`ground_marker`) для замахов (удар голема по земле).

var _from: Vector3
var _to: Vector3
var _flight: float
var _time: float = 0.0
var _height: float
var _radius: float
var _info: Dictionary
var _color: Color
var _marker: Node3D


## Бросить из from в to за flight секунд. info — как для take_hit Рэя (damage, slow, blind, stun...).
static func throw(parent: Node, from: Vector3, to: Vector3, flight: float, radius: float, info: Dictionary,
		color: Color, size: float, height: float = 2.0) -> Lobbed:
	var l := Lobbed.new()
	l._from = from
	l._to = to
	l._flight = flight
	l._height = height
	l._radius = radius
	l._info = info
	l._color = color
	var mesh := MeshInstance3D.new()
	var sphere := SphereMesh.new()
	sphere.radius = size
	sphere.height = size * 2.0
	sphere.radial_segments = 8
	sphere.rings = 4
	mesh.mesh = sphere
	var mat := StandardMaterial3D.new()
	mat.albedo_color = color
	mat.roughness = 1.0
	mesh.material_override = mat
	l.add_child(mesh)
	parent.add_child(l)
	l.global_position = from
	l._marker = ground_marker(parent, Vector3(to.x, to.y, to.z), radius, flight, color)
	return l


## Метка на земле: полупрозрачный круг, наливается к моменту удара (duration), потом исчезает.
static func ground_marker(parent: Node, at: Vector3, radius: float, duration: float, color: Color) -> Node3D:
	var m := MeshInstance3D.new()
	var disc := CylinderMesh.new()
	disc.top_radius = radius
	disc.bottom_radius = radius
	disc.height = 0.02
	disc.radial_segments = 24
	m.mesh = disc
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.albedo_color = Color(color, 0.15)
	m.material_override = mat
	m.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	parent.add_child(m)
	m.global_position = at + Vector3(0, 0.03, 0)
	m.scale = Vector3(0.3, 1, 0.3)
	var t := m.create_tween()
	t.tween_property(m, "scale", Vector3.ONE, duration)
	t.parallel().tween_property(mat, "albedo_color:a", 0.45, duration)
	t.tween_property(mat, "albedo_color:a", 0.0, 0.25)
	t.tween_callback(m.queue_free)
	return m


func _physics_process(delta: float) -> void:
	_time += delta
	var t := clampf(_time / _flight, 0.0, 1.0)
	global_position = _from.lerp(_to, t) + Vector3(0, sin(t * PI) * _height, 0)
	if t < 1.0:
		return
	CombatFX.burst(_to + Vector3(0, 0.2, 0), _color, Vector3.ZERO, 16, 3.0, 8.0, 0.08, 0.5)
	var player := get_tree().get_first_node_in_group("player") as Node3D
	if player and player.has_method("take_hit"):
		var d := player.global_position - _to
		if Vector2(d.x, d.z).length() <= _radius + 0.3:
			var info := _info.duplicate()
			info["dir"] = Vector3(d.x, 0, d.z).normalized() if Vector2(d.x, d.z).length() > 0.05 else Vector3.FORWARD
			player.take_hit(info)
	queue_free()
