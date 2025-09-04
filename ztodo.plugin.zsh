#!/usr/bin/env zsh

# ------------------------------
# ZTodo: SQLite-based Todo Plugin for Oh-My-Zsh
# ------------------------------

# Default configuration
ZTODO_DB_PATH="${ZTODO_DB_PATH:-$HOME/.ztodo.db}"
ZTODO_CONFIG_PATH="${ZTODO_CONFIG_PATH:-$HOME/.ztodo.conf}"
# Allow users to disable config file and use .zshrc values directly
ZTODO_USE_CONFIG_FILE="${ZTODO_USE_CONFIG_FILE:-true}"
ZTODO_HISTORY_ENABLED="${ZTODO_HISTORY_ENABLED:-false}"
ZTODO_HISTORY_CAPTURE_PWD="${ZTODO_HISTORY_CAPTURE_PWD:-true}"
ZTODO_HISTORY_IGNORE="${ZTODO_HISTORY_IGNORE:-}"
ZTODO_HISTORY_REDACT="${ZTODO_HISTORY_REDACT:-true}"
ZTODO_HISTORY_REDACT_PATTERNS="${ZTODO_HISTORY_REDACT_PATTERNS:-password,passwd,token,secret,api_key,api-key,authorization,bearer}"
ZTODO_FOCUS_PERSIST="${ZTODO_FOCUS_PERSIST:-false}"
ZTODO_FOCUS_FILE="${ZTODO_FOCUS_FILE:-$HOME/.ztodo_focus}"

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

# Lightweight migrations and extensions
_ztodo_maybe_add_column() {
  local table="$1" col="$2" decl="$3"
  local exists=$(sqlite3 "$ZTODO_DB_PATH" "SELECT 1 FROM pragma_table_info('$table') WHERE name='$col' LIMIT 1;")
  if [[ -z "$exists" ]]; then
    sqlite3 "$ZTODO_DB_PATH" "ALTER TABLE $table ADD COLUMN $decl;" 2>/dev/null || true
  fi
}

_ztodo_migrate_db() {
  _ztodo_init_db

  # Add optional/extended columns to tasks
  _ztodo_maybe_add_column tasks recurrence "recurrence TEXT"
  _ztodo_maybe_add_column tasks recurrence_until "recurrence_until TEXT"
  _ztodo_maybe_add_column tasks time_tracked "time_tracked INTEGER DEFAULT 0"
  _ztodo_maybe_add_column tasks active_timer_started_at "active_timer_started_at TEXT"
  _ztodo_maybe_add_column tasks project "project TEXT"

  # Subtasks table
  sqlite3 "$ZTODO_DB_PATH" <<'EOF'
CREATE TABLE IF NOT EXISTS subtasks (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  task_id INTEGER NOT NULL,
  title TEXT NOT NULL,
  completed INTEGER DEFAULT 0,
  created_at TEXT DEFAULT CURRENT_TIMESTAMP,
  completed_at TEXT,
  FOREIGN KEY(task_id) REFERENCES tasks(id) ON DELETE CASCADE
);
CREATE INDEX IF NOT EXISTS idx_subtasks_task ON subtasks(task_id);
EOF

  # Task history table
  sqlite3 "$ZTODO_DB_PATH" <<'EOF'
CREATE TABLE IF NOT EXISTS task_history (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  task_id INTEGER,
  event TEXT NOT NULL,
  meta TEXT,
  created_at TEXT DEFAULT CURRENT_TIMESTAMP,
  FOREIGN KEY(task_id) REFERENCES tasks(id) ON DELETE SET NULL
);
CREATE INDEX IF NOT EXISTS idx_task_history_task ON task_history(task_id);
EOF

  # Templates table (simple)
  sqlite3 "$ZTODO_DB_PATH" <<'EOF'
CREATE TABLE IF NOT EXISTS templates (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  name TEXT UNIQUE NOT NULL,
  title TEXT,
  description TEXT,
  category TEXT,
  priority INTEGER,
  project TEXT,
  default_deadline_days INTEGER
);
EOF
}

# History logger
_ztodo_log_event() {
  local task_id="$1" event="$2" meta="$3"
  sqlite3 "$ZTODO_DB_PATH" "INSERT INTO task_history (task_id, event, meta) VALUES (${task_id:+$task_id}, '$event', '$meta');" 2>/dev/null || true
}

# Per-task command history hooks (opt-in)
_ztodo_history_should_ignore() {
  local cmd="$1"
  [[ -z "$ZTODO_HISTORY_IGNORE" ]] && return 1
  local IFS=,
  for pat in $ZTODO_HISTORY_IGNORE; do
    [[ -z "$pat" ]] && continue
    if [[ "$cmd" == *"$pat"* ]]; then
      return 0
    fi
  done
  return 1
}

_ztodo_history_preexec() {
  [[ "${ZTODO_HISTORY_ENABLED}" != "true" ]] && return 0
  [[ -z "${ZTODO_ACTIVE_TASK}" ]] && return 0
  _ZTODO_LAST_CMD="$1"
  _ZTODO_LAST_CMD_TS=${EPOCHSECONDS:-$(date +%s 2>/dev/null)}
}

_ztodo_history_precmd() {
  [[ "${ZTODO_HISTORY_ENABLED}" != "true" ]] && return 0
  [[ -z "${ZTODO_ACTIVE_TASK}" ]] && return 0
  [[ -z "${_ZTODO_LAST_CMD}" ]] && return 0
  local cmd="${_ZTODO_LAST_CMD}"
  # Redact secrets if configured
  if [[ "${ZTODO_HISTORY_REDACT}" == "true" ]]; then
    cmd=$(_ztodo_redact_command "$cmd")
  fi
  _ZTODO_LAST_CMD=""
  local dur=""
  if [[ -n "${_ZTODO_LAST_CMD_TS}" ]]; then
    local now=${EPOCHSECONDS:-$(date +%s 2>/dev/null)}
    (( now > _ZTODO_LAST_CMD_TS )) && dur=$(( now - _ZTODO_LAST_CMD_TS ))
  fi
  local status=$?
  if _ztodo_history_should_ignore "$cmd"; then
    return 0
  fi
  local meta="cmd=$(_ztodo_sql_escape "$cmd");status=$status"
  if [[ "${ZTODO_HISTORY_CAPTURE_PWD}" == "true" ]]; then
    meta+=";dir=$(_ztodo_sql_escape "$PWD")"
  fi
  if [[ -n "$dur" ]]; then
    meta+=";duration=$dur"
  fi
  _ztodo_log_event "$ZTODO_ACTIVE_TASK" "cmd" "$meta"
}

