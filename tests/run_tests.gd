## Юнит-тесты правил. Запуск:
##   godot --headless --path . -s tests/run_tests.gd
extends SceneTree

const GameData = preload("res://scripts/core/game_data.gd")
const Board = preload("res://scripts/core/board.gd")
const RunState = preload("res://scripts/core/run_state.gd")

var failures := 0
var data


func _initialize() -> void:
	data = GameData.new()
	_check(data.load_all(), "данные загружаются и валидны")
	test_neighbors()
	test_house_field()
	test_mill_two_fields()
	test_per_neighbor()
	test_preview()
	test_run_flow()
	test_undo()
	print("\n%s" % ("ВСЕ ТЕСТЫ ПРОШЛИ" if failures == 0 else "ПРОВАЛЕНО: %d" % failures))
	quit(1 if failures > 0 else 0)


func test_neighbors() -> void:
	_check(Board.neighbors(4).size() == 4, "центр имеет 4 соседа")
	_check(Board.neighbors(0).size() == 2, "угол имеет 2 соседа")
	_check(Board.neighbors(4, true).size() == 8, "центр с диагоналями — 8")


func test_house_field() -> void:
	var b = Board.new()
	b.cells[0] = "house"
	b.cells[1] = "field"
	var t: Dictionary = b.evaluate(data)["total"]
	# домик 1 + поле 1 + комбо 3
	_check(t["food"] == 5, "домик+поле = 5 еды (получили %d)" % t["food"])


func test_mill_two_fields() -> void:
	var b = Board.new()
	b.cells[4] = "mill"
	b.cells[1] = "field"
	var t: Dictionary = b.evaluate(data)["total"]
	_check(t["food"] == 1, "мельница с одним полем не срабатывает")
	b.cells[3] = "field"
	t = b.evaluate(data)["total"]
	_check(t["food"] == 12, "мельница + 2 поля = 12 еды (получили %d)" % t["food"])
	b.cells[0] = "field"  # диагональ — не сосед мельнице
	t = b.evaluate(data)["total"]
	_check(t["food"] == 13, "диагональ не считается соседом")


func test_per_neighbor() -> void:
	var b = Board.new()
	b.cells[4] = "market"
	b.cells[1] = "house"
	b.cells[3] = "house"
	var t: Dictionary = b.evaluate(data)["total"]
	_check(t["gold"] == 5, "рынок с 2 домиками = 1 + 2×2 = 5 золота (получили %d)" % t["gold"])


func test_preview() -> void:
	var b = Board.new()
	b.cells[0] = "field"
	var d: Dictionary = b.preview_delta(data, 1, "house")
	_check(d["food"] == 4, "превью: домик рядом с полем даёт +4 (получили %d)" % d["food"])
	_check(b.cells[1] == "", "превью не меняет поле")


func test_run_flow() -> void:
	var run = RunState.new()
	run.start(data, 42)
	_check(run.hand.size() >= 3 and run.hand.size() <= 5, "в руке 3–5 карт")
	var deck_total: int = run.deck.total_cards() + run.hand.size()
	var free: Array = run.board.free_cells()
	_check(run.place(0, free[0]), "карта ставится в свободную клетку")
	_check(not run.place(0, free[0]), "в занятую клетку ставить нельзя")
	var report: Dictionary = run.finish_field()
	_check(report.has("income"), "отчёт поля содержит доход")
	_check(run.hand.is_empty(), "после поля рука сброшена")
	_check(run.deck.total_cards() == deck_total, "карты не теряются между полями")
	run.next_field()
	_check(run.field_number == 2, "переход на следующее поле")


func test_undo() -> void:
	var run = RunState.new()
	run.start(data, 7)
	var n: int = run.hand.size()
	var card: String = run.hand[0]
	var cell: int = run.board.free_cells()[0]
	run.place(0, cell)
	_check(run.undo(), "отмена работает")
	_check(run.hand.size() == n and run.hand[0] == card, "карта вернулась в руку")
	_check(run.board.is_free(cell), "клетка освободилась")


func _check(cond: bool, label: String) -> void:
	if cond:
		print("  ok   ", label)
	else:
		failures += 1
		print("  FAIL ", label)
