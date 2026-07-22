---
name: magi-hard
description: MAGI 6体（melchior→balthasar→casper→metatron→sandalphon→leliel）でPRレビューを行う。決定的集約と review-plan.json 生成を行い、poster が review-plan.json から冪等投稿する。Trigger: "/magi-hard", "magi-hard", "ハードレビュー", "PRをMAGIにレビューさせて"
---

# MAGI-HARD スキル

MAGI の6体（MELCHIOR→BALTHASAR→CASPER→METATRON→SANDALPHON→LELIEL）を順次実行し、PR の全差分を深くレビューする。persona の raw 出力は terminal に再表示せず、`magi-aggregate.py` が生成する `review-plan.json` と canonical summary だけを表示の正本にする。

F6 は sink mode、2段階 aggregate、Codex annotation を使用する。投稿は poster が `review-plan.json` から冪等に行う。false positive は finding を削除せず raw gate を緩和しない。レビュー不完全、raw HIGH/MEDIUM、または `needs_human` が残る場合は LGTM を許可しない。

## 前提

各体は独立して同じ filter 済み diff を見る。sink mode では caller が run dir を作成・保護・prune し、persona はその配下の指定 artifact だけを使用する。persona sink 実行契約は `magi-common/references/execution-steps.md` に従う。

CASPER は Haiku へ直行し、Ollama の確認をしない。MELCHIOR/BALTHASAR/METATRON/SANDALPHON/LELIEL は Ollama が使えない場合、**ペルソナごとに** AskUserQuestion で「Haiku で続行 / 中止」を確認する。拒否時はモデルを呼ばず、sink status を `failed` または `not_run` として確定する。orchestrator はこの確認を迂回・代理承認しない。

## ステップ 0: フラグと実行前提の確定

引数なしだけを受け付ける。未知の引数は usage を表示して停止する。全コマンドは repository root で実行し、以後に作る run artifact と一時ファイルには `umask 077` を適用する。

```bash
REPO_ROOT=$(git rev-parse --show-toplevel) || exit 1
cd "$REPO_ROOT"
AGGREGATE="$REPO_ROOT/scripts/magi-aggregate.py"
FILTER="$REPO_ROOT/scripts/magi-diff-filter.sh"
SPLITTER="$REPO_ROOT/scripts/magi-split-hunk.sh"
PRETRIAGE="$REPO_ROOT/scripts/magi-leliel-pretriage.py"
POSTER="$REPO_ROOT/scripts/magi-hard-poster.py"
[ -f "$AGGREGATE" ] && [ -f "$FILTER" ] && [ -f "$SPLITTER" ] && [ -f "$PRETRIAGE" ] && [ -f "$POSTER" ] || {
  echo 'MAGI-HARD: required MAGI scripts are unavailable'
  exit 1
}
[ "$#" -eq 0 ] || { echo 'usage: /magi-hard'; exit 2; }

BRANCH=$(git branch --show-current) || exit 1
PR_JSON=$(gh pr view --json number,headRefName,state,url) || exit 1
PR_NUM=$(jq -r '.number' <<<"$PR_JSON")
HEAD_REF=$(jq -r '.headRefName' <<<"$PR_JSON")
PR_STATE=$(jq -r '.state' <<<"$PR_JSON")
PR_URL=$(jq -r '.url' <<<"$PR_JSON")
OWNER_REPO=$(gh repo view --json nameWithOwner --jq .nameWithOwner) || exit 1
OWNER=${OWNER_REPO%%/*}; REPO=${OWNER_REPO#*/}
[ "$PR_STATE" = open ] || { echo 'MAGI-HARD: PR はすでに closed または merged です'; exit 0; }
HEAD_SHA=$(gh api "repos/$OWNER/$REPO/pulls/$PR_NUM" --jq .head.sha) || exit 1
[[ "$HEAD_SHA" =~ ^[0-9a-fA-F]{40}$ ]] || { echo 'MAGI-HARD: head.sha が不正です'; exit 1; }
HEAD_SHA=$(printf '%s' "$HEAD_SHA" | tr '[:upper:]' '[:lower:]')

PROFILE_ID="codex-companion-read-only/v1"
ANNOTATION_ELIGIBLE=false
PROFILE_VERIFIED=false
PROFILE_STATUS=unavailable
PROFILE_FAILED_CHECKS=()
PROFILE_WARNINGS=()
CODEX_VERSION=$(codex --version 2>/dev/null) || PROFILE_FAILED_CHECKS+=("codex_cli_unavailable")
COMPANION_PATH=$(ls "$HOME"/.claude/plugins/cache/openai-codex/codex/*/scripts/codex-companion.mjs 2>/dev/null | sort -V | tail -1)
[ -n "$COMPANION_PATH" ] || PROFILE_FAILED_CHECKS+=("companion_script_unavailable")
CODEX_COMPANION="$COMPANION_PATH"
CODEX_COMMAND="$COMPANION_PATH"
if [ "${#PROFILE_FAILED_CHECKS[@]}" -eq 0 ]; then
  ANNOTATION_ELIGIBLE=true
  PROFILE_STATUS=eligible
fi

json_array() {
  if [ "$#" -eq 0 ]; then printf '[]'; else printf '%s\n' "$@" | jq -R . | jq -s .; fi
}
json_string_or_null() {
  if [ -n "${1:-}" ]; then jq -Rn --arg value "$1" '$value'; else printf 'null'; fi
}
write_profile_verification() {
  PROFILE_VERIFICATION="$RUN_DIR/audit/profile-verification.json"
  PROFILE_TMP="$RUN_DIR/audit/.profile-verification.json.tmp"
  FAILED_CHECKS_JSON=$(json_array "${PROFILE_FAILED_CHECKS[@]}")
  WARNINGS_JSON=$(json_array "${PROFILE_WARNINGS[@]}")
  CODEX_VERSION_JSON=$(json_string_or_null "${CODEX_VERSION:-}")
  COMPANION_PATH_JSON=$(json_string_or_null "${COMPANION_PATH:-}")
  jq -n --arg profile_id "$PROFILE_ID" \
    --argjson annotation_eligible "$ANNOTATION_ELIGIBLE" \
    --argjson profile_verified "$PROFILE_VERIFIED" \
    --arg status "$PROFILE_STATUS" \
    --argjson failed_checks "$FAILED_CHECKS_JSON" \
    --argjson warnings "$WARNINGS_JSON" \
    --arg network_isolation "not_supported_by_codex_companion_1.0.5" \
    --argjson codex_version "$CODEX_VERSION_JSON" \
    --argjson companion_path "$COMPANION_PATH_JSON" \
    '{schema_version:"profile-verification/v1",profile_id:$profile_id,annotation_eligible:$annotation_eligible,profile_verified:$profile_verified,status:$status,failed_checks:$failed_checks,warnings:$warnings,network_isolation:$network_isolation,codex_version:$codex_version,companion_path:$companion_path}' \
    > "$PROFILE_TMP" && mv -f "$PROFILE_TMP" "$PROFILE_VERIFICATION"
}
```