# Check if database exists, create if not
_ztodo_ensure_db() {
  if ! command -v sqlite3 &> /dev/null; then
    echo "${RED}Error: sqlite3 is not installed. Please install it before using ZTodo.${NC}"
    return 1
  fi
  
  _ztodo_migrate_db
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
  
  local title description category priority deadline project recurrence
  
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
  
  read -r "project?Project (optional): "
  read -r "recurrence?Recurrence (daily/weekly/monthly/none): "
  if [[ -n "$recurrence" && ! "$recurrence" =~ ^(daily|weekly|monthly|none)$ ]]; then
    echo "${RED}Error: Recurrence must be daily, weekly, monthly, or none${NC}"
    return 1
  fi
  [[ "$recurrence" == "none" ]] && recurrence=""

  # Insert into database
  sqlite3 "$ZTODO_DB_PATH" <<EOF
INSERT INTO tasks (title, description, category, priority, deadline, project, recurrence)
VALUES ('$title', '$description', '$category', $priority, '$deadline', '$project', '$recurrence');
EOF
  local new_id=$(sqlite3 "$ZTODO_DB_PATH" "SELECT last_insert_rowid();")
  _ztodo_log_event "$new_id" "created" "title=$title;deadline=$deadline;priority=$priority;category=$category;project=$project;recurrence=$recurrence"

  echo "${GREEN}Task added successfully (ID: $new_id)${NC}"
}

# List tasks
ztodo_list() {
  _ztodo_ensure_db || return 1
  
  local filter="$1"
  local query=""
  local project_filter=""
  if [[ "$filter" == "project" ]]; then
    local proj="$2"
    if [[ -z "$proj" ]]; then
      echo "${RED}Usage: ztodo list project <name>${NC}"
      return 1
    fi
    project_filter="AND project = '"$proj"'"
    filter="" # fall back to default active listing with project filter
  fi
  
  case "$filter" in
    "all") query="SELECT * FROM tasks WHERE 1=1 ${project_filter} ORDER BY priority, deadline IS NULL, deadline, created_at;" ;;
    "completed") query="SELECT * FROM tasks WHERE completed = 1 ${project_filter} ORDER BY completed_at DESC;" ;;
    "overdue") 
      query="SELECT * FROM tasks WHERE completed = 0 ${project_filter} AND deadline < date('now') AND deadline != '' ORDER BY deadline, priority;"
      ;;
    *) # Default: only active tasks
      query="SELECT * FROM tasks WHERE completed = 0 ${project_filter} ORDER BY priority, deadline IS NULL, deadline, created_at;"
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

# Projects overview
ztodo_projects() {
  _ztodo_ensure_db || return 1
  sqlite3 -header -column "$ZTODO_DB_PATH" "SELECT IFNULL(project,'') AS project, COUNT(*) AS count FROM tasks GROUP BY project ORDER BY count DESC, project;"
}

# Task/event history
ztodo_history() {
  _ztodo_ensure_db || return 1
  local id="$1"
  if [[ -n "$id" ]]; then
    sqlite3 -header -column "$ZTODO_DB_PATH" "SELECT id, event, IFNULL(meta,'') AS meta, created_at FROM task_history WHERE task_id=$id ORDER BY id DESC LIMIT 50;"
  else
    sqlite3 -header -column "$ZTODO_DB_PATH" "SELECT id, task_id, event, IFNULL(meta,'') AS meta, created_at FROM task_history ORDER BY id DESC LIMIT 50;"
  fi
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
  _ztodo_log_event "$id" "completed" ""

  # Recurring: spawn next occurrence based on deadline
  local recurrence=$(sqlite3 "$ZTODO_DB_PATH" "SELECT recurrence FROM tasks WHERE id = $id;")
  if [[ -n "$recurrence" ]]; then
    local dl=$(sqlite3 "$ZTODO_DB_PATH" "SELECT deadline FROM tasks WHERE id = $id;")
    local title=$(sqlite3 "$ZTODO_DB_PATH" "SELECT title FROM tasks WHERE id = $id;")
    local description=$(sqlite3 "$ZTODO_DB_PATH" "SELECT description FROM tasks WHERE id = $id;")
    local category=$(sqlite3 "$ZTODO_DB_PATH" "SELECT category FROM tasks WHERE id = $id;")
    local priority=$(sqlite3 "$ZTODO_DB_PATH" "SELECT priority FROM tasks WHERE id = $id;")
    local project=$(sqlite3 "$ZTODO_DB_PATH" "SELECT project FROM tasks WHERE id = $id;")
    local next_deadline=""
    if [[ -n "$dl" ]]; then
      case "$recurrence" in
        daily)   next_deadline=$(sqlite3 "$ZTODO_DB_PATH" "SELECT date('$dl','+1 day');") ;;
        weekly)  next_deadline=$(sqlite3 "$ZTODO_DB_PATH" "SELECT date('$dl','+7 day');") ;;
        monthly) next_deadline=$(sqlite3 "$ZTODO_DB_PATH" "SELECT date('$dl','+1 month');") ;;
      esac
    fi
    sqlite3 "$ZTODO_DB_PATH" <<EOF
