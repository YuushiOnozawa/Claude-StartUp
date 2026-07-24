#!/usr/bin/env bash
# test-knowledge-rag-local.sh — knowledge-rag のローカル documents_dir・hook 動作テスト

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TEST_SCRIPT="$SCRIPT_DIR/test-knowledge-rag-local.sh"
SETUP_SCRIPT="$SCRIPT_DIR/../setup/402-knowledge-rag-mcp-config.sh"
AUTO_PROMOTE_SCRIPT="$SCRIPT_DIR/../hooks/knowledge-auto-promote.sh"
PRUNE_SCRIPT="$SCRIPT_DIR/../hooks/knowledge-prune.sh"
CHECK_QUEUE_SCRIPT="$SCRIPT_DIR/../hooks/check-queue.sh"
KNOWLEDGE_DISTILL_SCRIPT="$SCRIPT_DIR/../hooks/knowledge-distill.sh"
LESSONS_LEARNED_DISTILL_SCRIPT="$SCRIPT_DIR/../hooks/lessons-learned-distill.sh"
REMEMBER_SKILL="$SCRIPT_DIR/../skills/remember/SKILL.md"
BASH_BIN="$(command -v bash)"

PASS=0
FAIL=0
SKIP=0
FIXTURE_DIRS=()
SERVER_PIDS=()
TEST_SKIP_REASON=""
FIXTURE_DIR=""
CONFIG_PATH=""

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

run_jq_test() {
  local desc="$1"
  local test_function="$2"

  if command -v jq >/dev/null 2>&1; then
    run_test "$desc" "$test_function"
  else
    skip_test "$desc" "jq not installed"
  fi
}

create_fixture() {
  FIXTURE_DIR="$(mktemp -d)"
  FIXTURE_DIRS+=("$FIXTURE_DIR")
  CONFIG_PATH="$FIXTURE_DIR/.local/share/knowledge-rag/config.yaml"
}

write_config() {
  local content="$1"

  mkdir -p "$(dirname "$CONFIG_PATH")"
  printf '%s\n' "$content" >"$CONFIG_PATH"
}

run_setup() {
  local output_var="$1"
  local status_var="$2"
  local result_output
  local result_status

  if result_output=$(
    HOME="$FIXTURE_DIR" \
    KRAG_VENV="$FIXTURE_DIR/venv" \
    "$BASH_BIN" -c '
      ok() { printf "STUB_OK: %s\n" "$*"; }
      fail() { printf "STUB_FAIL: %s\n" "$*"; }
      MISSING_CMDS=()
      source "$1"
    ' _ "$SETUP_SCRIPT" 2>&1
  ); then
    result_status=0
  else
    result_status=$?
  fi

  printf -v "$output_var" '%s' "$result_output"
  printf -v "$status_var" '%s' "$result_status"
}

mapping_count() {
  local key="$1"

  grep -Ec "^[[:space:]]*(\"${key}\"|${key}):[[:space:]]*" "$CONFIG_PATH" || true
}

has_mapping() {
  local key="$1"
  local value="$2"

  grep -Eq "^[[:space:]]*(\"${key}\"|${key}):[[:space:]]*(\"${value}\"|${value})([[:space:]]|$)" "$CONFIG_PATH"
}

setup_generates_local_documents_dir() {
  local output
  local status

  create_fixture
  run_setup output status

  [ "$status" -eq 0 ] &&
    [ -f "$CONFIG_PATH" ] &&
    grep -Fq "documents_dir: \"${FIXTURE_DIR}/.local/share/knowledge-rag/documents\"" "$CONFIG_PATH" &&
    ! grep -Fq '/pcloud/obsidian' "$CONFIG_PATH"
}

setup_replaces_existing_absolute_documents_dir_only() {
  local output
  local status
  local old_path
  local original_content
  local expected_content

  create_fixture
  old_path="${FIXTURE_DIR}/pcloud/obsidian"
  original_content=$(printf '# keep this comment\npaths:\n    documents_dir: "%s"\n    data_dir: "./data" # keep this setting\ncategory_mappings:\n    "sessions": "sessions"\n    "knowledge": "knowledge"\n    "lessons-learned": "lessons-learned"\n' "$old_path")
  expected_content=$(printf '# keep this comment\npaths:\n    documents_dir: "%s"\n    data_dir: "./data" # keep this setting\ncategory_mappings:\n    "sessions": "sessions"\n    "knowledge": "knowledge"\n    "lessons-learned": "lessons-learned"\n' "${FIXTURE_DIR}/.local/share/knowledge-rag/documents")
  write_config "$original_content"

  run_setup output status

  [ "$status" -eq 0 ] &&
    [ "$(<"$CONFIG_PATH")" = "$expected_content" ]
}

