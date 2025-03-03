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
- `ztodo help` - Show help message

## Configuration

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
```

You can override these paths in your `~/.zshrc` before Oh-My-Zsh loads the plugin:

```bash
# Override paths before loading oh-my-zsh
ZTODO_DB_PATH="$HOME/custom/path/to/db"
ZTODO_CONFIG_PATH="$HOME/custom/path/to/config"

# Then load oh-my-zsh
source $ZSH/oh-my-zsh.sh
```

## Features

- SQLite-based persistent storage
- Color-coded priority levels
- Task categorization
- Deadline tracking
- Task completion tracking
- Efficient search capabilities
- Automatic cleanup of expired tasks

## Roadmap

These are features we're planning to implement in the future:

### Third-party Integrations

- **ClickUp Integration**: Sync tasks with your ClickUp workspaces, push local tasks to ClickUp, and pull assigned tasks to your local environment.
- **Notion Integration**: Seamlessly sync with Notion databases, enabling bidirectional updates between ZTodo and your Notion workspace.
- **GitHub Issues**: Convert GitHub issues to local tasks and vice versa, ideal for developers managing project tasks.
- **Jira Integration**: For enterprise users, sync with Jira tickets and track work across platforms.

### Enhanced Features

- **Recurring Tasks**: Set up tasks that repeat on daily, weekly, monthly, or custom schedules.
- **Time Tracking**: Track how long you spend on each task.
- **Subtasks Support**: Break down complex tasks into manageable subtasks.
- **Calendar View**: Visual representation of your deadlines in calendar format.
- **Data Export/Import**: Export your tasks as CSV/JSON and import from various formats.
- **Task Templates**: Create templates for common task types with predefined attributes.
- **Team Sharing**: Share tasks with team members (requires server component).
- **Per Task History**: Configure your ZSH history to log task-related commands.


### UI Improvements

- **Interactive TUI**: A full terminal user interface for easier task management.
- **Custom Theming**: Define your own color schemes and styling.
- **Dashboard View**: Overview of task statistics and upcoming deadlines.
- **Notifications**: Desktop notifications for upcoming deadlines and reminders.
- **Mobile App**: Companion app for managing tasks on the go.
- **Web Interface**: A web-based dashboard for managing tasks from any device.

If you'd like to contribute to any of these features, please check out our [Contributing Guide](CONTRIBUTING.md).

## License

Apache License 2.0