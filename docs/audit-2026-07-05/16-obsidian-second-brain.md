# 16. Obsidian 第2の脳ワークフロー（inbox → 調査 → knowledge 還流）

種別: 推奨追加機能（最終目標に直結）/ 優先度: 中（13 完了後に着手）

## 目的

Obsidian を「AI 用の第2の脳」として機能させる循環を作る：

```
スマホ/PC の Obsidian: inbox/ に URL や調べたいことを一言メモ
        ↓ 取込層（13）が store/vault/inbox/ にミラー
WSL の Claude: /inbox スキルで未処理メモを検出 → 調査（WebFetch / WebSearch / codegen）
        ↓
調査結果を knowledge/re-<slug>.md として記録層に書く（[[元メモ]] リンク付き）
        ↓ RAG インデックス（search_knowledge で即活用可能）
        ↓ 配送層（13）が Obsidian に公開 → グラフビューで元メモと繋がる
```

前提: [13](13-pcloud-fallback.md) の store / 配送層 / 取込層が稼働していること。

## 設計

### inbox の規約（人間側は最小ルール）

- vault 直下に `inbox/` を作る。1メモ1ファイル。書式自由（URL 1行だけでも可）
- 任意で frontmatter による指示: `type: research | summarize | monitor`、`priority: high`
  — 無ければ `research` 扱い。人間側に書式を強制しない（一言メモが成立の条件）

### /inbox スキル（新規）

1. **検出**: `store/vault/inbox/*.md` を列挙し、処理済み台帳
   `store/knowledge/_inbox-ledger.md`（機械領域。ファイル名 + content hash を記録）と突合
   - inbox ノート自体は人間領域（読み取り専用）なので **Claude は書き換えない**。
     処理済み管理は台帳側で行う。hash 突合により「人間がメモを追記したら再処理対象になる」
2. **確認**: 未処理一覧を提示し、AskUserQuestion で処理対象を選択（全件自動は最初はやらない）
3. **調査**: URL は WebFetch、テーマは WebSearch。knowledge-rag の既存知識を先に
   `search_knowledge` で確認（CLAUDE.md の既存原則どおり）
4. **還流**: 結果を `store/knowledge/re-<slug>.md` に保存:
   - frontmatter: `source: [[<元メモ名>]]`, `date`, `origin-url`
   - 本文: 要約 / 詳細 / 出典。RAG チャンクに乗る粒度（見出し分割）で書く
5. **台帳更新**: `_inbox-ledger.md` に処理記録を追記（台帳も outbound で Obsidian から見える =
   人間側から処理状況が確認できる）

### 自動化の段階（v1 は手動トリガー）

| 段階 | トリガー | 内容 |
|---|---|---|
| v1 | `/inbox` 手動実行 | 検出→確認→調査→還流。まず運用感を掴む |
| v2 | SessionStart フックで未処理件数を通知 | 「inbox に未処理 N 件」を会話コンテキストに注入（check-queue.sh の通知方式を流用） |
| v3 | schedule（cloud agent / cron）で定期処理 | `priority: high` のみ自動調査等。コスト見合いで判断 |

### 将来拡張（構想メモ、本プランのスコープ外）

- `type: monitor`: URL の定点観測（差分があれば知識更新）
- knowledge/ 内の関連ノート自動リンク（[[]] 挿入）による脳の「連想」強化
- 蒸留セッション（sessions/）と人間ノートの横断類似検出 → auto-promote の対象拡大

## 受け入れ基準

- [ ] スマホで inbox/ に URL をメモ → 次の WSL セッションで `/inbox` → 調査結果が
      Obsidian のグラフビューで元メモとリンクされて見える
- [ ] 同じ結果が `search_knowledge` でヒットする
- [ ] 同一メモが二重処理されない。メモを人間が追記したら再処理候補に上がる
- [ ] inbox ノート自体は一切書き換えられていない

## 影響ファイル

- 新規: `skills/inbox/SKILL.md`（+ references/）
- `config.example.yaml`（category_mappings に `vault/inbox` 等を追加）
- v2 時: `hooks/check-queue.sh` または新規 SessionStart フック
- `SKILLS.md`, `DESIGN.md`（ワークフロー図）
