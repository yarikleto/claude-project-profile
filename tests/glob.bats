#!/usr/bin/env bats

load test_helper

@test "glob *.json matches specific files in .claude/" {
  echo '{"memory": true}' > "$PROJECT_DIR/.claude/memory.json"
  echo "not-json" > "$PROJECT_DIR/.claude/notes.txt"

  # Init profiles, then switch to glob before saving
  run_cli fork default
  [ "$status" -eq 0 ]
  printf '.claude/*.json\nCLAUDE.md\n' > "$PROJECT_DIR/.claude-profiles/.include"

  # Create a fresh profile with glob-only tracking
  run_cli new glob-test
  echo '{"memory": true}' > "$PROJECT_DIR/.claude/memory.json"
  echo '{"setting": "original"}' > "$PROJECT_DIR/.claude/settings.json"
  echo "not-json" > "$PROJECT_DIR/.claude/notes.txt"
  run_cli save -m "json only"

  # Both json files should be in profile
  [ -f "$PROJECT_DIR/.claude-profiles/glob-test/.claude/settings.json" ]
  [ -f "$PROJECT_DIR/.claude-profiles/glob-test/.claude/memory.json" ]

  # txt file should NOT be in profile
  [ ! -f "$PROJECT_DIR/.claude-profiles/glob-test/.claude/notes.txt" ]
}

@test "glob pattern switches only matched files" {
  echo '{"memory": "dev"}' > "$PROJECT_DIR/.claude/memory.json"
  echo "dev notes" > "$PROJECT_DIR/.claude/notes.txt"

  run_cli fork dev
  [ "$status" -eq 0 ]
  printf '.claude/*.json\nCLAUDE.md\n' > "$PROJECT_DIR/.claude-profiles/.include"
  run_cli save -m "dev state"

  # Change files and create new profile
  echo '{"memory": "review"}' > "$PROJECT_DIR/.claude/memory.json"
  echo '{"setting": "review"}' > "$PROJECT_DIR/.claude/settings.json"
  echo "review notes" > "$PROJECT_DIR/.claude/notes.txt"
  run_cli fork review
  run_cli save -m "review state"

  # Switch back to dev
  run_cli use dev
  [ "$status" -eq 0 ]

  # json files should be restored
  mem="$(cat "$PROJECT_DIR/.claude/memory.json")"
  [[ "$mem" == *'"memory": "dev"'* ]]

  # notes.txt should NOT be touched (not matched by glob)
  notes="$(cat "$PROJECT_DIR/.claude/notes.txt")"
  [[ "$notes" == *"review notes"* ]]
}

@test "multiple glob patterns work together" {
  mkdir -p "$PROJECT_DIR/docs"
  echo "# Guide" > "$PROJECT_DIR/docs/guide.md"
  echo "# API" > "$PROJECT_DIR/docs/api.md"
  echo "data" > "$PROJECT_DIR/docs/data.csv"

  run_cli fork default
  [ "$status" -eq 0 ]
  printf '.claude/\nCLAUDE.md\ndocs/*.md\n' > "$PROJECT_DIR/.claude-profiles/.include"
  run_cli save -m "with docs"

  [ -f "$PROJECT_DIR/.claude-profiles/default/docs/guide.md" ]
  [ -f "$PROJECT_DIR/.claude-profiles/default/docs/api.md" ]
  [ ! -f "$PROJECT_DIR/.claude-profiles/default/docs/data.csv" ]
}

@test "glob with no matches is silently skipped" {
  run_cli fork default
  [ "$status" -eq 0 ]
  printf '.claude/\nCLAUDE.md\n*.nonexistent\n' > "$PROJECT_DIR/.claude-profiles/.include"
  run_cli save -m "with missing glob"
  [ "$status" -eq 0 ]
}

@test "? glob matches single character" {
  echo "a" > "$PROJECT_DIR/.claude/a.json"
  echo "b" > "$PROJECT_DIR/.claude/b.json"
  echo "ab" > "$PROJECT_DIR/.claude/ab.json"

  # Set up glob include BEFORE first meaningful save
  run_cli fork default
  [ "$status" -eq 0 ]
  printf '.claude/?.json\nCLAUDE.md\n' > "$PROJECT_DIR/.claude-profiles/.include"

  run_cli new qmark-test
  echo "a" > "$PROJECT_DIR/.claude/a.json"
  echo "b" > "$PROJECT_DIR/.claude/b.json"
  echo "ab" > "$PROJECT_DIR/.claude/ab.json"
  run_cli save -m "single char glob"

  [ -f "$PROJECT_DIR/.claude-profiles/qmark-test/.claude/a.json" ]
  [ -f "$PROJECT_DIR/.claude-profiles/qmark-test/.claude/b.json" ]
  [ ! -f "$PROJECT_DIR/.claude-profiles/qmark-test/.claude/ab.json" ]
}

@test "** recursive glob matches nested files" {
  mkdir -p "$PROJECT_DIR/docs/api"
  mkdir -p "$PROJECT_DIR/docs/guides/getting-started"
  echo "# Top" > "$PROJECT_DIR/docs/README.md"
  echo "# API" > "$PROJECT_DIR/docs/api/endpoints.md"
  echo "# Guide" > "$PROJECT_DIR/docs/guides/getting-started/intro.md"
  echo "data" > "$PROJECT_DIR/docs/api/schema.yaml"

  run_cli fork default
  [ "$status" -eq 0 ]
  printf '.claude/\nCLAUDE.md\ndocs/**/*.md\n' > "$PROJECT_DIR/.claude-profiles/.include"
  run_cli save -m "recursive docs"

  # All .md files at any depth should be matched
  [ -f "$PROJECT_DIR/.claude-profiles/default/docs/README.md" ]
  [ -f "$PROJECT_DIR/.claude-profiles/default/docs/api/endpoints.md" ]
  [ -f "$PROJECT_DIR/.claude-profiles/default/docs/guides/getting-started/intro.md" ]

  # Non-md files should NOT be matched
  [ ! -f "$PROJECT_DIR/.claude-profiles/default/docs/api/schema.yaml" ]
}
