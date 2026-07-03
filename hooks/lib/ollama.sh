# Ollama model resolution helper
# Source this file, then call: ollama_best_model [model_file_path]
#
# Priority:
#   1. KRAG_DISTILL_MODEL env var
#   2. model file (~/.local/share/knowledge-rag/model)
#   3. dynamic: largest model from `ollama list`
#   4. hardcoded fallback: qwen2.5:7b

# WSL2 NATモード: Windows ホスト IP をデフォルトゲートウェイから取得
# ip -4 で IPv4 限定、IP 形式チェック付き
_ollama_win_host() {
  ip -4 route show default 2>/dev/null \
    | awk 'NR==1 && $3 ~ /^[0-9.]+$/ { print $3 }'
}

# Ollama ベース URL 解決（OLLAMA_BASE_URL 最優先、プロセス内キャッシュ付き）
# 優先順位:
#   1. OLLAMA_BASE_URL 環境変数（例: http://172.17.96.1:11434）
#   2. WSL2 NAT モード: デフォルトゲートウェイ IP を自動検出
#   3. フォールバック: http://localhost:11434
_OLLAMA_BASE_URL_CACHE=""
ollama_base_url() {
  if [[ -n "${_OLLAMA_BASE_URL_CACHE:-}" ]]; then
    echo "$_OLLAMA_BASE_URL_CACHE"
    return 0
  fi
  if [[ -n "${OLLAMA_BASE_URL:-}" ]]; then
    _OLLAMA_BASE_URL_CACHE="$OLLAMA_BASE_URL"
  elif grep -qi microsoft /proc/sys/kernel/osrelease 2>/dev/null; then
    local win_ip
    win_ip=$(_ollama_win_host)
    _OLLAMA_BASE_URL_CACHE="http://${win_ip:-localhost}:11434"
  else
    _OLLAMA_BASE_URL_CACHE="http://localhost:11434"
  fi
  echo "$_OLLAMA_BASE_URL_CACHE"
}

ollama_best_model() {
  local model_file="${1:-$HOME/.local/share/knowledge-rag/model}"

  # 1. env var
  if [[ -n "${KRAG_DISTILL_MODEL:-}" ]]; then
    echo "$KRAG_DISTILL_MODEL"
    return 0
  fi

  # 2. model file
  if [[ -f "$model_file" ]]; then
    local model_name
    model_name=$(head -n 1 "$model_file" | xargs 2>/dev/null)
    if [[ -n "$model_name" ]]; then
      echo "$model_name"
      return 0
    fi
  fi

  # 3. dynamic: REST API（ollama CLI 不在時のフォールバック含む）
  local base_url best
  base_url=$(ollama_base_url)
  if command -v jq >/dev/null 2>&1; then
    best=$(curl -sf --max-time 5 "${base_url}/api/tags" 2>/dev/null \
      | jq -r '.models[]? | "\(.size) \(.name)"' \
      | sort -rn | head -1 | awk '{print $2}')
    if [[ -n "$best" ]]; then
      echo "$best"
      return 0
    fi
  fi
  if command -v ollama >/dev/null 2>&1; then
    best=$(ollama list 2>/dev/null \
      | tail -n +2 \
      | awk 'NF>=4 {
          val = $3 + 0
          if ($4 == "GB") val *= 1024
          if (val > max) { max = val; model = $1 }
        }
        END { if (model) print model }')
    if [[ -n "$best" ]]; then
      echo "$best"
      return 0
    fi
  fi

  # 4. hardcoded fallback
  echo "qwen2.5:7b"
}

# Ollama 起動確認（REST API 応答チェック）
# 戻り値: 0 = 起動中、1 = 未起動
ollama_is_up() {
  curl -sf --max-time 3 "$(ollama_base_url)/api/tags" >/dev/null 2>&1
}