setup_replaces_existing_tilde_documents_dir_only() {
  local output
  local status
  local original_content
  local expected_content

  create_fixture
  original_content=$(printf '# tilde path comment\npaths:\n  documents_dir: "~/pcloud/obsidian"\n  data_dir: "./data"\ncategory_mappings:\n  "sessions": "sessions"\n  "knowledge": "knowledge"\n  "lessons-learned": "lessons-learned"\n')
  expected_content=$(printf '# tilde path comment\npaths:\n  documents_dir: "%s"\n  data_dir: "./data"\ncategory_mappings:\n  "sessions": "sessions"\n  "knowledge": "knowledge"\n  "lessons-learned": "lessons-learned"\n' "${FIXTURE_DIR}/.local/share/knowledge-rag/documents")
  write_config "$original_content"

  run_setup output status

  [ "$status" -eq 0 ] &&
    [ "$(<"$CONFIG_PATH")" = "$expected_content" ]
}

setup_preserves_custom_documents_dir_and_warns() {
  local output
  local status
  local original_content

  create_fixture
  original_content=$(printf '# custom path must remain\npaths:\n  documents_dir: "/custom/path"\n  data_dir: "./data"\ncategory_mappings:\n  "sessions": "sessions"\n  "knowledge": "knowledge"\n  "lessons-learned": "lessons-learned"\n')
  write_config "$original_content"

  run_setup output status

  [ "$(<"$CONFIG_PATH")" = "$original_content" ] &&
    grep -Eiq 'STUB_FAIL:|warning|warn|警告|変更しません|custom|カスタム' <<<"$output"
}

setup_adds_category_mappings_when_missing() {
  local output
  local status

  create_fixture
  write_config "$(printf '# category mapping comment\npaths:\n  documents_dir: \"%s\"\n' "${FIXTURE_DIR}/.local/share/knowledge-rag/documents")"

  run_setup output status

  [ "$status" -eq 0 ] &&
    has_mapping sessions sessions &&
    has_mapping knowledge knowledge &&
    has_mapping lessons-learned lessons-learned
}

setup_expands_empty_category_mappings_to_three_keys() {
  local output
  local status

  create_fixture
  write_config "$(printf 'paths:\n  documents_dir: \"%s\"\ncategory_mappings: {}\n' "${FIXTURE_DIR}/.local/share/knowledge-rag/documents")"

  run_setup output status

  [ "$status" -eq 0 ] &&
    ! grep -Fq 'category_mappings: {}' "$CONFIG_PATH" &&
    has_mapping sessions sessions &&
    has_mapping knowledge knowledge &&
    has_mapping lessons-learned lessons-learned
}

setup_preserves_nonempty_category_mapping_and_adds_missing_keys() {
  local output
  local status

  create_fixture
  write_config "$(printf 'paths:\n  documents_dir: \"%s\"\ncategory_mappings:\n    "custom": "custom"\n    "knowledge": "legacy-knowledge"\n' "${FIXTURE_DIR}/.local/share/knowledge-rag/documents")"

  run_setup output status

  [ "$status" -eq 0 ] &&
    has_mapping custom custom &&
    has_mapping knowledge legacy-knowledge &&
    has_mapping sessions sessions &&
    has_mapping lessons-learned lessons-learned &&
    [ "$(mapping_count custom)" -eq 1 ] &&
    [ "$(mapping_count knowledge)" -eq 1 ]
}

