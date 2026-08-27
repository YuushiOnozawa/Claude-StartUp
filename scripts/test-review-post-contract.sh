#!/usr/bin/env bash
# scripts/test-review-post-contract.sh — /review-post 共通契約の参照テスト
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
POST_REF="skills/flow-common/references/review-post.md"
PASS=0
FAIL=0
TEST_ROOT="$(mktemp -d)"

cleanup() {
  rm -rf -- "$TEST_ROOT"
}
trap cleanup EXIT

record_result() {
  local description="$1"
  local status="$2"
  if [[ "$status" -eq 0 ]]; then
    echo "PASS: $description"
    ((PASS++)) || true
  else
    echo "FAIL: $description"
    ((FAIL++)) || true
  fi
}

extract_code_block() {
  local heading="$1"
  local source_file="$2"
  local output_file="$3"
  local block_number="${4:-1}"
  awk -v heading="$heading" -v block_number="$block_number" '
    index($0, heading) == 1 { found=1; next }
    found && /^```bash$/ {
      block_count++
      in_block=(block_count == block_number)
      next
    }
    found && in_block && /^```$/ { exit }
    found && in_block { print }
  ' "$source_file" >"$output_file"
}

POST_SCRIPT="$TEST_ROOT/review-post.sh"
extract_code_block "## 実行手順" "$REPO_ROOT/$POST_REF" "$POST_SCRIPT"
if [[ -s "$POST_SCRIPT" ]]; then
  record_result "review-post.md の実行コードブロックを抽出できる" 0
else
  record_result "review-post.md の実行コードブロックを抽出できる" 1
fi
if bash -n "$POST_SCRIPT"; then
  record_result "review-post 実行コードブロックの構文が正しい" 0
else
  record_result "review-post 実行コードブロックの構文が正しい" 1
fi

STUB_DIR="$TEST_ROOT/bin"
GH_LOG="$TEST_ROOT/gh.log"
mkdir -p "$STUB_DIR"
printf '%s\n' \
  '#!/usr/bin/env bash' \
  'set -u' \
  'endpoint=""' \
  'body=""' \
  'path_arg=""' \
  'line_arg=""' \
  'side_arg=""' \
  'take_f=false' \
  'for arg in "$@"; do' \
  '  if [[ "$take_f" == true ]]; then' \
  '    [[ "$arg" == body=* ]] && body="${arg#body=}"' \
  '    [[ "$arg" == path=* ]] && path_arg="${arg#path=}"' \
  '    [[ "$arg" == side=* ]] && side_arg="${arg#side=}"' \
  '    take_f=false' \
  '    continue' \
  '  fi' \
  '  [[ "$arg" == repos/* ]] && endpoint="$arg"' \
  '  [[ "$arg" == path=* ]] && path_arg="${arg#path=}"' \
  '  [[ "$arg" == line=* ]] && line_arg="${arg#line=}"' \
  '  [[ "$arg" == side=* ]] && side_arg="${arg#side=}"' \
  '  [[ "$arg" == "-f" ]] && take_f=true' \
  'done' \
  'case "$endpoint" in' \
  '  */pulls/*/comments) kind=inline ;;' \
  '  */issues/*/comments) kind=issue ;;' \
  '  *) kind=other ;;' \
  'esac' \
  'printf "ENDPOINT:%s\\n" "$endpoint" >> "$GH_LOG"' \
  'printf "KIND:%s\\n" "$kind" >> "$GH_LOG"' \
  'printf "PATH:%s\\n" "$path_arg" >> "$GH_LOG"' \
  'printf "LINE:%s\\n" "$line_arg" >> "$GH_LOG"' \
  'printf "SIDE:%s\\n" "$side_arg" >> "$GH_LOG"' \
  'printf "BODY:%s\\n" "$body" >> "$GH_LOG"' \
  'if [[ "${GH_MODE:-}" == summary-fail && "$kind" == issue ]]; then' \
  '  echo "HTTP 500" >&2' \
  '  exit 1' \
  'fi' \
  'if [[ "${GH_MODE:-}" == 422 && "$kind" == inline ]]; then' \
  '  echo "HTTP 422 Unprocessable Entity" >&2' \
  '  exit 1' \
  'fi' \
  'printf "%s\n" "https://stub.invalid/$kind"' \
  'exit 0' >"$STUB_DIR/gh"
chmod +x "$STUB_DIR/gh"

