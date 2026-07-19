class_name ResponsiveLayout
extends RefCounted
## 기기 비율이 달라도 1280×720 콘텐츠를 왜곡 없이 중앙에 두는 계산 모음.

const BASE_SIZE := Vector2(1280, 720)


static func content_offset_for_size(viewport_size: Vector2) -> Vector2:
	return (viewport_size - BASE_SIZE) * 0.5


static func expanded_rect_for_size(viewport_size: Vector2) -> Rect2:
	return Rect2(-content_offset_for_size(viewport_size), viewport_size)


static func cover_source_rect(texture_size: Vector2, destination_size: Vector2) -> Rect2:
	if texture_size.x <= 0.0 or texture_size.y <= 0.0 \
			or destination_size.x <= 0.0 or destination_size.y <= 0.0:
		return Rect2(Vector2.ZERO, texture_size)
	var source_size := texture_size
	var destination_aspect := destination_size.x / destination_size.y
	var texture_aspect := texture_size.x / texture_size.y
	if texture_aspect < destination_aspect:
		source_size.y = texture_size.x / destination_aspect
	else:
		source_size.x = texture_size.y * destination_aspect
	return Rect2((texture_size - source_size) * 0.5, source_size)
