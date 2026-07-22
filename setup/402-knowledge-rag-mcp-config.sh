# setup/402-knowledge-rag-mcp-config.sh — knowledge-rag: MCP 設定・config.yaml 生成
# Requires: ok, fail, MISSING_CMDS (append-only)
# Requires: KRAG_VENV (set by 400-knowledge-rag-python.sh)

[[ "${BASH_SOURCE[0]}" == "$0" ]] && { echo "ERROR: setup.sh から source してください" >&2; exit 1; }

echo ""
echo "--- knowledge-rag: mcp config ---"

_KRAG_MCP_REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

# llm-tools-mcp 設定 (~/.llm-tools-mcp/mcp.json)
LLM_MCP_DIR="$HOME/.llm-tools-mcp"
LLM_MCP_CONF="$LLM_MCP_DIR/mcp.json"

if [[ -x "$KRAG_VENV/bin/python" ]] && command -v jq &>/dev/null; then
  KRAG_PYTHON_ABS="$KRAG_VENV/bin/python"

  if [[ -s "$LLM_MCP_CONF" ]] && \
     jq -e '.mcpServers["knowledge-rag"]' "$LLM_MCP_CONF" >/dev/null 2>&1; then
    ok "llm-tools-mcp config"
  else
    echo "  → llm-tools-mcp 設定を書き込み: $LLM_MCP_CONF"
    mkdir -p "$LLM_MCP_DIR"
    if [[ -s "$LLM_MCP_CONF" ]]; then
      if jq --arg py "$KRAG_PYTHON_ABS" \
        '.mcpServers["knowledge-rag"] = {"type":"stdio","command":$py,"args":["-m","mcp_server.server"]}' \
        "$LLM_MCP_CONF" > "$LLM_MCP_CONF.tmp" && mv "$LLM_MCP_CONF.tmp" "$LLM_MCP_CONF"; then
        ok "llm-tools-mcp config (書き込み完了)"
      else
        rm -f "$LLM_MCP_CONF.tmp"
        fail "llm-tools-mcp config  →  jq 編集失敗"
        MISSING_CMDS+=("llm-tools-mcp-config")
      fi
    else
      if jq -n --arg py "$KRAG_PYTHON_ABS" \
        '{"mcpServers":{"knowledge-rag":{"type":"stdio","command":$py,"args":["-m","mcp_server.server"]}}}' \
        > "$LLM_MCP_CONF.tmp" && mv "$LLM_MCP_CONF.tmp" "$LLM_MCP_CONF"; then
        ok "llm-tools-mcp config (書き込み完了)"
      else
        rm -f "$LLM_MCP_CONF.tmp"
        fail "llm-tools-mcp config  →  jq 生成失敗"
        MISSING_CMDS+=("llm-tools-mcp-config")
      fi
    fi
  fi
elif ! command -v jq &>/dev/null; then
  fail "llm-tools-mcp config  →  jq が必要です"
fi

# Claude Code settings.local.json の mcpServers に knowledge-rag を登録
_KRAG_CC_SETTINGS="$HOME/.claude/settings.local.json"
if [[ -x "$KRAG_VENV/bin/python" ]] && command -v jq &>/dev/null; then
  _krag_py_abs="$KRAG_VENV/bin/python"
  _krag_already=false
  if [[ -s "$_KRAG_CC_SETTINGS" ]] && \
     jq -e '.mcpServers["knowledge-rag"]' "$_KRAG_CC_SETTINGS" >/dev/null 2>&1; then
    _krag_already=true
  fi
  if [[ "$_krag_already" == true ]]; then
    ok "settings.local.json (mcpServers: knowledge-rag)"
  else
    _krag_tmp="${_KRAG_CC_SETTINGS}.tmp"
    _krag_ok=false
    if [[ -s "$_KRAG_CC_SETTINGS" ]]; then
      if jq --arg py "$_krag_py_abs" \
        '.mcpServers["knowledge-rag"] = {"type":"stdio","command":$py,"args":["-m","mcp_server.server"]}' \
        "$_KRAG_CC_SETTINGS" > "$_krag_tmp" && mv "$_krag_tmp" "$_KRAG_CC_SETTINGS"; then
        _krag_ok=true
      else
        rm -f "$_krag_tmp"
      fi
    else
      mkdir -p "$(dirname "$_KRAG_CC_SETTINGS")"
      if jq -n --arg py "$_krag_py_abs" \
        '{"mcpServers":{"knowledge-rag":{"type":"stdio","command":$py,"args":["-m","mcp_server.server"]}}}' \
        > "$_KRAG_CC_SETTINGS"; then
        _krag_ok=true
      fi
    fi
    if [[ "$_krag_ok" == true ]]; then
      ok "settings.local.json (mcpServers: knowledge-rag 追加)"
    else
      fail "settings.local.json の mcpServers 更新に失敗"
      MISSING_CMDS+=("cc-mcp-settings")
    fi
  fi
