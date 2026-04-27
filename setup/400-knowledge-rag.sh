# setup/400-knowledge-rag.sh — knowledge-rag pipeline セットアップ
# Requires: ok, fail, check_cmd, MISSING_CMDS (append-only)

[[ "${BASH_SOURCE[0]}" == "$0" ]] && { echo "ERROR: setup.sh から source してください" >&2; exit 1; }

# --- knowledge-rag pipeline: RAG ベースの知識検索 ---
echo ""
echo "--- knowledge-rag pipeline ---"

# Python 3.11+ 確認
KRAG_PYTHON_CMD=""
for py_candidate in python3.13 python3.12 python3.11 python3; do
  if command -v "$py_candidate" &>/dev/null; then
    if "$py_candidate" -c "import sys; sys.exit(0 if sys.version_info >= (3, 11) else 1)" 2>/dev/null; then
      KRAG_PYTHON_CMD="$py_candidate"
      break
    fi
  fi
done

if [[ -n "$KRAG_PYTHON_CMD" ]]; then
  ok "Python 3.11+ ($KRAG_PYTHON_CMD)"
else
  fail "Python 3.11+  →  https://www.python.org/downloads/"
  MISSING_CMDS+=("python3.11+")
fi

# jq (JSON 操作に必要)
check_cmd "jq" "jq" "brew install jq  /  apt install jq"

# venv 作成 + pip パッケージ
KRAG_VENV="$HOME/.local/share/knowledge-rag/venv"

if [[ -n "$KRAG_PYTHON_CMD" ]]; then
  # 既存 venv が壊れている場合は再作成
  if [[ -d "$KRAG_VENV" ]] && ! "$KRAG_VENV/bin/python" -c "import sys" &>/dev/null; then
    echo "  → 既存 venv が壊れています。再作成します..."
    # パス検証ガード: rm -rf の対象が想定パスと一致することを確認
    [[ "$KRAG_VENV" == "$HOME/.local/share/knowledge-rag/venv" ]] || { fail "KRAG_VENV が想定外: $KRAG_VENV"; MISSING_CMDS+=("knowledge-rag-venv"); return 0; }
    rm -rf "$KRAG_VENV"
  fi

  if [[ ! -d "$KRAG_VENV" ]]; then
    echo "  → venv 作成: $KRAG_VENV"
    mkdir -p "$(dirname "$KRAG_VENV")"
    if "$KRAG_PYTHON_CMD" -m venv "$KRAG_VENV"; then
      "$KRAG_VENV/bin/pip" install --quiet --upgrade pip 2>/dev/null || true
      ok "venv 作成完了"
    else
      fail "venv 作成失敗  →  apt install python3-venv が必要かもしれません"
      MISSING_CMDS+=("knowledge-rag-venv")
    fi
  fi

  if [[ -x "$KRAG_VENV/bin/pip" ]]; then
    KRAG_PKGS=(knowledge-rag llm llm-ollama llm-tools-mcp)
    KRAG_MISSING_PKGS=()
    for pkg in "${KRAG_PKGS[@]}"; do
      if ! "$KRAG_VENV/bin/pip" show "$pkg" >/dev/null 2>&1; then
        KRAG_MISSING_PKGS+=("$pkg")
      fi
    done

    if [[ ${#KRAG_MISSING_PKGS[@]} -eq 0 ]]; then
      ok "knowledge-rag venv パッケージ"
    else
      echo "  → 不足パッケージをインストール: ${KRAG_MISSING_PKGS[*]}"
      if "$KRAG_VENV/bin/pip" install --quiet "${KRAG_MISSING_PKGS[@]}"; then
        ok "knowledge-rag venv パッケージ (自動インストール完了)"
      else
        fail "knowledge-rag パッケージ  →  手動: $KRAG_VENV/bin/pip install ${KRAG_PKGS[*]}"
        MISSING_CMDS+=("knowledge-rag-pkgs")
      fi
    fi
  fi
fi

# Ollama
if ! command -v ollama &>/dev/null; then
  echo "  → Ollama が未導入。公式インストーラを実行..."
  if curl -fsSL https://ollama.com/install.sh | sh; then
    ok "Ollama (自動インストール完了)"
  else
    fail "Ollama  →  手動: https://ollama.com/download"
    MISSING_CMDS+=("ollama")
  fi
else
  ok "ollama"
fi

# Ollama モデル (qwen2.5:3b, ~1.9GB)
if command -v ollama &>/dev/null; then
  if [[ "${SKIP_OLLAMA_MODEL:-}" == "1" ]]; then
    echo "  ℹ  SKIP_OLLAMA_MODEL=1 のためモデル取得をスキップ"
  elif ollama list 2>/dev/null | grep -qE '^qwen2.5:3b[[:space:]]'; then
    ok "ollama model qwen2.5:3b"
  else
    # ollama serve が起動していなければモデル取得をスキップ
    if ! ollama list &>/dev/null; then
      fail "ollama model  →  ollama serve を起動してから再実行してください"
      MISSING_CMDS+=("ollama-model")
    else
      echo "  → qwen2.5:3b モデル (~1.9GB) をダウンロードします..."
      echo "    ⚠  大容量ダウンロードです。ネットワーク環境を確認してください。"
      if ollama pull qwen2.5:3b; then
        ok "ollama model qwen2.5:3b (ダウンロード完了)"
      else
        fail "ollama model  →  手動: ollama pull qwen2.5:3b"
        MISSING_CMDS+=("ollama-model")
      fi
    fi
  fi
fi

# llm-tools-mcp 設定 (~/.llm-tools-mcp/mcp.json)
LLM_MCP_DIR="$HOME/.llm-tools-mcp"
LLM_MCP_CONF="$LLM_MCP_DIR/mcp.json"

if [[ -x "$KRAG_VENV/bin/python" ]] && command -v jq &>/dev/null; then
  KRAG_PYTHON_ABS="$KRAG_VENV/bin/python"

  if [[ -f "$LLM_MCP_CONF" ]] && \
     jq -e '.mcpServers["knowledge-rag"]' "$LLM_MCP_CONF" >/dev/null 2>&1; then
    ok "llm-tools-mcp config"
  else
    echo "  → llm-tools-mcp 設定を書き込み: $LLM_MCP_CONF"
    mkdir -p "$LLM_MCP_DIR"
    if [[ -f "$LLM_MCP_CONF" ]]; then
      jq --arg py "$KRAG_PYTHON_ABS" \
        '.mcpServers["knowledge-rag"] = {"type":"stdio","command":$py,"args":["-m","mcp_server.server"]}' \
        "$LLM_MCP_CONF" > "$LLM_MCP_CONF.tmp" && mv "$LLM_MCP_CONF.tmp" "$LLM_MCP_CONF"
    else
      jq -n --arg py "$KRAG_PYTHON_ABS" \
        '{"mcpServers":{"knowledge-rag":{"type":"stdio","command":$py,"args":["-m","mcp_server.server"]}}}' \
        > "$LLM_MCP_CONF"
    fi
    ok "llm-tools-mcp config (書き込み完了)"
  fi
elif ! command -v jq &>/dev/null; then
  fail "llm-tools-mcp config  →  jq が必要です"
fi
