#!/usr/bin/env bash
# git unified diff を hunk 単位（行数上限付き）に分割する
# 使用法: printf '%s' "$DIFF" | bash scripts/magi-split-hunk.sh [MAX_LINES]
#   MAX_LINES  1チャンクの最大行数（デフォルト: 100）
# 出力: 各チャンクを "=== CHUNK: <path> (<n>) ===" ヘッダーで区切ったセクション
#       各チャンクにはファイルヘッダー（diff --git / --- / +++）を再付与

MAX_LINES="${1:-200}"

awk -v max_lines="$MAX_LINES" '
BEGIN {
  file_header = ""
  chunk_lines = 0
  chunk_buf   = ""
  chunk_n     = 0
  path        = ""
}

function flush_chunk(   label) {
  if (chunk_buf == "") return
  chunk_n++
  label = "=== CHUNK: " path " (" chunk_n ") ==="
  print label
  printf "%s", file_header
  printf "%s", chunk_buf
  print ""
  chunk_buf   = ""
  chunk_lines = 0
}

# ファイルヘッダー行: diff --git a/... b/...
/^diff --git a\// && / b\// {
  flush_chunk()
  chunk_n   = 0
  path      = $NF; sub(/^b\//, "", path)
  file_header = $0 "\n"
  next
}

# ファイルメタ行（new/deleted file mode, index, similarity 等）はヘッダーに追記
/^(new|deleted) file mode / || /^index / || /^similarity / || /^rename / || /^Binary / {
  file_header = file_header $0 "\n"
  next
}

# --- / +++ 行はファイルヘッダーに追記（hunk 開始前のみ）
/^--- / || /^\+\+\+ / {
  if (chunk_lines == 0) {
    file_header = file_header $0 "\n"
  } else {
    chunk_buf   = chunk_buf $0 "\n"
    chunk_lines++
  }
  next
}

# hunk ヘッダー: @@ ... @@
/^@@/ {
  # 現在の chunk が max_lines 行以上なら flush してから新 hunk 開始
  # （chunk_lines >= max_lines のとき flush: hunk 単位で切るため途中分割しない）
  if (chunk_lines > 0 && chunk_lines >= max_lines) {
    flush_chunk()
  }
  chunk_buf   = chunk_buf $0 "\n"
  chunk_lines++
  next
}

# その他の行（コンテキスト・追加・削除）
{
  chunk_buf   = chunk_buf $0 "\n"
  chunk_lines++
  # 上限超えかつ hunk ヘッダー手前で flush するため、ここでは flush しない
  # （hunk の途中でチャンクを切ると LLM に渡しにくいため）
}

END { flush_chunk() }
'