PR の特定結果として `$PR_NUM`、`$OWNER`、`$REPO`、`$HEAD_SHA`、`$PR_URL` を保持する。closed / merged の場合は終了し、レビューを実行しない。
Codex annotation の可否は自己申告の環境変数ではなく、以後に保存する `$RUN_DIR/audit/profile-verification.json` だけを正とする。Step 0 では実行前に検証可能な Codex CLI availability、companion plugin path、`--write` を渡さないコード経路だけを確認し、isolated snapshot と cwd の検証は Step 5 で追記する。`network_isolation` は Codex companion 経由では検証不能なため、判定根拠にしない。

## ステップ 1: filter 済み入力、diff-hash、run dir の準備

`gh pr diff $PR_NUM` の stdout を raw file に一度だけ保存し、filter の stdout を候補 file に保存する。差分をシェル変数へ入れてはならない。filter の excluded list は run dir 作成前には一時ファイルへ出力し、run dir 作成後に移す。

```bash
umask 077
PREP_TMPDIR=$(mktemp -d)
trap 'rm -rf "$PREP_TMPDIR"' EXIT
gh pr diff "$PR_NUM" > "$PREP_TMPDIR/input.raw" || exit 1
MAGI_FILTER_EXCLUDED_LIST="$PREP_TMPDIR/excluded.txt" bash "$FILTER" < "$PREP_TMPDIR/input.raw" > "$PREP_TMPDIR/input.filtered"
if [ ! -s "$PREP_TMPDIR/input.filtered" ]; then
  echo 'MAGI-HARD: レビュー対象の差分がありません'
  exit 0
fi
DIFF_HASH=$(sha256sum "$PREP_TMPDIR/input.filtered" | awk '{print $1}')
```

`DIFF_HASH` は filter 適用後、splitter に渡す raw bytes の SHA-256 である。改行正規化、再 filter、別入力の hash は禁止する。

run ID の排他的作成、canonical path の検証、14日超過および各 diff-hash 配下20 run超過の安全な prune は `magi-fast` ステップ1と同一の手順を用いる。`MAGI_RUN_DIR`、`MAGI_RESULT_FILE`、`MAGI_STATUS_FILE`、`MAGI_QUIET=1` の sink 契約は `execution-steps.md` に従う。hard では `diff/`、`results/`、`status/` に加えて `audit/`、`plan/`、`isolated/` も、同じ non-symlink directory 検証と mode 700 で作成する。

