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
  'method=GET' \
  'endpoint=""' \
  'body=""' \
  'jq_filter=""' \
  'path_arg=""' \
  'line_arg=""' \
  'side_arg=""' \
  'comment_id=""' \
  'take_method=false' \
  'take_field=false' \
  'take_jq=false' \
  'for arg in "$@"; do' \
  '  if [[ "$take_method" == true ]]; then' \
  '    method="${arg^^}"' \
  '    take_method=false' \
  '    continue' \
  '  fi' \
  '  if [[ "$take_field" == true ]]; then' \
  '    [[ "$arg" == body=* ]] && body="${arg#body=}"' \
  '    [[ "$arg" == path=* ]] && path_arg="${arg#path=}"' \
  '    [[ "$arg" == line=* ]] && line_arg="${arg#line=}"' \
  '    [[ "$arg" == side=* ]] && side_arg="${arg#side=}"' \
  '    take_field=false' \
  '    continue' \
  '  fi' \
  '  if [[ "$take_jq" == true ]]; then' \
  '    jq_filter="$arg"' \
  '    take_jq=false' \
  '    continue' \
  '  fi' \
  '  case "$arg" in' \
  '    -X) take_method=true ;;' \
  '    -f|-F) take_field=true ;;' \
  '    --jq) take_jq=true ;;' \
  '    --paginate) ;;' \
  '    user) endpoint="user" ;;' \
  '    repos/*) endpoint="$arg" ;;' \
  '    path=*) path_arg="${arg#path=}" ;;' \
  '    line=*) line_arg="${arg#line=}" ;;' \
  '    side=*) side_arg="${arg#side=}" ;;' \
  '  esac' \
  'done' \
  'case "$endpoint" in' \
  '  user) kind=user ;;' \
  '  */pulls/*/comments*) kind=inline ;;' \
  '  */issues/comments/*) kind=issue ;;' \
  '  */issues/*/comments*) kind=issue ;;' \
  '  *) kind=other ;;' \
  'esac' \
  'if [[ "$method" == PATCH && "$endpoint" =~ /issues/comments/([0-9]+) ]]; then' \
  '  comment_id="${BASH_REMATCH[1]}"' \
  'fi' \
  'printf "ENDPOINT:%s\\n" "$endpoint" >> "$GH_LOG"' \
  'printf "METHOD:%s\\n" "$method" >> "$GH_LOG"' \
  'printf "KIND:%s\\n" "$kind" >> "$GH_LOG"' \
  'printf "PATH:%s\\n" "$path_arg" >> "$GH_LOG"' \
  'printf "LINE:%s\\n" "$line_arg" >> "$GH_LOG"' \
  'printf "SIDE:%s\\n" "$side_arg" >> "$GH_LOG"' \
  'printf "BODY:%s\\n" "$body" >> "$GH_LOG"' \
  'if [[ "$method" == PATCH ]]; then' \
  '  printf "COMMENT_ID:%s\\n" "$comment_id" >> "$GH_LOG"' \
  'fi' \
  'if [[ "$method" == GET ]]; then' \
  '  if [[ "$kind" == user ]]; then' \
  '    if [[ "${STUB_USER_FAIL:-}" == 1 ]]; then' \
  '      echo "gh api user failed" >&2' \
  '      exit 1' \
  '    fi' \
  '    user_json="${STUB_USER_JSON:-}"' \
  '    if [[ -z "$user_json" ]]; then user_json="{\"login\":\"review-bot\"}"; fi' \
  '    printf "%s" "$user_json" | jq -r "${jq_filter:-.}"' \
  '    exit $?' \
  '  fi' \
  '  if [[ "${STUB_GET_FAIL:-}" == issue && "$kind" == issue ]] || [[ "${STUB_GET_FAIL:-}" == both && "$kind" == issue ]]; then' \
  '    echo "GET issues failed" >&2' \
  '    exit 1' \
  '  fi' \
  '  if [[ "${STUB_GET_FAIL:-}" == pull && "$kind" == inline ]] || [[ "${STUB_GET_FAIL:-}" == both && "$kind" == inline ]]; then' \
  '    echo "GET pulls failed" >&2' \
  '    exit 1' \
  '  fi' \
  '  if [[ "$kind" == issue && -n "${STUB_ISSUE_COMMENTS:-}" ]]; then' \
  '    cat "$STUB_ISSUE_COMMENTS"' \
  '  elif [[ "$kind" == inline && -n "${STUB_PULL_COMMENTS:-}" ]]; then' \
  '    cat "$STUB_PULL_COMMENTS"' \
  '  fi' \
  '  exit 0' \
  'fi' \
  'if [[ "$method" == PATCH && "${STUB_PATCH_FAIL:-}" == 1 ]]; then' \
  '  echo "PATCH failed" >&2' \
  '  exit 1' \
  'fi' \
  'if [[ "$method" == POST && "${GH_MODE:-}" == summary-fail && "$kind" == issue ]]; then' \
  '  echo "HTTP 500" >&2' \
  '  exit 1' \
  'fi' \
  'if [[ "$method" == POST && "${GH_MODE:-}" == 422 && "$kind" == inline ]]; then' \
  '  echo "HTTP 422 Unprocessable Entity" >&2' \
  '  exit 1' \
  'fi' \
  'if [[ "$method" == PATCH ]]; then' \
  '  printf "%s\\n" "https://stub.invalid/patch"' \
  'else' \
  '  printf "%s\\n" "https://stub.invalid/$kind"' \
  'fi' \
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
  '  ground-same) printf "%s\n" "{\"schema_version\":\"1\",\"anchors\":[{\"id\":\"S-002\",\"anchored_path\":\"same.sh\",\"anchored_line\":1,\"side\":\"RIGHT\",\"anchor_status\":\"ok\"},{\"id\":\"S-001\",\"anchored_path\":\"same.sh\",\"anchored_line\":1,\"side\":\"RIGHT\",\"anchor_status\":\"ok\"}]}"; exit 0 ;;' \
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
  local issue_fixture="${3:-}"
  local pull_fixture="${4:-}"
  local get_fail="${5:-}"
  local patch_fail="${6:-}"
  local user_json="${7:-}"
  local user_fail="${8:-}"
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
    GROUND_STUB_LOG="$TEST_ROOT/grounder-called.log" GH_LOG="$GH_LOG" GH_MODE="$gh_mode" \
    STUB_ISSUE_COMMENTS="$issue_fixture" STUB_PULL_COMMENTS="$pull_fixture" \
    STUB_GET_FAIL="$get_fail" STUB_PATCH_FAIL="$patch_fail" \
    STUB_USER_JSON="$user_json" STUB_USER_FAIL="$user_fail" \
    bash "$POST_SCRIPT" "$request" \
    >"$TEST_ROOT/stdout" 2>"$TEST_ROOT/stderr"; then
    POST_EXIT=0
  else
    POST_EXIT=$?
  fi
}

