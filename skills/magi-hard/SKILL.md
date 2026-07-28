---
name: magi-hard
description: MAGI 6体（melchior→balthasar→casper→metatron→sandalphon→leliel）でPRレビューを行う。指摘をGitHubにコメント投稿する。Trigger: "/magi-hard", "magi-hard", "ハードレビュー", "PRをMAGIにレビューさせて"
---

# MAGI-HARD スキル

MAGI の6体を順次実行し、PR の全差分を深くレビューする。
各体は担当ドメインに専念し、ドメイン分離によって重複を防ぐ。
HIGH/MEDIUM 指摘を GitHub PR のインラインコメントとして投稿し、サマリも別途投稿する。

## 前提

- `gh` CLI が認証済み
- 作業中ブランチがリモートに push 済み
- 対象 PR が open 状態

## ステップ 1: PR 特定と差分取得

```bash
git branch --show-current
gh pr view --json number,headRefName,baseRefName,url,state
HEAD_SHA=$(gh api repos/$OWNER/$REPO/pulls/$PR_NUM --jq .head.sha)
```

- closed / merged の場合は「PR はすでに closed です」と報告して終了
- PR 番号を `$PR_NUM`、リポジトリを `$OWNER/$REPO`、HEAD コミットを `$HEAD_SHA` として保持

PR の全差分を取得：

```bash
DIFF=$(gh pr diff $PR_NUM 2>/dev/null)
# ロールプレイ指示ファイルを除外する（各MAGIでも防御的再フィルタを行う二層構造）
DIFF=$(printf '%s\n' "$DIFF" | bash scripts/magi-diff-filter.sh)
```

差分が空の場合は「差分がありません」と報告して終了。

## ステップ 2: $IMPACT_CONTEXT 生成

```bash
IMPACT_CONTEXT=$(bash scripts/magi-impact-context.sh "$DIFF" 2>/dev/null || true)
```

失敗時は空文字で続行（中断しない）。

## ステップ 3.1: MELCHIOR 実行（最初）

`/melchior` スキルの手順に従い、`$DIFF` を渡してレビューを実行する。
実行が**完全に完了**した後、結果を `$MELCHIOR_RESULT` として保持してからステップ 3.2 に進む。

## ステップ 3.2: BALTHASAR 実行（`$MELCHIOR_RESULT` 取得後）

`$MELCHIOR_RESULT` が得られたことを確認してから起動する。
`MAGI_IMPACT_CONTEXT="$IMPACT_CONTEXT"` を設定して `/balthasar` スキルの手順に従い、`$DIFF` を渡してレビューを実行する。
実行が**完全に完了**した後、結果を `$BALTHASAR_RESULT` として保持してからステップ 3.3 に進む。

## ステップ 3.3: CASPER 実行（`$BALTHASAR_RESULT` 取得後）

`$BALTHASAR_RESULT` が得られたことを確認してから起動する。
`/casper` スキルの手順に従い、`$DIFF` を渡してレビューを実行する。
実行が**完全に完了**した後、結果を `$CASPER_RESULT` として保持してからステップ 3.4 に進む。

## ステップ 3.4: METATRON 実行（`$CASPER_RESULT` 取得後）

`$CASPER_RESULT` が得られたことを確認してから起動する。
`/metatron` スキルの手順に従い、`$DIFF` を渡してレビューを実行する。
実行が**完全に完了**した後、結果を `$METATRON_RESULT` として保持してからステップ 3.5 に進む。

## ステップ 3.5: SANDALPHON 実行（`$METATRON_RESULT` 取得後）

`$METATRON_RESULT` が得られたことを確認してから起動する。
`/sandalphon` スキルの手順に従い、`$DIFF` を渡してレビューを実行する。
実行が**完全に完了**した後、結果を `$SANDALPHON_RESULT` として保持してからステップ 3.6 に進む。

## ステップ 3.6: LELIEL 実行（`$SANDALPHON_RESULT` 取得後）

`$SANDALPHON_RESULT` が得られたことを確認してから起動する。
`MAGI_IMPACT_CONTEXT="$IMPACT_CONTEXT"` を設定して `/leliel` スキルの手順に従い、`$DIFF` を渡してレビューを実行する。
実行が**完全に完了**した後、結果を `$LELIEL_RESULT` として保持してからステップ 4 に進む。

## ステップ 3.7: 指摘の正規化

