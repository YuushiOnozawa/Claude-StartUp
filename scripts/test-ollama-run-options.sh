#!/usr/bin/env bash
# scripts/test-ollama-run-options.sh — ollama-run.sh の options と終了理由のテスト

set -euo pipefail

SCRIPT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/ollama-run.sh"
PASS=0
FAIL=0
TEST_ROOT="$(mktemp -d)"
FAKE_CURL_DIR="$TEST_ROOT/bin"
ORIGINAL_PATH="${PATH:-}"

cleanup() {
  rm -rf -- "$TEST_ROOT"
}
trap cleanup EXIT

mkdir -p "$FAKE_CURL_DIR"

cat >"$FAKE_CURL_DIR/curl" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail

: "${CURL_CAPTURE_DIR:?CURL_CAPTURE_DIR is required}"
mkdir -p "$CURL_CAPTURE_DIR"

count_file="$CURL_CAPTURE_DIR/.count"
if [[ -f "$count_file" ]]; then
  count="$(<"$count_file")"
else
  count=0
fi
count=$((count + 1))
printf '%s\n' "$count" >"$count_file"

body=""
output_file=""
while (($# > 0)); do
  case "$1" in
    -d|--data|--data-raw)
      body="${2:?missing argument for $1}"
      shift 2
      ;;
    -o|--output)
      output_file="${2:?missing argument for $1}"
      shift 2
      ;;
    *)
      shift
      ;;
  esac
done

printf '%s' "$body" >"$CURL_CAPTURE_DIR/call-$count.json"

if [[ -n "$output_file" ]]; then
  if [[ -n "${CURL_FAKE_RESPONSE_FILE:-}" ]]; then
    cp -- "$CURL_FAKE_RESPONSE_FILE" "$output_file"
  else
    printf '%s\n' '{"response":"ok","done_reason":"stop"}' >"$output_file"
  fi
fi

exit 0
EOF
chmod +x "$FAKE_CURL_DIR/curl"

record_result() {
  local description="$1"
  local passed="$2"

  if [[ "$passed" -eq 0 ]]; then
    echo "PASS: $description"
    ((PASS++)) || true
  else
    echo "FAIL: $description"
    ((FAIL++)) || true
  fi
}

capture_contract_ok() {
  local capture_dir="$1"

  [[ -f "$capture_dir/call-1.json" ]] \
    && [[ -f "$capture_dir/call-2.json" ]] \
    && [[ ! -e "$capture_dir/call-3.json" ]] \
    && jq -e 'has("prompt")' "$capture_dir/call-1.json" >/dev/null 2>&1 \
    && jq -e '(.keep_alive == 0) and (has("prompt") | not)' \
      "$capture_dir/call-2.json" >/dev/null 2>&1
}

payload_matches() {
  local payload_file="$1"
  local expression="$2"

  jq -e "$expression" "$payload_file" >/dev/null 2>&1
}