# grounding 出力の契約検証を GitHub API なしで行うため、対象リポジトリ解決と grounder を一時的に差し替える。
GROUND_STUB_ROOT="$TEST_ROOT/ground-root"
GROUND_STUB_BIN="$TEST_ROOT/ground-bin"
mkdir -p "$GROUND_STUB_ROOT/scripts" "$GROUND_STUB_BIN"
printf '%s\n' \
  '#!/usr/bin/env bash' \
  'if [[ "$*" == "rev-parse --show-toplevel" ]]; then' \
  '  printf "%s\n" "$GROUND_STUB_ROOT"' \
  '  exit 0' \
  'fi' \
  'exec /usr/bin/git "$@"' >"$GROUND_STUB_BIN/git"
chmod +x "$GROUND_STUB_BIN/git"
printf '%s\n' \
  '#!/usr/bin/env bash' \
  'case "${GROUND_STUB_MODE:-}" in' \
  '  all-null) : >"${GROUND_STUB_LOG:-/dev/null}"; exit 99 ;;' \
  '  ground-missing) printf "%s\n" "{\"schema_version\":\"1\",\"anchors\":[]}"; exit 0 ;;' \
  '  ground-unknown) printf "%s\n" "{\"schema_version\":\"1\",\"anchors\":[{\"id\":\"G-001\",\"anchored_path\":\"a.sh\",\"anchored_line\":1,\"side\":\"RIGHT\",\"anchor_status\":\"partial\"}]}"; exit 0 ;;' \
  '  ground-invalid) printf "%s\n" "{\"schema_version\":\"1\",\"anchors\":[{\"id\":\"G-001\",\"anchored_path\":\"\",\"anchored_line\":0,\"side\":\"RIGHT\",\"anchor_status\":\"ok\"},{\"id\":\"G-002\",\"anchored_path\":\"b.sh\",\"anchored_line\":1,\"side\":\"CENTER\",\"anchor_status\":\"ok\"}]}"; exit 0 ;;' \
  '  ground-all) printf "%s\n" "{\"schema_version\":\"1\",\"anchors\":[{\"id\":\"G-002\",\"anchored_path\":\"b.sh\",\"anchored_line\":1,\"side\":\"RIGHT\",\"anchor_status\":\"ok\"},{\"id\":\"G-001\",\"anchored_path\":\"a.sh\",\"anchored_line\":1,\"side\":\"RIGHT\",\"anchor_status\":\"ok\"}]}"; exit 0 ;;' \
  '  ground-invalid-position) printf "%s\n" "{\"schema_version\":\"1\",\"anchors\":[{\"id\":\"G-002\",\"anchored_path\":\"a.sh\",\"anchored_line\":2,\"side\":\"RIGHT\",\"anchor_status\":\"ok\"},{\"id\":\"G-001\",\"anchored_path\":\"outside.sh\",\"anchored_line\":1,\"side\":\"RIGHT\",\"anchor_status\":\"ok\"}]}"; exit 0 ;;' \
  'esac' \
  'exit 99' >"$GROUND_STUB_ROOT/scripts/magi-ground-findings.sh"
chmod +x "$GROUND_STUB_ROOT/scripts/magi-ground-findings.sh"

make_case() {
  local name="$1"
  CASE_DIR="$TEST_ROOT/$name"
  mkdir -p "$CASE_DIR"
  : >"$CASE_DIR/pr.diff"
}

write_request() {
  local output="$1"
  local engine="$2"
  local artifact="$3"
  local adjudication="$4"
  local diff="$5"
  local post_inline="$6"
  local block_layer="$7"
  local normalized="$8"
  local finding_list="$9"
  local result_path="${10}"
  jq -n \
    --arg engine "$engine" \
    --arg artifact "$artifact" \
    --arg adjudication "$adjudication" \
    --arg diff "$diff" \
    --argjson post_inline "$post_inline" \
    --arg block_layer "$block_layer" \
    --arg normalized "$normalized" \
    --arg finding_list "$finding_list" \
    --arg result_path "$result_path" \
    '{schema_version:"1", artifact_type:"review-post-request", engine:$engine,
      pr:{owner:"owner", repo:"repo", number:7, head_sha:"0123456789abcdef"},
      inputs:{findings_artifact:(if $artifact == "" then null else $artifact end),
              adjudication_result:(if $adjudication == "" then null else $adjudication end), diff:$diff},
      engine_state:{post_inline:$post_inline,
        block_layer:(if $block_layer == "" then null else $block_layer end),
        audit_note:null, importance_note:null, artifact_note:null,
        normalized_results:(if $normalized == "" then null else $normalized end),
        finding_list:(if $finding_list == "" then null else $finding_list end)},
      result_path:$result_path}' >"$output"
}

