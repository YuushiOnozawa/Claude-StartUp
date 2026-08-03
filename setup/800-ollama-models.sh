# setup/800-ollama-models.sh — MAGI 用 Ollama モデルの確認と案内
# Requires: ok, KRAG_BASE_DIR (set by 400-knowledge-rag-python.sh)
#
# Ollama は Windows ホスト側で動作する構成が標準のため、WSL2 側から pull しない。
# 未導入モデルは Windows 側で実行するコマンドを案内するに留め、setup は失敗させない
# （WSL2 側で解決できる依存ではないため MISSING_CMDS には積まない）。

[[ "${BASH_SOURCE[0]}" == "$0" ]] && { echo "ERROR: setup.sh から source してください" >&2; exit 1; }

echo ""
echo "--- ollama models ---"

_om_script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
_om_ollama_sh="$_om_script_dir/../hooks/lib/ollama.sh"
# shellcheck source=../hooks/lib/ollama.sh
[[ -f "$_om_ollama_sh" ]] || { echo "Error: ollama.sh not found: $_om_ollama_sh" >&2; exit 1; }
source "$_om_ollama_sh"
_om_base_url="$(ollama_base_url)"

# --- モデルリスト ---
# CASPER は Ollama を使わず Haiku を標準モデルとし（skills/casper/SKILL.md）、
# METATRON は Ollama を使わず Codex を標準モデルとする（skills/metatron/SKILL.md）ため、
# ローカルモデルの pull 対象に含めない。

# Fast/Hard 共用（7B、コード特化）
_om_shared=(
  "qwen2.5-coder:7b"   # MELCHIOR用
  "qwen3:4b-instruct"  # Normalizer用（DETECTION NOTES契約の構造化清書）
)

# Hard 専用（高品質・重め）
_om_hard=(
  "gemma4:e4b-it-qat"  # BALTHASAR用
  "granite3.3:8b"      # SANDALPHON用
  "lfm2.5:8b"          # LELIEL用 (構造化出力安定・低幻覚率) https://ollama.com/library/lfm2.5
  "qwen3:8b"           # generate-obsidian-index 等で使用
)

# knowledge-rag 蒸留用（OLLAMA_TIER=low: 3b のみ / high: 3b + 7b）
# OLLAMA_TIER=low  → デフォルト（現PC向け）
# OLLAMA_TIER=high → TargetPC: RTX 3070 / 8GB VRAM
if [[ "${OLLAMA_TIER:-low}" == "high" ]]; then
  _om_knowledge=(
    "qwen2.5:3b"   # ~1.9GB  軽量・高速用途
    "qwen2.5:7b"   # ~4.7GB  高品質知識蒸留（primary）
  )
else
  _om_knowledge=(
    "qwen2.5:3b"   # ~1.9GB  知識蒸留・軽量用途
  )
fi

_om_model_installed() {
  local model="$1"
  printf '%s\n' "$_om_models" | grep -Fxq -- "$model"
}

_om_check() {
  local model="$1"
  if _om_model_installed "$model"; then
    echo "  [SKIP] $model — 導入済み"
    return
  fi
  echo "  [MISS] $model — 未導入"
  echo "  → Windows 側で実行: ollama pull $model"
}

_om_ollama_up=0
_om_tags_json=""
_om_models=""
if _om_tags_json="$(curl -sf --max-time 5 "${_om_base_url}/api/tags" 2>/dev/null)"; then
  _om_ollama_up=1
  _om_models="$(printf '%s' "$_om_tags_json" | jq -r '.models[]?.name' 2>/dev/null || true)"
else
  echo "  ⚠  Windows ホスト側の Ollama に到達できません: $_om_base_url"
  echo "  ℹ  モデル確認をスキップします。Windows 側で Ollama が起動しているか確認してください。"
fi

if [[ "$_om_ollama_up" -eq 1 ]]; then
  echo "  === Fast/Hard 共用モデル ==="
  for _om_m in "${_om_shared[@]}"; do _om_check "$_om_m"; done

  echo "  === Hard 専用モデル ==="
  for _om_m in "${_om_hard[@]}"; do _om_check "$_om_m"; done

  echo "  === knowledge-rag 蒸留用モデル ==="
  for _om_m in "${_om_knowledge[@]}"; do _om_check "$_om_m"; done
fi

# primary model（リスト末尾）を knowledge-distill 用に保存
_om_primary="${_om_knowledge[-1]}"
mkdir -p "$KRAG_BASE_DIR"
echo "${_om_primary}" > "$KRAG_BASE_DIR/model"
ok "knowledge-rag primary model → ${_om_primary}"

ok "ollama models"

unset -f _om_model_installed _om_check
unset _om_shared _om_hard _om_knowledge _om_m _om_primary
unset _om_script_dir _om_ollama_sh _om_base_url _om_tags_json _om_models _om_ollama_up
