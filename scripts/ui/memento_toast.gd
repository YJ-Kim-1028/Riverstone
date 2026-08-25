extends Control

## 추억의 물건을 받는 순간(NPCManager.memento_received) 화면에 잠깐 띄우는
## 작은 알림 - 아이콘(16x16) + 이름만, 인벤토리 화면을 안 열어도 뭘 받았는지
## 바로 보이게 한다(사용자 지시, 2026-08-25 - "인벤에만 보여주는 거 말고").

const FADE_IN_SECONDS := 0.2
const HOLD_SECONDS := 1.8
const FADE_OUT_SECONDS := 0.5

@onready var _icon: TextureRect = $HBox/Icon
@onready var _label: Label = $HBox/Label

var _tween: Tween = null


func show_memento(npc_id: String) -> void:
	show_item("memento_%s" % npc_id)


## 추억의 물건 외 다른 아이템(예: 영혼의 결정 지급, 사용자 지시 2026-08-25)에도
## 같은 알림을 재사용할 수 있게 memento_id 계산 부분만 show_memento()에서
## 분리했다.
func show_item(item_id: String) -> void:
	var item_name := String(InventoryManager.get_item_definition(item_id).get("name", ""))
	if item_name.is_empty():
		return
	_icon.texture = InventoryManager.get_item_icon_texture(item_id)
	_label.text = "%s을(를) 얻었다." % item_name
	if _tween != null and _tween.is_valid():
		_tween.kill()
	modulate.a = 0.0
	_tween = create_tween()
	_tween.tween_property(self, "modulate:a", 1.0, FADE_IN_SECONDS)
	_tween.tween_interval(HOLD_SECONDS)
	_tween.tween_property(self, "modulate:a", 0.0, FADE_OUT_SECONDS)