INSERT INTO tasks (title, description, category, priority, deadline, project, recurrence)
VALUES ('$title', '$description', '$category', $priority, '$next_deadline', '$project', '$recurrence');
EOF
    local nid=$(sqlite3 "$ZTODO_DB_PATH" "SELECT last_insert_rowid();")
    _ztodo_log_event "$nid" "spawned_from_recurrence" "source=$id"
    echo "${YELLOW}Recurring task created (ID: $nid)${NC}"
  fi

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
  _ztodo_log_event "$id" "deleted" ""
  
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
  _ztodo_log_event "" "clear" "$filter"
  
  echo "${GREEN}$message${NC}"
}

# Time tracking
ztodo_timer_start() {
  _ztodo_ensure_db || return 1
  local id="$1"
  [[ -z "$id" ]] && { echo "${RED}Usage: ztodo timer start <id>${NC}"; return 1; }
  local running=$(sqlite3 "$ZTODO_DB_PATH" "SELECT active_timer_started_at FROM tasks WHERE id=$id;")
  [[ -z "$running" ]] || { echo "${YELLOW}Timer already running for task $id${NC}"; return 0; }
  sqlite3 "$ZTODO_DB_PATH" "UPDATE tasks SET active_timer_started_at = datetime('now') WHERE id=$id;"
  _ztodo_log_event "$id" "timer_start" ""
  echo "${GREEN}Timer started for task $id${NC}"
}

ztodo_timer_stop() {
  _ztodo_ensure_db || return 1
  local id="$1"
  [[ -z "$id" ]] && { echo "${RED}Usage: ztodo timer stop <id>${NC}"; return 1; }
  local started=$(sqlite3 "$ZTODO_DB_PATH" "SELECT active_timer_started_at FROM tasks WHERE id=$id;")
  [[ -n "$started" ]] || { echo "${YELLOW}No running timer for task $id${NC}"; return 0; }
  sqlite3 "$ZTODO_DB_PATH" <<EOF
UPDATE tasks
SET time_tracked = time_tracked + CAST(ROUND((JULIANDAY('now') - JULIANDAY(active_timer_started_at)) * 24 * 60) AS INTEGER),
    active_timer_started_at = NULL
WHERE id = $id;
EOF
  _ztodo_log_event "$id" "timer_stop" "started_at=$started"
  echo "${GREEN}Timer stopped for task $id${NC}"
}

ztodo_timer_status() {
  _ztodo_ensure_db || return 1
  local id="$1"
  if [[ -n "$id" ]]; then
    sqlite3 -header -column "$ZTODO_DB_PATH" "SELECT id, title, time_tracked AS minutes, active_timer_started_at FROM tasks WHERE id=$id;"
  else
    sqlite3 -header -column "$ZTODO_DB_PATH" "SELECT id, title, time_tracked AS minutes, active_timer_started_at FROM tasks WHERE active_timer_started_at IS NOT NULL;"
  fi
}

# Subtasks
ztodo_sub_add() {
  _ztodo_ensure_db || return 1
  local task_id="$1"
  [[ -z "$task_id" ]] && { echo "${RED}Usage: ztodo sub add <task_id>${NC}"; return 1; }
  local title
  read -r "title?Subtask title: "
  [[ -z "$title" ]] && { echo "${RED}Error: Title cannot be empty${NC}"; return 1; }
  sqlite3 "$ZTODO_DB_PATH" "INSERT INTO subtasks (task_id, title) VALUES ($task_id, '$title');"
  local sid=$(sqlite3 "$ZTODO_DB_PATH" "SELECT last_insert_rowid();")
  _ztodo_log_event "$task_id" "subtask_created" "subtask_id=$sid;title=$title"
  echo "${GREEN}Subtask added (ID: $sid)${NC}"
}

ztodo_sub_list() {
  _ztodo_ensure_db || return 1
  local task_id="$1"
  [[ -z "$task_id" ]] && { echo "${RED}Usage: ztodo sub list <task_id>${NC}"; return 1; }
  sqlite3 -header -column "$ZTODO_DB_PATH" "SELECT id, title, completed, created_at, completed_at FROM subtasks WHERE task_id=$task_id ORDER BY completed, created_at;"
}

ztodo_sub_complete() {
  _ztodo_ensure_db || return 1
  local sub_id="$1"
  [[ -z "$sub_id" ]] && { echo "${RED}Usage: ztodo sub complete <sub_id>${NC}"; return 1; }
  sqlite3 "$ZTODO_DB_PATH" "UPDATE subtasks SET completed=1, completed_at=datetime('now') WHERE id=$sub_id;"
  local t_id=$(sqlite3 "$ZTODO_DB_PATH" "SELECT task_id FROM subtasks WHERE id=$sub_id;")
  _ztodo_log_event "$t_id" "subtask_completed" "subtask_id=$sub_id"
  echo "${GREEN}Subtask $sub_id completed${NC}"
}

ztodo_sub_remove() {
  _ztodo_ensure_db || return 1
  local sub_id="$1"
  [[ -z "$sub_id" ]] && { echo "${RED}Usage: ztodo sub remove <sub_id>${NC}"; return 1; }
  local t_id=$(sqlite3 "$ZTODO_DB_PATH" "SELECT task_id FROM subtasks WHERE id=$sub_id;")
  sqlite3 "$ZTODO_DB_PATH" "DELETE FROM subtasks WHERE id=$sub_id;"
  _ztodo_log_event "$t_id" "subtask_deleted" "subtask_id=$sub_id"
  echo "${GREEN}Subtask $sub_id removed${NC}"
}