```bash
fatal() { echo "MAGI-HARD: $*" >&2; exit 1; }
reject_symlink() { [ ! -L "$1" ] || fatal "symlink は許可しません: $1"; }
verify_dir() { [ -d "$1" ] && [ ! -L "$1" ] || fatal "non-symlink directory ではありません: $1"; }
HOME_CANONICAL=$(realpath "$HOME") || fatal 'HOME を canonical 化できません'
RUNS_ROOT="$HOME_CANONICAL/.cache/magi/runs"; DIFF_RUNS_DIR="$RUNS_ROOT/$DIFF_HASH"
for path in "$HOME_CANONICAL/.cache" "$HOME_CANONICAL/.cache/magi" "$RUNS_ROOT" "$DIFF_RUNS_DIR"; do reject_symlink "$path"; done
mkdir -p -m 700 "$DIFF_RUNS_DIR" || fatal 'run root を作成できません'
verify_dir "$RUNS_ROOT"; verify_dir "$DIFF_RUNS_DIR"
RUN_DIR_CREATED=false
for attempt in 1 2 3 4 5; do
  RUN_ID="$(date -u +%Y%m%dT%H%M%SZ)-$$-$(od -An -N4 -tx4 /dev/urandom | tr -d ' \n')"
  RUN_DIR="$DIFF_RUNS_DIR/$RUN_ID"; reject_symlink "$RUN_DIR"
  if mkdir -m 700 "$RUN_DIR" 2>/dev/null; then RUN_DIR_CREATED=true; break; fi
  [ -e "$RUN_DIR" ] || fatal "run dir を作成できません: $RUN_DIR"
done
[ "$RUN_DIR_CREATED" = true ] || fatal 'run ID の衝突が継続したため run dir を作成できません'
EXPECTED_RUN_DIR=$(realpath -e "$RUN_DIR") || fatal 'run dir を検証できません'
for path in diff results status audit plan isolated; do
  reject_symlink "$RUN_DIR/$path"; [ ! -e "$RUN_DIR/$path" ] || fatal "run subdirectory が既に存在します: $path"
  mkdir -m 700 "$RUN_DIR/$path" || fatal "run subdirectory を作成できません: $path"
  verify_dir "$RUN_DIR/$path"
done
write_profile_verification || fatal 'profile verification を保存できません'
cp "$PREP_TMPDIR/input.filtered" "$RUN_DIR/diff/input.filtered.patch" || fatal 'diff を保存できません'
cp "$PREP_TMPDIR/excluded.txt" "$RUN_DIR/diff/excluded-files.txt" 2>/dev/null || :
sha256sum "$RUN_DIR/diff/input.filtered.patch" | grep -q "^$DIFF_HASH  " || fatal 'diff hash 検証に失敗しました'

PR_BODY=$(gh pr view "$PR_NUM" --json body -q .body)
source "$REPO_ROOT/scripts/lib/magi-change-summary.sh"
SUMMARY=$(extract_pr_summary "$PR_BODY")
SUMMARY=$(truncate_utf8 "$SUMMARY" 300)
printf '%s' "$SUMMARY" > "$RUN_DIR/change-summary.txt"
```

prune の失敗は warning に留めるが、現 run の作成、入力保存、manifest/policy 書込み失敗は fatal error とする。run 作成後、現在の `$RUN_DIR` を除外して一度だけ prune する。

## ステップ 2: manifest と hard 用 run-policy の生成

JSON は `$RUN_DIR` 内の tmp file から atomic rename で書く。manifest は実行順と ID prefix を次で固定する。

```json
{"schema_version":"persona-manifest/v1","personas":[
  {"ordinal":1,"key":"melchior","name":"MELCHIOR","id_prefix":"MEL"},
  {"ordinal":2,"key":"balthasar","name":"BALTHASAR","id_prefix":"BAL"},
  {"ordinal":3,"key":"casper","name":"CASPER","id_prefix":"CAS"},
  {"ordinal":4,"key":"metatron","name":"METATRON","id_prefix":"MET"},
  {"ordinal":5,"key":"sandalphon","name":"SANDALPHON","id_prefix":"SAN"}
]}
```

`run-policy.json` は次の固定値で生成する。`head_sha` は検証済みの40桁 hex、`diff_source.kind` は `file` である。

```json
{"schema_version":"magi-run-policy/v1","workflow":"hard","gate_basis":"raw","gate_severity":"HIGH","audit_enabled":true,"audit_severities":["HIGH","MEDIUM"],"false_positive_policy":"annotate","needs_human_policy":"label_and_block","dedupe_enabled":true,"renderer":"github","locale":"ja","anchor_policy":"pr","completion_policy":{"require_marker":true,"zero_findings_requires_no_findings":true},"diff_source":{"kind":"file"},"head_sha":"<40 lowercase hex>"}
```

`require_marker:true` は marker 出力を期待するという意味であり、marker 欠落時でも Assessment 構造完全性を満たせば `chunk_complete` として受理する（#314 の OR 緩和）という parser の実際の受理条件とは独立である。markerless fallback は `magi-aggregate.py` 側の別条件として動作する。

manifest と policy は一時ファイルを `mv` して atomic に保存し、失敗時は fatal とする。

## ステップ 3: 5体の直列 sink 実行

`melchior`→`balthasar`→`casper`→`metatron`→`sandalphon` の順に、前体の完了後に次体を起動する。

