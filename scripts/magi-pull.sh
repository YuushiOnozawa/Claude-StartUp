#!/usr/bin/env bash
# MAGI / codegen スキル用 Ollama モデル一括ダウンロード
# 用途: ローカルLLMレビュー系スキル（Magi-fast / Magi-hard）および codegen スキルで使用するモデルを一括取得する
set -uo pipefail

# --- モデルリスト ---
# Fast/Hard 共用（7B、コード特化）
MODELS_SHARED=(
  "qwen2.5-coder:7b"
  "llama3.1:8b"
)

# Hard 専用（高品質・重め）
MODELS_HARD=(
  "phi4:latest"
  "deepseek-r1:8b"
  "qwen3:8b"
)

# codegen スキル専用（Claude が計画・gemma4:12b が実装）
MODELS_CODEGEN=(
  "gemma4:12b"
)

# 導入済み（スキップ）: qwen2.5:7b, qwen2.5:3b
# CASPER用: granite4:7b-a1b-h → llama3.1:8b に変更（Issue #137: granite4が指示追従不可）

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
  if ollama pull "$model"; then
    echo "[DONE] $model"
  else
    echo "[ERROR] $model のダウンロードに失敗しました"
    return 1
  fi
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
fi

if [[ "$SKIP_HARD" -eq 0 ]]; then
  echo ""
  echo "=== codegen スキル用モデル ==="
  for m in "${MODELS_CODEGEN[@]}"; do
    pull_model "$m"
  done
fi

echo ""
echo "=== インストール済みモデル一覧 ==="
ollama list