# Export/Import
ztodo_export() {
  _ztodo_ensure_db || return 1
  local fmt="$1" out="$2"
  [[ -z "$fmt" ]] && fmt="csv"
  case "$fmt" in
    csv)
      local query="SELECT id,title,description,category,priority,deadline,project,recurrence,completed FROM tasks ORDER BY id;"
      if [[ -n "$out" ]]; then
        sqlite3 -header -csv "$ZTODO_DB_PATH" "$query" > "$out"
        echo "${GREEN}Exported tasks to $out${NC}"
      else
        sqlite3 -header -csv "$ZTODO_DB_PATH" "$query"
      fi
      ;;
    json)
      # Build JSON array manually to avoid external deps
      local sep=$'\x1F'
      local rows=$(sqlite3 -separator "$sep" "$ZTODO_DB_PATH" "SELECT ifnull(id,''), ifnull(title,''), ifnull(description,''), ifnull(category,''), ifnull(priority,''), ifnull(deadline,''), ifnull(project,''), ifnull(recurrence,''), ifnull(completed,''), ifnull(created_at,''), ifnull(completed_at,'') FROM tasks ORDER BY id;")
      local json='['
      local first=1
      for line in ${(f)rows}; do
        local id title description category priority deadline project recurrence completed created_at completed_at
        id=${${(ps:$sep:)line}[1]}
        title=${${(ps:$sep:)line}[2]}
        description=${${(ps:$sep:)line}[3]}
        category=${${(ps:$sep:)line}[4]}
        priority=${${(ps:$sep:)line}[5]}
        deadline=${${(ps:$sep:)line}[6]}
        project=${${(ps:$sep:)line}[7]}
        recurrence=${${(ps:$sep:)line}[8]}
        completed=${${(ps:$sep:)line}[9]}
        created_at=${${(ps:$sep:)line}[10]}
        completed_at=${${(ps:$sep:)line}[11]}
        local esc_title=$(_ztodo_json_escape "$title")
        local esc_description=$(_ztodo_json_escape "$description")
        local esc_category=$(_ztodo_json_escape "$category")
        local esc_deadline=$(_ztodo_json_escape "$deadline")
        local esc_project=$(_ztodo_json_escape "$project")
        local esc_recurrence=$(_ztodo_json_escape "$recurrence")
        local esc_created=$(_ztodo_json_escape "$created_at")
        local esc_completed_at=$(_ztodo_json_escape "$completed_at")
        local obj
        obj="{\"id\":$id,\"title\":\"$esc_title\",\"description\":\"$esc_description\",\"category\":\"$esc_category\",\"priority\":$priority,\"deadline\":\"$esc_deadline\",\"project\":\"$esc_project\",\"recurrence\":\"$esc_recurrence\",\"completed\":$completed,\"created_at\":\"$esc_created\",\"completed_at\":\"$esc_completed_at\"}"
        if (( first )); then
          json+="$obj"
          first=0
        else
          json+=",$obj"
        fi
      done
      json+=']'
      if [[ -n "$out" ]]; then
        print -r -- "$json" > "$out"
        echo "${GREEN}Exported tasks to $out${NC}"
      else
        print -r -- "$json"
      fi
      ;;
    *)
      echo "${YELLOW}Supported export formats: csv, json${NC}"
      return 1
      ;;
  esac
}

ztodo_import() {
  _ztodo_ensure_db || return 1
  local fmt="$1" file="$2"
  if [[ -z "$fmt" || -z "$file" ]]; then
    echo "${RED}Usage: ztodo import <csv|json> <file>${NC}"
    return 1
  fi
  if [[ ! -f "$file" ]]; then
    echo "${RED}File not found: $file${NC}"
    return 1
  fi
  case "$fmt" in
    csv)
      local IFS=$'\n'
      local n=0
      for line in $(tail -n +2 "$file"); do
        n=$((n+1))
        local title=$(echo "$line" | awk -F, '{print $1}')
        local description=$(echo "$line" | awk -F, '{print $2}')
        local category=$(echo "$line" | awk -F, '{print $3}')
        local priority=$(echo "$line" | awk -F, '{print $4}')
        local deadline=$(echo "$line" | awk -F, '{print $5}')
        local project=$(echo "$line" | awk -F, '{print $6}')
        local recurrence=$(echo "$line" | awk -F, '{print $7}')
        sqlite3 "$ZTODO_DB_PATH" "INSERT INTO tasks (title, description, category, priority, deadline, project, recurrence) VALUES ('$title', '$description', '$category', $priority, '$deadline', '$project', '$recurrence');"
      done
      echo "${GREEN}Imported $n tasks from $file${NC}"
      ;;
    json)
      # Parse JSON produced by export (array of flat objects)
      local json_content; json_content=$(cat "$file")
      # Remove outer [ ] and split on '},{' safely
      json_content=${json_content#\[}
      json_content=${json_content%\]}
      local IFS=$'\n'
      local n=0
      # Replace '},{' separators with newlines
      local objs=$(print -r -- "$json_content" | sed 's/},{/}\n{/g')
      for obj in ${(f)objs}; do
        # Extract fields using sed; handles escaped quotes minimally
        local get() { echo "$obj" | sed -n "s/.*\"$1\":\(\"\([^\"]*\)\"\|\([^,}]*\)\).*/\2\3/p"; }
        local title=$(get title)
        local description=$(get description)
        local category=$(get category)
        local priority=$(get priority)
        local deadline=$(get deadline)
        local project=$(get project)
        local recurrence=$(get recurrence)
        local completed=$(get completed)
        [[ -z "$priority" ]] && priority=2
        [[ -z "$completed" ]] && completed=0
        sqlite3 "$ZTODO_DB_PATH" "INSERT INTO tasks (title, description, category, priority, deadline, project, recurrence, completed) VALUES ('$title', '$description', '$category', $priority, '$deadline', '$project', '$recurrence', $completed);"
        n=$((n+1))
      done
      echo "${GREEN}Imported $n tasks from $file${NC}"
      ;;
    *)
      echo "${RED}Unsupported format: $fmt${NC}"
      return 1
      ;;
  esac
}