6体の結果から**指摘ではない見出しを除外**する。以降のステップ（カウント・Codex 監査・投稿）はすべて除外後の結果を使う。

### 除外 1: `No findings` 見出し

見出しの本文が `No findings` のもの（例: `### [HIGH] No findings`）は指摘として扱わない。

ローカルLLMは「指摘がなければ No findings と明記せよ」という指示を、Assessment ではなく各重大度見出しに適用することがある。除外しないとサマリの件数が水増しされ、「No findings」というインラインコメントが PR に投稿される。

### 除外 2: few-shot 例文の引き写し

弱いモデルは `skills/<persona>/references/task-instruction.md` の `<EXAMPLES>` に置かれた
見本をそのまま出力することがある（実測: `llama3.1:8b` で 14/14 件が例文のコピー）。

**headline の一致だけを条件にしてはならない。** 各ペルソナの例文見出しは
`command injection via unquoted user input` のように**本物の脆弱性でも自然に出る**文言であり、
このステップは Codex 監査より前にあるため、ここで消すと監査にも人間にも渡らない。

除外するのは次の**両方**を満たす指摘に限る。

1. headline（`— ` 以降）が、担当ペルソナの `<EXAMPLES>` 内の見出しと一致する
   （ファイルパスと行番号は当然異なるので比較対象にしない。正規化して比較する）
2. **かつ** 次のいずれか
   - 指摘の本文が例文の本文を引き写している
   - `filepath` が例文の `filepath` と一致する（例: METATRON が `scripts/run.sh` や
     `config/settings.py` をそのまま出している）

参考: 各ペルソナの例文 filepath

| ペルソナ | 例文の filepath |
|---|---|
| MELCHIOR | `scripts/deploy.sh` / `lib/utils.sh` |
| BALTHASAR | `src/service.py` / `lib/db.py` |
| CASPER | `scripts/deploy.sh` / `scripts/build.sh` |
| METATRON | `scripts/run.sh` / `config/settings.py` |
| SANDALPHON | `migrations/001_drop_table.sql` / `scripts/start.sh` |
| LELIEL | `scripts/ollama-run.sh` |

> **「`filepath` が diff に存在しない」を除外根拠にしてはならない。**
> `magi-hard` は差分外の行を通常 PR コメントへフォールバックする設計を持っており（ステップ 6 の 422 フォールバック）、
> diff 外の path はそれだけでは誤りではない。

## ステップ 4: Codex 監査

6体の結果から HIGH/MEDIUM 指摘に finding ID を付与し、Codex で妥当性を検証する。

### 4-1. Finding ID の付与

6体の結果（`$MELCHIOR_RESULT`〜`$LELIEL_RESULT`）から HIGH/MEDIUM 指摘を抽出し、`M-001`, `M-002`, ... の形式で連番付与する。

```text
M-001: [HIGH] MELCHIOR — filepath:line — headline
M-002: [MEDIUM] BALTHASAR — filepath:line — headline
...
```

このリストを `$FINDING_LIST` として保持する（plain text）。
HIGH/MEDIUM 指摘が 0 件の場合は Codex 監査をスキップしてステップ 5 に進む。

### 4-2. Codex 監査の実行

```bash
MAGI_TMPDIR=$(mktemp -d)
```

`skills/magi-common/references/codex-audit.md`（repo 内）または `~/.claude/skills/magi-common/references/codex-audit.md` を Read ツールで読み込み、記載の手順に従って Codex を呼び出す。

- 入力: `$FINDING_LIST`（finding-list fence）+ `$DIFF`（diff-block fence）
- 出力: `$MAGI_TMPDIR/codex-audit.json`

### 4-3. 結果の判定

**監査は保険ではなく中核部品**。実測では最良のモデルでも指摘の 55% が誤検知であり、監査結果を
失ったまま投稿すると PR が誤検知で埋まる。**監査結果を信頼できないときはインライン投稿を行わない**
（fail-soft）。「監査が通った」と「監査結果が読めなかった」を区別せずに投稿するのは fail-open であり、
これを禁止する。

`$MAGI_TMPDIR/codex-audit.json` を検証し、`$POST_INLINE` を**必ず明示的に設定する**。

