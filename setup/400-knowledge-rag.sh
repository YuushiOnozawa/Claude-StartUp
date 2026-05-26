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
elif command -v apt-get &>/dev/null; then
  echo "  → Python 3.11+ が未導入。deadsnakes PPA からインストールを試みます..."
  if (add-apt-repository -y ppa:deadsnakes/ppa >/dev/null 2>&1 && \
      apt-get update -qq 2>/dev/null && \
      apt-get install -y python3.11 python3.11-venv >/dev/null 2>&1); then
    KRAG_PYTHON_CMD="python3.11"
    ok "Python 3.11 (自動インストール完了)"
  else
    fail "Python 3.11+  →  手動: sudo add-apt-repository ppa:deadsnakes/ppa && sudo apt install python3.11 python3.11-venv"
    MISSING_CMDS+=("python3.11+")
  fi
else
  fail "Python 3.11+  →  手動: https://www.python.org/downloads/"
  MISSING_CMDS+=("python3.11+")
fi

# jq (JSON 操作に必要)
check_cmd "jq" "jq" "brew install jq  /  apt install jq"

# venv 作成 + pip パッケージ
KRAG_VENV="$HOME/.local/share/knowledge-rag/venv"

if [[ -n "$KRAG_PYTHON_CMD" ]]; then
  # 既存 venv が壊れている場合は再作成 (rm -rf 対象はハードコードされたパスのみ)
  if [[ -d "$KRAG_VENV" ]] && ! "$KRAG_VENV/bin/python" -c "import sys" &>/dev/null; then
    echo "  → 既存 venv が壊れています。再作成します..."
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

# Ollama モデルリスト（ティア別）
# 追加・変更はここだけ編集すればよい
# OLLAMA_TIER=low  → デフォルト（現PC向け）
# OLLAMA_TIER=high → TargetPC: RTX 3070 / 8GB VRAM
OLLAMA_MODELS_LOW=(
  "qwen2.5:3b"   # ~1.9GB  知識蒸留・軽量用途
)
OLLAMA_MODELS_HIGH=(
  "qwen2.5:3b"   # ~1.9GB  軽量・高速用途
  "qwen2.5:7b"   # ~4.7GB  高品質知識蒸留（primary）
)

if command -v ollama &>/dev/null; then
  if [[ "${SKIP_OLLAMA_MODEL:-}" == "1" ]]; then
    echo "  ℹ  SKIP_OLLAMA_MODEL=1 のためモデル取得をスキップ"
  elif ! ollama list &>/dev/null; then
    fail "ollama model  →  ollama serve を起動してから再実行してください"
    MISSING_CMDS+=("ollama-model")
  else
    if [[ "${OLLAMA_TIER:-low}" == "high" ]]; then
      _OLLAMA_MODELS=("${OLLAMA_MODELS_HIGH[@]}")
    else
      _OLLAMA_MODELS=("${OLLAMA_MODELS_LOW[@]}")
    fi

    for _model in "${_OLLAMA_MODELS[@]}"; do
      if ollama list 2>/dev/null | grep -qE "^${_model//./\\.}([[:space:]]|$)"; then
        ok "ollama model ${_model}"
      else
        echo "  → ${_model} をダウンロードします..."
        echo "    ⚠  大容量ダウンロードです。ネットワーク環境を確認してください。"
        if ollama pull "${_model}"; then
          ok "ollama model ${_model} (ダウンロード完了)"
        else
          fail "ollama model  →  手動: ollama pull ${_model}"
          MISSING_CMDS+=("ollama-model")
        fi
      fi
    done

    # primary model（リスト末尾）を knowledge-distill 用に保存
    _PRIMARY_MODEL="${_OLLAMA_MODELS[-1]}"
    mkdir -p "$HOME/.local/share/knowledge-rag"
    echo "${_PRIMARY_MODEL}" > "$HOME/.local/share/knowledge-rag/model"
    ok "primary model → ${_PRIMARY_MODEL}"
  fi
fi

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

