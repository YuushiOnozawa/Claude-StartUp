#!/usr/bin/env bash
# resource lock の実経路契約テスト
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
PASS=0
FAIL=0
TEST_ROOT="$(mktemp -d)"
trap 'rm -rf -- "$TEST_ROOT"' EXIT

record_result() {
  if [[ "$2" -eq 0 ]]; then
    echo "PASS: $1"
    ((PASS++)) || true
  else
    echo "FAIL: $1"
    ((FAIL++)) || true
  fi
}

# Markdown の fenced bash block だけを入力にし、行全体の grep ではなく
# shell の simple command の境界（pipeline / list）を分解して direct task を探す。
extract_task_command() {
  local source="$1"
  awk '
    /^```bash[[:space:]]*$/ { in_block=1; next }
    in_block && /^```[[:space:]]*$/ { in_block=0; next }
    in_block && $0 ~ /bash[[:space:]]+"\$CODEX_BROKER_RUN"[[:space:]]+task/ {
      line=$0
      while (line ~ /\\[[:space:]]*$/) {
        sub(/\\[[:space:]]*$/, "", line)
        if (getline continuation <= 0) break
        line=line " " continuation
      }
      print line
      exit
    }
  ' "$source"
}

count_broker_tasks() {
  local source="$1"
  awk '
    /^```bash[[:space:]]*$/ { in_block=1; next }
    in_block && /^```[[:space:]]*$/ { in_block=0; next }
    in_block && $0 ~ /bash[[:space:]]+"\$CODEX_BROKER_RUN"[[:space:]]+task/ { count++ }
    END { print count + 0 }
  ' "$source"
}

