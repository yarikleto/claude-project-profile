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

assert_no_restore_tmp_dirs() {
  ! compgen -G "$PROJECT_DIR/.claude-profiles/.restore-tmp.*" >/dev/null
}

make_readlink_without_f_fake() {
  local bin_dir="$1"
  local real_readlink
  real_readlink="$(command -v readlink)"
  mkdir -p "$bin_dir"
  cat > "$bin_dir/readlink" <<EOF
#!/usr/bin/env bash
if [[ "\${1:-}" == "-f" ]]; then
  exit 1
fi
exec "$real_readlink" "\$@"
EOF
  chmod +x "$bin_dir/readlink"
}

make_realpath_failure_fake() {
  local bin_dir="$1"
  mkdir -p "$bin_dir"
  cat > "$bin_dir/realpath" <<'EOF'
#!/usr/bin/env bash
exit 1
EOF
  chmod +x "$bin_dir/realpath"
}

make_git_checkout_failure_fake() {
  local bin_dir="$1"
  local real_git
  real_git="$(command -v git)"
  mkdir -p "$bin_dir"
  cat > "$bin_dir/git" <<EOF
#!/usr/bin/env bash
set -euo pipefail

args=("\$@")
cmd_index=0
if (( \${#args[@]} >= 3 )); then
  if [[ "\${args[0]}" == "-C" ]]; then
    cmd_index=2
  fi
fi

if (( \${#args[@]} > cmd_index )) && [[ "\${args[\$cmd_index]}" == "checkout" ]]; then
  ref_index=\$((cmd_index + 1))
  if (( \${#args[@]} > ref_index + 2 )) \
    && [[ "\${args[\$((ref_index + 1))]}" == "--" ]] \
    && [[ "\${args[\$((ref_index + 2))]}" == "." ]]; then
    case "\${CPP_FAKE_GIT_CHECKOUT_FAILURE_MODE:-target}" in
      all)
        exit 1
        ;;
      target)
        ref="\${args[\$ref_index]}"
        if [[ "\$ref" =~ ^[0-9a-fA-F]{40}$ ]]; then
          exit 1
        fi
        ;;
    esac
  fi
fi

exec "$real_git" "\$@"
EOF
  chmod +x "$bin_dir/git"
}
