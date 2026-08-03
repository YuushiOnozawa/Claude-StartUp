#!/usr/bin/env bash

# magi-ground-findings.sh — MAGI finding の引用コードを PR diff 上の投稿位置へ対応付ける
# Usage: bash scripts/magi-ground-findings.sh <findings-table.json> <diff-file>
#
# 設計判断:
# - semantic な妥当性は判定しない。本文の引用が diff のどこに実在するかだけを確認する。
# - finding は 1 件も捨てない。diff 上に一意な追加/削除行が見つからない場合は unanchorable を返す。
# - 探索範囲は original_path に限定する。他ファイルの同一文字列へ誤って投稿しないため。
# - context 行や作業ツリーで見つかっても unanchorable とする。GitHub インラインコメントの
#   アンカーは PR diff 上の変更行へ張る契約で、diff 外の既存行は通常コメントへ退避させるため。
# - `evidence`フィールドがある場合はそれを唯一の候補として完全一致で探索し、bodyのバッククォート抽出へは
#   フォールバックしない（断片化による誤補正を避けるため。unanchorableの方が誤ったcorrectedより安全という既存方針と一貫させる）。
# - 引用候補が空の場合のみ、original_line が新側追加行として一意に実在するか確認し、未検証アンカーとして返す。
# - JSON の読み書きは jq に任せる。body は改行・引用符・パイプ等を含むため、手書き連結しない。

usage() {
  echo "error: usage: bash scripts/magi-ground-findings.sh <findings-table.json> <diff-file>" >&2
}

die() {
  echo "error: $*" >&2
  exit 1
}

json_field() {
  local row="$1"
  local expr="$2"
  printf '%s' "$row" | jq -Rr "@base64d | fromjson | $expr"
}

trim_text() {
  awk '{
    gsub(/^[[:space:]]+/, "", $0)
    gsub(/[[:space:]]+$/, "", $0)
    print
  }'
}

emit_anchor() {
  local id="$1"
  local path="$2"
  local line="$3"
  local side="$4"
  local status="$5"

  jq -cn \
    --arg id "$id" \
    --arg path "$path" \
    --arg side "$side" \
    --arg status "$status" \
    --argjson line "$line" \
    '{id:$id, anchored_path:$path, anchored_line:$line, side:$side, anchor_status:$status}' \
    >> "$ANCHORS_TMP"
}

emit_unanchorable() {
  local id="$1"
  emit_anchor "$id" "" 0 "" "unanchorable"
}

extract_candidates() {
  awk '
function trim(s) {
  gsub(/^[[:space:]]+/, "", s)
  gsub(/[[:space:]]+$/, "", s)
  return s
}

function emit(s) {
  s = trim(s)
  if (s != "") print s
}

function emit_inline(s,    cand) {
  while (match(s, /`[^`]*`/)) {
    cand = substr(s, RSTART + 1, RLENGTH - 2)
    emit(cand)
    s = substr(s, RSTART + RLENGTH)
  }
}

{
  line = $0
  while (line != "") {
    if (in_fence) {
      pos = index(line, "```")
      if (pos > 0) {
        emit(substr(line, 1, pos - 1))
        line = substr(line, pos + 3)
        in_fence = 0
        continue
      }
      emit(line)
      break
    }

    pos = index(line, "```")
    if (pos > 0) {
      emit_inline(substr(line, 1, pos - 1))
      in_fence = 1
      break
    }

    emit_inline(line)
    break
  }
}
'
}