count_kind() {
  local kind="$1"
  awk -v kind="$kind" '
    /^METHOD:/ { method = substr($0, 8) }
    /^KIND:/ && method == "POST" && substr($0, 6) == kind { count++ }
    END { print count + 0 }
  ' "$GH_LOG"
}

count_method_kind() {
  local method="$1"
  local kind="$2"
  awk -v wanted_method="$method" -v wanted_kind="$kind" '
    /^METHOD:/ { current_method = substr($0, 8) }
    /^KIND:/ && current_method == wanted_method && substr($0, 6) == wanted_kind { count++ }
    END { print count + 0 }
  ' "$GH_LOG"
}

assert_result() {
  local file="$1"
  local filter="$2"
  jq -e "$filter" "$file" >/dev/null 2>&1
}

finding_fp() {
  local engine_label="$1"
  local head_sha="$2"
  local persona="$3"
  local path="$4"
  local line="$5"
  printf '%s\0' 'review-post:v1' 'finding' "$engine_label" "$head_sha" "$persona" "$path" "$line" \
    | sha256sum | cut -c1-24
}

summary_marker() {
  local engine_label="$1"
  local head_sha="$2"
  local fp
  fp="$(printf '%s\0' 'review-post:v1' 'summary' "$engine_label" "$head_sha" | sha256sum | cut -c1-24)"
  printf '%s\n' "<!-- review-post:v1 kind=summary engine=$engine_label head_sha=$head_sha fp=$fp -->"
}

finding_marker() {
  local engine_label="$1"
  local head_sha="$2"
  local persona="$3"
  local path="$4"
  local line="$5"
  local fp
  fp="$(finding_fp "$engine_label" "$head_sha" "$persona" "$path" "$line")"
  printf '%s\n' "<!-- review-post:v1 kind=finding engine=$engine_label head_sha=$head_sha fp=$fp -->"
}

append_comment() {
  local file="$1"
  local id="$2"
  local body="$3"
  local login="${4:-review-bot}"
  jq -n -c --argjson id "$id" --arg body "$body" --arg login "$login" '{id:$id,body:$body,login:$login}' >>"$file"
}

post_bodies_have_markers() {
  awk '
    function finish_call() {
      if (method == "POST" && (kind == "issue" || kind == "inline") &&
          last !~ /^<!-- review-post:v1 kind=(summary|finding) engine=[^ ]+ head_sha=[^ ]+ fp=[0-9a-f]{24} -->$/) {
        bad = 1
      }
    }
    /^ENDPOINT:/ {
      if (seen) finish_call()
      seen = 1
      method = ""
      kind = ""
      body_started = 0
      last = ""
      next
    }
    /^METHOD:/ { method = substr($0, 8); next }
    /^KIND:/ { kind = substr($0, 6); next }
    /^BODY:/ { body_started = 1; last = substr($0, 6); next }
    body_started { last = $0 }
    END {
      if (seen) finish_call()
      exit bad
    }
  ' "$GH_LOG"
}

