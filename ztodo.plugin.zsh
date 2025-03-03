#!/usr/bin/env zsh

# ------------------------------
# ZTodo: SQLite-based Todo Plugin for Oh-My-Zsh
# ------------------------------

# Default configuration
ZTODO_DB_PATH="${ZTODO_DB_PATH:-$HOME/.ztodo.db}"
ZTODO_CONFIG_PATH="${ZTODO_CONFIG_PATH:-$HOME/.ztodo.conf}"
# Allow users to disable config file and use .zshrc values directly
ZTODO_USE_CONFIG_FILE="${ZTODO_USE_CONFIG_FILE:-true}"

# Initialize config file if it doesn't exist and if config file usage is enabled
_ztodo_init_config() {
  if [[ "${ZTODO_USE_CONFIG_FILE}" != "true" ]]; then
    return 0
  fi

  if [[ ! -f "$ZTODO_CONFIG_PATH" ]]; then
    local template_path="${0:A:h}/ztodo.conf.template"
    if [[ -f "$template_path" ]]; then
      echo "Creating default ZTodo configuration at $ZTODO_CONFIG_PATH"
      cp "$template_path" "$ZTODO_CONFIG_PATH"
    else
      echo "${YELLOW}Warning: Could not find configuration template at $template_path${NC}"
      # Create minimal config
      cat > "$ZTODO_CONFIG_PATH" <<EOF
# ZTodo Configuration File
ZTODO_DB_PATH="$HOME/.ztodo.db"
ZTODO_DEFAULT_CATEGORY="general"
ZTODO_DEFAULT_PRIORITY=2
ZTODO_SHOW_UPCOMING_DEADLINES="true"
ZTODO_UPCOMING_DAYS=7
ZTODO_COLOR_ENABLED="true"
EOF
    fi
  fi
}

# Import configuration if exists and if config file usage is enabled
_ztodo_init_config
if [[ "${ZTODO_USE_CONFIG_FILE}" == "true" && -f "$ZTODO_CONFIG_PATH" ]]; then
  source "$ZTODO_CONFIG_PATH"
fi

# Colors - only apply if enabled in config
if [[ "${ZTODO_COLOR_ENABLED:-true}" == "true" ]]; then
  RED='\033[0;31m'
  YELLOW='\033[0;33m'
  GREEN='\033[0;32m'
  BLUE='\033[0;34m'
  PURPLE='\033[0;35m'
  NC='\033[0m' # No Color
else
  RED=''
  YELLOW=''
  GREEN=''
  BLUE=''
  PURPLE=''
  NC=''
fi

# Initialize database if not exists
_ztodo_init_db() {
  if [[ ! -f "$ZTODO_DB_PATH" ]]; then
    echo "Initializing ZTodo database at $ZTODO_DB_PATH"
    sqlite3 "$ZTODO_DB_PATH" <<EOF
CREATE TABLE tasks (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  title TEXT NOT NULL,
  description TEXT,
  category TEXT DEFAULT 'general',
  priority INTEGER DEFAULT 2, -- 1 (high), 2 (medium), 3 (low)
  deadline TEXT, -- ISO8601 format YYYY-MM-DD
  created_at TEXT DEFAULT CURRENT_TIMESTAMP,
  completed INTEGER DEFAULT 0, -- 0 (not completed), 1 (completed)
  completed_at TEXT
);

CREATE INDEX idx_tasks_category ON tasks(category);
CREATE INDEX idx_tasks_priority ON tasks(priority);
CREATE INDEX idx_tasks_completed ON tasks(completed);
EOF
  fi
}

# Check if database exists, create if not
_ztodo_ensure_db() {
  if ! command -v sqlite3 &> /dev/null; then
    echo "${RED}Error: sqlite3 is not installed. Please install it before using ZTodo.${NC}"
    return 1
  fi
  
  _ztodo_init_db
}

# Format date for display
_ztodo_format_date() {
  local date_str="$1"
  if [[ -z "$date_str" ]]; then
    echo "No date"
  else
    echo "$date_str"
  fi
}

# Format priority for display
_ztodo_format_priority() {
  local priority="$1"
  case "$priority" in
    1) echo "${RED}High${NC}" ;;
    2) echo "${YELLOW}Medium${NC}" ;;
    3) echo "${GREEN}Low${NC}" ;;
    *) echo "Unknown" ;;
  esac
}