run_ollama() {
  local run_dir="$1"
  local response_json="$2"
  local num_predict="$3"
  local repeat_penalty="$4"
  local system_file="${5:-}"
  local run_log="${6:-$run_dir/ollama-run.log}"
  local response_file="$run_dir/response.json"
  local -a env_args
  local -a script_args

  RUN_CAPTURE_DIR="$run_dir/capture"
  RUN_STDOUT="$run_dir/stdout"
  RUN_STDERR="$run_dir/stderr"
  mkdir -p "$RUN_CAPTURE_DIR" "$run_dir/lock"
  printf '%s\n' "$response_json" >"$response_file"

  env_args=(
    env
    -u OLLAMA_NUM_PREDICT
    -u OLLAMA_REPEAT_PENALTY
    -u OLLAMA_NUM_CTX
    -u OLLAMA_TEMPERATURE
    -u OLLAMA_KEEP_ALIVE
    -u OLLAMA_RUN_LOG
    "OLLAMA_BASE_URL=http://127.0.0.1:11434"
    "OLLAMA_LOCK_DIR=$run_dir/lock"
    "OLLAMA_TIMEOUT=10"
    "OLLAMA_RUN_LOG=$run_log"
    "PATH=$FAKE_CURL_DIR:$ORIGINAL_PATH"
    "CURL_CAPTURE_DIR=$RUN_CAPTURE_DIR"
    "CURL_FAKE_RESPONSE_FILE=$response_file"
  )
  if [[ "$num_predict" != "__unset__" ]]; then
    env_args+=("OLLAMA_NUM_PREDICT=$num_predict")
  fi
  if [[ "$repeat_penalty" != "__unset__" ]]; then
    env_args+=("OLLAMA_REPEAT_PENALTY=$repeat_penalty")
  fi

  script_args=(bash "$SCRIPT" some-model)
  if [[ -n "$system_file" ]]; then
    script_args+=("$system_file")
  fi

  RUN_STATUS=0
  if printf '%s\n' 'test prompt' \
    | "${env_args[@]}" "${script_args[@]}" >"$RUN_STDOUT" 2>"$RUN_STDERR"; then
    RUN_STATUS=0
  else
    RUN_STATUS=$?
  fi
}

# 1. デフォルト値と既存 options の回帰
run_ollama "$TEST_ROOT/case-1" \
  '{"response":"ok","done_reason":"stop"}' '__unset__' '__unset__'
if capture_contract_ok "$RUN_CAPTURE_DIR" \
  && payload_matches "$RUN_CAPTURE_DIR/call-1.json" \
    '.options.num_predict == 4096 and .options.repeat_penalty == 1.15 and .options.num_ctx == 16384 and .options.temperature == 0.1 and .keep_alive == 0' \
  && [[ "$RUN_STATUS" -eq 0 ]] \
  && [[ "$(<"$RUN_STDOUT")" == "ok" ]]; then
  record_result "デフォルト値と既存 options を送信する" 0
else
  record_result "デフォルト値と既存 options を送信する" 1
fi

# 2. num_predict の指定
run_ollama "$TEST_ROOT/case-2" \
  '{"response":"ok","done_reason":"stop"}' '800' '__unset__'
if capture_contract_ok "$RUN_CAPTURE_DIR" \
  && payload_matches "$RUN_CAPTURE_DIR/call-1.json" '.options.num_predict == 800' \
  && [[ "$RUN_STATUS" -eq 0 ]] \
  && [[ "$(<"$RUN_STDOUT")" == "ok" ]]; then
  record_result "OLLAMA_NUM_PREDICT=800 を送信する" 0
else
  record_result "OLLAMA_NUM_PREDICT=800 を送信する" 1
fi

# 3. repeat_penalty の指定
run_ollama "$TEST_ROOT/case-3" \
  '{"response":"ok","done_reason":"stop"}' '__unset__' '1.3'
if capture_contract_ok "$RUN_CAPTURE_DIR" \
  && payload_matches "$RUN_CAPTURE_DIR/call-1.json" '.options.repeat_penalty == 1.3' \
  && [[ "$RUN_STATUS" -eq 0 ]] \
  && [[ "$(<"$RUN_STDOUT")" == "ok" ]]; then
  record_result "OLLAMA_REPEAT_PENALTY=1.3 を送信する" 0
else
  record_result "OLLAMA_REPEAT_PENALTY=1.3 を送信する" 1
fi

# 4. num_predict の負値フォールバック
run_ollama "$TEST_ROOT/case-4" \
  '{"response":"ok","done_reason":"stop"}' '-1' '__unset__'
if capture_contract_ok "$RUN_CAPTURE_DIR" \
  && payload_matches "$RUN_CAPTURE_DIR/call-1.json" '.options.num_predict == 4096' \
  && [[ "$RUN_STATUS" -eq 0 ]] \
  && [[ "$(<"$RUN_STDOUT")" == "ok" ]] \
  && grep -qi 'warning' "$RUN_STDERR"; then
  record_result "OLLAMA_NUM_PREDICT=-1 を警告して 4096 にフォールバックする" 0