run_post() {
  local request="$1"
  local mode="${2:-}"
  local post_path="$STUB_DIR:$PATH"
  local ground_mode=""
  local gh_mode="$mode"
  if [[ "$mode" == ground-* || "$mode" == all-null ]]; then
    post_path="$GROUND_STUB_BIN:$STUB_DIR:$PATH"
    ground_mode="$mode"
    gh_mode=""
  fi
  : >"$GH_LOG"
  rm -f -- "$TEST_ROOT/grounder-called.log"
  if PATH="$post_path" GROUND_STUB_ROOT="$GROUND_STUB_ROOT" GROUND_STUB_MODE="$ground_mode" \
    GROUND_STUB_LOG="$TEST_ROOT/grounder-called.log" GH_LOG="$GH_LOG" GH_MODE="$gh_mode" bash "$POST_SCRIPT" "$request" \
    >"$TEST_ROOT/stdout" 2>"$TEST_ROOT/stderr"; then
    POST_EXIT=0
  else
    POST_EXIT=$?
  fi
}

count_kind() {
  local kind="$1"
  grep -c "^KIND:$kind$" "$GH_LOG" 2>/dev/null || true
}

assert_result() {
  local file="$1"
  local filter="$2"
  jq -e "$filter" "$file" >/dev/null 2>&1
}

# 正常 MAGI: body/evidence の特殊文字、null-line 分離、ID join、original/anchored 分離、422 fallback。
make_case magi-normal
printf '%s\n' \
  'diff --git a/old.sh b/new.sh' \
  'similarity index 80%' \
  'rename from old.sh' \
  'rename to new.sh' \
  '--- a/old.sh' \
  '+++ b/new.sh' \
  '@@ -1 +1 @@' \
  '-old' \
  '+echo "a" | sed' >"$CASE_DIR/pr.diff"
jq -n \
  --arg body $'Problem\n| quote "x"\n```\necho "a" | sed\n```' \
  '{schema_version:"1",engine:"magi",detection_status:"complete",failed_personas:[],findings:[
    {id:"M-001",source_persona:"MELCHIOR",path:"old.sh",line:1,headline:"quoted",body:$body,evidence:"echo \"a\" | sed"},
    {id:"M-002",source_persona:"CASPER",path:"old.sh",line:null,headline:"unknown line",body:"line is unknown",evidence:null}]}' \
  >"$CASE_DIR/artifact.json"
jq -n '{schema_version:"1",artifact_type:"review-adjudication",validity_global_failure:false,results:[
  {id:"M-002",verdict:"false_positive",importance:null,importance_status:"not_applicable",reported_gate:null,final_gate:"defer"},
  {id:"M-001",verdict:"valid",importance:"HIGH",importance_status:"ok",reported_gate:null,final_gate:"block"}]}' \
  >"$CASE_DIR/adjudication.json"
write_request "$CASE_DIR/request.json" magi "$CASE_DIR/artifact.json" "$CASE_DIR/adjudication.json" \
  "$CASE_DIR/pr.diff" true "" "" "" "$CASE_DIR/result.json"
run_post "$CASE_DIR/request.json" 422
if [[ "$POST_EXIT" -eq 0 ]] \
  && assert_result "$CASE_DIR/result.json" '.status == "posted" and .counts.inline_posted == 0 and .counts.fallback_posted == 1 and (.items[] | select(.id=="M-001") | .delivery == "pr_comment")' \
  && [[ "$(count_kind inline)" -eq 1 ]] && [[ "$(count_kind issue)" -eq 2 ]] \
  && grep -Fq 'PATH:new.sh' "$GH_LOG" && grep -Fq 'old.sh:1' "$GH_LOG"; then
  result=0
else
  result=1
fi
record_result "正常経路は特殊文字を保ち、ID join と original/anchored 分離、422 fallback を行う" "$result"

# Codex CASPER: importance:null でも final_gate=block を投稿対象にし、evidence:null は unverified にする。
make_case codex-casper
printf '%s\n' \
  'diff --git a/src/casper.sh b/src/casper.sh' \
  '--- a/src/casper.sh' \
  '+++ b/src/casper.sh' \
  '@@ -0,0 +1 @@' \
  '+echo CASPER' >"$CASE_DIR/pr.diff"
jq -n '{schema_version:"1",engine:"codex",detection_status:"complete",failed_personas:[],findings:[
  {id:"C-001",source_persona:"CASPER",path:"src/casper.sh",line:1,headline:"rule",body:"rule finding",evidence:null}]}' \
  >"$CASE_DIR/artifact.json"