# Add a new task
ztodo_add() {
  _ztodo_ensure_db || return 1
  
  local title description category priority deadline
  
  # Get task details
  read -r "title?Task title: "
  [[ -z "$title" ]] && { echo "${RED}Error: Title cannot be empty${NC}"; return 1; }
  
  read -r "description?Description (optional): "
  
  read -r "category?Category (default: ${ZTODO_DEFAULT_CATEGORY:-general}): "
  category="${category:-${ZTODO_DEFAULT_CATEGORY:-general}}"
  
  read -r "priority?Priority (1-High, 2-Medium, 3-Low, default: ${ZTODO_DEFAULT_PRIORITY:-2}): "
  priority="${priority:-${ZTODO_DEFAULT_PRIORITY:-2}}"
  [[ "$priority" =~ ^[1-3]$ ]] || { echo "${RED}Error: Priority must be 1, 2, or 3${NC}"; return 1; }
  
  read -r "deadline?Deadline (YYYY-MM-DD, optional): "
  if [[ -n "$deadline" && ! "$deadline" =~ ^[0-9]{4}-[0-9]{2}-[0-9]{2}$ ]]; then
    echo "${RED}Error: Deadline must be in YYYY-MM-DD format${NC}"
    return 1
  fi
  
  # Insert into database
  sqlite3 "$ZTODO_DB_PATH" <<EOF
INSERT INTO tasks (title, description, category, priority, deadline)
VALUES ('$title', '$description', '$category', $priority, '$deadline');
EOF
  
  echo "${GREEN}Task added successfully${NC}"
}

# List tasks
ztodo_list() {
  _ztodo_ensure_db || return 1
  
  local filter="$1"
  local query=""
  
  case "$filter" in
    "all") query="SELECT * FROM tasks ORDER BY priority, deadline IS NULL, deadline, created_at;" ;;
    "completed") query="SELECT * FROM tasks WHERE completed = 1 ORDER BY completed_at DESC;" ;;
    "overdue") 
      query="SELECT * FROM tasks WHERE completed = 0 AND deadline < date('now') AND deadline != '' ORDER BY deadline, priority;"
      ;;
    *) # Default: only active tasks
      query="SELECT * FROM tasks WHERE completed = 0 ORDER BY priority, deadline IS NULL, deadline, created_at;"
      ;;
  esac
  
  local result=$(sqlite3 -header -column "$ZTODO_DB_PATH" "$query")
  
  if [[ -z "$result" ]]; then
    echo "No tasks found"
    return 0
  fi
  
  # Print results in a formatted way
  local IFS=$'\n'
  local header=1
  for line in $result; do
    if (( header )); then
      echo "${BLUE}$line${NC}"
      echo "${BLUE}$(printf '%0.s-' {1..80})${NC}"
      header=0
    else
      local id=$(echo "$line" | awk '{print $1}')
      local title=$(echo "$line" | awk '{print $2}')
      local category=$(echo "$line" | awk '{print $4}')
      local priority=$(echo "$line" | awk '{print $5}')
      local deadline=$(echo "$line" | awk '{print $6}')
      local completed=$(echo "$line" | awk '{print $8}')
      
      local priority_text=$(_ztodo_format_priority "$priority")
      local deadline_text=$(_ztodo_format_date "$deadline")
      
      local status="${GREEN}[ ]${NC}"
      if [[ "$completed" == "1" ]]; then
        status="${GREEN}[✓]${NC}"
      elif [[ -n "$deadline" && "$deadline" < $(date +%Y-%m-%d) ]]; then
        status="${RED}[!]${NC}"
      fi
      
      printf "%s ${PURPLE}%-3s${NC} %-30s %-10s %s %s\n" \
        "$status" "$id" "$title" "$category" "$priority_text" "$deadline_text"
    fi
  done
}

