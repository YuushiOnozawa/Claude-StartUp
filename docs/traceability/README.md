# トレーサビリティ全体ボード

最終更新: 2026-07-06（実行順に並べ替え。旧番号は各 core README の「旧番号」注記を参照）

分類元: [docs/planning/fable-traceability-classification.md](../planning/fable-traceability-classification.md)
運用手順: `/traceability-flow`（各 Step のスキル一覧と進行判定）

| 核問題 | 分類 | confidence | req | spec | impl-plan | 実装 | design-review | test | audit |
|---|---|---|---|---|---|---|---|---|---|
| [core-01-environment-scope](core-01-environment-scope/README.md) — 対応環境スコープ・優先度の未確定（旧 core-07） | 要確認 | medium | draft | draft | draft | todo | todo | draft | todo |
| [core-02-live-deploy-drift](core-02-live-deploy-drift/README.md) — 本番 ~/.claude とリポジトリの正の分裂（旧 core-05） | 必須 | high | draft | draft | draft | todo | todo | draft | todo |
| [core-03.1-magi-codex-llm-sync](core-03.1-magi-codex-llm-sync/README.md) — MAGI/Codex/ローカルLLM の実体・参照・割当ズレ（旧 core-02） | 必須 | high | draft | draft | draft | todo | todo | draft | todo |
| [core-03.2-knowledge-distill-store](core-03.2-knowledge-distill-store/README.md) — hooks/蒸留/知識ストアの二重化・欠落・密結合（旧 core-03） | 必須 | high | draft | draft | draft | todo | todo | draft | todo |
| [core-03.3-setup-readiness](core-03.3-setup-readiness/README.md) — ワンライナー展開後の実行可能状態保証（旧 core-01） | 必須 | high | draft | draft | draft | todo | todo | draft | todo |
| [core-03.4-continuous-assurance](core-03.4-continuous-assurance/README.md) — ドキュメント・CI・verify の継続保証不足（旧 core-06） | 必須 | high | draft | draft | draft | todo | todo | draft | todo |
| [core-04-second-brain-recall](core-04-second-brain-recall/README.md) — 第二の脳・横断想起の運用仕様化（番号変更なし） | 将来拡張 | medium | draft | draft | draft | todo | todo | draft | todo |

## 実行順（2026-07-06 決定）

1. **core-01**: 要確認分類のため最初に人間判断（環境スコープが core-03.3 の要求範囲に影響する）
2. **core-02**: `/traceability-requirements core-02` — 他の全修正の反映経路の前提（監査15）。
   de-git + deploy.sh 方式を採るかを Step 3 で確定させる
3. **core-03.1 → core-03.2 → core-03.3 → core-03.4**: 同一分類（必須・grouping "3"）内はこの順で
   requirements 確認を進める
4. **core-04**: 将来拡張のため最後（core-03.2 の仕様確定が前提）

## blocked

- なし

## 運用メモ

- このボードは各 `core-XX/README.md` のステータス表からの派生物。手で編集せず
  `/traceability-board-update` で再生成する
- ステータス値・共通ルールは `skills/traceability-common/references/rules.md` を参照
- 2026-07-06 の番号並べ替え経緯: 実行順（環境スコープ確定 → 本番デプロイ正常化 → 必須群 → 将来拡張）に
  合わせて旧 core-01/02/03/05/06/07 を並べ替えた。旧 core-04 は番号変更なし。
  各フォルダの README に旧番号を記録済み