# JSON escaping helper
_ztodo_json_escape() {
  local s="$1"
  s=${s//\\/\\\\}
  s=${s//\"/\\\"}
  s=${s//$'\n'/\\n}
  s=${s//$'\r'/\\r}
  s=${s//$'\t'/\\t}
  print -r -- "$s"
}

# SQL single-quote escape helper
_ztodo_sql_escape() {
  local s="$1"
  s=${s//\'/''}
  print -r -- "$s"
}

# Base64 helpers (prefer coreutils base64, fallback to openssl)
_ztodo_base64_encode() {
  if command -v base64 >/dev/null 2>&1; then
    print -r -- "$1" | base64 | tr -d '\n'
  elif command -v openssl >/dev/null 2>&1; then
    print -r -- "$1" | openssl base64 -A
  else
    echo "${RED}Error: base64 or openssl required for share codes${NC}" >&2
    return 1
  fi
}

_ztodo_base64_decode() {
  if command -v base64 >/dev/null 2>&1; then
    print -r -- "$1" | base64 -d 2>/dev/null
  elif command -v openssl >/dev/null 2>&1; then
    print -r -- "$1" | openssl base64 -A -d 2>/dev/null
  else
    echo "${RED}Error: base64 or openssl required for share codes${NC}" >&2
    return 1
  fi
}

# Redact common secret patterns in a command string
_ztodo_redact_command() {
  local cmd_in="$1"
  local redacted="$cmd_in"
  # Split patterns by comma, case-insensitive masking for key=value and --key=value
  local IFS=,
  for key in ${=ZTODO_HISTORY_REDACT_PATTERNS}; do
    [[ -z "$key" ]] && continue
    # --key=VALUE or key=VALUE
    redacted=$(print -r -- "$redacted" | sed -E "s/((--|)(${key}))([[:space:]]*[:=])[^"]+/\1\4***/Ig")
    # KEY VALUE (space separated), keep next token masked
    redacted=$(print -r -- "$redacted" | sed -E "s/((--|)(${key}))([[:space:]]+)([^[:space:]]+)/\1\4***/Ig")
  done
  # Authorization: Bearer xxxx or bearer xxxx
  redacted=$(print -r -- "$redacted" | sed -E "s/(Authorization:[[:space:]]*Bearer[[:space:]]+)[^[:space:]]+/\1***/I")
  redacted=$(print -r -- "$redacted" | sed -E "s/([[:space:]]|^)bearer[[:space:]]+[^[:space:]]+/\1bearer ***/I")
  print -r -- "$redacted"
}

# Share code: export/import a single task as Base64 JSON
ztodo_share_export() {
  _ztodo_ensure_db || return 1
  local id="$1"
  [[ -z "$id" ]] && { echo "${RED}Usage: ztodo share export <id>${NC}"; return 1; }
  local sep=$'\x1F'
  local row=$(sqlite3 -separator "$sep" "$ZTODO_DB_PATH" "SELECT id, ifnull(title,''), ifnull(description,''), ifnull(category,''), ifnull(priority,2), ifnull(deadline,''), ifnull(project,''), ifnull(recurrence,''), ifnull(completed,0) FROM tasks WHERE id=$id LIMIT 1;")
  if [[ -z "$row" ]]; then
    echo "${RED}Task not found: $id${NC}"
    return 1
  fi
  local fid=${${(ps:$sep:)row}[1]}
  local title=${${(ps:$sep:)row}[2]}
  local description=${${(ps:$sep:)row}[3]}
  local category=${${(ps:$sep:)row}[4]}
  local priority=${${(ps:$sep:)row}[5]}
  local deadline=${${(ps:$sep:)row}[6]}
  local project=${${(ps:$sep:)row}[7]}
  local recurrence=${${(ps:$sep:)row}[8]}
  local completed=${${(ps:$sep:)row}[9]}
  local json
  json="{\"title\":\"$(_ztodo_json_escape "$title")\",\"description\":\"$(_ztodo_json_escape "$description")\",\"category\":\"$(_ztodo_json_escape "$category")\",\"priority\":$priority,\"deadline\":\"$(_ztodo_json_escape "$deadline")\",\"project\":\"$(_ztodo_json_escape "$project")\",\"recurrence\":\"$(_ztodo_json_escape "$recurrence")\",\"completed\":$completed}"
  local code=$(_ztodo_base64_encode "$json") || return 1
  echo "$code"
}

ztodo_share_import() {
  _ztodo_ensure_db || return 1
  local code="$1"
  [[ -z "$code" ]] && { echo "${RED}Usage: ztodo share import <base64_code>${NC}"; return 1; }
  # Accept full pasted code possibly with spaces/newlines
  local decoded=$(_ztodo_base64_decode "$code")
  if [[ -z "$decoded" || "$decoded" == *"invalid"* ]]; then
    echo "${RED}Invalid share code${NC}"
    return 1
  fi
  local obj="$decoded"
  # Minimal JSON field extraction compatible with our exporter
  local get() { echo "$obj" | sed -n "s/.*\"$1\":\(\"\([^\"]*\)\"\|\([^,}]*\)\).*/\2\3/p"; }
  local title=$(get title)
  local description=$(get description)
  local category=$(get category)
  local priority=$(get priority)
  local deadline=$(get deadline)
  local project=$(get project)
  local recurrence=$(get recurrence)
  local completed=$(get completed)
  [[ -z "$title$description$category$project$deadline$recurrence$priority$completed" ]] && { echo "${RED}Could not parse JSON in share code${NC}"; return 1; }
  [[ -z "$priority" ]] && priority=2
  [[ -z "$completed" ]] && completed=0
  # SQL escape single quotes
  local stitle=$(_ztodo_sql_escape "$title")
  local sdesc=$(_ztodo_sql_escape "$description")
  local scat=$(_ztodo_sql_escape "$category")
  local sproj=$(_ztodo_sql_escape "$project")
  local sdl=$(_ztodo_sql_escape "$deadline")
  local srec=$(_ztodo_sql_escape "$recurrence")
  sqlite3 "$ZTODO_DB_PATH" "INSERT INTO tasks (title, description, category, priority, deadline, project, recurrence, completed) VALUES ('$stitle', '$sdesc', '$scat', $priority, '$sdl', '$sproj', '$srec', $completed);"
  local nid=$(sqlite3 "$ZTODO_DB_PATH" "SELECT last_insert_rowid();")
  _ztodo_log_event "$nid" "imported_from_share" ""
  echo "${GREEN}Imported task (ID: $nid)${NC}"
}

# Templates
ztodo_template_create() {
  _ztodo_ensure_db || return 1
  local name="$1"
  [[ -z "$name" ]] && { echo "${RED}Usage: ztodo template create <name>${NC}"; return 1; }
  local title description category priority project default_days
  read -r "title?Default title (optional): "
  read -r "description?Default description (optional): "
  read -r "category?Default category (optional): "
  read -r "priority?Default priority (1-3, optional): "
  read -r "project?Default project (optional): "
  read -r "default_days?Default deadline offset days (optional): "
  sqlite3 "$ZTODO_DB_PATH" "INSERT OR REPLACE INTO templates (name,title,description,category,priority,project,default_deadline_days) VALUES ('$name', '$title', '$description', '$category', NULLIF('$priority',''), '$project', NULLIF('$default_days',''));"
  echo "${GREEN}Template '$name' saved${NC}"
}

ztodo_template_list() {
  _ztodo_ensure_db || return 1
  sqlite3 -header -column "$ZTODO_DB_PATH" "SELECT name, title, category, priority, project, default_deadline_days FROM templates ORDER BY name;"
}

ztodo_template_apply() {
  _ztodo_ensure_db || return 1
  local name="$1"
  [[ -z "$name" ]] && { echo "${RED}Usage: ztodo template apply <name>${NC}"; return 1; }
  local title=$(sqlite3 "$ZTODO_DB_PATH" "SELECT IFNULL(title,'') FROM templates WHERE name='$name';")
  local description=$(sqlite3 "$ZTODO_DB_PATH" "SELECT IFNULL(description,'') FROM templates WHERE name='$name';")
  local category=$(sqlite3 "$ZTODO_DB_PATH" "SELECT IFNULL(category,'general') FROM templates WHERE name='$name';")
  local priority=$(sqlite3 "$ZTODO_DB_PATH" "SELECT IFNULL(priority,2) FROM templates WHERE name='$name';")
  local project=$(sqlite3 "$ZTODO_DB_PATH" "SELECT IFNULL(project,'') FROM templates WHERE name='$name';")
  local offset=$(sqlite3 "$ZTODO_DB_PATH" "SELECT IFNULL(default_deadline_days,'') FROM templates WHERE name='$name';")
  if [[ -z "$title$description$category$project$offset" ]]; then
    echo "${RED}Template '$name' not found${NC}"
    return 1
  fi
  local deadline=""
  if [[ -n "$offset" ]]; then
    deadline=$(sqlite3 "$ZTODO_DB_PATH" "SELECT date('now','+$offset day');")
  fi
  sqlite3 "$ZTODO_DB_PATH" "INSERT INTO tasks (title, description, category, priority, deadline, project) VALUES ('$title', '$description', '$category', $priority, '$deadline', '$project');"
  local nid=$(sqlite3 "$ZTODO_DB_PATH" "SELECT last_insert_rowid();")
  _ztodo_log_event "$nid" "created_from_template" "name=$name"
  echo "${GREEN}Task created from template '$name' (ID: $nid)${NC}"
}

# Calendar views
ztodo_calendar() {
  _ztodo_ensure_db || return 1
  local mode="$1" arg="$2"
  [[ -z "$mode" ]] && mode="month"
  case "$mode" in
    month)
      local ym="$arg"
      [[ -z "$ym" ]] && ym=$(date +%Y-%m 2>/dev/null || sqlite3 "$ZTODO_DB_PATH" "SELECT strftime('%Y-%m','now');")
      _ztodo_calendar_month "$ym"
      ;;
    week)
      local ymd="$arg"
      [[ -z "$ymd" ]] && ymd=$(date +%Y-%m-%d 2>/dev/null || sqlite3 "$ZTODO_DB_PATH" "SELECT date('now');")
      _ztodo_calendar_week "$ymd"
      ;;
    *)
      echo "${RED}Usage: ztodo calendar [month [YYYY-MM] | week [YYYY-MM-DD]]${NC}"
      return 1
      ;;
  esac
}

_ztodo_calendar_month() {
  local ym="$1"
  local first="$ym-01"
  local last_day=$(sqlite3 "$ZTODO_DB_PATH" "SELECT strftime('%d', date('$first','start of month','+1 month','-1 day'));")
  local first_w=$(sqlite3 "$ZTODO_DB_PATH" "SELECT strftime('%w', '$first');")
  local counts_raw=$(sqlite3 -separator '|' "$ZTODO_DB_PATH" "SELECT strftime('%d', deadline), COUNT(*) FROM tasks WHERE completed=0 AND deadline BETWEEN date('$first') AND date('$first','start of month','+1 month','-1 day') GROUP BY 1;")
  typeset -A counts; counts=()
  local IFS=$'\n'
  for l in ${(f)counts_raw}; do
    local d=${${(ps:|:)l}[1]}
    local c=${${(ps:|:)l}[2]}
    counts[$d]=$c
  done
  echo "${BLUE}Calendar $ym${NC}"
  echo "Su Mo Tu We Th Fr Sa"
  local col=0
  for ((i=0;i<first_w;i++)); do printf "   "; ((col++)); done
  for ((day=1; day<=10#$last_day; day++)); do
    local dd=$(printf "%02d" $day)
    local mark="  "
    if [[ -n "${counts[$dd]}" ]]; then
      mark="*${counts[$dd]}"
      [[ ${#mark} -eq 2 ]] && mark=" ${mark}"
    fi
    printf "%2d" $day
    if [[ -n "${counts[$dd]}" ]]; then
      printf "%s" "$mark"
    else
      printf "  "
    fi
    ((col++))
    if (( col % 7 == 0 )); then
      printf "\n"
    else
      printf " "
    fi
  done
  if (( col % 7 != 0 )); then printf "\n"; fi
  echo "*N indicates number of deadlines on that day"
}

_ztodo_calendar_week() {
  local ymd="$1"
  local w=$(sqlite3 "$ZTODO_DB_PATH" "SELECT strftime('%w', '$ymd');")
  local start=$(sqlite3 "$ZTODO_DB_PATH" "SELECT date('$ymd','-'||$w||' day');")
  echo "${BLUE}Week starting $start${NC}"
  for i in 0 1 2 3 4 5 6; do
    local d=$(sqlite3 "$ZTODO_DB_PATH" "SELECT date('$start','+'||$i||' day');")
    local list=$(sqlite3 -separator '|' "$ZTODO_DB_PATH" "SELECT id||' '||title FROM tasks WHERE completed=0 AND deadline='$d' ORDER BY priority, id;")
    printf "%s: " "$d"
    if [[ -z "$list" ]]; then
      echo "-"
    else
      echo
      local IFS=$'\n'
      for row in ${(f)list}; do
        echo "  • $row"
      done
    fi
  done
}

# Minimal TUI (fzf)
ztodo_tui() {
  _ztodo_ensure_db || return 1
  if ! command -v fzf >/dev/null 2>&1; then
    echo "${YELLOW}fzf not found. Please install fzf for TUI.${NC}"
    return 1
  fi
  local lines=$(sqlite3 -separator $'|' "$ZTODO_DB_PATH" "SELECT id, completed, title, category, priority, IFNULL(deadline,'') FROM tasks ORDER BY completed, priority, deadline IS NULL, deadline;" | \
    awk -F'|' '{status=($2==1?"[✓]":"[ ]"); printf "%s %3s | %-30s | %-10s | p%s | %s\n", status, $1, $3, $4, $5, $6}')
  local sel=$(echo "$lines" | fzf --header="Enter: toggle complete | Ctrl-D: delete | Esc: quit" --expect=enter,ctrl-d)
  local key=$(echo "$sel" | head -n1)
  local row=$(echo "$sel" | sed -n '2p')
  local id=$(echo "$row" | awk '{print $2}')
  [[ -z "$id" ]] && return 0
  case "$key" in
    enter)
      local is_completed=$(sqlite3 "$ZTODO_DB_PATH" "SELECT completed FROM tasks WHERE id=$id;")
      if [[ "$is_completed" == "1" ]]; then
        sqlite3 "$ZTODO_DB_PATH" "UPDATE tasks SET completed=0, completed_at=NULL WHERE id=$id;"
        _ztodo_log_event "$id" "reopened" ""
        echo "Reopened task $id"
      else
        ztodo_complete "$id"
      fi
      ;;
    ctrl-d)
      ztodo_remove "$id"
      ;;
  esac
}

# Integration stubs
ztodo_integration() {
  local target="$1"; shift || true
  case "$target" in
    clickup|notion|github|jira|gcal|slack)
      echo "${YELLOW}Integration '$target' is not implemented yet. Contributions welcome!${NC}"
      ;;
    *)
      echo "${RED}Usage: ztodo integration <clickup|notion|github|jira|gcal|slack>${NC}"
      return 1
      ;;
  esac
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
  list [filter]     List todo items (filters: all, completed, overdue, project <name>)
  complete <id>     Mark a todo item as complete
  remove <id>       Remove a specific todo item
  clear [filter]    Clear tasks (filters: completed, expired)
  search <keyword>  Search tasks by keyword
  timer <op> [...]  Time tracking (start/stop/status)
  sub <op> [...]    Subtasks (add/list/complete/remove)
  export [fmt] [f]  Export tasks (csv)
  import [fmt] <f>  Import tasks (csv)
  export json [f]   Export tasks as JSON
  import json <f>   Import tasks from JSON (export-compatible)
  share export <id> Create a share code (Base64 JSON)
  share import <c>  Import from a share code
  tui               Minimal interactive UI (fzf)
  integration <t>   Third-party integration stubs
  projects          List projects with task counts
  history [id]      Show recent events (optionally for a task)
  template create|apply|list
  calendar [month|week] [date]
  focus <id>        Focus a task to log shell commands
  unfocus           Clear focused task
  context           Show current focused task
  report <today|week>
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
    "timer")
      case "$1" in
        start) shift; ztodo_timer_start "$@" ;;
        stop) shift; ztodo_timer_stop "$@" ;;
        status) shift; ztodo_timer_status "$@" ;;
        *) echo "${RED}Usage: ztodo timer <start|stop|status> [id]${NC}" ;;
      esac
      ;;
    "sub")
      case "$1" in
        add) shift; ztodo_sub_add "$@" ;;
        list) shift; ztodo_sub_list "$@" ;;
        complete) shift; ztodo_sub_complete "$@" ;;
        remove) shift; ztodo_sub_remove "$@" ;;
        *) echo "${RED}Usage: ztodo sub <add|list|complete|remove> ...${NC}" ;;
      esac
      ;;
    "export") ztodo_export "$@" ;;
    "import") ztodo_import "$@" ;;
    "tui") ztodo_tui ;;
    "integration") ztodo_integration "$@" ;;
    "projects") ztodo_projects ;;
    "history") ztodo_history "$@" ;;
    "template")
      case "$1" in
        create) shift; ztodo_template_create "$@" ;;
        list) shift; ztodo_template_list "$@" ;;
        apply) shift; ztodo_template_apply "$@" ;;
        *) echo "${RED}Usage: ztodo template <create|list|apply> ...${NC}" ;;
      esac
      ;;
    "calendar") ztodo_calendar "$@" ;;
    "share")
      case "$1" in
        export) shift; ztodo_share_export "$@" ;;
        import) shift; ztodo_share_import "$@" ;;
        *) echo "${RED}Usage: ztodo share <export|import> ...${NC}" ;;
      esac
      ;;
    "focus") ztodo_focus "$@" ;;
    "unfocus") ztodo_unfocus ;;
    "context") ztodo_context ;;
    "report") ztodo_report "$@" ;;
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