# Complete a task
ztodo_complete() {
  _ztodo_ensure_db || return 1
  
  local id="$1"
  if [[ -z "$id" ]]; then
    echo "${RED}Error: Task ID required${NC}"
    return 1
  fi
  
  # Check if task exists
  local exists=$(sqlite3 "$ZTODO_DB_PATH" "SELECT COUNT(*) FROM tasks WHERE id = $id;")
  if [[ "$exists" -eq "0" ]]; then
    echo "${RED}Error: Task with ID $id not found${NC}"
    return 1
  fi
  
  # Mark task as completed
  sqlite3 "$ZTODO_DB_PATH" \
    "UPDATE tasks SET completed = 1, completed_at = datetime('now') WHERE id = $id;"
  
  echo "${GREEN}Task $id marked as completed${NC}"
}

# Remove a task
ztodo_remove() {
  _ztodo_ensure_db || return 1
  
  local id="$1"
  if [[ -z "$id" ]]; then
    echo "${RED}Error: Task ID required${NC}"
    return 1
  fi
  
  # Check if task exists
  local exists=$(sqlite3 "$ZTODO_DB_PATH" "SELECT COUNT(*) FROM tasks WHERE id = $id;")
  if [[ "$exists" -eq "0" ]]; then
    echo "${RED}Error: Task with ID $id not found${NC}"
    return 1
  fi
  
  # Ask for confirmation
  local task_title=$(sqlite3 "$ZTODO_DB_PATH" "SELECT title FROM tasks WHERE id = $id;")
  read -r "confirm?Delete task $id ($task_title)? [y/N] "
  if [[ ! "$confirm" =~ ^[Yy]$ ]]; then
    echo "Operation cancelled"
    return 0
  fi
  
  # Remove task
  sqlite3 "$ZTODO_DB_PATH" "DELETE FROM tasks WHERE id = $id;"
  
  echo "${GREEN}Task $id removed${NC}"
}

# Clear completed or expired tasks
ztodo_clear() {
  _ztodo_ensure_db || return 1
  
  local filter="$1"
  local query=""
  local message=""
  
  case "$filter" in
    "completed")
      query="DELETE FROM tasks WHERE completed = 1;"
      message="Cleared completed tasks"
      ;;
    "expired")
      query="DELETE FROM tasks WHERE deadline < date('now') AND deadline != '';"
      message="Cleared expired tasks"
      ;;
    *)
      read -r "confirm?Clear all completed and expired tasks? [y/N] "
      if [[ ! "$confirm" =~ ^[Yy]$ ]]; then
        echo "Operation cancelled"
        return 0
      fi
      query="DELETE FROM tasks WHERE completed = 1 OR (deadline < date('now') AND deadline != '');"
      message="Cleared all completed and expired tasks"
      ;;
  esac
  
  # Execute query
  sqlite3 "$ZTODO_DB_PATH" "$query"
  
  echo "${GREEN}$message${NC}"
}

# Search tasks
ztodo_search() {
  _ztodo_ensure_db || return 1
  
  local keyword="$1"
  if [[ -z "$keyword" ]]; then
    echo "${RED}Error: Search keyword required${NC}"
    return 1
  fi
  
  local query="SELECT * FROM tasks WHERE title LIKE '%$keyword%' OR description LIKE '%$keyword%' OR category LIKE '%$keyword%' ORDER BY completed, priority, deadline IS NULL, deadline;"
  
  local result=$(sqlite3 -header -column "$ZTODO_DB_PATH" "$query")
  
  if [[ -z "$result" ]]; then
    echo "No tasks found matching '$keyword'"
    return 0
  fi
  
  # Print results in a formatted way
  local IFS=$'\n'
  local header=1
  for line in $result; do
    if (( header )); then
      echo "${BLUE}$line${NC}"
      echo "${BLUE}$(printf '%0.s-' {1..80})${NC}"
      header=0
    else
      local id=$(echo "$line" | awk '{print $1}')
      local title=$(echo "$line" | awk '{print $2}')
      local category=$(echo "$line" | awk '{print $4}')
      local priority=$(echo "$line" | awk '{print $5}')
      local deadline=$(echo "$line" | awk '{print $6}')
      local completed=$(echo "$line" | awk '{print $8}')
      
      local priority_text=$(_ztodo_format_priority "$priority")
      local deadline_text=$(_ztodo_format_date "$deadline")
      
      local status="${GREEN}[ ]${NC}"
      if [[ "$completed" == "1" ]]; then
        status="${GREEN}[✓]${NC}"
      elif [[ -n "$deadline" && "$deadline" < $(date +%Y-%m-%d) ]]; then
        status="${RED}[!]${NC}"
      fi
      
      printf "%s ${PURPLE}%-3s${NC} %-30s %-10s %s %s\n" \
        "$status" "$id" "$title" "$category" "$priority_text" "$deadline_text"
    fi
  done
}

