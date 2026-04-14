# config.sh — Constants and path resolution (project-level)

VERSION="1.0.1"

# ─── Project root detection ────────────────────────────────
_detect_project_root() {
  local root
  root="$(git rev-parse --show-toplevel 2>/dev/null)" || {
    err "Not inside a git repository. Run this command from a project directory."
    exit 1
  }
  echo "$root"
}

# Lazily resolved — set once on first access via _ensure_paths
PROJECT_ROOT=""
PROFILES_DIR=""
CURRENT_FILE=""
INCLUDE_FILE=""

_ensure_paths() {
  if [[ -n "$PROJECT_ROOT" ]]; then
    return
  fi
  PROJECT_ROOT="$(_detect_project_root)"
  PROFILES_DIR="$PROJECT_ROOT/.claude-profiles"
  CURRENT_FILE="$PROFILES_DIR/.current"
  INCLUDE_FILE="$PROFILES_DIR/.include"
}

# Default content for .include
INCLUDE_DEFAULT="# Files and directories managed by profiles (relative to project root)
.claude/
CLAUDE.md"

# Seed files for new (empty) profiles (paths relative to profile root)
SEED_NAMES=(".claude/settings.json")
SEED_CONTENTS=(
  '{}'
)

# Gitignore for profile git history — keep only small config files
GITIGNORE_CONTENT="/projects
/agent-memory
/todos
/plans
/tasks
/plugins
/history.jsonl"