jq -n '{schema_version:"1",artifact_type:"review-adjudication",validity_global_failure:false,results:[
  {id:"C-001",verdict:"valid",importance:null,importance_status:"not_applicable",reported_gate:"block",final_gate:"block"}]}' \
  >"$CASE_DIR/adjudication.json"
write_request "$CASE_DIR/request.json" codex "$CASE_DIR/artifact.json" "$CASE_DIR/adjudication.json" \
  "$CASE_DIR/pr.diff" true "" "" "" "$CASE_DIR/result.json"
run_post "$CASE_DIR/request.json"
if [[ "$POST_EXIT" -eq 0 ]] \
  && assert_result "$CASE_DIR/result.json" '.counts.block == 1 and .counts.inline_posted == 1 and .items[0].importance == null and .items[0].anchor_status == "unverified" and .items[0].delivery == "inline"' \
  && [[ "$(count_kind inline)" -eq 1 ]] \
  && grep -Fq '位置は未検証（evidence引用なし、original_lineの実在確認のみ）' "$GH_LOG" \
  && grep -Fq 'UNRATED' "$GH_LOG"; then
  result=0
else
  result=1
fi
record_result "Codex CASPER の importance:null かつ final_gate:block を除外せず unverified として投稿する" "$result"

# post_inline=false の audit: summary は常に投稿し、ステップ7相当は一切呼ばない。
make_case audit-no-inline
printf '%s\n' 'diff --git a/a.sh b/a.sh' '--- a/a.sh' '+++ b/a.sh' '@@ -0,0 +1 @@' '+echo audit' >"$CASE_DIR/pr.diff"
jq -n '{schema_version:"1",engine:"magi",detection_status:"complete",failed_personas:[],findings:[
  {id:"M-010",source_persona:"MELCHIOR",path:"a.sh",line:1,headline:"audit",body:"audit body",evidence:null}]}' \
  >"$CASE_DIR/artifact.json"
jq -n '{schema_version:"1",artifact_type:"review-adjudication",validity_global_failure:false,results:[
  {id:"M-010",verdict:"valid",importance:"HIGH",importance_status:"ok",reported_gate:null,final_gate:"block"}]}' \
  >"$CASE_DIR/adjudication.json"
write_request "$CASE_DIR/request.json" magi "$CASE_DIR/artifact.json" "$CASE_DIR/adjudication.json" \
  "$CASE_DIR/pr.diff" false audit "" $'M-010: [HIGH] MELCHIOR — a.sh:1 — audit' "$CASE_DIR/result.json"
run_post "$CASE_DIR/request.json"
if [[ "$POST_EXIT" -eq 0 ]] \
  && assert_result "$CASE_DIR/result.json" '.counts.summary_only == 1 and .counts.inline_posted == 0 and .counts.fallback_posted == 0 and .items[0].delivery == "summary_only"' \
  && [[ "$(count_kind issue)" -eq 1 ]] && [[ "$(count_kind inline)" -eq 0 ]] \
  && grep -Fq '未監査の指摘一覧' "$GH_LOG" && grep -Fq 'M-010' "$GH_LOG"; then
  result=0
else
  result=1
fi
record_result "post_inline:false はサマリと指摘一覧を残し、インライン/通常PRコメントを抑止する" "$result"

# structure: artifactなし + rawありは report-only として受理し、raw を summary details にそのまま載せる。
make_case structure-raw
printf '%s\n' 'not a diff but readable' >"$CASE_DIR/pr.diff"
write_request "$CASE_DIR/request.json" magi "" "" "$CASE_DIR/pr.diff" false structure \
  $'raw | quote "x"\n```\nnot-json\n```' "" "$CASE_DIR/result.json"
run_post "$CASE_DIR/request.json"
if [[ "$POST_EXIT" -eq 0 ]] \
  && assert_result "$CASE_DIR/result.json" '.status == "report_only" and .counts.total_findings == 0 and .grounding_status == "skipped"' \
  && [[ "$(count_kind issue)" -eq 1 ]] && [[ "$(count_kind inline)" -eq 0 ]] \
  && grep -Fq '指摘の構造化に失敗したため未整形のまま一覧表示する' "$GH_LOG" \
  && grep -Fq 'not-json' "$GH_LOG"; then
  result=0
else
  result=1
fi
record_result "structure 経路は raw を summary details に埋め込み report-only で受理する" "$result"

# anchors の欠落・未知 status・不正 path/line/side は部分採用せず全件 fallback する。
make_case anchor-contract
printf '%s\n' \
  'diff --git a/a.sh b/a.sh' \
  '--- a/a.sh' \
  '+++ b/a.sh' \
  '@@ -1 +1 @@' \
  '-old a' \
  '+new a' \
  'diff --git a/b.sh b/b.sh' \
  '--- a/b.sh' \
  '+++ b/b.sh' \
  '@@ -1 +1 @@' \
  '-old b' \
  '+new b' >"$CASE_DIR/pr.diff"
