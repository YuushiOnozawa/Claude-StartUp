# `/review-post` 共通契約

`/review-post` は canonical findings artifact（`skills/flow-common/references/findings-artifact.md`）と
adjudication result（`scripts/review-adjudicate-findings.sh` の出力）を受け取り、grounding
（PR diff 上の行アンカー確認・補正）と GitHub 投稿を行う共通後段である。MAGI（`/magi-hard`）と
Codex（`/codex-hard`）の両方から呼び出される。GitHub への書き込みはサマリコメントを必ず先に行い、
その後、`post_inline` が許可する場合だけステップ7相当のインラインコメントまたは通常 PR コメント退避を行う。

## 入力: request JSON

`/review-post <request-file>` の形で単一の request JSON ファイルパスを受け取る。
request は手書きの JSON 連結ではなく、呼び出し元が `jq -n --arg --argjson --rawfile` で生成する。

```json
{
  "schema_version": "1",
  "artifact_type": "review-post-request",
  "engine": "magi",
  "forge_host": "github.com",
  "pr": { "owner": "string", "repo": "string", "number": 123, "head_sha": "string" },
  "singleflight": {
    "managed_by": "review-hard",
    "tmpdir": "/path/dispatch-tmp",
    "owner_token_file": "/path/dispatch-tmp/sf-owner-token",
    "lease_file_ref": "/path/dispatch-tmp/dispatch-state.json",
    "scope": "per_pr",
    "canonical_key": "github.com\nowner/repo\n123",
    "lease_id": "lease-uuid",
    "forge_host": "github.com"
  },
  "inputs": {
    "findings_artifact": "/path/findings-artifact.json",
    "adjudication_result": "/path/adjudication-result.json",
    "diff": "/path/pr.diff"
  },
  "engine_state": {
    "post_inline": true,
    "block_layer": null,
    "audit_note": null,
    "importance_note": null,
    "artifact_note": null,
    "normalized_results": null,
    "finding_list": null
  },
  "result_path": "/path/review-post-result.json"
}
```

`engine` は `magi` または `codex`、PR 番号は正整数、`head_sha` は空でない文字列とする。diff のパスは
必須で空であってはならない。artifact と adjudication は通常・audit・importance 経路では必須であり、
`block_layer: "structure"` の場合だけ両方を `null` にできる。この structure 経路では
`normalized_results` が空でない文字列でなければならない。`block_layer: "audit"` では
`finding_list` が空でない文字列でなければならない。

`post_inline` はステップ7相当（インラインコメントと通常 PR コメント退避）だけを制御する。
サマリコメントは常に投稿する。`block_layer: "importance"` と anchor 層の失敗は
`post_inline` を変更しない。

## post lock と managed single-flight fencing（PR-2 + PR-3）

PR-2 が提供するのは fencing 契約の step 2（post lock 取得）と step 6（lock 保持中に既存コメント一覧の
取得・dedup から全 GitHub write までを行うこと）である。PR-3 は step 1（managed request の lease_id
必須化）、step 3（lock 内の per_pr lease 再確認）、step 4（不一致時の mutation 前停止）、step 5
（force-release 側の post lock）を接続する（PR-3 の step 1/3/4/5）。`singleflight` が欠如する非 managed 実行は従来どおり lock に
触れず、`singleflight` がある実行では `REVIEW_POST_USE_LOCK=1` を内部的に有効化する。

managed request は次の検証を、一覧 GET を含む GitHub API 呼び出しより前に完了させる。

- `singleflight` は object で、`managed_by=review-hard`、`scope=per_pr`、`tmpdir`、`owner_token_file`、
  `lease_file_ref`、`canonical_key`、`lease_id`、`forge_host` がすべて非空文字列であること。
- `tmpdir` は絶対パスの実在ディレクトリ、token file は `tmpdir` 配下の通常ファイル・実行 UID 所有・
  mode `0600`・非空、state file は `tmpdir` 配下で読み取り可能であること（symlink は拒否）。
- `lease_file_ref.per_pr.lease_id` が request の `singleflight.lease_id` と一致し、`canonical_key` が
  `forge_host` と `pr.owner/repo/number`（owner/repo は小文字化）から再構成した値と一致すること。

一つでも不正なら managed を非 managed に降格せず、GitHub mutation 前に終了コード 2（入力契約違反または
managed lease admission failure、いずれも GitHub mutation 未実行）で停止する。

## 単一 JSON 値の検証と request の構造検証

request、findings artifact、adjudication result、および grounding 出力は配列やオブジェクトの連結を
受け入れず、1ファイル1 JSON 値として読み込む。request または入力 artifact の契約違反は終了コード2とし、
この検証より前に GitHub API を呼び出してはならない。

## canonical finding の写像と grounding

artifact の全 `findings[]` を grounding 入力へ写像する。`id`、`body`、`evidence` はそのまま、
`path` は `original_path`、`line` は `original_line` とする。`line: null` は grounder に渡す前に分離し、
`{id, anchored_path:"", anchored_line:0, side:"", anchor_status:"unanchorable"}` とする。
全 finding が null-line の場合は `scripts/magi-ground-findings.sh` を呼ばない。

grounder の出力は ID の重複・欠落・余分、未知の status、不正な path/line/side がないことを全件検証する。
1件でも検証に失敗した場合は部分採用せず、全 finding を `unanchorable` に倒し、次の注記を result と
サマリへ設定する。

```text
GROUNDING_FAILED（アンカーを確認できなかったため全件を通常PRコメントとして投稿する）
```

成功時も join は必ず ID で行い、配列順に依存しない。`original_*` は元の場所、`anchored_*` は
インライン投稿専用の補正位置として別フィールドで保持する。

## 実行手順

以下が `/review-post` の実行本体である。`gh` が返す URL は result の `github_writes` に保存し、
サマリを含むいずれかの API 呼び出しが失敗した場合は成功済みの write を保存したうえで終了コード1とする。
contract violation は終了コード2、サマリのみ投稿・投稿対象0件・grounding fallback 後の投稿成功は終了コード0とする。
終了コード2には、request / 入力 artifact の契約違反に加えて、managed single-flight の lease admission
failure（singleflight 不正、post lock 内の lease_id 不一致、renew の `not_owner` / I/O 失敗）を含める。
いずれも GitHub API の GET を含む mutation 前の検証で停止し、GitHub mutation 未実行を保証する。

