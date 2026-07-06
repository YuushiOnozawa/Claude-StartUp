# Specification Draft: Core 05

## 仕様候補

- 本番同期を git pull 基本にするか setup再実行も含めるか
- /finished-pr に本番pull提案やworktree清掃を含めるか
- .gitignore 対象の整理
- 本番だけの実験を置ける場所・命名

## 境界条件

- この仕様候補は、分類成果物の「仕様化の観点」から起こした論点であり、まだ確定仕様ではない。
- 関連Fable項目 07, 15 のうち、他の核問題にも現れる項目は重複として扱う。
- 実装確認メモに基づく現状は次の通り。

- 開発リポジトリは main の 99166b8 (#265)
- 開発リポジトリには .codex/、session summary、CLAUDE.local.md、audit、index-investigations.sh が未追跡
- 本番 ~/.claude は HEAD e1dc01f で dirty 多数
- 本番では agents削除、settings変更、hooks/skills/scripts未追跡が混在
- 約100PR遅れはFable項目15の監査結果を根拠とする

## fail / warn / info の判定が必要なもの

- 目的達成に必須で、欠けると主要機能が動かないものは fail 候補。
- 手動認証、環境差、任意機能、段階導入対象は warn / info 候補。
- 具体的な判定境界は requirements.md の人間確認事項を解消してから決める。

## 未確定事項

- 本番差分をmain反映済み、未マージ実験、ローカル状態に分類すること
- 追跡ファイルの本番直編集を禁止するか
- セッションまとめや調査スクリプトを削除/追跡するか