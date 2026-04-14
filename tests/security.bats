#!/usr/bin/env bats

load test_helper

# ─── Path traversal via .include: SAVE must not read outside project ──────

@test "SECURITY: save does not copy files outside project via ../ in .include" {
  echo "SENSITIVE" > "$TEST_DIR/secret.txt"

  run_cli fork default
  [ "$status" -eq 0 ]

  printf '.claude/\nCLAUDE.md\n../secret.txt\n' > "$PROJECT_DIR/.claude-profiles/.include"

  run_cli save -m "attempt traversal"

  # The file outside the project must NOT appear anywhere in the profile
  [ ! -f "$PROJECT_DIR/.claude-profiles/default/../secret.txt" ]
  [ ! -f "$PROJECT_DIR/.claude-profiles/secret.txt" ]

  # The original file must be untouched
  [ -f "$TEST_DIR/secret.txt" ]
  [[ "$(cat "$TEST_DIR/secret.txt")" == "SENSITIVE" ]]
}

@test "SECURITY: save does not copy files outside project via nested ../ in .include" {
  mkdir -p "$TEST_DIR/above"
  echo "PRIVATE" > "$TEST_DIR/above/private.key"

  run_cli fork default
  [ "$status" -eq 0 ]

  printf '.claude/\nfoo/../../above/private.key\n' > "$PROJECT_DIR/.claude-profiles/.include"

  run_cli save -m "nested traversal"

  [ ! -f "$PROJECT_DIR/.claude-profiles/default/foo/../../above/private.key" ]
  # Original untouched
  [ -f "$TEST_DIR/above/private.key" ]
}

@test "SECURITY: save does not copy files via absolute path in .include" {
  run_cli fork default
  [ "$status" -eq 0 ]

  printf '.claude/\n/etc/hostname\n' > "$PROJECT_DIR/.claude-profiles/.include"

  run_cli save -m "absolute path"

  [ ! -f "$PROJECT_DIR/.claude-profiles/default/etc/hostname" ]
}

# ─── Path traversal via .include: SWITCH must not delete outside project ──

@test "SECURITY: switch does not delete files outside project via ../ in .include" {
  echo "DO NOT DELETE" > "$TEST_DIR/preserve-me.txt"

  run_cli fork first
  [ "$status" -eq 0 ]

  printf '.claude/\nCLAUDE.md\n../preserve-me.txt\n' > "$PROJECT_DIR/.claude-profiles/.include"

  run_cli new second
  run_cli use first

  # The file outside the project MUST still exist
  [ -f "$TEST_DIR/preserve-me.txt" ]
  [[ "$(cat "$TEST_DIR/preserve-me.txt")" == "DO NOT DELETE" ]]
}

@test "SECURITY: switch does not overwrite files outside project via ../ in .include" {
  echo "ORIGINAL CONTENT" > "$TEST_DIR/outside.txt"

  run_cli fork first
  [ "$status" -eq 0 ]

  printf '.claude/\nCLAUDE.md\n../outside.txt\n' > "$PROJECT_DIR/.claude-profiles/.include"

  # Even if a profile somehow has a ../outside.txt, it should not be written
  run_cli new second
  run_cli use first

  [ -f "$TEST_DIR/outside.txt" ]
  [[ "$(cat "$TEST_DIR/outside.txt")" == "ORIGINAL CONTENT" ]]
}

# ─── Path traversal via .include: MOVE (--move) must not move outside ─────

@test "SECURITY: save --move does not remove files outside project via ../" {
  echo "KEEP ME" > "$TEST_DIR/keep.txt"

  run_cli fork first
  [ "$status" -eq 0 ]

  printf '.claude/\nCLAUDE.md\n../keep.txt\n' > "$PROJECT_DIR/.claude-profiles/.include"

  # cmd_new calls _save_current_to with --move
  run_cli new second

  # File outside project must survive the --move save
  [ -f "$TEST_DIR/keep.txt" ]
  [[ "$(cat "$TEST_DIR/keep.txt")" == "KEEP ME" ]]
}

# ─── Path traversal via .include: DEACTIVATE must not delete outside ──────

@test "SECURITY: deactivate does not delete files outside project" {
  echo "EXTERNAL" > "$TEST_DIR/external.txt"

  run_cli fork default
  [ "$status" -eq 0 ]

  printf '.claude/\nCLAUDE.md\n../external.txt\n' > "$PROJECT_DIR/.claude-profiles/.include"

  run_cli deactivate

  [ -f "$TEST_DIR/external.txt" ]
  [[ "$(cat "$TEST_DIR/external.txt")" == "EXTERNAL" ]]
}

