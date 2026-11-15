## Колода игрока: стопка добора и сброс. Когда добор кончается, сброс замешивается обратно.
extends RefCounted

var draw_pile: Array = []
var discard_pile: Array = []
var rng: RandomNumberGenerator


func setup(counts: Dictionary, rng_: RandomNumberGenerator) -> void:
	rng = rng_
	draw_pile.clear()
	discard_pile.clear()
	for id in counts:
		for _n in int(counts[id]):
			draw_pile.append(id)
	_shuffle(draw_pile)


func add_card(id: String) -> void:
	discard_pile.append(id)


func draw(n: int) -> Array:
	var hand := []
	for _k in n:
		if draw_pile.is_empty():
			if discard_pile.is_empty():
				break
			draw_pile = discard_pile
			discard_pile = []
			_shuffle(draw_pile)
		hand.append(draw_pile.pop_back())
	return hand


func discard(cards: Array) -> void:
	discard_pile.append_array(cards)


func total_cards() -> int:
	return draw_pile.size() + discard_pile.size()


func _shuffle(a: Array) -> void:
	for i in range(a.size() - 1, 0, -1):
		var j := rng.randi_range(0, i)
		var t = a[i]
		a[i] = a[j]
		a[j] = t