# Display upcoming deadlines
_ztodo_show_upcoming_deadlines() {
  _ztodo_ensure_db || return 1
  
  local days="${ZTODO_UPCOMING_DAYS:-7}"
  
  # Query for tasks with deadlines in the next X days
  local query="SELECT * FROM tasks WHERE completed = 0 AND deadline BETWEEN date('now') AND date('now', '+$days day') ORDER BY deadline, priority;"
  
  local result=$(sqlite3 -header -column "$ZTODO_DB_PATH" "$query")
  
  if [[ -z "$result" ]]; then
    return 0
  fi
  
  echo "${YELLOW}Upcoming deadlines in the next $days days:${NC}"
  
  # Print results in a formatted way
  local IFS=$'\n'
  local header=1
  local count=0
  for line in $result; do
    if (( header )); then
      header=0
      continue
    else
      count=$((count+1))
      local id=$(echo "$line" | awk '{print $1}')
      local title=$(echo "$line" | awk '{print $2}')
      local deadline=$(echo "$line" | awk '{print $6}')
      
      # Calculate days left using SQLite to ensure cross-platform compatibility
      local days_left=$(sqlite3 "$ZTODO_DB_PATH" "SELECT JULIANDAY('$deadline') - JULIANDAY('now');")
      days_left=${days_left%.*} # Remove decimal part
      
      if [[ $days_left -eq 0 ]]; then
        printf "${RED}➤ TODAY:${NC} %s (ID: ${PURPLE}%s${NC})\n" "$title" "$id"
      elif [[ $days_left -eq 1 ]]; then
        printf "${YELLOW}➤ TOMORROW:${NC} %s (ID: ${PURPLE}%s${NC})\n" "$title" "$id"
      else
        printf "${GREEN}➤ In %d days:${NC} %s (ID: ${PURPLE}%s${NC}) - %s\n" "$days_left" "$title" "$id" "$deadline"
      fi
    fi
  done
  
  echo ""
  return 0
}

# Show help
ztodo_help() {
  local config_status="enabled"
  if [[ "${ZTODO_USE_CONFIG_FILE}" != "true" ]]; then
    config_status="disabled (using .zshrc values)"
  fi
  
  cat <<EOF
${BLUE}ZTodo - SQLite-based Todo Plugin for Oh-My-Zsh${NC}

${YELLOW}Usage:${NC}
  ztodo <command> [arguments]

${YELLOW}Commands:${NC}
  add               Add a new todo item
  list [filter]     List todo items (filters: all, completed, overdue)
  complete <id>     Mark a todo item as complete
  remove <id>       Remove a specific todo item
  clear [filter]    Clear tasks (filters: completed, expired)
  search <keyword>  Search tasks by keyword
  help              Show this help message

${YELLOW}Configuration:${NC}
  Database: $ZTODO_DB_PATH
  Config:   $ZTODO_CONFIG_PATH (${config_status})
  
  You can customize ZTodo by editing $ZTODO_CONFIG_PATH or setting variables in .zshrc
EOF
}

# Main function
ztodo() {
  local cmd="$1"
  shift || true
  
  case "$cmd" in
    "add") ztodo_add "$@" ;;
    "list") ztodo_list "$@" ;;
    "complete") ztodo_complete "$@" ;;
    "remove") ztodo_remove "$@" ;;
    "clear") ztodo_clear "$@" ;;
    "search") ztodo_search "$@" ;;
    "help") ztodo_help ;;
    *) 
      if [[ -z "$cmd" ]]; then
        ztodo_list
      else
        echo "${RED}Unknown command: $cmd${NC}"
        ztodo_help
      fi
      ;;
  esac
}

# Initialize database on plugin load
_ztodo_ensure_db >/dev/null

# Show upcoming deadlines if enabled
if [[ "${ZTODO_SHOW_UPCOMING_DEADLINES:-false}" == "true" ]]; then
  _ztodo_show_upcoming_deadlines
fi