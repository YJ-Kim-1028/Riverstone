extends Node

## Owns the read-only content of category=="book" items (data/books/books.json) -
## title/author/paginated text. Books are non-discardable, stack-limit-1
## items (inventory_manager.gd) that stay in the bag forever and can be
## reread any time, so this manager only looks data up; it never consumes
## anything (unlike CookingManager.learn_recipe()).

const BOOKS_PATH := "res://data/books/books.json"

var _books: Dictionary = {}


func _ready() -> void:
	_load_books()


func has_book(item_id: String) -> bool:
	return _books.has(item_id)


func get_book(item_id: String) -> Dictionary:
	return _books.get(item_id, {})


func _load_books() -> void:
	var file := FileAccess.open(BOOKS_PATH, FileAccess.READ)
	if file == null:
		push_error("Book catalog could not be opened: %s" % BOOKS_PATH)
		return
	var parsed: Variant = JSON.parse_string(file.get_as_text())
	if not (parsed is Dictionary):
		push_error("Book catalog is not valid JSON: %s" % BOOKS_PATH)
		return
	_books = Localizer.apply_language(parsed, BOOKS_PATH) as Dictionary