find_in_diff_layer() {
  local path="$1"
  local needle="$2"
  local layer="$3"
  local match_mode="${4:-substring}"

  MAGI_GROUND_TARGET="$path" MAGI_GROUND_NEEDLE="$needle" MAGI_GROUND_MATCH_MODE="$match_mode" awk -v layer="$layer" '
BEGIN {
  # awk -v は \n 等を解釈して引用候補を壊すため、文字列は環境変数から受け取る。
  target = ENVIRON["MAGI_GROUND_TARGET"]
  needle = ENVIRON["MAGI_GROUND_NEEDLE"]
  match_mode = ENVIRON["MAGI_GROUND_MATCH_MODE"]
  if (match_mode == "") match_mode = "substring"
}

function trim(s) {
  gsub(/^[[:space:]]+/, "", s)
  gsub(/[[:space:]]+$/, "", s)
  return s
}

function matches(content, line_no) {
  if (match_mode == "line") return line_no == (needle + 0)
  if (match_mode == "exact") return trim(content) == trim(needle)
  return index(content, needle) > 0
}

function parse_hunk(line,    rest, parts, oldspec, newspec, oldparts, newparts) {
  rest = line
  sub(/^@@ -/, "", rest)
  split(rest, parts, " ")
  oldspec = parts[1]
  newspec = parts[2]
  sub(/^\+/, "", newspec)
  split(oldspec, oldparts, ",")
  split(newspec, newparts, ",")
  old_line = oldparts[1] + 0
  new_line = newparts[1] + 0
}

function remember(line_no) {
  count++
  matched_line = line_no
  matched_path = current_b_path
}

function strip_a_path(line,    path) {
  path = line
  sub(/^diff --git a\//, "", path)
  sub(/ b\/.*$/, "", path)
  return path
}

function strip_b_path(line,    path) {
  path = line
  sub(/^diff --git a\/.* b\//, "", path)
  return path
}

/^diff --git / {
  # quoted 形式を awk で無理に戻すと \t, \", \\, \NNN の扱いを誤りやすい。
  # 誤アンカーより unanchorable の方が安全なので、従来形式だけパスを採用する。
  current_a_path = ""
  current_b_path = ""
  if ($0 ~ /^diff --git a\// && $0 ~ / b\//) {
    current_a_path = strip_a_path($0)
    current_b_path = strip_b_path($0)
  }
  in_target_hunk = 0
  next
}

/^@@ / {
  parse_hunk($0)
  # rename diff では finding が旧パスを指すことがあるため a/b 両側で同じ diff エントリを選ぶ。
  # GitHub の inline comment は新側パスだけを受け付けるので、返す anchoring path は常に b 側にする。
  in_target_hunk = (current_a_path == target || current_b_path == target)
  in_target_hunk_new_path = (current_b_path == target)
  next
}

!in_target_hunk { next }

/^\\ No newline at end of file$/ { next }

{
  if (length($0) == 0) {
    # 空 context 行の末尾空白が落ちた diff でも、以降の行番号をずらさない。
    old_line++
    new_line++
    next
  }

  prefix = substr($0, 1, 1)
  content = substr($0, 2)

  if (prefix == "+") {
    if (layer == "add" && matches(content, new_line)) {
      if (match_mode != "line" || in_target_hunk_new_path) remember(new_line)
    }
    new_line++
    next
  }

  if (prefix == "-") {
    if (layer == "del" && matches(content, old_line)) remember(old_line)
    old_line++
    next
  }

  if (prefix == " ") {
    if (layer == "context" && matches(content, new_line)) remember(new_line)
    old_line++
    new_line++
  }
}

END {
  if (count == 1) {
    print matched_line "\t" matched_path
    exit 0
  }
  if (count > 1) exit 2
  exit 1
}
' "$DIFF_FILE"
}

find_in_worktree() {
  local path="$1"
  local needle="$2"
  local match_mode="${3:-substring}"
  local file="$REPO_ROOT/$path"

  [ -f "$file" ] || return 1
  MAGI_GROUND_NEEDLE="$needle" MAGI_GROUND_MATCH_MODE="$match_mode" awk '
BEGIN {
  needle = ENVIRON["MAGI_GROUND_NEEDLE"]
  match_mode = ENVIRON["MAGI_GROUND_MATCH_MODE"]
  if (match_mode == "") match_mode = "substring"
}

function trim(s) {
  gsub(/^[[:space:]]+/, "", s)
  gsub(/[[:space:]]+$/, "", s)
  return s
}

{
  if (match_mode == "exact") {
    if (trim($0) == trim(needle)) found = 1
  } else if (index($0, needle) > 0) {
    found = 1
  }
}

END {
  exit found ? 0 : 1
}
' "$file"
}

if [ "$#" -ne 2 ]; then
  usage
  exit 1
fi

FINDINGS_JSON="$1"
DIFF_FILE="$2"

[ -r "$FINDINGS_JSON" ] || die "findings table is not readable: $FINDINGS_JSON"
[ -r "$DIFF_FILE" ] || die "diff file is not readable: $DIFF_FILE"
command -v jq >/dev/null 2>&1 || die "jq is required"

if ! jq -e '.findings | type == "array"' "$FINDINGS_JSON" >/dev/null 2>&1; then
  die "input JSON must parse and contain .findings as an array"
fi

# downstream は ID で結果を join するため、このスクリプトが使う必須フィールドだけは先に落とす。
if ! jq -e '
  all(.findings[];
    (.id | type == "string" and length > 0)
    and (.body | type == "string")
    and has("evidence")
    and (((.evidence | type) == "string" and (.evidence | length) > 0) or (.evidence | type) == "null")
    and (.original_path | type == "string" and length > 0)
    and (.original_line | type == "number" and (. | floor) == . and . > 0)
  )
' "$FINDINGS_JSON" >/dev/null 2>&1; then
  die "each finding must contain required fields: id, body, evidence, original_path, original_line"
fi

if ! jq -e '
  [.findings[].id] as $ids
  | ($ids | length) == ($ids | unique | length)
' "$FINDINGS_JSON" >/dev/null 2>&1; then
  die "finding ids must be unique"
fi

REPO_ROOT=$(git rev-parse --show-toplevel 2>/dev/null || pwd)
TMP_DIR=$(mktemp -d "${TMPDIR:-/tmp}/magi-ground-findings.XXXXXX") || die "failed to create temporary directory"
ANCHORS_TMP="$TMP_DIR/anchors.ndjson"
: > "$ANCHORS_TMP"
trap 'rm -rf "$TMP_DIR"' EXIT HUP INT TERM

while IFS= read -r FINDING_ROW; do
  ID=$(json_field "$FINDING_ROW" '.id // ""')
  BODY=$(json_field "$FINDING_ROW" '.body // ""')
  EVIDENCE=$(json_field "$FINDING_ROW" '(.evidence // null) | if . == null then "" else . end')
  EVIDENCE_TRIMMED=$(printf '%s' "$EVIDENCE" | trim_text)
  ORIGINAL_PATH=$(json_field "$FINDING_ROW" '.original_path // ""')
  ORIGINAL_LINE=$(json_field "$FINDING_ROW" '(.original_line // 0 | tonumber? // 0)')

  CANDIDATES_TMP="$TMP_DIR/candidates.$$"
  MATCH_MODE="substring"
  if [ -n "$EVIDENCE_TRIMMED" ]; then
    printf '%s\n' "$EVIDENCE" > "$CANDIDATES_TMP"
    MATCH_MODE="exact"
  else
    printf '%s' "$BODY" | extract_candidates > "$CANDIDATES_TMP"
  fi

  if [ ! -s "$CANDIDATES_TMP" ]; then
    MATCH_RESULT=$(find_in_diff_layer "$ORIGINAL_PATH" "$ORIGINAL_LINE" "add" "line")
    if [ $? -eq 0 ]; then
      MATCH_LINE=${MATCH_RESULT%%$'\t'*}
      MATCH_PATH=${MATCH_RESULT#*$'\t'}
      emit_anchor "$ID" "$MATCH_PATH" "$MATCH_LINE" "RIGHT" "unverified"
    else
      emit_unanchorable "$ID"
    fi
    continue
  fi

  ANCHOR_DONE=0
  # 仕様は候補ごとではなく層ごとに探索する。context の早い候補で、
  # 後続候補の追加/削除行アンカーを潰さないため。
  for LAYER in add del context worktree; do
    while IFS= read -r CANDIDATE; do
      if [ "$LAYER" = "worktree" ]; then
        if find_in_worktree "$ORIGINAL_PATH" "$CANDIDATE" "$MATCH_MODE"; then
          emit_unanchorable "$ID"
          ANCHOR_DONE=1
          break
        fi
        continue
      fi

      MATCH_RESULT=$(find_in_diff_layer "$ORIGINAL_PATH" "$CANDIDATE" "$LAYER" "$MATCH_MODE")
      MATCH_STATUS=$?
      if [ "$MATCH_STATUS" -eq 0 ]; then
        if [ "$LAYER" = "context" ]; then
          emit_unanchorable "$ID"
          ANCHOR_DONE=1
          break
        fi

        MATCH_LINE=${MATCH_RESULT%%$'\t'*}
        MATCH_PATH=${MATCH_RESULT#*$'\t'}
        if [ "$LAYER" = "add" ]; then
          MATCH_SIDE="RIGHT"
        else
          MATCH_SIDE="LEFT"
        fi
        if [ "$MATCH_LINE" = "$ORIGINAL_LINE" ]; then
          emit_anchor "$ID" "$MATCH_PATH" "$MATCH_LINE" "$MATCH_SIDE" "ok"
        else
          emit_anchor "$ID" "$MATCH_PATH" "$MATCH_LINE" "$MATCH_SIDE" "corrected"
        fi
        ANCHOR_DONE=1
        break
      fi
      if [ "$MATCH_STATUS" -eq 2 ]; then
        emit_unanchorable "$ID"
        ANCHOR_DONE=1
        break
      fi
    done < "$CANDIDATES_TMP"

    if [ "$ANCHOR_DONE" -eq 1 ]; then
      break
    fi
  done

  if [ "$ANCHOR_DONE" -eq 0 ]; then
    emit_unanchorable "$ID"
  fi
done < <(jq -cr '.findings[] | @base64' "$FINDINGS_JSON")

jq -s '{schema_version:"1", anchors:.}' "$ANCHORS_TMP"
