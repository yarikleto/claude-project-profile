#!/usr/bin/env bats

load test_helper

make_restore_commit_failure_fake() {
  local bin_dir="$1"
  local real_git
  real_git="$(command -v git)"
  mkdir -p "$bin_dir"
  cat > "$bin_dir/git" <<EOF
#!/usr/bin/env bash
set -euo pipefail

args=("\$@")
cmd_index=0
git_dir=""
if (( \${#args[@]} >= 3 )) && [[ "\${args[0]}" == "-C" ]]; then
  git_dir="\${args[1]}"
  cmd_index=2
fi

if (( \${#args[@]} > cmd_index )) \
  && [[ "\${args[\$cmd_index]}" == "commit" ]] \
  && [[ "\$git_dir" == *"/.restore-tmp."* ]]; then
  exit 1
fi

exec "$real_git" "\$@"
EOF
  chmod +x "$bin_dir/git"
}

@test "version prints version string" {
  run_cli version
  [ "$status" -eq 0 ]
  [[ "$output" == *"claude-project-profile"* ]]
}

@test "help prints usage" {
  run_cli help
  [ "$status" -eq 0 ]
  [[ "$output" == *"USAGE"* ]]
  [[ "$output" == *"COMMANDS"* ]]
}

@test "list with no profiles shows empty message" {
  run_cli list
  [ "$status" -eq 0 ]
  [[ "$output" == *"No profiles yet"* ]]
}

@test "fork creates a profile from current state" {
  run_cli fork default
  [ "$status" -eq 0 ]
  [[ "$output" == *"default"* ]]

  [ -d "$PROJECT_DIR/.claude-profiles/default" ]
  [ -d "$PROJECT_DIR/.claude-profiles/default/.claude" ]
  [ -f "$PROJECT_DIR/.claude-profiles/default/.claude/settings.json" ]
  [ -f "$PROJECT_DIR/.claude-profiles/default/CLAUDE.md" ]
}

@test "fork preserves file contents" {
  run_cli fork default
  [ "$status" -eq 0 ]

  content="$(cat "$PROJECT_DIR/.claude-profiles/default/.claude/settings.json")"
  [[ "$content" == *'"setting": "original"'* ]]

  md_content="$(cat "$PROJECT_DIR/.claude-profiles/default/CLAUDE.md")"
  [[ "$md_content" == *"Original CLAUDE.md"* ]]
}

@test "current shows active profile after fork" {
  run_cli fork default
  [ "$status" -eq 0 ]

  run_cli current
  [ "$status" -eq 0 ]
  [[ "$output" == "default" ]]
}

@test "new creates a clean profile" {
  run_cli fork default
  run_cli new clean
  [ "$status" -eq 0 ]

  # Should have seed files
  [ -f "$PROJECT_DIR/.claude-profiles/clean/.claude/settings.json" ]

  # Should NOT have CLAUDE.md (clean profile)
  [ ! -f "$PROJECT_DIR/.claude-profiles/clean/CLAUDE.md" ]

  run_cli current
  [[ "$output" == "clean" ]]
}

@test "new replaces live state with clean profile" {
  run_cli new clean
  [ "$status" -eq 0 ]

  # Live CLAUDE.md should be removed (managed by .include)
  [ ! -f "$PROJECT_DIR/CLAUDE.md" ]

  # Live .claude/ should have seed settings
  [ -f "$PROJECT_DIR/.claude/settings.json" ]
}

@test "use switches between profiles" {
  run_cli fork dev
  [ "$status" -eq 0 ]

  echo '{"setting": "dev-modified"}' > "$PROJECT_DIR/.claude/settings.json"
  echo "# Dev CLAUDE.md" > "$PROJECT_DIR/CLAUDE.md"
  run_cli save -m "Dev modified"

  run_cli new review
  [ "$status" -eq 0 ]
  echo '{"setting": "review"}' > "$PROJECT_DIR/.claude/settings.json"
  echo "# Review CLAUDE.md" > "$PROJECT_DIR/CLAUDE.md"
  run_cli save -m "Review setup"

  run_cli use dev
  [ "$status" -eq 0 ]

  content="$(cat "$PROJECT_DIR/.claude/settings.json")"
  [[ "$content" == *"dev-modified"* ]]

  md_content="$(cat "$PROJECT_DIR/CLAUDE.md")"
  [[ "$md_content" == *"Dev CLAUDE.md"* ]]
}

@test "list shows all profiles with active marker" {
  run_cli fork alpha
  run_cli new beta

  run_cli list
  [ "$status" -eq 0 ]
  [[ "$output" == *"alpha"* ]]
  [[ "$output" == *"beta"* ]]
  [[ "$output" == *"(active)"* ]]
}

@test "delete removes a profile" {
  run_cli fork first
  run_cli new second

  run_cli delete first -f
  [ "$status" -eq 0 ]
  [ ! -d "$PROJECT_DIR/.claude-profiles/first" ]
}

@test "delete refuses to delete active profile" {
  run_cli fork only
  run_cli delete only -f
  [ "$status" -ne 0 ]
  [[ "$output" == *"Cannot delete the active profile"* ]]
}

@test "deactivate restores original state" {
  run_cli fork dev
  echo '{"setting": "modified"}' > "$PROJECT_DIR/.claude/settings.json"
  echo "# Modified" > "$PROJECT_DIR/CLAUDE.md"

  run_cli deactivate
  [ "$status" -eq 0 ]

  content="$(cat "$PROJECT_DIR/.claude/settings.json")"
  [[ "$content" == *'"setting": "original"'* ]]

  md_content="$(cat "$PROJECT_DIR/CLAUDE.md")"
  [[ "$md_content" == *"Original CLAUDE.md"* ]]

  run_cli current
  [ "$status" -ne 0 ]
}

@test "deactivate --keep keeps current config" {
  run_cli fork dev
  echo '{"setting": "keep-me"}' > "$PROJECT_DIR/.claude/settings.json"

  run_cli deactivate --keep
  [ "$status" -eq 0 ]

  content="$(cat "$PROJECT_DIR/.claude/settings.json")"
  [[ "$content" == *"keep-me"* ]]

  run_cli current
  [ "$status" -ne 0 ]
}

@test "fork rejects invalid profile names" {
  run_cli fork "../escape"
  [ "$status" -ne 0 ]

  run_cli fork ".hidden"
  [ "$status" -ne 0 ]

  run_cli fork "-flag"
  [ "$status" -ne 0 ]
}

@test "fork rejects duplicate names" {
  run_cli fork dup
  [ "$status" -eq 0 ]

  run_cli fork dup
  [ "$status" -ne 0 ]
  [[ "$output" == *"already exists"* ]]
}

@test "use with nonexistent profile fails" {
  run_cli use ghost
  [ "$status" -ne 0 ]
  [[ "$output" == *"not found"* ]]
}

@test "save commits profile state" {
  run_cli fork dev
  echo '{"setting": "v2"}' > "$PROJECT_DIR/.claude/settings.json"

  run_cli save -m "Updated settings"
  [ "$status" -eq 0 ]

  run_cli history
  [ "$status" -eq 0 ]
  [[ "$output" == *"Updated settings"* ]]
}

@test "show displays profile contents" {
  run_cli fork dev
  run_cli show dev
  [ "$status" -eq 0 ]
  [[ "$output" == *"dev"* ]]
}

@test "profiles are stored in .claude-profiles" {
  run_cli fork test-profile
  [ "$status" -eq 0 ]
  [ -d "$PROJECT_DIR/.claude-profiles" ]
  [ -d "$PROJECT_DIR/.claude-profiles/test-profile" ]
}

@test "backup is created on first use" {
  run_cli fork default
  [ "$status" -eq 0 ]
  [ -d "$PROJECT_DIR/.claude-profiles/.pre-profiles-backup" ]
  [ -f "$PROJECT_DIR/.claude-profiles/.pre-profiles-backup/.claude/settings.json" ]
}

@test "restore active profile reloads exact target tree and deletes later files" {
  run_cli fork exact
  [ "$status" -eq 0 ]

  echo '{"setting": "v1"}' > "$PROJECT_DIR/.claude/settings.json"
  rm -f "$PROJECT_DIR/.claude/extra.json"
  run_cli save -m "Version 1"
  [ "$status" -eq 0 ]

  local profile_dir="$PROJECT_DIR/.claude-profiles/exact"
  local target_commit target_tree restored_tree
  target_commit="$(git -C "$profile_dir" rev-parse HEAD)"
  target_tree="$(git -C "$profile_dir" rev-parse "${target_commit}^{tree}")"

  echo '{"setting": "v2"}' > "$PROJECT_DIR/.claude/settings.json"
  echo '{"later": true}' > "$PROJECT_DIR/.claude/extra.json"
  run_cli save -m "Version 2"
  [ "$status" -eq 0 ]
  [ -f "$profile_dir/.claude/extra.json" ]

  run_cli restore exact "$target_commit"
  [ "$status" -eq 0 ]

  [ ! -f "$profile_dir/.claude/extra.json" ]
  [ ! -f "$PROJECT_DIR/.claude/extra.json" ]
  [[ "$(cat "$profile_dir/.claude/settings.json")" == *'"setting": "v1"'* ]]
  [[ "$(cat "$PROJECT_DIR/.claude/settings.json")" == *'"setting": "v1"'* ]]

  restored_tree="$(git -C "$profile_dir" rev-parse HEAD^{tree})"
  [ "$restored_tree" = "$target_tree" ]
  [ -z "$(git -C "$profile_dir" status --porcelain --untracked-files=all)" ]
  assert_no_restore_tmp_dirs
}

@test "restore rollback: failed checkout does not destroy profile" {
  # 1. Create a profile with some content and history
  run_cli fork myprofile
  [ "$status" -eq 0 ]

  echo '{"setting": "v1"}' > "$PROJECT_DIR/.claude/settings.json"
  run_cli save -m "Version 1"
  [ "$status" -eq 0 ]

  echo '{"setting": "v2"}' > "$PROJECT_DIR/.claude/settings.json"
  run_cli save -m "Version 2"
  [ "$status" -eq 0 ]

  # Get the first non-HEAD commit (the "Version 1" commit)
  local profile_dir="$PROJECT_DIR/.claude-profiles/myprofile"
  local old_commit
  old_commit="$(git -C "$profile_dir" log --format='%H' --skip=1 -1)"

  # Snapshot current profile contents before the restore attempt
  local settings_before
  settings_before="$(cat "$profile_dir/.claude/settings.json")"

  # 2. Corrupt the tree object of the old commit so checkout will fail
  #    but rev-parse and git-log still succeed (commit object is intact)
  local tree_hash
  tree_hash="$(git -C "$profile_dir" cat-file -p "$old_commit" | grep tree | awk '{print $2}')"
  local obj_path="$profile_dir/.git/objects/${tree_hash:0:2}/${tree_hash:2}"
  chmod u+w "$obj_path"
  echo "CORRUPT" > "$obj_path"

  # 3. Attempt restore — should fail but NOT destroy the profile
  run_cli restore myprofile "$old_commit"
  [ "$status" -ne 0 ]

  # 4. Assert profile content is still intact (not destroyed)
  [ -f "$profile_dir/.claude/settings.json" ]
  local settings_after
  settings_after="$(cat "$profile_dir/.claude/settings.json")"
  [ "$settings_before" = "$settings_after" ]

  # 5. Verify the restore failed before mutating the original profile
  [[ "$output" == *"profile unchanged"* ]]
  assert_no_restore_tmp_dirs
}

@test "restore rollback preserves dirty tracked edits in inactive profile" {
  run_cli fork manual
  [ "$status" -eq 0 ]

  echo '{"setting": "v1"}' > "$PROJECT_DIR/.claude/settings.json"
  run_cli save -m "Version 1"
  [ "$status" -eq 0 ]

  echo '{"setting": "v2"}' > "$PROJECT_DIR/.claude/settings.json"
  run_cli save -m "Version 2"
  [ "$status" -eq 0 ]

  local profile_dir="$PROJECT_DIR/.claude-profiles/manual"
  local target_commit
  target_commit="$(git -C "$profile_dir" rev-parse HEAD~1)"

  run_cli new other
  [ "$status" -eq 0 ]

  echo '{"setting": "manual inactive edit"}' > "$profile_dir/.claude/settings.json"
  local dirty_before
  dirty_before="$(cat "$profile_dir/.claude/settings.json")"
  [ -n "$(git -C "$profile_dir" status --porcelain -- .claude/settings.json)" ]

  local fake_bin="$TEST_DIR/fake-bin"
  make_git_checkout_failure_fake "$fake_bin"
  export CPP_FAKE_GIT_CHECKOUT_FAILURE_MODE=target
  export PATH="$fake_bin:$PATH"

  run_cli restore manual "$target_commit"
  [ "$status" -ne 0 ]

  [ -f "$profile_dir/.claude/settings.json" ]
  [ "$(cat "$profile_dir/.claude/settings.json")" = "$dirty_before" ]
  [ -n "$(git -C "$profile_dir" status --porcelain -- .claude/settings.json)" ]
  assert_no_restore_tmp_dirs
}

@test "restore rollback leaves profile clean when rollback checkout fails" {
  run_cli fork rollback
  [ "$status" -eq 0 ]

  echo '{"setting": "v1"}' > "$PROJECT_DIR/.claude/settings.json"
  run_cli save -m "Version 1"
  [ "$status" -eq 0 ]

  echo '{"setting": "v2"}' > "$PROJECT_DIR/.claude/settings.json"
  run_cli save -m "Version 2"
  [ "$status" -eq 0 ]

  local profile_dir="$PROJECT_DIR/.claude-profiles/rollback"
  local target_commit
  target_commit="$(git -C "$profile_dir" rev-parse HEAD~1)"

  local settings_before
  settings_before="$(cat "$profile_dir/.claude/settings.json")"
  [ -z "$(git -C "$profile_dir" status --porcelain --untracked-files=all)" ]

  local fake_bin="$TEST_DIR/fake-bin"
  make_git_checkout_failure_fake "$fake_bin"
  export CPP_FAKE_GIT_CHECKOUT_FAILURE_MODE=all
  export PATH="$fake_bin:$PATH"

  run_cli restore rollback "$target_commit"
  [ "$status" -ne 0 ]

  [ -f "$profile_dir/.claude/settings.json" ]
  [ "$(cat "$profile_dir/.claude/settings.json")" = "$settings_before" ]
  [ -z "$(git -C "$profile_dir" status --porcelain --untracked-files=all)" ]
  assert_no_restore_tmp_dirs
}

@test "restore does not replace profile when restored tree cannot be committed" {
  run_cli fork verified
  [ "$status" -eq 0 ]

  echo '{"setting": "v1"}' > "$PROJECT_DIR/.claude/settings.json"
  run_cli save -m "Version 1"
  [ "$status" -eq 0 ]

  echo '{"setting": "v2"}' > "$PROJECT_DIR/.claude/settings.json"
  run_cli save -m "Version 2"
  [ "$status" -eq 0 ]

  run_cli new other
  [ "$status" -eq 0 ]

  local profile_dir="$PROJECT_DIR/.claude-profiles/verified"
  local target_commit
  target_commit="$(git -C "$profile_dir" rev-parse HEAD~1)"

  local settings_before head_before
  settings_before="$(cat "$profile_dir/.claude/settings.json")"
  head_before="$(git -C "$profile_dir" rev-parse HEAD)"
  [ -z "$(git -C "$profile_dir" status --porcelain --untracked-files=all)" ]

  local fake_bin="$TEST_DIR/fake-bin"
  make_restore_commit_failure_fake "$fake_bin"
  export PATH="$fake_bin:$PATH"

  run_cli restore verified "$target_commit"
  [ "$status" -ne 0 ]
  [[ "$output" == *"profile unchanged"* ]]

  [ -f "$profile_dir/.claude/settings.json" ]
  [ "$(cat "$profile_dir/.claude/settings.json")" = "$settings_before" ]
  [ "$(git -C "$profile_dir" rev-parse HEAD)" = "$head_before" ]
  [ -z "$(git -C "$profile_dir" status --porcelain --untracked-files=all)" ]
  assert_no_restore_tmp_dirs
}