```bash
#!/usr/bin/env bash
set -euo pipefail
REVIEW_POST_STARTED_AT="$(date +%s)"

die_contract() {
  echo "review-post contract violation: $*" >&2
  exit 2
}

strict_json() {
  local input_file="$1"
  jq -s -c 'if length == 1 then .[0] else error("expected exactly one JSON value") end' "$input_file"
}

[[ "$#" -eq 1 ]] || die_contract "usage: /review-post <request-file>"
REQUEST_FILE="$1"
[[ -r "$REQUEST_FILE" ]] || die_contract "request を読み取れません: $REQUEST_FILE"
command -v jq >/dev/null 2>&1 || die_contract "jq が必要です"

if ! REQUEST_JSON="$(strict_json "$REQUEST_FILE" 2>/dev/null)"; then
  die_contract "request は単一の JSON 値でなければなりません"
fi

if ! jq -e '
  def nonempty_string: type == "string" and length > 0;
  def nullable_string: type == "null" or nonempty_string;
  def valid_note: nullable_string;
  type == "object"
  and .schema_version == "1"
  and .artifact_type == "review-post-request"
  and (.engine | type == "string" and IN("magi", "codex"))
  and ((has("forge_host") | not) or (.forge_host | nonempty_string))
  and (.pr | type == "object"
       and (.owner | nonempty_string)
       and (.repo | nonempty_string)
       and (.number | type == "number" and floor == . and . > 0)
       and (.head_sha | nonempty_string))
  and (.inputs | type == "object"
       and has("findings_artifact")
       and has("adjudication_result")
       and has("diff")
       and (.findings_artifact == null or (.findings_artifact | nonempty_string))
       and (.adjudication_result == null or (.adjudication_result | nonempty_string))
       and (.diff | nonempty_string))
  and (.engine_state | type == "object"
       and (has("post_inline") and has("block_layer") and has("audit_note") and has("importance_note")
            and has("artifact_note") and has("normalized_results") and has("finding_list"))
       and (.post_inline | type == "boolean")
       and ((.block_layer | type) == "null" or (.block_layer | IN("structure", "audit", "importance")))
       and (.audit_note | valid_note)
       and (.importance_note | valid_note)
       and (.artifact_note | valid_note)
       and (.normalized_results | valid_note)
       and (.finding_list | valid_note))
  and (.result_path | nonempty_string)
  and ((.engine_state.block_layer != "structure" and .engine_state.block_layer != "audit")
       or .engine_state.post_inline == false)
  and (.engine_state.post_inline == true
       or .engine_state.block_layer == "structure"
       or .engine_state.block_layer == "audit")
  and (.engine_state.block_layer != "structure"
       or (.inputs.findings_artifact == null
           and .inputs.adjudication_result == null
           and (.engine_state.normalized_results | nonempty_string)))
  and (.engine_state.block_layer == "structure"
       or (.inputs.findings_artifact != null and .inputs.adjudication_result != null))
  and (.engine_state.block_layer != "audit"
       or (.engine_state.finding_list | nonempty_string))
  and (.engine_state.block_layer != "importance" or .engine_state.post_inline == true)
' <<<"$REQUEST_JSON" >/dev/null 2>&1; then
  die_contract "request の構造または層別組合せが不正です"
fi

ENGINE="$(jq -r '.engine' <<<"$REQUEST_JSON")"
ROOT="$(git rev-parse --show-toplevel 2>/dev/null || pwd)"
BUDGET_HELPER="$ROOT/skills/flow-common/execution-budget.sh"
[[ -r "$BUDGET_HELPER" ]] || BUDGET_HELPER="$HOME/.claude/skills/flow-common/execution-budget.sh"
REVIEW_POST_BUDGET=$(bash "$BUDGET_HELPER" get review_post "$ENGINE" 2>/dev/null || true)
REVIEW_POST_API_TIMEOUT=$(bash "$BUDGET_HELPER" review-post api_timeout 2>/dev/null || true)
REVIEW_POST_PAGE_LIMIT=$(bash "$BUDGET_HELPER" review-post page_limit 2>/dev/null || true)
REVIEW_POST_INLINE_SOFT=$(bash "$BUDGET_HELPER" review-post inline_soft 2>/dev/null || true)
: "${REVIEW_POST_API_TIMEOUT:=60}"
: "${REVIEW_POST_PAGE_LIMIT:=10}"
: "${REVIEW_POST_INLINE_SOFT:=1800}"
: "${REVIEW_POST_BUDGET:=3120}"

review_post_remaining() {
  local elapsed
  elapsed=$(( $(date +%s) - REVIEW_POST_STARTED_AT ))
  (( elapsed < REVIEW_POST_BUDGET )) || return 1
  printf '%s\n' "$((REVIEW_POST_BUDGET - elapsed))"
}

review_post_api() {
  local remaining limit
  remaining="$(review_post_remaining)" || return 124
  limit="$REVIEW_POST_API_TIMEOUT"
  (( remaining < limit )) && limit="$remaining"
  timeout "$limit" "$@"
}

OWNER="$(jq -r '.pr.owner' <<<"$REQUEST_JSON")"
REPO="$(jq -r '.pr.repo' <<<"$REQUEST_JSON")"
PR_NUM="$(jq -r '.pr.number' <<<"$REQUEST_JSON")"
FORGE_HOST="$(jq -r '.forge_host // "github.com"' <<<"$REQUEST_JSON")"
HEAD_SHA="$(jq -r '.pr.head_sha' <<<"$REQUEST_JSON")"
DIFF_FILE="$(jq -r '.inputs.diff' <<<"$REQUEST_JSON")"
RESULT_PATH="$(jq -r '.result_path' <<<"$REQUEST_JSON")"
POST_INLINE="$(jq -r '.engine_state.post_inline' <<<"$REQUEST_JSON")"
BLOCK_LAYER="$(jq -r '.engine_state.block_layer // ""' <<<"$REQUEST_JSON")"
AUDIT_NOTE="$(jq -r '.engine_state.audit_note // ""' <<<"$REQUEST_JSON")"
IMPORTANCE_NOTE="$(jq -r '.engine_state.importance_note // ""' <<<"$REQUEST_JSON")"
ARTIFACT_NOTE="$(jq -r '.engine_state.artifact_note // ""' <<<"$REQUEST_JSON")"
NORMALIZED_RESULTS="$(jq -r '.engine_state.normalized_results // ""' <<<"$REQUEST_JSON")"
FINDING_LIST="$(jq -r '.engine_state.finding_list // ""' <<<"$REQUEST_JSON")"
[[ -r "$DIFF_FILE" ]] || die_contract "diff を読み取れません: $DIFF_FILE"

MANAGED_SINGLEFLIGHT=false
SINGLEFLIGHT_PRESENT="$(jq -r 'has("singleflight")' <<<"$REQUEST_JSON")"
if [[ "$SINGLEFLIGHT_PRESENT" == true ]]; then
  if ! jq -e '
    (.singleflight) as $sf
    | ($sf | type == "object")
    and (["managed_by","tmpdir","owner_token_file","lease_file_ref","scope","canonical_key","lease_id","forge_host"]
         | all(.[]; . as $key | $sf | has($key)))
    and ($sf.managed_by == "review-hard")
    and ($sf.scope == "per_pr")
    and ($sf.tmpdir | type == "string" and length > 0)
    and ($sf.owner_token_file | type == "string" and length > 0)
    and ($sf.lease_file_ref | type == "string" and length > 0)
    and ($sf.canonical_key | type == "string" and length > 0)
    and ($sf.lease_id | type == "string" and length > 0)
    and ($sf.forge_host | type == "string" and length > 0)
  ' <<<"$REQUEST_JSON" >/dev/null 2>&1; then
    echo "review-post managed lease admission failure: singleflight object が不正です" >&2
    exit 2
  fi
  SINGLEFLIGHT_TMPDIR="$(jq -r '.singleflight.tmpdir' <<<"$REQUEST_JSON")"
  SINGLEFLIGHT_OWNER_TOKEN_FILE="$(jq -r '.singleflight.owner_token_file' <<<"$REQUEST_JSON")"
  SINGLEFLIGHT_STATE_FILE="$(jq -r '.singleflight.lease_file_ref' <<<"$REQUEST_JSON")"
  SINGLEFLIGHT_LEASE_ID="$(jq -r '.singleflight.lease_id' <<<"$REQUEST_JSON")"
  SINGLEFLIGHT_KEY="$(jq -r '.singleflight.canonical_key' <<<"$REQUEST_JSON")"
  SINGLEFLIGHT_FORGE_HOST="$(jq -r '.singleflight.forge_host' <<<"$REQUEST_JSON")"
  SINGLEFLIGHT_TMPDIR_REAL="$(realpath -e -- "$SINGLEFLIGHT_TMPDIR" 2>/dev/null || true)"
  SINGLEFLIGHT_OWNER_TOKEN_REAL="$(realpath -e -- "$SINGLEFLIGHT_OWNER_TOKEN_FILE" 2>/dev/null || true)"
  SINGLEFLIGHT_STATE_REAL="$(realpath -e -- "$SINGLEFLIGHT_STATE_FILE" 2>/dev/null || true)"
  EXPECTED_SINGLEFLIGHT_KEY="$(printf '%s\n%s/%s\n%s' "$SINGLEFLIGHT_FORGE_HOST" "${OWNER,,}" "${REPO,,}" "$PR_NUM")"
  if [[ "$SINGLEFLIGHT_TMPDIR" != /* || "$SINGLEFLIGHT_OWNER_TOKEN_FILE" != /* || "$SINGLEFLIGHT_STATE_FILE" != /* ]] \
    || [[ -z "$SINGLEFLIGHT_TMPDIR_REAL" || ! -d "$SINGLEFLIGHT_TMPDIR_REAL" || -L "$SINGLEFLIGHT_TMPDIR" ]] \
    || [[ -z "$SINGLEFLIGHT_OWNER_TOKEN_REAL" || ! -f "$SINGLEFLIGHT_OWNER_TOKEN_REAL" || -L "$SINGLEFLIGHT_OWNER_TOKEN_FILE" ]] \
    || [[ -z "$SINGLEFLIGHT_STATE_REAL" || ! -f "$SINGLEFLIGHT_STATE_REAL" || -L "$SINGLEFLIGHT_STATE_FILE" ]] \
    || [[ "$SINGLEFLIGHT_OWNER_TOKEN_REAL" != "$SINGLEFLIGHT_TMPDIR_REAL"/* ]] \
    || [[ "$SINGLEFLIGHT_STATE_REAL" != "$SINGLEFLIGHT_TMPDIR_REAL"/* ]] \
    || [[ "$SINGLEFLIGHT_FORGE_HOST" != "$FORGE_HOST" || "$SINGLEFLIGHT_KEY" != "$EXPECTED_SINGLEFLIGHT_KEY" ]]; then
    echo "review-post managed lease admission failure: singleflight path または canonical key が不正です" >&2
    exit 2
  fi
  SINGLEFLIGHT_TOKEN_OWNER="$(stat -c '%u' -- "$SINGLEFLIGHT_OWNER_TOKEN_REAL" 2>/dev/null || stat -f '%u' -- "$SINGLEFLIGHT_OWNER_TOKEN_REAL" 2>/dev/null || true)"
  SINGLEFLIGHT_TOKEN_MODE="$(stat -c '%a' -- "$SINGLEFLIGHT_OWNER_TOKEN_REAL" 2>/dev/null || stat -f '%Lp' -- "$SINGLEFLIGHT_OWNER_TOKEN_REAL" 2>/dev/null || true)"
  if [[ "$SINGLEFLIGHT_TOKEN_OWNER" != "$(id -u)" || "$SINGLEFLIGHT_TOKEN_MODE" != "600" || ! -s "$SINGLEFLIGHT_OWNER_TOKEN_REAL" ]]; then
    echo "review-post managed lease admission failure: owner token file の owner/mode/content が不正です" >&2
    exit 2
  fi
  SINGLEFLIGHT_TMP_OWNER="$(stat -c '%u' -- "$SINGLEFLIGHT_TMPDIR_REAL" 2>/dev/null || stat -f '%u' -- "$SINGLEFLIGHT_TMPDIR_REAL" 2>/dev/null || true)"
  SINGLEFLIGHT_TMP_MODE="$(stat -c '%a' -- "$SINGLEFLIGHT_TMPDIR_REAL" 2>/dev/null || stat -f '%Lp' -- "$SINGLEFLIGHT_TMPDIR_REAL" 2>/dev/null || true)"
  SINGLEFLIGHT_STATE_OWNER="$(stat -c '%u' -- "$SINGLEFLIGHT_STATE_REAL" 2>/dev/null || stat -f '%u' -- "$SINGLEFLIGHT_STATE_REAL" 2>/dev/null || true)"
  SINGLEFLIGHT_STATE_MODE="$(stat -c '%a' -- "$SINGLEFLIGHT_STATE_REAL" 2>/dev/null || stat -f '%Lp' -- "$SINGLEFLIGHT_STATE_REAL" 2>/dev/null || true)"
  if [[ "$SINGLEFLIGHT_TMP_OWNER" != "$(id -u)" || "$SINGLEFLIGHT_TMP_MODE" != "700" \
    || "$SINGLEFLIGHT_STATE_OWNER" != "$(id -u)" || "$SINGLEFLIGHT_STATE_MODE" != "600" || ! -s "$SINGLEFLIGHT_STATE_REAL" ]]; then
    echo "review-post managed lease admission failure: dispatch-state.json の owner/mode/content が不正です" >&2
    exit 2
  fi
  if ! jq -e --arg expected "$SINGLEFLIGHT_LEASE_ID" --arg token_file "$SINGLEFLIGHT_OWNER_TOKEN_FILE" \
    '.per_pr.acquired == true and .per_pr.lease_id == $expected and .owner_token_file == $token_file' \
    "$SINGLEFLIGHT_STATE_REAL" >/dev/null 2>&1; then
    echo "review-post managed lease admission failure: dispatch-state.json の lease_id が不正です" >&2
    exit 2
  fi
  SINGLEFLIGHT_HELPER="$ROOT/scripts/review-singleflight.sh"
  [[ -r "$SINGLEFLIGHT_HELPER" ]] || { echo "review-post managed lease admission failure: helper がありません" >&2; exit 2; }
  MANAGED_SINGLEFLIGHT=true
  # managed 判定から post lock gate を内部的に有効化する。非 managed request は従来どおり変更しない。
  REVIEW_POST_USE_LOCK=1
fi

sf_verify() {
  [[ "$MANAGED_SINGLEFLIGHT" == true ]] || return 0
  bash "$SINGLEFLIGHT_HELPER" verify --scope per_pr --key "$SINGLEFLIGHT_KEY" \
    --owner-token-file "$SINGLEFLIGHT_OWNER_TOKEN_FILE" --lease-id "$SINGLEFLIGHT_LEASE_ID" \
    >"$TMP_DIR/singleflight-verify-${1:-mutation}.out" 2>"$TMP_DIR/singleflight-verify-${1:-mutation}.err"
}

sf_renew() {
  [[ "$MANAGED_SINGLEFLIGHT" == true ]] || return 0
  local phase="$1" post_state="$2"
  bash "$SINGLEFLIGHT_HELPER" renew --scope per_pr --key "$SINGLEFLIGHT_KEY" \
    --owner-token-file "$SINGLEFLIGHT_OWNER_TOKEN_FILE" --lease-id "$SINGLEFLIGHT_LEASE_ID" \
    --current-phase "$phase" --phase-started-at "${REVIEW_SINGLEFLIGHT_NOW:-$(date +%s)}" --post-state "$post_state" \
    >"$TMP_DIR/singleflight-renew-${phase}.out" 2>"$TMP_DIR/singleflight-renew-${phase}.err"
}

TMP_DIR="$(mktemp -d)"
trap 'rm -rf -- "$TMP_DIR"' EXIT HUP INT TERM

ARTIFACT_JSON='null'
ADJUDICATION_JSON='null'
ARTIFACT_FINDINGS='[]'
ADJUDICATION_RESULTS='[]'
GROUNDING_STATUS="skipped"
GROUNDING_NOTE=""
DETECTION_NOTE=""

ARTIFACT_PATH="$(jq -r '.inputs.findings_artifact // ""' <<<"$REQUEST_JSON")"
ADJUDICATION_PATH="$(jq -r '.inputs.adjudication_result // ""' <<<"$REQUEST_JSON")"

if [[ "$BLOCK_LAYER" == "structure" ]]; then
  # structure 経路は raw の report-only。canonical artifact はまだ存在しない。
  :
else
  [[ -r "$ARTIFACT_PATH" ]] || die_contract "findings artifact を読み取れません: $ARTIFACT_PATH"
  [[ -r "$ADJUDICATION_PATH" ]] || die_contract "adjudication result を読み取れません: $ADJUDICATION_PATH"
  if ! ARTIFACT_JSON="$(strict_json "$ARTIFACT_PATH" 2>/dev/null)"; then
    die_contract "findings artifact は単一の JSON 値でなければなりません"
  fi
  if ! jq -e --arg engine "$ENGINE" '
    def nonempty_string: type == "string" and length > 0;
    def valid_line: type == "null" or (type == "number" and floor == . and . > 0);
    def personas: ["MELCHIOR", "BALTHASAR", "METATRON", "SANDALPHON", "LELIEL", "CASPER"];
    type == "object"
    and .schema_version == "1"
    and .engine == $engine
    and has("detection_status")
    and (.detection_status | type == "string" and IN("complete", "incomplete", "unknown"))
    and has("failed_personas")
    and (
      if .failed_personas == null then true
      else
        (.failed_personas | type) == "array"
        and all(.failed_personas[];
          . as $persona
          | type == "string" and length > 0 and (personas | index($persona)) != null
        )
        and ((.failed_personas | length) == (.failed_personas | unique | length))
      end
    )
    and (
      (.detection_status == "complete" and .failed_personas == [])
      or (.detection_status == "incomplete" and (.failed_personas | type) == "array" and (.failed_personas | length) > 0)
      or (.detection_status == "unknown" and .failed_personas == null)
    )
    and (.findings | type == "array")
    and ([.findings[].id] | length) == ([.findings[].id] | unique | length)
    and all(.findings[];
      type == "object"
      and has("id") and (.id | nonempty_string)
      and has("source_persona") and (.source_persona | nonempty_string)
      and has("path") and (.path | nonempty_string)
      and has("line") and (.line | valid_line)
      and has("headline") and (.headline | nonempty_string)
      and has("body") and (.body | nonempty_string)
      and has("evidence")
      and ((.evidence | type) == "null"
           or (.evidence | type == "string" and length > 0)))
  ' <<<"$ARTIFACT_JSON" >/dev/null 2>&1; then
    die_contract "findings artifact の構造が不正です"
  fi
  ARTIFACT_FINDINGS="$(jq -c '.findings' <<<"$ARTIFACT_JSON")"
  DETECTION_STATUS="$(jq -r '.detection_status' <<<"$ARTIFACT_JSON")"
  FAILED_PERSONAS="$(jq -r '(.failed_personas // []) | if length == 0 then "" else join(", ") end' <<<"$ARTIFACT_JSON")"
  if [[ "$DETECTION_STATUS" != "complete" ]]; then
    DETECTION_NOTE="検出層: $DETECTION_STATUS（失敗ペルソナ: ${FAILED_PERSONAS:-なし}）"
  else
    DETECTION_NOTE=""
  fi

  if ! ADJUDICATION_JSON="$(strict_json "$ADJUDICATION_PATH" 2>/dev/null)"; then
    die_contract "adjudication result は単一の JSON 値でなければなりません"
  fi
  if ! jq -e '
    type == "object"
    and .schema_version == "1"
    and .artifact_type == "review-adjudication"
    and (.validity_global_failure | type == "boolean")
    and (.results | type == "array")
    and ([.results[].id] | length) == ([.results[].id] | unique | length)
    and all(.results[];
      type == "object"
      and has("id") and (.id | type == "string" and length > 0)
      and has("verdict")
      and ((.verdict | type) == "null"
           or (.verdict | type == "string" and IN("valid", "false_positive", "needs_human")))
      and has("importance_status")
      and (.importance_status | type == "string" and IN("ok", "failed", "not_applicable"))
      and has("reported_gate")
      and ((.reported_gate | type) == "null"
           or (.reported_gate | type == "string" and IN("block", "defer", "manual")))
      and has("final_gate")
      and ((.final_gate | type) == "null"
           or (.final_gate | type == "string" and IN("block", "defer")))
      and has("importance")
      and ((.importance | type) == "null"
           or (.importance | type == "string" and IN("HIGH", "MEDIUM", "LOW"))))
  ' <<<"$ADJUDICATION_JSON" >/dev/null 2>&1; then
    die_contract "adjudication result の構造が不正です"
  fi
  ADJUDICATION_RESULTS="$(jq -c '.results' <<<"$ADJUDICATION_JSON")"
  if ! jq -n -e --argjson artifact "$ARTIFACT_FINDINGS" --argjson results "$ADJUDICATION_RESULTS" '
    ($artifact | map(.id) | sort) as $artifact_ids
    | ($results | map(.id) | sort) as $result_ids
    | $artifact_ids == $result_ids
  ' >/dev/null 2>&1; then
    die_contract "artifact と adjudication の finding ID 集合が一致しません"
  fi
  if ! jq -e --arg layer "$BLOCK_LAYER" '
    if .validity_global_failure == true
    then ($layer == "audit")
    else true
    end
  ' <<<"$ADJUDICATION_JSON" >/dev/null 2>&1; then
    die_contract "validity_global_failure と投稿経路の組合せが不正です"
  fi
  if [[ "$BLOCK_LAYER" != "audit" ]] && ! jq -e 'all(.[]; .final_gate != null)' <<<"$ADJUDICATION_RESULTS" >/dev/null 2>&1; then
    die_contract "通常投稿経路の adjudication に final_gate がありません"
  fi
fi

ANCHORS_DATA='[]'
if [[ "$BLOCK_LAYER" != "structure" ]]; then
  DIFF_COMMENTABLE_LINES="$TMP_DIR/diff-commentable-lines.json"
  if ! awk '
    function emit_line(path, side, line, key) {
      key = path SUBSEP side SUBSEP line
      if (!seen[key]++) print path "\t" side "\t" line
    }

    /^diff --git / {
      header = $0
      sub(/^diff --git a\//, "", header)
      separator = index(header, " b/")
      current_b_path = separator > 0 ? substr(header, separator + 3) : ""
      in_hunk = 0
      next
    }

    /^@@ / {
      if (current_b_path == "") {
        in_hunk = 0
        next
      }
      hunk = $0
      sub(/^@@ -/, "", hunk)
      split(hunk, ranges, " ")
      old_spec = ranges[1]
      new_spec = ranges[2]
      sub(/^\+/, "", new_spec)
      split(old_spec, old_parts, ",")
      split(new_spec, new_parts, ",")
      old_line = old_parts[1] + 0
      new_line = new_parts[1] + 0
      in_hunk = 1
      next
    }

    !in_hunk { next }
    /^\\ No newline at end of file$/ { next }

    {
      prefix = substr($0, 1, 1)
      if (prefix == "+") {
        emit_line(current_b_path, "RIGHT", new_line)
        new_line++
        next
      }
      if (prefix == "-") {
        emit_line(current_b_path, "LEFT", old_line)
        old_line++
        next
      }
      if (prefix == " ") {
        emit_line(current_b_path, "RIGHT", new_line)
        emit_line(current_b_path, "LEFT", old_line)
        old_line++
        new_line++
      }
    }
  ' "$DIFF_FILE" | jq -Rn '
    reduce inputs as $row ({};
      ($row | split("\t")) as $fields
      | .[$fields[0]] = (.[$fields[0]] // {RIGHT:[], LEFT:[]})
      | .[$fields[0]][$fields[1]] += [($fields[2] | tonumber)]
    )
    | with_entries(.value |= with_entries(.value |= sort))
  ' >"$DIFF_COMMENTABLE_LINES"; then
    printf '%s\n' '{}' >"$DIFF_COMMENTABLE_LINES"
  fi
  NULL_LINE_ANCHORS="$(jq -c '[.[] | select(.line == null) | {id, anchored_path:"", anchored_line:0, side:"", anchor_status:"unanchorable"}]' <<<"$ARTIFACT_FINDINGS")"
  GROUNDABLE_TABLE="$TMP_DIR/groundable.json"
  jq -n --argjson findings "$ARTIFACT_FINDINGS" \
    '{schema_version:"1", findings: [$findings[] | select(.line != null) | {
      id: .id, body: .body, evidence: .evidence,
      original_path: .path, original_line: .line
    }]}' >"$GROUNDABLE_TABLE"
  GROUNDABLE_COUNT="$(jq '.findings | length' "$GROUNDABLE_TABLE")"
  if [[ "$GROUNDABLE_COUNT" -eq 0 ]]; then
    ANCHORS_DATA="$NULL_LINE_ANCHORS"
  else
    GROUNDING_OUTPUT="$TMP_DIR/anchors.json"
    GROUNDING_ERR="$TMP_DIR/grounding.err"
    GROUNDING_EXIT=0
    bash "$ROOT/scripts/magi-ground-findings.sh" "$GROUNDABLE_TABLE" "$DIFF_FILE" \
      >"$GROUNDING_OUTPUT" 2>"$GROUNDING_ERR" || GROUNDING_EXIT=$?
    GROUNDING_VALID=false
    if [[ "$GROUNDING_EXIT" -eq 0 ]] && ANCHORS_JSON="$(strict_json "$GROUNDING_OUTPUT" 2>/dev/null)"; then
      if jq -e --slurpfile diff_lines "$DIFF_COMMENTABLE_LINES" '
        def commentable_anchor:
          if (.anchored_path | type) != "string"
             or (.anchored_line | type) != "number"
             or (.side | type) != "string"
          then false
          else
            .anchored_path as $path
            | .anchored_line as $line
            | .side as $side
            | (($diff_lines[0][$path] // {})[$side] // [] | index($line)) != null
          end;
        type == "object"
        and .schema_version == "1"
        and (.anchors | type == "array")
        and ([.anchors[].id] | length) == ([.anchors[].id] | unique | length)
        and all(.anchors[];
          type == "object"
          and (.id | type == "string" and length > 0)
          and (.anchor_status | type == "string"
               and IN("ok", "corrected", "unverified", "unanchorable"))
          and (if .anchor_status == "ok" or .anchor_status == "corrected"
               then (.anchored_path | type == "string" and length > 0)
                    and (.anchored_line | type == "number" and floor == . and . > 0)
                    and (.side | type == "string" and IN("RIGHT", "LEFT"))
                    and commentable_anchor
               elif .anchor_status == "unverified"
               then (.anchored_path | type == "string" and length > 0)
                    and (.anchored_line | type == "number" and floor == . and . > 0)
                    and (.side | type == "string" and . == "RIGHT")
                    and commentable_anchor
               else true end))
      ' <<<"$ANCHORS_JSON" >/dev/null 2>&1; then
        ANCHORS_FROM_GROUNDER="$(jq -c '.anchors' <<<"$ANCHORS_JSON")"
        EXPECTED_IDS="$(jq -c '[.findings[].id]' "$GROUNDABLE_TABLE")"
        if jq -n -e --argjson expected "$EXPECTED_IDS" \
          --argjson actual "$ANCHORS_FROM_GROUNDER" \
          '($actual | map(.id) | sort) == ($expected | sort)' >/dev/null 2>&1; then
          ANCHORS_DATA="$(jq -n --argjson grounded "$ANCHORS_FROM_GROUNDER" --argjson nulls "$NULL_LINE_ANCHORS" '$grounded + $nulls')"
          GROUNDING_VALID=true
        fi
      fi
    fi
    if [[ "$GROUNDING_VALID" != true ]]; then
      ANCHORS_DATA="$(jq -n --argjson findings "$ARTIFACT_FINDINGS" '[ $findings[] | {id, anchored_path:"", anchored_line:0, side:"", anchor_status:"unanchorable"} ]')"
      GROUNDING_NOTE="GROUNDING_FAILED（アンカーを確認できなかったため全件を通常PRコメントとして投稿する）"
    fi
  fi
  GROUNDING_STATUS="complete"
fi

ENRICHED_FINDINGS="[]"
if [[ "$BLOCK_LAYER" != "structure" ]]; then
  ENRICHED_FINDINGS="$(jq -n -c --argjson findings "$ARTIFACT_FINDINGS" --argjson anchors "$ANCHORS_DATA" '
    ($anchors | map({key:.id, value:.}) | from_entries) as $by_id
    | $findings | map(
        . as $finding
        | ($by_id[$finding.id] // {anchored_path:"", anchored_line:0, side:"", anchor_status:"unanchorable"}) as $anchor
        | $finding + {
            anchored_path: (if $anchor.anchor_status == "unanchorable" then "" else $anchor.anchored_path end),
            anchored_line: (if $anchor.anchor_status == "unanchorable" then 0 else $anchor.anchored_line end),
            side: (if $anchor.anchor_status == "unanchorable" then "" else $anchor.side end),
            anchor_status: ($anchor.anchor_status // "unanchorable")
          }
      )
  ' )"
fi

ENGINE_LABEL="$(if [[ "$ENGINE" == "codex" ]]; then printf '%s' 'CODEX-HARD'; else printf '%s' 'MAGI-HARD'; fi)"
PERSONA_ROWS='["MELCHIOR","BALTHASAR","CASPER","METATRON","SANDALPHON","LELIEL"]'
BLOCK_ROWS='[]'
if [[ "$BLOCK_LAYER" != "structure" ]]; then
  BLOCK_ROWS="$(jq -n -c --argjson findings "$ENRICHED_FINDINGS" --argjson results "$ADJUDICATION_RESULTS" '
    [ $results[] | select(.final_gate == "block") as $result
      | ($findings[] | select(.id == $result.id)) as $finding
      | $finding + {final_gate:$result.final_gate, importance:$result.importance} ]
  ' )"
fi
TOTAL_FINDINGS="$(jq 'length' <<<"$ARTIFACT_FINDINGS")"
BLOCK_COUNT="$(jq '[.[] | select(.final_gate == "block")] | length' <<<"$ADJUDICATION_RESULTS")"
DEFER_COUNT="$(jq '[.[] | select(.final_gate == "defer")] | length' <<<"$ADJUDICATION_RESULTS")"
UNRATED_COUNT="$(jq '[.[] | select(.final_gate == "block" and .importance == null)] | length' <<<"$ADJUDICATION_RESULTS")"

SUMMARY_MARKDOWN="$(jq -r --arg label "$ENGINE_LABEL" --argjson rows "$BLOCK_ROWS" --argjson personas "$PERSONA_ROWS" '
  def viewpoint:
    if . == "MELCHIOR" then "コード品質・バグ"
    elif . == "BALTHASAR" then "設計・アーキテクチャ"
    elif . == "CASPER" then "ルール遵守"
    elif . == "METATRON" then "セキュリティ"
    elif . == "SANDALPHON" then "実行環境・デプロイ"
    elif . == "LELIEL" then "既存ソース影響"
    else "レビュー観点" end;
  ("## " + $label + " レビュー完了\n\n"
   + "| ペルソナ | HIGH | MEDIUM | LOW |\n"
   + "|---------|------|--------|-----|\n"
   + ($personas | map(. as $p
       | ($rows | map(select(.source_persona == $p))) as $mine
       | "| " + $p + "（" + ($p | viewpoint) + "） | "
         + (([$mine[] | select(.importance == "HIGH")] | length) | tostring) + " | "
         + (([$mine[] | select(.importance == "MEDIUM")] | length) | tostring) + " | "
         + (([$mine[] | select(.importance == "LOW")] | length) | tostring) + " |") | join("\n"))
   + "\n\n**HIGH: "
   + (([$rows[] | select(.importance == "HIGH")] | length) | tostring)
   + "件 / MEDIUM: "
   + (([$rows[] | select(.importance == "MEDIUM")] | length) | tostring)
   + "件 / LOW: "
   + (([$rows[] | select(.importance == "LOW")] | length) | tostring)
   + "件**")
  + (if ($rows | length) == 0 then "\n\n投稿対象はありません。" else "\n\n各行への指摘はインラインコメントまたは通常PRコメントとして続けて投稿します。" end)
  + (if ([ $rows[] | select(.importance == null) ] | length) > 0
     then "\n\n> ⚠ 重要度未評価: " + (([$rows[] | select(.importance == null)] | length) | tostring) + "件（severity表の列外）"
     else "" end)
' <<<"$BLOCK_ROWS")"

append_summary_note() {
  local label="$1"
  local value="$2"
  if [[ -n "$value" ]]; then
    SUMMARY_MARKDOWN+=$'\n\n> ⚠ '
    SUMMARY_MARKDOWN+="$label: $value"
  fi
}
append_summary_note "Codex 監査" "$AUDIT_NOTE"
append_summary_note "重要度判定" "$IMPORTANCE_NOTE"
append_summary_note "grounding" "$GROUNDING_NOTE"
append_summary_note "canonical artifact" "$ARTIFACT_NOTE"
append_summary_note "検出状態" "$DETECTION_NOTE"

if [[ "$POST_INLINE" == "false" ]]; then
  if [[ "$BLOCK_LAYER" == "structure" ]]; then
    SUMMARY_MARKDOWN+=$'\n\n> ⚠ 指摘の構造化に失敗したため未整形のまま一覧表示する\n\n<details><summary>未整形の指摘一覧</summary>\n\n'
    SUMMARY_MARKDOWN+="$NORMALIZED_RESULTS"
    SUMMARY_MARKDOWN+=$'\n\n</details>'
  elif [[ "$BLOCK_LAYER" == "audit" ]]; then
    SUMMARY_MARKDOWN+=$'\n\n> ⚠ Codex 監査が実行できなかったため指摘は投稿せず以下に一覧表示する\n\n<details><summary>未監査の指摘一覧</summary>\n\n'
    SUMMARY_MARKDOWN+="$FINDING_LIST"
    SUMMARY_MARKDOWN+=$'\n\n</details>'
  fi
fi

SUMMARY_FP="$(printf '%s\0' 'review-post:v1' 'summary' "$ENGINE_LABEL" "$HEAD_SHA" | sha256sum | cut -c1-24)"
SUMMARY_MARKER="<!-- review-post:v1 kind=summary engine=$ENGINE_LABEL head_sha=$HEAD_SHA fp=$SUMMARY_FP -->"
SUMMARY_MARKDOWN="${SUMMARY_MARKDOWN}"$'\n\n'"${SUMMARY_MARKER}"

DELIVERY_JSON="$(jq -n -c --argjson results "$ADJUDICATION_RESULTS" --arg inline "$POST_INLINE" '
  reduce $results[] as $result ({};
    .[$result.id] = (if $result.final_gate == "block"
                     then (if $inline == "false" then "summary_only" else "not_posted" end)
                     else "not_posted" end))
' )"
REUSED_JSON='{}'
GITHUB_WRITES='[]'
GITHUB_FAILED=false
POST_LOCK_READY=true
POST_LOCK_ACQUIRED=false

# PR-2 の step 2 / 6 と、PR-3 の step 1 / 3 / 4 / 5 を managed request に接続する。
# singleflight 欠如時だけ REVIEW_POST_USE_LOCK の明示 opt-in という従来動作を残す。
if [[ "$MANAGED_SINGLEFLIGHT" == true || "${REVIEW_POST_USE_LOCK:-0}" == "1" ]]; then
  REVIEW_POST_LOCK_BUDGET="$(review_post_remaining || true)"
  REVIEW_POST_LOCK_BUDGET_EXPIRED=false
  REVIEW_POST_LOCK_BUDGET_DISPLAY="$REVIEW_POST_LOCK_BUDGET"
  if [[ ! "$REVIEW_POST_LOCK_BUDGET" =~ ^[1-9][0-9]*$ ]]; then
    # 全体予算を使い切った場合は追加 wait をせず、診断上の最小待機単位だけ表示する。
    REVIEW_POST_LOCK_BUDGET_EXPIRED=true
    REVIEW_POST_LOCK_BUDGET_DISPLAY=1
  fi
  POST_LOCK_HASH="$(printf '%s\0%s/%s\0%s' "$FORGE_HOST" "${OWNER,,}" "${REPO,,}" "$PR_NUM" | sha256sum | cut -d' ' -f1)"
  POST_LOCK_PREFIX="$(printf '%s-%s-%s' "${OWNER,,}" "${REPO,,}" "$PR_NUM" | tr -cs 'a-z0-9._-' '-' | cut -c1-48)"
  if [[ "$MANAGED_SINGLEFLIGHT" == true ]]; then
    [[ -n "${XDG_RUNTIME_DIR:-}" ]] || { echo "review-post managed lease admission failure: XDG_RUNTIME_DIR がありません" >&2; exit 2; }
    POST_LOCK_RUNTIME="$XDG_RUNTIME_DIR"
  else
    POST_LOCK_RUNTIME="${XDG_RUNTIME_DIR:-/tmp}"
  fi
  POST_LOCK="$POST_LOCK_RUNTIME/claude-review-post-${POST_LOCK_PREFIX}-${POST_LOCK_HASH}.lock"
  if ! mkdir -p "$(dirname "$POST_LOCK")"; then
    echo "review-post lock directory を作成できません: $(dirname "$POST_LOCK")" >&2
    POST_LOCK_READY=false
    GITHUB_FAILED=true
  elif ! { exec 8>"$POST_LOCK"; } 2>/dev/null; then
    echo "review-post lock file を開けません: $POST_LOCK" >&2
    POST_LOCK_READY=false
    GITHUB_FAILED=true
  elif [[ "$REVIEW_POST_LOCK_BUDGET_EXPIRED" == true ]] \
    || ! flock -w "$REVIEW_POST_LOCK_BUDGET" -E 9 8; then
    echo "review-post 排他ロックを${REVIEW_POST_LOCK_BUDGET_DISPLAY}秒以内に取得できませんでした" >&2
    exec 8>&- 2>/dev/null || true
    POST_LOCK_READY=false
    GITHUB_FAILED=true
  else
    POST_LOCK_ACQUIRED=true
  fi
fi
if [[ "$MANAGED_SINGLEFLIGHT" == true && "$POST_LOCK_READY" != true ]]; then
  echo "review-post managed lease admission failure: post lock を取得できません" >&2
  exit 2
fi
if [[ "$MANAGED_SINGLEFLIGHT" == true ]]; then
  # post lock 内で current per_pr lease_id と token を再確認する（fencing step 3/4）。
  if ! sf_verify "post-lock"; then
    echo "review-post managed lease admission failure: per_pr lease verify に失敗しました" >&2
    exit 2
  fi
fi

record_write() {
  local kind="$1"
  local url="$2"
  local operation="${3:-create}"
  GITHUB_WRITES="$(jq -c --arg kind "$kind" --arg url "$url" --arg operation "$operation" '. + [{kind:$kind, url:$url, operation:$operation}]' <<<"$GITHUB_WRITES")"
}

ISSUE_COMMENTS_RAW="$TMP_DIR/issue-comments.raw"
ISSUE_COMMENTS_ERR="$TMP_DIR/issue-comments.err"
PULL_COMMENTS_RAW="$TMP_DIR/pull-comments.raw"
PULL_COMMENTS_ERR="$TMP_DIR/pull-comments.err"
ISSUE_LIST_EXIT=0
: > "$ISSUE_COMMENTS_RAW"
# execution-budget.json: review_post pagination hard budget
if [[ "$POST_LOCK_READY" == true ]]; then
  for PAGE in $(seq 1 "$REVIEW_POST_PAGE_LIMIT"); do
    PAGE_RAW="$TMP_DIR/issue-comments-$PAGE.json"
    review_post_api gh api "repos/$OWNER/$REPO/issues/$PR_NUM/comments?page=$PAGE&per_page=100" >"$PAGE_RAW" 2>"$ISSUE_COMMENTS_ERR" || {
      ISSUE_LIST_EXIT=$?
      break
    }
    PAGE_COUNT="$(jq -s -e 'if length == 1 and (.[0] | type) == "array" then (.[0] | length) else error("expected exactly one array") end' "$PAGE_RAW" 2>/dev/null)" || {
      ISSUE_LIST_EXIT=1
      break
    }
    [[ "$PAGE_COUNT" -gt 0 ]] || break
    jq -c '.[] | {id, body, login: (.user.login // null)}' "$PAGE_RAW" >> "$ISSUE_COMMENTS_RAW" || {
      ISSUE_LIST_EXIT=1
      break
    }
    if [[ "$PAGE_COUNT" -eq 100 && "$PAGE" -eq "$REVIEW_POST_PAGE_LIMIT" ]]; then
      ISSUE_LIST_EXIT=1
      break
    fi
    [[ "$PAGE_COUNT" -eq 100 ]] || break
  done
else
  ISSUE_LIST_EXIT=1
fi
PULL_LIST_EXIT=0
: > "$PULL_COMMENTS_RAW"
if [[ "$POST_LOCK_READY" == true ]]; then
  for PAGE in $(seq 1 "$REVIEW_POST_PAGE_LIMIT"); do
    PAGE_RAW="$TMP_DIR/pull-comments-$PAGE.json"
    review_post_api gh api "repos/$OWNER/$REPO/pulls/$PR_NUM/comments?page=$PAGE&per_page=100" >"$PAGE_RAW" 2>"$PULL_COMMENTS_ERR" || {
      PULL_LIST_EXIT=$?
      break
    }
    PAGE_COUNT="$(jq -s -e 'if length == 1 and (.[0] | type) == "array" then (.[0] | length) else error("expected exactly one array") end' "$PAGE_RAW" 2>/dev/null)" || {
      PULL_LIST_EXIT=1
      break
    }
    [[ "$PAGE_COUNT" -gt 0 ]] || break
    jq -c '.[] | {id, body, login: (.user.login // null)}' "$PAGE_RAW" >> "$PULL_COMMENTS_RAW" || {
      PULL_LIST_EXIT=1
      break
    }
    if [[ "$PAGE_COUNT" -eq 100 && "$PAGE" -eq "$REVIEW_POST_PAGE_LIMIT" ]]; then
      PULL_LIST_EXIT=1
      break
    fi
    [[ "$PAGE_COUNT" -eq 100 ]] || break
  done
else
  PULL_LIST_EXIT=1
fi

MY_LOGIN_ERR="$TMP_DIR/whoami.err"
MY_LOGIN=""
MY_LOGIN_EXIT=0
if [[ "$POST_LOCK_READY" == true ]]; then
  MY_LOGIN="$(review_post_api gh api user \
    --jq 'if (.login | type) == "string" and (.login | length) > 0 then .login else error("missing login") end' \
    2>"$MY_LOGIN_ERR")" || MY_LOGIN_EXIT=$?
else
  MY_LOGIN_EXIT=1
fi
if [[ "$MY_LOGIN_EXIT" -eq 0 && -z "$MY_LOGIN" ]]; then
  MY_LOGIN_EXIT=1
fi

ISSUE_COMMENTS='[]'
if [[ "$ISSUE_LIST_EXIT" -eq 0 ]] && ! ISSUE_COMMENTS="$(jq -s -c '.' "$ISSUE_COMMENTS_RAW" 2>/dev/null)"; then
  ISSUE_LIST_EXIT=1
fi
PULL_COMMENTS='[]'
if [[ "$PULL_LIST_EXIT" -eq 0 ]] && ! PULL_COMMENTS="$(jq -s -c '.' "$PULL_COMMENTS_RAW" 2>/dev/null)"; then
  PULL_LIST_EXIT=1
fi

SUMMARY_ERR="$TMP_DIR/summary.err"
SUMMARY_URL=""
SUMMARY_EXIT=0
if [[ "$ISSUE_LIST_EXIT" -ne 0 || "$PULL_LIST_EXIT" -ne 0 || "$MY_LOGIN_EXIT" -ne 0 ]]; then
  # 既存コメントを確認できない場合は、重複投稿を避けるため fail-closed にする。
  SUMMARY_EXIT=1
  GITHUB_FAILED=true
else
  if [[ "$MANAGED_SINGLEFLIGHT" == true ]]; then
    # GET/dedup の後、サマリ phase へ遷移して mutation 直前に再確認する。
    if ! sf_renew "summary" "in_progress" || ! sf_verify "summary"; then
      echo "review-post managed lease admission failure: GitHub mutation 前の per_pr renew に失敗しました" >&2
      exit 2
    fi
  fi
  SUMMARY_COMMENT_ID="$(jq -r --arg marker "$SUMMARY_MARKER" --arg my_login "$MY_LOGIN" '
    [ .[]
      | select((.body | type) == "string" and (.body | endswith($marker)) and (.login == $my_login))
      | select((.id | type) == "number" and (.id | floor) == .id)
    ]
    | sort_by(.id) | .[0].id // empty
  ' <<<"$ISSUE_COMMENTS")"
  if [[ -n "$SUMMARY_COMMENT_ID" ]]; then
    SUMMARY_URL=""
    if ! sf_verify "summary-patch"; then
      echo "review-post managed lease admission failure: summary PATCH 直前の verify に失敗しました" >&2
      exit 2
    fi
    SUMMARY_URL="$(review_post_api gh api -X PATCH "repos/$OWNER/$REPO/issues/comments/$SUMMARY_COMMENT_ID" \
      -f body="$SUMMARY_MARKDOWN" --jq '.html_url' 2>"$SUMMARY_ERR")" || SUMMARY_EXIT=$?
    if [[ "$SUMMARY_EXIT" -eq 0 ]]; then
      record_write "summary" "$SUMMARY_URL" update
    else
      GITHUB_FAILED=true
    fi
  else
    if ! sf_verify "summary-post"; then
      echo "review-post managed lease admission failure: summary POST 直前の verify に失敗しました" >&2
      exit 2
    fi
    SUMMARY_URL="$(review_post_api gh api -X POST "repos/$OWNER/$REPO/issues/$PR_NUM/comments" \
      -f body="$SUMMARY_MARKDOWN" --jq '.html_url' 2>"$SUMMARY_ERR")" || SUMMARY_EXIT=$?
    if [[ "$SUMMARY_EXIT" -eq 0 ]]; then
      record_write "summary" "$SUMMARY_URL"
    else
      GITHUB_FAILED=true
    fi
  fi
fi

set_delivery() {
  local id="$1"
  local delivery="$2"
  local reused="${3:-false}"
  DELIVERY_JSON="$(jq -c --arg id "$id" --arg delivery "$delivery" '.[$id] = $delivery' <<<"$DELIVERY_JSON")"
  REUSED_JSON="$(jq -c --arg id "$id" --argjson reused "$reused" '.[$id] = $reused' <<<"$REUSED_JSON")"
}

post_pr_comment() {
  local id="$1"
  local severity="$2"
  local persona="$3"
  local path="$4"
  local line="$5"
  local body="$6"
  local prefix="$7"
  local marker="$8"
  local comment_body
  local error_file="$TMP_DIR/comment-$id.err"
  local url=""
  local status=0
  if ! sf_verify "fallback-$id"; then
    echo "review-post managed lease admission failure: fallback POST 直前の verify に失敗しました" >&2
    return 2
  fi
  comment_body="$(printf '[%s] **[%s] %s** `%s:%s`\n\n%s' "$prefix" "$severity" "$persona" "$path" "$line" "$body")"
  comment_body="${comment_body}"$'\n\n'"${marker}"
  url="$(review_post_api gh api -X POST "repos/$OWNER/$REPO/issues/$PR_NUM/comments" \
    -f body="$comment_body" --jq '.html_url' 2>"$error_file")" || status=$?
  if [[ "$status" -ne 0 ]]; then
    GITHUB_FAILED=true
    return 1
  fi
  record_write "pr_comment" "$url"
  set_delivery "$id" "pr_comment"
  return 0
}

if [[ "$MANAGED_SINGLEFLIGHT" == true && "$SUMMARY_EXIT" -eq 0 && "$POST_INLINE" == "true" && "$BLOCK_COUNT" -gt 0 ]]; then
  if ! sf_renew "inline" "in_progress"; then
    echo "review-post managed lease admission failure: inline phase への renew に失敗しました" >&2
    exit 2
  fi
fi

if [[ "$SUMMARY_EXIT" -eq 0 && "$POST_INLINE" == "true" && "$BLOCK_COUNT" -gt 0 ]]; then
  PULL_REMAINING="$(jq -c --arg engine "$ENGINE_LABEL" --arg head_sha "$HEAD_SHA" --arg my_login "$MY_LOGIN" '
    reduce .[] as $comment ({};
      if ($comment.body | type) != "string" then .
      else
        (try ($comment.body | split("\n") | .[-1]
          | capture("^<!-- review-post:v1 kind=(?<kind>finding) engine=(?<engine>[^ ]+) head_sha=(?<head_sha>[^ ]+) fp=(?<fp>[0-9a-f]{24}) -->$")) catch null) as $marker
        | if $marker != null and $comment.login == $my_login and $marker.engine == $engine and $marker.head_sha == $head_sha
          then .[$marker.fp] = ((.[$marker.fp] // 0) + 1)
          else .
          end
      end
    )
  ' <<<"$PULL_COMMENTS")"
  ISSUE_REMAINING="$(jq -c --arg engine "$ENGINE_LABEL" --arg head_sha "$HEAD_SHA" --arg my_login "$MY_LOGIN" '
    reduce .[] as $comment ({};
      if ($comment.body | type) != "string" then .
      else
        (try ($comment.body | split("\n") | .[-1]
          | capture("^<!-- review-post:v1 kind=(?<kind>finding) engine=(?<engine>[^ ]+) head_sha=(?<head_sha>[^ ]+) fp=(?<fp>[0-9a-f]{24}) -->$")) catch null) as $marker
        | if $marker != null and $comment.login == $my_login and $marker.engine == $engine and $marker.head_sha == $head_sha
          then .[$marker.fp] = ((.[$marker.fp] // 0) + 1)
          else .
          end
      end
    )
  ' <<<"$ISSUE_COMMENTS")"
  # execution-budget.json: review_post inline post loop (soft)
  INLINE_STARTED_AT=$(date +%s)
  while IFS= read -r FINDING_ROW; do
    if [[ "$(( $(date +%s) - INLINE_STARTED_AT ))" -ge "$REVIEW_POST_INLINE_SOFT" ]]; then
      DELIVERY_JSON="$(jq -c --argjson rows "$BLOCK_ROWS" '
        reduce $rows[].id as $id (.;
          if .[$id] == "not_posted" then .[$id] = "summary_only" else . end)
      ' <<<"$DELIVERY_JSON")"
      break
    fi
    ID="$(jq -r '.id' <<<"$FINDING_ROW")"
    STATUS="$(jq -r '.anchor_status // "unanchorable"' <<<"$FINDING_ROW")"
    SEVERITY="$(jq -r --arg id "$ID" --argjson results "$ADJUDICATION_RESULTS" 'first($results[] | select(.id == $id) | (.importance // "UNRATED"))' <<<"$FINDING_ROW")"
    PERSONA="$(jq -r '.source_persona' <<<"$FINDING_ROW")"
    case "$PERSONA" in
      MELCHIOR) VIEWPOINT="コード品質・バグ" ;;
      BALTHASAR) VIEWPOINT="設計・アーキテクチャ" ;;
      CASPER) VIEWPOINT="ルール遵守" ;;
      METATRON) VIEWPOINT="セキュリティ" ;;
      SANDALPHON) VIEWPOINT="実行環境・デプロイ" ;;
      LELIEL) VIEWPOINT="既存ソース影響" ;;
      *) VIEWPOINT="レビュー観点" ;;
    esac
    ORIGINAL_PATH="$(jq -r '.path' <<<"$FINDING_ROW")"
    ORIGINAL_LINE="$(jq -r '.line' <<<"$FINDING_ROW")"
    FINDING_FP="$(printf '%s\0' 'review-post:v1' 'finding' "$ENGINE_LABEL" "$HEAD_SHA" "$PERSONA" "$ORIGINAL_PATH" "$ORIGINAL_LINE" | sha256sum | cut -c1-24)"
    FINDING_MARKER="<!-- review-post:v1 kind=finding engine=$ENGINE_LABEL head_sha=$HEAD_SHA fp=$FINDING_FP -->"
    PULL_COUNT="$(jq -r --arg fp "$FINDING_FP" '.[$fp] // 0' <<<"$PULL_REMAINING")"
    if [[ "$PULL_COUNT" -gt 0 ]]; then
      PULL_REMAINING="$(jq -c --arg fp "$FINDING_FP" 'if .[$fp] == 1 then del(.[$fp]) else .[$fp] -= 1 end' <<<"$PULL_REMAINING")"
      set_delivery "$ID" "inline" true
      continue
    fi
    ISSUE_COUNT="$(jq -r --arg fp "$FINDING_FP" '.[$fp] // 0' <<<"$ISSUE_REMAINING")"
    if [[ "$ISSUE_COUNT" -gt 0 ]]; then
      ISSUE_REMAINING="$(jq -c --arg fp "$FINDING_FP" 'if .[$fp] == 1 then del(.[$fp]) else .[$fp] -= 1 end' <<<"$ISSUE_REMAINING")"
      set_delivery "$ID" "pr_comment" true
      continue
    fi
    BODY="$(jq -r '.body' <<<"$FINDING_ROW")"
    PREFIX="$ENGINE_LABEL"
    if [[ "$STATUS" == "ok" || "$STATUS" == "corrected" || "$STATUS" == "unverified" ]]; then
      ANCHORED_PATH="$(jq -r '.anchored_path' <<<"$FINDING_ROW")"
      ANCHORED_LINE="$(jq -r '.anchored_line' <<<"$FINDING_ROW")"
      SIDE="$(jq -r '.side' <<<"$FINDING_ROW")"
      COMMENT_BODY="$(printf '[%s] **[%s] %s（%s）**\n\n%s' "$PREFIX" "$SEVERITY" "$PERSONA" "$VIEWPOINT" "$BODY")"
      if [[ "$STATUS" == "unverified" ]]; then
        COMMENT_BODY="$(printf '[%s] **[%s] %s（%s）**\n\n⚠ 位置は未検証（evidence引用なし、original_lineの実在確認のみ）\n\n%s' "$PREFIX" "$SEVERITY" "$PERSONA" "$VIEWPOINT" "$BODY")"
      fi
      COMMENT_BODY="${COMMENT_BODY}"$'\n\n'"${FINDING_MARKER}"
      INLINE_ERR="$TMP_DIR/inline-$ID.err"
      INLINE_URL=""
      INLINE_EXIT=0
      if ! sf_verify "inline-$ID"; then
        echo "review-post managed lease admission failure: inline POST 直前の verify に失敗しました" >&2
        exit 2
      fi
      INLINE_URL="$(review_post_api gh api -X POST "repos/$OWNER/$REPO/pulls/$PR_NUM/comments" \
        -f body="$COMMENT_BODY" -f path="$ANCHORED_PATH" -F line="$ANCHORED_LINE" \
        -f side="$SIDE" -f commit_id="$HEAD_SHA" --jq '.html_url' 2>"$INLINE_ERR")" || INLINE_EXIT=$?
      if [[ "$INLINE_EXIT" -eq 0 ]]; then
        record_write "inline" "$INLINE_URL"
        set_delivery "$ID" "inline"
      elif grep -Eq '(^|[^0-9])422([^0-9]|$)' "$INLINE_ERR"; then
        post_pr_comment "$ID" "$SEVERITY" "$PERSONA" "$ORIGINAL_PATH" "$ORIGINAL_LINE" "$BODY" "$PREFIX" "$FINDING_MARKER" || {
          FALLBACK_RC=$?
          [[ "$FALLBACK_RC" -eq 2 ]] && exit 2
        }
      else
        GITHUB_FAILED=true
      fi
    else
      post_pr_comment "$ID" "$SEVERITY" "$PERSONA" "$ORIGINAL_PATH" "$ORIGINAL_LINE" "$BODY" "$PREFIX" "$FINDING_MARKER" || {
        FALLBACK_RC=$?
        [[ "$FALLBACK_RC" -eq 2 ]] && exit 2
      }
    fi
  done < <(jq -c --argjson rows "$BLOCK_ROWS" '$rows[]' <<<"$BLOCK_ROWS")
elif [[ "$SUMMARY_EXIT" -ne 0 ]]; then
  # サマリに失敗した場合はステップ7相当を進めず、二重投稿を避ける。
  while IFS= read -r ID; do
    [[ -n "$ID" ]] || continue
    set_delivery "$ID" "not_posted"
  done < <(jq -r '.[] | select(.final_gate == "block") | .id' <<<"$ADJUDICATION_RESULTS")
fi

# 最後の record_write より後まで保持し、一覧 GET → dedup → 全 write を原子的に見せる。
if [[ "$MANAGED_SINGLEFLIGHT" == true ]]; then
  POST_FINAL_STATE="complete"
  [[ "$GITHUB_FAILED" == true ]] && POST_FINAL_STATE="unknown"
  if ! sf_renew "post-complete" "$POST_FINAL_STATE"; then
    echo "review-post managed lease admission failure: post phase 完了の renew に失敗しました" >&2
    exit 2
  fi
fi
if [[ "$POST_LOCK_ACQUIRED" == true ]]; then
  exec 8>&-
  POST_LOCK_ACQUIRED=false
fi

if [[ "$SUMMARY_EXIT" -ne 0 ]]; then
  GITHUB_FAILED=true
fi

INLINE_COUNT="$(jq '[to_entries[] | select(.value == "inline")] | length' <<<"$DELIVERY_JSON")"
FALLBACK_COUNT="$(jq '[to_entries[] | select(.value == "pr_comment")] | length' <<<"$DELIVERY_JSON")"
SUMMARY_ONLY_COUNT="$(jq '[to_entries[] | select(.value == "summary_only")] | length' <<<"$DELIVERY_JSON")"
NOT_POSTED_COUNT="$(jq '[to_entries[] | select(.value == "not_posted")] | length' <<<"$DELIVERY_JSON")"
REUSED_COUNT="$(jq '[to_entries[] | select(.value == true)] | length' <<<"$REUSED_JSON")"
ITEMS_JSON="$(jq -n -c --argjson findings "$ENRICHED_FINDINGS" --argjson results "$ADJUDICATION_RESULTS" --argjson delivery "$DELIVERY_JSON" --argjson reused "$REUSED_JSON" '
  $findings | map(
    . as $finding
    | (first($results[] | select(.id == $finding.id)) // {}) as $result
    | {id:$finding.id, final_gate:($result.final_gate // null), importance:($result.importance // null),
       anchor_status:($finding.anchor_status // "unanchorable"), delivery:($delivery[$finding.id] // "not_posted"),
       reused:($reused[$finding.id] // false)}
  )
' )"

if [[ "$BLOCK_LAYER" == "structure" ]]; then
  RESULT_STATUS="report_only"
elif [[ "$BLOCK_COUNT" -eq 0 ]]; then
  RESULT_STATUS="no_findings"
else
  RESULT_STATUS="posted"
fi

if ! jq -n \
  --arg engine "$ENGINE" \
  --arg owner "$OWNER" \
  --arg repo "$REPO" \
  --argjson number "$PR_NUM" \
  --arg status "$RESULT_STATUS" \
  --arg grounding_status "$GROUNDING_STATUS" \
  --arg grounding_note "$GROUNDING_NOTE" \
  --argjson total "$TOTAL_FINDINGS" \
  --argjson block "$BLOCK_COUNT" \
  --argjson defer "$DEFER_COUNT" \
  --argjson inline_posted "$INLINE_COUNT" \
  --argjson fallback_posted "$FALLBACK_COUNT" \
  --argjson reused "$REUSED_COUNT" \
  --argjson summary_only "$SUMMARY_ONLY_COUNT" \
  --argjson not_posted "$NOT_POSTED_COUNT" \
  --argjson items "$ITEMS_JSON" \
  --arg summary_markdown "$SUMMARY_MARKDOWN" \
  --argjson github_writes "$GITHUB_WRITES" \
  '{schema_version:"1", artifact_type:"review-post-result", status:$status, engine:$engine,
    pr:{owner:$owner, repo:$repo, number:$number}, grounding_status:$grounding_status,
    grounding_note:(if $grounding_note == "" then null else $grounding_note end),
    counts:{total_findings:$total, block:$block, defer:$defer, inline_posted:$inline_posted,
      fallback_posted:$fallback_posted, reused:$reused, summary_only:$summary_only, not_posted:$not_posted},
    items:$items, summary_markdown:$summary_markdown, github_writes:$github_writes}' \
  >"$RESULT_PATH"; then
  echo "review-post result を書き出せません: $RESULT_PATH" >&2
  exit 1
fi

if [[ "$GITHUB_FAILED" == true ]]; then
  exit 1
fi
exit 0
```