jq -n '{schema_version:"1",engine:"magi",detection_status:"complete",failed_personas:[],findings:[
  {id:"G-001",source_persona:"MELCHIOR",path:"a.sh",line:1,headline:"a",body:"a",evidence:null},
  {id:"G-002",source_persona:"BALTHASAR",path:"b.sh",line:1,headline:"b",body:"b",evidence:null}]}' \
  >"$CASE_DIR/artifact.json"
jq -n '{schema_version:"1",artifact_type:"review-adjudication",validity_global_failure:false,results:[
  {id:"G-001",verdict:"valid",importance:"HIGH",importance_status:"ok",reported_gate:null,final_gate:"block"},
  {id:"G-002",verdict:"valid",importance:"MEDIUM",importance_status:"ok",reported_gate:null,final_gate:"block"}]}' \
  >"$CASE_DIR/adjudication.json"
for GROUND_CASE in ground-missing ground-unknown ground-invalid; do
  write_request "$CASE_DIR/$GROUND_CASE-request.json" magi "$CASE_DIR/artifact.json" "$CASE_DIR/adjudication.json" \
    "$CASE_DIR/pr.diff" true "" "" "" "$CASE_DIR/$GROUND_CASE-result.json"
  run_post "$CASE_DIR/$GROUND_CASE-request.json" "$GROUND_CASE"
  if [[ "$POST_EXIT" -eq 0 ]] \
    && assert_result "$CASE_DIR/$GROUND_CASE-result.json" '.grounding_note != null and .counts.fallback_posted == 2 and all(.items[]; .anchor_status == "unanchorable" and .delivery == "pr_comment")' \
    && [[ "$(count_kind issue)" -eq 3 ]] && [[ "$(count_kind inline)" -eq 0 ]]; then
    result=0
  else
    result=1
  fi
  record_result "$GROUND_CASE は anchors 不備時に全件 unanchorable fallback になる" "$result"
done

# anchors の path が diff 外、または line が diff 上でコメント不可能でも、全件 fallback する。
write_request "$CASE_DIR/ground-invalid-position-request.json" magi "$CASE_DIR/artifact.json" "$CASE_DIR/adjudication.json" \
  "$CASE_DIR/pr.diff" true "" "" "" "$CASE_DIR/ground-invalid-position-result.json"
run_post "$CASE_DIR/ground-invalid-position-request.json" ground-invalid-position
if [[ "$POST_EXIT" -eq 0 ]] \
  && assert_result "$CASE_DIR/ground-invalid-position-result.json" '.grounding_note != null and .counts.fallback_posted == 2 and all(.items[]; .anchor_status == "unanchorable" and .delivery == "pr_comment")' \
  && [[ "$(count_kind issue)" -eq 3 ]] && [[ "$(count_kind inline)" -eq 0 ]]; then
  result=0
else
  result=1
fi
record_result "diff 外 path またはコメント不可能な line の anchors は全件 unanchorable fallback になる" "$result"

# grounder の返却順が入力順と異なっても、ID join で各 finding の位置を取り違えない。
jq '.results[1].final_gate="defer"' "$CASE_DIR/adjudication.json" >"$CASE_DIR/ground-all-adjudication.json"
write_request "$CASE_DIR/ground-all-request.json" magi "$CASE_DIR/artifact.json" "$CASE_DIR/ground-all-adjudication.json" \
  "$CASE_DIR/pr.diff" true "" "" "" "$CASE_DIR/ground-all-result.json"
run_post "$CASE_DIR/ground-all-request.json" ground-all
if [[ "$POST_EXIT" -eq 0 ]] \
  && assert_result "$CASE_DIR/ground-all-result.json" '.grounding_note == null and (.items[] | select(.id == "G-001") | .anchor_status == "ok" and .delivery == "inline")' \
  && [[ "$(count_kind issue)" -eq 1 ]] && [[ "$(count_kind inline)" -eq 1 ]] \
  && grep -Fq 'PATH:a.sh' "$GH_LOG"; then
  result=0
else
  result=1
fi
record_result "grounding は anchors の返却順に依存せず ID join する" "$result"

# 全件 null-line: grounder を呼ばず、null を unanchorable として通常コメントへ退避する。
make_case all-null-line
jq -n '{schema_version:"1",engine:"magi",detection_status:"complete",failed_personas:[],findings:[
  {id:"M-020",source_persona:"MELCHIOR",path:"missing.sh",line:null,headline:"unknown",body:"unknown line",evidence:null}]}' \
  >"$CASE_DIR/artifact.json"
