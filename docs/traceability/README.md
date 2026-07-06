# トレーサビリティ全体ボード

最終更新: 2026-07-06（初期生成）

分類元: [docs/planning/fable-traceability-classification.md](../planning/fable-traceability-classification.md)
運用手順: `/traceability-flow`（各 Step のスキル一覧と進行判定）

| 核問題 | 分類 | confidence | req | spec | impl-plan | 実装 | design-review | test | audit |
|---|---|---|---|---|---|---|---|---|---|
| [core-01-setup-readiness](core-01-setup-readiness/README.md) — ワンライナー展開後の実行可能状態保証 | 必須 | high | draft | draft | draft | todo | todo | draft | todo |
| [core-02-magi-codex-llm-sync](core-02-magi-codex-llm-sync/README.md) — MAGI/Codex/ローカルLLM の実体・参照・割当ズレ | 必須 | high | draft | draft | draft | todo | todo | draft | todo |
| [core-03-knowledge-distill-store](core-03-knowledge-distill-store/README.md) — hooks/蒸留/知識ストアの二重化・欠落・密結合 | 必須 | high | draft | draft | draft | todo | todo | draft | todo |
| [core-04-second-brain-recall](core-04-second-brain-recall/README.md) — 第二の脳・横断想起の運用仕様化 | 将来拡張 | medium | draft | draft | draft | todo | todo | draft | todo |
| [core-05-live-deploy-drift](core-05-live-deploy-drift/README.md) — 本番 ~/.claude とリポジトリの正の分裂 | 必須 | high | draft | draft | draft | todo | todo | draft | todo |
| [core-06-continuous-assurance](core-06-continuous-assurance/README.md) — ドキュメント・CI・verify の継続保証不足 | 必須 | high | draft | draft | draft | todo | todo | draft | todo |
| [core-07-environment-scope](core-07-environment-scope/README.md) — 対応環境スコープ・優先度の未確定 | 要確認 | medium | draft | draft | draft | todo | todo | draft | todo |

## 次のアクション候補

全核問題が Step 3（要求定義）の人間確認前。推奨順:

1. core-07: 要確認分類のため**最初に人間判断**（環境スコープが core-01 の要求範囲に影響する）
2. core-05: `/traceability-requirements core-05` — 他の全修正の反映経路の前提（監査15）
3. core-02 → core-03 → core-01 → core-06 の順で requirements 確認を進める
4. core-04 は将来拡張のため後回し可（core-03 の仕様確定が前提）

## blocked

- なし

## 運用メモ

- このボードは各 `core-XX/README.md` のステータス表からの派生物。手で編集せず
  `/traceability-board-update` で再生成する
- ステータス値・共通ルールは `skills/traceability-common/references/rules.md` を参照