fi

# config.yaml の自動生成（初回のみ、既存は上書きしない）
# 生成先は venv 親ディレクトリ (~/.local/share/knowledge-rag/) — KnowledgeOrchestrator が自動発見できる場所
KRAG_CONFIG="$HOME/.local/share/knowledge-rag/config.yaml"
KRAG_CONFIG_EXAMPLE="$_KRAG_MCP_REPO_DIR/config.example.yaml"

if [[ -f "$KRAG_CONFIG" ]]; then
  ok "config.yaml (既存)"
elif [[ -f "$KRAG_CONFIG_EXAMPLE" ]]; then
  echo "  → config.yaml を生成: $KRAG_CONFIG"
  mkdir -p "$(dirname "$KRAG_CONFIG")"
  if sed "s|documents_dir: \"./documents\"|documents_dir: \"${HOME}/.local/share/knowledge-rag\"|" \
    "$KRAG_CONFIG_EXAMPLE" > "$KRAG_CONFIG" && \
    grep -q "documents_dir: \"${HOME}/.local/share/knowledge-rag\"" "$KRAG_CONFIG"; then
    ok "config.yaml (documents_dir=${HOME}/.local/share/knowledge-rag)"
  else
    fail "config.yaml  →  sed 置換失敗"
    rm -f "$KRAG_CONFIG"
    MISSING_CMDS+=("knowledge-rag-config")
  fi
else
  fail "config.yaml  →  config.example.yaml が見つかりません"
  MISSING_CMDS+=("knowledge-rag-config")
fi