gets_precede_mutations() {
  awk '
    /^METHOD:(POST|PATCH)$/ { mutation_seen = 1 }
    /^METHOD:GET$/ && mutation_seen { bad = 1 }
    END { exit bad }
  ' "$GH_LOG"
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
  && grep -Fq 'PATH:new.sh' "$GH_LOG" && grep -Fq 'old.sh:1' "$GH_LOG" \
  && grep -Fq 'quote "x"' "$GH_LOG"; then
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

# 冪等性: clean な PR では summary/finding をすべて新規作成し、本文末尾にマーカーを付ける。
make_case idempotency-clean
cp "$TEST_ROOT/anchor-contract/pr.diff" "$CASE_DIR/pr.diff"
cp "$TEST_ROOT/anchor-contract/artifact.json" "$CASE_DIR/artifact.json"
cp "$TEST_ROOT/anchor-contract/adjudication.json" "$CASE_DIR/adjudication.json"
write_request "$CASE_DIR/request.json" magi "$CASE_DIR/artifact.json" "$CASE_DIR/adjudication.json" \
  "$CASE_DIR/pr.diff" true "" "" "" "$CASE_DIR/result.json"
run_post "$CASE_DIR/request.json" ground-all
if [[ "$POST_EXIT" -eq 0 ]] \
  && assert_result "$CASE_DIR/result.json" '.counts.reused == 0 and .counts.inline_posted == 2 and all(.items[]; .reused == false) and (.github_writes | length) == 3 and all(.github_writes[]; .operation == "create")' \
  && [[ "$(count_method_kind GET issue)" -eq 1 ]] && [[ "$(count_method_kind GET inline)" -eq 1 ]] \
  && [[ "$(count_method_kind POST issue)" -eq 1 ]] && [[ "$(count_method_kind POST inline)" -eq 2 ]] \
  && [[ "$(count_method_kind PATCH issue)" -eq 0 ]] \
  && post_bodies_have_markers && gets_precede_mutations \
  && grep -Fq 'BODY:[MAGI-HARD]' "$GH_LOG"; then
  result=0
else
  result=1
fi
record_result "冪等性 clean は全件を新規投稿し、本文末尾マーカーと MAGI 接頭辞を維持する" "$result"

# 同一 SHA の完全再実行: pulls の inline を優先し、issues の退避を通常コメントとして再利用する。
make_case idempotency-full-rerun
cp "$TEST_ROOT/anchor-contract/pr.diff" "$CASE_DIR/pr.diff"
cp "$TEST_ROOT/anchor-contract/artifact.json" "$CASE_DIR/artifact.json"
cp "$TEST_ROOT/anchor-contract/adjudication.json" "$CASE_DIR/adjudication.json"
ISSUE_FIXTURE="$CASE_DIR/issues.jsonl"
PULL_FIXTURE="$CASE_DIR/pulls.jsonl"
: >"$ISSUE_FIXTURE"
: >"$PULL_FIXTURE"
append_comment "$ISSUE_FIXTURE" 100 $'old summary\n\n'"$(summary_marker MAGI-HARD 0123456789abcdef)"
append_comment "$ISSUE_FIXTURE" 101 $'[MAGI-HARD] old fallback\n\n'"$(finding_marker MAGI-HARD 0123456789abcdef MELCHIOR a.sh 1)"
append_comment "$PULL_FIXTURE" 200 $'[MAGI-HARD] old inline\n\n'"$(finding_marker MAGI-HARD 0123456789abcdef BALTHASAR b.sh 1)"
write_request "$CASE_DIR/request.json" magi "$CASE_DIR/artifact.json" "$CASE_DIR/adjudication.json" \
  "$CASE_DIR/pr.diff" true "" "" "" "$CASE_DIR/result.json"
run_post "$CASE_DIR/request.json" ground-all "$ISSUE_FIXTURE" "$PULL_FIXTURE"
if [[ "$POST_EXIT" -eq 0 ]] \
  && assert_result "$CASE_DIR/result.json" '.counts.reused == 2 and all(.items[]; .reused == true) and (.items[] | select(.id == "G-001") | .delivery == "pr_comment") and (.items[] | select(.id == "G-002") | .delivery == "inline") and (.github_writes | length) == 1 and .github_writes[0].operation == "update"' \
  && [[ "$(count_method_kind PATCH issue)" -eq 1 ]] && [[ "$(count_method_kind POST issue)" -eq 0 ]] \
  && [[ "$(count_method_kind POST inline)" -eq 0 ]] && grep -Fq 'COMMENT_ID:100' "$GH_LOG" \
  && gets_precede_mutations; then
  result=0
else
  result=1
fi
record_result "同一 SHA の完全再実行は summary PATCH と inline/退避の multiset 再利用を行う" "$result"

# 部分再実行: 既存 finding の ID が変わっても位置 fingerprint で再利用し、未投稿分だけ作成する。
make_case idempotency-partial-rerun
cp "$TEST_ROOT/anchor-contract/pr.diff" "$CASE_DIR/pr.diff"
cp "$TEST_ROOT/anchor-contract/artifact.json" "$CASE_DIR/artifact.json"
cp "$TEST_ROOT/anchor-contract/adjudication.json" "$CASE_DIR/adjudication.json"
ISSUE_FIXTURE="$CASE_DIR/issues.jsonl"
: >"$ISSUE_FIXTURE"
append_comment "$ISSUE_FIXTURE" 300 $'previous summary\n\n'"$(summary_marker MAGI-HARD 0123456789abcdef)"
append_comment "$ISSUE_FIXTURE" 999 $'[MAGI-HARD] previous text\n\n'"$(finding_marker MAGI-HARD 0123456789abcdef MELCHIOR a.sh 1)"
write_request "$CASE_DIR/request.json" magi "$CASE_DIR/artifact.json" "$CASE_DIR/adjudication.json" \
  "$CASE_DIR/pr.diff" true "" "" "" "$CASE_DIR/result.json"
run_post "$CASE_DIR/request.json" ground-all "$ISSUE_FIXTURE"
if [[ "$POST_EXIT" -eq 0 ]] \
  && assert_result "$CASE_DIR/result.json" '.counts.reused == 1 and (.items[] | select(.id == "G-001") | .reused == true and .delivery == "pr_comment") and (.items[] | select(.id == "G-002") | .reused == false and .delivery == "inline") and (.github_writes | map(.operation) == ["update", "create"])' \
  && [[ "$(count_method_kind PATCH issue)" -eq 1 ]] && [[ "$(count_method_kind POST issue)" -eq 0 ]] \
  && [[ "$(count_method_kind POST inline)" -eq 1 ]]; then
  result=0
else
  result=1
fi
record_result "部分再実行は finding ID 非依存で既存分を再利用し未投稿分だけ投稿する" "$result"

# 本文と severity が変わっても位置 fingerprint は不変なので再利用する。
make_case idempotency-body-difference
cp "$TEST_ROOT/anchor-contract/pr.diff" "$CASE_DIR/pr.diff"
cp "$TEST_ROOT/anchor-contract/artifact.json" "$CASE_DIR/artifact.json"
jq '.results[0].importance="MEDIUM" | .results[1].final_gate="defer"' \
  "$TEST_ROOT/anchor-contract/adjudication.json" >"$CASE_DIR/adjudication.json"
ISSUE_FIXTURE="$CASE_DIR/issues.jsonl"
: >"$ISSUE_FIXTURE"
append_comment "$ISSUE_FIXTURE" 400 $'previous HIGH wording\n\n'"$(summary_marker MAGI-HARD 0123456789abcdef)"
append_comment "$ISSUE_FIXTURE" 401 $'[MAGI-HARD] **[HIGH] old wording**\n\nold body\n\n'"$(finding_marker MAGI-HARD 0123456789abcdef MELCHIOR a.sh 1)"
write_request "$CASE_DIR/request.json" magi "$CASE_DIR/artifact.json" "$CASE_DIR/adjudication.json" \
  "$CASE_DIR/pr.diff" true "" "" "" "$CASE_DIR/result.json"
run_post "$CASE_DIR/request.json" ground-all "$ISSUE_FIXTURE"
if [[ "$POST_EXIT" -eq 0 ]] \
  && assert_result "$CASE_DIR/result.json" '.counts.reused == 1 and (.items[] | select(.id == "G-001") | .importance == "MEDIUM" and .reused == true and .delivery == "pr_comment") and (.github_writes | length) == 1 and .github_writes[0].operation == "update"' \
  && [[ "$(count_method_kind POST inline)" -eq 0 ]] && [[ "$(count_method_kind POST issue)" -eq 0 ]]; then
  result=0
else
  result=1
fi
record_result "本文差異と HIGH/MEDIUM 変更があっても位置キー一致の finding を再利用する" "$result"

# 同一位置の複数 finding は集合ではなく個数を消費するため、欠落させない。
make_case idempotency-multiset
printf '%s\n' \
  'diff --git a/same.sh b/same.sh' \
  '--- a/same.sh' \
  '+++ b/same.sh' \
  '@@ -0,0 +1 @@' \
  '+echo same' >"$CASE_DIR/pr.diff"
jq -n '{schema_version:"1",engine:"magi",detection_status:"complete",failed_personas:[],findings:[
  {id:"S-001",source_persona:"MELCHIOR",path:"same.sh",line:1,headline:"one",body:"first wording",evidence:null},
  {id:"S-002",source_persona:"MELCHIOR",path:"same.sh",line:1,headline:"two",body:"second wording",evidence:null}]}' \
  >"$CASE_DIR/artifact.json"
