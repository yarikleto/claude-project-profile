# files.sh — File operations between live project and profile directories
#
# What gets switched is defined entirely by .claude-profiles/.include
# Supports glob patterns: .claude/*.json, docs/**/*.md, etc.
# Default: .claude/ and CLAUDE.md

# ─── Safety boundary ──────────────────────────────────────────
# Hard guard: verify that base/rel resolves to a path within base.
# This is the last line of defense — every copy/move/delete MUST pass this.
_assert_path_within() {
  local rel="$1" base="$2"
  local real_base
  real_base="$(cd "$base" 2>/dev/null && pwd -P)" || {
    err "SAFETY: base directory '$base' does not exist"
    return 1
  }
  local target="$base/$rel"
  # Resolve the real path as far as possible, including symlinks on the final component
  if [[ -e "$target" || -L "$target" ]]; then
    local real_target
    if [[ -d "$target" && ! -L "$target" ]]; then
      # Real directory — resolve via cd
      real_target="$(cd "$target" 2>/dev/null && pwd -P)"
    elif [[ -L "$target" ]]; then
      # Symlink — fully resolve it (follow all symlinks)
      # Use readlink -f (available on macOS and Linux) to resolve the entire chain
      real_target="$(readlink -f "$target" 2>/dev/null)" || {
        # Fallback: resolve the symlink manually
        local link_dest
        link_dest="$(readlink "$target" 2>/dev/null)" || link_dest="$target"
        if [[ "$link_dest" == /* ]]; then
          real_target="$link_dest"
        else
          real_target="$(cd "$(dirname "$target")" 2>/dev/null && pwd -P)/$link_dest"
        fi
      }
    else
      # Regular file — resolve the parent directory and keep the basename
      real_target="$(cd "$(dirname "$target")" 2>/dev/null && pwd -P)/$(basename "$target")"
    fi
    if [[ "$real_target" != "$real_base" && "$real_target" != "$real_base/"* ]]; then
      err "SAFETY: '$rel' resolves outside allowed directory — refusing to proceed"
      return 1
    fi
  else
    # Target doesn't exist — walk up to the nearest existing ancestor
    local check="$target"
    while [[ ! -e "$check" && "$check" != "/" ]]; do
      check="$(dirname "$check")"
    done
    local real_ancestor
    real_ancestor="$(cd "$check" 2>/dev/null && pwd -P)" || return 1
    if [[ "$real_ancestor" != "$real_base" && "$real_ancestor" != "$real_base/"* ]]; then
      err "SAFETY: '$rel' resolves outside allowed directory — refusing to proceed"
      return 1
    fi
  fi
  return 0
}

# Seed a new (empty) profile with template files.
_seed_profile() {
  local dst="$1"
  _ensure_paths
  local seed_dir="$PROFILES_DIR/.seed"
  local f
  for f in "$seed_dir"/* "$seed_dir"/.*; do
    local base
    base="$(basename "$f")"
    [[ "$base" == "." || "$base" == ".." ]] && continue
    [[ -e "$f" ]] && cp -RH "$f" "$dst/"
  done
}

# ─── Per-entry helpers ─────────────────────────────────────

# Move or copy a resolved path from source base into destination base.
_save_entry() {
  local rel="$1" src_base="$2" dst_base="$3" move="$4"
  rel="${rel%/}"
  _assert_path_within "$rel" "$src_base" || return 1
  _assert_path_within "$rel" "$dst_base" || return 1
  local src="$src_base/$rel"
  local dst="$dst_base/$rel"
  [[ -e "$src" ]] || return 0
  rm -rf "$dst"
  mkdir -p "$(dirname "$dst")"
  if [[ "$move" == "--move" ]]; then
    mv "$src" "$dst"
  else
    cp -RH "$src" "$dst"
  fi
}

# Remove a resolved path from a base directory.
_remove_entry() {
  local rel="$1" base="$2"
  rel="${rel%/}"
  _assert_path_within "$rel" "$base" || return 1
  local target="$base/$rel"
  if [[ -e "$target" || -L "$target" ]]; then
    rm -rf "$target"
  fi
}

# ─── Core operations ───────────────────────────────────────

# Copy live state into a profile directory (no git commit).
_snapshot_current() {
  local dst="$1"
  _ensure_paths
  local entry
  while IFS= read -r entry; do
    _save_entry "$entry" "$PROJECT_ROOT" "$dst" ""
  done < <(_resolve_includes "$PROJECT_ROOT")
}

# Save live state into a profile directory and commit.
# With --move, entries are moved instead of copied.
_save_current_to() {
  local dst="$1"
  local msg="${2:-Auto-save}"
  local move="${3:-}"
  _ensure_paths
  mkdir -p "$dst"

  local entry
  while IFS= read -r entry; do
    _save_entry "$entry" "$PROJECT_ROOT" "$dst" "$move"
  done < <(_resolve_includes "$PROJECT_ROOT")

  _git_commit "$dst" "$msg"
}

# Pre-validate a profile directory is safe to load.
_validate_profile_for_load() {
  local profile_dir="$1"
  local f
  for f in "$profile_dir"/* "$profile_dir"/.*; do
    local base
    base="$(basename "$f")"
    [[ "$base" == "." || "$base" == ".." || "$base" == ".git" || "$base" == ".gitignore" ]] && continue
    if [[ -L "$f" ]]; then
      err "Symlink '$base' found in profile — aborting switch (live files untouched)"
      return 1
    fi
    if [[ -e "$f" ]]; then
      if [[ -d "$f" ]]; then
        local nested_symlink
        nested_symlink="$(find "$f" -type l 2>/dev/null | head -1)" || true
        if [[ -n "$nested_symlink" ]]; then
          err "Symlink found in $f — aborting switch (live files untouched)"
          return 1
        fi
      elif [[ -f "$f" && ! -r "$f" ]]; then
        err "Unreadable file '$base' in profile — aborting switch (live files untouched)"
        return 1
      fi
    fi
  done
}

# Restore profile contents into the live project.
_load_profile_to_live() {
  local profile_dir="$1"
  local move="${2:-}"
  _ensure_paths

  _validate_profile_for_load "$profile_dir" || return 1

  # Remove managed entries from live project (resolve against live)
  local entry
  while IFS= read -r entry; do
    _remove_entry "$entry" "$PROJECT_ROOT"
  done < <(_resolve_includes "$PROJECT_ROOT")

  # Restore from profile (resolve against profile dir)
  while IFS= read -r entry; do
    entry="${entry%/}"
    _assert_path_within "$entry" "$profile_dir" || continue
    _assert_path_within "$entry" "$PROJECT_ROOT" || continue
    local src="$profile_dir/$entry"
    local dst="$PROJECT_ROOT/$entry"
    if [[ -e "$src" && ! -L "$src" ]]; then
      mkdir -p "$(dirname "$dst")"
      if [[ "$move" == "--move" ]]; then
        mv "$src" "$dst"
      else
        cp -RH "$src" "$dst"
      fi
    fi
  done < <(_resolve_includes "$profile_dir")
}

# Restore from the original backup into live locations.
_restore_from_backup() {
  _ensure_paths
  local backup_dir="$PROFILES_DIR/.pre-profiles-backup"
  if [[ ! -d "$backup_dir" ]]; then
    err "Original backup not found — refusing to restore (would destroy live files)"
    return 1
  fi
  _load_profile_to_live "$backup_dir"
}
