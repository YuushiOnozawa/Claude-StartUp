# Traceability Map: Core 05

## 重複・横断関係

Fable 07 は core-06 と重複する。

## 対応表

| Fable項目 | 問題 | 要求候補 | 仕様候補 | 実装項目候補 | テスト観点 | 状態 |
|---|---|---|---|---|---|---|
| 07 | リポジトリ衛生。本番 ~/.claude が未コミット直編集を多く含み、開発リポジトリと正が分裂している。リポジトリが再現可能なセットアップの正であるという前提を弱めている。 | 本番反映の正規手順を定義する<br>本番追跡ファイルの直編集ルールを定義する<br>マシン固有設定、個人メモ、実験、正式実装を区別する<br>worktree完了時の清掃を開発フローに含める | 本番同期を git pull 基本にするか setup再実行も含めるか<br>/finished-pr に本番pull提案やworktree清掃を含めるか<br>.gitignore 対象の整理<br>本番だけの実験を置ける場所・命名 | 開発リポジトリは main の 99166b8 (#265)<br>開発リポジトリには .codex/、session summary、CLAUDE.local.md、audit、index-investigations.sh が未追跡<br>本番 ~/.claude は HEAD e1dc01f で dirty 多数<br>本番では agents削除、settings変更、hooks/skills/scripts未追跡が混在<br>約100PR遅れはFable項目15の監査結果を根拠とする | 本番 ~/.claude のgit statusが説明可能な差分だけになるか<br>本番HEADがorigin/mainと一致するか<br>マージ後の本番反映手順が辿れるか<br>worktree完了後に残骸が残らないか | 未確定 / 要整理 |
| 15 | 本番 ~/.claude クローンの git 状態正常化とデプロイフロー定義。本番 ~/.claude が未コミット直編集を多く含み、開発リポジトリと正が分裂している。リポジトリが再現可能なセットアップの正であるという前提を弱めている。 | 本番反映の正規手順を定義する<br>本番追跡ファイルの直編集ルールを定義する<br>マシン固有設定、個人メモ、実験、正式実装を区別する<br>worktree完了時の清掃を開発フローに含める | 本番同期を git pull 基本にするか setup再実行も含めるか<br>/finished-pr に本番pull提案やworktree清掃を含めるか<br>.gitignore 対象の整理<br>本番だけの実験を置ける場所・命名 | 開発リポジトリは main の 99166b8 (#265)<br>開発リポジトリには .codex/、session summary、CLAUDE.local.md、audit、index-investigations.sh が未追跡<br>本番 ~/.claude は HEAD e1dc01f で dirty 多数<br>本番では agents削除、settings変更、hooks/skills/scripts未追跡が混在<br>約100PR遅れはFable項目15の監査結果を根拠とする | 本番 ~/.claude のgit statusが説明可能な差分だけになるか<br>本番HEADがorigin/mainと一致するか<br>マージ後の本番反映手順が辿れるか<br>worktree完了後に残骸が残らないか | 未確定 / 要整理 |

## 注意

状態はすべて暫定。要求・仕様・実装計画・テスト設計の各段階で更新する。