jq -n '{schema_version:"1",artifact_type:"review-adjudication",validity_global_failure:false,results:[
  {id:"M-020",verdict:"valid",importance:"MEDIUM",importance_status:"ok",reported_gate:null,final_gate:"block"}]}' \
  >"$CASE_DIR/adjudication.json"
write_request "$CASE_DIR/request.json" magi "$CASE_DIR/artifact.json" "$CASE_DIR/adjudication.json" \
  "$CASE_DIR/pr.diff" true "" "" "" "$CASE_DIR/result.json"
run_post "$CASE_DIR/request.json" all-null
if [[ "$POST_EXIT" -eq 0 ]] \
  && assert_result "$CASE_DIR/result.json" '.grounding_note == null and .items[0].anchor_status == "unanchorable" and .counts.fallback_posted == 1' \
  && [[ "$(count_kind issue)" -eq 2 ]] && [[ "$(count_kind inline)" -eq 0 ]] \
  && [[ ! -e "$TEST_ROOT/grounder-called.log" ]]; then
  result=0
else
  result=1
fi
record_result "全件 null-line は grounder を呼ばず unanchorable として退避する" "$result"

# 投稿対象0件: summary のみで no-op。
make_case no-findings
printf '%s\n' 'readable diff' >"$CASE_DIR/pr.diff"
printf '%s\n' '{"schema_version":"1","engine":"magi","detection_status":"complete","failed_personas":[],"findings":[]}' >"$CASE_DIR/artifact.json"
printf '%s\n' '{"schema_version":"1","artifact_type":"review-adjudication","validity_global_failure":false,"results":[]}' >"$CASE_DIR/adjudication.json"
write_request "$CASE_DIR/request.json" magi "$CASE_DIR/artifact.json" "$CASE_DIR/adjudication.json" \
  "$CASE_DIR/pr.diff" true "" "" "" "$CASE_DIR/result.json"
run_post "$CASE_DIR/request.json"
if [[ "$POST_EXIT" -eq 0 ]] \
  && assert_result "$CASE_DIR/result.json" '.status == "no_findings" and .counts.block == 0 and .counts.inline_posted == 0 and .counts.fallback_posted == 0 and .counts.not_posted == 0' \
  && [[ "$(count_kind issue)" -eq 1 ]] && [[ "$(count_kind inline)" -eq 0 ]]; then
  result=0
else
  result=1
fi
record_result "投稿対象0件は summary のみの no-op になる" "$result"

# detection_status が incomplete/unknown の artifact を complete と表示しない。
make_case detection-status
cp "$TEST_ROOT/magi-normal/pr.diff" "$CASE_DIR/pr.diff"
jq '.detection_status="incomplete" | .failed_personas=["CASPER"]' \
  "$TEST_ROOT/magi-normal/artifact.json" >"$CASE_DIR/artifact.json"
cp "$TEST_ROOT/magi-normal/adjudication.json" "$CASE_DIR/adjudication.json"
write_request "$CASE_DIR/request.json" magi "$CASE_DIR/artifact.json" "$CASE_DIR/adjudication.json" \
  "$CASE_DIR/pr.diff" true "" "" "" "$CASE_DIR/result.json"
run_post "$CASE_DIR/request.json"
if [[ "$POST_EXIT" -eq 0 ]] \
  && grep -Fq '検出状態: 検出層: incomplete' "$CASE_DIR/result.json" \
  && [[ "$(count_kind issue)" -eq 1 ]] && [[ "$(count_kind inline)" -eq 1 ]]; then
  result=0
else
  result=1
fi
record_result "detection_status incomplete は summary に状態を明記する" "$result"

expect_contract_exit() {
  local label="$1"
  local request="$2"
  run_post "$request"
  if [[ "$POST_EXIT" -eq 2 && ! -s "$GH_LOG" ]]; then
    result=0
  else
    result=1
  fi
  record_result "$label" "$result"
}

# strict_json: request / artifact / adjudication の連結 JSON を拒否する。
make_case strict-json
printf '%s\n' 'diff' >"$CASE_DIR/pr.diff"
printf '%s\n' '{"schema_version":"1","engine":"magi","detection_status":"complete","failed_personas":[],"findings":[]}' >"$CASE_DIR/artifact.json"
printf '%s\n' '{"schema_version":"1","artifact_type":"review-adjudication","validity_global_failure":false,"results":[]}' >"$CASE_DIR/adjudication.json"
write_request "$CASE_DIR/request.json" magi "$CASE_DIR/artifact.json" "$CASE_DIR/adjudication.json" \
  "$CASE_DIR/pr.diff" true "" "" "" "$CASE_DIR/result.json"