## 投稿対象と本文

adjudication の `results[]` から `final_gate == "block"` の全 finding を投稿対象とする。`reported_gate` は
使わず、`importance: null` も除外しない。importance が null の場合の severity 表示は `UNRATED` とし、
HIGH/MEDIUM/LOW の列へ落とさず列外に別記する。

`ok`/`corrected` は補正位置でインライン、`unverified` は補正位置でインラインし本文冒頭へ
「⚠ 位置は未検証（evidence引用なし、original_lineの実在確認のみ）」を付ける。`unanchorable` または
anchor フィールドがない場合は `original_path:original_line` を場所表示に使う通常 PR コメントへ退避する。
インライン API が 422 を返した場合も同じ通常 PR コメントへフォールバックする。

本文の接頭辞は MAGI が `[MAGI-HARD]`、Codex が `[CODEX-HARD]` であり、インラインの形式は次のとおりとする。
同一 `$HEAD_SHA` の再実行では、既存コメントの末尾にあるマーカーを使って dedup する。サマリのマーカーは
`<!-- review-post:v1 kind=summary engine=<ENGINE_LABEL> head_sha=<HEAD_SHA> fp=<24hex> -->`、finding の
マーカーは `<!-- review-post:v1 kind=finding engine=<ENGINE_LABEL> head_sha=<HEAD_SHA> fp=<24hex> -->` とし、
どちらも本文末尾に空行2つを挟んで置く（`pr-review-respond` の `startswith("[MAGI-HARD]")` を壊さないため）。
finding の fingerprint は `engine + head_sha + persona + path + line` だけから計算し、本文・finding id・
severity・side・anchor_status は含めない。同じ鍵の複数 finding は、既存コメントの個数を1件ずつ消費する
multiset 突合とする。サマリは同じ engine と head_sha なら PATCH し、finding は issues と pulls の両方を
照合する。dedup の突合対象は `gh api user` で取得した bot 自身の login が投稿したコメントだけであり、
他ユーザーが本文末尾に同じ書式のマーカーを偽造しても突合対象にしない（該当 finding は通常どおり新規投稿し、
summary も新規 POST する）。マーカーのない旧コメントは dedup 対象外である。この冪等性が保証するのは、
同一 `$HEAD_SHA` に対する逐次再実行と部分失敗後の再試行のみである。同一 PR・同一 HEAD で `/review-post`
を同時並行実行した場合、一覧取得と投稿の間に別 run が割り込むと重複投稿が起こり得る。GitHub のコメント
API に原子的な idempotency key がないため、managed 実行では host-local post lock を必ず併用する。
非 managed の直接実行は `REVIEW_POST_USE_LOCK=1` の明示時だけ lock を取得し、別ホスト間の排他は保証対象外である。
managed 実行は lock 内で `review-singleflight.sh verify` を行い、サマリ mutation 直前に per_pr lease を
`review-singleflight.sh renew`（acquire / release はしない）する。renew または verify が失敗した場合は
GitHub write 前に exit 2 とし、dispatch 側で `post_state=post_failed` / `dispatch_status=failed` に写像する。
force-release は同じ post lock を保持しているため進行中の POST の終了を待ち、旧 owner を kill しない。