setup_is_idempotent_and_preserves_yaml_layout() {
  local output
  local status
  local first_content
  local old_path

  create_fixture
  old_path="${FIXTURE_DIR}/pcloud/obsidian"
  write_config "$(printf '# keep layout and comments\npaths:\n    documents_dir: "%s"\n    data_dir: "./data" # preserve inline comment\n# mapping comment\ncategory_mappings:\n    "custom": "custom"\n' "$old_path")"

  run_setup output status
  [ "$status" -eq 0 ] || return 1
  first_content="$(<"$CONFIG_PATH")"

  run_setup output status

  [ "$status" -eq 0 ] &&
    [ "$(<"$CONFIG_PATH")" = "$first_content" ] &&
    grep -Fq "documents_dir: \"${FIXTURE_DIR}/.local/share/knowledge-rag/documents\"" "$CONFIG_PATH" &&
    grep -Fq '# keep layout and comments' "$CONFIG_PATH" &&
    grep -Fq 'data_dir: "./data" # preserve inline comment' "$CONFIG_PATH" &&
    grep -Fq '# mapping comment' "$CONFIG_PATH" &&
    grep -Eq '^    "sessions":' "$CONFIG_PATH" &&
    grep -Eq '^    "knowledge":' "$CONFIG_PATH" &&
    grep -Eq '^    "lessons-learned":' "$CONFIG_PATH" &&
    [ "$(mapping_count sessions)" -eq 1 ] &&
    [ "$(mapping_count knowledge)" -eq 1 ] &&
    [ "$(mapping_count lessons-learned)" -eq 1 ]
}

make_fake_llm() {
  local llm_path="$FIXTURE_DIR/.local/share/knowledge-rag/venv/bin/llm"

  mkdir -p "$(dirname "$llm_path")"
  printf '%s\n' \
    "#!$BASH_BIN" \
    'set -euo pipefail' \
    'log_file="$HOME/.fake-llm-calls.log"' \
    'count_file="$HOME/.fake-llm-count"' \
    'printf "%s\n" "KNOWLEDGE_RAG_DIR=${KNOWLEDGE_RAG_DIR:-}" >> "$log_file"' \
    'cat >> "$log_file"' \
    'printf "%s\n" "---" >> "$log_file"' \
    'if [[ -f "$count_file" ]]; then count=$(<"$count_file"); else count=0; fi' \
    'count=$((count + 1))' \
    'printf "%s\n" "$count" > "$count_file"' \
    'if [[ "$count" -eq 1 ]]; then printf "%s\n" "${FAKE_LLM_SEARCH_RESULT:-NONE}"; else printf "%s\n" registered; fi' \
    >"$llm_path"
  chmod +x "$llm_path"
}

run_auto_promote() {
  local output_var="$1"
  local status_var="$2"
  local session_file="$3"
  local search_result="${4:-NONE}"
  local result_output
  local result_status

  if result_output=$(
    HOME="$FIXTURE_DIR" \
    KRAG_DISTILL_MODEL=test-model \
    FAKE_LLM_SEARCH_RESULT="$search_result" \
    "$BASH_BIN" "$AUTO_PROMOTE_SCRIPT" "$session_file" 2>&1
  ); then
    result_status=0
  else
    result_status=$?
  fi

  printf -v "$output_var" '%s' "$result_output"
  printf -v "$status_var" '%s' "$result_status"
}

auto_promote_does_not_skip_when_pcloud_is_unmounted() {
  local output
  local status
  local session_file

  create_fixture
  make_fake_llm
  session_file="$FIXTURE_DIR/session.md"
  printf '%s\n' '# test session' 'local knowledge' >"$session_file"

  run_auto_promote output status "$session_file"

  [ "$status" -eq 0 ] &&
    [ -s "$FIXTURE_DIR/.fake-llm-calls.log" ] &&
    grep -Fq 'KNOWLEDGE_RAG_DIR='"$FIXTURE_DIR"'/.local/share/knowledge-rag' "$FIXTURE_DIR/.fake-llm-calls.log" &&
    ! grep -Fq 'pCloud 未マウント' <<<"$output"
}

auto_promote_copies_and_registers_in_local_knowledge_dir() {
  local output
  local status
  local session_file
  local destination

  create_fixture
  make_fake_llm
  session_file="$FIXTURE_DIR/session-to-promote.md"
  destination="$FIXTURE_DIR/.local/share/knowledge-rag/documents/knowledge/session-to-promote.md"
  printf '%s\n' '# promoted session' 'knowledge body' >"$session_file"

  run_auto_promote output status "$session_file" 'sessions/similar.md'

  [ "$status" -eq 0 ] &&
    [ -f "$destination" ] &&
    [ "$(<"$destination")" = "$(<"$session_file")" ] &&
    grep -Fq 'filepath: knowledge/session-to-promote.md' "$FIXTURE_DIR/.fake-llm-calls.log" &&
    grep -Fq 'KNOWLEDGE_RAG_DIR='"$FIXTURE_DIR"'/.local/share/knowledge-rag' "$FIXTURE_DIR/.fake-llm-calls.log" &&
    [ ! -e "$FIXTURE_DIR/pcloud" ]
}

