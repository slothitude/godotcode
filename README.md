<p align="center">
  <img src="GodotCode_logo.png" alt="GodotCode" width="256">
</p>

# GodotCode

AI assistant editor plugin for Godot 4.6. Chat with an AI assistant directly inside the Godot editor — read/write project files, search code, run commands, and more.

## Features

- **Streaming chat** — Real-time SSE streaming with support for multiple LLM providers
- **File tools** — Read, write, and edit project files via tool calls
- **Live editor tools** — Inspect the scene tree, get/set node properties, capture screenshots, monitor errors, and install plugins at runtime
- **Code search** — Glob pattern matching and regex content search (Grep)
- **Shell execution** — Run bash commands with permission prompts
- **Web tools** — Fetch URLs and search the web
- **Sub-agents** — Delegate research tasks to spawned sub-agents
- **Task management** — Create, track, and update task lists
- **Scheduled prompts** — Cron-like timers that fire during your session
- **Slash commands** — `/compact`, `/commit`, `/review`, `/doctor`, `/memory`
- **Permission system** — Approval prompts for destructive operations, auto-approve read-only tools
- **Context awareness** — Automatically includes project.godot, file tree, CLAUDE.md, and current scene info in the system prompt
- **Cost tracking** — Token usage and cost display per session
- **Dark/light themes** — Customizable color schemes

## Install

1. Copy the `addons/godotcode/` folder into your Godot project's `addons/` directory
2. Open **Project → Project Settings → Plugins**
3. Enable the **GodotCode** plugin
4. The dock appears on the right side of the editor

## Configure

1. Click the **⚙** button in the dock header
2. Enter your API key
3. Select a model (e.g. `claude-sonnet-4-20250514`, `gpt-4o`, `gemini-2.0-flash`)
4. Adjust permission mode if needed

## Usage

Type a message in the input field and press **Enter** to send. The assistant will respond with streaming text and can use tools to interact with your project.

### Slash Commands

| Command | Description |
|---------|-------------|
| `/compact [N]` | Clear history, keeping last N messages (default 4) |
| `/commit [msg]` | Git commit workflow |
| `/review` | Start a code review of recent changes |
| `/doctor` | Run environment diagnostics |
| `/memory` | View persistent memory files |

### Permission Modes

| Mode | Behavior |
|------|----------|
| `default` | Read-only tools auto-approve, write/execute tools require approval |
| `plan` | Only read-only tools allowed |
| `bypass` | All tools auto-approved (use with caution) |

## Architecture

```
addons/godotcode/
├── plugin.cfg                 # Plugin metadata
├── plugin.gd                  # EditorPlugin entry point
├── core/
│   ├── api_client.gd          # LLM provider API (HTTP + SSE streaming)
│   ├── query_engine.gd        # Core loop: stream → tool calls → execute → repeat
│   ├── message_types.gd       # Message data classes with API serialization
│   ├── tool_registry.gd       # Tool registration and lookup
│   ├── conversation_history.gd # Conversation persistence
│   ├── context_manager.gd     # Project context for system prompt
│   ├── permission_manager.gd  # Permission prompt system
│   ├── cost_tracker.gd        # Token usage and cost tracking
│   └── settings.gd            # Editor settings storage
├── tools/
│   ├── base_tool.gd           # Abstract base class
│   ├── file_read_tool.gd
│   ├── file_write_tool.gd
│   ├── file_edit_tool.gd
│   ├── glob_tool.gd
│   ├── grep_tool.gd
│   ├── bash_tool.gd
│   ├── web_search_tool.gd
│   ├── web_fetch_tool.gd
│   ├── agent_tool.gd
│   ├── task_tools.gd
│   ├── schedule_tools.gd
│   ├── plan_mode_tool.gd
│   ├── sleep_tool.gd
│   ├── scene_tree_tool.gd      # Live scene tree inspection & manipulation
│   ├── node_property_tool.gd   # Get/set node properties at runtime
│   ├── screenshot_tool.gd      # Viewport capture with vision pipeline
│   ├── error_monitor_tool.gd   # Editor error/warning log reader
│   └── plugin_writer_tool.gd   # Self-extending plugin installer
├── commands/
│   ├── base_command.gd
│   ├── compact_command.gd
│   ├── commit_command.gd
│   ├── review_command.gd
│   ├── doctor_command.gd
│   └── memory_command.gd
├── ui/
│   ├── chat_panel.tscn/.gd
│   ├── message_display.tscn/.gd
│   ├── code_block.tscn/.gd
│   ├── settings_dialog.tscn/.gd
│   ├── tool_approval_dialog.tscn/.gd
│   └── theme.gd
└── tests/
    ├── unit/                  # GDUnit tests
    └── scenes/                # Integration test scenes
```

## Requirements

- Godot 4.6+
- API key from a supported LLM provider
- (Optional) GDUnit4 for running tests

## License

MIT
