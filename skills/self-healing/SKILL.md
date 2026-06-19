name: self-healing
desc: 実行中の失敗をリアルタイムで修復する。コマンド・テスト・ビルド・lint が失敗したとき、依存関係やランタイムのエラー、不足ツール・スクリプト、外部 API エラーなどで使う。Trigger: "/self-healing", "self-healing", "エラーを修復", "失敗を直して", "heal"
argument-hint: "<失敗したコマンドまたはエラー内容>"

# Self-Healing スキル

実行中の失敗に対して「診断→パッチ→検証→記録」のループを実行し、再利用可能な検証済みアーティファクトを残す。

`self-improvement` との関係:
- **self-healing（このスキル）**: 実行中・ライブな失敗を修復。VERIFY 必須。`.learnings/HEALS.md` に記録
- **self-improvement**: 事後の蓄積・昇格レイヤー。VERIFY 不要。`.learnings/ERRORS.md` 等に記録

**境界ルール**: 事実・修正・要望を蓄積するなら `self-improvement`。ライブな失敗を修復・検証するなら `self-healing`。

## 使用タイミング

以下のいずれかが発生したとき:
- コマンド・テスト・ビルド・lint が非ゼロで終了
- 不足ツール、依存関係ミスマッチ、ランタイムバージョンエラー
- 権限エラー、ポート競合、汚れた git 状態
- 必要なヘルパーや one-off スクリプトが存在しない
- 外部 API / MCP がエラーまたはレート制限
- テストがフレイキー

## Heal Loop

### PHASE 1: DIAGNOSE

1. 失敗したコマンド・出力・終了コードをキャプチャする
2. `.learnings/HEALS.md` を Pattern-Key で検索する
   - 同じパターンが見つかった場合 → Recurrence-Count をインクリメントして PHASE 2 へ
   - 見つからない場合 → 新規 HEAL として PHASE 2 へ
3. 根本原因を特定する（症状ではなく原因を見る）

### PHASE 2: PATCH

1. 修正を書く（コード変更・設定修正・コマンド変更・スクリプト作成等）
2. 再利用可能なアーティファクト（スクリプト・設定等）は `.learnings/heals/<HEAL-ID>/` に保存（lazy: 再発時に価値があると判断した場合のみ）
3. 3回試みて解決できない場合は `abandoned` としてマークし、ユーザーにエスカレーション

### PHASE 3: VERIFY（必須・省略禁止）

**「検証なしで記録しない」** — これが self-healing の核心ルール。

1. 修正を適用する
2. **失敗した操作をそのまま再実行する**
3. 成功を確認する（出力・終了コード 0 を確認）
4. サンドボックス等で再実行が不可能な場合のみ `pending-verify` とする

### PHASE 4: FILE

`.learnings/HEALS.md` に以下の形式でエントリを追記する:

```markdown
### HEAL-YYYYMMDD-XXX
**Pattern-Key:** [パターンを一言で（例: npm-missing-dep）]
**Symptom:** [失敗したコマンドと出力の要約]
**Root-Cause:** [診断した根本原因]
**Fix:** [適用した修正の概要]
**Verify:** [再実行した証拠（コマンドと出力の要約）]
**Artifacts:** [.learnings/heals/<HEAL-ID>/ のファイル一覧、なければ None]
**Recurrence-Count:** 1
**Status:** verified | pending-verify | abandoned
```

## 同じパターンの再発（Recurrence-Count >= 3）

- `self-improvement` スキルに Handoff する
- 昇格先候補: CLAUDE.md ルール追加、settings.json 設定変更、専用スクリプト作成

## ファイル構成

```
.learnings/
  HEALS.md                    # HEAL エントリ一覧
  heals/
    HEAL-20240115-001/        # アーティファクト（lazy）
      fix.sh
      README.md
```