```bash
AUDIT_JSON="$MAGI_TMPDIR/codex-audit.json"
POST_INLINE=true
AUDIT_NOTE=""
FALSE_POSITIVE_IDS=""

if [ ! -f "$AUDIT_JSON" ]; then
  POST_INLINE=false
  AUDIT_NOTE="AUDIT_SKIPPED（監査結果ファイルが存在しない）"
elif jq -e 'type == "object" and has("error")' "$AUDIT_JSON" >/dev/null 2>&1; then
  POST_INLINE=false
  AUDIT_NOTE="AUDIT_ERROR（$(jq -r '.error // "unknown"' "$AUDIT_JSON" 2>/dev/null)）"
elif ! jq -e '
        type == "array" and length > 0
        and all(.[];
              type == "object"
              and (.id? | type) == "string"
              and (.verdict? | type) == "string"
              and (.verdict | IN("valid", "false_positive", "needs_human")))
      ' "$AUDIT_JSON" >/dev/null 2>&1; then
  POST_INLINE=false
  AUDIT_NOTE="AUDIT_ERROR（監査結果が期待する形式ではない）"
else
  # finding ID を過不足なくカバーしているか照合する。取りこぼした ID は
  # false_positive 判定を受けていないため、そのまま投稿すると監査を通さずに素通りする。
  EXPECTED_IDS=$(printf '%s\n' "$FINDING_LIST" | sed -nE 's/^(M-[0-9]+):.*/\1/p' | sort -u)
  ACTUAL_IDS=$(jq -r '.[].id' "$AUDIT_JSON" 2>/dev/null | sort -u)
  if [ "$EXPECTED_IDS" != "$ACTUAL_IDS" ]; then
    POST_INLINE=false
    AUDIT_NOTE="AUDIT_ERROR（finding ID が一致しない: 期待 $(printf '%s\n' "$EXPECTED_IDS" | grep -c . ) 件 / 実際 $(printf '%s\n' "$ACTUAL_IDS" | grep -c . ) 件）"
  else
    FALSE_POSITIVE_IDS=$(jq -r '.[] | select(.verdict == "false_positive") | .id' "$AUDIT_JSON" 2>/dev/null)
  fi
fi
```

判定の意味：

| `$POST_INLINE` | 条件 | ステップ 6 の動作 |
|---|---|---|
| `false` | ファイル不在（`AUDIT_SKIPPED`） | インライン投稿しない |
| `false` | `{"error":...}`（`AUDIT_ERROR`） | インライン投稿しない |
| `false` | 非空の JSON 配列でない（**空ファイルを含む**） | インライン投稿しない |
| `false` | 要素が object でない / `id` または `verdict` を欠く | インライン投稿しない |
| `false` | `verdict` が `valid` / `false_positive` / `needs_human` 以外 | インライン投稿しない |
| `false` | `$FINDING_LIST` の finding ID を過不足なくカバーしていない | インライン投稿しない |
| `true` | 上記すべてを満たす | `$FALSE_POSITIVE_IDS` を除いて投稿 |

`needs_human` は `valid` と同じく**投稿対象**とする（人間が判断できる形で PR に出す）。

ステップ 5 に進む。

## ステップ 5: サマリコメント投稿

6体のレビュー完了後、まず PR 全体に**サマリコメント**を1件投稿する。インライン指摘より先に投稿することで、レビュー全体像をレビュアーが把握しやすくなる。

```bash
SUMMARY_URL=$(gh api -X POST repos/$OWNER/$REPO/issues/$PR_NUM/comments \
  -f body="## MAGI-HARD レビュー完了

| ペルソナ | HIGH | MEDIUM | LOW |
|---------|------|--------|-----|
| MELCHIOR（コード品質・バグ） | N | M | K |
| BALTHASAR（設計・アーキテクチャ） | N | M | K |
| CASPER（ルール遵守） | N | M | K |
| METATRON（セキュリティ） | N | M | K |
| SANDALPHON（実行環境・デプロイ） | N | M | K |
| LELIEL（既存ソース影響） | N | M | K |

**HIGH: N件 / MEDIUM: M件 / LOW: K件**（LOW はインラインコメント対象外）

> 各行への指摘はインラインコメントとして続けて投稿します。対応完了後は各インラインコメントに返信してください（\`/pr-review-respond\` で自動化可能）

$AUDIT_NOTE が空でない場合はサマリ末尾に以下を追記する:
> ⚠ Codex 監査: \`$AUDIT_NOTE\`

Codex 監査で `false_positive` 除外が発生した場合は以下を追記する:
> Codex 監査除外: N件（誤検知と判定）" \
  --jq '.html_url')
```

