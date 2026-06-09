#!/usr/bin/env bash
# MAGI システム用 Ollama モデル一括ダウンロード
# 用途: ローカルLLMレビュー系スキル（Magi-fast / Magi-hard）で使用するモデルを一括取得する
set -uo pipefail

# --- モデルリスト ---
# Fast/Hard 共用（7B、コード特化）
MODELS_SHARED=(
  "qwen2.5-coder:7b"
  "granite4:7b-a1b-h"
)

# Hard 専用（高品質・重め）
MODELS_HARD=(
  "gemma4:12b"
  "deepseek-r1:8b"
)

# 導入済み（スキップ）: qwen2.5:7b, qwen2.5:3b

# --- オプション ---
SKIP_HARD=0
if [[ "${1:-}" == "--fast-only" ]]; then
  SKIP_HARD=1
  echo "[magi-pull] Fast 用モデルのみダウンロードします"
fi

# --- Ollama 起動確認 ---
if ! ollama list &>/dev/null; then
  echo "[ERROR] Ollama が起動していません。先に 'ollama serve' を実行してください。"
  exit 1
fi

# --- ダウンロード ---
pull_model() {
  local model="$1"
  if ollama list 2>/dev/null | grep -qF "$model"; then
    echo "[SKIP] $model — 導入済み"
    return
  fi
  echo "[PULL] $model ..."
  ollama pull "$model"
  echo "[DONE] $model"
}

echo "=== Magi Fast/Hard 共用モデル ==="
for m in "${MODELS_SHARED[@]}"; do
  pull_model "$m"
done

if [[ "$SKIP_HARD" -eq 0 ]]; then
  echo ""
  echo "=== Magi Hard 専用モデル ==="
  for m in "${MODELS_HARD[@]}"; do
    pull_model "$m"
  done
  echo ""
  echo "NOTE: gemma4:12b が OOM する場合は gemma3:12b に差し替えてください"
  echo "      ollama pull gemma3:12b"
fi

echo ""
echo "=== インストール済みモデル一覧 ==="
ollama list
