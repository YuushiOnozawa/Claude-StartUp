# 05. error-detector.sh が配備されず自動エラー検知が無音で無効

種別: 修正対応 / 深刻度: 中

## 現状

`settings.json` の PostToolUse フック（Bash matcher）：

```json
"command": "[ -f ~/.claude/hooks/error-detector.sh ] && bash ~/.claude/hooks/error-detector.sh || true"
```

しかし実体は `skills/self-improvement/scripts/error-detector.sh` にあり、
`~/.claude/hooks/` に配置する処理がどの setup モジュールにも存在しない
（`700-claude-md-lifecycle.sh` は `hooks/*.sh` と `hooks/lib/*.sh` のみコピー対象）。

`[ -f ... ] || true` のガードにより、**エラーにならず単に何もしない**ため、
self-improvement スキルの外側ループ（ERR 自動蓄積）が新規環境で一度も動かないまま気づけない。

**本番環境の実測**: 本番 `~/.claude/hooks/error-detector.sh` は存在する（内容は
`skills/self-improvement/scripts/error-detector.sh` と diff で同一確認済み）。ただし git 未追跡 =
**手動コピーで配備されたもの**。現行マシンでは動いているが、リポジトリにも setup にも配備経路が
ないため、ワンライナー展開した新規環境では確実に欠落する。案A（hooks/ へ移動）を採れば
本番の untracked ファイルはそのまま追跡ファイルに置き換わる。

## 対応プラン

以下のどちらかに決めて実施する。推奨は案A。

### 案A（推奨）: hooks/ に実体を移動

1. `skills/self-improvement/scripts/error-detector.sh` を `hooks/error-detector.sh` へ移動する
   （700 の「hooks/ 配下の全 .sh を自動配置」規約に乗せる。リポジトリ = ~/.claude なら移動だけで解決）。
2. `skills/self-improvement/SKILL.md` 内の参照パスを更新する。
3. settings.json のガード `[ -f ... ]` は残してよい（他マシンでの部分導入を許容）が、
   10-setup-verify.md の verify で「存在しない場合は警告」を出す。

### 案B: setup モジュールでコピー

- `setup/700-claude-md-lifecycle.sh`（または self-improvement 用の新モジュール）に
  `skills/self-improvement/scripts/error-detector.sh → ~/.claude/hooks/` のコピーを追加する。
- スキルディレクトリと hooks の二重管理になるため非推奨。

## 検証時の注意

- PostToolUse は Bash 実行ごとに毎回起動する。error-detector.sh の実行コストを確認し、
  重い場合（例: 毎回 jq で transcript を舐める等）は早期 return の入口ガードを付けること。
  トークン削減目的のリポジトリでフックがレイテンシ源になるのは本末転倒のため。

## 受け入れ基準

- [ ] 新規環境 setup 後、`~/.claude/hooks/error-detector.sh` が存在し実行可能
- [ ] Bash コマンド失敗時に `.learnings/ERRORS.md`（または設計上の出力先）へエントリが記録される
- [ ] フック実行時間が体感に影響しない（目安 <100ms、超える場合は入口ガード追加）

## 影響ファイル

- `skills/self-improvement/scripts/error-detector.sh`（移動）
- `skills/self-improvement/SKILL.md`（参照更新）
- `settings.json`（必要なら）
