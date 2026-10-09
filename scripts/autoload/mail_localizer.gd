extends RefCounted
class_name MailLocalizer

## 받은 메일/발신함/초대 내역을 "지금 설정된 언어"로 다시 보여주는 정적 유틸리티.
## 메일은 받는 순간의 제목/본문이 세이브에 완성된 문자열로 저장돼서, 언어를 바꿔도
## 예전에 받은 메일이 처음 받은 언어로 남는 문제가 있었다(2026-10-09). 그래서
## EmailManager._add_mail()이 "src"(어느 NPC의 어떤 메일인지)와 "date_parts"(날짜
## 숫자)를 같이 저장하고, 표시할 때마다 여기서 현재 언어의 NPC 데이터로 다시 찾는다.
## "src"/"date_parts"가 없는 옛 세이브 항목과 사칭/스토커 메일(발송 시점에 피해자
## 이름이 치환돼서 다시 만들 수 없음)은 저장된 글을 그대로 보여준다.
## Localizer와 같은 이유로 오토로드가 아니라 class_name 정적 유틸리티다.

const POOL_CATEGORIES := ["greeting", "gift_thanks", "event_invite"]
const SINGLE_CATEGORIES := ["memento_reminder", "alibi_reminder"]
const DATE_FORMAT_KEY := "%d년 %d월 %d일 %d일차"


## 메일 항목 하나를 현재 언어로 바꾼 복사본을 돌려준다(원본은 건드리지 않는다).
## npc_definition은 발신 NPC의 현재 언어 정의 - 오토로드 식별자를 직접 쓰지 않으려고 호출부가 넘긴다.
static func localize_entry(entry: Dictionary, npc_definition: Dictionary) -> Dictionary:
	var out: Dictionary = entry.duplicate(true)
	_apply_date(out)
	var source: Variant = entry.get("src")
	if source is Dictionary:
		var content := _find_content(npc_definition, source as Dictionary)
		if not content.is_empty():
			out["title"] = String(content.get("title", ""))
			out["lines"] = (content.get("lines", []) as Array).duplicate()
	return out


## 날짜 숫자만 가진 항목(발신함/초대 내역 포함)의 "date" 문자열을 현재 언어로 다시 만든다.
static func localize_dated(entry: Dictionary) -> Dictionary:
	var out: Dictionary = entry.duplicate(true)
	_apply_date(out)
	return out


static func _apply_date(entry: Dictionary) -> void:
	var parts: Variant = entry.get("date_parts")
	if parts is Array and (parts as Array).size() == 4:
		var p: Array = parts
		entry["date"] = String(TranslationServer.translate(DATE_FORMAT_KEY)) % [int(p[0]), int(p[1]), int(p[2]), int(p[3])]


static func _find_content(npc_definition: Dictionary, source: Dictionary) -> Dictionary:
	var emails: Dictionary = npc_definition.get("emails", {})
	var category := String(source.get("cat", ""))
	if category in POOL_CATEGORIES:
		var pool: Array = emails.get(category, [])
		var index := int(source.get("idx", -1))
		if index < 0 or index >= pool.size() or not (pool[index] is Dictionary):
			return {}
		return pool[index]
	if category in SINGLE_CATEGORIES:
		return emails.get(category, {})
	if category == "story_progress":
		var triggers: Dictionary = emails.get("story_progress", {})
		return triggers.get(String(source.get("trigger", "")), {})
	return {}