### `$POST_INLINE` が `false` の場合

サマリ本文の末尾に以下を追記する。**指摘を捨てるのではなく、人間が取捨選択できる形で本文に載せる。**

```markdown
> ⚠ Codex 監査が実行できなかったため指摘は投稿せず以下に一覧表示する（理由: `$AUDIT_NOTE`）

<details><summary>未監査の指摘一覧（HIGH/MEDIUM）</summary>

M-001: [HIGH] MELCHIOR — filepath:line — headline
M-002: [MEDIUM] BALTHASAR — filepath:line — headline
...

</details>
```

一覧は `$FINDING_LIST` をそのまま使う。実測で指摘の 55% が誤検知であるため、
監査を経ていない指摘をインラインコメントとして PR に撒くことはしない。

## ステップ 6: GitHub インラインコメント投稿

**`$POST_INLINE` が `false` の場合はこのステップを丸ごとスキップし、ステップ 7 に進む。**
指摘はステップ 5 のサマリ本文に一覧表示済みであり、失われない。
`$AUDIT_NOTE` だけを付けて投稿を続けると、監査結果が無い状態で全件投稿する fail-open になる。

6体の結果から HIGH/MEDIUM 指摘を抽出し、**指摘ごとに個別の PR インラインコメント**として投稿する。
`$FALSE_POSITIVE_IDS` に含まれる finding ID（`false_positive` 判定済み）は投稿をスキップする。
> ⚠ ローカルLLMが英語で出力した場合は、コメント本文に使用する前に日本語に翻訳する。

### インラインコメントの投稿方法

各 HIGH/MEDIUM 指摘について、出力形式 `### [HIGH] ファイルパス:行番号 — 見出し` または `### [MEDIUM] ファイルパス:行番号 — 見出し` から `path` と `line` を抽出し、以下のコマンドで投稿する：

```bash
gh api -X POST repos/$OWNER/$REPO/pulls/$PR_NUM/comments \
  -f body="[MAGI-HARD] **[HIGH] MELCHIOR（コード品質・バグ）**

<指摘内容>" \
  -f path="scripts/example.sh" \
  -F line=17 \
  -f side="RIGHT" \
  -f commit_id="$HEAD_SHA" \
  --jq '.html_url'
```

コメント本文の形式：
```
[MAGI-HARD] **[HIGH] <ペルソナ名>（<観点>）** または **[MEDIUM] <ペルソナ名>（<観点>）**

<指摘の詳細内容>
```

### ラインが差分にない場合のフォールバック

指定した `line` が PR diff に含まれていない場合（API エラー `422`）は、インラインコメントの代わりに通常の PR コメントとして投稿する：

```bash
gh api -X POST repos/$OWNER/$REPO/issues/$PR_NUM/comments \
  -f body="[MAGI-HARD] **[HIGH/MEDIUM] <ペルソナ>** `ファイルパス:行番号`

<指摘内容>"
```

## ステップ 7: 結果のサマリ表示

```bash
# 監査が失敗した場合は raw 出力を確認できるよう $MAGI_TMPDIR を残す
if [ "$POST_INLINE" = "true" ]; then
  rm -rf "$MAGI_TMPDIR"
fi
```

ユーザーに以下を表示する：

```
## MAGI-HARD 完了

| ペルソナ | HIGH | MEDIUM | LOW |
|---------|------|--------|-----|
| MELCHIOR | N | M | K |
| BALTHASAR | N | M | K |
| CASPER | N | M | K |
| METATRON | N | M | K |
| SANDALPHON | N | M | K |
| LELIEL | N | M | K |

インラインコメント: N件投稿
サマリコメント: $SUMMARY_URL

次のアクション:
- 指摘への対応・返信: `/pr-review-respond` を実行
- 指摘なし・軽微な場合: マージ準備完了
```

`$POST_INLINE` が `false` の場合は「インラインコメント: N件投稿」の代わりに以下を表示する。
**監査が失敗したことを黙って成功として報告しない。**

```
インラインコメント: 投稿なし（⚠ Codex 監査が実行できなかったため）
  理由: $AUDIT_NOTE
  未監査の指摘 N 件はサマリコメント本文に一覧表示済み
```
