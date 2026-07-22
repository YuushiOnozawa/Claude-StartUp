---
name: remember
description: Save the current knowledge/insight to Obsidian knowledge/ and register it to knowledge-rag. Use when the user says "/remember", "note", "capture", "Obsidianに入れといて", "知見として保存", "記録しておいて", "これを残して", or similar requests to explicitly save knowledge from the conversation.
---

# Remember Skill

会話中の知見を `$HOME/.local/share/knowledge-rag/knowledge/` に保存し、knowledge-rag に登録するスキル。
Markdown 整形と RAG 登録はローカル LLM（`llm` CLI）に委ねる。

## ステップ 1: 保存内容の確認（Claude）

ユーザーが内容を明示していればそのまま使う。明示がなければ直前の会話から
「保存すべき知見・結論・調査結果」を抽出し、ユーザーに確認する。

確定した内容を **RAW_CONTENT** として後続ステップに渡す。

## ステップ 2: ファイル名を決める（Claude）

トピックを英小文字ケバブケースに変換して決める（例: `rclone-pcloud-bisync-behavior`）。

- 既存ファイルと被る場合は日付サフィックスを追加（例: `topic-2026-05-18.md`）
- 最終パス: `$HOME/.local/share/knowledge-rag/knowledge/{filename}.md`

## ステップ 3: ローカル LLM で Markdown を生成してファイルに保存

以下の Bash コマンドを実行する。`{RAW_CONTENT}` には確定した内容を、`{filename}` にはステップ 2 で決めたファイル名を代入すること。

```bash
LLM="$HOME/.local/share/knowledge-rag/venv/bin/llm"
MODEL="$(grep . "$HOME/.local/share/knowledge-rag/model" 2>/dev/null || echo "qwen2.5:3b")"
OUTPUT="$HOME/.local/share/knowledge-rag/knowledge/{filename}.md"

mkdir -p "$(dirname "$OUTPUT")"

RAW_CONTENT=$(cat <<'RAWEOF'
{RAW_CONTENT}
RAWEOF
)

printf '以下の内容を Markdown 形式（# タイトル + セクション分け、日本語）で整形してください。frontmatter は不要です:\n\n%s' \
  "$RAW_CONTENT" \
  | "$LLM" prompt -m "$MODEL" > "$OUTPUT"

echo "保存完了: $OUTPUT"
```

## ステップ 4: knowledge-rag に登録（ローカル LLM）

```bash
LLM="$HOME/.local/share/knowledge-rag/venv/bin/llm"
MODEL="$(grep . "$HOME/.local/share/knowledge-rag/model" 2>/dev/null || echo "qwen2.5:3b")"
OUTPUT="$HOME/.local/share/knowledge-rag/knowledge/{filename}.md"

{
  echo "add_documentツールを使って次のMarkdownをknowledge-ragに登録してください。"
  echo "filepath: knowledge/{filename}.md"
  echo "category: knowledge"
  echo "content:"
  cat "$OUTPUT"
} | KNOWLEDGE_RAG_DIR="$HOME/.local/share/knowledge-rag" \
  "$LLM" prompt -m "$MODEL" -T MCP --no-stream \
  || { echo "knowledge-rag 登録失敗（ファイル保存は完了）" >&2; false; }
```

## ステップ 5: 完了報告（Claude）

保存先パスを1行でユーザーに報告する。

例: $HOME/.local/share/knowledge-rag/knowledge/{filename}.md に保存・登録しました。
