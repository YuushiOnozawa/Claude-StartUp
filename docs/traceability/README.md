# トレーサビリティ全体ボード

最終更新: 2026-07-07（全 core requirements approved 完了）

分類元: [docs/planning/fable-traceability-classification.md](../planning/fable-traceability-classification.md)
運用手順: `/traceability-flow`（各 Step のスキル一覧と進行判定）

| 核問題 | 分類 | confidence | req | spec | impl-plan | 実装 | design-review | test | audit |
|---|---|---|---|---|---|---|---|---|---|
| [core-01-environment-scope](core-01-environment-scope/README.md) — 対応環境スコープ・優先度の未確定（旧 core-07） | 要確認 | medium | **approved** | draft | draft | todo | todo | draft | todo |
| [core-02-live-deploy-drift](core-02-live-deploy-drift/README.md) — 実働環境で生まれた開発内容の還流経路が未定義（旧 core-05、旧名「本番とリポジトリの正の分裂」） | 必須 | high | **approved** | draft | draft | todo | todo | draft | todo |
| [core-03.1-magi-codex-llm-sync](core-03.1-magi-codex-llm-sync/README.md) — MAGI/Codex/ローカルLLM の実体・参照・割当ズレ（旧 core-02） | 必須 | high | **approved** | draft | draft | todo | todo | draft | todo |
| [core-03.2-knowledge-distill-store](core-03.2-knowledge-distill-store/README.md) — hooks/蒸留/知識ストアの二重化・欠落・密結合（旧 core-03） | 必須 | high | **approved** | draft | draft | todo | todo | draft | todo |
| [core-03.3-setup-readiness](core-03.3-setup-readiness/README.md) — ワンライナー展開後の実行可能状態保証（旧 core-01） | 必須 | high | **approved** | draft | draft | todo | todo | draft | todo |
| [core-03.4-continuous-assurance](core-03.4-continuous-assurance/README.md) — ドキュメント・CI・verify の継続保証不足（旧 core-06） | 必須 | high | **approved** | draft | draft | todo | todo | draft | todo |
| [core-04-second-brain-recall](core-04-second-brain-recall/README.md) — 第二の脳・横断想起の運用仕様化（番号変更なし） | 将来拡張 | medium | **approved** | draft | draft | todo | todo | draft | todo |

## 実行順（2026-07-06 決定 / 2026-07-07 追記）

1. ~~**core-01**: 要確認分類のため最初に人間判断~~ ✅ 完了（2026-07-07 requirements approved）
2. ~~**core-02**: requirements~~ ✅ 完了（2026-07-07 approved。前提変更により「還流経路の確立」へ
   問題を再定義。de-git + 還流スキル（手動）方式で確定。経緯は core-02 の
   opus-context / sonnet-handoff 2026-07-07 参照）
3. ~~**core-03.1**~~: ✅ 完了（2026-07-07 approved） / ~~**core-03.2**~~: ✅ 完了（2026-07-07 approved） / ~~**core-03.3**~~: ✅ 完了（2026-07-07 approved） / ~~**core-03.4**~~: ✅ 完了（2026-07-07 approved）
4. ~~**core-04**~~: ✅ 完了（2026-07-07 approved）— **全 core requirements 完了。次は spec フェーズへ**

### spec 以降の消化順（2026-07-07 決定）

- ~~**requirements を core-03.4 まで消化し終えるまで、spec 以降には進まない**~~ ✅ **全 core requirements 完了**（2026-07-07）
  **次フェーズ: spec 縦掘り開始**（core-02 → core-03.1 → core-03.2 → core-03.3 → core-03.4 → core-01 → core-04）
- その後は core 単位の縦掘り（spec → impl-plan → 実装 → design-review → test → audit）で全消化する:
  **core-02 → core-03.1 → core-03.2 → core-03.3 → core-03.4 → core-01 → core-04**
- core-02 を先頭に置く理由: 還流モデル（内容物ホワイトリスト・還流スキル）が他 core の
  実装着地先の土台になるため
- core-01 を後置する理由: 受け入れ条件（ワンライナー展開完走・Ollama 二重起動なし・pCloud 設計明記・
  verify の WSL2 明示）が core-03.2 / core-03.3 の成果物に依存するため。後置することで blocked 管理が不要になる
- それでも検証不能な受け入れ条件が出た場合は `blocked` とし、依存先 core の audit で一緒に閉じる

## blocked

- なし

## 運用メモ

- このボードの**ステータス表**は各 `core-XX/README.md` のステータス表からの派生物。手で編集せず
  `/traceability-board-update` で再生成する。**「実行順」「運用メモ」は人間の決定記録**であり、
  再生成時も削除せず保持する（traceability-board-update スキルにも保持ルールを明記済み）
- ステータス値・共通ルールは `skills/traceability-common/references/rules.md` を参照
- 2026-07-06 の番号並べ替え経緯: 実行順（環境スコープ確定 → 本番デプロイ正常化 → 必須群 → 将来拡張）に
  合わせて旧 core-01/02/03/05/06/07 を並べ替えた。旧 core-04 は番号変更なし。
  各フォルダの README に旧番号を記録済み