# Compact reports (today/week)
ztodo_report() {
  _ztodo_ensure_db || return 1
  local scope="$1"
  if [[ -z "$scope" ]]; then
    echo "${RED}Usage: ztodo report <today|week>${NC}"
    return 1
  fi
  local where=""
  case "$scope" in
    today)
      where="date(created_at) = date('now')"
      ;;
    week)
      where="date(created_at) BETWEEN date('now','-6 day') AND date('now')"
      ;;
    *)
      echo "${RED}Unknown scope: $scope (use today|week)${NC}"
      return 1
      ;;
  esac
  local sep=$'\x1F'
  local rows=$(sqlite3 -separator "$sep" "$ZTODO_DB_PATH" "SELECT IFNULL(task_id,''), IFNULL(meta,''), IFNULL(created_at,'') FROM task_history WHERE event='cmd' AND $where ORDER BY created_at;")
  if [[ -z "$rows" ]]; then
    echo "No command history for $scope"
    return 0
  fi
  typeset -A count_by; typeset -A secs_by; typeset -A last_by
  local IFS=$'\n'
  for line in ${(f)rows}; do
    local task_id=${${(ps:$sep:)line}[1]}
    local meta=${${(ps:$sep:)line}[2]}
    local ts=${${(ps:$sep:)line}[3]}
    (( count_by[$task_id]++ ))
    local dur=$(print -r -- "$meta" | sed -n 's/.*;duration=\([0-9][0-9]*\).*/\1/p')
    [[ -z "$dur" ]] && dur=0
    (( secs_by[$task_id]+=dur ))
    last_by[$task_id]="$ts"
  done
  echo "${BLUE}Report ($scope)${NC}"
  echo "Task  Title                                   Cmds  Time  Last"
  echo "---------------------------------------------------------------"
  for task_id in ${(k)count_by}; do
    local title=$(sqlite3 "$ZTODO_DB_PATH" "SELECT IFNULL(title,'') FROM tasks WHERE id=$task_id;")
    local cmds=${count_by[$task_id]:-0}
    local mins=$(( secs_by[$task_id] / 60 ))
    printf "%4s  %-38s %4d  %4dm  %s\n" "$task_id" "$title" "$cmds" "$mins" "${last_by[$task_id]}"
  done | sort
}

