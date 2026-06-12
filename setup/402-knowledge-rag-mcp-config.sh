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
        > "$LLM_MCP_CONF"; then
        ok "llm-tools-mcp config (書き込み完了)"
      else
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
    if [[ -s "$_KRAG_CC_SETTINGS" ]]; then
      jq --arg py "$_krag_py_abs" \
        '.mcpServers["knowledge-rag"] = {"type":"stdio","command":$py,"args":["-m","mcp_server.server"]}' \
        "$_KRAG_CC_SETTINGS" > "$_krag_tmp" && mv "$_krag_tmp" "$_KRAG_CC_SETTINGS"
    else
      mkdir -p "$(dirname "$_KRAG_CC_SETTINGS")"
      jq -n --arg py "$_krag_py_abs" \
        '{"mcpServers":{"knowledge-rag":{"type":"stdio","command":$py,"args":["-m","mcp_server.server"]}}}' \
        > "$_KRAG_CC_SETTINGS"
    fi
    if [[ $? -eq 0 ]]; then
      ok "settings.local.json (mcpServers: knowledge-rag 追加)"
    else
      rm -f "$_krag_tmp"
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
  if sed "s|documents_dir: \"./documents\"|documents_dir: \"${HOME}/pcloud/obsidian\"|" \
    "$KRAG_CONFIG_EXAMPLE" > "$KRAG_CONFIG" && \
    grep -q "documents_dir: \"${HOME}/pcloud/obsidian\"" "$KRAG_CONFIG"; then
    ok "config.yaml (documents_dir=${HOME}/pcloud/obsidian)"
  else
    fail "config.yaml  →  sed 置換失敗"
    rm -f "$KRAG_CONFIG"
    MISSING_CMDS+=("knowledge-rag-config")
  fi
else
  fail "config.yaml  →  config.example.yaml が見つかりません"
  MISSING_CMDS+=("knowledge-rag-config")
fi

# 既存 config.yaml の category_mappings が空なら sessions/knowledge を追記（冪等）
if [[ -f "$KRAG_CONFIG" ]] && grep -q 'category_mappings: {}' "$KRAG_CONFIG"; then
  echo "  → config.yaml に category_mappings を追記"
  _KRAG_TMP="${KRAG_CONFIG}.tmp"
  if sed \
    's|category_mappings: {}|category_mappings:\n  "sessions": "sessions"\n  "knowledge": "knowledge"|' \
    "$KRAG_CONFIG" > "$_KRAG_TMP" && mv "$_KRAG_TMP" "$KRAG_CONFIG"; then
    ok "config.yaml (category_mappings 追加)"
  else
    rm -f "$_KRAG_TMP"
    fail "config.yaml category_mappings 更新失敗（手動で追加してください）"
    MISSING_CMDS+=("knowledge-rag-category-mappings")
  fi
fi

# config.yaml の ~/pcloud を $HOME/pcloud に展開（upstream _resolve_path が expanduser() 未実装のため）
if [[ -f "$KRAG_CONFIG" ]] && grep -q '~/pcloud' "$KRAG_CONFIG"; then
  _KRAG_TMP="${KRAG_CONFIG}.tmp"
  if sed "s|~/pcloud|$HOME/pcloud|g" "$KRAG_CONFIG" > "$_KRAG_TMP" && mv "$_KRAG_TMP" "$KRAG_CONFIG"; then
    ok "config.yaml (~/pcloud → \$HOME/pcloud 展開)"
  else
    rm -f "$_KRAG_TMP"
    fail "config.yaml  →  ~/pcloud の展開失敗"
    MISSING_CMDS+=("knowledge-rag-config-expand")
  fi
fi

unset _KRAG_MCP_REPO_DIR KRAG_PYTHON_ABS _KRAG_CC_SETTINGS _krag_py_abs _krag_already _krag_tmp
unset LLM_MCP_DIR LLM_MCP_CONF KRAG_CONFIG KRAG_CONFIG_EXAMPLE _KRAG_TMP
