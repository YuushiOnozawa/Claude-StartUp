---
name: investigate
description: Obsidianの「from X.md」から未調査URLを読み取り、Web調査してinvestigationsフォルダにまとめファイルを保存するスキル。「FromXを調査して」「from Xを処理して」「調査スキル」「/investigate」など、XのブックマークやURLリストを調査・整理したいとき、またはObsidianにまとめを残したいときは必ずこのスキルを使う。
---

# investigate — from X.md 調査スキル

Obsidianの `from X.md` に溜まった未調査URLをWeb調査し、investigations/ にまとめファイルを作成する。

## ファイルパス（固定）

- **入力**: `$HOME/pcloud/obsidian/from X.md`
- **出力先**: `$HOME/pcloud/obsidian/investigations/`

> NOTE: 出力先の FUSE 直書きは core-01 SPEC-01-03 で改修予定のレガシー動作（不変条件: pCloud への書き込みは pcloud-sync.sh のみ）

## ステップ

### 1. 未調査項目の抽出

`from X.md` を読んで対象を2種類見つける：

**A. チェックボックス未済の項目**（`[ ]` で始まる）
```
- [ ] **タイトル** — 説明
  https://...
```

**B. 裸URL**（チェックボックスなし、タイトルなし、ファイル末尾に貼られているもの）
```
https://x.com/...
https://zenn.dev/...
```

既に `[x]` になっているものと `→ [[investigations/...]]` がついているものはスキップ。

### 2. 各URLをWeb調査

未調査項目ごとに WebSearch / WebFetch でURLの内容を調査する。  
**X（Twitter）のURLの場合は Jina を使う**：`https://r.jina.ai/https://x.com/...` の形式で WebFetch すると、ツイート本文・リンク先を取得できる。Jinaで内容が取れない場合は、URLに含まれるアカウント名・ポスト内容から推測してリポジトリURLや記事URLを特定し、そちらを調査する。

調査で把握すること：
- 何をするツール/記事/プロジェクトか（一言概要）
- 技術的な仕組みや特徴
- スター数・注目度（GitHubならスター数）
- 自分のプロジェクト（Claude StartUp）への応用可能性

### 3. タイトルとスラグの決定

- **タイトル**: 調査結果から日本語で命名（例: `LeanCTX — コンテキストOS`）
- **スラグ**: `YYYY-MM-DD-kebab-case-english`（例: `2026-06-10-lean-ctx`）
  - 今日の日付を使う
  - 英語のkebab-case、20文字以内目安

### 4. investigations/ にファイル作成

以下のフォーマットで `$HOME/pcloud/obsidian/investigations/YYYY-MM-DD-slug.md` を作成する：

```markdown
# [タイトル]
調査日: YYYY-MM-DD  
[リポジトリ or ソース or URL]: https://...  
タグ: #タグ1 #タグ2 #タグ3

---

## 概要
[1〜3文で何をするものか]

---

## [技術詳細セクション（内容に応じて自由に命名）]
[調査内容]

---

## 評価
[Claude StartUpや自分のプロジェクトへの応用可能性、メモ]
```

既存ファイルを参考に自然な日本語で書く。スター数があればセクション冒頭に `⭐ XX,XXX` の形で記載。

### 5. from X.md を更新

各項目について `from X.md` を編集する：

**A. `[ ]` 項目の場合** → `[x]` に変更し、wikiリンクを追記：
```
- [x] **タイトル** — 説明
  https://...
  → [[investigations/YYYY-MM-DD-slug]]
```

**B. 裸URLの場合** → その行をフォーマット済みエントリに置き換え：
```
- [x] **タイトル** — 一行概要
  https://...
  → [[investigations/YYYY-MM-DD-slug]]
```

### 6. ユーザーへの表示

全項目の調査が完了したら、各調査結果を会話上に表示する：

```
## [タイトル]
**URL**: https://...
**概要**: ...
**ポイント**: ...（箇条書き2〜3点）
**応用可能性**: ...
---
```

未調査項目がゼロだった場合は「from X.md に未調査項目はありませんでした」と伝える。

## 注意事項

- `from X.md` の既存フォーマット・改行・セクション構造を崩さないよう編集する
- 同じURLで既にinvestigationsファイルが存在する場合は作成をスキップし、wikiリンクのみ追記する
- X（Twitter）のURLは必ず `https://r.jina.ai/<元URL>` で WebFetch してからアーカイブや関連リポジトリを探す