```bash
MAGI_CHANGE_SUMMARY=$(cat "$RUN_DIR/change-summary.txt" 2>/dev/null || true)
for persona in melchior balthasar; do
  PERSONA_NAME=$(printf '%s' "$persona" | tr '[:lower:]' '[:upper:]')
  case "$persona" in
    melchior) OLLAMA_MODEL='qwen2.5-coder:7b' ;;
    balthasar) OLLAMA_MODEL='gemma4:e4b-it-qat' ;;
  esac
  IMPACT_CONTEXT=
  if [ "$persona" = balthasar ]; then
    IMPACT_CONTEXT=$(bash "$HOME/.claude/scripts/magi-impact-context.sh" "$(cat "$RUN_DIR/diff/input.filtered.patch")" 2>/dev/null || true)
  fi
  MAGI_RUN_DIR="$RUN_DIR" MAGI_INPUT_FILE="$RUN_DIR/diff/input.filtered.patch" \
  MAGI_RESULT_FILE="$RUN_DIR/results/$persona.md" MAGI_STATUS_FILE="$RUN_DIR/status/$persona.json" \
  MAGI_QUIET=1 PERSONA_NAME="$PERSONA_NAME" MAGI_CHANGE_SUMMARY="${MAGI_CHANGE_SUMMARY:-}" \
  MAGI_IMPACT_CONTEXT="${IMPACT_CONTEXT:-}" \
  python3 "$REPO_ROOT/scripts/magi-persona-runner.py" "$persona" --repo-root "$REPO_ROOT" --model "$OLLAMA_MODEL"
done
```

上記ループ完了後、3体目として CASPER を実行する。`magi-common/references/execution-steps.md` の「Haiku パス」節の契約に従い、Claude が `Agent(subagent_type="general-purpose", model="haiku")` を直接呼び出す。渡す内容は、共通 4 reference（`magi-common/references/task-base.md`、`casper/references/task-instruction.md`、`casper/references/review-criteria.md`、`magi-common/references/output-format.md`）、system prompt 末尾へ追加する `$CLAUDE_RULES`、filter 済み diff、chunk ID、期待される completion marker（`<!-- MAGI_COMPLETE persona=casper chunk=XXXX -->`）とする。magi-hard の CASPER には `plan-receipt.json` を渡さない。

Haiku 応答には staging file（`$RUN_DIR/results/.CASPER.<chunk_id>.haiku.tmp`）への書き込みだけを指示する。Claude は `execution-steps.md` の「Haiku パス」節の receipt 検証手順を実行し、検証済み本文だけを chunk 順に組み立ててから、`results/casper.md` と `status/casper.json` へ atomic commit する。

CASPER の atomic commit が完了してから、4体目以降を実行する。

```bash
for persona in metatron sandalphon; do
  PERSONA_NAME=$(printf '%s' "$persona" | tr '[:lower:]' '[:upper:]')
  case "$persona" in
    metatron) OLLAMA_MODEL='granite3.3:8b' ;;
    sandalphon) OLLAMA_MODEL='phi4:latest' ;;
  esac
  IMPACT_CONTEXT=
  MAGI_RUN_DIR="$RUN_DIR" MAGI_INPUT_FILE="$RUN_DIR/diff/input.filtered.patch" \
  MAGI_RESULT_FILE="$RUN_DIR/results/$persona.md" MAGI_STATUS_FILE="$RUN_DIR/status/$persona.json" \
  MAGI_QUIET=1 PERSONA_NAME="$PERSONA_NAME" MAGI_CHANGE_SUMMARY="${MAGI_CHANGE_SUMMARY:-}" \
  MAGI_IMPACT_CONTEXT="${IMPACT_CONTEXT:-}" \
  python3 "$REPO_ROOT/scripts/magi-persona-runner.py" "$persona" --repo-root "$REPO_ROOT" --model "$OLLAMA_MODEL"
done
```

sink + quiet の応答は receipt のみとし、raw body を最終応答へ転載しない。個々の error があっても、以後の persona を実行できるなら実行する。

## aggregate 失敗の共通 handler

parse/merge のいずれかが失敗したら、呼び出し元は通常のステップへ戻らず、この handler だけを実行する。`REVIEW_GATE=false` を確定し、後述の AskUserQuestion は opt-in とする。回答後は必ず終了し、annotation、merge、renderer、通常 gate へ fall-through しない。

```bash
aggregate_failure_handler() {
  failed_phase=$1; failed_exit=$2
  echo "MAGI-HARD: aggregate $failed_phase failed (exit=$failed_exit); LGTM を許可しません; run dir=$RUN_DIR"
  REVIEW_GATE=false
  case "${AGGREGATE_FALLBACK_REPLY:-}" in
    '補助再解析を許可する') : ;;
    *) : ;;
  esac
  exit 0
}
```

## ステップ 4: aggregate parse（1回目）

```bash
CANONICAL_5="$RUN_DIR/canonical-5.json"
python3 "$AGGREGATE" parse --run-dir "$RUN_DIR" --manifest "$RUN_DIR/manifest.json" --output "$CANONICAL_5"
PARSE_EXIT=$?
[ "$PARSE_EXIT" -eq 0 ] || aggregate_failure_handler parse "$PARSE_EXIT"
```

parse/merge の失敗時は後述の共通 handler だけを実行し、通常の次ステップへ進まない。

## ステップ 5: pre-triage と LELIEL

まず tracked files を保存し、PR head の tracked snapshot だけを隔離 root に展開する。