jq -n '{schema_version:"1",artifact_type:"review-adjudication",validity_global_failure:false,results:[
  {id:"S-001",verdict:"valid",importance:"HIGH",importance_status:"ok",reported_gate:null,final_gate:"block"},
  {id:"S-002",verdict:"valid",importance:"HIGH",importance_status:"ok",reported_gate:null,final_gate:"block"}]}' \
  >"$CASE_DIR/adjudication.json"
write_request "$CASE_DIR/request.json" magi "$CASE_DIR/artifact.json" "$CASE_DIR/adjudication.json" \
  "$CASE_DIR/pr.diff" true "" "" "" "$CASE_DIR/clean-result.json"
run_post "$CASE_DIR/request.json" ground-same
if [[ "$POST_EXIT" -eq 0 ]] \
  && assert_result "$CASE_DIR/clean-result.json" '.counts.reused == 0 and .counts.inline_posted == 2 and all(.items[]; .reused == false)' \
  && [[ "$(count_method_kind POST inline)" -eq 2 ]]; then
  MULTI_CLEAN_OK=0
else
  MULTI_CLEAN_OK=1
fi
ISSUE_FIXTURE="$CASE_DIR/issues.jsonl"
PULL_FIXTURE="$CASE_DIR/pulls.jsonl"
: >"$ISSUE_FIXTURE"
: >"$PULL_FIXTURE"
append_comment "$ISSUE_FIXTURE" 500 $'previous summary\n\n'"$(summary_marker MAGI-HARD 0123456789abcdef)"
append_comment "$PULL_FIXTURE" 501 $'one of two\n\n'"$(finding_marker MAGI-HARD 0123456789abcdef MELCHIOR same.sh 1)"
write_request "$CASE_DIR/rerun-request.json" magi "$CASE_DIR/artifact.json" "$CASE_DIR/adjudication.json" \
  "$CASE_DIR/pr.diff" true "" "" "" "$CASE_DIR/rerun-result.json"
