# GodotCode — future vision

## What it is now

GodotCode is an AI assistant editor plugin for Godot 4.6. It lives in a dock panel inside the editor. It streams responses from Claude, calls tools to read and write project files, runs shell commands, spawns sub-agents, tracks tasks, and manages conversation memory. The architecture is already solid:

- `QueryEngine` — drives the agent loop, handles SSE streaming and tool call cycles
- `ToolRegistry` — all agent actions registered and dispatched here
- `PermissionManager` — policy gates on destructive operations
- `ContextManager` — builds the system prompt from project state, CLAUDE.md, scene info
- `ConversationHistory` — persistent memory across sessions
- `agent_tool.gd` — sub-agents for parallel research tasks
- `task_tools.gd` — task creation, tracking, updates
- `schedule_tools.gd` — cron-like scheduled prompts during a session
- `memory_command.gd` — persistent memory files
- Slash commands: `/compact`, `/commit`, `/review`, `/doctor`, `/memory`

Everything in the README is real and working. The question is where it goes next.

---

## The core insight

GodotCode is not a plugin that assists with game development. It is an **agent runtime that inhabits a physics-simulated, visually-rendered, self-extensible world** — and builds that world by acting in it.

Every other AI coding tool operates on files. GodotCode can operate on a **live running world**. That is a fundamentally different category.

---

## Three additions that change the category

### 1. Live editor tools

Current tools interact with the project via the filesystem. The next level is interacting directly with the editor's runtime state via `EditorInterface`.

```gdscript
# read the live scene tree — no file I/O
var root = EditorInterface.get_edited_scene_root()

# add a node directly into the running editor
var node = Node3D.new()
node.name = "PatrolPoint"
root.add_child(node)
node.owner = root
node.position = Vector3(10, 0, 5)

# read any node property live
var hp = root.find_child("Player").get("max_health")
```

Tools to build:

- `scene_tree_tool.gd` — read scene tree, add/delete/reparent nodes, set properties
- `node_property_tool.gd` — get/set any exported or internal property on any node
- `error_monitor_tool.gd` — tap editor error signals, return live diagnostics
- `resource_scan_tool.gd` — inventory all project resources by type

The difference between file tools and live editor tools is the difference between reading a blueprint and touching the building.

### 2. Vision loop

Capture the editor viewport, send it to Claude's vision API, close the feedback loop.

```gdscript
# capture editor viewport as PNG
var viewport = EditorInterface.get_editor_viewport_3d(0)
var img = viewport.get_texture().get_image()
img.save_png("/tmp/godotcode_frame.png")
# base64 encode → include as vision content in next Claude message
```

This makes the agent able to **see**. It can look at the result of its own actions, decide whether they achieved the goal, and iterate. "Fix the lighting" becomes a loop: act → screenshot → evaluate → act again. No human relay required.

### 3. Plugin writer tool

This is the unlock. GodotCode can write GDScript plugins and install them into the editor at runtime — extending its own capability set within a single session.

```gdscript
# plugin_writer_tool.gd
func execute(params):
    var dir = "res://addons/godotcode_%s/" % params.name
    DirAccess.make_dir_recursive_absolute(dir)
    FileAccess.open(dir + "plugin.cfg", FileAccess.WRITE).store_string(params.plugin_cfg)
    FileAccess.open(dir + "plugin.gd",  FileAccess.WRITE).store_string(params.gdscript_code)
    EditorInterface.get_resource_filesystem().scan()
    # enable plugin programmatically
    var enabled = ProjectSettings.get_setting("editor_plugins/enabled", [])
    enabled.append("addons/godotcode_%s/plugin.cfg" % params.name)
    ProjectSettings.set_setting("editor_plugins/enabled", enabled)
    return { "status": "installed", "name": params.name }
```

The system prompt clause that activates this:

> If you need a capability you don't have, write a GDScript EditorPlugin that provides it.
> Use plugin_writer_tool to install it into the project, then use it to complete the task.
> You are not limited to your current toolset. You can extend yourself.

