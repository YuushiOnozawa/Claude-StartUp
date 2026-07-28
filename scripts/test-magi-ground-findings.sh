#!/usr/bin/env bash
# test-magi-ground-findings.sh — magi-ground-findings.sh の動作確認テスト

set -euo pipefail

SCRIPT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/magi-ground-findings.sh"
FIXTURE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/tests/fixtures/metatron-security-flaws.diff"
TMP_DIR="$(mktemp -d "${TMPDIR:-/tmp}/test-magi-ground-findings.XXXXXX")"
PASS=0
FAIL=0

trap 'rm -rf "$TMP_DIR"' EXIT HUP INT TERM

make_findings() {
  local output="$1"
  local finding
  local first=1
  shift

  {
    cat <<'JSON'
{"findings":[
JSON
    for finding in "$@"; do
      if [ "$first" -eq 1 ]; then
        first=0
      else
        printf ',\n'
      fi
      printf '%s' "$finding"
    done
    cat <<'JSON'
]}
JSON
  } > "$output"
}

make_finding() {
  local id="$1"
  local body="$2"
  local original_path="$3"
  local original_line="$4"

  jq -cn \
    --arg id "$id" \
    --arg body "$body" \
    --arg original_path "$original_path" \
    --argjson original_line "$original_line" \
    '{id:$id, body:$body, original_path:$original_path, original_line:$original_line}'
}

run_anchor_test() {
  local desc="$1"
  local id="$2"
  local body="$3"
  local original_path="$4"
  local original_line="$5"
  local expected_status="$6"
  local expected_path="$7"
  local expected_line="$8"
  local expected_side="$9"

  local findings_json="$TMP_DIR/${id}.json"
  local output
  local actual_status
  local actual_path
  local actual_line
  local actual_side

  make_findings "$findings_json" "$(make_finding "$id" "$body" "$original_path" "$original_line")"
  output=$(bash "$SCRIPT" "$findings_json" "$FIXTURE")

  actual_status=$(printf '%s' "$output" | jq -r --arg id "$id" '.anchors[] | select(.id == $id) | .anchor_status')
  actual_path=$(printf '%s' "$output" | jq -r --arg id "$id" '.anchors[] | select(.id == $id) | .anchored_path')
  actual_line=$(printf '%s' "$output" | jq -r --arg id "$id" '.anchors[] | select(.id == $id) | .anchored_line')
  actual_side=$(printf '%s' "$output" | jq -r --arg id "$id" '.anchors[] | select(.id == $id) | .side')

  if [ "$actual_status" = "$expected_status" ] \
    && [ "$actual_path" = "$expected_path" ] \
    && [ "$actual_line" = "$expected_line" ] \
    && [ "$actual_side" = "$expected_side" ]; then
    echo "PASS: $desc"
    ((PASS++)) || true
  else
    echo "FAIL: $desc (expected: ${expected_status}|${expected_path}|${expected_line}|${expected_side}, got: ${actual_status}|${actual_path}|${actual_line}|${actual_side})"
    ((FAIL++)) || true
  fi
}

run_status_test() {
  local desc="$1"
  shift

  if "$@" >/dev/null 2>&1; then
    echo "FAIL: $desc (expected non-zero exit, got 0)"
    ((FAIL++)) || true
  else
    echo "PASS: $desc"
    ((PASS++)) || true
  fi
}

run_anchor_test "新側にしか無い引用は original_line どおり ok" \
  "add-ok" \
  '検出箇所: `_artifact_sync_require_mirror_url() {`' \
  "scripts/lib/artifact-sync.sh" \
  30 \
  "ok" \
  "scripts/lib/artifact-sync.sh" \
  30 \
  "RIGHT"

run_anchor_test "新側にしか無い引用は誤った original_line から補正" \
  "add-corrected" \
  '検出箇所: `_artifact_sync_require_mirror_url() {`' \
  "scripts/lib/artifact-sync.sh" \
  12 \
  "corrected" \
  "scripts/lib/artifact-sync.sh" \
  30 \
  "RIGHT"

run_anchor_test "旧側にしか無い引用は LEFT へ補正" \
  "del-corrected" \
  '削除された検証: `sha256sum -c "$checksum_file"`' \
  "scripts/lib/artifact-sync.sh" \
  12 \
  "corrected" \
  "scripts/lib/artifact-sync.sh" \
  81 \
  "LEFT"

run_anchor_test "バックスラッシュを含む引用を壊さず補正" \
  "backslash-corrected" \
  'ログ出力: `printf '"'"'curl -fsS -H "Authorization: Bearer %s" -o %q %q\n'"'"' "$token"`' \
  "scripts/lib/artifact-sync.sh" \
  12 \
  "corrected" \
  "scripts/lib/artifact-sync.sh" \
  71 \
  "RIGHT"

run_anchor_test "修正提案だけの引用は unanchorable" \
  "suggestion-only" \
  '修正案: `subprocess.run(["curl", url])`' \
  "scripts/lib/artifact-sync.sh" \
  1 \
  "unanchorable" \
  "" \
  0 \
  ""

