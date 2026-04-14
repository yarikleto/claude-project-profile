#!/usr/bin/env bats

load test_helper

# ─── Symlink escape: .claude directory ────────────────────────────────────

@test "SECURITY: statusline install refuses when .claude is a symlink" {
  # Set up an external directory that the symlink points to
  local external_dir="$TEST_DIR/outside"
  mkdir -p "$external_dir"

  # Ensure .claude-profiles exists so the command doesn't fail early
  mkdir -p "$PROJECT_DIR/.claude-profiles"

  # Replace .claude with a symlink to the external directory
  rm -rf "$PROJECT_DIR/.claude"
  ln -s "$external_dir" "$PROJECT_DIR/.claude"

  # statusline install must fail (refuse to follow the symlink)
  run_cli statusline install
  [ "$status" -ne 0 ]
  [[ "$output" == *"ymlink"* ]]

  # The external directory must NOT contain a settings.json
  [ ! -f "$external_dir/settings.json" ]
}

@test "SECURITY: statusline install refuses when settings.json is a symlink" {
  # Set up an external file that the symlink points to
  local external_file="$TEST_DIR/hijacked-settings.json"
  echo '{}' > "$external_file"

  # Ensure .claude-profiles exists so the command doesn't fail early
  mkdir -p "$PROJECT_DIR/.claude-profiles"

  # Replace settings.json with a symlink
  rm -f "$PROJECT_DIR/.claude/settings.json"
  ln -s "$external_file" "$PROJECT_DIR/.claude/settings.json"

  # statusline install must fail
  run_cli statusline install
  [ "$status" -ne 0 ]
  [[ "$output" == *"ymlink"* ]]

  # The external file must NOT have been modified with statusLine
  ! grep -q "statusLine" "$external_file"
}

# ─── Fresh repo: no .claude-profiles directory ────────────────────────────

@test "statusline install succeeds on fresh repo without .claude-profiles" {
  # Remove .claude-profiles entirely (simulating a fresh repo)
  rm -rf "$PROJECT_DIR/.claude-profiles"

  # statusline install should succeed even without existing profiles dir
  run_cli statusline install
  [ "$status" -eq 0 ]

  # The statusline script should have been created
  [ -f "$PROJECT_DIR/.claude-profiles/statusline.sh" ]
}
