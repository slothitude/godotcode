# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

GodotCode is an AI assistant editor plugin for Godot 4.6, written in GDScript. It provides Claude-powered conversational AI inside the Godot editor with file tools, live scene manipulation, image generation, and self-extending plugin capabilities.

## Development Commands

- **Start GodotCode (clean sandbox):** `./start_godotcode.sh` — creates a fresh project at `~/godotcode-sandbox` and opens the editor. Pass a custom path as arg: `./start_godotcode.sh /path/to/project`
- **Run editor on this repo:** `"C:/Users/aaron/Godot/Godot_v4.6.1-stable_win64.exe" --editor --path .`
- **Run headless test (any script):** `"C:/Users/aaron/Godot/Godot_v4.6.1-stable_win64.exe" --headless --script addons/godotcode/tests/<test_file>.gd`
- **Run integration tests:** Open test scenes in `addons/godotcode/tests/scenes/` in the editor and press F5

### Headless test scripts

```bash
# Power-up features (12 features, 100 tests)
"C:/Users/aaron/Godot/Godot_v4.6.1-stable_win64.exe" --headless --script addons/godotcode/tests/test_powerups.gd

# NVIDIA image generation (live API)
"C:/Users/aaron/Godot/Godot_v4.6.1-stable_win64.exe" --headless --script addons/godotcode/tests/test_nvidia_gen.gd

# Image display and vision pipeline
"C:/Users/aaron/Godot/Godot_v4.6.1-stable_win64.exe" --headless --script addons/godotcode/tests/test_image_display.gd

# Image fetch integration
"C:/Users/aaron/Godot/Godot_v4.6.1-stable_win64.exe" --headless --script addons/godotcode/tests/test_image_fetch_integration.gd
```

### GDUnit4 unit tests

Located in `addons/godotcode/tests/unit/` — run from the editor via the GDUnit4 plugin panel.

No build step required — Godot loads plugins dynamically.

## Architecture

### Agent Loop (core system)

`GCQueryEngine` implements the main loop: **stream LLM response → parse tool calls → execute tools → feed results back → repeat** (max 50 iterations). State machine: `IDLE → STREAMING → TOOL_EXECUTING → COMPLETE`.

The execution pipeline includes pre/post hooks:
- **Pre-tool**: undo stack push (for Write/Edit), visual diff capture (for scene mutations), user hooks
- **Post-tool**: visual diff after-capture, user hooks, model router resolution
- **Pre-query / Post-query**: user hooks, auto-save
- **On-error**: user hooks

### Tool System

All tools extend `GCBaseTool` (RefCounted) and implement:
- `tool_name`, `description`, `input_schema` — API definition
- `is_read_only` — permission hint (read-only tools auto-approve)
- `validate_input(input)` → `{valid: bool}`
- `check_permissions(input, context)` → `{behavior: "allow"|"ask"|"deny"}`
- `execute(input, context)` → `{success: bool, data: ..., error: ...}`
- `to_tool_definition()` / `to_api_result()` — API serialization

Tools receive a `context` Dictionary with `project_path`, `conversation_history`, `tool_registry`, `settings`, `memory_manager`, `runtime_monitor`, `visual_diff`, `asset_manager`, `mcp_client`.

### Core Components

