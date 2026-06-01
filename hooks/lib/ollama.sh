# Ollama model resolution helper
# Source this file, then call: ollama_best_model [model_file_path]
#
# Priority:
#   1. KRAG_DISTILL_MODEL env var
#   2. model file (~/.local/share/knowledge-rag/model)
#   3. dynamic: largest model from `ollama list`
#   4. hardcoded fallback: qwen2.5:7b

ollama_best_model() {
  local model_file="${1:-$HOME/.local/share/knowledge-rag/model}"

  # 1. env var
  if [[ -n "${KRAG_DISTILL_MODEL:-}" ]]; then
    echo "$KRAG_DISTILL_MODEL"
    return 0
  fi

  # 2. model file
  if grep -q . "$model_file" 2>/dev/null; then
    grep . "$model_file"
    return 0
  fi

  # 3. dynamic: pick the model with the largest size from `ollama list`
  # Output format: NAME  ID  SIZE  UNIT  ...
  local best
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

  # 4. hardcoded fallback
  echo "qwen2.5:7b"
}
