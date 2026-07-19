#!/usr/bin/env bash
# test-lessons-learned-local.sh — lessons-learned-distill.sh のローカル保存・キュー動作テスト

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TEST_SCRIPT="$SCRIPT_DIR/test-lessons-learned-local.sh"
HOOK_SCRIPT="$SCRIPT_DIR/../hooks/lessons-learned-distill.sh"
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
  local retry="${5:-0}"
  local result_output
  local result_status

  if result_output=$(HOME="$FIXTURE_DIR" \
    OLLAMA_BASE_URL="$ollama_url" \
    KRAG_LL_RETRY="$retry" \
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
  local queue_dir="$FIXTURE_DIR/.claude/hooks/queue/lessons-learned"

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
  printf '%s/.claude/hooks/queue/lessons-learned/%s\n' "$FIXTURE_DIR" "$1"
}

queue_reason_count() {
  local expected_reason="$1"
  local queue_dir="$FIXTURE_DIR/.claude/hooks/queue/lessons-learned"
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

local_lessons_learned_dir() {
  printf '%s/.local/share/knowledge-rag/lessons-learned\n' "$FIXTURE_DIR"
}

pcloud_lessons_learned_dir() {
  printf '%s/pcloud/obsidian/lessons-learned\n' "$FIXTURE_DIR"
}

start_dummy_ollama() {
  local url_var="$1"
  local port_file="$FIXTURE_DIR/ollama-port"
  local server_log="$FIXTURE_DIR/ollama-server.log"
  local pid
  local port=""
  local attempt

  python3 -c 'import http.server, socketserver; Handler=type("Handler",(http.server.BaseHTTPRequestHandler,),{"do_GET":lambda self: (self.send_response(200), self.end_headers(), self.wfile.write(b"{}")) if self.path == "/api/tags" else (self.send_response(404), self.end_headers()),"do_POST":lambda self: (self.send_response(200), self.end_headers(), self.wfile.write(b"{\"response\":\"test\"}")) if self.path == "/api/generate" else (self.send_response(404), self.end_headers()),"log_message":lambda *args: None}); server=socketserver.TCPServer(("127.0.0.1", 0), Handler); print(server.server_address[1], flush=True); server.serve_forever()' \
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

local_output_directory_is_created() {
  local output
  local status
  local ollama_url

  create_fixture
  make_transcript
  start_dummy_ollama ollama_url || return $?
  run_hook output status "$(session_input)" "$ollama_url"

  [ "$status" -eq 0 ] && [ -d "$(local_lessons_learned_dir)" ]
}

unmounted_pcloud_exits_zero_without_pcloud_queue() {
  local output
  local status

  create_fixture
  make_transcript
  run_hook output status "$(session_input)"

  [ "$status" -eq 0 ] && [ "$(queue_reason_count pcloud)" -eq 0 ]
}

pcloud_lessons_learned_path_is_not_written() {
  local output
  local status
  local ollama_url

  create_fixture
  make_transcript
  start_dummy_ollama ollama_url || return $?
  run_hook output status "$(session_input)" "$ollama_url"

  [ "$status" -eq 0 ] && [ ! -e "$(pcloud_lessons_learned_dir)" ]
}

static_check_has_no_mountpoint_check() {
  ! grep -Eq 'mountpoint[[:space:]]+-q' "$HOOK_SCRIPT"
}

static_check_has_no_pcloud_queue_reason() {
  ! grep -Eq 'queue_push[[:space:]][^#]*"pcloud"' "$HOOK_SCRIPT"
}

ollama_stopped_queues_ollama_and_exits_zero() {
  local output
  local status

  create_fixture
  make_transcript
  run_hook output status "$(session_input)"

  [ "$status" -eq 0 ] && [ "$(queue_reason_count ollama)" -eq 1 ]
}

retry_flag_skips_queue_drain() {
  local output
  local status
  local item

  create_fixture
  make_transcript
  write_queue_item ollama.json ollama 0 "$TRANSCRIPT_PATH"
  item="$(queue_item_path ollama.json)"
  run_hook output status '{}' 'http://127.0.0.1:9' 1

  [ "$status" -eq 0 ] && [ -f "$item" ] && [ "$(queue_reason_count ollama)" -eq 1 ]
}

missing_transcript_is_skipped() {
  local output
  local status

  create_fixture
  run_hook output status '{}'

  [ "$status" -eq 0 ] &&
    [ "$(queue_reason_count pcloud)" -eq 0 ] &&
    [ "$(queue_reason_count ollama)" -eq 0 ]
}

empty_conversation_is_skipped() {
  local output
  local status

  create_fixture
  make_empty_transcript
  run_hook output status "$(session_input)"

  [ "$status" -eq 0 ] &&
    [ "$(queue_reason_count pcloud)" -eq 0 ] &&
    [ "$(queue_reason_count ollama)" -eq 0 ]
}

ollama_stopped_does_not_drain_queue() {
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

if command -v shellcheck >/dev/null 2>&1; then
  run_test "shellcheck -S error がテストと hook の両方で通る" shellcheck_pass
else
  skip_test "shellcheck -S error がテストと hook の両方で通る" "shellcheck not installed"
fi
run_test "bash -n がテストと hook の両方で通る" bash_syntax

if command -v jq >/dev/null 2>&1 && command -v curl >/dev/null 2>&1; then
  if command -v python3 >/dev/null 2>&1; then
    run_test_or_skip "ローカル lessons-learned 出力ディレクトリを作成" local_output_directory_is_created
    run_test_or_skip "pCloud lessons-learned パスへ書き込まない" pcloud_lessons_learned_path_is_not_written
  else
    skip_test "ローカル lessons-learned 出力ディレクトリを作成" "python3 not installed"
    skip_test "pCloud lessons-learned パスへ書き込まない" "python3 not installed"
  fi
  run_test "pCloud 未マウントでも exit 0 かつ pcloud キューを生成しない" unmounted_pcloud_exits_zero_without_pcloud_queue
  run_test "Ollama 停止時は ollama reason でキューし exit 0" ollama_stopped_queues_ollama_and_exits_zero
  run_test "KRAG_LL_RETRY=1 時はキュー drain をスキップ" retry_flag_skips_queue_drain
  run_test "transcript_path なしを exit 0 でスキップ" missing_transcript_is_skipped
  run_test "空会話 transcript を exit 0 でスキップ" empty_conversation_is_skipped
  run_test "Ollama 停止時はキューを drain しない" ollama_stopped_does_not_drain_queue
else
  skip_test "lessons-learned の動作テスト" "jq or curl not installed"
fi

run_test "hook に mountpoint 確認を含めない" static_check_has_no_mountpoint_check
run_test "hook に pcloud reason の queue_push を含めない" static_check_has_no_pcloud_queue_reason

echo ""
echo "Results: ${PASS} PASS / ${FAIL} FAIL / ${SKIP} SKIP"

if [ "$FAIL" -gt 0 ]; then
  exit 1
fi