```bash
git ls-files -z > "$RUN_DIR/plan/tracked-files.txt" || fatal 'tracked files を取得できません'
git archive "$HEAD_SHA" | tar -x -C "$RUN_DIR/isolated" || fatal 'isolated snapshot を作成できません'
ISOLATED_ROOT="$RUN_DIR/isolated"
EXPECTED_ISOLATED_ROOT=$(realpath -e "$RUN_DIR/isolated") || PROFILE_FAILED_CHECKS+=("isolated_root_unavailable")
ANNOTATION_CWD=$(realpath -e "$ISOLATED_ROOT" 2>/dev/null || true)
case "$ANNOTATION_CWD/" in "$EXPECTED_ISOLATED_ROOT/"*) : ;; *) PROFILE_FAILED_CHECKS+=("annotation_cwd_outside_isolated") ;; esac
find "$ISOLATED_ROOT" -type f -exec sha256sum {} + | sort > "$RUN_DIR/audit/isolated-manifest.sha256" || PROFILE_FAILED_CHECKS+=("isolated_manifest_unavailable")
PRE_TREE_HASH=$(sha256sum "$RUN_DIR/audit/isolated-manifest.sha256" | awk '{print $1}') || PROFILE_FAILED_CHECKS+=("pre_tree_hash_unavailable")
if [ "${#PROFILE_FAILED_CHECKS[@]}" -eq 0 ]; then
  ANNOTATION_ELIGIBLE=true
  PROFILE_STATUS=eligible
else
  ANNOTATION_ELIGIBLE=false
  PROFILE_STATUS=unavailable
fi
write_profile_verification || fatal 'profile verification を更新できません'
```

Step 0 で作成し、isolated snapshot 作成後に更新した `$RUN_DIR/audit/profile-verification.json` の `annotation_eligible` が `true` の場合だけ `--codex-command` と `--isolated-profile codex-companion-read-only/v1` を渡す。確認できない場合は両方を渡さず、`magi-leliel-pretriage.py` 内蔵の `fallback_legacy` に任せる。

```bash
PRETRIAGE_START=$(date +%s%3N)
ANNOTATION_ELIGIBLE=$(jq -r '.annotation_eligible' "$RUN_DIR/audit/profile-verification.json" 2>/dev/null || echo false)
PRETRIAGE_ARGS=(prepare --diff-file "$RUN_DIR/diff/input.filtered.patch" --repo-root "$RUN_DIR/isolated" \
  --output-dir "$RUN_DIR/plan/pretriage" --audit-dir "$RUN_DIR/audit/pretriage" --tracked-files "$RUN_DIR/plan/tracked-files.txt")
[ "$ANNOTATION_ELIGIBLE" = true ] && PRETRIAGE_ARGS+=(--codex-command "$CODEX_COMMAND" --isolated-profile codex-companion-read-only/v1)
python3 "$PRETRIAGE" "${PRETRIAGE_ARGS[@]}"
PRETRIAGE_EXIT=$?
PRETRIAGE_MS=$(( $(date +%s%3N) - PRETRIAGE_START ))
if [ "$PRETRIAGE_EXIT" -eq 2 ] || [ "$PRETRIAGE_EXIT" -eq 1 ]; then
  PRETRIAGE_ERROR='LELIEL なし（部品エラー）'; PRETRIAGE_FAILED=true
fi
```

exit 2 は入力/契約エラー、exit 1 は I/O エラーであり、いずれも「LELIEL なし（部品エラー）」としてレビューを継続し、LELIEL の manifest 追加は行わない。結果をサマリへ記録する。

```bash
SKIP=false
if [ "${PRETRIAGE_FAILED:-false}" = true ]; then
  SKIP=true; SKIP_REASON='部品エラー（LELIEL なし）'
else
  mkdir -m 700 "$RUN_DIR/plan/leliel-context" || {
    SKIP=true; SKIP_REASON='部品エラー（context render 不能）'
  }
  if [ "$SKIP" != true ]; then
    python3 "$PRETRIAGE" render --manifest "$RUN_DIR/plan/pretriage/manifest.json" \
      --output-dir "$RUN_DIR/plan/leliel-context" || {
        SKIP=true; SKIP_REASON='部品エラー（context render 不能）'
      }
  fi
  if [ "$SKIP" != true ]; then
    python3 "$PRETRIAGE" decide-skip --manifest "$RUN_DIR/plan/pretriage/manifest.json" \
      --output "$RUN_DIR/plan/leliel-skip-decision.json" || {
        SKIP=true; SKIP_REASON='部品エラー（skip 判定不能）'
      }
    [ "$SKIP" = true ] || SKIP=$(jq -r '.skip' "$RUN_DIR/plan/leliel-skip-decision.json")
  fi
fi
```

`skip=true`（`new_files_only` または `impact_context_empty`）なら LELIEL を実行せず、`$CANONICAL=$CANONICAL_5`、`$FINAL_MANIFEST=$RUN_DIR/manifest.json` とし、理由をサマリへ記録する。非 skip なら `impact-context.md` の内容を `MAGI_IMPACT_CONTEXT` として LELIEL を sink 実行する。

