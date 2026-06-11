#!/usr/bin/env bash
# Obsidian investigations/ と knowledge/ の _index.md をローカルLLMで生成する
set -uo pipefail

OBSIDIAN_DIR="$HOME/pcloud/obsidian"
INVESTIGATIONS_DIR="$OBSIDIAN_DIR/investigations"
KNOWLEDGE_DIR="$OBSIDIAN_DIR/knowledge"
MODEL="${OBSIDIAN_INDEX_MODEL:-qwen3:8b}"
OLLAMA_URL="http://localhost:11434/api/generate"
TIMEOUT=600

log() { echo "[$1] $2" >&2; }

# Ollama 起動確認
if ! curl -sf "http://localhost:11434" > /dev/null 2>&1; then
  log "ERROR" "Ollama が起動していません"
  exit 1
fi

# ファイル一覧のサマリを収集する
collect_summaries() {
  local dir="$1"
  local folder_name
  folder_name="$(basename "$dir")"
  local summaries=""

  for md in "$dir"/*.md; do
    [[ -f "$md" ]] || continue
    local basename
    basename="$(basename "$md" .md)"
    [[ "$basename" == "_index" ]] && continue

    # H1タイトルのみ（コンテキスト削減のため）
    local title
    title="$(grep '^# ' "$md" | head -1 | sed 's/^# //')"
    [[ -z "$title" ]] && title="$basename"

    summaries+="- ${folder_name}/${basename}.md : ${title}"$'\n'
  done

  printf '%s' "$summaries"
}

# Ollama でインデックスを生成する
generate_index() {
  local folder_label="$1"
  local summaries="$2"
  local output_path="$3"
  local date_str
  date_str="$(date '+%Y-%m-%d')"

  log "INFO" "${folder_label} のインデックスを生成中（モデル: ${MODEL}）..."

  local prompt
  prompt="あなたはObsidianの知識管理を助けるアシスタントです。

以下は「${folder_label}」フォルダにあるノートのファイル名とタイトルの一覧です。
ファイル名とタイトルからトピックを推測し、グループ化した Obsidian 用の _index.md を生成してください。

【出力形式】
- 日本語で書く
- Markdown 形式
- トピック別のセクション（## トピック名）に分ける（3〜7グループ）
- 各ノートは [[ファイルベース名]] 形式のwikilink + 1行の日本語説明（ファイル名から推測）
- 最初に更新日（${date_str}）と概要（1〜2文）を入れる
- 「## 未分類」は使わない、全てどこかに分類する

【ファイル一覧】
${summaries}

_index.md の内容のみを出力してください（前置き・説明・コードブロック不要）:"

  local tmp_json
  tmp_json="$(mktemp)"

  jq -n \
    --arg model "$MODEL" \
    --arg prompt "$prompt" \
    '{"model": $model, "prompt": $prompt, "stream": false, "options": {"num_ctx": 8192, "num_predict": 4096}}' \
    > "$tmp_json"

  local response
  response="$(curl -sf --max-time "$TIMEOUT" "$OLLAMA_URL" \
    -H 'Content-Type: application/json' \
    -d "@${tmp_json}" \
    | jq -r '.response // empty')"
  rm -f "$tmp_json"

  if [[ -z "$response" ]]; then
    log "ERROR" "${folder_label} の生成に失敗しました"
    return 1
  fi

  # ファイルに書き込む
  {
    echo "---"
    echo "date: ${date_str}"
    echo "type: index"
    echo "auto-generated: true"
    echo "model: ${MODEL}"
    echo "---"
    echo ""
    echo "$response"
  } > "$output_path"

  log "INFO" "生成完了: ${output_path}"
}

# --- メイン ---

has_error=0

# investigations/
log "INFO" "investigations/ のファイルを収集中..."
inv_summaries="$(collect_summaries "$INVESTIGATIONS_DIR")"
inv_count="$(echo "$inv_summaries" | grep -c '^-' || true)"
log "INFO" "${inv_count} 件のファイルを収集"

if [[ "$inv_count" -gt 0 ]]; then
  generate_index "investigations" "$inv_summaries" "$INVESTIGATIONS_DIR/_index.md" || has_error=1
else
  log "WARN" "investigations/ にインデックス対象のファイルがありません"
fi

echo ""

# knowledge/
log "INFO" "knowledge/ のファイルを収集中..."
know_summaries="$(collect_summaries "$KNOWLEDGE_DIR")"
know_count="$(echo "$know_summaries" | grep -c '^-' || true)"
log "INFO" "${know_count} 件のファイルを収集"

if [[ "$know_count" -gt 0 ]]; then
  generate_index "knowledge" "$know_summaries" "$KNOWLEDGE_DIR/_index.md" || has_error=1
else
  log "WARN" "knowledge/ にインデックス対象のファイルがありません"
fi

echo ""
if [[ "$has_error" -ne 0 ]]; then
  log "ERROR" "一部のインデックス生成に失敗しました"
  exit 1
fi

log "INFO" "完了"
log "INFO" "  → $INVESTIGATIONS_DIR/_index.md"
log "INFO" "  → $KNOWLEDGE_DIR/_index.md"
