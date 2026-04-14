# history.sh — Git-based change tracking: history, diff, restore

# ─── Argument parsing helper ──────────────────────────────────
# Sets _PARSED_NAME and _PARSED_REF in the caller's scope.
_parse_name_ref() {
  _PARSED_NAME="" _PARSED_REF=""
  for arg in "$@"; do
    _ensure_paths
    if [[ -d "$PROFILES_DIR/$arg" ]]; then
      _PARSED_NAME="$arg"
    else
      _PARSED_REF="$arg"
    fi
  done
}

cmd_history() {
  local name="${1:-$(get_current)}"
  _require_profile_name "$name" "claude-project-profile history [name]"
  _ensure_paths

  local profile_dir="$PROFILES_DIR/$name"
  if [[ ! -d "$profile_dir/.git" ]]; then
    warn "No history for profile $(_pname "$name")"; return
  fi

  echo -e "${CYAN}${BOLD}History: $name${NC}"
  echo ""
  git -C "$profile_dir" log --format="  %C(yellow)%h%C(reset) %C(dim)%ci%C(reset)  %s" --date=short
}

cmd_diff() {
  _parse_name_ref "$@"
  local name="${_PARSED_NAME:-$(get_current)}"
  local ref="$_PARSED_REF"
  _require_profile_name "$name" "claude-project-profile diff [name] [commit|date]"
  _ensure_paths

  local profile_dir="$PROFILES_DIR/$name"
  if [[ ! -d "$profile_dir/.git" ]]; then
    warn "No history for profile $(_pname "$name")"; return
  fi

  if [[ -z "$ref" ]]; then
    _diff_unsaved "$name" "$profile_dir"
  else
    _diff_since_ref "$name" "$profile_dir" "$ref"
  fi
}

_diff_unsaved() {
  local name="$1" profile_dir="$2"
  echo -e "${CYAN}${BOLD}Unsaved changes: $name${NC}"
  echo ""

  local tmp
  tmp="$(mktemp -d)" || return 1
  trap "rm -rf '$tmp'" RETURN

  _snapshot_current "$tmp"

  local diff_args
  diff_args=(-rq "$profile_dir" "$tmp" --exclude=.git --exclude=.gitignore)

  local changes diff_status=0
  if ! changes="$(diff "${diff_args[@]}" 2>/dev/null \
    | sed "s|$profile_dir|profile|g; s|$tmp|current|g")"; then
    diff_status=$?
    if [[ $diff_status -gt 1 ]]; then
      return "$diff_status"
    fi
  fi

  if [[ -n "$changes" ]]; then
    echo "$changes"
  else
    echo -e "  ${DIM}(no changes)${NC}"
  fi
}

_diff_since_ref() {
  local name="$1" profile_dir="$2" ref="$3"
  local resolved
  resolved="$(_git_resolve_ref "$profile_dir" "$ref")"

  echo -e "${CYAN}${BOLD}Changes since $ref: $name${NC}"
  echo ""
  git -C "$profile_dir" diff "$resolved"..HEAD --stat --
  echo ""
  git -C "$profile_dir" diff "$resolved"..HEAD --
}

cmd_restore() {
  _parse_name_ref "$@"
  local name="${_PARSED_NAME:-$(get_current)}"
  local ref="$_PARSED_REF"
  if [[ -z "$name" || -z "$ref" ]]; then
    err "Usage: claude-project-profile restore [name] <commit|date>"; exit 1
  fi

  _ensure_paths
  local profile_dir="$PROFILES_DIR/$name"
  if [[ ! -d "$profile_dir/.git" ]]; then
    err "No history for profile $(_pname "$name")"; exit 1
  fi

  local resolved
  resolved="$(_git_resolve_ref "$profile_dir" "$ref")"

  local short
  short="$(git -C "$profile_dir" log --format='%h %s' -1 "$resolved" --)"
  info "Restoring $(_pname "$name") to: ${YELLOW}$short${NC}"

  if [[ "$(get_current)" == "$name" ]]; then
    _save_current_to "$profile_dir" "Auto-save before restore to $ref"
  fi

  # Create a safety snapshot so we can roll back if checkout fails
  local backup_tag="_restore_backup_$$"
  git -C "$profile_dir" tag "$backup_tag" HEAD 2>/dev/null

  if ! git -C "$profile_dir" rm -rf --quiet . 2>/dev/null; then
    git -C "$profile_dir" tag -d "$backup_tag" 2>/dev/null || true
    err "Failed to clean working tree for $ref — profile unchanged"
    exit 1
  fi
  if ! git -C "$profile_dir" checkout "$resolved" -- . 2>/dev/null; then
    # Checkout failed — roll back to the safety snapshot
    git -C "$profile_dir" checkout "$backup_tag" -- . 2>/dev/null || true
    git -C "$profile_dir" tag -d "$backup_tag" 2>/dev/null || true
    err "Failed to checkout $ref — restore aborted, profile rolled back"
    exit 1
  fi

  git -C "$profile_dir" tag -d "$backup_tag" 2>/dev/null || true
  _git_commit "$profile_dir" "Restored to $ref"

  if [[ "$(get_current)" == "$name" ]]; then
    info "Reloading active profile..."
    _load_profile_to_live "$profile_dir"
  fi

  ok "Restored $(_pname "$name") to ${YELLOW}$ref${NC}"
}