run_anchor_test "引用候補が無い本文は unanchorable" \
  "no-candidate" \
  "本文だけで引用候補がありません" \
  "scripts/lib/artifact-sync.sh" \
  1 \
  "unanchorable" \
  "" \
  0 \
  ""

run_anchor_test "別ファイルへはアンカーしない" \
  "wrong-path" \
  '検出箇所: `_artifact_sync_require_mirror_url() {`' \
  "scripts/lib/other.sh" \
  30 \
  "unanchorable" \
  "" \
  0 \
  ""

run_anchor_test "複数行に一致する引用は unanchorable" \
  "ambiguous" \
  '曖昧な引用: `_artifact_sync_require_mirror_url "$`' \
  "scripts/lib/artifact-sync.sh" \
  61 \
  "unanchorable" \
  "" \
  0 \
  ""

run_anchor_test "層優先で2つめの追加行候補へアンカー" \
  "layer-before-candidate" \
  '先の context 引用: `local pattern="$1"` 後の追加行引用: `_artifact_sync_require_mirror_url() {`' \
  "scripts/lib/artifact-sync.sh" \
  30 \
  "ok" \
  "scripts/lib/artifact-sync.sh" \
  30 \
  "RIGHT"

run_anchor_test "コードフェンス内の1行を引用できる" \
  "fence" \
  '本文に | と箇条書きを含む
- 問題:
```bash
_artifact_sync_require_mirror_url "$metadata_url"
```
補足 | 詳細' \
  "scripts/lib/artifact-sync.sh" \
  93 \
  "corrected" \
  "scripts/lib/artifact-sync.sh" \
  100 \
  "RIGHT"

empty_findings="$TMP_DIR/empty.json"
make_findings "$empty_findings"
empty_output=$(bash "$SCRIPT" "$empty_findings" "$FIXTURE")
if [ "$(printf '%s' "$empty_output" | jq -r '.anchors | length')" = "0" ]; then
  echo "PASS: findings が空配列"
  ((PASS++)) || true
else
  echo "FAIL: findings が空配列 (expected empty anchors, got: $empty_output)"
  ((FAIL++)) || true
fi

# 出力契約は schema_version と anchors の組なので、anchors だけでなく版も固定する。
if [ "$(printf '%s' "$empty_output" | jq -r '.schema_version')" = "1" ]; then
  echo "PASS: schema_version は 1"
  ((PASS++)) || true
else
  echo "FAIL: schema_version は 1 (got: $empty_output)"
  ((FAIL++)) || true
fi

rename_diff="$TMP_DIR/rename.diff"
cat > "$rename_diff" <<'DIFF'
diff --git a/src/old-name.sh b/src/new-name.sh
similarity index 82%
rename from src/old-name.sh
rename to src/new-name.sh
--- a/src/old-name.sh
+++ b/src/new-name.sh
@@ -1,2 +1,2 @@
 keep
-old_secret_check
+new_secret_check
DIFF

rename_findings="$TMP_DIR/rename.json"
make_findings "$rename_findings" \
  "$(make_finding "rename-left" '削除側の引用: `old_secret_check`' "src/old-name.sh" 2)"
rename_output=$(bash "$SCRIPT" "$rename_findings" "$rename_diff")
rename_status=$(printf '%s' "$rename_output" | jq -r '.anchors[] | select(.id == "rename-left") | .anchor_status')
rename_path=$(printf '%s' "$rename_output" | jq -r '.anchors[] | select(.id == "rename-left") | .anchored_path')
rename_line=$(printf '%s' "$rename_output" | jq -r '.anchors[] | select(.id == "rename-left") | .anchored_line')
rename_side=$(printf '%s' "$rename_output" | jq -r '.anchors[] | select(.id == "rename-left") | .side')
if [ "$rename_status" = "ok" ] \
  && [ "$rename_path" = "src/new-name.sh" ] \
  && [ "$rename_line" = "2" ] \
  && [ "$rename_side" = "LEFT" ]; then
  echo "PASS: rename diff の旧パス finding は LEFT に新パスでアンカー"
  ((PASS++)) || true
else
  echo "FAIL: rename diff の旧パス finding は LEFT に新パスでアンカー (expected: ok|src/new-name.sh|2|LEFT, got: ${rename_status}|${rename_path}|${rename_line}|${rename_side})"
  ((FAIL++)) || true
fi

quoted_diff="$TMP_DIR/quoted.diff"
cat > "$quoted_diff" <<'DIFF'
diff --git a/src/normal.sh b/src/normal.sh
index 1111111..2222222 100644
--- a/src/normal.sh
+++ b/src/normal.sh
@@ -1 +1 @@
-old_normal
+new_normal
diff --git "a/src/quoted\tname.sh" "b/src/quoted\tname.sh"
index 3333333..4444444 100644
--- "a/src/quoted\tname.sh"
+++ "b/src/quoted\tname.sh"
@@ -1 +1 @@
-old_quoted
+quoted_scope_leak_sentinel
DIFF

