# 12. セットアップ後の手動ステップ・チェックリスト整備

種別: 不足機能（ドキュメント）/ 優先度: 中

## 現状

ワンライナーで自動化できない手動ステップが複数あるが、README には pCloud 以外まとまっておらず、
一部は TOOLS.md やスクリプト内コメントにしか書かれていない：

| 手動ステップ | 現在の記載場所 | 問題 |
|---|---|---|
| Claude Code インストール + 認証 | README（記載あり） | ✅ 問題なし |
| Codex CLI の ChatGPT ログイン | どこにもない（セッションまとめのみ） | ❌ 新規環境で codegen が黙って Haiku 落ちする |
| pCloud OAuth（rclone config） | TOOLS.md + docs/pcloud-rclone-setup.md | ⚠ README から導線なし。未設定だと蒸留がキュー滞留し続ける |
| pCloud マウントの常駐化（systemd） | knowledge-distill.sh コメントに「systemd サービスの責務」とあるのみ | ❌ サービス定義例がリポジトリにない |
| `ollama serve` の事前起動 | TOOLS.md | 09 実施後は不要になる予定 |
| `OLLAMA_TIER=high` の意味 | setup/800 のコメントのみ | ❌ ユーザーが選べる知識になっていない |
| `SKIP_OLLAMA_MODEL=1` | TOOLS.md | ⚠ knowledge-rag 用のみ。命名も含め 09 で整理 |
| Claude Code v2.1.98 固定の判断 | README + DESIGN.md | ✅ 問題なし |

## 対応プラン

1. README に「セットアップ後チェックリスト」セクションを追加する。形式は
   コピペ可能なチェックボックス + 各1行コマンド：

   ```markdown
   ## セットアップ後の手動ステップ
   - [ ] Codex ログイン: `codex` を起動し ChatGPT アカウントで認証 → `codex --version`
   - [ ] pCloud OAuth: `rclone config`（詳細: docs/pcloud-rclone-setup.md）
   - [ ] pCloud マウント常駐化: docs/pcloud-rclone-setup.md の systemd ユニット参照
   - [ ] 検証: `bash setup.sh --verify`（→ 10 実装後）
   ```

2. 環境変数一覧を README（またはTOOLS.md）に表として集約する：
   `OLLAMA_TIER`, `SKIP_OLLAMA_MODEL(S)`, `CLAUDE_AUTOCOMPACT_PCT_OVERRIDE`,
   `CLAUDE_CODE_DISABLE_ADAPTIVE_THINKING`, `DISABLE_AUTOUPDATER`, `KRAG_DISTILL_RETRY`（内部用と注記）。
3. pCloud マウント用の systemd user unit のサンプルを `templates/systemd/pcloud-mount.service` として
   追加し、docs/pcloud-rclone-setup.md から参照する（knowledge-distill が前提とする
   「マウント管理は systemd の責務」を実体化する）。
4. setup.sh のサマリー出力末尾に「手動ステップが残っています → README の該当セクション」を
   固定表示し、ドキュメントへの導線をスクリプト側にも持たせる。

## 受け入れ基準

- [ ] README だけ読めば、ワンライナー実行 → 手動ステップ → verify まで一本道で完了できる
- [ ] すべての環境変数が1箇所の表から引ける
- [ ] pCloud 常駐化がテンプレートのコピーで完了する

## 影響ファイル

- `README.md`, `TOOLS.md`, `docs/pcloud-rclone-setup.md`
- 新規: `templates/systemd/pcloud-mount.service`
- `setup.sh`(サマリー文言)
