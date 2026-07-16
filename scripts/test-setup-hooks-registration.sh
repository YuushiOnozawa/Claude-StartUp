#!/usr/bin/env bash
# test-setup-hooks-registration.sh — setup hook 登録・移行の動作確認テスト

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DISTILL_SCRIPT="$SCRIPT_DIR/../setup/410-hooks-distill.sh"
AUTO_SCRIPT="$SCRIPT_DIR/../setup/411-hooks-auto.sh"
QUEUE_SCRIPT="$SCRIPT_DIR/../setup/412-hooks-queue.sh"
ERROR_DETECTOR_SCRIPT="$SCRIPT_DIR/../setup/413-hooks-error-detector.sh"
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

run_setup_capture() {
  local module="$1"

  SETUP_OUTPUT="$FIXTURE_DIR/setup-output"
  HOME="$FIXTURE_DIR" bash -c \
    'ok(){ :; }; fail(){ printf "✗ %s\n" "$*"; }; MISSING_CMDS=(); source "$1"; printf "MISSING_CMDS=%s\n" "${MISSING_CMDS[*]}"' _ "$module" \
    >"$SETUP_OUTPUT" 2>&1
}

hook_count() {
  local event="$1"
  local fragment="$2"

  if [ ! -f "$SETTINGS" ]; then
    printf '0\n'
    return 0
  fi

  jq --arg event "$event" --arg fragment "$fragment" '
    [.hooks[$event][]?.hooks[]? | (.command? // empty) | select(type == "string") | select(contains($fragment))] | length
  ' "$SETTINGS"
}

first_hook_command() {
  local event="$1"
  local fragment="$2"

  if [ ! -f "$SETTINGS" ]; then
    return 0
  fi

  jq -r --arg event "$event" --arg fragment "$fragment" '
    [.hooks[$event][]?.hooks[]? | (.command? // empty) | select(type == "string") | select(contains($fragment))] | .[0] // empty
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

error_detector_command() {
  printf 'bash %s/.claude/hooks/error-detector.sh' "$FIXTURE_DIR"
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

distill_deduplicates_canonical_session_start() {
  local expected
  create_fixture
  expected="$(distill_command)"
  write_settings "$(cat <<EOF
{
  "hooks": {
    "SessionStart": [
      {"matcher": "startup", "hooks": [{"type": "command", "command": "$expected"}]},
      {"matcher": "resume", "hooks": [{"type": "command", "command": "$expected"}]}
    ]
  }
}
EOF
)"

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

queue_deduplicates_session_end() {
  local expected
  create_fixture
  expected="$(queue_command)"
  write_settings "$(cat <<EOF
{
  "hooks": {
    "SessionEnd": [
      {"matcher": "exit", "hooks": [{"type": "command", "command": "$expected"}]},
      {"matcher": "shutdown", "hooks": [{"type": "command", "command": "$expected"}]}
    ]
  }
}
EOF
)"

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

distill_skips_dangling_settings_symlink() {
  local symlink_target
  create_fixture
  symlink_target=/nonexistent-target
  ln -s "$symlink_target" "$SETTINGS"

  run_setup "$DISTILL_SCRIPT"
  [ -L "$SETTINGS" ] &&
    [ "$(readlink "$SETTINGS")" = "$symlink_target" ] &&
    [ ! -e "$symlink_target" ]
}

distill_rejects_non_string_session_end_command() {
  local before_settings
  create_fixture
  write_settings "$(cat <<'EOF'
{
  "hooks": {
    "SessionEnd": [
      {"hooks": [{"type": "command", "command": 123}]}
    ]
  }
}
EOF
)"
  before_settings="$FIXTURE_DIR/settings.before"
  cp "$SETTINGS" "$before_settings"

  run_setup "$DISTILL_SCRIPT"
  diff -u "$before_settings" "$SETTINGS"
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

error_detector_registers_post_tool_use() {
  local expected
  create_fixture
  write_settings '{}'
  expected="$(error_detector_command)"

  run_setup "$ERROR_DETECTOR_SCRIPT"
  [ "$(hook_count PostToolUse error-detector.sh)" -eq 1 ] &&
    [ "$(first_hook_command PostToolUse error-detector.sh)" = "$expected" ] &&
    jq -e '([.hooks.PostToolUse[]? | select((.hooks // []) | length == 0)] | length == 0)' "$SETTINGS" >/dev/null
}

error_detector_replaces_legacy_post_tool_use() {
  local expected
  create_fixture
  expected="$(error_detector_command)"
  write_settings "$(cat <<EOF
{
  "hooks": {
    "PostToolUse": [
      {"hooks": [{"type": "command", "command": "[ -f $FIXTURE_DIR/.claude/hooks/error-detector.sh ] && bash $FIXTURE_DIR/.claude/hooks/error-detector.sh || true"}]}
    ]
  }
}
EOF
)"

  run_setup "$ERROR_DETECTOR_SCRIPT"
  [ "$(hook_count PostToolUse error-detector.sh)" -eq 1 ] &&
    [ "$(first_hook_command PostToolUse error-detector.sh)" = "$expected" ] &&
    jq -e '([.hooks.PostToolUse[]? | select((.hooks // []) | length == 0)] | length == 0)' "$SETTINGS" >/dev/null
}

error_detector_deduplicates_post_tool_use() {
  local expected
  create_fixture
  expected="$(error_detector_command)"
  write_settings "$(cat <<EOF
{
  "hooks": {
    "PostToolUse": [
      {"matcher": "Bash", "hooks": [{"type": "command", "command": "$expected"}]},
      {"matcher": "Write", "hooks": [{"type": "command", "command": "$expected"}]}
    ]
  }
}
EOF
)"

  run_setup "$ERROR_DETECTOR_SCRIPT"
  [ "$(hook_count PostToolUse error-detector.sh)" -eq 1 ] &&
    [ "$(first_hook_command PostToolUse error-detector.sh)" = "$expected" ] &&
    jq -e '([.hooks.PostToolUse[]? | select((.hooks // []) | length == 0)] | length == 0)' "$SETTINGS" >/dev/null
}

error_detector_initializes_missing_settings() {
  local expected
  create_fixture
  expected="$(error_detector_command)"

  run_setup "$ERROR_DETECTOR_SCRIPT"
  [ -f "$SETTINGS" ] &&
    [ "$(hook_count PostToolUse error-detector.sh)" -eq 1 ] &&
    [ "$(first_hook_command PostToolUse error-detector.sh)" = "$expected" ]
}

error_detector_copies_executable_hook() {
  local deployed
  create_fixture

  run_setup "$ERROR_DETECTOR_SCRIPT"
  deployed="$FIXTURE_DIR/.claude/hooks/error-detector.sh"
  [ -f "$deployed" ] &&
    [ ! -L "$deployed" ] &&
    [ -x "$deployed" ] &&
    cmp -s "$SCRIPT_DIR/../hooks/error-detector.sh" "$deployed"
}

error_detector_registers_when_hook_is_already_deployed() {
  local expected
  local deployed
  create_fixture
  write_settings '{}'
  expected="$(error_detector_command)"
  deployed="$FIXTURE_DIR/.claude/hooks/error-detector.sh"
  ln -s "$SCRIPT_DIR/../hooks/error-detector.sh" "$deployed"

  run_setup "$ERROR_DETECTOR_SCRIPT"
  [ "$(hook_count PostToolUse error-detector.sh)" -eq 1 ] &&
    [ "$(first_hook_command PostToolUse error-detector.sh)" = "$expected" ]
}

error_detector_is_idempotent() {
  local first_settings
  create_fixture
  first_settings="$FIXTURE_DIR/settings.after-first"
  write_settings '{}'

  run_setup "$ERROR_DETECTOR_SCRIPT"
  cp "$SETTINGS" "$first_settings"
  run_setup "$ERROR_DETECTOR_SCRIPT"
  diff -u "$first_settings" "$SETTINGS" &&
    [ "$(hook_count PostToolUse error-detector.sh)" -eq 1 ]
}

error_detector_preserves_unrelated_hook_and_matcher() {
  local expected
  local unrelated
  create_fixture
  expected="$(error_detector_command)"
  unrelated="bash $FIXTURE_DIR/.claude/hooks/unrelated.sh"
  write_settings "$(cat <<EOF
{
  "hooks": {
    "PostToolUse": [
      {
        "matcher": "Bash",
        "metadata": "keep",
        "hooks": [
          {"type": "command", "command": "[ -f $FIXTURE_DIR/.claude/hooks/error-detector.sh ] && bash $FIXTURE_DIR/.claude/hooks/error-detector.sh || true"},
          {"type": "command", "command": "$unrelated"}
        ]
      }
    ]
  }
}
EOF
)"

  run_setup "$ERROR_DETECTOR_SCRIPT"
  jq -e --arg expected "$expected" --arg unrelated "$unrelated" '
    ([.hooks.PostToolUse[]? | select(.matcher == "Bash" and .metadata == "keep")] | length == 1) and
    ([.hooks.PostToolUse[]?.hooks[]?.command // empty | select(. == $unrelated)] | length == 1) and
    ([.hooks.PostToolUse[]?.hooks[]?.command // empty | select(type == "string") | select(. == $expected)] | length == 1) and
    ([.hooks.PostToolUse[]?.hooks[]? | select((.command? // empty) | type == "string") | select(.command | contains("error-detector.sh"))] | length == 1)
  ' "$SETTINGS" >/dev/null
}

error_detector_skips_dangling_settings_symlink() {
  local symlink_target
  create_fixture
  symlink_target="$FIXTURE_DIR/missing-settings-target"
  ln -s "$symlink_target" "$SETTINGS"

  run_setup_capture "$ERROR_DETECTOR_SCRIPT"
  grep -Fq '✗' "$SETUP_OUTPUT" &&
    [ -L "$SETTINGS" ] &&
    [ "$(readlink "$SETTINGS")" = "$symlink_target" ] &&
    [ ! -e "$symlink_target" ]
}

error_detector_fails_when_source_is_missing() {
  local module_dir
  local module
  create_fixture
  write_settings '{}'

  [ -f "$ERROR_DETECTOR_SCRIPT" ] || return 1
  module_dir="$FIXTURE_DIR/module"
  module="$module_dir/413-hooks-error-detector.sh"
  mkdir -p "$module_dir"
  cp "$ERROR_DETECTOR_SCRIPT" "$module"

  run_setup_capture "$module"
  grep -Fq '✗' "$SETUP_OUTPUT" &&
    grep -Eq '^MISSING_CMDS=.+$' "$SETUP_OUTPUT" &&
    [ "$(hook_count PostToolUse error-detector.sh)" -eq 0 ] &&
    [ ! -e "$FIXTURE_DIR/.claude/hooks/error-detector.sh" ]
}

error_detector_preserves_non_string_command() {
  local expected
  create_fixture
  expected="$(error_detector_command)"
  write_settings "$(cat <<EOF
{
  "hooks": {
    "PostToolUse": [
      {
        "matcher": "Bash",
        "hooks": [
          {"type": "command", "command": 123},
          {"type": "command", "command": "bash $FIXTURE_DIR/.claude/hooks/unrelated.sh"}
        ]
      }
    ]
  }
}
EOF
)"

  run_setup "$ERROR_DETECTOR_SCRIPT"
  jq -e --arg expected "$expected" '
    ([.hooks.PostToolUse[]?.hooks[]? | select(.command == 123)] | length == 1) and
    ([.hooks.PostToolUse[]?.hooks[]?.command // empty | select(type == "string") | select(. == $expected)] | length == 1)
  ' "$SETTINGS" >/dev/null
}

all_setup_hooks_register_in_sequence() {
  create_fixture
  printf '%s\n' '# fixture hook' > "$FIXTURE_DIR/.claude/hooks/check-queue.sh"
  write_settings '{}'

  run_setup "$DISTILL_SCRIPT"
  run_setup "$AUTO_SCRIPT"
  run_setup "$QUEUE_SCRIPT"
  run_setup "$ERROR_DETECTOR_SCRIPT"

  [ "$(hook_count SessionStart knowledge-distill.sh)" -eq 1 ] &&
    [ "$(hook_count SessionEnd session-end-queue.sh)" -eq 1 ] &&
    [ "$(hook_count UserPromptSubmit check-queue.sh)" -eq 1 ] &&
    [ "$(hook_count PostToolUse error-detector.sh)" -eq 1 ]
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
  run_test "重複した正規 SessionStart コマンドを 1 件へ収束" distill_deduplicates_canonical_session_start
  run_test "412 実行後に SessionEnd の session-end-queue を 1 件登録" queue_registers_session_end
  run_test "重複した SessionEnd の session-end-queue を 1 件へ収束" queue_deduplicates_session_end
  run_test "settings.json 不存在でも 410 が初期化から登録まで完走" distill_initializes_missing_settings
  run_test "settings.json 不存在でも 412 が初期化から登録まで完走" queue_initializes_missing_settings
  run_test "410 実行後に hooks/logs を作成" distill_creates_logs_directory
  run_test "410 を 2 回実行しても settings.json が同一" distill_is_idempotent
  run_test "412 を 2 回実行しても settings.json が同一" queue_is_idempotent
  run_test "410 は dangling symlink の settings.json を置換しない" distill_skips_dangling_settings_symlink
  run_test "410 は非文字列 command で settings.json を変更しない" distill_rejects_non_string_session_end_command
  run_test "SessionEnd の無関係 hook と matcher を保持" distill_preserves_unrelated_session_end_hook
  run_test "knowledge-distill.sh 不在でも SessionEnd cleanup を実行" distill_cleans_without_hook_file
  run_test "lessons-learned-distill の SessionEnd 登録を維持" distill_registers_lessons_learned
  run_test "既存の check-queue UserPromptSubmit 登録を維持" queue_preserves_check_queue_registration
  run_test "413 実行後に PostToolUse へ error-detector を正規コマンドで 1 件だけ登録" error_detector_registers_post_tool_use
  run_test "旧形式の PostToolUse error-detector 登録を正規コマンドへ置換" error_detector_replaces_legacy_post_tool_use
  run_test "重複した PostToolUse の error-detector を 1 件へ収束" error_detector_deduplicates_post_tool_use
  run_test "settings.json 不存在でも 413 が初期化から登録まで完走" error_detector_initializes_missing_settings
  run_test "error-detector.sh を配置して実行権限を付与" error_detector_copies_executable_hook
  run_test "error-detector.sh 配置済みでも PostToolUse 登録を実行" error_detector_registers_when_hook_is_already_deployed
  run_test "413 を 2 回実行しても settings.json が同一" error_detector_is_idempotent
  run_test "PostToolUse の無関係 hook と matcher を保持" error_detector_preserves_unrelated_hook_and_matcher
  run_test "413 は dangling symlink の settings.json を置換しない" error_detector_skips_dangling_settings_symlink
  run_test "コピー元不在時は fail と MISSING_CMDS を出して登録しない" error_detector_fails_when_source_is_missing
  run_test "PostToolUse の非文字列 command を保持して登録" error_detector_preserves_non_string_command
  run_test "410 → 411 → 412 → 413 の hook 登録を同一 fixture で成立" all_setup_hooks_register_in_sequence
else
  echo "SKIP: hook 登録テスト (jq not installed)"
  ((SKIP++)) || true
fi

echo ""
echo "Results: ${PASS} PASS / ${FAIL} FAIL / ${SKIP} SKIP"

if [ "$FAIL" -gt 0 ]; then
  exit 1
fi