```bash
MAGI_IMPACT_CONTEXT=$(cat "$RUN_DIR/plan/leliel-context/impact-context.md")
MAGI_CHANGE_SUMMARY=$(cat "$RUN_DIR/change-summary.txt" 2>/dev/null || true)
OLLAMA_MODEL='llama3.1:8b'
MAGI_RUN_DIR="$RUN_DIR" MAGI_INPUT_FILE="$RUN_DIR/diff/input.filtered.patch" \
MAGI_RESULT_FILE="$RUN_DIR/results/leliel.md" MAGI_STATUS_FILE="$RUN_DIR/status/leliel.json" \
MAGI_QUIET=1 PERSONA_NAME=LELIEL MAGI_CHANGE_SUMMARY="${MAGI_CHANGE_SUMMARY:-}" \
MAGI_IMPACT_CONTEXT="${MAGI_IMPACT_CONTEXT:-}" \
python3 "$REPO_ROOT/scripts/magi-persona-runner.py" leliel --repo-root "$REPO_ROOT" --model "$OLLAMA_MODEL"
```

LELIEL 実行後、5体に `leliel/LELIEL/LEL` ordinal 6 を加えた manifest を `$RUN_DIR/manifest-6.json` として atomic に生成し、2回目の parse を行う。persona 別連番 ID のため、先行5体の ID は1回目と一致する。

```bash
CANONICAL="$CANONICAL_5"; FINAL_MANIFEST="$RUN_DIR/manifest.json"
if [ "$SKIP" != true ] && [ "${PRETRIAGE_FAILED:-false}" != true ]; then
  # manifest-6.json は上記5体に ordinal=6,key=leliel,name=LELIEL,id_prefix=LEL を追加して atomic 生成する。
  FINAL_MANIFEST="$RUN_DIR/manifest-6.json"
  CANONICAL="$RUN_DIR/canonical-findings.json"
  python3 "$AGGREGATE" parse --run-dir "$RUN_DIR" --manifest "$FINAL_MANIFEST" --output "$CANONICAL"
  PARSE_EXIT=$?; [ "$PARSE_EXIT" -eq 0 ] || aggregate_failure_handler parse "$PARSE_EXIT"
fi
```

## ステップ 6: Codex annotation（hard 変形）

`ANNOTATION_STATUS` と `ANNOTATION_REASON` を先に確定する。eligible set は raw canonical の HIGH/MEDIUM かつ `fallback == null` だけである。profile は `codex-companion-read-only/v1`、隔離 worktree `$ISOLATED_ROOT=$RUN_DIR/isolated` を `$RUN_DIR/audit/profile-verification.json` の `annotation_eligible` から確認する。network 遮断は Codex companion 経由では検証不能であり、`network_isolation` フィールドとして常に `not_supported_by_codex_companion_1.0.5` を記録し、判定根拠にしない。

`magi-common/references/codex-annotation.md` の hard 形式に従い、canonical raw-byte SHA-256、filter 済み diff、pre-triage の caller 抜粋・選定理由・skip 理由を、render 済みの `$RUN_DIR/plan/leliel-context/impact-context.md` または manifest 経由で検証済み artifact から取得して、動的 backtick fence で prompt に入れる。pre-triage 不発時は `leliel-evidence-block` 自体を省略する。eligible set 外の `id`/`duplicate_of`、未知 field、重複 ID、`false_positive` と `duplicate_of` の併記など F3 契約違反が一つでもあれば artifact 全体を不採用にし、`--audit` を渡さない。失敗は fail-open であり gate を緩和しない。

```bash
ANNOTATION_STATUS=unavailable
ANNOTATION_REASON='profile not verified'
MERGE_AUDIT_ARGS=()
ISOLATED_ROOT="$RUN_DIR/isolated"
CANONICAL_SHA256=$(sha256sum "$CANONICAL" | awk '{print $1}')
ANNOTATION_START=$(date +%s%3N)
ANNOTATION_ELIGIBLE=$(jq -r '.annotation_eligible' "$RUN_DIR/audit/profile-verification.json" 2>/dev/null || echo false)
if [ "$ANNOTATION_ELIGIBLE" = true ] && [ -d "$ISOLATED_ROOT" ]; then
  # prompt は canonical/diff/evidence ごとに最大 backtick 数+1の fence を生成する。
  # prompt は isolated root 内の関連 tracked files に限定し、root 外・untracked・`.git`・credential・`$HOME`・`/proc`・network 等の探索を要求しない。
  # artifact を厳格検証し、成功時だけ同一 directory の tmp から atomic rename する。
  node "$CODEX_COMPANION" task --prompt-file "$TASK_TMPDIR/task-prompt.txt" -C "$ISOLATED_ROOT" \
    > "$TASK_TMPDIR/task-raw.txt"
  if [ "$?" -eq 0 ] && validate_annotation "$TASK_TMPDIR/task-raw.txt" "$CANONICAL_SHA256"; then
    atomic_install_annotation "$TASK_TMPDIR/task-raw.txt" "$RUN_DIR/audit-annotations.json"
    if jq -e '((.fileChanges? // .touchedFiles?) | type) == "array"' "$TASK_TMPDIR/task-raw.txt" >/dev/null 2>&1; then
      TOUCHED_FILES=$(jq -r '(.fileChanges? // .touchedFiles?) | if type=="array" then .[] else empty end' "$TASK_TMPDIR/task-raw.txt")
    else
      TOUCHED_FILES_UNAVAILABLE=true
      TOUCHED_FILES=
      PROFILE_FAILED_CHECKS+=("touched_files_unavailable")
    fi
    POST_TREE_HASH=$(find "$ISOLATED_ROOT" -type f -exec sha256sum {} + | sort | sha256sum | awk '{print $1}')
    if [ "${TOUCHED_FILES_UNAVAILABLE:-false}" != true ] && [ "$POST_TREE_HASH" = "$PRE_TREE_HASH" ] && [ -z "$TOUCHED_FILES" ]; then
      PROFILE_VERIFIED=true
      PROFILE_STATUS=verified
      write_profile_verification || fatal 'profile verification を更新できません'
      MERGE_AUDIT_ARGS=(--audit "$RUN_DIR/audit-annotations.json")
      ANNOTATION_STATUS=applied; ANNOTATION_REASON='annotations applied'
    else
      PROFILE_VERIFIED=false
      PROFILE_STATUS=invalid
      [ "$POST_TREE_HASH" = "$PRE_TREE_HASH" ] || PROFILE_FAILED_CHECKS+=("post_run_tree_changed")
      [ -z "$TOUCHED_FILES" ] || PROFILE_FAILED_CHECKS+=("post_run_touched_files")
      write_profile_verification || fatal 'profile verification を更新できません'
      rm -f "$RUN_DIR/audit-annotations.json"
      MERGE_AUDIT_ARGS=()
      ANNOTATION_STATUS=invalid; ANNOTATION_REASON='annotation postflight failed'
    fi
  else
    ANNOTATION_REASON='annotation contract or executor failure'
  fi
fi
ANNOTATION_MS=$(( $(date +%s%3N) - ANNOTATION_START ))
```