quoted_findings="$TMP_DIR/quoted.json"
make_findings "$quoted_findings" \
  "$(make_finding "quoted-scope-reset" '引用: `quoted_scope_leak_sentinel`' "src/normal.sh" 1)"
quoted_output=$(bash "$SCRIPT" "$quoted_findings" "$quoted_diff")
quoted_status=$(printf '%s' "$quoted_output" | jq -r '.anchors[] | select(.id == "quoted-scope-reset") | .anchor_status')
quoted_path=$(printf '%s' "$quoted_output" | jq -r '.anchors[] | select(.id == "quoted-scope-reset") | .anchored_path')
quoted_line=$(printf '%s' "$quoted_output" | jq -r '.anchors[] | select(.id == "quoted-scope-reset") | .anchored_line')
quoted_side=$(printf '%s' "$quoted_output" | jq -r '.anchors[] | select(.id == "quoted-scope-reset") | .side')
if [ "$quoted_status" = "unanchorable" ] \
  && [ "$quoted_path" = "" ] \
  && [ "$quoted_line" = "0" ] \
  && [ "$quoted_side" = "" ]; then
  echo "PASS: quoted diff エントリは直前パスへ誤アンカーしない"
  ((PASS++)) || true
else
  echo "FAIL: quoted diff エントリは直前パスへ誤アンカーしない (expected: unanchorable||0|, got: ${quoted_status}|${quoted_path}|${quoted_line}|${quoted_side})"
  ((FAIL++)) || true
fi

multi_findings="$TMP_DIR/multi.json"
make_findings "$multi_findings" \
  "$(make_finding "multi-1" '検出箇所: `_artifact_sync_require_mirror_url() {`' "scripts/lib/artifact-sync.sh" 30)" \
  "$(make_finding "multi-2" '削除された検証: `sha256sum -c "$checksum_file"`' "scripts/lib/artifact-sync.sh" 12)" \
  "$(make_finding "multi-3" '修正案: `subprocess.run(["curl", url])`' "scripts/lib/artifact-sync.sh" 1)"
multi_output=$(bash "$SCRIPT" "$multi_findings" "$FIXTURE")
multi_ids=$(printf '%s' "$multi_output" | jq -r '[.anchors[].id] | join(",")')
if [ "$multi_ids" = "multi-1,multi-2,multi-3" ]; then
  echo "PASS: 複数 finding は入力順と同じ ID 集合で返る"
  ((PASS++)) || true
else
  echo "FAIL: 複数 finding は入力順と同じ ID 集合で返る (expected: multi-1,multi-2,multi-3, got: $multi_ids)"
  ((FAIL++)) || true
fi

run_status_test "引数が1個なら非ゼロ終了" bash "$SCRIPT" "$multi_findings"
run_status_test "findings table が存在しないなら非ゼロ終了" bash "$SCRIPT" "$TMP_DIR/missing.json" "$FIXTURE"

invalid_json="$TMP_DIR/invalid.json"
cat > "$invalid_json" <<'JSON'
not json
JSON
run_status_test "findings table が JSON でないなら非ゼロ終了" bash "$SCRIPT" "$invalid_json" "$FIXTURE"

not_array_json="$TMP_DIR/not-array.json"
cat > "$not_array_json" <<'JSON'
{"findings":"x"}
JSON
run_status_test ".findings が配列でないなら非ゼロ終了" bash "$SCRIPT" "$not_array_json" "$FIXTURE"

missing_id_json="$TMP_DIR/missing-id.json"
cat > "$missing_id_json" <<'JSON'
{"findings":[{"body":"body","original_path":"scripts/lib/artifact-sync.sh","original_line":1}]}
JSON
run_status_test "id を欠く finding は非ゼロ終了" bash "$SCRIPT" "$missing_id_json" "$FIXTURE"

missing_path_json="$TMP_DIR/missing-original-path.json"
cat > "$missing_path_json" <<'JSON'
{"findings":[{"id":"missing-path","body":"body","original_line":1}]}
JSON
run_status_test "original_path を欠く finding は非ゼロ終了" bash "$SCRIPT" "$missing_path_json" "$FIXTURE"

duplicate_id_json="$TMP_DIR/duplicate-id.json"
make_findings "$duplicate_id_json" \
  "$(make_finding "dupe" '検出箇所: `_artifact_sync_require_mirror_url() {`' "scripts/lib/artifact-sync.sh" 30)" \
  "$(make_finding "dupe" '削除された検証: `sha256sum -c "$checksum_file"`' "scripts/lib/artifact-sync.sh" 12)"
run_status_test "id が重複する finding は非ゼロ終了" bash "$SCRIPT" "$duplicate_id_json" "$FIXTURE"

echo ""
echo "Results: ${PASS} PASS / ${FAIL} FAIL"

if [ "$FAIL" -gt 0 ]; then
  exit 1
fi