find_direct_companion_task() {
  local source="$1"
  awk -v source="$source" '
    function flush_command(    i, command) {
      if (pending == "") return
      n=split(pending, parts, /[|;&]/)
      for (i=1; i<=n; i++) {
        command=parts[i]
        gsub(/^[[:space:]]*(if|then|do|else|elif)[[:space:]]+/, "", command)
        if (command ~ /(^|[[:space:]])node[[:space:]]+/ \
            && command ~ /codex-companion([.]mjs)?/ \
            && command ~ /(^|[[:space:]])task([[:space:]]|$)/) {
          print source ":" NR ": direct codex-companion task"
          found=1
        }
      }
      pending=""
    }
    /^```bash[[:space:]]*$/ { flush_command(); in_block=1; next }
    in_block && /^```[[:space:]]*$/ { flush_command(); in_block=0; next }
    !in_block { next }
    {
      line=$0
      sub(/[[:space:]]+#.*/, "", line)
      pending=pending line
      if (line !~ /\\[[:space:]]*$/) flush_command()
      else sub(/\\[[:space:]]*$/, "", pending)
    }
    END { flush_command(); exit(found ? 1 : 0) }
  ' "$source"
}

find_plangen_background_task() {
  local source="$1"
  awk '
    /^```bash[[:space:]]*$/ { in_block=1; next }
    in_block && /^```[[:space:]]*$/ { in_block=0; next }
    in_block {
      line=$0
      sub(/[[:space:]]+#.*/, "", line)
      if (line ~ /node/ && line ~ /CODEX_COMPANION/ && line ~ /--background/) {
        print source ":" NR ": CODEX_COMPANION background task"
        found=1
      }
    }
    END { exit(found ? 0 : 1) }
  ' source="$source" "$source"
}

extract_broker_resolver() {
  local source="$1"
  awk '
    /^```bash[[:space:]]*$/ { in_block=1; next }
    in_block && /^```[[:space:]]*$/ { in_block=0; next }
    in_block && !capturing && $0 ~ /^CODEX_BROKER_RUN=""$/ {
      capturing=1
      closures=0
    }
    capturing {
      print
      if ($0 ~ /^[[:space:]]*fi[[:space:]]*$/) {
        closures++
        if (closures == 2) exit
      }
    }
  ' "$source"
}

BROKER_FILES=(
  skills/codegen/references/spec-template.md
  skills/dev-flow-fast/references/codex-review.md
  skills/dev-flow-fast/references/codex-review-audit.md
  skills/dev-flow-fast/references/codex-review-fast.md
  skills/dev-flow-fast/references/codex-review-hard.md
  skills/dev-flow-fast/references/codex-review-validity.md
  skills/flow-common/references/design-review.md
  skills/magi-common/references/codex-audit.md
  skills/magi-common/references/codex-fast-gate.md
  skills/magi-common/references/codex-importance.md
)

BROKER_TASKS=0
PARSER_FAILED=0
# codex-review-fast.md は hard の resolver 契約を再利用するだけで、自身の resolver block を持たない。
for file in "${BROKER_FILES[@]}"; do
  source="$REPO_ROOT/$file"
  if [[ ! -r "$source" ]] || [[ -z "$(extract_task_command "$source")" ]]; then
    PARSER_FAILED=1
  fi
  if find_direct_companion_task "$source" >"$TEST_ROOT/direct-task.txt"; then
    :
  else
    PARSER_FAILED=1
  fi
  BROKER_TASKS=$((BROKER_TASKS + $(count_broker_tasks "$source")))
done
if [[ "$PARSER_FAILED" -eq 0 && "$BROKER_TASKS" -eq "${#BROKER_FILES[@]}" ]]; then result=0; else result=1; fi
record_result "対象 command block の task 呼び出しが broker 経由で direct companion task を含まない" "$result"

PLANGEN_FILE="$REPO_ROOT/skills/plangen/references/spec-template.md"
if find_plangen_background_task "$PLANGEN_FILE" >"$TEST_ROOT/plangen-background.txt" 2>/dev/null; then
  PLANGEN_DIRECT=1
else
  PLANGEN_DIRECT=0
fi
if [[ "$PLANGEN_DIRECT" -eq 1 ]] \
  && ! grep -Fq 'codex-broker-run.sh' "$PLANGEN_FILE" \
  && grep -Fq 'broker lock の非参加者' "$PLANGEN_FILE" \
  && grep -Fq 'plangen と review の間に broker wedge' "$PLANGEN_FILE"; then result=0; else result=1; fi
record_result "plangen GENERATE は #412 の直接 background 経路を維持し broker 非参加を明記する" "$result"

# /magi-fast → dispatch → dev-flow の busy handoff を、実 producer と実 validator で通す。
mkdir -p "$TEST_ROOT/bin" "$TEST_ROOT/ollama-runtime"
cat >"$TEST_ROOT/bin/curl" <<'EOF'
#!/usr/bin/env bash
set -u
printf 'curl:%s\n' "${OLLAMA_BUSY_LOG:?}" >>"$OLLAMA_BUSY_LOG"
exit 9
EOF
chmod +x "$TEST_ROOT/bin/curl"
printf '%s\n' 'busy fixture prompt' >"$TEST_ROOT/prompt.txt"
cat >"$TEST_ROOT/magi-fast-dispatch-fixture.sh" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
REPO_ROOT="$1"
PROMPT_FILE="$2"
HANDOFF_FILE="$3"
OUTPUT_FILE="$4"
ERROR_FILE="$5"
if bash "$REPO_ROOT/scripts/ollama-run.sh" qwen-test <"$PROMPT_FILE" >"$OUTPUT_FILE" 2>"$ERROR_FILE"; then
  NATIVE_EXIT=0
else
  NATIVE_EXIT=$?
fi
jq -n --arg reason "busy_resource: ollama lock exit 9" --argjson exit_code "$NATIVE_EXIT" \
  '{schema_version:"1",artifact_type:"review-dispatch-result",review_kind:"fast",backend:"magi",
    dispatch_status:"failed",gate_decision:"indeterminate",lgtm_eligible:false,blocking_count:null,
    manual_review_required:true,manual_review:null,artifact_ref:null,adjudication_ref:null,
    post_state:"not_applicable",failure_reason:$reason,native_result:{exit_code:$exit_code}}' \
  >"$HANDOFF_FILE"
exit "$NATIVE_EXIT"
EOF
chmod +x "$TEST_ROOT/magi-fast-dispatch-fixture.sh"

MAGI_FAST_RESULT="$TEST_ROOT/magi-fast-result.json"
BUSY_EXIT=0
if PATH="$TEST_ROOT/bin:$PATH" OLLAMA_BUSY_LOG="$TEST_ROOT/busy-events.log" \
  OLLAMA_LOCK_DIR="$TEST_ROOT/ollama-runtime" OLLAMA_RUN_LOG="$TEST_ROOT/ollama-run.log" \
  OLLAMA_BASE_URL=http://busy-fixture \
  bash "$TEST_ROOT/magi-fast-dispatch-fixture.sh" "$REPO_ROOT" "$TEST_ROOT/prompt.txt" \
  "$MAGI_FAST_RESULT" "$TEST_ROOT/magi-fast.out" "$TEST_ROOT/magi-fast.err"; then
  BUSY_EXIT=0
else
  BUSY_EXIT=$?
fi
DISPATCH_RESULT="$MAGI_FAST_RESULT"
DISPATCH_EXIT=0
bash "$REPO_ROOT/scripts/review-dispatch-envelope.sh" validate "$DISPATCH_RESULT" || DISPATCH_EXIT=$?
if [[ "$BUSY_EXIT" -eq 9 ]] \
  && [[ "$DISPATCH_EXIT" -eq 0 ]] \
  && jq -e '.native_result.exit_code == 9
    and .backend == "magi"
    and .dispatch_status != "complete"
    and .lgtm_eligible == false
    and .manual_review_required == true' "$DISPATCH_RESULT" >/dev/null \
  && grep -Fq 'curl:' "$TEST_ROOT/busy-events.log" \
  && ! grep -Eiq 'fallback|lgtm' "$TEST_ROOT/magi-fast.out" "$TEST_ROOT/magi-fast.err"; then result=0; else result=1; fi
record_result "magi-fast の Ollama exit 9 が実 handoff/validator を経て LGTM 化・backend fallback されない" "$result"

# 実 wrapper と companion fixture を3つの resolver 配置へ用意する。
mkdir -p "$TEST_ROOT/plugin/scripts" "$TEST_ROOT/plugin/skills/flow-common" "$TEST_ROOT/codex-runtime"
mkdir -p "$TEST_ROOT/distribution/scripts" "$TEST_ROOT/distribution/skills/flow-common"
mkdir -p "$TEST_ROOT/home/.claude/scripts" "$TEST_ROOT/home/.claude/skills/flow-common"
mkdir -p "$TEST_ROOT/home/.claude/plugins/cache/openai-codex/codex/test/scripts"
cp "$REPO_ROOT/scripts/codex-broker-run.sh" "$TEST_ROOT/plugin/scripts/codex-broker-run.sh"
cp "$REPO_ROOT/skills/flow-common/execution-budget.sh" "$TEST_ROOT/plugin/skills/flow-common/execution-budget.sh"
cp "$REPO_ROOT/skills/flow-common/execution-budget.json" "$TEST_ROOT/plugin/skills/flow-common/execution-budget.json"
cp "$REPO_ROOT/scripts/codex-broker-run.sh" "$TEST_ROOT/distribution/scripts/codex-broker-run.sh"
cp "$REPO_ROOT/skills/flow-common/execution-budget.sh" "$TEST_ROOT/distribution/skills/flow-common/execution-budget.sh"
cp "$REPO_ROOT/skills/flow-common/execution-budget.json" "$TEST_ROOT/distribution/skills/flow-common/execution-budget.json"
cp "$REPO_ROOT/scripts/codex-broker-run.sh" "$TEST_ROOT/home/.claude/scripts/codex-broker-run.sh"
cp "$REPO_ROOT/skills/flow-common/execution-budget.sh" "$TEST_ROOT/home/.claude/skills/flow-common/execution-budget.sh"
cp "$REPO_ROOT/skills/flow-common/execution-budget.json" "$TEST_ROOT/home/.claude/skills/flow-common/execution-budget.json"
git init -q "$TEST_ROOT/distribution"
cat >"$TEST_ROOT/plugin/scripts/codex-companion.mjs" <<'EOF'
import fs from "node:fs";

const id = process.env.STUB_ID || "unknown";
const log = process.env.CODEX_EVENT_LOG;
const now = () => Date.now();
const write = (event) => fs.appendFileSync(log, `${event}|${id}|${now()}\n`);
const sleep = (ms) => Atomics.wait(new Int32Array(new SharedArrayBuffer(4)), 0, 0, ms);

if (process.argv[2] === "task") {
  write("start");
  sleep(Number(process.env.STUB_DURATION_MS || 400));
  write("end");
  process.exit(0);
}
if (process.argv[2] === "status") {
  console.log("Session runtime: wiring-test");
  process.exit(0);
}
process.exit(2);
EOF
cp "$TEST_ROOT/plugin/scripts/codex-companion.mjs" \
  "$TEST_ROOT/home/.claude/plugins/cache/openai-codex/codex/test/scripts/codex-companion.mjs"

verify_broker_resolver() {
  local file source resolver branch expected workdir path_file output_file error_file
  local label failed=0
  file="$1"
  source="$REPO_ROOT/$file"
  label="${file//\//_}"
  resolver="$(extract_broker_resolver "$source")"
  [[ -n "$resolver" ]] || return 1
  for branch in plugin distribution fallback; do
    case "$branch" in
      plugin)
        export CLAUDE_PLUGIN_ROOT="$TEST_ROOT/plugin"
        expected="$TEST_ROOT/plugin/scripts/codex-broker-run.sh"
        workdir="$TEST_ROOT"
        ;;
      distribution)
        unset CLAUDE_PLUGIN_ROOT
        expected="$TEST_ROOT/distribution/scripts/codex-broker-run.sh"
        workdir="$TEST_ROOT/distribution"
        ;;
      fallback)
        unset CLAUDE_PLUGIN_ROOT
        expected="$TEST_ROOT/home/.claude/scripts/codex-broker-run.sh"
        workdir="$TEST_ROOT"
        ;;
    esac
    path_file="$TEST_ROOT/resolver-$label-$branch.path"
    output_file="$TEST_ROOT/resolver-$label-$branch.out"
    error_file="$TEST_ROOT/resolver-$label-$branch.err"
    if (
      export HOME="$TEST_ROOT/home"
      export XDG_RUNTIME_DIR="$TEST_ROOT/codex-runtime"
      export EXECUTION_BUDGET_JSON="$REPO_ROOT/skills/flow-common/execution-budget.json"
      export STUB_LOG="$TEST_ROOT/resolver-events.log"
      cd "$workdir"
      eval "$resolver"
      [[ "$CODEX_BROKER_RUN" == "$expected" ]]
      printf '%s\n' "$CODEX_BROKER_RUN" >"$path_file"
      bash "$CODEX_BROKER_RUN" --check >"$output_file" 2>"$error_file"
    ); then
      if [[ "$(<"$path_file")" == "$expected" ]] \
        && grep -Fq "Session runtime: wiring-test" "$output_file"; then
        continue
      fi
    fi
    failed=1
  done
  return "$failed"
}