```text
[MAGI-HARD] **[<severity>] <persona>（<観点>）**

<指摘内容>

<!-- review-post:v1 kind=finding engine=MAGI-HARD head_sha=<HEAD_SHA> fp=<24hex> -->
```

`post_inline:false` の場合は、サマリ本文の末尾に structure なら normalized raw、audit なら finding list を
`<details>` とともに埋め込み、ステップ7相当の GitHub API 呼び出しを一切行わない。サマリはこの gate に
関係なく常に1件投稿する。

## 出力と終了コード

`result_path` には次の形の単一 JSON 値を書き出す。`delivery` は `inline`、`pr_comment`、`summary_only`、
`not_posted` のいずれかである。

```json
{
  "schema_version": "1",
  "artifact_type": "review-post-result",
  "status": "posted",
  "engine": "magi",
  "pr": { "owner": "...", "repo": "...", "number": 123 },
  "grounding_status": "complete",
  "grounding_note": null,
  "counts": {
    "total_findings": 0, "block": 0, "defer": 0,
    "inline_posted": 0, "fallback_posted": 0, "reused": 0, "summary_only": 0, "not_posted": 0
  },
  "items": [ { "id": "M-001", "final_gate": "block", "importance": "HIGH", "anchor_status": "ok", "delivery": "inline", "reused": false } ],
  "summary_markdown": "...",
  "github_writes": [ { "kind": "summary", "url": "https://...", "operation": "create" } ]
}
```