run_post "$CASE_DIR/rerun-request.json" ground-same "$ISSUE_FIXTURE" "$PULL_FIXTURE"
MULTI_RERUN_OK=$([[ "$POST_EXIT" -eq 0 ]] \
  && assert_result "$CASE_DIR/rerun-result.json" '.counts.reused == 1 and .counts.inline_posted == 2 and (.items | map(select(.reused == true)) | length) == 1 and (.items | map(select(.reused == false)) | length) == 1' \
  && [[ "$(count_method_kind POST inline)" -eq 1 ]])
if [[ "$MULTI_CLEAN_OK" -eq 0 && "$MULTI_RERUN_OK" -eq 0 ]]; then
  result=0
else
  result=1
fi
record_result "同一位置の複数 finding は既存1件でも残り1件を投稿して欠落させない" "$result"

# HEAD SHA が変われば旧マーカーを再利用せず、全件を新しい SHA で投稿する。
make_case idempotency-head-difference
cp "$TEST_ROOT/anchor-contract/pr.diff" "$CASE_DIR/pr.diff"
cp "$TEST_ROOT/anchor-contract/artifact.json" "$CASE_DIR/artifact.json"
cp "$TEST_ROOT/anchor-contract/adjudication.json" "$CASE_DIR/adjudication.json"
ISSUE_FIXTURE="$CASE_DIR/issues.jsonl"
: >"$ISSUE_FIXTURE"
append_comment "$ISSUE_FIXTURE" 600 $'old summary\n\n'"$(summary_marker MAGI-HARD old-head-sha)"
append_comment "$ISSUE_FIXTURE" 601 $'old one\n\n'"$(finding_marker MAGI-HARD old-head-sha MELCHIOR a.sh 1)"
append_comment "$ISSUE_FIXTURE" 602 $'old two\n\n'"$(finding_marker MAGI-HARD old-head-sha BALTHASAR b.sh 1)"
write_request "$CASE_DIR/request.json" magi "$CASE_DIR/artifact.json" "$CASE_DIR/adjudication.json" \
  "$CASE_DIR/pr.diff" true "" "" "" "$CASE_DIR/result.json"