else
  record_result "OLLAMA_NUM_PREDICT=-1 を警告して 4096 にフォールバックする" 1
fi

# 5. num_predict の非数値フォールバック
run_ollama "$TEST_ROOT/case-5" \
  '{"response":"ok","done_reason":"stop"}' 'abc' '__unset__'
if capture_contract_ok "$RUN_CAPTURE_DIR" \
  && payload_matches "$RUN_CAPTURE_DIR/call-1.json" '.options.num_predict == 4096' \
  && [[ "$RUN_STATUS" -eq 0 ]] \
  && [[ "$(<"$RUN_STDOUT")" == "ok" ]] \
  && grep -qi 'warning' "$RUN_STDERR"; then
  record_result "OLLAMA_NUM_PREDICT=abc を警告して 4096 にフォールバックする" 0
else
  record_result "OLLAMA_NUM_PREDICT=abc を警告して 4096 にフォールバックする" 1
fi

# 6. done_reason=length の扱い
run_ollama "$TEST_ROOT/case-6" \
  '{"response":"truncated","done_reason":"length"}' '__unset__' '__unset__'
if capture_contract_ok "$RUN_CAPTURE_DIR" \
  && [[ "$RUN_STATUS" -eq 75 ]] \
  && [[ ! -s "$RUN_STDOUT" ]] \
  && grep -qi 'warning' "$RUN_STDERR"; then
  record_result "done_reason=length で 75 を返し本文を出力しない" 0
else
  record_result "done_reason=length で 75 を返し本文を出力しない" 1
fi

# 7. 通常の done_reason では従来どおり本文を出力
run_ollama "$TEST_ROOT/case-7" \
  '{"response":"completed","done_reason":"stop"}' '__unset__' '__unset__'
if capture_contract_ok "$RUN_CAPTURE_DIR" \
  && [[ "$RUN_STATUS" -eq 0 ]] \
  && [[ "$(<"$RUN_STDOUT")" == "completed" ]]; then
  record_result "done_reason=stop では本文を出力する" 0
else
  record_result "done_reason=stop では本文を出力する" 1
fi

# 8. system プロンプト分岐と通常分岐の双方
SYSTEM_FILE="$TEST_ROOT/system-prompt.txt"
printf '%s\n' 'system prompt' >"$SYSTEM_FILE"
run_ollama "$TEST_ROOT/case-8-system" \
  '{"response":"ok","done_reason":"stop"}' '__unset__' '__unset__' "$SYSTEM_FILE"
SYSTEM_CAPTURE_DIR="$RUN_CAPTURE_DIR"
SYSTEM_STDOUT="$RUN_STDOUT"
SYSTEM_STATUS="$RUN_STATUS"

run_ollama "$TEST_ROOT/case-8-no-system" \
  '{"response":"ok","done_reason":"stop"}' '__unset__' '__unset__'
NO_SYSTEM_CAPTURE_DIR="$RUN_CAPTURE_DIR"
NO_SYSTEM_STDOUT="$RUN_STDOUT"
NO_SYSTEM_STATUS="$RUN_STATUS"

if capture_contract_ok "$SYSTEM_CAPTURE_DIR" \
  && payload_matches "$SYSTEM_CAPTURE_DIR/call-1.json" \
    '.system == "system prompt" and .options.num_predict == 4096 and .options.repeat_penalty == 1.15' \
  && [[ "$SYSTEM_STATUS" -eq 0 ]] \
  && [[ "$(<"$SYSTEM_STDOUT")" == "ok" ]] \
  && capture_contract_ok "$NO_SYSTEM_CAPTURE_DIR" \
  && payload_matches "$NO_SYSTEM_CAPTURE_DIR/call-1.json" \
    '.options.num_predict == 4096 and .options.repeat_penalty == 1.15' \
  && [[ "$NO_SYSTEM_STATUS" -eq 0 ]] \
  && [[ "$(<"$NO_SYSTEM_STDOUT")" == "ok" ]]; then
  record_result "system プロンプト有無の両分岐に新 options を含める" 0