- **`GCApiClient`** — Multi-provider LLM API (Anthropic, OpenAI, OpenAI-compatible) with SSE streaming and model overrides
- **`GCContextManager`** — Builds system prompt from project state (project.godot, file tree, CLAUDE.md, persistent memory, runtime state)
- **`GCConversationHistory`** — Message storage with JSON persistence and compaction
- **`GCPermissionManager`** — Three modes: `default` (read auto-approve, write ask), `plan` (read-only), `bypass` (all auto)
- **`GCSettings`** — EditorSettings wrapper for API keys, model, provider, theme, MCP servers
- **`GCCostTracker`** — Token usage and cost tracking per session
- **`GCUndoStack`** — Safety net for AI file operations (max 100 entries)
- **`GCMemoryManager`** — Persistent memories stored in `user://claude_memory/*.md`, auto-injected into system prompt
- **`GCSessionManager`** — Save/resume conversations across editor restarts (`user://godotcode_sessions/`)
- **`GCRuntimeMonitor`** — Live game state inspection during play mode
- **`GCVisualDiff`** — Before/after screenshots around scene mutations
- **`GCAssetManager`** — Import images, create materials, apply textures to nodes
- **`GCHooksManager`** — User-configurable pre/post execution hooks (`user://godotcode_hooks.json`)
- **`GCMCPClient`** — Connect to external MCP tool servers via HTTP transport
- **`GCModelRouter`** — Per-tool model/cost routing (`user://godotcode_model_routing.json`)
- **`GCCustomCommandLoader`** — Load user commands from `res://.godotcode/commands/*.gd`

### Tools (28 total)

**File & Search:** Read, Write, Edit, Glob, Grep, Bash, WebSearch, WebFetch
**Agent & Planning:** Agent, EnterPlanMode, TaskManage, Schedule, Sleep
**Editor Live:** SceneTree, NodeProperty, Screenshot, ErrorMonitor, PluginWriter
**Image:** ImageGen, ImageFetch
**Power-Ups:** Git, Memory, RuntimeState, VisualDiff, AssetPipeline, Shader, MCP

### Slash Commands

- `/compact [N]` — Clear history, keep last N messages
- `/commit [msg]` — Git commit workflow
- `/review` — Code review prompt
- `/doctor` — Environment diagnostics
- `/memory [clear]` — View persistent memory
- `/undo [list|clear]` — Undo AI file changes
- `/session [list|save|load|delete|new]` — Manage conversation sessions

### Key Directories

- `addons/godotcode/core/` — Core systems (query engine, API client, message types, tool registry, managers)
- `addons/godotcode/tools/` — 28 tool implementations
- `addons/godotcode/commands/` — Slash commands + custom command loader
- `addons/godotcode/ui/` — Godot scenes (.tscn) and scripts (.gd) for the dock panel
- `addons/godotcode/tests/` — Unit (GDUnit4), integration (test scenes), live API tests, power-up test suite

## Naming Conventions

- **Class prefix:** `GC` (e.g., `GCQueryEngine`, `GCFileReadTool`)
- **Tools:** `GC*Tool` suffix
- **Commands:** `GC*Command` suffix
- **Private members:** `_prefix` (e.g., `_settings`, `_api_client`)

## Patterns

- **Signals** for async communication between components (e.g., `stream_text_delta`, `query_complete`, `permission_requested`)
- **await** for long-running operations (HTTP requests, process frames, thread joins)
- **Dictionary-based** message format for LLM API compatibility
- Tool results use `{success: bool, data: ..., error: ...}` consistently
- Vision results tagged with `{is_vision: true, vision_data: base64, media_type: "..."}`
- File paths support both absolute and `res://` protocol via `ProjectSettings.globalize_path()`
- **GDScript type inference caveat:** Use explicit types (`var x: Dictionary = ...`) when assigning from variant-returning functions (`.get()`, `await`, array index). Avoid `\x` escape sequences — use `char(N)` instead.
- **Windows caveat:** Don't use `bash -c` in `OS.execute()`. Call executables directly with argument arrays.

## Adding a New Tool

1. Create `addons/godotcode/tools/your_tool.gd` extending `GCBaseTool`
2. Set `tool_name`, `description`, `input_schema`, `is_read_only` in constructor
3. Override `execute(input, context)` returning `{success, data/error}`
4. Register in `plugin.gd` → `_register_tools()`
5. Add permission rule in `permission_manager.gd` → `_rules`

## Adding a New Slash Command

1. Create `addons/godotcode/commands/your_command.gd` extending `GCBaseCommand`
2. Implement `command_name`, `description`, `execute(args, context)`
3. Register in `plugin.gd` → `_register_commands()`

Or drop `.gd` files extending `GCBaseCommand` into `res://.godotcode/commands/` for auto-loading (no plugin.gd changes needed).
