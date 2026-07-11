#!/usr/bin/env bash
# test-sync-check.sh — sync-check.sh の動作確認テスト

set -euo pipefail

SCRIPT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/sync-check.sh"
PASS=0
FAIL=0
SKIP=0
FIXTURE_DIRS=()

cleanup_fixtures() {
  rm -rf "${FIXTURE_DIRS[@]}"
}

trap cleanup_fixtures EXIT

run_test() {
  local desc="$1"
  local test_function="$2"

  if "$test_function"; then
    echo "PASS: $desc"
    ((PASS++)) || true
  else
    echo "FAIL: $desc"
    ((FAIL++)) || true
  fi
}

create_fixture() {
  FIXTURE_DIR="$(mktemp -d)"
  FIXTURE_DIRS+=("$FIXTURE_DIR")
  mkdir -p "$FIXTURE_DIR/live" "$FIXTURE_DIR/repo/scripts"
}

write_whitelist() {
  cat >"$FIXTURE_DIR/repo/scripts/sync-whitelist.conf" <<'EOF'
+ /skills/***
+ /agents/***
+ /CLAUDE.md
- /***
EOF
}

write_known_deletions() {
  cat >"$FIXTURE_DIR/repo/scripts/sync-known-deletions.conf" <<'EOF'
agents/leliel.md
EOF
}

run_sync_check() {
  local output_var="$1"
  local status_var="$2"
  local result_output
  local result_status

  if result_output=$(bash "$SCRIPT" "$FIXTURE_DIR/live" "$FIXTURE_DIR/repo" 2>&1); then
    result_status=0
  else
    result_status=$?
  fi

  printf -v "$output_var" '%s' "$result_output"
  printf -v "$status_var" '%s' "$result_status"
}

shellcheck_pass() {
  shellcheck -S error "$SCRIPT"
}

bash_syntax() {
  bash -n "$SCRIPT"
}

new_only_live() {
  local output status
  create_fixture
  write_whitelist
  write_known_deletions
  mkdir -p "$FIXTURE_DIR/live/skills/code-review"
  printf '%s\n' '---' >"$FIXTURE_DIR/live/skills/code-review/SKILL.md"

  run_sync_check output status
  [ "$status" -eq 1 ] && [[ "$output" == *"要還流（新規）"* ]]
}

changed_both() {
  local output status
  create_fixture
  write_whitelist
  write_known_deletions
  printf '%s\n' 'live' >"$FIXTURE_DIR/live/CLAUDE.md"
  printf '%s\n' 'repo' >"$FIXTURE_DIR/repo/CLAUDE.md"

  run_sync_check output status
  [ "$status" -eq 1 ] && [[ "$output" == *"要還流（変更）"* ]]
}

known_deletion() {
  local output status
  create_fixture
  write_whitelist
  write_known_deletions
  mkdir -p "$FIXTURE_DIR/live/agents"
  printf '%s\n' 'known deletion' >"$FIXTURE_DIR/live/agents/leliel.md"

  run_sync_check output status
  [ "$status" -eq 0 ] && [[ "$output" == *"削除予定（既知）"* ]] &&
    [[ "$output" != *"要還流"* ]]
}

verbose_same() {
  local default_output default_status verbose_output verbose_status
  create_fixture
  write_whitelist
  write_known_deletions
  printf '%s\n' 'same' >"$FIXTURE_DIR/live/CLAUDE.md"
  printf '%s\n' 'same' >"$FIXTURE_DIR/repo/CLAUDE.md"

  run_sync_check default_output default_status
  if verbose_output=$(bash "$SCRIPT" --verbose "$FIXTURE_DIR/live" "$FIXTURE_DIR/repo" 2>&1); then
    verbose_status=0
  else
    verbose_status=$?
  fi

  [ "$default_status" -eq 0 ] && [ "$verbose_status" -eq 0 ] &&
    [[ "$default_output" != *"同一"* ]] && [[ "$verbose_output" == *"同一"* ]]
}

exclude_settings() {
  local output status
  create_fixture
  write_whitelist
  write_known_deletions
  printf '%s\n' '{}' >"$FIXTURE_DIR/live/settings.json"
  printf '%s\n' 'local only' >"$FIXTURE_DIR/live/CLAUDE.local.md"

  run_sync_check output status
  [ "$status" -eq 0 ] && [[ "$output" != *"settings.json"* ]] &&
    [[ "$output" != *"CLAUDE.local.md"* ]]
}

missing_whitelist() {
  local output status
  create_fixture
  write_known_deletions

  run_sync_check output status
  [ "$status" -eq 2 ]
}

missing_live_path() {
  local output status
  create_fixture
  write_whitelist
  write_known_deletions

  if output=$(bash "$SCRIPT" "$FIXTURE_DIR/missing-live" "$FIXTURE_DIR/repo" 2>&1); then
    status=0
  else
    status=$?
  fi

  [ "$status" -eq 2 ]
}

missing_known_deletions() {
  local output status
  create_fixture
  write_whitelist
  printf '%s\n' 'same' >"$FIXTURE_DIR/live/CLAUDE.md"
  printf '%s\n' 'same' >"$FIXTURE_DIR/repo/CLAUDE.md"

  run_sync_check output status
  [ "$status" -eq 0 ]
}

if command -v shellcheck >/dev/null 2>&1; then
  run_test "shellcheck -S error が通る" shellcheck_pass
else
  echo "SKIP: shellcheck -S error が通る (shellcheck not installed)"
  ((SKIP++)) || true
fi
run_test "bash -n が通る" bash_syntax
run_test "実働環境のみにあるファイルを新規として検出" new_only_live
run_test "両側で異なるファイルを変更として検出" changed_both
run_test "既知削除予定を通常の還流対象から除外" known_deletion
run_test "同一ファイルは --verbose 時だけ表示" verbose_same
run_test "settings.json と CLAUDE.local.md を除外" exclude_settings
run_test "whitelist がない場合は exit 2" missing_whitelist
run_test "実働環境パスがない場合は exit 2" missing_live_path
run_test "known-deletions がなくても正常終了" missing_known_deletions

echo ""
echo "Results: ${PASS} PASS / ${FAIL} FAIL / ${SKIP} SKIP"

if [ "$FAIL" -gt 0 ]; then
  exit 1
fi