else
  record_result "system プロンプト有無の両分岐に新 options を含める" 1
fi

# 9. 通常完了時の実行ログ
run_ollama "$TEST_ROOT/case-9" \
  '{"response":"ok","done_reason":"stop"}' '__unset__' '__unset__'
LOG_FILE="$TEST_ROOT/case-9/ollama-run.log"
if capture_contract_ok "$RUN_CAPTURE_DIR" \
  && [[ -f "$LOG_FILE" ]] \
  && [[ "$(wc -l <"$LOG_FILE")" -eq 2 ]] \
  && awk -F '\t' '
    NR == 1 { start_ok = NF == 3 }
    NR == 2 { complete_ok = NF == 4 && $4 == "ok" && $3 ~ /^[0-9]+$/ }
    END { exit !(NR == 2 && start_ok && complete_ok) }
  ' "$LOG_FILE" \
  && [[ "$RUN_STATUS" -eq 0 ]] \
  && [[ "$(<"$RUN_STDOUT")" == "ok" ]]; then
  record_result "通常完了時に開始・完了ログを記録する" 0
else
  record_result "通常完了時に開始・完了ログを記録する" 1
fi

# 10. 応答切り詰め時の実行ログ
run_ollama "$TEST_ROOT/case-10" \
  '{"response":"truncated","done_reason":"length"}' '__unset__' '__unset__'
LOG_FILE="$TEST_ROOT/case-10/ollama-run.log"
if capture_contract_ok "$RUN_CAPTURE_DIR" \
  && [[ -f "$LOG_FILE" ]] \
  && [[ "$(wc -l <"$LOG_FILE")" -eq 2 ]] \
  && awk -F '\t' '
    NR == 1 { start_ok = NF == 3 }
    NR == 2 { complete_ok = NF == 4 && $4 == "truncated" }
    END { exit !(NR == 2 && start_ok && complete_ok) }
  ' "$LOG_FILE" \
  && [[ "$RUN_STATUS" -eq 75 ]] \
  && [[ ! -s "$RUN_STDOUT" ]]; then
  record_result "切り詰め時に truncated の完了ログを記録する" 0
else
  record_result "切り詰め時に truncated の完了ログを記録する" 1
fi

# 11. num_predict のゼロ埋め値フォールバック
run_ollama "$TEST_ROOT/case-11-00" \
  '{"response":"ok","done_reason":"stop"}' '00' '__unset__'
ZERO_PAD_00_CAPTURE_DIR="$RUN_CAPTURE_DIR"
ZERO_PAD_00_STDOUT="$RUN_STDOUT"
ZERO_PAD_00_STDERR="$RUN_STDERR"
ZERO_PAD_00_STATUS="$RUN_STATUS"

run_ollama "$TEST_ROOT/case-11-0000" \
  '{"response":"ok","done_reason":"stop"}' '0000' '__unset__'
ZERO_PAD_0000_CAPTURE_DIR="$RUN_CAPTURE_DIR"
ZERO_PAD_0000_STDOUT="$RUN_STDOUT"
ZERO_PAD_0000_STDERR="$RUN_STDERR"
ZERO_PAD_0000_STATUS="$RUN_STATUS"

if capture_contract_ok "$ZERO_PAD_00_CAPTURE_DIR" \
  && payload_matches "$ZERO_PAD_00_CAPTURE_DIR/call-1.json" '.options.num_predict == 4096' \
  && [[ "$ZERO_PAD_00_STATUS" -eq 0 ]] \
  && [[ "$(<"$ZERO_PAD_00_STDOUT")" == "ok" ]] \
  && grep -qi 'warning' "$ZERO_PAD_00_STDERR" \
  && capture_contract_ok "$ZERO_PAD_0000_CAPTURE_DIR" \
  && payload_matches "$ZERO_PAD_0000_CAPTURE_DIR/call-1.json" '.options.num_predict == 4096' \
  && [[ "$ZERO_PAD_0000_STATUS" -eq 0 ]] \
  && [[ "$(<"$ZERO_PAD_0000_STDOUT")" == "ok" ]] \
  && grep -qi 'warning' "$ZERO_PAD_0000_STDERR"; then
  record_result "OLLAMA_NUM_PREDICT=00/0000 を警告して 4096 にフォールバックする" 0