printf '%s\n%s\n' "$(<"$CASE_DIR/request.json")" "$(<"$CASE_DIR/request.json")" >"$CASE_DIR/request-concat.json"
expect_contract_exit "request の連結 JSON を strict_json で拒否する" "$CASE_DIR/request-concat.json"
printf '%s\n%s\n' "$(<"$CASE_DIR/artifact.json")" "$(<"$CASE_DIR/artifact.json")" >"$CASE_DIR/artifact-concat.json"
write_request "$CASE_DIR/artifact-request.json" magi "$CASE_DIR/artifact-concat.json" "$CASE_DIR/adjudication.json" \
  "$CASE_DIR/pr.diff" true "" "" "" "$CASE_DIR/artifact-result.json"
expect_contract_exit "findings artifact の連結 JSON を strict_json で拒否する" "$CASE_DIR/artifact-request.json"
printf '%s\n%s\n' "$(<"$CASE_DIR/adjudication.json")" "$(<"$CASE_DIR/adjudication.json")" >"$CASE_DIR/adjudication-concat.json"
write_request "$CASE_DIR/adj-request.json" magi "$CASE_DIR/artifact.json" "$CASE_DIR/adjudication-concat.json" \
  "$CASE_DIR/pr.diff" true "" "" "" "$CASE_DIR/adj-result.json"
expect_contract_exit "adjudication result の連結 JSON を strict_json で拒否する" "$CASE_DIR/adj-request.json"

# schema/type、IDの不足・余分・重複、通常経路の artifact 不在を拒否する。
mutate_request_and_expect() {
  local label="$1"
  local expression="$2"
  local request="$CASE_DIR/mutated.json"
  jq "$expression" "$CASE_DIR/request.json" >"$request"
  expect_contract_exit "$label" "$request"
}
mutate_request_and_expect "request の schema/type 違反を拒否する" '.schema_version="2" | .pr.number="7"'
mutate_request_and_expect "request の engine 不一致を拒否する" '.engine="other"'
mutate_request_and_expect "通常経路の artifact/adjudication null を拒否する" '.inputs.findings_artifact=null'
mutate_request_and_expect "structure の raw 欠落を拒否する" '.engine_state.block_layer="structure" | .engine_state.post_inline=false | .engine_state.normalized_results=null | .inputs.findings_artifact=null | .inputs.adjudication_result=null'
mutate_request_and_expect "post_inline:false かつ block_layer:null を拒否する" '.engine_state.post_inline=false | .engine_state.block_layer=null'
jq '.engine="codex"' "$CASE_DIR/artifact.json" >"$CASE_DIR/engine-mismatch.json"
write_request "$CASE_DIR/engine-request.json" magi "$CASE_DIR/engine-mismatch.json" "$CASE_DIR/adjudication.json" \
  "$CASE_DIR/pr.diff" true "" "" "" "$CASE_DIR/engine-result.json"
expect_contract_exit "artifact と request engine の不一致を拒否する" "$CASE_DIR/engine-request.json"
jq '.findings=[{id:"DUP",source_persona:"MELCHIOR",path:"a",line:1,headline:"h",body:"b",evidence:null},{id:"DUP",source_persona:"MELCHIOR",path:"a",line:1,headline:"h",body:"b",evidence:null}]' \
  "$CASE_DIR/artifact.json" >"$CASE_DIR/duplicate-artifact.json"
write_request "$CASE_DIR/duplicate-request.json" magi "$CASE_DIR/duplicate-artifact.json" "$CASE_DIR/adjudication.json" \
  "$CASE_DIR/pr.diff" true "" "" "" "$CASE_DIR/duplicate-result.json"
expect_contract_exit "artifact の重複 ID を拒否する" "$CASE_DIR/duplicate-request.json"
jq '.failed_personas="CASPER"' "$CASE_DIR/artifact.json" >"$CASE_DIR/non-array-failed-personas.json"
write_request "$CASE_DIR/non-array-failed-personas-request.json" magi "$CASE_DIR/non-array-failed-personas.json" "$CASE_DIR/adjudication.json" \
  "$CASE_DIR/pr.diff" true "" "" "" "$CASE_DIR/non-array-failed-personas-result.json"
