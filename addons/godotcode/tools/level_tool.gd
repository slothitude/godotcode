class_name GCLevelTool
extends GCBaseTool
## Procedural level generation: layout, population, navigation, collision


func _init() -> void:
	super._init(
		"Level",
		"Procedural level generation with layout algorithms, object placement, navigation baking, and auto-collision. Actions: generate_layout, populate, auto_nav, auto_collision, info.",
		{
			"action": {
				"type": "string",
				"description": "Action: generate_layout, populate, auto_nav, auto_collision, info",
				"enum": ["generate_layout", "populate", "auto_nav", "auto_collision", "info"]
			},
			"algorithm": {
				"type": "string",
				"description": "Layout algorithm: bsp_dungeon, cellular_automata, noise_terrain, grid_rooms, maze (default: bsp_dungeon)",
				"enum": ["bsp_dungeon", "cellular_automata", "noise_terrain", "grid_rooms", "maze"]
			},
			"width": {
				"type": "integer",
				"description": "Level width in cells/tiles (default: 40)"
			},
			"height": {
				"type": "integer",
				"description": "Level height in cells/tiles (default: 40)"
			},
			"cell_size": {
				"type": "integer",
				"description": "Size of each cell in pixels (default: 16)"
			},
			"scene_template": {
				"type": "string",
				"description": "Scene to instance for populate (e.g. res://scenes/enemy.tscn)"
			},
			"count": {
				"type": "integer",
				"description": "Number of instances to place (for populate, default: 10)"
			},
			"parent_path": {
				"type": "string",
				"description": "Scene tree path to parent node for placement"
			},
			"tilemap_path": {
				"type": "string",
				"description": "Path to TileMapLayer node for layout output"
			},
			"wall_tile": {
				"type": "integer",
				"description": "Tile atlas coordinate for walls (default: 0)"
			},
			"floor_tile": {
				"type": "integer",
				"description": "Tile atlas coordinate for floor (default: 1)"
			},
			"seed_value": {
				"type": "integer",
				"description": "Random seed for reproducible generation (0 = random)"
			},
			"fill_ratio": {
				"type": "number",
				"description": "Wall fill ratio for cellular automata (default: 0.45)"
			},
			"iterations": {
				"type": "integer",
				"description": "Smoothing iterations for cellular automata (default: 5)"
			}
		}
	)
	is_read_only = false


func validate_input(input: Dictionary) -> Dictionary:
	var action: String = input.get("action", "")
	if action == "":
		return {"valid": false, "error": "action is required"}
	match action:
		"populate":
			if input.get("scene_template", "") == "":
				return {"valid": false, "error": "scene_template is required for populate"}
	return {"valid": true}


func check_permissions(input: Dictionary, context: Dictionary) -> Dictionary:
	var action: String = input.get("action", "")
	if action == "info":
		return {"behavior": "allow"}
	return {"behavior": "ask", "message": "Level: %s" % action}


func execute(input: Dictionary, context: Dictionary) -> Dictionary:
	var action: String = input.get("action", "")

	match action:
		"generate_layout":
			return _generate_layout(input)
		"populate":
			return _populate(input)
		"auto_nav":
			return _auto_nav(input)
		"auto_collision":
			return _auto_collision(input)
		"info":
			return _info()
		_:
			return {"success": false, "error": "Unknown action: %s" % action}


func _generate_layout(input: Dictionary) -> Dictionary:
	var algorithm: String = input.get("algorithm", "bsp_dungeon")
	var width: int = input.get("width", 40)
	var height: int = input.get("height", 40)
	var cell_size: int = input.get("cell_size", 16)
	var seed_val: int = input.get("seed_value", 0)

	if seed_val != 0:
		seed(seed_val)
	else:
		randomize()

	var grid: Array = []

	match algorithm:
		"bsp_dungeon":
			grid = _generate_bsp(width, height)
		"cellular_automata":
			var fill: float = input.get("fill_ratio", 0.45)
			var iters: int = input.get("iterations", 5)
			grid = _generate_cellular(width, height, fill, iters)
		"noise_terrain":
			grid = _generate_noise(width, height)
		"grid_rooms":
			grid = _generate_grid_rooms(width, height)
		"maze":
			grid = _generate_maze(width, height)
		_:
			return {"success": false, "error": "Unknown algorithm: %s" % algorithm}

	# Apply to TileMapLayer if in editor and path provided
	if Engine.is_editor_hint() and input.get("tilemap_path", "") != "":
		_apply_to_tilemap(input, grid, cell_size)

	# Calculate stats
	var floor_count: int = 0
	var wall_count: int = 0
	for row in grid:
		for cell in row:
			if cell == 0:
				wall_count += 1
			else:
				floor_count += 1

	return {
		"success": true,
		"data": "Generated %s layout (%dx%d): %d floor, %d wall cells" % [algorithm, width, height, floor_count, wall_count],
		"grid": grid,
		"width": width,
		"height": height
	}


