# ZTodo - Oh-My-Zsh Todo Plugin

A SQLite-based todo plugin for Oh-My-Zsh, providing persistent storage and efficient task management.

## Requirements

- Oh-My-Zsh
- SQLite3
- Zsh

## Installation

1. Install sqlite3 if not already installed:

   ```bash
   # Ubuntu/Debian
   sudo apt install sqlite3

   # CentOS/RHEL
   sudo yum install sqlite

   # Arch
   sudo pacman -Sy sqlite

   # macOS
   brew install sqlite

   ```

2. Clone this repository into your Oh-My-Zsh custom plugins directory:

   ```bash
   git clone https://github.com/murapa96/ztodo ${ZSH_CUSTOM:-~/.oh-my-zsh/custom}/plugins/ztodo
   ```

3. Add `ztodo` to your plugins array in `~/.zshrc`:

   ```bash
   plugins=(... ztodo)
   ```

4. Reload your shell:
   ```bash
   source ~/.zshrc
   ```

## Usage

- `ztodo add` - Add a new todo item
- `ztodo list` - List all active todo items
- `ztodo remove <id>` - Remove a specific todo item
- `ztodo complete <id>` - Mark a todo item as complete
- `ztodo clear` - Remove expired and completed tasks
- `ztodo search <keyword>` - Search tasks by keyword
- `ztodo timer <start|stop|status> [id]` - Time tracking utilities
- `ztodo sub <add|list|complete|remove> ...` - Manage subtasks
- `ztodo export [csv] [file]` - Export tasks (CSV)
- `ztodo import csv <file>` - Import tasks from CSV
- `ztodo export json [file]` - Export tasks to JSON
- `ztodo import json <file>` - Import tasks from JSON (same shape as export)
- `ztodo share export <id>` - Generate a share code (Base64 JSON) for one task
- `ztodo share import <code>` - Import a task from a share code
- `ztodo tui` - Minimal interactive UI (requires `fzf`)
- `ztodo projects` - List projects with task counts
- `ztodo history [id]` - Show recent events (optionally per task)
- `ztodo template create|apply|list` - Manage task templates
- `ztodo calendar [month|week] [date]` - ASCII calendar (deadlines)
- `ztodo focus <id>` / `ztodo unfocus` / `ztodo context` - Per-task shell history context
- `ztodo report <today|week>` - Compact per-task summary (commands/time)
- `ztodo help` - Show help message

## Features

- SQLite-based persistent storage
- Color-coded priority levels
- Task categorization
- Deadline tracking
- Task completion tracking
- Efficient search capabilities
- Automatic cleanup of expired tasks
- Recurring tasks (basic: daily/weekly/monthly when completing a task)
- Time tracking (start/stop/status with per-task minutes)
- Subtasks (create/list/complete/remove)
- CSV export/import
- JSON export/import
- Offline share codes (Base64 JSON per task)
- Minimal TUI via `fzf` (complete or delete)
- Per-task shell history (opt-in, via focus)

## Configuration

### Option 1: Using the configuration file (default)

The plugin will automatically create a configuration file at `~/.ztodo.conf` if it doesn't exist. You can customize the following settings:

```bash
# Database location
ZTODO_DB_PATH="$HOME/.ztodo.db"

# Default task settings
ZTODO_DEFAULT_CATEGORY="general"
ZTODO_DEFAULT_PRIORITY=2  # 1=high, 2=medium, 3=low

# Notification settings
ZTODO_SHOW_UPCOMING_DEADLINES="true"  # Show upcoming deadlines when opening a terminal
ZTODO_UPCOMING_DAYS=7  # Number of days to look ahead for deadlines

# Display settings
ZTODO_COLOR_ENABLED="true"  # Enable colored output

# Per-task shell history (opt-in)
ZTODO_HISTORY_ENABLED="false"          # enable logging of commands for a focused task
ZTODO_HISTORY_CAPTURE_PWD="true"       # include current working directory
ZTODO_HISTORY_IGNORE="pass,token,secret"  # comma-separated substrings to skip
```

See [Configuration File](ztodo.conf.template) for an example.

### Option 2: Using .zshrc directly

If you prefer to manage all configuration in your `.zshrc` file, you can disable the configuration file:

```bash
# Disable the configuration file
ZTODO_USE_CONFIG_FILE="false"

# Then set your configuration options
ZTODO_DB_PATH="$HOME/my-tasks.db"
ZTODO_DEFAULT_CATEGORY="work"
ZTODO_DEFAULT_PRIORITY=1
ZTODO_SHOW_UPCOMING_DEADLINES="true"
ZTODO_UPCOMING_DAYS=5
ZTODO_COLOR_ENABLED="true"

# These must be set before Oh-My-Zsh loads the plugin
plugins=(... ztodo)
source $ZSH/oh-my-zsh.sh
```

### Overriding the configuration file location

You can also change the location of the configuration file:

```bash
# Set custom config path before loading oh-my-zsh
ZTODO_CONFIG_PATH="$HOME/Documents/ztodo-config.conf"

# Then load oh-my-zsh
source $ZSH/oh-my-zsh.sh
```

## Roadmap

These are features we're planning to implement in the future:


### Enhanced Features

- [x] **Recurring Tasks**: Set up tasks that repeat on daily, weekly, monthly, or custom schedules.
- [x] **Time Tracking**: Track how long you spend on each task.
- [x] **Subtasks Support**: Break down complex tasks into manageable subtasks.
- [x] **Project Management**: Group tasks into projects for better organization.
- [x] **Calendar View**: ASCII month/week views highlighting deadlines.
- [x] **Data Export/Import**: Export/Import tasks as CSV and JSON.
- [x] **Task Templates**: Create templates for common task types with predefined attributes.
- [ ] **Team Sharing**: Share tasks with team members (requires server component).
- [x] **Per Task History**: Opt-in shell command logging tied to a focused task.

#### Per Task History Enhancements

- [x] Basic redactor for common secret patterns (e.g., masks values after `--password=`, `TOKEN=...`).
- [x] Persist focused task across terminals (opt-in), with simple cache file.
- [x] Compact reports, e.g., `ztodo report today` to summarize time and commands.

### UI Improvements

- [x] **Interactive TUI**: A minimal fzf-based TUI for quick actions.
- [ ] **Notifications**: Desktop notifications for upcoming deadlines and reminders.

If you'd like to contribute to any of these features, please check out our [Contributing Guide](CONTRIBUTING.md).

## License

Apache License 2.0