expect_contract_exit "artifact の非配列 failed_personas を拒否する" "$CASE_DIR/non-array-failed-personas-request.json"
jq '.detection_status="partial"' "$CASE_DIR/artifact.json" >"$CASE_DIR/invalid-detection-status.json"
write_request "$CASE_DIR/invalid-detection-status-request.json" magi "$CASE_DIR/invalid-detection-status.json" "$CASE_DIR/adjudication.json" \
  "$CASE_DIR/pr.diff" true "" "" "" "$CASE_DIR/invalid-detection-status-result.json"
expect_contract_exit "artifact の不正な detection_status を拒否する" "$CASE_DIR/invalid-detection-status-request.json"
jq '.findings[0] |= del(.id)' "$TEST_ROOT/magi-normal/artifact.json" >"$CASE_DIR/missing-id-artifact.json"
write_request "$CASE_DIR/missing-id-request.json" magi "$CASE_DIR/missing-id-artifact.json" \
  "$TEST_ROOT/magi-normal/adjudication.json" "$CASE_DIR/pr.diff" true "" "" "" "$CASE_DIR/missing-id-result.json"
expect_contract_exit "artifact の ID 欠落を拒否する" "$CASE_DIR/missing-id-request.json"
jq '.results=[{id:"EXTRA",verdict:"valid",importance:"HIGH",importance_status:"ok",reported_gate:null,final_gate:"block"}]' \
  "$CASE_DIR/adjudication.json" >"$CASE_DIR/extra-adjudication.json"
write_request "$CASE_DIR/extra-request.json" magi "$CASE_DIR/artifact.json" "$CASE_DIR/extra-adjudication.json" \
  "$CASE_DIR/pr.diff" true "" "" "" "$CASE_DIR/extra-result.json"
expect_contract_exit "adjudication の余分 ID を拒否する" "$CASE_DIR/extra-request.json"

# validity_global_failure は通常投稿に流さず、audit + finding_list の summary-only に限定する。
make_case validity-audit
printf '%s\n' 'diff' >"$CASE_DIR/pr.diff"
jq -n '{schema_version:"1",engine:"magi",detection_status:"complete",failed_personas:[],findings:[
  {id:"M-030",source_persona:"MELCHIOR",path:"a.sh",line:1,headline:"h",body:"b",evidence:null}]}' >"$CASE_DIR/artifact.json"
jq -n '{schema_version:"1",artifact_type:"review-adjudication",validity_global_failure:true,results:[
  {id:"M-030",verdict:null,importance:null,importance_status:"not_applicable",reported_gate:null,final_gate:null}]}' >"$CASE_DIR/adjudication.json"
write_request "$CASE_DIR/request.json" magi "$CASE_DIR/artifact.json" "$CASE_DIR/adjudication.json" \
  "$CASE_DIR/pr.diff" true "" "" "" "$CASE_DIR/result.json"
expect_contract_exit "validity_global_failure かつ通常投稿要求を拒否する" "$CASE_DIR/request.json"
write_request "$CASE_DIR/audit-request.json" magi "$CASE_DIR/artifact.json" "$CASE_DIR/adjudication.json" \
  "$CASE_DIR/pr.diff" false audit "" "M-030: 未監査" "$CASE_DIR/audit-result.json"
run_post "$CASE_DIR/audit-request.json"
if [[ "$POST_EXIT" -eq 0 ]] && [[ "$(count_kind issue)" -eq 1 ]] && [[ "$(count_kind inline)" -eq 0 ]]; then
  result=0
else
  result=1
fi
record_result "validity_global_failure は audit 経路の summary-only として受理する" "$result"

# GitHub API 失敗は成功済み write を保持して終了コード1とする。
make_case github-failure
printf '%s\n' '{"schema_version":"1","engine":"magi","detection_status":"complete","failed_personas":[],"findings":[]}' >"$CASE_DIR/artifact.json"
printf '%s\n' '{"schema_version":"1","artifact_type":"review-adjudication","validity_global_failure":false,"results":[]}' >"$CASE_DIR/adjudication.json"
write_request "$CASE_DIR/request.json" magi "$CASE_DIR/artifact.json" "$CASE_DIR/adjudication.json" \
  "$CASE_DIR/pr.diff" true "" "" "" "$CASE_DIR/result.json"
run_post "$CASE_DIR/request.json" summary-fail
if [[ "$POST_EXIT" -eq 1 ]] && assert_result "$CASE_DIR/result.json" '.github_writes == []'; then
  result=0
else
  result=1
fi
record_result "GitHub API 失敗は終了コード1で result を残す" "$result"

echo ""
echo "=== 結果: PASS=$PASS FAIL=$FAIL ==="
if [[ "$FAIL" -eq 0 ]]; then
  exit 0
fi
exit 1
