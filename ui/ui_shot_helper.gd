extends Node
## 메뉴/선택/설정처럼 전투 월드가 없는 화면의 개발용 레이아웃 캡처.

var frame := 0
var out_path := "/tmp/eclipse_ui.png"
var _capturing := false


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	if OS.get_environment("ECLIPSE_UI_SHOT_OUT") != "":
		out_path = OS.get_environment("ECLIPSE_UI_SHOT_OUT")


func _process(_dt: float) -> void:
	frame += 1
	if frame >= 35 and not _capturing:
		_capturing = true
		_capture_after_draw()


func _capture_after_draw() -> void:
	await RenderingServer.frame_post_draw
	RenderingServer.force_sync()
	if OS.get_environment("ECLIPSE_UI_DUMP") != "":
		_dump_controls(get_parent(), "")
	var img := get_viewport().get_texture().get_image()
	if img == null or img.save_png(out_path) != OK:
		push_error("UI 스크린샷 저장 실패: " + out_path)
		AudioManager.stop_all()
		get_tree().quit(1)
		return
	print("UI 스크린샷 저장: ", out_path)
	AudioManager.stop_all()
	await get_tree().process_frame
	get_tree().quit()


func _dump_controls(node: Node, indent: String) -> void:
	if node is Control:
		print(indent, node.get_class(), " pos=", node.position, " size=", node.size,
				" min=", node.custom_minimum_size, " visible=", node.visible)
	for child in node.get_children():
		_dump_controls(child, indent + "  ")