# Initialize database on plugin load
_ztodo_ensure_db >/dev/null

# Show upcoming deadlines if enabled
if [[ "${ZTODO_SHOW_UPCOMING_DEADLINES:-false}" == "true" ]]; then
  _ztodo_show_upcoming_deadlines
fi

# Simple on-load message (notification)
if [[ "${ZTODO_ONLOAD_MESSAGE:-true}" == "true" ]]; then
  echo "${BLUE}ZTodo ready:${NC} type 'ztodo help' for commands."
fi

# Restore focus from previous session if enabled
if [[ "${ZTODO_FOCUS_PERSIST}" == "true" && -z "${ZTODO_ACTIVE_TASK}" && -f "$ZTODO_FOCUS_FILE" ]]; then
  ZTODO_ACTIVE_TASK=$(cat "$ZTODO_FOCUS_FILE" 2>/dev/null)
  if [[ -n "$ZTODO_ACTIVE_TASK" ]]; then
    # Validate task exists
    if [[ $(sqlite3 "$ZTODO_DB_PATH" "SELECT COUNT(*) FROM tasks WHERE id=$ZTODO_ACTIVE_TASK;") -eq 0 ]]; then
      unset ZTODO_ACTIVE_TASK
    fi
  fi
fi

# Register history hooks if enabled
if [[ "${ZTODO_HISTORY_ENABLED}" == "true" ]]; then
  typeset -ga preexec_functions
  typeset -ga precmd_functions
  if ! (( ${preexec_functions[(I)_ztodo_history_preexec]} )); then
    preexec_functions+=( _ztodo_history_preexec )
  fi
  if ! (( ${precmd_functions[(I)_ztodo_history_precmd]} )); then
    precmd_functions+=( _ztodo_history_precmd )
  fi