else
  record_result "OLLAMA_NUM_PREDICT=00/0000 を警告して 4096 にフォールバックする" 1
fi

# 12. 連続実行時の開始・完了ログ順序
SEQUENTIAL_LOG_DIR="$TEST_ROOT/case-12"
SEQUENTIAL_LOG_FILE="$SEQUENTIAL_LOG_DIR/shared-ollama-run.log"
mkdir -p "$SEQUENTIAL_LOG_DIR"
run_ollama "$TEST_ROOT/case-12-run-1" \
  '{"response":"ok","done_reason":"stop"}' '__unset__' '__unset__' '' "$SEQUENTIAL_LOG_FILE"
SEQUENTIAL_RUN_1_CAPTURE_DIR="$RUN_CAPTURE_DIR"
SEQUENTIAL_RUN_1_STDOUT="$RUN_STDOUT"
SEQUENTIAL_RUN_1_STATUS="$RUN_STATUS"

run_ollama "$TEST_ROOT/case-12-run-2" \
  '{"response":"ok","done_reason":"stop"}' '__unset__' '__unset__' '' "$SEQUENTIAL_LOG_FILE"
SEQUENTIAL_RUN_2_CAPTURE_DIR="$RUN_CAPTURE_DIR"
SEQUENTIAL_RUN_2_STDOUT="$RUN_STDOUT"
SEQUENTIAL_RUN_2_STATUS="$RUN_STATUS"

if capture_contract_ok "$SEQUENTIAL_RUN_1_CAPTURE_DIR" \
  && [[ "$SEQUENTIAL_RUN_1_STATUS" -eq 0 ]] \
  && [[ "$(<"$SEQUENTIAL_RUN_1_STDOUT")" == "ok" ]] \
  && capture_contract_ok "$SEQUENTIAL_RUN_2_CAPTURE_DIR" \
  && [[ "$SEQUENTIAL_RUN_2_STATUS" -eq 0 ]] \
  && [[ "$(<"$SEQUENTIAL_RUN_2_STDOUT")" == "ok" ]] \
  && [[ "$(wc -l <"$SEQUENTIAL_LOG_FILE")" -eq 4 ]] \
  && awk -F '\t' '
    NR == 1 { start_1_ok = NF == 3 && $2 == "some-model" && $3 ~ /^[0-9]+$/ }
    NR == 2 { complete_1_ok = NF == 4 && $2 == "some-model" && $3 ~ /^[0-9]+$/ && $4 == "ok" }
    NR == 3 { start_2_ok = NF == 3 && $2 == "some-model" && $3 ~ /^[0-9]+$/ }
    NR == 4 { complete_2_ok = NF == 4 && $2 == "some-model" && $3 ~ /^[0-9]+$/ && $4 == "ok" }
    END { exit !(NR == 4 && start_1_ok && complete_1_ok && start_2_ok && complete_2_ok) }
  ' "$SEQUENTIAL_LOG_FILE"; then
  record_result "連続実行時に開始・完了ログを順序どおり記録する" 0
else
  record_result "連続実行時に開始・完了ログを順序どおり記録する" 1
fi

