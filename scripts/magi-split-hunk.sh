#!/usr/bin/env bash
# git unified diff を hunk 単位（行数上限付き）に分割する
# 使用法: printf '%s' "$DIFF" | bash scripts/magi-split-hunk.sh [MAX_LINES]
#   MAX_LINES  1チャンクの最大行数（デフォルト: 200）
# 出力: 各チャンクを "=== CHUNK: <path> (<n>) ===" ヘッダーで区切ったセクション
#       各チャンクにはファイルヘッダー（diff --git / --- / +++）を再付与

MAX_LINES="${1:-200}"

awk -v max_lines="$MAX_LINES" '
BEGIN {
  file_count = 0
  file_lines = 0
  pack_buf = ""
  pack_lines = 0
  pack_files = 0
}

function clear_file(   i) {
  for (i = 1; i <= file_lines; i++) delete current[i]
  file_lines = 0
}

function flush_pack(   label) {
  if (pack_buf == "") return
  label = "=== CHUNK: " pack_path
  if (pack_files > 1) label = label " +" (pack_files - 1) " files"
  label = label " (1) ==="
  print label
  printf "%s", pack_buf
  print ""
  pack_buf = ""
  pack_lines = 0
  pack_files = 0
}

function emit_large(   i, line, header, body, body_lines, chunk_n) {
  flush_pack()
  header = ""
  body = ""
  body_lines = 0
  chunk_n = 0
  for (i = 1; i <= file_lines; i++) {
    line = current[i]
    if (line ~ /^@@/) {
      if (body_lines > 0 && body_lines >= max_lines) {
        chunk_n++
        print "=== CHUNK: " file_path " (" chunk_n ") ==="
        printf "%s", header
        printf "%s", body
        print ""
        body = ""
        body_lines = 0
      }
      body = body line "\n"
      body_lines++
    } else if (body_lines == 0 &&
               (line ~ /^diff --git a\// || line ~ /^(new|deleted) file mode / ||
                line ~ /^index / || line ~ /^similarity / || line ~ /^rename / ||
                line ~ /^Binary / || line ~ /^--- / || line ~ /^\+\+\+ /)) {
      header = header line "\n"
    } else {
      body = body line "\n"
      body_lines++
    }
  }
  if (body != "") {
    chunk_n++
    print "=== CHUNK: " file_path " (" chunk_n ") ==="
    printf "%s", header
    printf "%s", body
    print ""
  }
}

function finish_file(   i, raw, total) {
  if (file_lines == 0) return
  raw = ""
  for (i = 1; i <= file_lines; i++) raw = raw current[i] "\n"
  total = file_lines
  if (total <= max_lines) {
    if (pack_buf != "" && pack_lines + total > max_lines) flush_pack()
    if (pack_buf == "") pack_path = file_path
    pack_buf = pack_buf raw
    pack_lines += total
    pack_files++
  } else {
    emit_large()
  }
  clear_file()
}

/^diff --git a\// && / b\// {
  finish_file()
  file_path = $NF
  sub(/^b\//, "", file_path)
  current[++file_lines] = $0
  next
}

{
  if (file_lines > 0) current[++file_lines] = $0
}

END {
  finish_file()
  flush_pack()
}
'