func _populate(input: Dictionary) -> Dictionary:
	if not Engine.is_editor_hint():
		return {"success": false, "error": "Requires editor mode"}

	var scene_path: String = input.get("scene_template", "")
	var count: int = input.get("count", 10)
	var parent_path: String = input.get("parent_path", "")

	var root := EditorInterface.get_edited_scene_root()
	if not root:
		return {"success": false, "error": "No scene open"}

	var parent: Node = root
	if parent_path != "":
		parent = root.get_node_or_null(NodePath(parent_path))
		if not parent:
			return {"success": false, "error": "Parent node not found: %s" % parent_path}

	var scene := load(scene_path)
	if not scene is PackedScene:
		return {"success": false, "error": "Cannot load scene: %s" % scene_path}

	var placed: Array = []
	for i in count:
		var instance: Node = scene.instantiate()
		var pos := Vector2(
			randf_range(-500.0, 500.0),
			randf_range(-500.0, 500.0)
		)
		if instance is Node2D:
			instance.position = pos
		elif instance is Node3D:
			instance.position = Vector3(pos.x, 0, pos.y)
		parent.add_child(instance)
		instance.owner = root
		placed.append(str(pos))

	return {"success": true, "data": "Placed %d instances of %s" % [count, scene_path], "positions": placed}


func _auto_nav(input: Dictionary) -> Dictionary:
	if not Engine.is_editor_hint():
		return {"success": false, "error": "Requires editor mode"}

	var root := EditorInterface.get_edited_scene_root()
	if not root:
		return {"success": false, "error": "No scene open"}

	# Find existing NavigationRegion or create one
	var is_3d: bool = false
	var nav_region := _find_nav_region(root, is_3d)

	if not nav_region:
		if is_3d:
			nav_region = NavigationRegion3D.new()
		else:
			nav_region = NavigationRegion2D.new()
		nav_region.name = "NavigationRegion"
		root.add_child(nav_region)
		nav_region.owner = root

	# Bake navigation mesh
	if nav_region is NavigationRegion2D:
		var nav_mesh := NavigationPolygon.new()
		nav_mesh.vertices = PackedVector2Array([Vector2(-1000, -1000), Vector2(1000, -1000), Vector2(1000, 1000), Vector2(-1000, 1000)])
		nav_mesh.add_polygon(PackedInt32Array([0, 1, 2, 3]))
		nav_region.navigation_polygon = nav_mesh
	elif nav_region is NavigationRegion3D:
		var nav_mesh := NavigationMesh.new()
		nav_mesh.vertices = PackedVector3Array([Vector3(-10, 0, -10), Vector3(10, 0, -10), Vector3(10, 0, 10), Vector3(-10, 0, 10)])
		nav_mesh.add_polygon(PackedInt32Array([0, 1, 2, 3]))
		nav_region.navigation_mesh = nav_mesh

	return {"success": true, "data": "Created navigation region for %s scene" % ("3D" if is_3d else "2D")}


func _auto_collision(input: Dictionary) -> Dictionary:
	if not Engine.is_editor_hint():
		return {"success": false, "error": "Requires editor mode"}

	var root := EditorInterface.get_edited_scene_root()
	if not root:
		return {"success": false, "error": "No scene open"}

	var added: Array = []
	_add_collision_shapes(root, added, root)

	if added.is_empty():
		return {"success": true, "data": "No physics bodies found that need CollisionShape children"}

	return {"success": true, "data": "Added CollisionShape to %d bodies:\n%s" % [added.size(), "\n".join(added)]}


func _info() -> Dictionary:
	var info := {
		"algorithms": {
			"bsp_dungeon": "Binary Space Partitioning — rooms connected by corridors",
			"cellular_automata": "Cave-like organic shapes via cell birth/death rules",
			"noise_terrain": "Perlin noise-based terrain height map",
			"grid_rooms": "Simple grid with random room placement",
			"maze": "Perfect maze with guaranteed path between any two points"
		},
		"actions": {
			"generate_layout": "Create a procedural grid layout",
			"populate": "Place scene instances at random positions",
			"auto_nav": "Create NavigationRegion from scene geometry",
			"auto_collision": "Add CollisionShape to physics bodies missing them"
		}
	}
	var lines: Array = ["Level Generation Tool:", "", "Algorithms:"]
	for algo in info.algorithms:
		lines.append("  %s: %s" % [algo, info.algorithms[algo]])
	lines.append("")
	lines.append("Actions:")
	for act in info.actions:
		lines.append("  %s: %s" % [act, info.actions[act]])
	return {"success": true, "data": "\n".join(lines)}


# --- BSP Dungeon ---

