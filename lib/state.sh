# state.sh — Profile state: current profile, backup, directory management

ensure_dir() {
  _ensure_paths
  mkdir -p "$PROFILES_DIR"
}

get_current() {
  _ensure_paths
  if [[ -f "$CURRENT_FILE" ]]; then
    cat "$CURRENT_FILE"
  else
    echo ""
  fi
}

set_current() {
  _ensure_paths
  echo "$1" > "$CURRENT_FILE"
}

clear_current() {
  _ensure_paths
  rm -f "$CURRENT_FILE"
}

# Back up original project .claude/ state once, before first use.
_backup_raw_state() {
  _ensure_paths
  local backup_dir="$PROFILES_DIR/.pre-profiles-backup"
  [[ -d "$backup_dir" ]] && return
  mkdir -p "$backup_dir"
  info "Backing up original project state..."
  _snapshot_current "$backup_dir"
}

_ensure_seed_dir() {
  _ensure_paths
  local seed_dir="$PROFILES_DIR/.seed"
  [[ -d "$seed_dir" ]] && return
  mkdir -p "$seed_dir"
  local i
  for i in "${!SEED_NAMES[@]}"; do
    mkdir -p "$(dirname "$seed_dir/${SEED_NAMES[$i]}")"
    echo "${SEED_CONTENTS[$i]}" > "$seed_dir/${SEED_NAMES[$i]}"
  done
}

_ensure_include_file() {
  _ensure_paths
  [[ -f "$INCLUDE_FILE" ]] && return
  echo "$INCLUDE_DEFAULT" > "$INCLUDE_FILE"
}

_ensure_original_backup() {
  ensure_dir
  _ensure_include_file
  _backup_raw_state
  _ensure_seed_dir
}

_validate_profile_name() {
  local name="$1"
  # Whitelist: alphanumeric, hyphens, underscores. Must start with alphanumeric.
  if [[ ! "$name" =~ ^[a-zA-Z0-9][a-zA-Z0-9._-]*$ ]]; then
    err "Invalid profile name '$name' (must start with alphanumeric, only letters/digits/hyphens/underscores/dots allowed)"
    exit 1
  fi
  # Double-check: block any embedded ".." even without slashes
  if [[ "$name" == *..* ]]; then
    err "Invalid profile name '$name' (contains '..')"
    exit 1
  fi
}

_require_profile_name() {
  local name="$1" usage="$2"
  if [[ -z "$name" ]]; then
    err "Usage: $usage"
    exit 1
  fi
  _validate_profile_name "$name"
}

_require_profile_exists() {
  local name="$1"
  _ensure_paths
  local profile_dir="$PROFILES_DIR/$name"
  if [[ ! -d "$profile_dir" ]]; then
    err "Profile '$name' not found"
    exit 1
  fi
}

# Auto-save the current active profile before a destructive operation.
_auto_save_current() {
  local msg="$1" move="${2:-}"
  _ensure_paths
  local current
  current="$(get_current)"
  if [[ -n "$current" && -d "$PROFILES_DIR/$current" ]]; then
    info "Saving $(_pname "$current")..."
    _save_current_to "$PROFILES_DIR/$current" "$msg" "$move"
  fi
}