run_prune() {
  local output_var="$1"
  local status_var="$2"
  local result_output
  local result_status

  if result_output=$(
    HOME="$FIXTURE_DIR" \
    KRAG_PRUNE_RETRY=0 \
    "$BASH_BIN" "$PRUNE_SCRIPT" 2>&1
  ); then
    result_status=0
  else
    result_status=$?
  fi

  printf -v "$output_var" '%s' "$result_output"
  printf -v "$status_var" '%s' "$result_status"
}

make_fake_curl_down() {
  local curl_path="$FIXTURE_DIR/bin/curl"

  mkdir -p "$(dirname "$curl_path")"
  printf '%s\n' \
    "#!$BASH_BIN" \
    'exit 1' \
    >"$curl_path"
  chmod +x "$curl_path"
}

prune_processes_local_documents_without_pcloud_queue() {
  local output
  local status
  local docs_dir
  local old_file
  local archive_dir

  create_fixture
  docs_dir="$FIXTURE_DIR/.local/share/knowledge-rag/documents/sessions"
  archive_dir="$FIXTURE_DIR/.local/share/knowledge-rag/archive/sessions"
  old_file="$docs_dir/old-session.md"
  mkdir -p "$docs_dir"
  printf '%s\n' '# old session' >"$old_file"
  touch -d '40 days ago' "$old_file"

  run_prune output status

  [ "$status" -eq 0 ] &&
    [ ! -f "$old_file" ] &&
    find "$archive_dir" -maxdepth 1 -type f -name '*-old-session.md' -print -quit | grep -q . &&
    [ ! -e "$FIXTURE_DIR/pcloud" ] &&
    [ ! -d "$FIXTURE_DIR/.claude/hooks/queue/knowledge-prune" ]
}

write_distill_transcript() {
  local transcript_file="$1"

  printf '%s\n' \
    '{"type":"user","content":"Please remember that local documents are stored under knowledge-rag."}' \
    '{"type":"assistant","content":"Recorded the local documents path decision."}' \
    >"$transcript_file"
}

run_knowledge_distill() {
  local output_var="$1"
  local status_var="$2"
  local transcript_file="$3"
  local result_output
  local result_status
  local input

  input=$(jq -n \
    --arg transcript_path "$transcript_file" \
    --arg cwd "$FIXTURE_DIR/project" \
    '{"transcript_path":$transcript_path,"cwd":$cwd}')

  if result_output=$(
    HOME="$FIXTURE_DIR" \
    PATH="$FIXTURE_DIR/bin:$PATH" \
    "$BASH_BIN" "$KNOWLEDGE_DISTILL_SCRIPT" <<<"$input" 2>&1
  ); then
    result_status=0
  else
    result_status=$?
  fi

  printf -v "$output_var" '%s' "$result_output"
  printf -v "$status_var" '%s' "$result_status"
}

knowledge_distill_uses_local_sessions_without_pcloud_mount() {
  local output
  local status
  local transcript_file
  local queue_file

  create_fixture
  make_fake_curl_down
  mkdir -p "$FIXTURE_DIR/project"
  transcript_file="$FIXTURE_DIR/transcript.jsonl"
  write_distill_transcript "$transcript_file"

  run_knowledge_distill output status "$transcript_file"
  queue_file=$(find "$FIXTURE_DIR/.claude/hooks/queue/knowledge-distill" -maxdepth 1 -type f -name '*.json' -print -quit 2>/dev/null || true)

  [ "$status" -eq 0 ] &&
    [ -d "$FIXTURE_DIR/.local/share/knowledge-rag/documents/sessions" ] &&
    [ -d "$FIXTURE_DIR/.local/share/knowledge-rag/documents/sessions/raw" ] &&
    [ ! -e "$FIXTURE_DIR/pcloud" ] &&
    [ -n "$queue_file" ] &&
    jq -e '.reason == "ollama"' "$queue_file" >/dev/null &&
    ! grep -Fq 'pCloud 未マウント' <<<"$output"
}