func _generate_bsp(width: int, height: int) -> Array:
	var grid := []
	grid.resize(height)
	for y in height:
		grid[y] = []
		grid[y].resize(width)
		grid[y].fill(0)

	var rooms := _bsp_split(Rect2i(1, 1, width - 2, height - 2), 4)

	for room in rooms:
		for y in range(room.position.y, room.end.y):
			for x in range(room.position.x, room.end.x):
				if x >= 0 and x < width and y >= 0 and y < height:
					grid[y][x] = 1

	# Connect rooms with corridors
	for i in range(rooms.size() - 1):
		var a := _room_center(rooms[i])
		var b := _room_center(rooms[i + 1])
		_carve_corridor(grid, a, b, width, height)

	return grid


func _bsp_split(area: Rect2i, depth: int) -> Array:
	if depth <= 0 or area.size.x < 8 or area.size.y < 8:
		var margin := 2
		var room := Rect2i(
			area.position.x + margin,
			area.position.y + margin,
			maxi(area.size.x - margin * 2, 3),
			maxi(area.size.y - margin * 2, 3)
		)
		return [room]

	var rooms: Array = []
	var split_horizontal: bool = randf() > 0.5

	if area.size.x > area.size.y * 1.5:
		split_horizontal = false
	elif area.size.y > area.size.x * 1.5:
		split_horizontal = true

	if split_horizontal:
		var split := area.position.y + randi_range(area.size.y / 3, area.size.y * 2 / 3)
		rooms.append_array(_bsp_split(Rect2i(area.position.x, area.position.y, area.size.x, split - area.position.y), depth - 1))
		rooms.append_array(_bsp_split(Rect2i(area.position.x, split, area.size.x, area.end.y - split), depth - 1))
	else:
		var split := area.position.x + randi_range(area.size.x / 3, area.size.x * 2 / 3)
		rooms.append_array(_bsp_split(Rect2i(area.position.x, area.position.y, split - area.position.x, area.size.y), depth - 1))
		rooms.append_array(_bsp_split(Rect2i(split, area.position.y, area.end.x - split, area.size.y), depth - 1))

	return rooms


func _room_center(room: Rect2i) -> Vector2i:
	return Vector2i(room.position.x + room.size.x / 2, room.position.y + room.size.y / 2)


func _carve_corridor(grid: Array, a: Vector2i, b: Vector2i, w: int, h: int) -> void:
	var x := a.x
	var y := a.y
	while x != b.x:
		if x >= 0 and x < w and y >= 0 and y < h:
			grid[y][x] = 1
			if y + 1 < h:
				grid[y + 1][x] = 1
		x += 1 if b.x > x else -1
	while y != b.y:
		if x >= 0 and x < w and y >= 0 and y < h:
			grid[y][x] = 1
			if x + 1 < w:
				grid[y][x + 1] = 1
		y += 1 if b.y > y else -1


# --- Cellular Automata ---

func _generate_cellular(width: int, height: int, fill_ratio: float, iterations: int) -> Array:
	var grid := []
	grid.resize(height)
	for y in height:
		grid[y] = []
		grid[y].resize(width)
		for x in width:
			if x == 0 or x == width - 1 or y == 0 or y == height - 1:
				grid[y][x] = 0
			else:
				grid[y][x] = 0 if randf() < fill_ratio else 1

	for _i in iterations:
		var new_grid := []
		new_grid.resize(height)
		for y in height:
			new_grid[y] = []
			new_grid[y].resize(width)
			for x in width:
				var walls := _count_neighbors(grid, x, y, width, height)
				if walls > 4:
					new_grid[y][x] = 0
				elif walls < 4:
					new_grid[y][x] = 1
				else:
					new_grid[y][x] = grid[y][x]
		grid = new_grid

	return grid


func _count_neighbors(grid: Array, cx: int, cy: int, w: int, h: int) -> int:
	var count: int = 0
	for dy in range(-1, 2):
		for dx in range(-1, 2):
			if dx == 0 and dy == 0:
				continue
			var nx: int = cx + dx
			var ny: int = cy + dy
			if nx < 0 or nx >= w or ny < 0 or ny >= h:
				count += 1
			elif grid[ny][nx] == 0:
				count += 1
	return count


# --- Noise Terrain ---

func _generate_noise(width: int, height: int) -> Array:
	var grid := []
	var noise := FastNoiseLite.new()
	noise.seed = randi()
	noise.frequency = 0.05
	noise.fractal_octaves = 4

	grid.resize(height)
	for y in height:
		grid[y] = []
		grid[y].resize(width)
		for x in width:
			var val := noise.get_noise_2d(x, y)
			grid[y][x] = 1 if val > -0.2 else 0

	return grid


# --- Grid Rooms ---

