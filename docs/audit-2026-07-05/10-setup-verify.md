# 10. セットアップ統合検証（doctor / verify）の追加

種別: 不足機能 / 優先度: 中

## 現状

setup.sh は「導入」の成否は報告するが、**導入後にパイプライン全体が機能する状態か**を
検証する手段がない。今回の精査で見つかった不整合（agents 欠落、モデル未pull、
error-detector 未配備、フック二重登録）はいずれも「setup は成功と表示するが実際は動かない」
タイプであり、検証層があれば即座に検出できたもの。

## 対応プラン

1. `setup/900-verify.sh` を新設する（番号末尾 = 全モジュール実行後に走る）。
   チェック内容は**副作用ゼロ（読み取りのみ）**とする：

   | カテゴリ | チェック |
   |---|---|
   | コマンド | claude / codex / rtk / kizami / ollama / jq / gh の存在とバージョン |
   | Claude Code | バージョンが推奨（2.1.98）か、DISABLE_AUTOUPDATER 設定済みか |
   | Ollama | サーバー到達（`ollama_base_url` 経由）、スキル要求モデル全種の存在（`skills/*/SKILL.md` の OLLAMA_MODEL を grep して突合 → 02 の再発防止を兼ねる） |
   | Codex | companion path 解決可、`status` で ready、プラグイン一覧に codex@openai-codex |
   | エージェント | `agents/{melchior,balthasar,casper,metatron,sandalphon,leliel}.md` の存在 |
   | フック | settings.json の SessionStart/SessionEnd/UserPromptSubmit/PostToolUse に期待エントリが存在、二重登録なし、参照先スクリプトが存在し実行可能、`hooks/logs/` 存在 |
   | knowledge-rag | venv python 実行可、`~/.llm-tools-mcp/mcp.json` 存在、model ファイル存在 |
   | pCloud | rclone 設定済みか（未設定は warn 扱い。手動ステップのため fail にしない） |
   | キュー | pending/pcloud/ollama キューの滞留件数表示（多い場合は warn） |

2. 出力形式は setup.sh のサマリーと揃え、`✓ / ⚠(warn) / ✗(fail)` の3値にする。
   fail のみ exit 1。手動ステップ系（Codex ログイン・pCloud OAuth）は warn 固定。
3. 単独実行も可能にする: `bash setup.sh --verify` で 900 だけ実行できる分岐を setup.sh に追加
   （既存の「引数 = repo URL」との衝突を避けるため `--verify` を先に判定）。
4. TOOLS.md の各「導入確認」セクションから 900-verify への参照を張り、手動確認手順を段階的に集約する。

## 受け入れ基準

- [ ] `bash setup.sh --verify` が全チェックを1画面で報告する
- [ ] 今回の監査で見つかった不整合（01/02/04/05）を意図的に再現させると、verify がすべて検出する
- [ ] verify 自体は環境を一切変更しない

## 影響ファイル

- 新規: `setup/900-verify.sh`
- `setup.sh`（--verify 分岐）
- `TOOLS.md`（参照追記）
