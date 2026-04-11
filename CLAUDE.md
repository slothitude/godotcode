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

### Tool System

All tools extend `GCBaseTool` (RefCounted) and implement:
- `tool_name`, `description`, `input_schema` — API definition
- `is_read_only` — permission hint (read-only tools auto-approve)
- `validate_input(input)` → `{valid: bool}`
- `check_permissions(input, context)` → `{behavior: "allow"|"ask"|"deny"}`
- `execute(input, context)` → `{success: bool, data: ..., error: ...}`
- `to_tool_definition()` / `to_api_result()` — API serialization

Tools receive a `context` Dictionary with `project_path`, `conversation_history`, `tool_registry`, `settings`.

### Core Components

- **`GCApiClient`** — Multi-provider LLM API (Anthropic, OpenAI, OpenAI-compatible) with SSE streaming
- **`GCContextManager`** — Builds system prompt from project state (project.godot, file tree, CLAUDE.md, current scene)
- **`GCConversationHistory`** — Message storage with JSON persistence and compaction
- **`GCPermissionManager`** — Three modes: `default` (read auto-approve, write ask), `plan` (read-only), `bypass` (all auto)
- **`GCSettings`** — EditorSettings wrapper for API keys, model, provider, theme
- **`GCCostTracker`** — Token usage and cost tracking per session

### Key Directories

- `addons/godotcode/core/` — Core systems (query engine, API client, message types, tool registry)
- `addons/godotcode/tools/` — 19+ tool implementations
- `addons/godotcode/commands/` — Slash commands (`/compact`, `/commit`, `/review`, `/doctor`, `/memory`)
- `addons/godotcode/ui/` — Godot scenes (.tscn) and scripts (.gd) for the dock panel
- `addons/godotcode/tests/` — Unit (GDUnit4), integration (test scenes), and live API tests

## Naming Conventions

- **Class prefix:** `GC` (e.g., `GCQueryEngine`, `GCFileReadTool`)
- **Tools:** `GC*Tool` suffix
- **Commands:** `GC*Command` suffix
- **Private members:** `_prefix` (e.g., `_settings`, `_api_client`)

## Patterns

- **Signals** for async communication between components (e.g., `stream_text_delta`, `query_complete`, `permission_requested`)
- **await** for long-running operations (HTTP requests, process frames)
- **Dictionary-based** message format for LLM API compatibility
- Tool results use `{success: bool, data: ..., error: ...}` consistently
- Vision results tagged with `{is_vision: true, vision_data: base64, media_type: "..."}`
- File paths support both absolute and `res://` protocol via `ProjectSettings.globalize_path()`

## Adding a New Tool

1. Create `addons/godotcode/tools/your_tool.gd` extending `GCBaseTool`
2. Set `tool_name`, `description`, `input_schema`, `is_read_only` in constructor
3. Override `execute(input, context)` returning `{success, data/error}`
4. Register in `plugin.gd` → `_register_tools()`

## Adding a New Slash Command

1. Create `addons/godotcode/commands/your_command.gd` extending `GCBaseCommand`
2. Implement `command_name`, `description`, `execute(args, context)`
3. Register in `plugin.gd` → `_register_commands()`
