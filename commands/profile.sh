# profile.sh — Core profile operations: new, fork, use, save, deactivate

cmd_new() {
  local name="${1:-}"
  _require_profile_name "$name" "claude-project-profile new <name>"
  _ensure_paths
  _ensure_original_backup

  local profile_dir="$PROFILES_DIR/$name"
  if [[ -d "$profile_dir" ]]; then
    err "Profile '$(_pname "$name")' already exists"; exit 1
  fi

  # Auto-save current profile before switching
  _auto_save_current "Auto-save before new '$name'" --move

  mkdir -p "$profile_dir"
  _seed_profile "$profile_dir"
  _git_init "$profile_dir"
  _load_profile_to_live "$profile_dir"
  set_current "$name"
  ok "Created and activated $(_pname "$name") ${DIM}(clean)${NC}"
}

cmd_fork() {
  local name="${1:-}"
  _require_profile_name "$name" "claude-project-profile fork <name>"
  _ensure_paths
  _ensure_original_backup

  local profile_dir="$PROFILES_DIR/$name"
  if [[ -d "$profile_dir" ]]; then
    err "Profile '$(_pname "$name")' already exists"; exit 1
  fi

  mkdir -p "$profile_dir"

  local current
  current="$(get_current)"

  # Auto-save current profile before forking
  _auto_save_current "Auto-save before fork '$name'"

  if [[ -n "$current" ]]; then
    info "Forking from $(_pname "$current")..."
  else
    info "Forking from current project state..."
  fi
  _snapshot_current "$profile_dir"
  _git_init "$profile_dir"

  set_current "$name"
  ok "Created and activated $(_pname "$name")"
  _show_summary "$profile_dir"
}

cmd_use() {
  local name="${1:-}"
  _require_profile_name "$name" "claude-project-profile use <name>"
  _ensure_paths

  local profile_dir="$PROFILES_DIR/$name"
  if [[ ! -d "$profile_dir" ]]; then
    err "Profile '$(_pname "$name")' not found"
    cmd_list
    exit 1
  fi

  local current
  current="$(get_current)"

  if [[ "$current" == "$name" ]]; then
    ok "$(_pname "$name") is already active"
    return
  fi

  _ensure_original_backup

  # Pre-validate target profile before any destructive operations
  _validate_profile_for_load "$profile_dir" || exit 1

  # Auto-save current profile before switching
  _auto_save_current "Auto-save before switch to '$name'" --move

  info "Switching to $(_pname "$name")..."
  _load_profile_to_live "$profile_dir" --move

  set_current "$name"
  ok "Active profile: $(_pname "$name")"
  _show_summary "$profile_dir"
}

cmd_save() {
  local name="" msg=""
  while [[ $# -gt 0 ]]; do
    case "$1" in
      -m) msg="${2:?-m requires a message}"; shift 2 ;;
      *)  name="$1"; shift ;;
    esac
  done

  name="${name:-$(get_current)}"
  _require_profile_name "$name" "claude-project-profile save [name] [-m message]"
  _ensure_paths
  _ensure_original_backup

  local profile_dir="$PROFILES_DIR/$name"
  mkdir -p "$profile_dir"
  _save_current_to "$profile_dir" "${msg:-Manual save}"
  ok "Saved $(_pname "$name")"
}

cmd_deactivate() {
  local keep=false
  if [[ "${1:-}" == "--keep" ]]; then
    keep=true
  fi

  _ensure_paths
  local current
  current="$(get_current)"
  if [[ -z "$current" ]]; then
    warn "No profile is active"; return
  fi

  if [[ "$keep" == true ]]; then
    _auto_save_current "Auto-save before deactivate --keep"
    clear_current
    ok "Detached from $(_pname "$current") — current project config kept as-is"
  else
    local backup_dir="$PROFILES_DIR/.pre-profiles-backup"
    if [[ ! -d "$backup_dir" ]]; then
      err "Original backup not found — refusing to restore (would destroy live files)"
      return 1
    fi
    _auto_save_current "Auto-save before deactivate" --move
    info "Restoring original project state..."
    _restore_from_backup
    clear_current
    ok "Deactivated $(_pname "$current"), restored original project state"
  fi
}