run_post "$CASE_DIR/request.json" ground-all "$ISSUE_FIXTURE"
if [[ "$POST_EXIT" -eq 0 ]] \
  && assert_result "$CASE_DIR/result.json" '.counts.reused == 0 and all(.items[]; .reused == false) and all(.github_writes[]; .operation == "create")' \
  && [[ "$(count_method_kind PATCH issue)" -eq 0 ]] && [[ "$(count_method_kind POST issue)" -eq 1 ]] \
  && [[ "$(count_method_kind POST inline)" -eq 2 ]] \
  && grep -Fq 'head_sha=0123456789abcdef' "$GH_LOG"; then
  result=0
else
  result=1
fi
record_result "HEAD SHA が異なる既存マーカーは再利用せず新 SHA で投稿する" "$result"

# 一覧取得失敗は issues/pulls のどちらでも mutation なしの fail-closed とする。
make_case idempotency-list-failure
cp "$TEST_ROOT/anchor-contract/pr.diff" "$CASE_DIR/pr.diff"
cp "$TEST_ROOT/anchor-contract/artifact.json" "$CASE_DIR/artifact.json"
cp "$TEST_ROOT/anchor-contract/adjudication.json" "$CASE_DIR/adjudication.json"
write_request "$CASE_DIR/request.json" magi "$CASE_DIR/artifact.json" "$CASE_DIR/adjudication.json" \
  "$CASE_DIR/pr.diff" true "" "" "" "$CASE_DIR/result.json"
run_post "$CASE_DIR/request.json" ground-all "" "" issue
if [[ "$POST_EXIT" -eq 1 ]] \
  && assert_result "$CASE_DIR/result.json" '.github_writes == [] and .counts.reused == 0 and all(.items[]; .delivery == "not_posted" and .reused == false)' \
  && [[ "$(count_method_kind GET issue)" -eq 1 ]] && [[ "$(count_method_kind GET inline)" -eq 1 ]] \
  && [[ "$(count_method_kind POST issue)" -eq 0 ]] && [[ "$(count_method_kind POST inline)" -eq 0 ]]; then
  ISSUE_LIST_FAILURE_OK=0
else
  ISSUE_LIST_FAILURE_OK=1
fi
run_post "$CASE_DIR/request.json" ground-all "" "" pull
if [[ "$POST_EXIT" -eq 1 ]] \
  && assert_result "$CASE_DIR/result.json" '.github_writes == [] and .counts.reused == 0 and all(.items[]; .delivery == "not_posted" and .reused == false)' \
  && [[ "$(count_method_kind GET issue)" -eq 1 ]] && [[ "$(count_method_kind GET inline)" -eq 1 ]] \
  && [[ "$(count_method_kind POST issue)" -eq 0 ]] && [[ "$(count_method_kind POST inline)" -eq 0 ]]; then
  PULL_LIST_FAILURE_OK=0
else
  PULL_LIST_FAILURE_OK=1
fi
if [[ "$ISSUE_LIST_FAILURE_OK" -eq 0 && "$PULL_LIST_FAILURE_OK" -eq 0 ]]; then
  result=0
else
  result=1
fi
record_result "issues/pulls 一覧取得失敗は result を生成し全 mutation を抑止する" "$result"

# 422 退避済み finding は pulls が空でも issues 側から再利用する。
make_case idempotency-fallback-rerun
cp "$TEST_ROOT/anchor-contract/pr.diff" "$CASE_DIR/pr.diff"
cp "$TEST_ROOT/anchor-contract/artifact.json" "$CASE_DIR/artifact.json"
jq '.results[1].final_gate="defer"' "$TEST_ROOT/anchor-contract/adjudication.json" >"$CASE_DIR/adjudication.json"
ISSUE_FIXTURE="$CASE_DIR/issues.jsonl"
: >"$ISSUE_FIXTURE"
append_comment "$ISSUE_FIXTURE" 700 $'fallback from prior run\n\n'"$(finding_marker MAGI-HARD 0123456789abcdef MELCHIOR a.sh 1)"
write_request "$CASE_DIR/request.json" magi "$CASE_DIR/artifact.json" "$CASE_DIR/adjudication.json" \
  "$CASE_DIR/pr.diff" true "" "" "" "$CASE_DIR/result.json"
run_post "$CASE_DIR/request.json" ground-all "$ISSUE_FIXTURE"
if [[ "$POST_EXIT" -eq 0 ]] \
  && assert_result "$CASE_DIR/result.json" '(.items[] | select(.id == "G-001") | .reused == true and .delivery == "pr_comment") and .counts.reused == 1 and (.github_writes | length) == 1' \
  && [[ "$(count_method_kind POST inline)" -eq 0 ]] && [[ "$(count_method_kind POST issue)" -eq 1 ]]; then
  result=0
else
  result=1
fi
record_result "422 フォールバック済み finding は inline POST を再試行せず再利用する" "$result"

