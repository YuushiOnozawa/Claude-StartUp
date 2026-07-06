# 17. プロジェクト横断の長期記憶活用（蒸留フォーマット強化 + auto-recall）

種別: 推奨追加機能（最終目標の要件4を完成させる層）/ 優先度: 中（13 完了後、16 と並行可）

## 目的

「プロジェクト A でこうやったらこうなった → B でも同様に / B では逆に」という
**横断的な経験転用**を、Claude の自発性に頼らず機能させる。

現状のギャップ:
1. 蒸留ノートが「結果・判断」を構造化して残す形式になっておらず、転用に耐えない
2. 想起が CLAUDE.md ルール（search_knowledge を呼べ）頼みで、呼び忘れ・クエリずれで空振りする

## Part 1: 蒸留フォーマットの強化（貯める側）

### 1-1. 蒸留プロンプトの出力形式を「転用可能な単位」に変更

`hooks/knowledge-distill-extract.sh` の蒸留プロンプトを、要約ではなく**経験カード**形式に：

```markdown
---
project: <プロジェクト名>
date: YYYY-MM-DD
tech: [<技術タグ>, ...]          # 例: [rclone, WSL, systemd]
outcome: success | failure | partial | decision
---
## 状況
## やったこと
## 結果（何が起きたか）
## 判断と理由（なぜそうしたか / 次はどうするか)
```

- `lessons-learned`（ミス限定）と対になる**成功・設計判断の記録**が主目的。
  frontmatter の `tech` タグと `outcome` が横断検索の手がかりになる
- 1セッションから複数カードが出てよい（1カード1経験）。RAG のチャンクとも相性が良い

### 1-2. 4000字制限の見直し

`knowledge-distill.sh` は会話を先頭 4000 字で切って LLM に渡しており、
**長いセッションほど後半の結論・結果が落ちる**（転用に最重要の部分が失われる）。

- 対応案A（推奨・簡単）: 先頭 2000 字 + 末尾 6000 字に変更（結論は末尾に集中する）
- 対応案B: チャンク分割 → 各チャンク蒸留 → 統合の2パス（Ollama 実行時間が倍増、qwen2.5:7b 前提）
- まず A で効果を見る。OLLAMA_TIER=high 環境のみ B、という段階も可

### 1-3. 検索言語の正準化（前提条件、[13](13-pcloud-fallback.md) Step 4 で実施）

決定（2026-07-05）: 索引は**英語シャドウノート**（`store/index-en/`、配送対象外）に正準化する。
検索スタック（埋め込み/BM25/reranker）がすべて英語前提のため、多言語埋め込み切替より効果範囲が広い。

- 蒸留プロンプトは 1-1 の経験カードを**日英同時出力**する（日本語 = 人間用・Obsidian 配送、
  英語 = index-en/ 索引専用）。frontmatter（tech タグ・outcome）は両言語で共通
- auto-recall のクエリは**プロンプト中の ASCII 技術語抽出**で生成する（翻訳不要・レイテンシゼロ。
  `rclone` `systemd` 等の技術語は日本語文中でも英語のまま出現するため実用になる）
- CLAUDE.md に「search_knowledge のクエリは英語で書く」ルールを追加（スキル経由検索の言語合わせ）

### 1-4. 検索メタデータの活用

`config.yaml` の未使用機能を有効化する：
- `keyword_routes`: tech タグ頻出語 → カテゴリ誘導
- `query_expansions`: 略語展開（例: "WSL" → "Windows Subsystem for Linux"）
初期値はリポジトリの config 生成（402）に含め、運用で育てる。

## Part 2: auto-recall フック（想起側）

### 2-1. UserPromptSubmit での自動想起

`hooks/auto-recall.sh`（新規、UserPromptSubmit 登録）:

1. プロンプト本文を読み、**技術的内容の場合のみ**（ヒューリスティック: 長さ・コードブロック・
   技術語の有無。LLM は使わずコストゼロで判定）検索を実行
2. `search_knowledge`（knowledge-rag を CLI 経由で直接叩く。venv の Python で
   ChromaDB に直接クエリすれば MCP 往復不要）で上位 2〜3 件を取得
3. スコア閾値以上のヒットがあれば stdout でコンテキスト注入
   （check-queue.sh の通知注入と同じ方式）:

   ```
   [RECALL] 関連する過去の経験が見つかりました:
   - <project A> (2026-06-12, outcome: failure): rclone mount は複数WSLで外れる → ローカル正に移行
   （詳細が必要なら search_knowledge で "<クエリ>" を検索）
   ```

4. **要約1行だけ注入して本文は注入しない**（トークン削減方針と両立させる。
   詳細は Claude が必要と判断したときだけ search_knowledge で取りに行く）

### 2-2. 暴発防止（設計上の必須ガード）

- 実行時間上限: 全体で 1〜2 秒以内。超過時は無言でスキップ（UserPromptSubmit は
  入力をブロックしないカテゴリ A 方針に従う）
- 同一セッション内の注入回数上限（例: 3回）と、同じヒットの再注入抑止（セッション単位の既出キャッシュ）
- スコア閾値は高めから始める（誤想起のノイズはトークンと注意の両方を浪費するため）

### 2-3. kizami との役割整理

kizami（会話単位の recall）と knowledge-rag（構造化知識）の重複を DESIGN.md で明文化する:
- auto-recall のソースは **knowledge-rag に一本化**（蒸留済み・構造化済み・横断タグ付きのため）
- kizami は「特定の過去会話を明示的に思い出したい」時の手動用途と位置づける

## 段階導入

| 段階 | 内容 | 判断基準 |
|---|---|---|
| v1 | Part 1 のみ（フォーマット + 4000字対応） | 蒸留カードの品質を2週間分目視評価 |
| v2 | auto-recall を閾値高め・注入1行で導入 | 誤想起率・体感ノイズ |
| v3 | 閾値・件数チューニング、query_expansions 育成 | ヒット率 |

## 受け入れ基準

- [ ] プロジェクト A の作業（例: rclone 問題の解決）後、プロジェクト B で類似トピックの
      プロンプトを投げると、[RECALL] 注入または search_knowledge で A の経験カードがヒットする
- [ ] 経験カードに outcome / 判断理由が含まれ、「同様に or 逆に」の判断材料になる
- [ ] auto-recall がプロンプト応答を体感で遅延させない（<2秒、超過時サイレントスキップ）
- [ ] 非技術的な雑談プロンプトで注入が発生しない
- [ ] **日本語プロンプト（技術語含む）から index-en の英語カードにヒットする**（言語正準化の成立検証）

## 影響ファイル

- `hooks/knowledge-distill-extract.sh`, `hooks/knowledge-distill.sh`（4000字制限）
- 新規: `hooks/auto-recall.sh`
- `settings.json`（UserPromptSubmit 登録 — 04 の直書き方針に従う）
- `setup/402-knowledge-rag-mcp-config.sh`（keyword_routes / query_expansions 初期値）
- `DESIGN.md`（kizami / knowledge-rag の役割整理）, `CLAUDE.md`（search_knowledge ルールとの関係追記）
