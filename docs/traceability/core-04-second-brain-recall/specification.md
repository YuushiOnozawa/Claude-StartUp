# Specification: Core 04 — 第二の脳・プロジェクト横断想起の運用仕様化

> ステータス: approved（2026-07-08 人間承認済み）
> 対応 requirements: approved 2026-07-07

---

## SPEC-04-01 — /inbox スキルの実装仕様

**対応 REQ:** REQ-04-01  
**対象:** `skills/inbox/SKILL.md`（新規）

### 振る舞い

`/inbox` を実行すると以下のフローを実行する:

1. **入力読み取り**: `store/vault/_inbox/` ディレクトリ内の `.md` ファイルを列挙する
2. **未処理フィルタ**: `store/vault/_inbox-ledger.md` を参照し、`processed: true` のエントリをスキップする
3. **調査実行**: 未処理エントリごとに以下を実行する:
   - URL が含まれる場合: `WebFetch` または `WebSearch` で内容を取得・要約する
   - メモのみの場合: メモ内容を knowledge-rag へ登録する文書として整形する
4. **knowledge 還流**: 調査結果を `mcp__knowledge-rag__add_document` で登録する
   - `filepath`: `inbox/<YYYY-MM-DD>-<slug>.md`（slug は元ファイル名から拡張子を除いた文字列）
   - `category`: `inbox`
5. **台帳更新**: `store/vault/_inbox-ledger.md` に処理完了を記録する（SPEC-04-03 参照）
6. **Obsidian ノート本体は書き換えない**: `store/vault/_inbox/` への書き込みのみ許可。それ以外のパスへの直接書き込みは禁止

### 境界条件

| 条件 | 出力 | 終了 | 台帳 |
|---|---|---|---|
| `store/vault/_inbox/` が空 | `[INFO] inbox は空です` | 正常終了 | 変更なし |
| 台帳に `processed: true` のエントリ | `[SKIP] <slug>` | 継続 | 変更なし |
| WebFetch 失敗（HTTP エラー・タイムアウト） | `[WARN] <URL> の取得失敗。手動確認を推奨` | 継続 | `processed: false` のまま維持（次回 /inbox 実行時に再試行可能） |
| knowledge-rag 登録失敗 | `[WARN] knowledge 登録失敗: <slug>` | 継続 | `processed: false` のまま維持（再試行可能） |

### スコープ外（v2 以降）

- SessionStart での inbox 未処理通知
- 自動実行トリガー

---

## SPEC-04-02 — 経験カード形式の定義

**対応 REQ:** REQ-04-02  
**対象:** `skills/compact-prep/SKILL.md`（更新）

### 振る舞い

蒸留フロー（compact-prep）で生成される経験カードは以下の形式に従う。

#### 必須フィールド（全件必須。省略不可）

```markdown
---
title: <セッションタイトルまたはタスク概要>
date: <YYYY-MM-DD>
tags: [<技術タグ1>, <技術タグ2>]
outcome: success | partial | failed
---

## 状況
<どのような問題・タスクに取り組んでいたか。背景・制約を含む>

## やったこと
<実際に行った操作・判断・コマンド。箇条書き可>

## 結果
<何が達成されたか。エラー・失敗の場合はその内容>

## 判断理由
<なぜそのアプローチを選んだか。代替案との比較があれば記述>

## outcome
<success / partial / failed とその理由一文>
```

セクション名（`## 状況`・`## やったこと`・`## 結果`・`## 判断理由`・`## outcome`）は完全一致で出力する。テストは `grep -c "^## 状況"` 等で検証できる。

#### 出力先

- 日本語カード: `store/distilled/ja/<YYYY-MM-DD>-<slug>.md`
- 英語シャドウ: `store/distilled/en/<YYYY-MM-DD>-<slug>.md`（同一 frontmatter・英語本文）

### 境界条件

| 条件 | 判定基準 | 動作 |
|---|---|---|
| セッションが短い（transcript が 500 文字未満） | トランスクリプト文字数で判定 | 「状況: 情報不足（トランスクリプト不足）」として出力し、他フィールドを空欄にせずプレースホルダーで補完する |
| outcome が判定できない場合 | — | `partial` をデフォルトとする |
| 英語翻訳が困難な専門用語 | — | 英語カードでは原語（日本語）のまま記述し、説明を付記する |

---

## SPEC-04-03 — store/vault/_inbox-ledger.md の責務定義

**対応 REQ:** REQ-04-03  
**対象:** ディレクトリ構造の spec + `store/vault/_inbox-ledger.md` フォーマット

### 前提条件（他 core で確定済みの依存仕様）

| 依存先 | 内容 |
|---|---|
| SPEC-03.2-03 | セッションログの記録層は `~/.local/share/knowledge-rag/sessions/` にローカル保存。pCloud は配送層（非同期）|
| SPEC-03.2-05 | lessons-learned も `~/.local/share/knowledge-rag/lessons-learned/` にローカル保存（FUSE 書き込み廃止）|
| SPEC-01-03 | pCloud への書き込み経路は `pcloud-sync.sh` のみ（FUSE マウント経由の書き込み禁止）|

### store 基点パス

store 配下のすべてのディレクトリは **リポジトリ外** に配置する:

```
STORE_BASE="$HOME/.local/share/knowledge-rag/store"
```

リポジトリ内には `store/` ディレクトリを作成しない。git 管理対象外（`.gitignore` 追補不要）。

### ディレクトリ責務

