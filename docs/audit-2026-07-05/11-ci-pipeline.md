# 11. CI パイプラインの追加（shellcheck / 構文 / 既存テスト / 整合性突合）

種別: 不足機能 / 優先度: 中

## 現状

- `scripts/test-magi-diff-filter.sh`, `test-magi-format.sh`, `test-function-calling.sh` と
  テスト資産はあるが、実行は手動任せ。
- AGENTS.md は「シェル変更時は `bash -n`」を求めているが、強制する仕組みがない。
- `templates/security/github-workflows/security-scan.yml` は**他プロジェクトへ配布する**テンプレートで、
  このリポジトリ自身の CI は存在しない（`.github/` なし）。
- シェルスクリプト約30本 + jq 埋め込み + スキル間のモデル名整合という「壊れやすいが検出は機械化できる」
  性質のリポジトリなので、CI の費用対効果が高い。

## 対応プラン

1. `.github/workflows/ci.yml` を新設。PR と main push で実行：

   ```yaml
   jobs:
     lint:
       - bash -n を setup.sh, setup/*.sh, hooks/**/*.sh, scripts/*.sh に一括実行
       - shellcheck（severity=warning 以上。既存コードの指摘が多い場合は
         初回は --severity=error で導入し、段階的に厳格化）
       - jq のドライラン: setup/4xx が使う jq フィルタの構文チェック
     test:
       - scripts/test-magi-diff-filter.sh
       - scripts/test-magi-format.sh
       （test-function-calling.sh は Ollama 必須のため CI 対象外とし、900-verify 側に残す）
     consistency:
       - スキル OLLAMA_MODEL ↔ setup/800 モデルリストの突合（02 の再発防止）
       - settings.json が参照する hooks/*.sh がリポジトリに存在するか（05 の再発防止）
       - SKILL.md 内の 'bash scripts/' 相対参照・バージョン固定パスの grep 禁止（06 の再発防止）
   ```

2. consistency チェックは `scripts/check-consistency.sh` として切り出し、ローカルでも
   `/magi-fast` 前に実行できるようにする（CASPER のルール遵守観点と役割が重なるが、
   機械化できる検査を LLM ルールで重複させない AGENTS.md 方針に合致）。
3. gitleaks をこのリポジトリ自身にも適用する（templates に既にある `.gitleaks.toml` を流用）。
   フックスクリプトが transcript や設定を扱うため、誤コミット検出の価値が高い。
4. セルフセットアップの smoke test（任意・後回し可）: ubuntu ランナーで
   `bash setup.sh`（repo URL なし・Ollama/pCloud なし）を流し、exit code と
   「想定 fail のみか」を確認するジョブ。ネットワーク依存が強いので nightly か手動トリガーにする。

## 受け入れ基準

- [ ] PR 作成で lint / test / consistency が自動実行される
- [ ] 02/05/06 型の不整合を含む PR が CI で fail する
- [ ] main が常にグリーン

## 影響ファイル

- 新規: `.github/workflows/ci.yml`, `scripts/check-consistency.sh`
- 既存テストスクリプト（CI から呼ぶだけ、変更最小）
