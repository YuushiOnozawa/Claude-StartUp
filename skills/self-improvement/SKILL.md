name: self-improvement
desc: 学習・エラー・修正・機能要求を .learnings/ に構造化して蓄積し継続改善を実現する。Trigger: "/self-improvement", "self-improvement", "学習を記録", "エラーを記録", "これを残して", "修正パターンを記録"
argument-hint: "<エントリタイプ: LRN|ERR|FEAT> または <自由記述>"

# Self-Improvement スキル

学習・エラー・修正・機能要求を `.learnings/` マークダウンファイルに記録し、継続的改善を実現する。

`self-healing` との関係: self-healing は実行中の失敗をリアルタイムで修復・検証・記録するスキル。このスキル（self-improvement）は事後の蓄積・昇格レイヤー。両者を併用することで内側ループ（検出→修復）と外側ループ（蓄積→昇格）が成立する。

## エントリ種別

| 種別 | ID 形式 | 用途 |
|------|---------|------|
| Learning | `LRN-YYYYMMDD-XXX` | 修正・知識ギャップ・ベストプラクティス |
| Error | `ERR-YYYYMMDD-XXX` | コマンド失敗・API エラー |
| Feature Request | `FEAT-YYYYMMDD-XXX` | 欠けている機能・能力 |

## エントリフォーマット

```markdown
### LRN-20240115-001
**Summary:** [1行で何を学んだか]
**Details:** [詳細。何が起きたか・なぜ間違えたか]
**Suggested Action:** [次回どうするか / 昇格先（CLAUDE.md 等）]

**Source:** [タスク名 or ファイル名]
**Related Files:** [関連ファイル（任意）]
**Tags:** [タグ（任意）]
**Pattern-Key:** [パターンを一言で（例: git-rebase-conflict）]
**Recurrence-Count:** 1
**Status:** pending
```

## ファイル構成

```
.learnings/
  LEARNINGS.md      # LRN エントリ
  ERRORS.md         # ERR エントリ
  FEATURE_REQUESTS.md  # FEAT エントリ
  HEALS.md          # self-healing からの HEAL エントリ
```

## 昇格ルール

以下をすべて満たすパターンは CLAUDE.md / settings.json への永続化を検討する:
- Recurrence-Count >= 3
- 2つ以上の異なるタスクで発生
- 30日以内

昇格後は Status を `promoted` に更新する。

## 手順

1. エントリ種別を判定（LRN / ERR / FEAT）
2. 該当ファイルを Read して既存の Pattern-Key を確認
3. 同じ Pattern-Key があれば Recurrence-Count をインクリメント
4. なければ新規エントリを追記
5. 昇格条件を満たすパターンがあればユーザーに通知

## Hook 連携

`PostToolUse (Bash)` フックで `error-detector.sh` が失敗を自動検出し、ERR エントリ作成を促す `additionalContext` を出力する。

## デプロイ

PR マージ後、スクリプトを `~/.claude/hooks/` にコピーする:

```bash
cp hooks/error-detector.sh ~/.claude/hooks/
chmod +x ~/.claude/hooks/error-detector.sh
```

`settings.json` の PostToolUse hook は `~/.claude/hooks/error-detector.sh` を参照する。
