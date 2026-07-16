#!/usr/bin/env bash
# test-setup-hooks-registration.sh — setup hook 登録・移行の動作確認テスト

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DISTILL_SCRIPT="$SCRIPT_DIR/../setup/410-hooks-distill.sh"
QUEUE_SCRIPT="$SCRIPT_DIR/../setup/412-hooks-queue.sh"
PASS=0
FAIL=0
SKIP=0
FIXTURE_DIRS=()

cleanup_fixtures() {
  rm -rf -- "${FIXTURE_DIRS[@]}"
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
  mkdir -p "$FIXTURE_DIR/.claude/hooks"
  SETTINGS="$FIXTURE_DIR/.claude/settings.json"
}

write_settings() {
  printf '%s\n' "$1" >"$SETTINGS"
}

run_setup() {
  local module="$1"

  HOME="$FIXTURE_DIR" bash -c \
    'ok(){ :; }; fail(){ :; }; MISSING_CMDS=(); source "$1"' _ "$module" \
    >/dev/null 2>&1
}

hook_count() {
  local event="$1"
  local fragment="$2"

  if [ ! -f "$SETTINGS" ]; then
    printf '0\n'
    return 0
  fi

  jq --arg event "$event" --arg fragment "$fragment" '
    [.hooks[$event][]?.hooks[]? | (.command // "") | select(contains($fragment))] | length
  ' "$SETTINGS"
}

first_hook_command() {
  local event="$1"
  local fragment="$2"

  if [ ! -f "$SETTINGS" ]; then
    return 0
  fi

  jq -r --arg event "$event" --arg fragment "$fragment" '
    [.hooks[$event][]?.hooks[]? | (.command // "") | select(contains($fragment))] | .[0] // empty
  ' "$SETTINGS"
}

distill_command() {
  printf 'bash %s/.claude/hooks/knowledge-distill.sh 2>> %s/.claude/hooks/logs/knowledge-distill.log' \
    "$FIXTURE_DIR" "$FIXTURE_DIR"
}

queue_command() {
  printf 'bash %s/.claude/hooks/session-end-queue.sh 2>> %s/.claude/hooks/logs/session-end-queue.log' \
    "$FIXTURE_DIR" "$FIXTURE_DIR"
}

check_queue_command() {
  printf 'bash %s/.claude/hooks/check-queue.sh' "$FIXTURE_DIR"
}

shellcheck_pass() {
  shellcheck -S error "$SCRIPT_DIR/test-setup-hooks-registration.sh"
}

bash_syntax() {
  bash -n "$SCRIPT_DIR/test-setup-hooks-registration.sh"
}

distill_cleans_session_end() {
  create_fixture
  touch "$FIXTURE_DIR/.claude/hooks/knowledge-distill.sh"
  write_settings "$(cat <<EOF
{
  "hooks": {
    "SessionEnd": [
      {"matcher": "exit", "hooks": [{"type": "command", "command": "bash $FIXTURE_DIR/.claude/hooks/knowledge-distill.sh"}]}
    ]
  }
}
EOF
)"

  run_setup "$DISTILL_SCRIPT"
  [ "$(hook_count SessionEnd knowledge-distill.sh)" -eq 0 ]
}

distill_registers_session_start() {
  local expected
  create_fixture
  write_settings '{}'
  expected="$(distill_command)"

  run_setup "$DISTILL_SCRIPT"
  [ "$(hook_count SessionStart knowledge-distill.sh)" -eq 1 ] &&
    [ "$(first_hook_command SessionStart knowledge-distill.sh)" = "$expected" ]
}

distill_replaces_legacy_session_start_log() {
  local expected
  create_fixture
  write_settings "$(cat <<EOF
{
  "hooks": {
    "SessionStart": [
      {"hooks": [{"type": "command", "command": "bash $FIXTURE_DIR/.claude/hooks/knowledge-distill.sh 2>> $FIXTURE_DIR/.claude/hooks/knowledge-distill.log"}]}
    ]
  }
}
EOF
)"
  expected="$(distill_command)"

  run_setup "$DISTILL_SCRIPT"
  [ "$(hook_count SessionStart knowledge-distill.sh)" -eq 1 ] &&
    [ "$(first_hook_command SessionStart knowledge-distill.sh)" = "$expected" ]
}

distill_deduplicates_session_start() {
  local expected
  create_fixture
  write_settings "$(cat <<EOF
{
  "hooks": {
    "SessionStart": [
      {"matcher": "startup", "hooks": [{"type": "command", "command": "bash $FIXTURE_DIR/.claude/hooks/knowledge-distill.sh 2>> $FIXTURE_DIR/.claude/hooks/knowledge-distill.log"}]},
      {"matcher": "resume", "hooks": [{"type": "command", "command": "bash $FIXTURE_DIR/.claude/hooks/knowledge-distill.sh 2>> $FIXTURE_DIR/.claude/hooks/logs/knowledge-distill.log"}]}
    ]
  }
}
EOF
)"
  expected="$(distill_command)"

  run_setup "$DISTILL_SCRIPT"
  [ "$(hook_count SessionStart knowledge-distill.sh)" -eq 1 ] &&
    [ "$(first_hook_command SessionStart knowledge-distill.sh)" = "$expected" ]
}

queue_registers_session_end() {
  local expected
  create_fixture
  write_settings '{}'
  expected="$(queue_command)"

  run_setup "$QUEUE_SCRIPT"
  [ "$(hook_count SessionEnd session-end-queue.sh)" -eq 1 ] &&
    [ "$(first_hook_command SessionEnd session-end-queue.sh)" = "$expected" ]
}

distill_initializes_missing_settings() {
  local expected
  create_fixture
  expected="$(distill_command)"

  run_setup "$DISTILL_SCRIPT"
  [ -f "$SETTINGS" ] &&
    [ "$(hook_count SessionStart knowledge-distill.sh)" -eq 1 ] &&
    [ "$(first_hook_command SessionStart knowledge-distill.sh)" = "$expected" ]
}

queue_initializes_missing_settings() {
  local expected
  create_fixture
  expected="$(queue_command)"

  run_setup "$QUEUE_SCRIPT"
  [ -f "$SETTINGS" ] &&
    [ "$(hook_count SessionEnd session-end-queue.sh)" -eq 1 ] &&
    [ "$(first_hook_command SessionEnd session-end-queue.sh)" = "$expected" ]
}

distill_creates_logs_directory() {
  create_fixture
  write_settings '{}'

  run_setup "$DISTILL_SCRIPT"
  [ -d "$FIXTURE_DIR/.claude/hooks/logs" ]
}

distill_is_idempotent() {
  local expected
  local first_settings
  create_fixture
  first_settings="$FIXTURE_DIR/settings.after-first"
  write_settings '{}'
  expected="$(distill_command)"

  run_setup "$DISTILL_SCRIPT"
  cp "$SETTINGS" "$first_settings"
  run_setup "$DISTILL_SCRIPT"
  diff -u "$first_settings" "$SETTINGS" &&
    [ "$(hook_count SessionStart knowledge-distill.sh)" -eq 1 ] &&
    [ "$(first_hook_command SessionStart knowledge-distill.sh)" = "$expected" ]
}

queue_is_idempotent() {
  local expected
  local first_settings
  create_fixture
  first_settings="$FIXTURE_DIR/settings.after-first"
  write_settings '{}'
  expected="$(queue_command)"

  run_setup "$QUEUE_SCRIPT"
  cp "$SETTINGS" "$first_settings"
  run_setup "$QUEUE_SCRIPT"
  diff -u "$first_settings" "$SETTINGS" &&
    [ "$(hook_count SessionEnd session-end-queue.sh)" -eq 1 ] &&
    [ "$(first_hook_command SessionEnd session-end-queue.sh)" = "$expected" ]
}

distill_preserves_unrelated_session_end_hook() {
  local unrelated
  create_fixture
  unrelated="bash $FIXTURE_DIR/.claude/hooks/unrelated.sh"
  write_settings "$(cat <<EOF
{
  "hooks": {
    "SessionEnd": [
      {
        "matcher": "exit",
        "metadata": "keep",
        "hooks": [
          {"type": "command", "command": "bash $FIXTURE_DIR/.claude/hooks/knowledge-distill.sh"},
          {"type": "command", "command": "$unrelated"}
        ]
      },
      {
        "matcher": "legacy-only",
        "hooks": [{"type": "command", "command": "bash $FIXTURE_DIR/.claude/hooks/knowledge-distill.sh"}]
      }
    ]
  }
}
EOF
)"

  run_setup "$DISTILL_SCRIPT"
  jq -e --arg unrelated "$unrelated" '
    ([.hooks.SessionEnd[]? | select(.matcher == "exit")] | length == 1) and
    ([.hooks.SessionEnd[]? | select(.matcher == "exit") | .metadata] | .[0] == "keep") and
    ([.hooks.SessionEnd[]? | select(.matcher == "exit") | .hooks[]?.command] == [$unrelated]) and
    ([.hooks.SessionEnd[]? | select((.hooks // []) | length == 0)] | length == 0) and
    ([.hooks.SessionEnd[]?.hooks[]?.command // empty | select(contains("knowledge-distill.sh"))] | length == 0)
  ' "$SETTINGS" >/dev/null
}

distill_cleans_without_hook_file() {
  create_fixture
  write_settings "$(cat <<EOF
{
  "hooks": {
    "SessionEnd": [
      {"hooks": [{"type": "command", "command": "bash $FIXTURE_DIR/.claude/hooks/knowledge-distill.sh"}]}
    ]
  }
}
EOF
)"

  [ ! -e "$FIXTURE_DIR/.claude/hooks/knowledge-distill.sh" ]
  run_setup "$DISTILL_SCRIPT"
  [ "$(hook_count SessionEnd knowledge-distill.sh)" -eq 0 ]
}

distill_registers_lessons_learned() {
  local expected
  create_fixture
  printf '%s\n' '# fixture hook' >"$FIXTURE_DIR/.claude/hooks/lessons-learned-distill.sh"
  expected="bash $FIXTURE_DIR/.claude/hooks/lessons-learned-distill.sh 2>> $FIXTURE_DIR/.claude/hooks/logs/lessons-learned-distill.log"

  run_setup "$DISTILL_SCRIPT"
  [ "$(hook_count SessionEnd lessons-learned-distill.sh)" -eq 1 ] &&
    [ "$(first_hook_command SessionEnd lessons-learned-distill.sh)" = "$expected" ]
}

queue_preserves_check_queue_registration() {
  local expected
  create_fixture
  printf '%s\n' '# fixture hook' >"$FIXTURE_DIR/.claude/hooks/check-queue.sh"
  write_settings '{"hooks":{"UserPromptSubmit":[]}}'
  expected="$(check_queue_command)"

  run_setup "$QUEUE_SCRIPT"
  [ "$(hook_count UserPromptSubmit check-queue.sh)" -eq 1 ] &&
    [ "$(first_hook_command UserPromptSubmit check-queue.sh)" = "$expected" ]
}

if command -v shellcheck >/dev/null 2>&1; then
  run_test "shellcheck -S error が通る" shellcheck_pass
else
  echo "SKIP: shellcheck -S error が通る (shellcheck not installed)"
  ((SKIP++)) || true
fi
run_test "bash -n が通る" bash_syntax

if command -v jq >/dev/null 2>&1; then
  run_test "410 実行後に SessionEnd の knowledge-distill を除去" distill_cleans_session_end
  run_test "410 実行後に SessionStart へ正規コマンドを 1 件だけ登録" distill_registers_session_start
  run_test "古い knowledge-distill ログパスを正規コマンドへ置換" distill_replaces_legacy_session_start_log
  run_test "重複した SessionStart の knowledge-distill を 1 件へ収束" distill_deduplicates_session_start
  run_test "412 実行後に SessionEnd の session-end-queue を 1 件登録" queue_registers_session_end
  run_test "settings.json 不存在でも 410 が初期化から登録まで完走" distill_initializes_missing_settings
  run_test "settings.json 不存在でも 412 が初期化から登録まで完走" queue_initializes_missing_settings
  run_test "410 実行後に hooks/logs を作成" distill_creates_logs_directory
  run_test "410 を 2 回実行しても settings.json が同一" distill_is_idempotent
  run_test "412 を 2 回実行しても settings.json が同一" queue_is_idempotent
  run_test "SessionEnd の無関係 hook と matcher を保持" distill_preserves_unrelated_session_end_hook
  run_test "knowledge-distill.sh 不在でも SessionEnd cleanup を実行" distill_cleans_without_hook_file
  run_test "lessons-learned-distill の SessionEnd 登録を維持" distill_registers_lessons_learned
  run_test "既存の check-queue UserPromptSubmit 登録を維持" queue_preserves_check_queue_registration
else
  echo "SKIP: hook 登録テスト (jq not installed)"
  ((SKIP++)) || true
fi

echo ""
echo "Results: ${PASS} PASS / ${FAIL} FAIL / ${SKIP} SKIP"

if [ "$FAIL" -gt 0 ]; then
  exit 1
fi