# summary PATCH の失敗時は finding 投稿へ進まず、失敗 write を result に残さない。
make_case idempotency-summary-patch-failure
cp "$TEST_ROOT/anchor-contract/pr.diff" "$CASE_DIR/pr.diff"
cp "$TEST_ROOT/anchor-contract/artifact.json" "$CASE_DIR/artifact.json"
cp "$TEST_ROOT/anchor-contract/adjudication.json" "$CASE_DIR/adjudication.json"
ISSUE_FIXTURE="$CASE_DIR/issues.jsonl"
: >"$ISSUE_FIXTURE"
append_comment "$ISSUE_FIXTURE" 800 $'patch me\n\n'"$(summary_marker MAGI-HARD 0123456789abcdef)"
write_request "$CASE_DIR/request.json" magi "$CASE_DIR/artifact.json" "$CASE_DIR/adjudication.json" \
  "$CASE_DIR/pr.diff" true "" "" "" "$CASE_DIR/result.json"
run_post "$CASE_DIR/request.json" ground-all "$ISSUE_FIXTURE" "" "" 1
if [[ "$POST_EXIT" -eq 1 ]] \
  && assert_result "$CASE_DIR/result.json" '.github_writes == [] and all(.items[]; .delivery == "not_posted" and .reused == false)' \
  && [[ "$(count_method_kind PATCH issue)" -eq 1 ]] && [[ "$(count_method_kind POST issue)" -eq 0 ]] \
  && [[ "$(count_method_kind POST inline)" -eq 0 ]]; then
  result=0
else
  result=1
fi
record_result "summary PATCH 失敗時は finding 投稿を開始せず失敗 write を記録しない" "$result"

# 他ユーザーが偽造した marker は dedup せず、summary/finding とも新規投稿する。
make_case idempotency-forged-marker
cp "$TEST_ROOT/anchor-contract/pr.diff" "$CASE_DIR/pr.diff"
cp "$TEST_ROOT/anchor-contract/artifact.json" "$CASE_DIR/artifact.json"
cp "$TEST_ROOT/anchor-contract/adjudication.json" "$CASE_DIR/adjudication.json"
ISSUE_FIXTURE="$CASE_DIR/issues.jsonl"
PULL_FIXTURE="$CASE_DIR/pulls.jsonl"
: >"$ISSUE_FIXTURE"
: >"$PULL_FIXTURE"
append_comment "$ISSUE_FIXTURE" 900 $'forged summary\n\n'"$(summary_marker MAGI-HARD 0123456789abcdef)" attacker
append_comment "$PULL_FIXTURE" 901 $'forged finding\n\n'"$(finding_marker MAGI-HARD 0123456789abcdef MELCHIOR a.sh 1)" attacker
write_request "$CASE_DIR/request.json" magi "$CASE_DIR/artifact.json" "$CASE_DIR/adjudication.json" \
  "$CASE_DIR/pr.diff" true "" "" "" "$CASE_DIR/result.json"
run_post "$CASE_DIR/request.json" "" "$ISSUE_FIXTURE" "$PULL_FIXTURE"
if [[ "$POST_EXIT" -eq 0 ]] \
  && assert_result "$CASE_DIR/result.json" '.counts.reused == 0 and all(.items[]; .reused == false) and all(.github_writes[]; .operation == "create") and ([.github_writes[] | select(.operation == "update")] | length) == 0' \
  && [[ "$(count_method_kind POST issue)" -ge 1 ]] && [[ "$(count_method_kind PATCH issue)" -eq 0 ]] \
  && [[ "$(grep -c '^COMMENT_ID:' "$GH_LOG")" -eq 0 ]] \
  && [[ "$(count_method_kind POST inline)" -eq 2 ]]; then
  result=0
else
  result=1
fi
record_result "他ユーザーの偽造 marker は dedup せず summary/finding を新規投稿する" "$result"

# bot 自身の識別に失敗した場合は、一覧取得失敗と同じ fail-closed にする。
make_case idempotency-self-identity-failure
cp "$TEST_ROOT/anchor-contract/pr.diff" "$CASE_DIR/pr.diff"
cp "$TEST_ROOT/anchor-contract/artifact.json" "$CASE_DIR/artifact.json"
cp "$TEST_ROOT/anchor-contract/adjudication.json" "$CASE_DIR/adjudication.json"
write_request "$CASE_DIR/request.json" magi "$CASE_DIR/artifact.json" "$CASE_DIR/adjudication.json" \
  "$CASE_DIR/pr.diff" true "" "" "" "$CASE_DIR/result.json"
