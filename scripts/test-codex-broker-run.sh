#!/usr/bin/env bash
# codex-broker-run.sh の前景専用・排他・worker 寿命 lock 契約テスト
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
WRAPPER="$SCRIPT_DIR/codex-broker-run.sh"
PASS=0
FAIL=0
TEST_ROOT="$(mktemp -d)"

cleanup() {
  if [[ -s "$TEST_ROOT/worker.pid" ]]; then
    kill "$(<"$TEST_ROOT/worker.pid")" 2>/dev/null || true
  fi
  rm -rf -- "$TEST_ROOT"
}
trap cleanup EXIT

record_result() {
  if [[ "$2" -eq 0 ]]; then
    echo "PASS: $1"
    ((PASS++)) || true
  else
    echo "FAIL: $1"
    ((FAIL++)) || true
  fi
}

mkdir -p "$TEST_ROOT/plugin/scripts" "$TEST_ROOT/runtime"
printf '%s\n' '{"phases":{"resource_wait":{"magi":3,"codex":3}}}' >"$TEST_ROOT/budget.json"
printf '%s\n' 'broker test prompt' >"$TEST_ROOT/prompt.txt"

cat >"$TEST_ROOT/plugin/scripts/codex-companion.mjs" <<'EOF'
import fs from "node:fs";

const args = process.argv.slice(2);
const log = process.env.STUB_LOG;
const id = process.env.STUB_ID || "unknown";
const append = (event) => fs.appendFileSync(log, `${event}:${id}\n`);
const sleep = (ms) => Atomics.wait(new Int32Array(new SharedArrayBuffer(4)), 0, 0, ms);

if (args[0] === "status") {
  console.log("Session runtime: test");
  process.exit(0);
}
if (args[0] === "task") {
  append("start");
  if (process.env.STUB_PID_FILE) fs.writeFileSync(process.env.STUB_PID_FILE, String(process.pid));
  sleep(Number(process.env.STUB_DURATION_MS || 0));
  append("end");
  process.exit(Number(process.env.STUB_EXIT || 0));
}
process.exit(2);
EOF

COMMON_ENV=(
  "CLAUDE_PLUGIN_ROOT=$TEST_ROOT/plugin"
  "EXECUTION_BUDGET_JSON=$TEST_ROOT/budget.json"
  "XDG_RUNTIME_DIR=$TEST_ROOT/runtime"
  "STUB_LOG=$TEST_ROOT/events.log"
)

: >"$TEST_ROOT/events.log"
if env "${COMMON_ENV[@]}" bash "$WRAPPER" --check >"$TEST_ROOT/check.out" 2>"$TEST_ROOT/check.err" \
  && grep -Fq "Session runtime: test" "$TEST_ROOT/check.out"; then result=0; else result=1; fi
record_result "--check は wrapper が解決した companion の status を返す" "$result"

assert_rejected() {
  local label="$1"
  shift
  set +e
  env "${COMMON_ENV[@]}" bash "$WRAPPER" task --prompt-file "$TEST_ROOT/prompt.txt" "$@" \
    >"$TEST_ROOT/reject.out" 2>"$TEST_ROOT/reject.err"
  local status=$?
  set -e
  if [[ "$status" -eq 2 ]] && grep -Fq "前景のみ" "$TEST_ROOT/reject.err" \
    && grep -Fq "plangen GENERATE" "$TEST_ROOT/reject.err" \
    && [[ ! -s "$TEST_ROOT/events.log" ]]; then result=0; else result=1; fi
  record_result "$label を worker 起動前に exit 2 で拒否する" "$result"
}

: >"$TEST_ROOT/events.log"
assert_rejected "--background" --background
: >"$TEST_ROOT/events.log"
assert_rejected "--background=true" --background=true
: >"$TEST_ROOT/events.log"
assert_rejected "--background=1" --background=1
: >"$TEST_ROOT/events.log"
assert_rejected "-background" -background

: >"$TEST_ROOT/events.log"
set +e
env "${COMMON_ENV[@]}" bash "$WRAPPER" task "raw positional prompt" \
  >"$TEST_ROOT/raw.out" 2>"$TEST_ROOT/raw.err"
STATUS=$?
set -e
if [[ "$STATUS" -eq 2 ]] && grep -Fq -- "--prompt-file" "$TEST_ROOT/raw.err" \
  && [[ ! -s "$TEST_ROOT/events.log" ]]; then result=0; else result=1; fi
record_result "raw positional prompt を --prompt-file 案内付きで拒否する" "$result"

: >"$TEST_ROOT/events.log"
env "${COMMON_ENV[@]}" STUB_ID=one STUB_DURATION_MS=1200 \
  bash "$WRAPPER" task --prompt-file "$TEST_ROOT/prompt.txt" >"$TEST_ROOT/one.out" 2>"$TEST_ROOT/one.err" &
