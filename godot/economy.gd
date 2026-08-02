# EMBERFALL: 1940 — economy.gd
# The emberstone economy (GAME_DESIGN.md §5): every faction's credit
# balance, and the map's ember reserves — each field tile holds a finite
# stock that harvesters drain. When a tile runs dry its crystals vanish,
# the ground turns to cratered rough, and the minimap updates.

class_name EFEconomy
extends Node

signal field_depleted(tile: Vector2i)

const CREDITS_PER_TILE := 1500
const START_CREDITS := 3000

signal field_regrown(tile: Vector2i)

var world: EFWorld
var credits := {}         # faction -> credits
var reserves := {}        # Vector2i -> credits left in that field tile
var income_mult := {}     # faction -> AI difficulty handicap on deposits
var regrow_delay := 75.0  # seconds a dead field lies fallow
var regrow_rate := 6.0    # credits/second a field regrows afterward
var _regrow := {}         # tile -> fallow countdown


func setup(w: EFWorld) -> void:
	world = w
	for slot in world.slot_faction:
		credits[world.slot_faction[slot]] = START_CREDITS
	for tile in world.ember_tiles:
		reserves[tile] = CREDITS_PER_TILE


func mine(tile: Vector2i, amount: float) -> float:
	# returns what was actually extracted
	if not reserves.has(tile):
		return 0.0
	var got: float = minf(amount, reserves[tile])
	reserves[tile] -= got
	if reserves[tile] <= 0.0:
		reserves.erase(tile)
		world.deplete_ember(tile)
		field_depleted.emit(tile)
		_regrow[tile] = regrow_delay    # the ash remembers; the ember returns
	return got


func has_reserves(tile: Vector2i) -> bool:
	return reserves.has(tile)


func nearest_field(pos: Vector3) -> Vector2i:
	var best := Vector2i(-1, -1)
	var best_d := 1e18
	for tile: Vector2i in reserves:
		var d := Vector2(tile.x * EFWorld.T - pos.x, tile.y * EFWorld.T - pos.z).length_squared()
		if d < best_d:
			best_d = d
			best = tile
	return best


func deposit(faction: int, amount: float) -> void:
	credits[faction] = credits.get(faction, 0) \
		+ int(amount * income_mult.get(faction, 1.0))


func _process(dt: float) -> void:
	# fallow fields come back to life...
	var reborn := []
	for tile in _regrow:
		_regrow[tile] -= dt
		if _regrow[tile] <= 0.0:
			reborn.append(tile)
	for tile in reborn:
		_regrow.erase(tile)
		reserves[tile] = 1.0
		world.regrow_ember(tile)
		field_regrown.emit(tile)
	# ...and every living field slowly fattens back toward full
	for tile in reserves:
		if reserves[tile] < CREDITS_PER_TILE:
			reserves[tile] = minf(float(CREDITS_PER_TILE),
				reserves[tile] + regrow_rate * dt)


func total_reserves() -> int:
	var t := 0
	for tile in reserves:
		t += int(reserves[tile])
	return t