| パス（STORE_BASE 基準） | 責務 | writer |
|---|---|---|
| `$STORE_BASE/distilled/ja/` | 蒸留済み経験カード（日本語） | Claude（compact-prep スキル） |
| `$STORE_BASE/distilled/en/` | 蒸留済み経験カード（英語シャドウ） | Claude（compact-prep スキル） |
| `$STORE_BASE/knowledge/` | knowledge-rag エクスポート済みファイル（参照用） | Claude（knowledge-rag 登録時） |
| `$STORE_BASE/vault/` | Obsidian 取込用（人間が Obsidian へ手動インポートする） | Claude（書き込み可）+ 人間（読み取り・移動） |
| `$STORE_BASE/vault/_inbox/` | Obsidian inbox からの入力 | 人間のみ（Claude は読み取り専用） |
| `$STORE_BASE/vault/_inbox-ledger.md` | /inbox 処理台帳。二重処理防止 | Claude（/inbox スキル） |

### _inbox-ledger.md フォーマット

ヘッダー行・区切り行・データ行からなる標準 GitHub Flavored Markdown 表とする。

```markdown
# Inbox Ledger

| slug | source_file | processed | processed_at | knowledge_id | notes |
|---|---|---|---|---|---|
| 2026-07-08-ollama-host | _inbox/2026-07-08-ollama-host.md | true | 2026-07-08T10:30:00Z | inbox/2026-07-08-ollama-host | - |
| 2026-07-08-pcloud-sync | _inbox/2026-07-08-pcloud-sync.md | false | - | - | WebFetch失敗 |
```

#### フィールド定義

| フィールド | 型・形式 | 空値 |
|---|---|---|
| `slug` | 英数字・ハイフンのみ（`[a-zA-Z0-9-]+`）。パイプ文字・改行禁止 | 不可 |
| `source_file` | `_inbox/<filename>.md` 形式の相対パス | 不可 |
| `processed` | `true` または `false` のいずれか | 不可 |
| `processed_at` | UTC タイムスタンプ（ISO 8601: `YYYY-MM-DDTHH:MM:SSZ`）または `-`（未処理） | `-` を許可 |
| `knowledge_id` | `inbox/<YYYY-MM-DD>-<slug>` 形式（SPEC-04-01 `filepath` と同値・拡張子なし）または `-` | `-` を許可 |
| `notes` | 任意テキスト。パイプ文字禁止。空の場合は `-` | `-` を許可 |

#### 台帳操作ルール

- `store/vault/_inbox-ledger.md` が存在しない場合: `/inbox` 実行時にヘッダー行と区切り行のみで新規作成する
- `slug` が重複する場合: 既存行を更新する（新規行を追加しない）

---

## SPEC-04-04 — auto-recall 設計仕様

**対応 REQ:** REQ-04-04  
**対象:** 設計仕様（実装は実装条件ゲートを満たしてから）

### 実装ゲート（実装前に人間が確認する条件）

以下の全条件を満たし、かつ人間が `docs/traceability/core-04-second-brain-recall/auto-recall-go.md` を作成して GO を宣言するまで、auto-recall は実装しない:

| # | 条件 | 判定方法 |
|---|---|---|
| 1 | `store/distilled/ja/` 配下の `.md` ファイルが 10件以上存在する | `ls store/distilled/ja/*.md \| wc -l` ≥ 10 |
| 2 | `/inbox` スキルが 5回以上エラーなく完了している | `_inbox-ledger.md` で `processed: true` の行数 ≥ 5 |
| 3 | 経験カードの想起精度を人間が評価し「GO」と判断している | `auto-recall-go.md` が存在することで確認 |

実装ゲート未達の場合は auto-recall 機能を起動せずサイレントに無視する（warn も出力しない）。

### 設計仕様

実装ゲート通過後に以下の仕様に従って実装する。

#### 発火条件

| 条件 | 発火 | 判定方法 |
|---|---|---|
| SessionStart でユーザーの最初のプロンプトにコード・コマンド・ファイル名・エラーメッセージのいずれかが含まれる | 発火 | 正規表現: コードフェンス（` ``` `）・`$`/`/`/`.sh`/`.py`/`.ts`・エラーキーワード（`Error:`・`failed`・`exception`）のいずれかにマッチ |
| ユーザーが `/recall` コマンドを明示的に呼ぶ | 発火 | — |
| プロンプトが 50文字未満 かつ上記パターン不一致 | 発火しない | 文字数カウント |
| 当セッションで既に auto-recall を実行済み | 発火しない（セッション内既出抑止） | セッション変数で管理 |

#### 検索パラメータ

| パラメータ | 値 | 理由 |
|---|---|---|
| 最大取得件数 | 3件 | コンテキスト節約とノイズ防止のバランス |
| トークン上限 | 1000 tokens | 3件 × 約333 tokens/カード |
| タイムアウト | 5秒 | 超過した場合は挿入をスキップし会話を継続 |
| 最小スコア閾値 | knowledge-rag デフォルト値に従う（実装時に調整） |

#### 既出抑止

セッション変数（または `ctx_session`）に「挿入済み knowledge_id リスト」を保持する。同一 `knowledge_id` は同一セッション内で2回以上挿入しない。

### 境界条件

| 条件 | 動作 |
|---|---|
| knowledge-rag タイムアウト（5秒超過） | auto-recall をスキップ。`[WARN] auto-recall タイムアウト` をログに出力。会話を継続 |
| 取得件数が 0 件 | 挿入しない（サイレント） |
| トークン上限超過 | 先頭3件を優先し超過分を切り捨て |

---

## 未確定事項

- **UND-04-02**: `store/distilled/en/` への英語シャドウ出力の運用方針（日英比率・index-en への連携）は A/B 評価後に spec 改訂で確定する。現時点では「両方出力する」を仕様とし、比率最適化はしない。
- **UND-04-04**: auto-recall の実装タイミングは「実装条件ゲート」（SPEC-04-04 参照）を人間が確認後に決定する。ゲート通過前に impl-plan は作成しない。
