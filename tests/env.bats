#!/usr/bin/env bats

load test_helper

@test "fails gracefully outside git repo" {
  local nogit_dir="$TEST_DIR/nogit"
  mkdir -p "$nogit_dir"

  cd "$nogit_dir"
  run "$CLI" list
  [ "$status" -ne 0 ]
  [[ "$output" == *"git repository"* ]]
}