run_post "$CASE_DIR/request.json" "" "" "" "" "" "" 1
if [[ "$POST_EXIT" -eq 1 ]] \
  && [[ -f "$CASE_DIR/result.json" ]] && jq -e . "$CASE_DIR/result.json" >/dev/null 2>&1 \
  && assert_result "$CASE_DIR/result.json" '.github_writes == [] and .counts.reused == 0 and all(.items[]; .delivery == "not_posted" and .reused == false)' \
  && [[ "$(count_method_kind GET issue)" -eq 1 ]] && [[ "$(count_method_kind GET inline)" -eq 1 ]] \
  && [[ "$(count_method_kind GET user)" -eq 1 ]] && [[ -s "$GH_LOG" ]] \
  && [[ "$(count_method_kind POST issue)" -eq 0 ]] && [[ "$(count_method_kind POST inline)" -eq 0 ]] \
  && [[ "$(count_method_kind PATCH issue)" -eq 0 ]]; then
  result=0
else
  result=1
fi
record_result "self-identity 取得失敗は fail-closed で投稿と PATCH を抑止する" "$result"

# self-identity の login が valid JSON だが不正（null / 欠落 / 非文字列）なら、gh api user の --jq
# 型検証が error() で非ゼロ終了し、一覧取得失敗と同じ fail-closed になることを実入力で pin する。
identity_result=0
for user_json in '{"login":null}' '{}' '{"login":123}'; do
  make_case idempotency-self-identity-invalid
  cp "$TEST_ROOT/anchor-contract/pr.diff" "$CASE_DIR/pr.diff"
  cp "$TEST_ROOT/anchor-contract/artifact.json" "$CASE_DIR/artifact.json"
  cp "$TEST_ROOT/anchor-contract/adjudication.json" "$CASE_DIR/adjudication.json"
  write_request "$CASE_DIR/request.json" magi "$CASE_DIR/artifact.json" "$CASE_DIR/adjudication.json" \
    "$CASE_DIR/pr.diff" true "" "" "" "$CASE_DIR/result.json"
  run_post "$CASE_DIR/request.json" "" "" "" "" "" "$user_json"
  if [[ "$POST_EXIT" -eq 1 ]] \
    && [[ -f "$CASE_DIR/result.json" ]] && jq -e . "$CASE_DIR/result.json" >/dev/null 2>&1 \
    && assert_result "$CASE_DIR/result.json" '.github_writes == [] and .counts.reused == 0 and all(.items[]; .delivery == "not_posted" and .reused == false)' \
    && [[ "$(count_method_kind GET issue)" -eq 1 ]] && [[ "$(count_method_kind GET inline)" -eq 1 ]] \
    && [[ "$(count_method_kind GET user)" -eq 1 ]] && [[ -s "$GH_LOG" ]] \
    && [[ "$(count_method_kind POST issue)" -eq 0 ]] && [[ "$(count_method_kind POST inline)" -eq 0 ]] \
    && [[ "$(count_method_kind PATCH issue)" -eq 0 ]]; then
    :
  else
    identity_result=1
    echo "  self-identity-invalid failed for: $user_json" >&2
  fi
done
record_result "self-identity の不正 login（null/欠落/非文字列）は jq 型検証で fail-closed する" "$identity_result"

# fingerprint の入力境界と、マーカーが本文末尾かつ先頭でないことを確認する。
BASE_FP="$(finding_fp MAGI-HARD 0123456789abcdef MELCHIOR a.sh 1)"
VARIANT_FP="$(finding_fp MAGI-HARD 0123456789abcdef MELCHIOR a.sh 1)"
HEAD_FP="$(finding_fp MAGI-HARD fedcba9876543210 MELCHIOR a.sh 1)"
ENGINE_FP="$(finding_fp CODEX-HARD 0123456789abcdef MELCHIOR a.sh 1)"
PERSONA_FP="$(finding_fp MAGI-HARD 0123456789abcdef BALTHASAR a.sh 1)"
PATH_FP="$(finding_fp MAGI-HARD 0123456789abcdef MELCHIOR b.sh 1)"
LINE_FP="$(finding_fp MAGI-HARD 0123456789abcdef MELCHIOR a.sh 2)"
MARKER="$(finding_marker MAGI-HARD 0123456789abcdef MELCHIOR a.sh 1)"
MARKED_BODY=$'[MAGI-HARD] changed wording\n\n'"$MARKER"
if [[ "$BASE_FP" == "$VARIANT_FP" && "$BASE_FP" != "$HEAD_FP" && "$BASE_FP" != "$ENGINE_FP" \
  && "$BASE_FP" != "$PERSONA_FP" && "$BASE_FP" != "$PATH_FP" && "$BASE_FP" != "$LINE_FP" \
  && "$MARKED_BODY" == *"$MARKER" && "$MARKED_BODY" != "$MARKER"* ]]; then
  result=0
else
  result=1
fi
record_result "fingerprint は位置キーだけで計算し、マーカーを本文末尾に置く" "$result"

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
