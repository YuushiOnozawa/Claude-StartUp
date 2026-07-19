# Test Plan: Core 03.2 — hooks / knowledge-distill / 知識ストアの二重化・欠落・密結合

> ステータス: 実行済み（2026-07-19、全 57 件 PASS）
> 対応 specification: approved（2026-07-08 SPEC-03.2-05 追補）

## テスト資産

既存の自動テストスクリプトで SPEC-03.2-01〜05 をカバーする。新規スクリプトは不要（流用）。

| スクリプト | 対象 SPEC | 件数 |
|---|---|---|
| `scripts/test-setup-hooks-registration.sh` | SPEC-03.2-01, SPEC-03.2-02, SPEC-03.2-04 | 32 |
| `scripts/test-knowledge-distill-local.sh` | SPEC-03.2-03 | 13 |
| `scripts/test-lessons-learned-local.sh` | SPEC-03.2-05 | 12 |

## SPEC → TEST 対応

### TEST-03.2-01（SPEC-03.2-01: SessionEnd→SessionStart 移行）

区分: 自動テスト（`test-setup-hooks-registration.sh`）

- 正常系: 410 実行後に SessionStart へ正規コマンドを 1 件登録／SessionEnd の knowledge-distill を除去／session-end-queue を SessionEnd に 1 件登録
- 異常系: settings.json 不存在でも初期化から登録まで完走／dangling symlink を置換しない／非文字列 command を変更しない
- 境界条件: 2 回実行しても同一（冪等性）／重複登録の収束／無関係な hook・matcher を保持

結果: 該当 9 ケース PASS（2026-07-19 実行）

### TEST-03.2-02（SPEC-03.2-02: ログパス統一）

区分: 自動テスト（`test-setup-hooks-registration.sh`）

- 正常系: 410 実行後に `hooks/logs/` を作成／古いログパスを正規コマンドへ置換

結果: 該当 2 ケース PASS（2026-07-19 実行）

### TEST-03.2-03（SPEC-03.2-03: 記録層/配送層分離）

区分: 自動テスト（`test-knowledge-distill-local.sh`）+ 未テスト項目あり

- 正常系: SessionEnd 相当入力で raw と Ollama キューを生成／pCloud ディレクトリ・pCloud キューを生成しない／Ollama 起動中の drain で retry raw を生成
- 異常系: transcript_path なし・空会話 transcript を exit 0 でスキップ
- 境界条件: Ollama 停止中は pending/ollama キューを drain しない（4 回連続実行でも dead-letter に移動しない）／pCloud キューを Ollama 停止中でも pending へ移行／hook 本体に pCloud drain・mountpoint 確認を含めない

結果: 該当 13 ケース PASS（2026-07-19 実行）

**未テスト（理由）**:
- knowledge-rag 登録が pCloud mount に依存せず完走すること（REQ-03.2-03 受け入れ条件） — [#326](https://github.com/YuushiOnozawa/Claude-StartUp/issues/326) の documents_dir 再設計待ちのため blocked。design-review.md の HIGH 指摘と対応
- `knowledge-auto-promote.sh` の LOCAL_STAGING_DIR パスでの動作確認（手動） — #326 に含めて判断（自動昇格の「完走」定義が未確定のため）
- `scripts/pcloud-sync.sh` による実転送 — core-01 の実装・テスト範囲（本 core 対象外）

### TEST-03.2-04（SPEC-03.2-04: error-detector.sh リポジトリ追加・配備）

区分: 自動テスト（`test-setup-hooks-registration.sh`）

- 正常系: 413 実行後に PostToolUse へ正規コマンドで 1 件登録／error-detector.sh を配置し実行権限を付与
- 異常系: コピー元不在時は fail と MISSING_CMDS を出して登録しない
- 境界条件: 旧形式登録を正規コマンドへ置換／重複登録の収束／2 回実行しても同一／dangling symlink を置換しない／410→411→412→413 の統合登録が同一 fixture で成立

結果: 該当 8 ケース PASS（2026-07-19 実行）

**未テスト（理由）**: `error-detector.sh` 自体の検知ロジック（Bash コマンドエラー検出→ERRORS.md 記録促し）は SPEC-03.2-04 のスコープ外（既存スクリプトの原本コピーのみが本 SPEC の対象。検知ロジック自体は本 core での変更なし）

### TEST-03.2-05（SPEC-03.2-05: lessons-learned ローカル化）

区分: 自動テスト（`test-lessons-learned-local.sh`）

- 正常系: ローカル lessons-learned 出力ディレクトリを作成
- 異常系: pCloud 未マウントでも exit 0 かつ pcloud キューを生成しない／Ollama 停止時は ollama reason でキューし exit 0／transcript_path なし・空会話 transcript を exit 0 でスキップ
- 境界条件: pCloud パスへ書き込まない／KRAG_LL_RETRY=1 時はキュー drain をスキップ／Ollama 停止時はキューを drain しない／hook 本体に mountpoint 確認・pcloud reason の queue_push を含めない

結果: 該当 12 ケース PASS（2026-07-19 実行）

**未テスト（理由）**: 手動保存ファイル（CLAUDE.md 経由）の knowledge-rag 登録 — 仕様上「登録経路なし」と確定済み（SPEC-03.2-05 注記、2026-07-19）のためテスト対象外（not applicable）

## 実行結果サマリー（2026-07-19）

```
test-setup-hooks-registration.sh : 32 PASS / 0 FAIL / 0 SKIP
test-knowledge-distill-local.sh  : 13 PASS / 0 FAIL / 0 SKIP
test-lessons-learned-local.sh    : 12 PASS / 0 FAIL / 0 SKIP
合計                              : 57 PASS / 0 FAIL / 0 SKIP
```

各スクリプトは shellcheck -S error・bash -n の静的チェックも含む（fixture HOME 方式）。

## 未テスト仕様（手動確認が必要な残項目）

| 項目 | 対応 | 状態 |
|---|---|---|
| knowledge-rag 登録の mount 非依存（REQ-03.2-03 受け入れ条件） | [#326](https://github.com/YuushiOnozawa/Claude-StartUp/issues/326) | blocked（別トラック） |
| `knowledge-auto-promote.sh` の「完走」定義・動作確認 | #326 に含める | blocked（別トラック） |
| rclone 未起動環境での smoke test（生 Ollama 経由の end-to-end） | Step 9 audit で必要性を再確認 | 未実施（自動テストの Ollama モックで代替済み） |
| 既存 pcloud キューアイテムの移行確認（本番環境） | 運用時の一度きりの確認 | 未実施（テストで移行ロジック自体は検証済み） |

## CI 候補

- 上記 3 スクリプトを CI（GitHub Actions）に組み込む提案は #315（setup モジュール一括ハードニング）と合わせて別途検討する