fi

# Focus helpers
ztodo_focus() {
  _ztodo_ensure_db || return 1
  local id="$1"
  if [[ -z "$id" ]]; then
    echo "${RED}Usage: ztodo focus <id>${NC}"
    return 1
  fi
  local exists=$(sqlite3 "$ZTODO_DB_PATH" "SELECT COUNT(*) FROM tasks WHERE id = $id;")
  if [[ "$exists" -eq "0" ]]; then
    echo "${RED}Task not found: $id${NC}"
    return 1
  fi
  export ZTODO_ACTIVE_TASK="$id"
  if [[ "${ZTODO_FOCUS_PERSIST}" == "true" ]]; then
    print -r -- "$id" > "$ZTODO_FOCUS_FILE" 2>/dev/null || true
  fi
  echo "${GREEN}Focused task $id${NC}"
}

ztodo_unfocus() {
  unset ZTODO_ACTIVE_TASK
  if [[ "${ZTODO_FOCUS_PERSIST}" == "true" && -f "$ZTODO_FOCUS_FILE" ]]; then
    : > "$ZTODO_FOCUS_FILE" 2>/dev/null || true
  fi
  echo "${GREEN}Focus cleared${NC}"
}

ztodo_context() {
  if [[ -n "${ZTODO_ACTIVE_TASK}" ]]; then
    local t=$(sqlite3 -separator '|' "$ZTODO_DB_PATH" "SELECT id||' - '||title FROM tasks WHERE id=$ZTODO_ACTIVE_TASK;")
    if [[ -n "$t" ]]; then
      echo "${BLUE}Focused:${NC} $t"
      return 0
    fi
  fi
  echo "No task focused"
}