run_lessons_learned_distill() {
  local output_var="$1"
  local status_var="$2"
  local transcript_file="$3"
  local result_output
  local result_status
  local input

  input=$(jq -n \
    --arg transcript_path "$transcript_file" \
    --arg cwd "$FIXTURE_DIR/project" \
    '{"transcript_path":$transcript_path,"cwd":$cwd}')

  if result_output=$(
    HOME="$FIXTURE_DIR" \
    PATH="$FIXTURE_DIR/bin:$PATH" \
    "$BASH_BIN" "$LESSONS_LEARNED_DISTILL_SCRIPT" <<<"$input" 2>&1
  ); then
    result_status=0
  else
    result_status=$?
  fi

  printf -v "$output_var" '%s' "$result_output"
  printf -v "$status_var" '%s' "$result_status"
}

lessons_learned_distill_uses_local_documents_without_pcloud_mount() {
  local output
  local status
  local transcript_file
  local queue_file

  create_fixture
  make_fake_curl_down
  mkdir -p "$FIXTURE_DIR/project"
  transcript_file="$FIXTURE_DIR/transcript.jsonl"
  write_distill_transcript "$transcript_file"

  run_lessons_learned_distill output status "$transcript_file"
  queue_file=$(find "$FIXTURE_DIR/.claude/hooks/queue/lessons-learned" -maxdepth 1 -type f -name '*.json' -print -quit 2>/dev/null || true)

  [ "$status" -eq 0 ] &&
    [ -d "$FIXTURE_DIR/.local/share/knowledge-rag/documents/lessons-learned" ] &&
    [ ! -e "$FIXTURE_DIR/pcloud" ] &&
    [ -n "$queue_file" ] &&
    jq -e '.reason == "ollama"' "$queue_file" >/dev/null &&
    ! grep -Fq 'pCloud 未マウント' <<<"$output"
}

install_bash_probe() {
  local probe_path="$FIXTURE_DIR/bin/bash"

  mkdir -p "$(dirname "$probe_path")"
  printf '%s\n' \
    "#!$BASH_BIN" \
    'if [[ "$*" == *knowledge-distill.sh* ]]; then' \
    '  printf "%s\n" "$*" >> "$HOME/.knowledge-distill-invocations"' \
    'fi' \
    "exec \"$BASH_BIN\" \"\$@\"" \
    >"$probe_path"
  chmod +x "$probe_path"
}

run_check_queue() {
  local output_var="$1"
  local status_var="$2"
  local result_output
  local result_status

  if result_output=$(
    HOME="$FIXTURE_DIR" \
    PATH="$FIXTURE_DIR/bin:$PATH" \
    "$BASH_BIN" "$CHECK_QUEUE_SCRIPT" <<< '{}' 2>&1
  ); then
    result_status=0
  else
    result_status=$?
  fi

  printf -v "$output_var" '%s' "$result_output"
  printf -v "$status_var" '%s' "$result_status"
}

check_queue_starts_distill_drain_without_mount_gate() {
  local output
  local status
  local queue_dir
  local attempt

  create_fixture
  install_bash_probe
  queue_dir="$FIXTURE_DIR/.claude/hooks/queue/knowledge-distill"
  mkdir -p "$queue_dir"
  printf '%s\n' '{"transcript_path":"","cwd":"","reason":"pending","retry_count":0}' >"$queue_dir/item.json"

  run_check_queue output status

  for ((attempt = 0; attempt < 50; attempt += 1)); do
    [ -s "$FIXTURE_DIR/.knowledge-distill-invocations" ] && break
    sleep 0.05
  done

  [ "$status" -eq 0 ] &&
    [ -s "$FIXTURE_DIR/.knowledge-distill-invocations" ] &&
    grep -Fq 'knowledge-distill.sh' "$FIXTURE_DIR/.knowledge-distill-invocations"
}

bash_syntax() {
  "$BASH_BIN" -n \
    "$TEST_SCRIPT" \
    "$SETUP_SCRIPT" \
    "$AUTO_PROMOTE_SCRIPT" \
    "$PRUNE_SCRIPT" \
    "$CHECK_QUEUE_SCRIPT" \
    "$KNOWLEDGE_DISTILL_SCRIPT" \
    "$LESSONS_LEARNED_DISTILL_SCRIPT"
}

shellcheck_pass() {
  if ! command -v shellcheck >/dev/null 2>&1; then
    TEST_SKIP_REASON="shellcheck not installed"
    return 2
  fi
  shellcheck -S error "$TEST_SCRIPT"
}

remember_has_no_pcloud_documents_path() {
  ! grep -Fq 'pcloud/obsidian' "$REMEMBER_SKILL"
}

