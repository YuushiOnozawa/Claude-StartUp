# 08. Codex CLI の自動インストール（現状は確認のみ）

種別: 不足機能 / 優先度: 高

## 現状

`setup/850-codex.sh` は：

- Codex CLI: `command -v codex` の**確認のみ**。未導入なら fail 表示 + MISSING_CMDS 追加で終わり。
- Codex プラグイン: marketplace 追加 + `claude plugin install` まで自動化済み。

他モジュール（RTK / mise / Ollama / kizami / lean-ctx / gitleaks）はすべて自動インストールを試みる
設計なのに、**「実装は Codex が行う」という本リポジトリの中核依存だけが手動**になっている。
新規環境でワンライナーを流すと、codegen / MAGI 監査 / 設計レビューがすべて Haiku・BALTHASAR
フォールバックに落ちた状態で立ち上がる。

## 対応プラン

1. `setup/850-codex.sh` に自動インストールを追加（既存の check_package ヘルパーが使える）：

   ```bash
   check_package "codex CLI" npm "@openai/codex"
   ```

   npm 不在時は 100-core / 050-mise の失敗として既にハンドルされるため、npm ガードのみ追加する。
2. インストール後の認証（ChatGPT ログイン）は対話式で自動化不可。pCloud OAuth と同様に
   「初回のみ手動」であることを fail ではなく **info 扱い**で明示する：
   - `codex login status`（または `codex --version` 後の status 相当）で未認証を検出したら
     「⚠ 手動ステップ: `codex` を起動してログインしてください」と表示。MISSING_CMDS には積まない
     （積むと setup 全体が exit 1 になり、他の導入結果の見通しが悪くなるため）。
   - 手動ステップ一覧（[12-manual-steps-checklist.md](12-manual-steps-checklist.md)）に記載。
3. プラグインインストールの成否確認を強化: 現状 `claude plugin install ... &>/dev/null` で
   出力を捨てているため、失敗時に原因が追えない。失敗時のみ出力をログへ残す
   （setup.sh 全体が tee でログを取っている構造を活かし、`&>/dev/null` をやめて通常出力にする）。
4. バージョン方針の明文化: Claude Code 本体は v2.1.98 固定を README で案内している。
   Codex CLI / プラグインについても「動作確認済みバージョン」を README または DESIGN.md に記録する
   （spec-template のパス問題（06）と同根の、プラグイン更新破壊への備え）。

## 受け入れ基準

- [ ] codex 未導入の新規環境で setup 実行 → `codex --version` が通る状態になる
- [ ] 未認証時に setup が失敗せず、手動ログイン手順が明示される
- [ ] プラグインインストール失敗時にログから原因が特定できる

## 影響ファイル

- `setup/850-codex.sh`
- `README.md`（手動ステップ記載 → 12 と連動）