# ─── Path traversal: trailing /.. edge case ───────────────────────────────

@test "SECURITY: path ending in /.. is blocked" {
  mkdir -p "$TEST_DIR/above"
  echo "SECRET" > "$TEST_DIR/above/data.txt"

  run_cli fork default
  [ "$status" -eq 0 ]

  printf '.claude/\nfoo/..\n' > "$PROJECT_DIR/.claude-profiles/.include"

  run_cli save -m "trailing dotdot"

  # Must not have copied anything from parent
  [ ! -f "$PROJECT_DIR/.claude-profiles/default/foo/../data.txt" ]
  [ -f "$TEST_DIR/above/data.txt" ]
}

# ─── Code injection via eval in glob patterns ─────────────────────────────

@test "SECURITY: command substitution in .include glob is not executed" {
  local marker="$TEST_DIR/pwned"

  run_cli fork default
  [ "$status" -eq 0 ]

  # Glob metachar + command substitution: if eval is used, $(touch ...) executes
  printf '.claude/\n*$(touch %s)\n' "$marker" > "$PROJECT_DIR/.claude-profiles/.include"

  run_cli save -m "injection attempt" 2>/dev/null || true

  # The marker file must NOT exist
  [ ! -f "$marker" ]
}

@test "SECURITY: backtick injection in .include glob is not executed" {
  local marker="$TEST_DIR/pwned-backtick"

  run_cli fork default
  [ "$status" -eq 0 ]

  printf '.claude/\n*\x60touch %s\x60\n' "$marker" > "$PROJECT_DIR/.claude-profiles/.include"

  run_cli save -m "backtick injection" 2>/dev/null || true

  [ ! -f "$marker" ]
}

# ─── Profile name validation ──────────────────────────────────────────────

@test "SECURITY: profile name with slash is rejected" {
  run_cli fork "a/b"
  [ "$status" -ne 0 ]
  [[ "$output" == *"Invalid"* ]]
}

@test "SECURITY: profile name starting with dot is rejected" {
  run_cli fork ".hidden"
  [ "$status" -ne 0 ]
  [[ "$output" == *"Invalid"* ]]
}

@test "SECURITY: profile name starting with dash is rejected" {
  run_cli fork "-flag"
  [ "$status" -ne 0 ]
  [[ "$output" == *"Invalid"* ]]
}

@test "SECURITY: profile name with embedded .. is rejected" {
  run_cli fork "a..b"
  [ "$status" -ne 0 ]
  [[ "$output" == *"Invalid"* ]]
}

@test "SECURITY: profile name with control characters is rejected" {
  local name=$'evil\ttab'
  run_cli fork "$name"
  [ "$status" -ne 0 ]
}

@test "SECURITY: profile name with spaces is rejected" {
  run_cli fork "has space"
  [ "$status" -ne 0 ]
}

# ─── Symlink protection ──────────────────────────────────────────────────

@test "SECURITY: profile containing top-level symlink is rejected on load" {
  run_cli fork good
  [ "$status" -eq 0 ]

  run_cli fork poisoned
  [ "$status" -eq 0 ]

  # Plant a symlink in the poisoned profile dir
  ln -sf /etc/passwd "$PROJECT_DIR/.claude-profiles/poisoned/evil-link"

  run_cli use good
  [ "$status" -eq 0 ]

  # Switching to poisoned profile must fail
  run_cli use poisoned
  [ "$status" -ne 0 ]
  [[ "$output" == *"ymlink"* ]]
}

@test "SECURITY: profile containing nested symlink is rejected on load" {
  run_cli fork good
  [ "$status" -eq 0 ]

  run_cli fork poisoned
  [ "$status" -eq 0 ]

  # Switch to good first (this auto-saves poisoned cleanly)
  run_cli use good
  [ "$status" -eq 0 ]

  # NOW plant the nested symlink — after auto-save, so it won't be overwritten
  mkdir -p "$PROJECT_DIR/.claude-profiles/poisoned/.claude"
  ln -sf /etc/shadow "$PROJECT_DIR/.claude-profiles/poisoned/.claude/steal"

  # Switching to poisoned must fail due to symlink
  run_cli use poisoned
  [ "$status" -ne 0 ]
  [[ "$output" == *"ymlink"* ]]
}