**The compounding property:** every plugin GodotCode writes is a permanent capability addition to the project. Session two, it already has the tools it wrote in session one. The capability surface grows with every conversation. This is the opposite of every fixed-tool AI assistant.

---

## What the plugin compiler enables

These are not hypothetical. Each one is a single agent session:

**Procedural dungeon generator** — GodotCode writes a dock plugin with generation parameters, installs it, uses it to build a dungeon, previews the result via screenshot, iterates on the seed until it meets the design brief.

**Live shader editor** — Writes a plugin that exposes GLSL uniform sliders, captures the viewport after each change, evaluates the visual result, iterates until the description matches the output.

**Signal graph visualiser** — Writes a plugin that maps all node signal connections as an interactive diagram inside a second editor panel.

**Playtesting agent** — Writes an `@tool` script, runs the game headlessly, reads debug output, identifies failure modes, patches the scripts, reruns. All in one loop.

**Animation state machine builder** — Writes a plugin that generates `AnimationTree` state machine transitions from a natural language description of game states.

**Lore database** — Writes a plugin backed by a SQLite `.tres` resource, lets Claude query and write game narrative directly into the resource system.

None of these require changes to the GodotCode kernel. They are capabilities the agent bootstraps for itself.

---

## The self-extension loop

```
request arrives
    ↓
ToolRegistry lookup
    ↓ (tool missing)
Claude writes plugin_gd + plugin_cfg
    ↓
plugin_writer_tool installs to addons/
    ↓
EditorInterface reloads plugin
    ↓
ToolRegistry.register(new_tool)
    ↓
original request re-executes
    ↓ (now has the tool)
result
```

This loop runs within a single agent cycle. The user does not see the mechanism — they see the result.

---

## Permission model

The existing `PermissionManager` applies to plugin installation:

| Mode | Behaviour |
|------|-----------|
| `plan` | Describe the plugin that would be written, don't install |
| `default` | Show the plugin code as a diff, require explicit approval before install |
| `bypass` | Fully autonomous — install and execute without prompts |

The kernel is always auditable. Every plugin is inspectable GDScript before it runs.

---

## Architecture after the rebuild

```
Godot editor process
└── GodotCode plugin (the kernel — small, stable, never changes)
    ├── core/
    │   ├── query_engine.gd        ← agent loop
    │   ├── tool_registry.gd       ← all actions registered here
    │   ├── permission_manager.gd  ← policy gates
    │   ├── context_manager.gd     ← world state → system prompt
    │   ├── conversation_history.gd
    │   └── cost_tracker.gd
    ├── tools/
    │   ├── [existing 14 tools]
    │   ├── scene_tree_tool.gd     ← NEW: live world read/write
    │   ├── node_property_tool.gd  ← NEW: live property access
    │   ├── screenshot_tool.gd     ← NEW: vision sense
    │   ├── error_monitor_tool.gd  ← NEW: live diagnostics
    │   └── plugin_writer_tool.gd  ← NEW: self-extension
    └── addons/                    ← self-written, grows each session
        ├── godotcode_dungeon/
        ├── godotcode_shader_editor/
        ├── godotcode_signal_graph/
        └── ... (unbounded)
```

The kernel is a fixed surface. The `addons/` directory is unbounded. The agent decides what goes in it.

---

## Build order

1. `scene_tree_tool.gd` — highest leverage, immediate capability jump, 2–3 hours
2. `error_monitor_tool.gd` — tap editor signals for live diagnostics, 1 hour
3. `screenshot_tool.gd` — viewport capture + base64 for vision loop, 1 hour
4. `plugin_writer_tool.gd` + system prompt clause — self-extension, 2–3 hours
5. `node_property_tool.gd` — completes the live editor surface, 1 hour

Total: one focused day to shift from file-level assistant to world-level agent.

---

## What this is, stated plainly

Every other AI coding tool reads and writes files.

GodotCode acts in a live physics-simulated world, sees the results through a viewport, and extends its own capabilities by writing and installing new tools — within a single conversation.

The plugin is the compiler. The world is the context window. The agent is the developer.