for file in "${BROKER_FILES[@]}"; do
  if [[ "$file" != "skills/dev-flow-fast/references/codex-review-fast.md" ]]; then
    if verify_broker_resolver "$file"; then result=0; else result=1; fi
    record_result "$file の CODEX_BROKER_RUN resolver 3分岐を実行検証する" "$result"
  fi
done

DOC_FLOW_FILES=(
  "design|skills/flow-common/references/design-review.md|plugin"
  "codegen|skills/codegen/references/spec-template.md|distribution"
  "magi-persona|skills/magi-common/references/codex-audit.md|fallback"
  "codex-hard|skills/dev-flow-fast/references/codex-review-hard.md|plugin"
)
for entry in "${DOC_FLOW_FILES[@]}"; do
  IFS='|' read -r flow file branch <<<"$entry"
  FLOW_DIR="$TEST_ROOT/$flow"
  mkdir -p "$FLOW_DIR"
  printf '%s\n' "$flow prompt" >"$FLOW_DIR/prompt.txt"
  : >"$FLOW_DIR/err.txt"
  : >"$FLOW_DIR/raw.txt"
done

run_doc_flow() {
  local flow file branch command resolver expected source
  flow="$1"
  file="$2"
  branch="$3"
  source="$REPO_ROOT/$file"
  command="$(extract_task_command "$source")"
  # design-review の元 snippet は stderr を捨てるため、lock wait 行だけ fixture log に残す。
  command="$(sed "s#2>/dev/null#2>\"$TEST_ROOT/$flow/err.txt\"#g" <<<"$command")"
  case "$flow" in
    design)
      DESIGN_REVIEW_TMPDIR="$TEST_ROOT/$flow"
      ;;
    codegen)
      CODEGEN_PROMPT_FILE="$TEST_ROOT/$flow/prompt.txt"
      ;;
    magi-persona)
      MAGI_TMPDIR="$TEST_ROOT/$flow"
      AUDIT_BUDGET=10
      ;;
    codex-hard)
      PROMPT_FILE="$TEST_ROOT/$flow/prompt.txt"
      RAW_FILE="$TEST_ROOT/$flow/raw.txt"
      ERR_FILE="$TEST_ROOT/$flow/err.txt"
      CODEX_TASK_BUDGET=10
      ;;
  esac
  case "$branch" in
    plugin)
      export CLAUDE_PLUGIN_ROOT="$TEST_ROOT/plugin"
      export HOME="$TEST_ROOT/home"
      expected="$TEST_ROOT/plugin/scripts/codex-broker-run.sh"
      cd "$TEST_ROOT"
      ;;
    distribution)
      unset CLAUDE_PLUGIN_ROOT
      export HOME="$TEST_ROOT/home"
      expected="$TEST_ROOT/distribution/scripts/codex-broker-run.sh"
      cd "$TEST_ROOT/distribution"
      ;;
    fallback)
      unset CLAUDE_PLUGIN_ROOT
      export HOME="$TEST_ROOT/home"
      expected="$TEST_ROOT/home/.claude/scripts/codex-broker-run.sh"
      cd "$TEST_ROOT"
      ;;
  esac
  resolver="$(extract_broker_resolver "$source")"
  eval "$resolver"
  [[ "$CODEX_BROKER_RUN" == "$expected" ]]
  export CODEX_EVENT_LOG="$TEST_ROOT/codex-events.log"
  export EXECUTION_BUDGET_JSON="$REPO_ROOT/skills/flow-common/execution-budget.json"
  export XDG_RUNTIME_DIR="$TEST_ROOT/codex-runtime"
  export STUB_ID="$flow"
  export STUB_DURATION_MS=400
  eval "$command" 2>>"$TEST_ROOT/$flow/err.txt"
}