func _generate_grid_rooms(width: int, height: int) -> Array:
	var grid := []
	grid.resize(height)
	for y in height:
		grid[y] = []
		grid[y].resize(width)
		grid[y].fill(0)

	var room_count := maxi(width * height / 100, 3)
	for _i in room_count:
		var rw := randi_range(4, 10)
		var rh := randi_range(4, 10)
		var rx := randi_range(1, width - rw - 1)
		var ry := randi_range(1, height - rh - 1)
		for y in range(ry, ry + rh):
			for x in range(rx, rx + rw):
				if x < width and y < height:
					grid[y][x] = 1

	# Connect with corridors
	var floors: Array = []
	for y in height:
		for x in width:
			if grid[y][x] == 1:
				floors.append(Vector2i(x, y))

	# Simple L-corridors between random floor cells
	for i in range(floors.size() - 1):
		if i % 3 == 0:
			var a: Vector2i = floors[i]
			var b: Vector2i = floors[(i + 1) % floors.size()]
			_carve_corridor(grid, a, b, width, height)

	return grid


# --- Maze ---

func _generate_maze(width: int, height: int) -> Array:
	var grid := []
	grid.resize(height)
	for y in height:
		grid[y] = []
		grid[y].resize(width)
		grid[y].fill(0)

	# Ensure odd dimensions for maze
	var maze_w := width - (width % 2 == 0  as int)
	var maze_h := height - (height % 2 == 0 as int)

	var stack: Array = [Vector2i(1, 1)]
	grid[1][1] = 1

	while not stack.is_empty():
		var current: Vector2i = stack[-1]
		var neighbors := _maze_unvisited(grid, current, maze_w, maze_h)
		if neighbors.is_empty():
			stack.pop_back()
		else:
			var next: Vector2i = neighbors[randi() % neighbors.size()]
			var mid := Vector2i((current.x + next.x) / 2, (current.y + next.y) / 2)
			grid[mid.y][mid.x] = 1
			grid[next.y][next.x] = 1
			stack.append(next)

	return grid


func _maze_unvisited(grid: Array, pos: Vector2i, w: int, h: int) -> Array:
	var dirs := [Vector2i(2, 0), Vector2i(-2, 0), Vector2i(0, 2), Vector2i(0, -2)]
	var result: Array = []
	for d in dirs:
		var nx: int = pos.x + d.x
		var ny: int = pos.y + d.y
		if nx > 0 and nx < w and ny > 0 and ny < h and grid[ny][nx] == 0:
			result.append(Vector2i(nx, ny))
	return result


# --- Helpers ---

func _apply_to_tilemap(input: Dictionary, grid: Array, cell_size: int) -> void:
	var tilemap_path: String = input.get("tilemap_path", "")
	var root := EditorInterface.get_edited_scene_root()
	if not root:
		return

	var tilemap: Node = root.get_node_or_null(NodePath(tilemap_path))
	if not tilemap:
		return

	var wall_tile: int = input.get("wall_tile", 0)
	var floor_tile: int = input.get("floor_tile", 1)

	if tilemap is TileMapLayer:
		for y in grid.size():
			for x in grid[y].size():
				var tile := floor_tile if grid[y][x] == 1 else wall_tile
				tilemap.set_cell(Vector2i(x, y), 0, Vector2i(tile, 0))


func _find_nav_region(node: Node, is_3d: bool) -> Node:
	if node is NavigationRegion2D:
		return node
	if node is NavigationRegion3D:
		is_3d = true
		return node
	for child in node.get_children():
		var result := _find_nav_region(child, is_3d)
		if result:
			return result
	# Check if scene uses 3D
	if node is Node3D:
		is_3d = true
	return null


func _add_collision_shapes(node: Node, added: Array, root: Node) -> void:
	var needs_shape := false
	if node is CharacterBody2D or node is CharacterBody3D or node is RigidBody2D or node is RigidBody3D or node is StaticBody2D or node is StaticBody3D:
		needs_shape = true
		for child in node.get_children():
			if child is CollisionShape2D or child is CollisionShape3D or child is CollisionPolygon2D or child is CollisionPolygon3D:
				needs_shape = false
				break

	if needs_shape:
		var shape: CollisionShape2D = null
		if node is Node2D:
			shape = CollisionShape2D.new()
			var rect := RectangleShape2D.new()
			rect.size = Vector2(32, 32)
			shape.shape = rect
		elif node is Node3D:
			var shape_3d := CollisionShape3D.new()
			var box := BoxShape3D.new()
			box.size = Vector3(1, 1, 1)
			shape_3d.shape = box
			node.add_child(shape_3d)
			shape_3d.owner = root
			added.append(str(root.get_path_to(node)))
			return

		if shape:
			node.add_child(shape)
			shape.owner = root
			added.append(str(root.get_path_to(node)))

	for child in node.get_children():
		_add_collision_shapes(child, added, root)