# knowledge-distill hook スクリプトの実行権限を保証し SessionEnd に登録
KRAG_HOOK="$HOME/.claude/hooks/knowledge-distill.sh"
if [[ -f "$KRAG_HOOK" ]]; then
  chmod +x "$KRAG_HOOK"
  ok "knowledge-distill hook (chmod)"

  # settings.json の SessionEnd に未登録なら追加
  KRAG_SETTINGS="$HOME/.claude/settings.json"
  if [[ -f "$KRAG_SETTINGS" ]] && command -v jq &>/dev/null; then
    KRAG_HOOK_CMD="bash -c 'trap \"\" INT TERM; bash ${HOME}/.claude/hooks/knowledge-distill.sh 2>> ${HOME}/.claude/hooks/knowledge-distill.log'"
    _krag_tmp="${KRAG_SETTINGS}.tmp"
    if jq --arg cmd "$KRAG_HOOK_CMD" '
      .hooks.SessionEnd //= [] |
      if (.hooks.SessionEnd | map(.hooks[]?.command // "") | any(contains("knowledge-distill.sh"))) then .
      else .hooks.SessionEnd += [{"hooks": [{"type": "command", "command": $cmd}]}]
      end
    ' "$KRAG_SETTINGS" > "$_krag_tmp" && mv "$_krag_tmp" "$KRAG_SETTINGS"; then
      ok "settings.json (SessionEnd: knowledge-distill)"
    else
      rm -f "$_krag_tmp"
      fail "settings.json の SessionEnd 更新に失敗"
      MISSING_CMDS+=("knowledge-distill-hook-settings")
    fi
  fi
fi

# check-queue hook スクリプトの実行権限を保証し UserPromptSubmit に登録
KRAG_CQ_HOOK="$HOME/.claude/hooks/check-queue.sh"
if [[ -f "$KRAG_CQ_HOOK" ]]; then
  chmod +x "$KRAG_CQ_HOOK"
  ok "check-queue hook (chmod)"

  KRAG_SETTINGS="$HOME/.claude/settings.json"
  if [[ -f "$KRAG_SETTINGS" ]] && command -v jq &>/dev/null; then
    KRAG_CQ_CMD="bash ${HOME}/.claude/hooks/check-queue.sh"
    _krag_tmp="${KRAG_SETTINGS}.tmp"
    if jq --arg cmd "$KRAG_CQ_CMD" '
      .hooks.UserPromptSubmit //= [] |
      if (.hooks.UserPromptSubmit | map(.hooks[]?.command // "") | any(contains("check-queue.sh"))) then .
      else .hooks.UserPromptSubmit += [{"hooks": [{"type": "command", "command": $cmd}]}]
      end
    ' "$KRAG_SETTINGS" > "$_krag_tmp" && mv "$_krag_tmp" "$KRAG_SETTINGS"; then
      ok "settings.json (UserPromptSubmit: check-queue)"
    else
      rm -f "$_krag_tmp"
      fail "settings.json の UserPromptSubmit 更新に失敗"
      MISSING_CMDS+=("check-queue-hook-settings")
    fi
  fi
fi

# config.yaml の自動生成（初回のみ、既存は上書きしない）
# 生成先は venv 親ディレクトリ (~/.local/share/knowledge-rag/) — KnowledgeOrchestrator が自動発見できる場所
KRAG_REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
KRAG_CONFIG="$HOME/.local/share/knowledge-rag/config.yaml"
KRAG_CONFIG_EXAMPLE="$KRAG_REPO_DIR/config.example.yaml"

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

# knowledge-auto-promote.sh の配置（hooks/ → ~/.claude/hooks/）
_KRAG_PROMOTE_SRC="${KRAG_REPO_DIR}/hooks/knowledge-auto-promote.sh"
_KRAG_PROMOTE_DST="$HOME/.claude/hooks/knowledge-auto-promote.sh"
if [[ -f "$_KRAG_PROMOTE_SRC" ]]; then
  if cp "$_KRAG_PROMOTE_SRC" "$_KRAG_PROMOTE_DST" && chmod +x "$_KRAG_PROMOTE_DST"; then
    ok "knowledge-auto-promote.sh"
  else
    fail "knowledge-auto-promote.sh  →  手動: cp $_KRAG_PROMOTE_SRC $_KRAG_PROMOTE_DST"
  fi
fi

# knowledge-prune.sh の配置と SessionEnd 登録（bash-only decay/pruning, Issue #92/#103）
_KRAG_PRUNE_SRC="${KRAG_REPO_DIR}/hooks/knowledge-prune.sh"
_KRAG_PRUNE_DST="$HOME/.claude/hooks/knowledge-prune.sh"
if [[ -f "$_KRAG_PRUNE_SRC" ]]; then
  if cp "$_KRAG_PRUNE_SRC" "$_KRAG_PRUNE_DST" && chmod +x "$_KRAG_PRUNE_DST"; then
    ok "knowledge-prune.sh (配置)"
  else
    fail "knowledge-prune.sh  →  手動: cp $_KRAG_PRUNE_SRC $_KRAG_PRUNE_DST"
  fi

  KRAG_SETTINGS="$HOME/.claude/settings.json"
  if [[ -f "$KRAG_SETTINGS" ]] && command -v jq &>/dev/null; then
    _KRAG_PRUNE_CMD="bash -c 'trap \"\" INT TERM; bash \"${HOME}/.claude/hooks/knowledge-prune.sh\" 2>> \"${HOME}/.claude/hooks/logs/knowledge-prune.log\"'"
    _krag_tmp="${KRAG_SETTINGS}.tmp"
    if jq --arg cmd "$_KRAG_PRUNE_CMD" '
      .hooks.SessionEnd //= [] |
      if (.hooks.SessionEnd | map(.hooks[]?.command // "") | any(contains("knowledge-prune.sh"))) then .
      else .hooks.SessionEnd += [{"hooks": [{"type": "command", "command": $cmd}]}]
      end
    ' "$KRAG_SETTINGS" > "$_krag_tmp" && mv "$_krag_tmp" "$KRAG_SETTINGS"; then
      ok "settings.json (SessionEnd: knowledge-prune)"
    else
      rm -f "$_krag_tmp"
      fail "settings.json の SessionEnd 更新に失敗"
      MISSING_CMDS+=("knowledge-prune-hook-settings")
    fi
  fi
fi
