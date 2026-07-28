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

PR 全体で使う作業ディレクトリを作る：

```bash
MAGI_RUN_DIR=$(mktemp -d)
MAGI_RUN_DIR_OWNED=0   # このディレクトリは magi-hard が管理する。個々のペルソナに消させない
```

`$MAGI_RUN_DIR_OWNED=0` を明示するのは、`/metatron` を単独実行した直後の環境で
フラグが `1` のまま残っていると、**METATRON が magi-hard 管理のディレクトリを削除してしまう**ため
（`skills/metatron/SKILL.md` ステップ 2・8）。

> ⚠ **`$MAGI_TMPDIR` を PR 全体用に流用してはならない。**
> `$MAGI_TMPDIR` は 2 つの別用途で使われている変数で、どちらも PR 全体の寿命を持たない：
> `execution-steps.md` は**チャンクごとに** `mktemp -d` して `rm -rf` し、
> ステップ 4-2 は**監査用に**別途 `mktemp -d` する。
> PR 全体で持ち回るファイル（METATRON のプロンプトと raw 出力など）は `$MAGI_RUN_DIR` に置く。
> **ステップ 4-2 の `$MAGI_TMPDIR` は変更しない。**

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

> METATRON だけは Ollama ではなく **Codex** を使い、共通手順（`execution-steps.md`）に乗らない。
> チャンク分割せず 1 回で全差分をレビューする。`$MAGI_RUN_DIR` を使うのはこのため。
> 呼び出し元から見た `$METATRON_RESULT` の形は他ペルソナと同一なので、ステップ 3.7 以降は変わらない。

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
   - `filepath` が例文の `filepath` と一致し、**かつその `filepath` が今回の diff に存在しない**

2つ目の条件で diff 不在を要求するのは、**例文の filepath が実在しうる**ため。
METATRON の例文は `scripts/run.sh:23 — command injection via unquoted user input` だが、
diff が本当に `scripts/run.sh` に `eval $USER_INPUT` を追加したなら、同じ headline の
妥当な HIGH が出る。filepath 一致だけを根拠にすると、この本物を Codex 監査より前に消す。

> headline を例文からコピーしつつ filepath を diff 内のものに差し替え、本文を言い換えた
> ケースは、この条件では除外されず投稿経路に残る。**これは意図的な判断**で、
> 本物の指摘を消すより Codex 監査に判定を委ねるほうが安全なため。

参考: 各ペルソナの例文 filepath

| ペルソナ | 例文の filepath |
|---|---|
| MELCHIOR | `scripts/deploy.sh` / `lib/utils.sh` |
| BALTHASAR | `src/service.py` / `lib/db.py` |
| CASPER | `scripts/deploy.sh` / `scripts/build.sh` |
| METATRON | `scripts/run.sh` / `config/settings.py` |
| SANDALPHON | `migrations/001_drop_table.sql` / `scripts/start.sh` |
| LELIEL | `scripts/ollama-run.sh` |

> **「`filepath` が diff に存在しない」を単独の除外根拠にしてはならない。**
> `magi-hard` は差分外の行を通常 PR コメントへフォールバックする設計を持っており（ステップ 6 の 422 フォールバック）、
> diff 外の path はそれだけでは誤りではない。上記の条件 2 で diff 不在を使うのは、
> 「headline が例文と一致」「filepath が例文と一致」と**併せて**判定するためであり、単独では使わない。

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
**ステップ 6 が投稿するのはこのリストの各エントリであり、6体の raw 結果ではない。**
ここで ID を振ったものだけが監査を通り、投稿対象になる。

HIGH/MEDIUM 指摘が 0 件の場合は Codex 監査をスキップしてステップ 5 に進む。
このとき次を**明示的に設定する**。未設定のままステップ 6 に到達すると、
`$POST_INLINE` が `false` でないため投稿処理が走る解釈が残る。

```bash
POST_INLINE=true      # 監査失敗ではない。投稿対象が 0 件なだけ
AUDIT_NOTE=""
FALSE_POSITIVE_IDS=""
FINDING_LIST=""
```

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
  ACTUAL_IDS_ALL=$(jq -r '.[].id' "$AUDIT_JSON" 2>/dev/null | sort)
  ACTUAL_IDS=$(printf '%s\n' "$ACTUAL_IDS_ALL" | uniq)
  if [ "$ACTUAL_IDS_ALL" != "$ACTUAL_IDS" ]; then
    # 同一 ID が複数回現れると、矛盾する verdict（valid と false_positive）が同時に成立し、
    # どちらを採用したかで投稿結果が変わる。集合として一致していても成功にしない。
    POST_INLINE=false
    AUDIT_NOTE="AUDIT_ERROR（finding ID が重複している）"
  elif [ "$EXPECTED_IDS" != "$ACTUAL_IDS" ]; then
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

**上記の `-f body=` に渡す文字列の末尾へ、以下を組み込んでから投稿する。**
別コメントとして後から投稿するのではなく、同じサマリコメントの本文に含める。
これを忘れるとステップ 6 がスキップされる一方で本文にも指摘が入らず、**指摘が PR から消える**。

指摘を捨てるのではなく、人間が取捨選択できる形で本文に載せる。

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

**投稿対象は `$FINDING_LIST` の各エントリである。6体の raw 結果を再走査してはならない。**
raw 結果から抽出し直すと、ステップ 3.7 で除外した指摘が戻り、finding ID も対応付かないため
`$FALSE_POSITIVE_IDS` による除外が効かなくなる。

`$FINDING_LIST` の各行は `M-001: [HIGH] MELCHIOR — filepath:line — headline` の形式で、
finding ID・重大度・ペルソナ・path・line・見出しをすべて持つ。指摘の本文は 6体の結果から
対応する見出しを引いて使う。

各エントリを**個別の PR インラインコメント**として投稿する。
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

# PR 全体用の作業ディレクトリはここで片付ける（METATRON のプロンプトと raw 出力が入っている）
rm -rf "$MAGI_RUN_DIR"
unset MAGI_RUN_DIR MAGI_RUN_DIR_OWNED
```

**削除と `unset` は必ずセットで行う。** 変数を残すと、次回の実行や `/metatron` 単独実行が
**削除済みの stale なパスを引き継ぐ**（`skills/metatron/SKILL.md` ステップ 2 の分岐が
「呼び出し元所有」と誤判定する）。

**`$MAGI_RUN_DIR` は最後のステップまで消してはならない。** ステップ 3.4 の METATRON が
プロンプトと raw 出力を置く場所であり、途中で消すと後続の参照が壊れる。
逆にここで消さないと、PR の差分と検出結果が一時ディレクトリに残り続ける。

METATRON が失敗して Haiku フォールバックにも進めずレビューを中止した場合は、
`$MAGI_RUN_DIR` を**残してパスをユーザーに提示する**（`$MAGI_TMPDIR` と同じ扱い）。
**その場合もパス提示後に `unset MAGI_RUN_DIR MAGI_RUN_DIR_OWNED` する**
（ディレクトリは残すが変数は残さない）。

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