duration は保持し、Codex failure/profile 未確認でも canonical finding は全件残す。`false_positive` 除外・annotation unavailable は raw gate を緩和しない。

## ステップ 7: merge、review-plan.json、サマリ表示、メトリクス

```bash
REVIEW_PLAN="$RUN_DIR/review-plan.json"
python3 "$AGGREGATE" merge --findings "$CANONICAL" --run-policy "$RUN_DIR/run-policy.json" \
  "${MERGE_AUDIT_ARGS[@]}" --output "$REVIEW_PLAN"
MERGE_EXIT=$?; [ "$MERGE_EXIT" -eq 0 ] || aggregate_failure_handler merge "$MERGE_EXIT"
```

terminal サマリには run ID/run dir、`workflow=hard`、PR 番号、HEAD SHA、0埋めの `raw_counts`、persona 別 `parse_status`、`needs_human` 件数、hard policy で excluded となった false positive の件数と ID（`excluded_findings` は削除しない）、`diff/excluded-files.txt` の除外ファイル、pre-triage の added/required 件数または skip 理由または部品エラー、`ANNOTATION_STATUS/REASON` を表示する。raw persona body は表示しない。

```bash
PRETRIAGE_VALUE=${PRETRIAGE_MS:-null}; ANNOTATION_VALUE=${ANNOTATION_MS:-null}
TMP_METRICS="$RUN_DIR/.metrics.json.tmp"
printf '{"schema_version":"magi-hard-metrics/v1","pretriage_ms":%s,"annotation_ms":%s}\n' \
  "$PRETRIAGE_VALUE" "$ANNOTATION_VALUE" > "$TMP_METRICS" && mv -f "$TMP_METRICS" "$RUN_DIR/metrics.json"
```

p50/p95 は複数 run の `metrics.json` を後から集計する。判定表示（REVIEW_GATE）は raw summary を正本とし、raw HIGH==0、raw MEDIUM==0、全 persona の `parse_status==ok`、`needs_human` なしのときだけ次を表示する。

```text
MAGI-HARD: LGTM（指摘なし）
```

```bash
RAW_HIGH=$(jq -r '.summary.raw_counts.HIGH // 0' "$CANONICAL")
RAW_MEDIUM=$(jq -r '.summary.raw_counts.MEDIUM // 0' "$CANONICAL")
ALL_PARSE_OK=false
jq -e 'all(.personas[]?; .parse_status == "ok")' "$CANONICAL" >/dev/null && ALL_PARSE_OK=true
NEEDS_HUMAN=$(jq '[.items[]? | select(.needs_human == true or .display_state == "needs_human")] | length' "$REVIEW_PLAN")
REVIEW_GATE=false
if [ "$RAW_HIGH" -eq 0 ] && [ "$RAW_MEDIUM" -eq 0 ] && [ "$ALL_PARSE_OK" = true ] && [ "$NEEDS_HUMAN" -eq 0 ]; then
  REVIEW_GATE=true; echo 'MAGI-HARD: LGTM（指摘なし）'
else
  [ "$RAW_HIGH" -gt 0 ] || [ "$RAW_MEDIUM" -gt 0 ] && echo 'MAGI-HARD: HIGH/MEDIUM が残る'
  [ "$ALL_PARSE_OK" = true ] || echo 'MAGI-HARD: レビュー不完全'
  [ "$NEEDS_HUMAN" -eq 0 ] || echo "MAGI-HARD: needs_human が残る（${NEEDS_HUMAN}件）"
fi
```

