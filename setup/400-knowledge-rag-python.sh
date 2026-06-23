# setup/400-knowledge-rag-python.sh — knowledge-rag: Python 環境セットアップ
# Requires: ok, fail, _detect_os, _detect_arch, _install_binary_direct, MISSING_CMDS (append-only)
# Exports: KRAG_VENV, KRAG_PYTHON_CMD (for 402-knowledge-rag-mcp-config.sh and later modules)

[[ "${BASH_SOURCE[0]}" == "$0" ]] && { echo "ERROR: setup.sh から source してください" >&2; exit 1; }

echo ""
echo "--- knowledge-rag: python ---"

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
  fail "Python 3.11+  →  mise 未設定か失敗。050-mise.sh の出力を確認してください"
  MISSING_CMDS+=("python3.11+")
fi

# jq (JSON 操作に必要)
if ! command -v jq &>/dev/null; then
  echo "  → jq が未導入。静的バイナリをダウンロード中..."
  _install_jq() {
    _install_binary_direct "jq" \
      "https://github.com/jqlang/jq/releases/latest/download/jq-$(_detect_os)-$(_detect_arch jq)"
  }
  if _install_jq; then
    ok "jq (バイナリ自動インストール完了)"
  else
    fail "jq  →  brew install jq  /  apt install jq"
    MISSING_CMDS+=("jq")
  fi
  unset -f _install_jq
else
  ok "jq"
fi

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
      fail "venv 作成失敗  →  050-mise.sh で Python が正しく導入されているか確認してください"
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

unset py_candidate pkg KRAG_PKGS KRAG_MISSING_PKGS