: >"$TEST_ROOT/codex-events.log"
run_doc_flow design "skills/flow-common/references/design-review.md" plugin & DESIGN_PID=$!
run_doc_flow codegen "skills/codegen/references/spec-template.md" distribution & CODEGEN_PID=$!
run_doc_flow magi-persona "skills/magi-common/references/codex-audit.md" fallback & MAGI_PID=$!
run_doc_flow codex-hard "skills/dev-flow-fast/references/codex-review-hard.md" plugin & CODEX_HARD_PID=$!
FLOW_FAILURE=0
wait "$DESIGN_PID" || FLOW_FAILURE=1
wait "$CODEGEN_PID" || FLOW_FAILURE=1
wait "$MAGI_PID" || FLOW_FAILURE=1
wait "$CODEX_HARD_PID" || FLOW_FAILURE=1

OVERLAP="$(awk -F'|' '
  $1 == "start" { start[$2]=$3; ids[++n]=$2 }
  $1 == "end" { end[$2]=$3 }
  END {
    bad=0
    for (i=1; i<=n; i++) for (j=i+1; j<=n; j++)
      if (start[ids[i]] < end[ids[j]] && start[ids[j]] < end[ids[i]]) bad=1
    print bad
  }
' "$TEST_ROOT/codex-events.log")"
LOCK_WAIT_ROWS=0
for flow in design codegen magi-persona codex-hard; do
  if grep -Fq 'Codex broker lock wait:' "$TEST_ROOT/$flow/err.txt"; then
    LOCK_WAIT_ROWS=$((LOCK_WAIT_ROWS + 1))
  fi
done
if [[ "$FLOW_FAILURE" -eq 0 && "$OVERLAP" -eq 0 && "$LOCK_WAIT_ROWS" -eq 4 ]]; then result=0; else result=1; fi
record_result "magi persona・codex-hard・design-review・codegen の実 task 区間が同時起動しても重ならない" "$result"

echo ""
echo "=== 結果: PASS=$PASS FAIL=$FAIL ==="
[[ "$FAIL" -eq 0 ]]