それ以外は「HIGH/MEDIUM が残る」「レビュー不完全」「needs_human」の理由別に表示し、LGTM は出さない。false positive 除外、annotation unavailable、UNKNOWN を含む除外は gate を緩和しない。

## ステップ 8: post-plan build と冪等投稿

merge 成功時だけ実行する。aggregate 失敗 handler 経由では実行しない。

### 8-1. build

```bash
python3 "$POSTER" build --review-plan "$RUN_DIR/review-plan.json" --output "$RUN_DIR/plan/post-plan.json" \
  --profile-verification "$RUN_DIR/audit/profile-verification.json"
BUILD_EXIT=$?
if [ "$BUILD_EXIT" -ne 0 ]; then
  echo "MAGI-HARD: post-plan build に失敗したため投稿しません (exit=$BUILD_EXIT)"
  echo 'MAGI-HARD: REVIEW_GATE の判定表示を維持します'
  exit 0
fi
```

exit 非 0 の場合は投稿を行わず、理由を表示して終了する。REVIEW_GATE の判定表示は維持する。

### 8-2. 翻訳

`post-plan.json` の `entries[]` から、次で `translation_status=="pending"` の ID を列挙する。

```bash
PENDING_IDS=$(jq -r '.entries[] | select(.translation_status == "pending") | .id' "$RUN_DIR/plan/post-plan.json")
if [ -n "$PENDING_IDS" ]; then
  # Claude が該当 entry の title_ja/body_ja だけを翻訳した JSON を作成する。
  # 形式は {"id":{"title_ja":"...","body_ja":"..."}} とし、marker や HTML コメントを含めない。
  # 意味の追加・削除・改変は禁止し、翻訳のみとする。
  : # $RUN_DIR/plan/translations.json に保存する
  python3 "$POSTER" build --review-plan "$RUN_DIR/review-plan.json" \
    --output "$RUN_DIR/plan/post-plan.json" --translations "$RUN_DIR/plan/translations.json" \
    --profile-verification "$RUN_DIR/audit/profile-verification.json"
fi
```

再 build 後も pending が残る場合はそのまま進む。poster が要人判断（未翻訳）として投稿する。

### 8-3. dry-run 確認

次の dry-run を実行し、summary、entries 件数、severity 内訳を表示する。

```bash
python3 "$POSTER" post --post-plan "$RUN_DIR/plan/post-plan.json" --pr "$PR_NUM" \
  --repo "$OWNER/$REPO" --results "$RUN_DIR/plan/post-results.jsonl" --dry-run \
  > "$RUN_DIR/plan/post-dry-run.json"
DRY_RUN_EXIT=$?
[ "$DRY_RUN_EXIT" -eq 0 ] || { echo "MAGI-HARD: dry-run に失敗しました (exit=$DRY_RUN_EXIT)"; exit 0; }
jq '{summary: .summary_body, entries: (.entries | length), severity: (.entries | group_by(.severity) | map({severity: .[0].severity, count: length}))}' \
  "$RUN_DIR/plan/post-dry-run.json"
```

表示後、AskUserQuestion で「投稿する」または「dry-run のみで終了」を確認する。省略・代理承認は禁止する。

質問: dry-run の内容で GitHub へ投稿しますか？
選択肢: 「投稿する」「dry-run のみで終了」

### 8-4. 投稿

「投稿する」の承認時だけ、`--dry-run` なしで実行する。

```bash
python3 "$POSTER" post --post-plan "$RUN_DIR/plan/post-plan.json" --pr "$PR_NUM" \
  --repo "$OWNER/$REPO" --results "$RUN_DIR/plan/post-results.jsonl"
POST_EXIT=$?
if [ "$POST_EXIT" -eq 3 ]; then
  echo 'MAGI-HARD: HEAD が更新されたため再レビューしてください'
  exit 0
elif [ "$POST_EXIT" -ne 0 ]; then
  echo "MAGI-HARD: 投稿に失敗しました (exit=$POST_EXIT)"
  exit 0
fi
jq -s 'def count_action($action): map(select(.action == $action)) | length; {posted: count_action("posted"), skipped_existing: count_action("skipped_existing"), fallback_issue_comment: count_action("fallback_issue_comment"), failed: count_action("failed")}' \
  "$RUN_DIR/plan/post-results.jsonl"
```

exit 0 時は `post-results.jsonl` を jq で集計し、`posted`、`skipped_existing`、`fallback_issue_comment`、`failed` の件数をサマリに追記表示する。

## aggregate 失敗時の Claude 再 parse opt-in

質問: 集約器が失敗したため、REVIEW_GATE は判定できません。raw persona artifact を Claude が補助的に再解析しますか？ この解析は gate/LGTM の根拠にはならず、結果を terminal に転載しません。
選択肢: 「再解析しない（推奨）」「補助再解析を許可する」

「再解析しない」または未回答は error と run dir を表示して終了する。「補助再解析を許可する」場合も canonical/review-plan を書き換えず、`REVIEW_GATE=false` と明示して終了する。正規経路は artifact/実行環境を直して `/magi-hard` を再実行することだけである。