# 13. SIGTERM 時の実行ログ
CASE_13_DIR="$TEST_ROOT/case-13"
CASE_13_CURL_DIR="$CASE_13_DIR/bin"
CASE_13_LOG_FILE="$CASE_13_DIR/ollama-run.log"
CASE_13_RESPONSE_FILE="$CASE_13_DIR/response.json"
CASE_13_CAPTURE_DIR="$CASE_13_DIR/capture"
CASE_13_STDOUT="$CASE_13_DIR/stdout"
CASE_13_STDERR="$CASE_13_DIR/stderr"
mkdir -p "$CASE_13_CURL_DIR" "$CASE_13_DIR/lock" "$CASE_13_CAPTURE_DIR"
printf '%s\n' '{"response":"ok","done_reason":"stop"}' >"$CASE_13_RESPONSE_FILE"
cat >"$CASE_13_CURL_DIR/curl" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail

: "${REAL_CURL:?REAL_CURL is required}"
args=("$@")
body=""
for ((i = 0; i < ${#args[@]}; i++)); do
  case "${args[i]}" in
    -d|--data|--data-raw)
      if ((i + 1 < ${#args[@]})); then
        body="${args[i + 1]}"
      fi
      i=$((i + 1))
      ;;
  esac
done

if [[ "$body" == *'"prompt"'* ]]; then
  sleep 5
fi
exec "$REAL_CURL" "${args[@]}"
EOF
chmod +x "$CASE_13_CURL_DIR/curl"

CASE_13_ENV_ARGS=(
  env
  -u OLLAMA_NUM_PREDICT
  -u OLLAMA_REPEAT_PENALTY
  -u OLLAMA_NUM_CTX
  -u OLLAMA_TEMPERATURE
  -u OLLAMA_KEEP_ALIVE
  -u OLLAMA_RUN_LOG
  "OLLAMA_BASE_URL=http://127.0.0.1:11434"
  "OLLAMA_LOCK_DIR=$CASE_13_DIR/lock"
  "OLLAMA_TIMEOUT=10"
  "OLLAMA_RUN_LOG=$CASE_13_LOG_FILE"
  "PATH=$CASE_13_CURL_DIR:$FAKE_CURL_DIR:$ORIGINAL_PATH"
  "CURL_CAPTURE_DIR=$CASE_13_CAPTURE_DIR"
  "CURL_FAKE_RESPONSE_FILE=$CASE_13_RESPONSE_FILE"
  "REAL_CURL=$FAKE_CURL_DIR/curl"
)
CASE_13_RUN_STATUS=0
printf '%s\n' 'test prompt' \
  | "${CASE_13_ENV_ARGS[@]}" bash "$SCRIPT" some-model \
    >"$CASE_13_STDOUT" 2>"$CASE_13_STDERR" &
CASE_13_PID=$!
CASE_13_START_SEEN=0
for _ in {1..50}; do
  if [[ -f "$CASE_13_LOG_FILE" ]] && [[ "$(wc -l <"$CASE_13_LOG_FILE")" -ge 1 ]]; then
    CASE_13_START_SEEN=1
    break
  fi
  sleep 0.1
done
kill -TERM "$CASE_13_PID" 2>/dev/null || true
if wait "$CASE_13_PID"; then
  CASE_13_RUN_STATUS=0
else
  CASE_13_RUN_STATUS=$?
fi

if [[ "$CASE_13_START_SEEN" -eq 1 ]] \
  && [[ "$CASE_13_RUN_STATUS" -eq 143 ]] \
  && [[ -f "$CASE_13_LOG_FILE" ]] \
  && [[ "$(wc -l <"$CASE_13_LOG_FILE")" -eq 2 ]] \
  && awk -F '\t' '
    NR == 1 { start_ok = NF == 3 }
    NR == 2 { complete_ok = NF == 4 && $4 == "interrupted:TERM" && $3 ~ /^[0-9]+$/ }
    END { exit !(NR == 2 && start_ok && complete_ok) }
  ' "$CASE_13_LOG_FILE"; then
  record_result "SIGTERM 時に interrupted:TERM の完了ログを記録する" 0
else
  record_result "SIGTERM 時に interrupted:TERM の完了ログを記録する" 1
fi

echo ""
echo "=== 結果: PASS=$PASS FAIL=$FAIL ==="
if [[ "$FAIL" -eq 0 ]]; then
  exit 0
fi
exit 1
