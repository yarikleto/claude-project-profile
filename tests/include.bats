#!/usr/bin/env bats

load test_helper

@test ".include file is created on first use with defaults" {
  run_cli fork default
  [ "$status" -eq 0 ]
  [ -f "$PROJECT_DIR/.claude-profiles/.include" ]

  content="$(cat "$PROJECT_DIR/.claude-profiles/.include")"
  [[ "$content" == *".claude/"* ]]
  [[ "$content" == *"CLAUDE.md"* ]]
}

@test "both .claude/ and CLAUDE.md are managed by default" {
  run_cli fork default
  [ "$status" -eq 0 ]

  [ -d "$PROJECT_DIR/.claude-profiles/default/.claude" ]
  [ -f "$PROJECT_DIR/.claude-profiles/default/.claude/settings.json" ]
  [ -f "$PROJECT_DIR/.claude-profiles/default/CLAUDE.md" ]
}

@test "adding extra files to .include tracks them" {
  echo "# My agents" > "$PROJECT_DIR/AGENTS.md"

  run_cli fork base
  [ "$status" -eq 0 ]
  echo "AGENTS.md" >> "$PROJECT_DIR/.claude-profiles/.include"
  run_cli save -m "track agents"

  [ -f "$PROJECT_DIR/.claude-profiles/base/AGENTS.md" ]
  content="$(cat "$PROJECT_DIR/.claude-profiles/base/AGENTS.md")"
  [[ "$content" == *"My agents"* ]]
}

@test "switching profiles restores all managed files" {
  run_cli fork profile-a
  [ "$status" -eq 0 ]
  echo "AGENTS.md" >> "$PROJECT_DIR/.claude-profiles/.include"

  echo "# Agents A" > "$PROJECT_DIR/AGENTS.md"
  run_cli save -m "profile-a state"

  run_cli new profile-b
  echo "# Agents B" > "$PROJECT_DIR/AGENTS.md"
  echo "# Claude B" > "$PROJECT_DIR/CLAUDE.md"
  run_cli save -m "profile-b state"

  run_cli use profile-a
  [ "$status" -eq 0 ]

  agents="$(cat "$PROJECT_DIR/AGENTS.md")"
  [[ "$agents" == *"Agents A"* ]]

  claude="$(cat "$PROJECT_DIR/CLAUDE.md")"
  [[ "$claude" == *"Original CLAUDE.md"* ]]
}

@test "removing entry from .include stops tracking it" {
  echo "# Agents" > "$PROJECT_DIR/AGENTS.md"
  run_cli fork default
  [ "$status" -eq 0 ]

  echo "AGENTS.md" >> "$PROJECT_DIR/.claude-profiles/.include"
  run_cli save -m "added agents"

  run_cli fork second

  # Remove AGENTS.md from .include (keep only defaults)
  printf '.claude/\nCLAUDE.md\n' > "$PROJECT_DIR/.claude-profiles/.include"

  echo "# Changed" > "$PROJECT_DIR/AGENTS.md"
  run_cli save -m "after remove"

  # Switch back — AGENTS.md should NOT be touched
  run_cli use default
  agents="$(cat "$PROJECT_DIR/AGENTS.md")"
  [[ "$agents" == *"Changed"* ]]
}

@test "comments and blank lines in .include are ignored" {
  run_cli fork default
  [ "$status" -eq 0 ]

  cat > "$PROJECT_DIR/.claude-profiles/.include" <<'EOF'
# This is a comment
.claude/

  # Another comment
CLAUDE.md

EOF

  echo "# Test" > "$PROJECT_DIR/CLAUDE.md"
  run_cli save -m "test"
  [ "$status" -eq 0 ]

  [ -f "$PROJECT_DIR/.claude-profiles/default/CLAUDE.md" ]
  [ -d "$PROJECT_DIR/.claude-profiles/default/.claude" ]
}

@test "user can remove CLAUDE.md from .include" {
  run_cli fork default
  [ "$status" -eq 0 ]

  # Only track .claude/, not CLAUDE.md
  printf '.claude/\n' > "$PROJECT_DIR/.claude-profiles/.include"

  echo "# Default version" > "$PROJECT_DIR/CLAUDE.md"
  run_cli save -m "no claude.md tracking"

  # Modify CLAUDE.md and switch — it should NOT be managed
  echo "# Modified after save" > "$PROJECT_DIR/CLAUDE.md"

  run_cli new other
  echo '{"other": true}' > "$PROJECT_DIR/.claude/settings.json"
  run_cli save -m "other profile"

  run_cli use default

  # .claude/ should be restored (tracked)
  content="$(cat "$PROJECT_DIR/.claude/settings.json")"
  [[ "$content" == *'"setting": "original"'* ]]

  # CLAUDE.md should NOT be restored — it's not tracked
  # So it keeps whatever value was there before the switch
  md="$(cat "$PROJECT_DIR/CLAUDE.md")"
  [[ "$md" == *"Modified after save"* ]]
}