`items[].reused` と `counts.reused` は既存 finding の再利用数を示す。再利用 finding は GitHub API を呼ばず、
`github_writes` に入らない。サマリを PATCH した場合は `github_writes[].operation` が `"update"` になり、
新規投稿は `"create"` になる。一覧取得（issues または pulls）が失敗した場合は mutation を行わず、
終了コード1、`github_writes: []`、全 block finding の `delivery: "not_posted"` / `reused: false` で result を
生成する。終了コード2では GET を含むすべての GitHub API 呼び出しを行わない。既存の exit 0/1/2 の写像は
維持し、managed lease admission failure の exit 2 は `review-dispatch.md` の hard 写像へ合流する。

self-identity（`gh api user`）の取得に失敗した場合、または login が文字列でない・空・欠落の
場合（`--jq` の型検証で gh が非ゼロ終了する）も一覧取得失敗と同じ
fail-closed とし、何も投稿せず `github_writes: []`・終了コード1で result を生成する。終了コード2へは変換しない。

`status` は通常経路が `posted`、structure 経路が `report_only`、投稿対象0件が `no_findings` である。
契約どおりの縮退を含む成功は終了コード0、GitHub API 呼び出しの失敗（部分投稿を含む）は1、requestまたは
入力 artifact の契約違反は GitHub 書き込み前に2で停止する。