FIRST_PID=$!
sleep 0.1
env "${COMMON_ENV[@]}" STUB_ID=two \
  bash "$WRAPPER" task --prompt-file "$TEST_ROOT/prompt.txt" >"$TEST_ROOT/two.out" 2>"$TEST_ROOT/two.err" &
SECOND_PID=$!
wait "$FIRST_PID"
wait "$SECOND_PID"
if [[ "$(tr '\n' ' ' <"$TEST_ROOT/events.log")" == "start:one end:one start:two end:two " ]]; then result=0; else result=1; fi
record_result "並行 task 2本が task 単位で直列化される" "$result"
if grep -Eq 'Codex broker lock wait: [1-9][0-9]*s' "$TEST_ROOT/two.err"; then result=0; else result=1; fi
record_result "flock 取得までの待ち秒数を stderr に出す" "$result"

: >"$TEST_ROOT/events.log"
if env "${COMMON_ENV[@]}" STUB_ID=long STUB_DURATION_MS=1500 \
  bash "$WRAPPER" task --prompt-file "$TEST_ROOT/prompt.txt" >"$TEST_ROOT/long.out" 2>"$TEST_ROOT/long.err"; then result=0; else result=1; fi
record_result "resource_wait を worker の実行 timeout に流用しない" "$result"

: >"$TEST_ROOT/events.log"
env "${COMMON_ENV[@]}" STUB_ID=killed STUB_DURATION_MS=1800 STUB_PID_FILE="$TEST_ROOT/worker.pid" \
  bash "$WRAPPER" task --prompt-file "$TEST_ROOT/prompt.txt" >"$TEST_ROOT/killed.out" 2>"$TEST_ROOT/killed.err" &
KILLED_WRAPPER_PID=$!
for _ in $(seq 1 50); do
  [[ -s "$TEST_ROOT/worker.pid" ]] && break
  sleep 0.05
done
kill -KILL "$KILLED_WRAPPER_PID" 2>/dev/null || true
wait "$KILLED_WRAPPER_PID" 2>/dev/null || true
set +e
timeout 1 env "${COMMON_ENV[@]}" STUB_ID=while-worker-runs \
  bash "$WRAPPER" task --prompt-file "$TEST_ROOT/prompt.txt" >"$TEST_ROOT/while.out" 2>"$TEST_ROOT/while.err"
STATUS=$?
set -e
if [[ "$STATUS" -eq 124 ]] && ! grep -Fq "start:while-worker-runs" "$TEST_ROOT/events.log"; then result=0; else result=1; fi
record_result "wrapper kill 後も前景 worker が fd 9 を保持する" "$result"
for _ in $(seq 1 50); do
  grep -Fq "end:killed" "$TEST_ROOT/events.log" 2>/dev/null && break
  sleep 0.05
done
if env "${COMMON_ENV[@]}" STUB_ID=after-worker \
  bash "$WRAPPER" task --prompt-file "$TEST_ROOT/prompt.txt" >"$TEST_ROOT/after.out" 2>"$TEST_ROOT/after.err" \
  && grep -Fq "start:after-worker" "$TEST_ROOT/events.log"; then result=0; else result=1; fi
record_result "worker 終了時に kernel が lock を解放する" "$result"

set +e
env "${COMMON_ENV[@]}" STUB_ID=exit-code STUB_EXIT=7 bash "$WRAPPER" task --prompt-file "$TEST_ROOT/prompt.txt" \
  >"$TEST_ROOT/exit.out" 2>"$TEST_ROOT/exit.err"
STATUS=$?
set -e
if [[ "$STATUS" -eq 7 ]]; then result=0; else result=1; fi
record_result "foreground task の終了コードを透過する" "$result"

LOCK="$TEST_ROOT/runtime/claude-codex-broker.lock"
exec 7>"$LOCK"
LOCK_INODE="$(stat -c %i "$LOCK")"
flock 7
set +e
env "${COMMON_ENV[@]}" STUB_ID=blocked bash "$WRAPPER" task --prompt-file "$TEST_ROOT/prompt.txt" \
  >"$TEST_ROOT/blocked.out" 2>"$TEST_ROOT/blocked.err"
STATUS=$?
set -e
if [[ "$STATUS" -eq 9 && "$LOCK_INODE" == "$(stat -c %i "$LOCK")" ]] \
  && grep -Fq "取得できませんでした" "$TEST_ROOT/blocked.err"; then result=0; else result=1; fi
exec 7>&-
record_result "lock timeout でも安定 pathname を unlink せず exit 9" "$result"

echo ""
echo "=== 結果: PASS=$PASS FAIL=$FAIL ==="
[[ "$FAIL" -eq 0 ]]
