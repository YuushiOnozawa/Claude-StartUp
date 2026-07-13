---
name: magi-hard
description: MAGI 6体（melchior→balthasar→casper→metatron→sandalphon→leliel）でPRレビューを行う。決定的集約と review-plan.json 生成を行う（GitHubへの投稿は行わない）。Trigger: "/magi-hard", "magi-hard", "ハードレビュー", "PRをMAGIにレビューさせて"
---

# MAGI-HARD スキル

MAGI の6体（MELCHIOR→BALTHASAR→CASPER→METATRON→SANDALPHON→LELIEL）を順次実行し、PR の全差分を深くレビューする。persona の raw 出力は terminal に再表示せず、`magi-aggregate.py` が生成する `review-plan.json` と canonical summary だけを表示の正本にする。

F6 は sink mode、2段階 aggregate、Codex annotation を使用し、GitHub へのサマリ・インラインコメント投稿を行わない。投稿は F7 の poster が `review-plan.json` から行う。false positive は finding を削除せず raw gate を緩和しない。レビュー不完全、raw HIGH/MEDIUM、または `needs_human` が残る場合は LGTM を許可しない。

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
[ -f "$AGGREGATE" ] && [ -f "$FILTER" ] && [ -f "$SPLITTER" ] && [ -f "$PRETRIAGE" ] || {
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
```

PR の特定結果として `$PR_NUM`、`$OWNER`、`$REPO`、`$HEAD_SHA`、`$PR_URL` を保持する。closed / merged の場合は終了し、レビューを実行しない。

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
cp "$PREP_TMPDIR/input.filtered" "$RUN_DIR/diff/input.filtered.patch" || fatal 'diff を保存できません'
cp "$PREP_TMPDIR/excluded.txt" "$RUN_DIR/diff/excluded-files.txt" 2>/dev/null || :
sha256sum "$RUN_DIR/diff/input.filtered.patch" | grep -q "^$DIFF_HASH  " || fatal 'diff hash 検証に失敗しました'
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
{"schema_version":"magi-run-policy/v1","workflow":"hard","gate_basis":"raw","gate_severity":"HIGH","audit_enabled":true,"audit_severities":["HIGH","MEDIUM"],"false_positive_policy":"exclude","needs_human_policy":"label_and_block","dedupe_enabled":true,"renderer":"github","locale":"ja","anchor_policy":"pr","completion_policy":{"require_marker":true,"zero_findings_requires_no_findings":true},"diff_source":{"kind":"file"},"head_sha":"<40 lowercase hex>"}
```

manifest と policy は一時ファイルを `mv` して atomic に保存し、失敗時は fatal とする。

## ステップ 3: 5体の直列 sink 実行

`melchior`→`balthasar`→`casper`→`metatron`→`sandalphon` の順に、前体の完了後に次体を起動する。

```bash
for persona in melchior balthasar casper metatron sandalphon; do
  PERSONA_NAME=$(printf '%s' "$persona" | tr '[:lower:]' '[:upper:]')
  IMPACT_ARG=()
  if [ "$persona" = balthasar ]; then
    IMPACT_CONTEXT=$(bash scripts/magi-impact-context.sh "$(cat "$RUN_DIR/diff/input.filtered.patch")" 2>/dev/null || true)
    export MAGI_IMPACT_CONTEXT="$IMPACT_CONTEXT"
  fi
  MAGI_RUN_DIR="$RUN_DIR" MAGI_INPUT_FILE="$RUN_DIR/diff/input.filtered.patch" \
  MAGI_RESULT_FILE="$RUN_DIR/results/$persona.md" MAGI_STATUS_FILE="$RUN_DIR/status/$persona.json" \
  MAGI_QUIET=1 PERSONA_NAME="$PERSONA_NAME" run_persona "$persona"
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
git ls-files > "$RUN_DIR/plan/tracked-files.txt" || fatal 'tracked files を取得できません'
git archive "$HEAD_SHA" | tar -x -C "$RUN_DIR/isolated" || fatal 'isolated snapshot を作成できません'
```

実行環境設定から Codex の sandbox read-only、network 遮断、`hard-read-only/v1` profile を確認できた場合だけ `--codex-command` と `--isolated-profile hard-read-only/v1` を渡す。確認できない場合は両方を渡さず、`magi-leliel-pretriage.py` 内蔵の `fallback_legacy` に任せる。

```bash
PRETRIAGE_START=$(date +%s%3N)
PRETRIAGE_ARGS=(prepare --diff-file "$RUN_DIR/diff/input.filtered.patch" --repo-root "$RUN_DIR/isolated" \
  --output-dir "$RUN_DIR/plan/pretriage" --audit-dir "$RUN_DIR/audit/pretriage" --tracked-files "$RUN_DIR/plan/tracked-files.txt")
# profile_verified=true の時だけ次の2引数を追加する。
[ "${PROFILE_VERIFIED:-false}" = true ] && PRETRIAGE_ARGS+=(--codex-command "$CODEX_COMMAND" --isolated-profile hard-read-only/v1)
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
MAGI_RUN_DIR="$RUN_DIR" MAGI_INPUT_FILE="$RUN_DIR/diff/input.filtered.patch" \
MAGI_RESULT_FILE="$RUN_DIR/results/leliel.md" MAGI_STATUS_FILE="$RUN_DIR/status/leliel.json" \
MAGI_QUIET=1 PERSONA_NAME=LELIEL run_persona leliel
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

`ANNOTATION_STATUS` と `ANNOTATION_REASON` を先に確定する。eligible set は raw canonical の HIGH/MEDIUM かつ `fallback == null` だけである。profile は `hard-read-only/v1`、隔離 worktree `$ISOLATED_ROOT=$RUN_DIR/isolated`、network 遮断を実行環境設定から確認する。確認できない場合は fail-open とする。

`magi-common/references/codex-annotation.md` の hard 形式に従い、canonical raw-byte SHA-256、filter 済み diff、pre-triage の caller 抜粋・選定理由・skip 理由を、render 済みの `$RUN_DIR/plan/leliel-context/impact-context.md` または manifest 経由で検証済み artifact から取得して、動的 backtick fence で prompt に入れる。pre-triage 不発時は `leliel-evidence-block` 自体を省略する。eligible set 外の `id`/`duplicate_of`、未知 field、重複 ID、`false_positive` と `duplicate_of` の併記など F3 契約違反が一つでもあれば artifact 全体を不採用にし、`--audit` を渡さない。失敗は fail-open であり gate を緩和しない。

```bash
ANNOTATION_STATUS=unavailable
ANNOTATION_REASON='profile not verified'
MERGE_AUDIT_ARGS=()
ISOLATED_ROOT="$RUN_DIR/isolated"
CANONICAL_SHA256=$(sha256sum "$CANONICAL" | awk '{print $1}')
ANNOTATION_START=$(date +%s%3N)
if [ "${PROFILE_VERIFIED:-false}" = true ] && [ -d "$ISOLATED_ROOT" ]; then
  # prompt は canonical/diff/evidence ごとに最大 backtick 数+1の fence を生成する。
  # artifact を厳格検証し、成功時だけ同一 directory の tmp から atomic rename する。
  node "$CODEX_COMPANION" task --prompt-file "$TASK_TMPDIR/task-prompt.txt" -C "$ISOLATED_ROOT" \
    > "$TASK_TMPDIR/task-raw.txt"
  if [ "$?" -eq 0 ] && validate_annotation "$TASK_TMPDIR/task-raw.txt" "$CANONICAL_SHA256"; then
    atomic_install_annotation "$TASK_TMPDIR/task-raw.txt" "$RUN_DIR/audit-annotations.json"
    MERGE_AUDIT_ARGS=(--audit "$RUN_DIR/audit-annotations.json")
    ANNOTATION_STATUS=applied; ANNOTATION_REASON='annotations applied'
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

F6 では GitHub 投稿を行わない。F7 の poster がこの `review-plan.json` を正本として投稿する。

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

## aggregate 失敗時の Claude 再 parse opt-in

質問: 集約器が失敗したため、REVIEW_GATE は判定できません。raw persona artifact を Claude が補助的に再解析しますか？ この解析は gate/LGTM の根拠にはならず、結果を terminal に転載しません。
選択肢: 「再解析しない（推奨）」「補助再解析を許可する」

「再解析しない」または未回答は error と run dir を表示して終了する。「補助再解析を許可する」場合も canonical/review-plan を書き換えず、`REVIEW_GATE=false` と明示して終了する。正規経路は artifact/実行環境を直して `/magi-hard` を再実行することだけである。