remember_uses_local_output_and_completion_path() {
  grep -Fq 'OUTPUT="$HOME/.local/share/knowledge-rag/documents/knowledge/{filename}.md"' "$REMEMBER_SKILL" &&
    grep -Fq '例: $HOME/.local/share/knowledge-rag/documents/knowledge/{filename}.md に保存・登録しました。' "$REMEMBER_SKILL"
}

changed_scripts_do_not_create_pcloud_paths() {
  local output
  local status
  local session_file

  create_fixture

  run_setup output status
  [ "$status" -eq 0 ] && [ ! -e "$FIXTURE_DIR/pcloud" ] || return 1

  make_fake_llm
  session_file="$FIXTURE_DIR/common-session.md"
  printf '%s\n' '# common test session' >"$session_file"
  run_auto_promote output status "$session_file"
  [ "$status" -eq 0 ] && [ ! -e "$FIXTURE_DIR/pcloud" ] || return 1

  run_prune output status
  [ "$status" -eq 0 ] && [ ! -e "$FIXTURE_DIR/pcloud" ] || return 1

  make_fake_curl_down
  write_distill_transcript "$session_file"
  run_knowledge_distill output status "$session_file"
  [ "$status" -eq 0 ] && [ ! -e "$FIXTURE_DIR/pcloud" ] || return 1

  run_lessons_learned_distill output status "$session_file"
  [ "$status" -eq 0 ] && [ ! -e "$FIXTURE_DIR/pcloud" ] || return 1

  run_check_queue output status
  [ "$status" -eq 0 ] && [ ! -e "$FIXTURE_DIR/pcloud" ]
}

run_test_or_skip "shellcheck -S error がテストスクリプトで通る" shellcheck_pass
run_test "bash -n が変更対象の全 shell script とテストで通る" bash_syntax

run_jq_test "新規 HOME で config.yaml の documents_dir をローカル絶対パスで生成" setup_generates_local_documents_dir
run_jq_test "既存の旧絶対 documents_dir だけを新パスへ置換" setup_replaces_existing_absolute_documents_dir_only
run_jq_test "既存の旧チルダ documents_dir だけを新パスへ置換" setup_replaces_existing_tilde_documents_dir_only
run_jq_test "カスタム documents_dir を保持して setup が警告する" setup_preserves_custom_documents_dir_and_warns
run_jq_test "category_mappings がない config に3キーを追加" setup_adds_category_mappings_when_missing
run_jq_test "空の category_mappings を3キーへ展開" setup_expands_empty_category_mappings_to_three_keys
run_jq_test "非空の category_mappings を保持して不足キーだけ追加" setup_preserves_nonempty_category_mapping_and_adds_missing_keys
run_jq_test "setup の再実行が冪等で YAML のインデントとコメントを保持" setup_is_idempotent_and_preserves_yaml_layout

run_jq_test "auto-promote が pCloud 未マウントでも早期スキップしない" auto_promote_does_not_skip_when_pcloud_is_unmounted
run_jq_test "auto-promote のコピー先・登録先がローカル knowledge-rag" auto_promote_copies_and_registers_in_local_knowledge_dir
run_jq_test "pCloud 未マウントでも prune がローカル documents を TTL 処理しキューを作らない" prune_processes_local_documents_without_pcloud_queue
run_jq_test "pCloud 未マウントでも knowledge-distill がローカル sessions を使い pCloud 保留にしない" knowledge_distill_uses_local_sessions_without_pcloud_mount
run_jq_test "pCloud 未マウントでも lessons-learned がローカル documents を使い pCloud 保留にしない" lessons_learned_distill_uses_local_documents_without_pcloud_mount
run_jq_test "pCloud 未マウントでも check-queue が knowledge-distill drain を起動" check_queue_starts_distill_drain_without_mount_gate

run_test "remember SKILL.md に旧 pCloud 保存先が残っていない" remember_has_no_pcloud_documents_path
run_test "remember SKILL.md の OUTPUT と完了報告がローカル保存先" remember_uses_local_output_and_completion_path
run_jq_test "変更対象スクリプトが一時 HOME の pCloud 配下を作成しない" changed_scripts_do_not_create_pcloud_paths

echo ""
echo "Results: ${PASS} passed, ${FAIL} failed, ${SKIP} skipped"

if [ "$FAIL" -gt 0 ]; then
  exit 1
fi
