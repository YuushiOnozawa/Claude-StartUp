# setup/800-ollama-models.sh — MAGI / codegen 用 Ollama モデルのセットアップ
# Requires: ok, fail, MISSING_CMDS (append-only)

[[ "${BASH_SOURCE[0]}" == "$0" ]] && { echo "ERROR: setup.sh から source してください" >&2; exit 1; }

echo ""
echo "--- ollama models ---"

if ! command -v ollama &>/dev/null; then
  echo "  ℹ  ollama が見つかりません。モデルのダウンロードをスキップ。"
  return 0
fi

if ! ollama list &>/dev/null; then
  echo "  ℹ  ollama が起動していません。モデルのダウンロードをスキップ。"
  return 0
fi

# --- モデルリスト ---
# Fast/Hard 共用（7B、コード特化）
_om_shared=(
  "qwen2.5-coder:7b"   # MELCHIOR用
  "llama3.1:8b"        # CASPER用
)

# Hard 専用（高品質・重め）
_om_hard=(
  "phi4:latest"        # BALTHASAR用
  "deepseek-r1:8b"     # METATRON用
  "qwen3:8b"           # generate-obsidian-index 等で使用
  "lfm2.5:8b"          # SANDALPHON用 (構造化出力安定・低幻覚率) https://ollama.com/library/lfm2.5
)

# codegen スキル専用（Claude が計画・gemma4:12b が実装）
_om_codegen=(
  "gemma4:12b"
)

# 導入済み（スキップ）: qwen2.5:7b, qwen2.5:3b
# CASPER用: granite4:7b-a1b-h → llama3.1:8b に変更（Issue #137: granite4が指示追従不可）

_om_pull() {
  local model="$1"
  if ollama list 2>/dev/null | grep -qF "$model"; then
    echo "  [SKIP] $model — 導入済み"
    return
  fi
  echo "  [PULL] $model ..."
  if ollama pull "$model"; then
    echo "  [DONE] $model"
  else
    echo "  [ERROR] $model のダウンロードに失敗しました"
    return 1
  fi
}

echo "  === Fast/Hard 共用モデル ==="
for _om_m in "${_om_shared[@]}"; do _om_pull "$_om_m"; done

echo "  === Hard 専用モデル ==="
for _om_m in "${_om_hard[@]}"; do _om_pull "$_om_m"; done

echo "  === codegen スキル用モデル ==="
for _om_m in "${_om_codegen[@]}"; do _om_pull "$_om_m"; done

ok "ollama models"

unset -f _om_pull
unset _om_shared _om_hard _om_codegen _om_m
