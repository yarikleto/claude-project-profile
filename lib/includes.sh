# includes.sh — Include file parsing and glob resolution

# Read raw include patterns. Returns one pattern per line.
# Skips comments and blank lines.
_get_includes() {
  _ensure_paths
  if [[ ! -f "$INCLUDE_FILE" ]]; then
    return
  fi
  while IFS= read -r line; do
    # Strip comments and whitespace
    line="${line%%#*}"
    line="${line#"${line%%[![:space:]]*}"}"
    line="${line%"${line##*[![:space:]]}"}"
    [[ -z "$line" ]] && continue
    echo "$line"
  done < "$INCLUDE_FILE"
}

# Check that a relative path doesn't escape its base via ../ traversal.
# Returns 0 (safe) or 1 (unsafe).
_is_safe_relative_path() {
  local rel="$1"
  # Reject absolute paths
  [[ "$rel" == /* ]] && return 1
  # Reject any component that is exactly ".."
  # Covers: "..", "../x", "x/../y", "x/.."
  [[ "$rel" == ".." || "$rel" == ../* || "$rel" == */../* || "$rel" == */.. ]] && return 1
  return 0
}

# Resolve include patterns against a base directory.
# Expands globs (*, ?, [], **) and returns one real path per line.
# Literal paths are returned as-is if they exist.
_resolve_includes() {
  local base="$1"
  local pattern
  while IFS= read -r pattern; do
    # Safety: reject patterns that could escape the project root
    if ! _is_safe_relative_path "$pattern"; then
      warn "Skipping unsafe include pattern: $pattern"
      continue
    fi

    # Directory pattern (trailing slash) — literal match
    if [[ "$pattern" == */ ]]; then
      local dir="${pattern%/}"
      if [[ -d "$base/$dir" ]]; then
        echo "$pattern"
      fi
      continue
    fi
    # Glob pattern — expand
    if [[ "$pattern" == *[\*\?\[]* ]]; then
      if [[ "$pattern" == *"**"* ]]; then
        # Recursive glob — use find (bash 3.2 has no globstar)
        # Split on ** to get prefix dir and suffix pattern
        local prefix="${pattern%%\*\**}"
        local suffix="${pattern#*\*\*}"
        prefix="${prefix%/}"
        suffix="${suffix#/}"
        local search_dir="$base/$prefix"
        # Resolve to real path and verify it stays within base
        local real_search
        real_search="$(cd "$search_dir" 2>/dev/null && pwd -P)" || continue
        local real_base
        real_base="$(cd "$base" 2>/dev/null && pwd -P)" || continue
        if [[ "$real_search" != "$real_base" && "$real_search" != "$real_base/"* ]]; then
          continue
        fi
        if [[ -d "$search_dir" ]]; then
          # Convert glob suffix to find -name pattern
          # e.g. "*.md" -> -name "*.md"
          local name_pattern="${suffix##*/}"
          find "$search_dir" -type f -name "$name_pattern" 2>/dev/null | while IFS= read -r match; do
            # Output path relative to base
            local rel_match="${match#"$base"/}"
            # Safety: skip any result that escapes base
            if [[ "$rel_match" == /* || "$rel_match" == ../* || "$rel_match" == */../* ]]; then
              continue
            fi
            echo "$rel_match"
          done
        fi
      else
        # Simple glob — use safe bash expansion (no eval)
        (
          cd "$base" 2>/dev/null || exit 0
          shopt -s nullglob dotglob 2>/dev/null || true
          # Expand the glob pattern safely via compgen
          while IFS= read -r -d '' _f; do
            echo "$_f"
          done < <(compgen -G "$pattern" | tr '\n' '\0') 2>/dev/null || true
        )
      fi
    else
      # Literal path
      if [[ -e "$base/$pattern" ]]; then
        echo "$pattern"
      fi
    fi
  done < <(_get_includes)
}
