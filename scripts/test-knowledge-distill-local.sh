#!/usr/bin/env bash
# test-knowledge-distill-local.sh — knowledge-distill.sh のローカル保存・キュー動作テスト

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TEST_SCRIPT="$SCRIPT_DIR/test-knowledge-distill-local.sh"
HOOK_SCRIPT="$SCRIPT_DIR/../hooks/knowledge-distill.sh"
PASS=0
FAIL=0
SKIP=0
FIXTURE_DIRS=()
SERVER_PIDS=()
TEST_SKIP_REASON=""

cleanup() {
  local pid

  for pid in "${SERVER_PIDS[@]}"; do
    kill "$pid" 2>/dev/null || true
    wait "$pid" 2>/dev/null || true
  done

  if ((${#FIXTURE_DIRS[@]} > 0)); then
    rm -rf -- "${FIXTURE_DIRS[@]}"
  fi
}

trap cleanup EXIT

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

run_test_or_skip() {
  local desc="$1"
  local test_function="$2"
  local status=0

  if "$test_function"; then
    echo "PASS: $desc"
    ((PASS++)) || true
  else
    status=$?
    if [ "$status" -eq 2 ] && [ -n "$TEST_SKIP_REASON" ]; then
      skip_test "$desc" "$TEST_SKIP_REASON"
    else
      echo "FAIL: $desc"
      ((FAIL++)) || true
    fi
  fi
}

skip_test() {
  local desc="$1"
  local reason="$2"

  echo "SKIP: $desc ($reason)"
  ((SKIP++)) || true
}

create_fixture() {
  FIXTURE_DIR="$(mktemp -d)"
  FIXTURE_DIRS+=("$FIXTURE_DIR")
  mkdir -p "$FIXTURE_DIR/.claude/hooks"
}

make_transcript() {
  TRANSCRIPT_PATH="$(mktemp "$FIXTURE_DIR/transcript.XXXXXX.jsonl")"
  printf '%s\n' '{"role":"user","content":"テスト"}' >"$TRANSCRIPT_PATH"
}

make_empty_transcript() {
  TRANSCRIPT_PATH="$(mktemp "$FIXTURE_DIR/transcript-empty.XXXXXX.jsonl")"
  printf '%s\n' '{"role":"user","content":""}' >"$TRANSCRIPT_PATH"
}

session_input() {
  jq -cn \
    --arg transcript_path "$TRANSCRIPT_PATH" \
    --arg cwd "$FIXTURE_DIR/project" \
    '{transcript_path:$transcript_path,cwd:$cwd}'
}

run_hook() {
  local output_var="$1"
  local status_var="$2"
  local input="$3"
  local ollama_url="${4:-http://127.0.0.1:9}"
  local result_output
  local result_status

  if result_output=$(HOME="$FIXTURE_DIR" \
    OLLAMA_BASE_URL="$ollama_url" \
    KRAG_DISTILL_RETRY=0 \
    bash "$HOOK_SCRIPT" <<<"$input" 2>&1); then
    result_status=0
  else
    result_status=$?
  fi

  printf -v "$output_var" '%s' "$result_output"
  printf -v "$status_var" '%s' "$result_status"
}

write_queue_item() {
  local filename="$1"
  local reason="$2"
  local retry_count="$3"
  local transcript_path="$4"
  local queue_dir="$FIXTURE_DIR/.claude/hooks/queue/knowledge-distill"

  mkdir -p "$queue_dir"
  jq -n \
    --arg transcript_path "$transcript_path" \
    --arg cwd "$FIXTURE_DIR/project" \
    --arg reason "$reason" \
    --argjson retry_count "$retry_count" \
    '{transcript_path:$transcript_path,cwd:$cwd,reason:$reason,retry_count:$retry_count}' \
    >"$queue_dir/$filename"
}

queue_item_path() {
  printf '%s/.claude/hooks/queue/knowledge-distill/%s\n' "$FIXTURE_DIR" "$1"
}

queue_reason_count() {
  local expected_reason="$1"
  local queue_dir="$FIXTURE_DIR/.claude/hooks/queue/knowledge-distill"
  local count=0
  local item

  [[ -d "$queue_dir" ]] || { printf '0\n'; return 0; }

  for item in "$queue_dir"/*.json; do
    [[ -f "$item" ]] || continue
    if [[ "$(jq -r '.reason // empty' "$item")" == "$expected_reason" ]]; then
      ((count++)) || true
    fi
  done
  printf '%s\n' "$count"
}

json_file_count() {
  local directory="$1"

  [[ -d "$directory" ]] || { printf '0\n'; return 0; }
  find "$directory" -maxdepth 1 -type f -name '*.json' -print | wc -l
}

raw_file_count() {
  local raw_dir="$FIXTURE_DIR/.local/share/knowledge-rag/sessions/raw"

  [[ -d "$raw_dir" ]] || { printf '0\n'; return 0; }
  find "$raw_dir" -maxdepth 1 -type f -name '*.md' -print | wc -l
}

start_dummy_ollama() {
  local url_var="$1"
  local port_file="$FIXTURE_DIR/ollama-port"
  local server_log="$FIXTURE_DIR/ollama-server.log"
  local pid
  local port=""
  local attempt

  python3 -c 'import http.server, socketserver; Handler=type("Handler",(http.server.BaseHTTPRequestHandler,),{"do_GET":lambda self: (self.send_response(200), self.end_headers(), self.wfile.write(b"{}")) if self.path == "/api/tags" else (self.send_response(404), self.end_headers()),"log_message":lambda *args: None}); server=socketserver.TCPServer(("127.0.0.1", 0), Handler); print(server.server_address[1], flush=True); server.serve_forever()' \
    >"$port_file" 2>"$server_log" &
  pid=$!
  SERVER_PIDS+=("$pid")

  for ((attempt = 0; attempt < 50; attempt += 1)); do
    if [[ -s "$port_file" ]]; then
      port="$(<"$port_file")"
      break
    fi
    if ! kill -0 "$pid" 2>/dev/null; then
      TEST_SKIP_REASON="dummy HTTP server could not start"
      return 2
    fi
    sleep 0.1
  done

  if ! [[ "$port" =~ ^[0-9]+$ ]]; then
    TEST_SKIP_REASON="dummy HTTP server did not expose a port"
    return 2
  fi
  printf -v "$url_var" 'http://127.0.0.1:%s' "$port"
}

shellcheck_pass() {
  shellcheck -S error "$TEST_SCRIPT" "$HOOK_SCRIPT"
}

bash_syntax() {
  bash -n "$TEST_SCRIPT" "$HOOK_SCRIPT"
}

session_end_queues_ollama_and_writes_raw() {
  local output
  local status

  create_fixture
  make_transcript
  run_hook output status "$(session_input)"

  [ "$status" -eq 0 ] &&
    [ "$(raw_file_count)" -eq 1 ] &&
    [ "$(queue_reason_count ollama)" -eq 1 ]
}

session_end_does_not_create_pcloud_or_pcloud_queue_item() {
  local output
  local status

  create_fixture
  make_transcript
  run_hook output status "$(session_input)"

  [ "$status" -eq 0 ] &&
    [ ! -e "$FIXTURE_DIR/pcloud" ] &&
    [ "$(queue_reason_count pcloud)" -eq 0 ]
}

pcloud_queue_item_migrates_to_pending_while_ollama_is_down() {
  local output
  local status
  local item

  create_fixture
  make_transcript
  write_queue_item legacy.json pcloud 0 "$TRANSCRIPT_PATH"
  item="$(queue_item_path legacy.json)"
  run_hook output status '{}'

  [ "$status" -eq 0 ] &&
    [ -f "$item" ] &&
    [ "$(jq -r '.reason' "$item")" = pending ]
}

pending_queue_is_not_drained_while_ollama_is_down() {
  local output
  local status
  local item

  create_fixture
  make_transcript
  write_queue_item pending.json pending 0 "$TRANSCRIPT_PATH"
  item="$(queue_item_path pending.json)"
  run_hook output status '{}'

  [ "$status" -eq 0 ] &&
    [ -f "$item" ] &&
    [ "$(jq -r '.retry_count' "$item")" -eq 0 ]
}

ollama_queue_is_not_drained_while_ollama_is_down() {
  local output
  local status
  local item

  create_fixture
  make_transcript
  write_queue_item ollama.json ollama 0 "$TRANSCRIPT_PATH"
  item="$(queue_item_path ollama.json)"
  run_hook output status '{}'

  [ "$status" -eq 0 ] &&
    [ -f "$item" ] &&
    [ "$(jq -r '.retry_count' "$item")" -eq 0 ]
}

pending_queue_is_not_dead_lettered_after_four_stopped_runs() {
  local output
  local status
  local item
  local attempt
  local dead_letter_dir

  create_fixture
  make_transcript
  write_queue_item pending.json pending 0 "$TRANSCRIPT_PATH"
  item="$(queue_item_path pending.json)"

  for ((attempt = 1; attempt <= 4; attempt += 1)); do
    run_hook output status '{}'
    [ "$status" -eq 0 ] || return 1
  done

  dead_letter_dir="$FIXTURE_DIR/.claude/hooks/queue/dead-letter/knowledge-distill"
  [ -f "$item" ] &&
    [ "$(jq -r '.retry_count' "$item")" -eq 0 ] &&
    [ "$(json_file_count "$dead_letter_dir")" -eq 0 ]
}

started_ollama_drains_pending_queue_and_writes_retry_raw() {
  local output
  local status
  local ollama_url

  create_fixture
  make_transcript
  write_queue_item pending.json pending 0 "$TRANSCRIPT_PATH"
  start_dummy_ollama ollama_url || return $?
  run_hook output status '{}' "$ollama_url"

  [ "$status" -eq 0 ] && [ "$(raw_file_count)" -eq 1 ]
}

missing_transcript_is_skipped() {
  local output
  local status

  create_fixture
  run_hook output status '{}'

  [ "$status" -eq 0 ] && [[ "$output" == *"transcript なし"* ]]
}

empty_conversation_is_skipped() {
  local output
  local status

  create_fixture
  make_empty_transcript
  run_hook output status "$(session_input)"

  [ "$status" -eq 0 ] && [[ "$output" == *"会話内容なし"* ]]
}

static_check_has_no_pcloud_drain_or_mount() {
  ! grep -Eq 'queue_drain.*pcloud' "$HOOK_SCRIPT" &&
    ! grep -Eq 'mountpoint[[:space:]]+-q.*pcloud' "$HOOK_SCRIPT"
}

if command -v shellcheck >/dev/null 2>&1; then
  run_test "shellcheck -S error がテストと hook の両方で通る" shellcheck_pass
else
  skip_test "shellcheck -S error がテストと hook の両方で通る" "shellcheck not installed"
fi
run_test "bash -n がテストと hook の両方で通る" bash_syntax

if command -v jq >/dev/null 2>&1 && command -v curl >/dev/null 2>&1; then
  run_test "SessionEnd 相当入力で raw と Ollama キューを生成" session_end_queues_ollama_and_writes_raw
  run_test "pCloud ディレクトリと pCloud キューを生成しない" session_end_does_not_create_pcloud_or_pcloud_queue_item
  run_test "pCloud キューを Ollama 停止中でも pending へ移行" pcloud_queue_item_migrates_to_pending_while_ollama_is_down
  run_test "Ollama 停止中は pending キューを drain しない" pending_queue_is_not_drained_while_ollama_is_down
  run_test "Ollama 停止中は Ollama キューも drain しない" ollama_queue_is_not_drained_while_ollama_is_down
  run_test "Ollama 停止中の 4 回連続実行で dead-letter に移動しない" pending_queue_is_not_dead_lettered_after_four_stopped_runs
  if command -v python3 >/dev/null 2>&1; then
    run_test_or_skip "Ollama 起動中の drain で retry raw を生成" started_ollama_drains_pending_queue_and_writes_retry_raw
  else
    skip_test "Ollama 起動中の drain で retry raw を生成" "python3 not installed"
  fi
  run_test "transcript_path なしを exit 0 でスキップ" missing_transcript_is_skipped
  run_test "空会話 transcript を exit 0 でスキップ" empty_conversation_is_skipped
else
  skip_test "knowledge-distill の動作テスト" "jq or curl not installed"
fi

run_test "hook に pCloud drain と mountpoint 確認を含めない" static_check_has_no_pcloud_drain_or_mount

echo ""
echo "Results: ${PASS} PASS / ${FAIL} FAIL / ${SKIP} SKIP"

if [ "$FAIL" -gt 0 ]; then
  exit 1
fi
