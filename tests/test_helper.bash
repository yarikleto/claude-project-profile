# test_helper.bash — Common setup/teardown for bats tests

setup() {
  # Create a temporary directory for each test
  TEST_DIR="$(mktemp -d)"
  PROJECT_DIR="$TEST_DIR/project"
  mkdir -p "$PROJECT_DIR"

  # Initialize a git repo (required for project root detection)
  git -C "$PROJECT_DIR" init -q

  # Create initial .claude/ and CLAUDE.md
  mkdir -p "$PROJECT_DIR/.claude"
  echo '{"setting": "original"}' > "$PROJECT_DIR/.claude/settings.json"
  echo "# Original CLAUDE.md" > "$PROJECT_DIR/CLAUDE.md"

  # Point to the CLI
  CLI="$BATS_TEST_DIRNAME/../claude-project-profile"
}

teardown() {
  rm -rf "$TEST_DIR"
}

# Run the CLI from inside the test project
run_cli() {
  cd "$PROJECT_DIR" && run "$CLI" "$@"
}
