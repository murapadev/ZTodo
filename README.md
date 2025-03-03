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

The plugin uses these default paths which can be overridden in your `~/.zshrc`:

```bash
# Database location
ZTODO_DB_PATH="$HOME/.ztodo.db"

# Config file location (for future use)
ZTODO_CONFIG_PATH="$HOME/.ztodo.conf"
```

## Features

- SQLite-based persistent storage
- Color-coded priority levels
- Task categorization
- Deadline tracking
- Task completion tracking
- Efficient search capabilities
- Automatic cleanup of expired tasks

## License

Apache License 2.0