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

# ─── Path traversal via .current: auto-save destination escape ────────────

@test "SECURITY: malformed .current (../..) does not relocate auto-save outside project" {
  # Sentinel directory OUTSIDE the project that an attacker tries to clobber.
  # With .current="../.." the save destination base becomes
  # PROFILES_DIR/../.. = TEST_DIR, and an attacker-controlled .include entry
  # naming the sentinel would cause it to be rm -rf'd and overwritten.
  mkdir -p "$TEST_DIR/sentinel"
  echo "PROTECTED" > "$TEST_DIR/sentinel/keep.txt"

  run_cli fork default
  [ "$status" -eq 0 ]

  # Attacker ships a malicious repo state:
  printf '../..' > "$PROJECT_DIR/.claude-profiles/.current"
  printf '.claude/\nsentinel\n' > "$PROJECT_DIR/.claude-profiles/.include"

  # cmd_new routes through _auto_save_current (with --move). It must NOT
  # treat "../.." as a profile path and must NOT touch the sentinel.
  run_cli new second

  # The out-of-project sentinel must survive untouched.
  [ -d "$TEST_DIR/sentinel" ]
  [ -f "$TEST_DIR/sentinel/keep.txt" ]
  [[ "$(cat "$TEST_DIR/sentinel/keep.txt")" == "PROTECTED" ]]

  # And nothing must have been written above the profiles dir as if it were
  # a save destination (e.g. a git history committed into TEST_DIR).
  [ ! -d "$TEST_DIR/.git" ]
}

@test "SECURITY: malformed .current with slash is treated as no active profile" {
  run_cli fork default
  [ "$status" -eq 0 ]

  printf 'a/b' > "$PROJECT_DIR/.claude-profiles/.current"

  # save with no name defaults to get_current(); a malformed value must not
  # be used as a path. get_current sanitizes to empty, so save errors on the
  # empty/invalid name rather than escaping the profiles dir.
  run_cli save -m "x"
  [ "$status" -ne 0 ]

  # No directory should have been created from the slashed value.
  [ ! -d "$PROJECT_DIR/.claude-profiles/a" ]
  [ ! -d "$PROJECT_DIR/.claude-profiles/a/b" ]
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

# ─── Symlink escape via live .claude pointing outside project ────────────

@test "SECURITY: symlink .claude pointing outside project must not exfiltrate files into profile via fork (live)" {
  # Create a sensitive directory outside the project with a secret file
  mkdir -p "$TEST_DIR/external-dir"
  echo "TOP SECRET DATA" > "$TEST_DIR/external-dir/secret.txt"
  echo '{"evil": true}' > "$TEST_DIR/external-dir/settings.json"

  # Replace .claude with a symlink to the external directory
  rm -rf "$PROJECT_DIR/.claude"
  ln -sf "$TEST_DIR/external-dir" "$PROJECT_DIR/.claude"

  # Attempt to fork — this should either fail or not copy external content
  run_cli fork default

  # The external secret must NOT appear in the profile directory
  [ ! -f "$PROJECT_DIR/.claude-profiles/default/secret.txt" ]
  [ ! -f "$PROJECT_DIR/.claude-profiles/default/.claude/secret.txt" ]

  # If fork succeeded, the profile must not contain the external settings
  if [ "$status" -eq 0 ] && [ -f "$PROJECT_DIR/.claude-profiles/default/.claude/settings.json" ]; then
    # The content must not be from the external directory
    local content
    content="$(cat "$PROJECT_DIR/.claude-profiles/default/.claude/settings.json")"
    [[ "$content" != *"evil"* ]]
  fi

  # Original external file must be untouched
  [ -f "$TEST_DIR/external-dir/secret.txt" ]
  [[ "$(cat "$TEST_DIR/external-dir/secret.txt")" == "TOP SECRET DATA" ]]
}

@test "SECURITY: relative symlink fallback does not exfiltrate outside files via fork" {
  mkdir -p "$TEST_DIR/external-dir"
  echo "RELATIVE SECRET" > "$TEST_DIR/external-dir/secret.txt"
  echo '{"evil": "relative"}' > "$TEST_DIR/external-dir/settings.json"

  rm -rf "$PROJECT_DIR/.claude"
  ln -s ../external-dir "$PROJECT_DIR/.claude"

  local fake_bin="$TEST_DIR/fake-bin"
  make_readlink_without_f_fake "$fake_bin"
  make_realpath_failure_fake "$fake_bin"
  export PATH="$fake_bin:$PATH"

  run_cli fork default

  [ ! -f "$PROJECT_DIR/.claude-profiles/default/secret.txt" ]
  [ ! -f "$PROJECT_DIR/.claude-profiles/default/.claude/secret.txt" ]

  if [ "$status" -eq 0 ] && [ -f "$PROJECT_DIR/.claude-profiles/default/.claude/settings.json" ]; then
    local content
    content="$(cat "$PROJECT_DIR/.claude-profiles/default/.claude/settings.json")"
    [[ "$content" != *"relative"* ]]
  fi

  [ -f "$TEST_DIR/external-dir/secret.txt" ]
  [[ "$(cat "$TEST_DIR/external-dir/secret.txt")" == "RELATIVE SECRET" ]]
}

@test "SECURITY: chained symlink fallback does not exfiltrate outside files via fork" {
  mkdir -p "$TEST_DIR/external-dir"
  echo "CHAINED SECRET" > "$TEST_DIR/external-dir/secret.txt"
  echo '{"evil": "chain"}' > "$TEST_DIR/external-dir/settings.json"

  rm -rf "$PROJECT_DIR/.claude"
  ln -s inner-link "$PROJECT_DIR/.claude"
  ln -s ../external-dir "$PROJECT_DIR/inner-link"

  local fake_bin="$TEST_DIR/fake-bin"
  make_readlink_without_f_fake "$fake_bin"
  make_realpath_failure_fake "$fake_bin"
  export PATH="$fake_bin:$PATH"

  run_cli fork default

  [ ! -f "$PROJECT_DIR/.claude-profiles/default/secret.txt" ]
  [ ! -f "$PROJECT_DIR/.claude-profiles/default/.claude/secret.txt" ]

  if [ "$status" -eq 0 ] && [ -f "$PROJECT_DIR/.claude-profiles/default/.claude/settings.json" ]; then
    local content
    content="$(cat "$PROJECT_DIR/.claude-profiles/default/.claude/settings.json")"
    [[ "$content" != *"chain"* ]]
  fi

  [ -f "$TEST_DIR/external-dir/secret.txt" ]
  [[ "$(cat "$TEST_DIR/external-dir/secret.txt")" == "CHAINED SECRET" ]]
}
