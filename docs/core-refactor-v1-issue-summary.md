# Coreリファクタ v1 Issue メモ

## 結論

Coreリファクタ v1 は失敗扱いで凍結する。

主因は、ローカルLLMに対して「レビュー本文生成」を超えるワークフロー制御、厳密 schema、commit gate 判定、traceability 記録まで要求し、通常開発の速度とレビュー可用性を落としたこと。

現 main は `archive/core-refactor-v1-failed-20260724` に退避し、通常運用する main は Coreリファクタ全項目着手前の `c1b1456` 相当へ戻す。

## Core単位の一覧

| Core | 問題にした点 | v1でやった対応 | 結果 | rollback後の扱い |
|---|---|---|---|---|
| core-01 environment/scope | 対応環境、pCloud同期、WSL/Windows/Ollama前提が曖昧 | requirements/spec/impl-plan を作成し、pCloud書き込み経路を `pcloud-sync.sh` に寄せる設計を記録 | 実装未完。`pcloud-sync.sh` 不在のまま他コンポーネントと不整合 | 凍結。環境スコープとpCloud同期は再設計対象 |
| core-02 live deploy drift | 実働 `~/.claude` と repo の正が分裂 | 還流棚卸し、sync系設定、README手順、traceability記録を追加 | verified 扱いまで進んだが、Core全体 rollback に巻き戻す | 内容は archive 参照。必要なら「本番同期正常化」だけ独立Issue化 |
| core-03.1 MAGI/Codex/LLM sync | MAGI persona、モデル割当、setup pull、docs のズレ | MAGI出力契約、plan-receipt、change-summary、複数スクリプト化、review router などを追加 | 一部の不整合は解消したが、strict gate 化でレビュー体験が劣化 | 旧レビュー体験へ戻す。再導入時は LLM は advisory 前提 |
| core-03.2 knowledge-distill/store | hooks二重登録、knowledge-distill、pCloud密結合 | SessionStart drain、ローカル staging、lessons-learned ローカル化、queue調整を追加 | `pcloud-sync.sh` 不在、remember/index/prune は FUSE 前提のままで中途半端 | いったん着手前へ戻す。pCloud/Obsidianは別Issueで再設計 |
| core-03.3 setup readiness | ワンライナー後に動く状態の保証不足 | requirements/spec/impl-plan まで作成 | 実装未完 | 凍結。setup verify は小さく再設計 |
| core-03.4 continuous assurance | CI/verify/docs整合の継続保証不足 | requirements/spec/impl-plan まで作成 | 実装未完 | 凍結。CIは deterministic test から再開 |
| core-04 second brain recall | Obsidian inbox、経験カード、横断想起が構想止まり | requirements/spec/impl-plan まで作成 | 将来拡張のまま未実装 | 凍結。knowledge基盤が安定してから再検討 |

## Fable項目単位の一覧

| # | 問題にした点 | v1でやった対応 | 結果 | 次に残すなら |
|---|---|---|---|---|
| 01 | MAGIエージェント定義の参照不整合 | MAGI共通契約・実行スクリプト側へ寄せる方向で対応 | 契約が重くなり、モデルのレビュー能力を削った | persona定義の正だけ決める。gate化しない |
| 02 | setupモデル一覧とスキル要求モデルのズレ | MAGI/LLM同期Coreで扱った | strict化と同時に入り、単独効果を検証しづらい | モデル突合チェックだけ小さく戻す |
| 03 | README/SKILLS/DESIGNの陳腐化 | traceability docs と各Core計画に反映 | docs量が増え、運用正本が増殖 | README最小、詳細はIssueに逃がす |
| 04 | knowledge-distill hook二重登録 | `setup/410` と `412`、SessionStart drain 方向へ修正 | 一部改善。ただし他のObsidian系と不整合 | hook登録だけ再監査して最小修正 |
| 05 | error-detector未配備 | Core分類・setup readiness に含めた | 実装完了前に凍結 | setup verify の一項目として扱う |
| 06 | `bash scripts/...` 相対パス参照 | MAGIスクリプト化・runner化を進めた | レビューゲート肥大化と結合 | パス解決だけ独立修正 |
| 07 | repo hygiene / worktree残骸 | core-02 / docsに記録 | cleanup自体は価値あり、Core本体とは独立可能 | 個別の掃除Issueにする |
| 08 | Codex CLI自動導入不足 | setup readiness に含めた | 未実装 | Codex導入/認証確認を小さく扱う |
| 09 | Ollama serve / 常駐化不足 | setup readiness に含めた | 未実装 | verify/warn中心にする |
| 10 | setup verify不足 | setup readiness に含めた | 未実装 | `setup --verify` を最小項目で作る |
| 11 | CIなし | continuous assurance に含めた | 未実装 | `bash -n` と既存テストだけから開始 |
| 12 | 手動ステップ導線不足 | setup readiness に含めた | 未実装 | READMEの短いチェックリストで足りる |
| 13 | pCloud FUSE密結合 | local staging / pcloud-sync 設計へ寄せた | `pcloud-sync.sh` 未実装で中途半端 | pCloud/Obsidian基盤Issueとして再設計 |
| 14 | Windows native対応範囲未定 | environment/scope に含めた | 未実装 | 当面 WSL2 正式、Windows native は非対象でよい |
| 15 | 本番 `~/.claude` とrepoの正の分裂 | core-02で還流・sync手順を記録 | 一部 verified 扱い。ただし全体rollbackで退避 | 本番同期正常化だけ独立Issue化 |
| 16 | Obsidian second brain workflow未仕様 | core-04で仕様化 | 未実装 | knowledge基盤後の将来Issue |
| 17 | cross-project recall未仕様 | core-04で仕様化 | 未実装 | auto-recallは最後。まず検索品質評価 |

## 失敗した設計判断

- LLMレビューを advisory ではなく commit gate にした。
- MAGIに、レビュー・裁判官・書記・schema producer を同時にやらせた。
- strict output / parse status / false positive分類 / duplicate分類 / needs_human分類を一度に要求した。
- traceability を通常 dev-flow の制御面へ寄せすぎた。
- Core 03.1 MAGI改善と Core 03.2 knowledge基盤を、通常開発の復旧より優先した。
- pCloud FUSE脱却の途中で `pcloud-sync.sh` が未実装のまま、ローカル staging だけ先に入った。

## まだ価値がある知見

- 問題分類そのものは有用。
- 本番 `~/.claude` と repo の正の分裂は解消すべき。
- setup verify / CI / manual steps は必要。ただし最小の deterministic check から始めるべき。
- pCloud FUSE書き込み依存は弱い。将来は local store + 明示syncへ寄せる価値がある。
- Obsidian second brain / cross-project recall は魅力があるが、knowledge基盤が安定するまで入れない。

## 再設計の前提

- LLMレビューは advisory。
- 機械ゲートは deterministic test、構文チェック、既存テストに限定する。
- LLM出力 schema は最小にする。
- commit可否を LLM に決めさせない。
- Traceability は通常開発の必須制御面にしない。
- Coreリファクタは1 Issue 1 関心事で再開する。

## 再開候補

優先度順:

1. 本番 `~/.claude` と repo の同期正常化。
2. `/magi-fast` を旧レベルの advisory review として安定化。
3. setup verify の最小実装。
4. pCloud/Obsidian/knowledge-distill の基盤再設計。
5. CI の最小導入。
6. Obsidian second brain / cross-project recall。