# 既存 config.yaml の documents_dir を旧 pCloud パスからローカルパスへ移行する。
# documents_dir の値行だけを対象にし、カスタム値や複雑な設定は変更しない。
if [[ -f "$KRAG_CONFIG" ]]; then
  _KRAG_LOCAL_DOCS_DIR="$HOME/.local/share/knowledge-rag"
  if ! _KRAG_DOCS_SUMMARY="$(awk \
    -v old_abs="$HOME/pcloud/obsidian" \
    -v old_tilde="~/pcloud/obsidian" \
    -v new_path="$_KRAG_LOCAL_DOCS_DIR" '
      function trim(value) {
        sub(/^[[:space:]]+/, "", value)
        sub(/[[:space:]]+$/, "", value)
        return value
      }
      function document_value(line,    colon, value) {
        if (line !~ /^[[:space:]]*documents_dir[[:space:]]*:/) return ""
        colon = index(line, ":")
        value = trim(substr(line, colon + 1))
        if (value ~ /^"[^"]*"[[:space:]]*(#.*)?$/) {
          sub(/^"/, "", value)
          sub(/"[[:space:]]*(#.*)?$/, "", value)
          return value
        }
        if (value ~ /^[^[:space:]#]+[[:space:]]*(#.*)?$/) {
          sub(/[[:space:]]+#.*$/, "", value)
          return value
        }
        return "__complex_documents_dir__"
      }
      {
        if ($0 !~ /^[[:space:]]*documents_dir[[:space:]]*:/) next
        total++
        value = document_value($0)
        if (value == old_abs || value == old_tilde) old++
        else if (value == new_path) new++
        else custom++
      }
      END { printf "%d %d %d %d\n", old, new, custom, total }
    ' "$KRAG_CONFIG")"; then
    fail "config.yaml documents_dir の検査に失敗"
    MISSING_CMDS+=("knowledge-rag-documents-dir")
  else
    read -r _KRAG_OLD_DOCS _KRAG_NEW_DOCS _KRAG_CUSTOM_DOCS _KRAG_DOCS_TOTAL <<<"$_KRAG_DOCS_SUMMARY"
    if [[ "$_KRAG_OLD_DOCS" -eq 1 && "$_KRAG_NEW_DOCS" -eq 0 && "$_KRAG_CUSTOM_DOCS" -eq 0 ]]; then
      _KRAG_DOCS_TMP=""
      if _KRAG_DOCS_TMP="$(mktemp "${KRAG_CONFIG}.XXXXXX" 2>/dev/null)" && \
         awk \
           -v old_abs="$HOME/pcloud/obsidian" \
           -v old_tilde="~/pcloud/obsidian" \
           -v new_path="$_KRAG_LOCAL_DOCS_DIR" '
             function trim(value) {
               sub(/^[[:space:]]+/, "", value)
               sub(/[[:space:]]+$/, "", value)
               return value
             }
             function document_value(line,    colon, value) {
               if (line !~ /^[[:space:]]*documents_dir[[:space:]]*:/) return ""
               colon = index(line, ":")
               value = trim(substr(line, colon + 1))
               if (value ~ /^"[^"]*"[[:space:]]*(#.*)?$/) {
                 sub(/^"/, "", value)
                 sub(/"[[:space:]]*(#.*)?$/, "", value)
                 return value
               }
               if (value ~ /^[^[:space:]#]+[[:space:]]*(#.*)?$/) {
                 sub(/[[:space:]]+#.*$/, "", value)
                 return value
               }
               return "__complex_documents_dir__"
             }
             function replacement(line,    colon, rest, suffix) {
               colon = index(line, ":")
               rest = substr(line, colon + 1)
               suffix = ""
               if (match(rest, /[[:space:]]+#.*/)) suffix = substr(rest, RSTART)
               return substr(line, 1, colon) " \"" new_path "\"" suffix
             }
             {
               value = document_value($0)
               if (value == old_abs || value == old_tilde) print replacement($0)
               else print
             }
           ' "$KRAG_CONFIG" >"$_KRAG_DOCS_TMP"; then
        _KRAG_DOCS_AFTER="$(awk \
          -v old_abs="$HOME/pcloud/obsidian" \
          -v old_tilde="~/pcloud/obsidian" \
          -v new_path="$_KRAG_LOCAL_DOCS_DIR" '
            function trim(value) {
              sub(/^[[:space:]]+/, "", value)
              sub(/[[:space:]]+$/, "", value)
              return value
            }
            function document_value(line,    colon, value) {
              if (line !~ /^[[:space:]]*documents_dir[[:space:]]*:/) return ""
              colon = index(line, ":")
              value = trim(substr(line, colon + 1))
              if (value ~ /^"[^"]*"[[:space:]]*(#.*)?$/) {
                sub(/^"/, "", value)
                sub(/"[[:space:]]*(#.*)?$/, "", value)
                return value
              }
              if (value ~ /^[^[:space:]#]+[[:space:]]*(#.*)?$/) {
                sub(/[[:space:]]+#.*$/, "", value)
                return value
              }
              return "__complex_documents_dir__"
            }
            {
              if ($0 !~ /^[[:space:]]*documents_dir[[:space:]]*:/) next
              total++
              value = document_value($0)
              if (value == old_abs || value == old_tilde) old++
              else if (value == new_path) new++
              else custom++
            }
            END { printf "%d %d %d %d\n", old, new, custom, total }
          ' "$_KRAG_DOCS_TMP")"
        read -r _KRAG_AFTER_OLD _KRAG_AFTER_NEW _KRAG_AFTER_CUSTOM _KRAG_AFTER_TOTAL <<<"$_KRAG_DOCS_AFTER"
        if [[ "$_KRAG_AFTER_OLD" -eq 0 && "$_KRAG_AFTER_NEW" -eq 1 && \
              "$_KRAG_AFTER_CUSTOM" -eq 0 && "$_KRAG_AFTER_TOTAL" -eq 1 ]] && \
           mv "$_KRAG_DOCS_TMP" "$KRAG_CONFIG"; then
          ok "config.yaml (documents_dir=${_KRAG_LOCAL_DOCS_DIR})"
        else
          rm -f "$_KRAG_DOCS_TMP"
          fail "config.yaml documents_dir の移行検証に失敗（変更しません）"
          MISSING_CMDS+=("knowledge-rag-documents-dir")
        fi
      else
        [[ -n "$_KRAG_DOCS_TMP" ]] && rm -f "$_KRAG_DOCS_TMP"
        fail "config.yaml documents_dir の移行に失敗（変更しません）"
        MISSING_CMDS+=("knowledge-rag-documents-dir")
      fi
    elif [[ "$_KRAG_CUSTOM_DOCS" -gt 0 || "$_KRAG_OLD_DOCS" -gt 1 || \
            "$_KRAG_NEW_DOCS" -gt 1 || \
            ("$_KRAG_OLD_DOCS" -gt 0 && "$_KRAG_NEW_DOCS" -gt 0) ]]; then
      fail "config.yaml documents_dir はカスタム値または複数値のため変更しません。hooks は新ローカルパス前提のため、カスタム値のまま放置すると保存先が分裂します"
      MISSING_CMDS+=("knowledge-rag-documents-dir")
    fi
  fi
fi

# category_mappings を標準3キーで補完する（既存エントリ・インデント・コメントを保持）。
if [[ -f "$KRAG_CONFIG" ]]; then
  _KRAG_CATEGORY_TMP=""
  if _KRAG_CATEGORY_TMP="$(mktemp "${KRAG_CONFIG}.XXXXXX" 2>/dev/null)" && \
     awk '
       function trim(value) {
         sub(/^[[:space:]]+/, "", value)
         sub(/[[:space:]]+$/, "", value)
         return value
       }
       function ignored(line) { return line ~ /^[[:space:]]*($|#)/ }
       function indent_of(line) {
         match(line, /^[[:space:]]*/)
         return RLENGTH
       }
       function top_key(line,    colon, key) {
         if (line ~ /^[[:space:]]/ || ignored(line)) return ""
         colon = index(line, ":")
         if (colon == 0) return ""
         key = trim(substr(line, 1, colon - 1))
         if (key ~ /^".*"$/) {
           sub(/^"/, "", key)
           sub(/"$/, "", key)
         }
         return key
       }
       function mapping_key(line,    colon, key) {
         if (ignored(line)) return ""
         colon = index(line, ":")
         if (colon == 0) return ""
         key = trim(substr(line, 1, colon - 1))
         if (key ~ /^".*"$/) {
           sub(/^"/, "", key)
           sub(/"$/, "", key)
         }
         if (key == "" || key ~ /^-/) return ""
         return key
       }
       function spaces(count,    value) {
         value = ""
         while (length(value) < count) value = value " "
         return value
       }
       function mark_bad(message) {
         bad = 1
         if (error_message == "") error_message = message
       }
       function emit_missing(child_indent,    i, key) {
         for (i = 1; i <= 3; i++) {
           key = required[i]
           if (!seen[key]) printf "%s\"%s\": \"%s\"\n", spaces(child_indent), key, key
         }
       }
       {
         lines[NR] = $0
         key = top_key($0)
         if (key == "category_mappings") {
           category_count++
           if (category_count == 1) category_start = NR
         }
       }
       END {
         line_count = NR
         required[1] = "sessions"
         required[2] = "knowledge"
         required[3] = "lessons-learned"

         if (category_count > 1) mark_bad("複数の top-level category_mappings")
         if (bad) {
           print "category_mappings の構造が複雑なため変更しません: " error_message > "/dev/stderr"
           exit 2
         }

         if (category_count == 0) {
           for (i = 1; i <= line_count; i++) print lines[i]
           print "category_mappings:"
           emit_missing(2)
           exit 0
         }

         category_end = line_count + 1
         for (i = category_start + 1; i <= line_count; i++) {
           if (top_key(lines[i]) != "") {
             category_end = i
             break
           }
         }

         header = lines[category_start]
         colon = index(header, ":")
         value = trim(substr(header, colon + 1))
         if (value ~ /^\{\}[[:space:]]*(#.*)?$/) {
           mode = "inline_empty"
         } else if (value == "" || value ~ /^#/) {
           mode = "mapping"
         } else {
           mark_bad("category_mappings が map ではありません")
         }

         child_indent = -1
         if (mode == "mapping") {
           for (i = category_start + 1; i < category_end; i++) {
             if (ignored(lines[i])) continue
             current_indent = indent_of(lines[i])
             if (current_indent <= 0) {
               mark_bad("category_mappings の子要素のインデントが不正です")
               continue
             }
             if (child_indent < 0) child_indent = current_indent
             if (current_indent < child_indent) {
               mark_bad("category_mappings に複数階層の子インデントがあります")
               continue
             }
             if (current_indent == child_indent) {
               key = mapping_key(lines[i])
               if (key == "") mark_bad("category_mappings の子要素が map ではありません")
               else if (seen[key]) mark_bad("category_mappings に重複キーがあります")
               else seen[key] = 1
             }
           }
           if (child_indent < 0) child_indent = 2
         } else if (mode == "inline_empty") {
           for (i = category_start + 1; i < category_end; i++) {
             if (!ignored(lines[i])) mark_bad("空 map の後に予期しない子要素があります")
           }
         }

         if (bad) {
           print "category_mappings の構造が複雑なため変更しません: " error_message > "/dev/stderr"
           exit 2
         }

         needs_update = (mode == "inline_empty")
         for (i = 1; i <= 3; i++) if (!seen[required[i]]) needs_update = 1
         if (!needs_update) {
           for (i = 1; i <= line_count; i++) print lines[i]
           exit 0
         }

         for (i = 1; i <= line_count; i++) {
           if (i == category_start && mode == "inline_empty") {
             header = lines[i]
             sub(/[[:space:]]*\{\}/, "", header)
             print header
             emit_missing(2)
           } else {
             if (i == category_end && mode == "mapping") emit_missing(child_indent)
             print lines[i]
           }
         }
         if (category_end == line_count + 1 && mode == "mapping") emit_missing(child_indent)
       }
     ' "$KRAG_CONFIG" >"$_KRAG_CATEGORY_TMP"; then
    if cmp -s "$_KRAG_CATEGORY_TMP" "$KRAG_CONFIG"; then
      rm -f "$_KRAG_CATEGORY_TMP"
    elif mv "$_KRAG_CATEGORY_TMP" "$KRAG_CONFIG"; then
      ok "config.yaml (category_mappings 補完)"
    else
      rm -f "$_KRAG_CATEGORY_TMP"
      fail "config.yaml category_mappings 更新失敗（手動で追加してください）"
      MISSING_CMDS+=("knowledge-rag-category-mappings")
    fi
  else
    [[ -n "$_KRAG_CATEGORY_TMP" ]] && rm -f "$_KRAG_CATEGORY_TMP"
    fail "config.yaml category_mappings 更新失敗（構造が複雑なため変更しません）"
    MISSING_CMDS+=("knowledge-rag-category-mappings")
  fi
fi

unset _KRAG_MCP_REPO_DIR KRAG_PYTHON_ABS _KRAG_CC_SETTINGS _krag_py_abs _krag_already _krag_tmp _krag_ok
unset LLM_MCP_DIR LLM_MCP_CONF KRAG_CONFIG KRAG_CONFIG_EXAMPLE _KRAG_LOCAL_DOCS_DIR _KRAG_DOCS_SUMMARY
unset _KRAG_OLD_DOCS _KRAG_NEW_DOCS _KRAG_CUSTOM_DOCS _KRAG_DOCS_TOTAL _KRAG_DOCS_TMP _KRAG_DOCS_AFTER
unset _KRAG_AFTER_OLD _KRAG_AFTER_NEW _KRAG_AFTER_CUSTOM _KRAG_AFTER_TOTAL _KRAG_CATEGORY_TMP
