extends RefCounted
## 여러 UI 화면이 함께 쓰는 정적 도우미 모음 (인스턴스를 만들지 않고 바로 호출한다).
##
## 새 파일을 만든 이유: _apply_mouse_filter_recursive()가 28개 화면 스크립트에 각각
## 복사돼 있어서, 같은 규칙을 고치려면 28곳을 다 고쳐야 했고 한 곳만 빠져도 "화면을
## 닫았는데 클릭이 씹히는" 버그가 재발했다(CLAUDE.md "UI 모달 화면 mouse_filter
## 체크리스트" 참고). 한 곳으로 모은다.
##
## 사용법(오토로드를 늘리지 않으려고 preload 상수로 쓴다):
##   const UIUtil := preload("res://scripts/ui/ui_util.gd")
##   UIUtil.apply_mouse_filter(self, Control.MOUSE_FILTER_STOP if is_open else Control.MOUSE_FILTER_IGNORE)


## node와 그 모든 하위 Control의 mouse_filter를 filter로 맞춘다.
##
## skip: 자기 열림/닫힘을 스스로 관리하는 서브 팝업(색상 선택기, 확인 팝업 등)처럼 건드리면
##   안 되는 하위 노드들. 그 서브트리 전체를 건너뛴다. 단, node 자신이 skip에 들어
##   있어도 node는 처리한다(서브 팝업 자신의 열림/닫힘을 직접 맞출 때 쓰려고).
## keep_group: 이 그룹에 속한 Control은 filter를 바꾸지 않는다(그 하위는 계속 처리한다).
##   버튼 위에 얹힌 아이콘/숫자 라벨처럼 클릭이 통과해야 하는 장식용 노드를 지키는 용도.
static func apply_mouse_filter(node: Node, filter: int, skip: Array = [], keep_group: StringName = &"") -> void:
	if node == null:
		return
	if node is Control and not (keep_group != &"" and node.is_in_group(keep_group)):
		(node as Control).mouse_filter = filter
	for child in node.get_children():
		if skip.has(child):
			continue
		apply_mouse_filter(child, filter, skip, keep_group)
