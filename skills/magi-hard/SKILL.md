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
printf '%s\n' "$DIFF" > "$MAGI_RUN_DIR/pr.diff"
```

`$MAGI_RUN_DIR/pr.diff` は**ステップ 5（grounding）の第2引数**になる。
ここで書き出さないと grounding の呼び出しが毎回非ゼロになり、
**常時失敗経路へ落ちて全件 `unanchorable` になり、インライン補正が一度も機能しない**。

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
> `magi-hard` は差分外の行を通常 PR コメントへフォールバックする設計を持っており（ステップ 7 の退避経路）、
> diff 外の path はそれだけでは誤りではない。上記の条件 2 で diff 不在を使うのは、
> 「headline が例文と一致」「filepath が例文と一致」と**併せて**判定するためであり、単独では使わない。

### 正規化結果の書き出し

除外後の結果を `$MAGI_RUN_DIR/normalized.md` に書き出し、`$NORMALIZED_RESULTS` として保持する。

```bash
NORMALIZED_RESULTS="$MAGI_RUN_DIR/normalized.md"
```

**ステップ 4-1 で `$FINDINGS_TABLE` を組み立てる前に行うこと。**
3.7 の結果から直接 `$FINDINGS_TABLE` を組み立てて途中を保存しない実装にすると、
**JSON 生成や構造検証が壊れた瞬間に退避元が存在しなくなる**
（`$FINDINGS_TABLE` も `$FINDING_LIST` も使えないため、設計上ある退避経路が実装時に参照不能になる）。

## ステップ 4: Codex 監査

6体の結果から HIGH/MEDIUM 指摘に finding ID を付与し、Codex で妥当性を検証する。

### 4-1. Finding ID の付与と `$FINDINGS_TABLE` の生成

6体の結果（`$MELCHIOR_RESULT`〜`$LELIEL_RESULT`）から HIGH/MEDIUM 指摘を抽出し、`M-001`, `M-002`, ... の形式で連番付与する。

採番と同時に **`$FINDINGS_TABLE` を作る。これが finding に関する唯一の source of truth** であり、
`$FINDING_LIST` はここから導出する。

```bash
FINDINGS_TABLE="$MAGI_RUN_DIR/findings-table.json"
```

#### 表の形（grounding 前）

```json
{
  "schema_version": "1",
  "findings": [
    { "id": "M-001", "persona": "MELCHIOR", "severity": "HIGH",
      "headline": "unquoted variable causes word splitting",
      "body": "…複数行の raw 本文…",
      "original_path": "scripts/example.sh", "original_line": 17 }
  ]
}
```

| フィールド | 出所 |
|---|---|
| `id` / `persona` / `severity` / `headline` / **`body`（raw 本文）** | ステップ 3.7 の結果に採番して格納 |
| `original_path` / `original_line` | ステップ 3.7 の結果（**モデルの申告値**） |
| `anchored_path` / `anchored_line` / `side` / `anchor_status` | **ここでは入れない**（ステップ 5 が書き足す） |

**`anchored_*` をここで初期投入してはならない。** 未検証の位置をステップ 7 が読む余地が出る。
逆に構造検証で `anchored_*` を必須にしてもならない（全件が検証失敗に倒れる）。

**物理形式は JSON ファイルとする。TSV / Markdown table / 1行1finding にしてはならない。**
raw 本文は複数行・箇条書き・`|`・コードフェンスを含みうるため、行指向の形式では
本文中の改行や区切り文字で行が壊れ、parse error で全件が失敗経路に落ちるか、
**別 ID の body / anchor を同じ行として扱う**。JSON 文字列なら改行も区切り文字もそのまま保持でき、
escaping は `jq` に任せられる。

#### `$FINDING_LIST` は表から導出する

```text
ステップ 3.7 の結果 → $FINDINGS_TABLE（採番・body・original_* を格納）
                            ↓ 各行を整形
                     $FINDING_LIST（plain text）
```

```text
M-001: [HIGH] MELCHIOR — filepath:line — headline
M-002: [MEDIUM] BALTHASAR — filepath:line — headline
...
```

`filepath:line` には **`original_path`:`original_line`** を使う（常に存在する）。
形式は変更しない。監査（4-2 / 4-3）の入出力契約・ID 母集合・検証条件も変更しない。

**両者を別々に組み立ててはならない。** 突合による検証では **`body` の取り違えを検出できない**。
`$FINDING_LIST` は body を持たないため、metadata が一致していて `body` だけ別 finding のもの、
という表は**どんな突合も通過する**。監査は `$FINDING_LIST` を見て `M-001` を `valid` と判定し、
ステップ 7 は表から `M-001` の（別 finding の）本文を読んで投稿する。
導出関係にすれば、**metadata と body が同じ行から出ることが構造的に保証される**（突合が不要になる）。

#### 表の構造検証（この直後に必ず行う）

導出元が壊れていれば下流すべてが壊れるため、ここで検証する。

- `findings` が**配列**であること（**空配列は正常**。下記の 0 件経路で使う）
- `id` が重複していないこと
- 各要素が必須フィールド（`id` / `persona` / `severity` / `headline` / `body` /
  `original_path` / `original_line`）を持ち、型が正しいこと
  （`original_line` は正の整数、`body` は非空文字列）

```bash
jq -e '
      .findings | type == "array"
      and ([.[].id] | length) == ([.[].id] | unique | length)
      and all(.[];
            (.id? | type) == "string" and (.id | length) > 0
            and (.persona? | type) == "string" and (.persona | length) > 0
            and (.severity? | type) == "string" and (.severity | length) > 0
            and (.headline? | type) == "string" and (.headline | length) > 0
            and (.body? | type) == "string" and (.body | length) > 0
            and (.original_path? | type) == "string" and (.original_path | length) > 0
            and (.original_line? | type) == "number"
            and (.original_line | floor) == .original_line and .original_line > 0)
    ' "$FINDINGS_TABLE" >/dev/null 2>&1
```

検証を通ったら次を設定してステップ 4-2 に進む。

```bash
BLOCK_LAYER=""        # $POST_INLINE=false の理由を層で区別する。true のときは参照しない
GROUNDING_NOTE=""     # anchor 層の状態。$AUDIT_NOTE とは別変数にする
```

#### 構造検証に失敗した場合（ファイル不在 / JSON でない / `findings` が配列でない / 上記を満たさない）

```bash
POST_INLINE=false
BLOCK_LAYER=structure
GROUNDING_NOTE=""
AUDIT_NOTE=""
FALSE_POSITIVE_IDS=""
MAGI_TMPDIR=""        # 4-2 を通らないので作られない
```

そのうえで次の順に進む。

1. **ステップ 4-2 / 4-3（Codex 監査）を丸ごとスキップする。**
   監査の入力は `$FINDING_LIST` だが、それは表から導出するため**表が壊れていれば存在しない**。
   「4-2 / 4-3 は無変更」は**正常系での話**であり、この失敗経路ではスキップする。
   守ろうとして進むと、**入力なしで監査経路に入るか、空の `$FINDING_LIST` を参照して空一覧になる**
2. **ステップ 5（grounding）もスキップする**（入力が無い）
3. **ステップ 6（サマリ投稿）で `$NORMALIZED_RESULTS` を載せる。**
   表が読めないとステップ 7 は `body` も `original_*` も取れず、「全件 `unanchorable` として
   通常 PR コメントに出す」を実行できない。`$FINDING_LIST` も導出不能なので退避元に使えない。
   **実行可能な唯一の退避元はステップ 3.7 の結果**である
4. **ステップ 7（インライン投稿）はスキップする**
5. ステップ 8 の表示にも同じ旨を出す

> **これは grounding スクリプトの失敗とは別の経路。**
> - **表が読めない** → 投稿に必要なデータが無い → `POST_INLINE=false`（サマリのみ）
> - **表は読めるが grounding が失敗** → 位置情報だけが無い → 全件 `unanchorable`（通常 PR コメント）

#### HIGH/MEDIUM 指摘が 0 件の場合

Codex 監査とステップ 5（grounding）をスキップしてステップ 6 に進む。
このとき次を**明示的に設定する**。未設定のままステップ 7 に到達すると、
`$POST_INLINE` が `false` でないため投稿処理が走る解釈が残る。

```bash
POST_INLINE=true      # 監査失敗ではない。投稿対象が 0 件なだけ
BLOCK_LAYER=""
AUDIT_NOTE=""
GROUNDING_NOTE=""
FALSE_POSITIVE_IDS=""
FINDING_LIST=""
MAGI_TMPDIR=""        # 4-2 を通らないので作られない。ステップ 8 の後片付けが参照する
printf '{"schema_version":"1","findings":[]}\n' > "$FINDINGS_TABLE"
```

**`MAGI_TMPDIR=""` を落としてはならない。** `$MAGI_TMPDIR` は 4-2 で初めて作られるが、
この経路は 4-2 を通らない。`$POST_INLINE` は `true` のままなので
**ステップ 8 の `rm -rf "$MAGI_TMPDIR"` が未設定変数を参照する**。

**空配列を構造検証で弾いてはならない。** 本来の「指摘なし」正常経路が
fail-soft 経路として扱われ、grounding 失敗扱いになる。

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
  BLOCK_LAYER=audit
  AUDIT_NOTE="AUDIT_SKIPPED（監査結果ファイルが存在しない）"
elif jq -e 'type == "object" and has("error")' "$AUDIT_JSON" >/dev/null 2>&1; then
  POST_INLINE=false
  BLOCK_LAYER=audit
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
  BLOCK_LAYER=audit
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
    BLOCK_LAYER=audit
    AUDIT_NOTE="AUDIT_ERROR（finding ID が重複している）"
  elif [ "$EXPECTED_IDS" != "$ACTUAL_IDS" ]; then
    POST_INLINE=false
    BLOCK_LAYER=audit
    AUDIT_NOTE="AUDIT_ERROR（finding ID が一致しない: 期待 $(printf '%s\n' "$EXPECTED_IDS" | grep -c . ) 件 / 実際 $(printf '%s\n' "$ACTUAL_IDS" | grep -c . ) 件）"
  else
    FALSE_POSITIVE_IDS=$(jq -r '.[] | select(.verdict == "false_positive") | .id' "$AUDIT_JSON" 2>/dev/null)
  fi
fi
```

判定の意味：

| `$POST_INLINE` | 条件 | ステップ 7 の動作 |
|---|---|---|
| `false` | ファイル不在（`AUDIT_SKIPPED`） | インライン投稿しない |
| `false` | `{"error":...}`（`AUDIT_ERROR`） | インライン投稿しない |
| `false` | 非空の JSON 配列でない（**空ファイルを含む**） | インライン投稿しない |
| `false` | 要素が object でない / `id` または `verdict` を欠く | インライン投稿しない |
| `false` | `verdict` が `valid` / `false_positive` / `needs_human` 以外 | インライン投稿しない |
| `false` | `$FINDING_LIST` の finding ID を過不足なくカバーしていない | インライン投稿しない |
| `true` | 上記すべてを満たす | `$FALSE_POSITIVE_IDS` を除いて投稿 |

`needs_human` は `valid` と同じく**投稿対象**とする（人間が判断できる形で PR に出す）。

**`POST_INLINE=false` に倒すすべての分岐で `BLOCK_LAYER=audit` を同時に立てる。**
立て忘れると、ステップ 6 が構造化失敗の文言（`$NORMALIZED_RESULTS` を出す分岐）へ流れる。
判定ロジックそのものは変更していない。

ステップ 5（grounding）に進む。

## ステップ 5: grounding（アンカーの確認と補正）

**`$POST_INLINE` が `false` の場合はこのステップを丸ごとスキップし、ステップ 6 に進む。**
HIGH/MEDIUM 指摘が 0 件の場合も同様にスキップする（4-1 で `$GROUNDING_NOTE=""` を設定済み）。

grounding は **監査の代替ではなく補助検査**である。担当するのは
**アンカーの確認と行ズレの補正**（`ok` / `corrected` / `unanchorable` の判定）だけで、
**semantic な妥当性判定と、幻覚の断定・finding の除外は行わない**（どちらも Codex 監査の責務）。

> **grounding は finding を1件も消さない。`dropped` という状態を持たない。**
> 引用候補が全部見つからなくても、それを幻覚と断定してはならない。
> 「`subprocess.run([...])` に置き換えるべき」のように**修正案だけ**をコードスパンにする
> 妥当な指摘は普通にあり、その修正案は diff にも作業ツリーにも存在しない。
> 「全候補が不在＝幻覚」は成立しない。**アンカーできなければ通常 PR コメントへ退避するだけ**にする。

```bash
GROUNDING_NOTE=""
ANCHORS_JSON="$MAGI_RUN_DIR/anchors.json"
if bash scripts/magi-ground-findings.sh "$FINDINGS_TABLE" "$MAGI_RUN_DIR/pr.diff" > "$ANCHORS_JSON" 2>/dev/null; then
  GROUNDING_OK=true
else
  GROUNDING_OK=false
fi
```

`anchors` の各要素は次の形をとる。

```json
{ "schema_version": "1",
  "anchors": [
    { "id": "M-001", "anchored_path": "scripts/example.sh", "anchored_line": 19,
      "side": "RIGHT", "anchor_status": "corrected" }
  ] }
```

| 状態 | `anchor_status` | 投稿 |
|---|---|---|
| 新側の行にアンカーできる | `ok` / `corrected` | インライン（`side: RIGHT`） |
| 旧側の行にアンカーできる | `ok` / `corrected` | インライン（`side: LEFT`） |
| **上記以外すべて**（位置を特定できない / 引用候補が空 / 全候補が不在 / context・作業ツリーでしか見つからない） | `unanchorable` | **通常 PR コメントへ退避** |

**旧側にしか無い引用を一律に落とさない。** 「削除された検証」「弱められたチェック」を
根拠とする指摘は正当であり、`side: LEFT` のインラインとして投稿できる。

**context / 作業ツリーの引用でアンカーできた場合も `unanchorable`**（インライン投稿しない）。
LELIEL は `<IMPACT_CONTEXT>` の呼び出し元証拠を根拠にする契約で、
根拠が diff 外の既存ファイルにあるのが正常系。PR diff 上に対応行が無いのでインラインは張れない。

### 5-1. 適用前の検証

`$GROUNDING_OK` が `true` でも、適用前に次を**すべて**検証する。
**1つでも満たさなければ 5-3 の失敗経路（全件 `unanchorable`）に倒す。**

- `anchors` の `id` 集合が `$FINDINGS_TABLE` の `id` 集合と**過不足なく・重複なく一致**する
- `anchor_status` が `ok` / `corrected` / `unanchorable` のいずれか（**未知の値を通さない**）
- `anchor_status` が `ok` / `corrected` のとき、`anchored_path` が非空文字列、
  `anchored_line` が正の整数、`side` が `RIGHT` / `LEFT` のいずれか（**前後空白を許さない**）
- `anchor_status` が `ok` / `corrected` のとき、`anchored_path` が `$DIFF` の変更対象に含まれ、
  **`anchored_line` が PR diff 上でコメント可能な位置**である
- `anchor_status` が `unanchorable` のとき、`anchored_*` / `side` は**参照しない**（値があっても無視する）

ID 集合だけを見ると、`anchor_status: "ok"` なのに `anchored_line` が `null`、`side` が `"RIGHT "`、
未知の `anchor_status: "partial"`、**別 finding の `anchored_path` / `anchored_line`** が入った JSON が
そのまま適用され、不正なインライン投稿・未定義分岐・誤行投稿になる。
新側行数の範囲内チェックだけでは投稿成功の根拠にならないので、コメント可能位置まで見る。

**`anchors` を部分採用してはならない。** 1件でも欠落・不一致があれば出力全体が信用できないため、
**残りの ID も含めて全件 `unanchorable`** にする。
欠落 ID だけ通常コメントへ退避し、残りをインライン投稿するのは不合格。

> **`id` で join する。入力順の一致に依存してはならない。**
> 順序 join では、スクリプトが1件でも要素を落とすと**後続 finding の anchor が前の ID にずれて入る**。
> `$FALSE_POSITIVE_IDS` を先に除外しても、`valid` / `needs_human` の別 ID に誤った anchor が
> 付いたままなので**間違った行へインラインが飛ぶ**。

### 5-2. 表への反映

検証を通ったら、`$FINDINGS_TABLE` の各 finding に `id` で join して
`anchored_path` / `anchored_line` / `side` / `anchor_status` を書き足す。

**フィールド名は `anchors` と同一にすること。** ずれると（例: `path` / `line` を読む）
補正位置が空扱いになり、5-1 の検証に落ちて全件 `unanchorable` になる。

反映後の形:

```json
{ "id": "M-001", "persona": "MELCHIOR", "severity": "HIGH",
  "headline": "unquoted variable causes word splitting",
  "body": "…複数行の raw 本文…",
  "original_path": "scripts/example.sh", "original_line": 17,
  "anchored_path": "scripts/example.sh", "anchored_line": 19,
  "side": "RIGHT", "anchor_status": "corrected" }
```

**`original_*` と `anchored_*` を1組のフィールドで兼ねてはならない。**
grounding が失敗した場合や `unanchorable` の場合、`anchored_*` は空になる。
兼ねると `$FINDING_LIST`（`filepath:line` が必須）もサマリも通常 PR コメントの場所表示も作れなくなる。

- `$FINDING_LIST` と通常 PR コメントの場所表示は **`original_*` を使う**（常に存在する）
- インラインコメントの位置は **`anchored_*` を使う**（`ok` / `corrected` のときのみ存在する）

### 5-3. grounding が失敗した場合

次のいずれか。

- スクリプトが非ゼロで終了した（`$GROUNDING_OK` が `false`）
- `anchors` が parse できない
- 5-1 の検証を1つでも満たさない

このとき:

- **`$FINDINGS_TABLE` の全 finding に `anchor_status: "unanchorable"` を書き足す**
  （`anchored_path` は空文字、`anchored_line` は 0、`side` は空文字）。
  **「全件 `unanchorable` として扱う」を心構えで済ませ、表に書かないではならない。**
  ステップ 7 は本文も位置も表から引き、`anchor_status` で分岐するため、
  フィールドが無いと**退避経路が未定義になり、指摘が PR から消える**
- インライン投稿はせず、通常 PR コメントに出す
- **`$POST_INLINE` は変更しない。** anchor 層の失敗は位置が確定しないだけで、投稿自体は可能
- **`$FALSE_POSITIVE_IDS` の除外と `$POST_INLINE=false` のスキップは通常どおり適用する。**
  「全 finding」は「監査を通過した投稿対象の全件」の意味であって、
  誤検知と判定されたものまで出すという意味ではない
- `$GROUNDING_NOTE` を設定する（無言でスキップしない）:

```bash
GROUNDING_NOTE="GROUNDING_FAILED（アンカーを確認できなかったため全件を通常 PR コメントとして投稿する）"
```

`$GROUNDING_NOTE` は**ステップ 6（サマリ投稿）の本文**と**ステップ 8（結果表示）**に出す。
grounding をサマリ投稿より前に置いたのはこのため。

> **`$AUDIT_NOTE` に相乗りしない。`$GROUNDING_NOTE` を別に用意する。**
> ステップ 4-3 は冒頭で `AUDIT_NOTE=""` を再代入する。grounding は 4-3 の後なので
> 上書きはされないが、同じ変数に混ぜると
> **「監査の状態」と「anchor 層の状態」が区別できなくなり、どちらの失敗か判別できない**。
> 変数を分けて層ごとに独立させる。

> **`$FINDINGS_TABLE` 自体が壊れているケースはここに含めない。** それは 4-1 の構造検証で
> `POST_INLINE=false` / `BLOCK_LAYER=structure` に倒しており、表が読めない以上
> この経路（通常 PR コメントへ退避）は実行できない。

### 層ごとの責務

| 層 | 失敗時の挙動 | `$POST_INLINE` |
|---|---|---|
| 構造化層（`$FINDINGS_TABLE` 生成・構造検証） | 4-2 / 4-3 とステップ 5・7 をスキップし、ステップ 6 で `$NORMALIZED_RESULTS` を出す | **`false`** |
| 監査層（Codex audit） | インライン投稿を一切しない。`$FINDING_LIST` をサマリに出す | **`false`** |
| anchor 層（grounding） | インラインは張らず全件を通常 PR コメントへ | **変更しない** |

anchor 層だけ `$POST_INLINE` を触らないのは、**位置が確定しないだけで投稿自体は可能**だから。

**これが fail-safe になる理由**: 「アンカーを確認できていない位置にインラインを張らない」で統一される。
grounding を素通りさせて元の `path:line` でインライン投稿すると、
**モデルが誤った行がたまたま diff 上でコメント可能だった場合に 422 も出ず、間違った行に付く**。
「取れなかった」と「何も無かった」を区別する思想は、監査層だけでなく anchor 層にも要る。

> **引用候補は「根拠」と「修正提案」を区別できない。** 提案側だけが実在して `ok` になり、
> 問題箇所でない行にインラインが付くケースは残る。これは**インライン位置の質の問題**であって
> fail-open ではない。指摘自体は Codex 監査が semantic に評価する。

## ステップ 6: サマリコメント投稿

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

$GROUNDING_NOTE が空でない場合はサマリ末尾に以下を追記する:
> ⚠ grounding: \`$GROUNDING_NOTE\`

Codex 監査で `false_positive` 除外が発生した場合は以下を追記する:
> Codex 監査除外: N件（誤検知と判定）" \
  --jq '.html_url')
```

### `$POST_INLINE` が `false` の場合

**上記の `-f body=` に渡す文字列の末尾へ、以下を組み込んでから投稿する。**
別コメントとして後から投稿するのではなく、同じサマリコメントの本文に含める。
これを忘れるとステップ 7 がスキップされる一方で本文にも指摘が入らず、**指摘が PR から消える**。

指摘を捨てるのではなく、人間が取捨選択できる形で本文に載せる。

**`$BLOCK_LAYER` で文言と一覧の出所を切り替える。**

| `$BLOCK_LAYER` | 立てた場所 | サマリの文言 | 一覧の出所 |
|---|---|---|---|
| `structure` | 4-1 の構造検証失敗 / 表 parse 失敗 | 「⚠ 指摘の構造化に失敗したため未整形のまま一覧表示する」 | `$NORMALIZED_RESULTS` |
| `audit` | 4-3 で `POST_INLINE=false` に倒すすべての分岐 | 「⚠ Codex 監査が実行できなかったため指摘は投稿せず以下に一覧表示する」 | `$FINDING_LIST` |

**構造化失敗をそのまま監査失敗の文言へ流してはならない。**
監査は実行すらしていないのに「監査が失敗した」と誤表示し、
`$FINDING_LIST` は導出不能なので一覧が空になり、**指摘が PR から消える**。

`$BLOCK_LAYER` が `audit` の場合:

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

`$BLOCK_LAYER` が `structure` の場合:

```markdown
> ⚠ 指摘の構造化に失敗したため未整形のまま一覧表示する

<details><summary>未整形の指摘一覧（HIGH/MEDIUM）</summary>

（$NORMALIZED_RESULTS の内容をそのまま貼る）

</details>
```

## ステップ 7: GitHub インラインコメント投稿

**`$POST_INLINE` が `false` の場合はこのステップを丸ごとスキップし、ステップ 8 に進む。**
指摘はステップ 6 のサマリ本文に一覧表示済みであり、失われない。
`$AUDIT_NOTE` だけを付けて投稿を続けると、監査結果が無い状態で全件投稿する fail-open になる。

> **`$POST_INLINE` は「このステップを実行するか」の gate** と定義する
> （「インラインコメントを張るか」ではない）。
> このステップは**インラインコメントと通常 PR コメントの両方**を担当し、
> `false` は**両方とも投稿しない**ことを意味する。
> anchor 層の失敗で `$POST_INLINE` を触らないのはこのため——**通常 PR コメントは出せるので
> ステップ 7 自体は実行する必要がある**。ここを「インラインを張るか」と読んで
> grounding 失敗時に `false` へ倒すと、**退避先の通常 PR コメントごと消える**。

**投稿対象は `$FINDING_LIST` の各 ID である。6体の raw 結果を再走査してはならない。**
raw 結果から抽出し直すと、ステップ 3.7 で除外した指摘が戻り、finding ID も対応付かないため
`$FALSE_POSITIVE_IDS` による除外が効かなくなる。

**本文と位置は `$FINDING_LIST` の各 ID で `$FINDINGS_TABLE` を引いて取る。**
body も anchor 情報も同じ表の同じ行から取るので、**取り違えが構造的に起きない**。

> 「本文は 6体の結果から対応する見出しを引いて使う」という従来のやり方は**廃止する**。
> 同一ペルソナが同じ headline を2件出すと、headline 照合は別 finding の本文を拾う。

### 投稿対象の判定順序

1. **`$FALSE_POSITIVE_IDS` に含まれる ID は投稿しない**（`false_positive` 判定済み）。
   これは `anchor_status` の分岐より**前**に適用する。
   anchor 情報の追加は投稿対象の判断を変えるものではない
2. 残った ID について `anchor_status` で**事前分岐**する（422 エラーを待たない）

| `anchor_status` | 経路 |
|---|---|
| `ok` / `corrected` | `anchored_path` / `anchored_line` / `side` でインラインコメント |
| `unanchorable` | **`anchored_line` / `side` を読まずに**通常 PR コメントへ退避 |
| **フィールドが無い** | `unanchorable` と同じ扱い（通常 PR コメントへ退避） |

最後の行は保険である。ステップ 5 は成功時も失敗時も全 finding に `anchor_status` を書き足すため、
正常系では発生しない。**ここを未定義のまま放置すると指摘が PR から消える**ので、明示する。

> ⚠ ローカルLLMが英語で出力した場合は、コメント本文に使用する前に日本語に翻訳する。

### インラインコメントの投稿方法

```bash
gh api -X POST repos/$OWNER/$REPO/pulls/$PR_NUM/comments \
  -f body="[MAGI-HARD] **[HIGH] MELCHIOR（コード品質・バグ）**

<指摘内容>" \
  -f path="scripts/example.sh" \
  -F line=19 \
  -f side="RIGHT" \
  -f commit_id="$HEAD_SHA" \
  --jq '.html_url'
```

`path` / `line` / `side` は表の `anchored_path` / `anchored_line` / `side` を使う。

コメント本文の形式：
```
[MAGI-HARD] **[HIGH] <ペルソナ名>（<観点>）** または **[MEDIUM] <ペルソナ名>（<観点>）**

<指摘の詳細内容>
```

### `unanchorable` の退避と 422 フォールバック

`anchor_status` が `unanchorable` の指摘は、通常の PR コメントとして投稿する。
場所表示には **`original_path`:`original_line`** を使う（`anchored_*` は空のため）。

```bash
gh api -X POST repos/$OWNER/$REPO/issues/$PR_NUM/comments \
  -f body="[MAGI-HARD] **[HIGH/MEDIUM] <ペルソナ>** `ファイルパス:行番号`

<指摘内容>"
```

インライン投稿が API エラー `422` を返した場合も、同じ形で通常 PR コメントへ退避する。

## ステップ 8: 結果のサマリ表示

```bash
# 監査が失敗した場合は raw 出力を確認できるよう $MAGI_TMPDIR を残す
# 空チェックを外してはならない。監査をスキップする経路（HIGH/MEDIUM 0件・構造検証失敗）では
# 4-2 を通らず $MAGI_TMPDIR が作られないまま、ここに到達する
if [ "$POST_INLINE" = "true" ] && [ -n "$MAGI_TMPDIR" ]; then
  rm -rf "$MAGI_TMPDIR"
fi

# PR 全体用の作業ディレクトリはここで片付ける
# （METATRON のプロンプトと raw 出力、pr.diff、normalized.md、findings-table.json、anchors.json）
rm -rf "$MAGI_RUN_DIR"
unset MAGI_RUN_DIR MAGI_RUN_DIR_OWNED
```

**削除と `unset` は必ずセットで行う。** 変数を残すと、次回の実行や `/metatron` 単独実行が
**削除済みの stale なパスを引き継ぐ**（`skills/metatron/SKILL.md` ステップ 2 の分岐が
「呼び出し元所有」と誤判定する）。

**`$MAGI_RUN_DIR` は最後のステップまで消してはならない。** ステップ 3.4 の METATRON が
プロンプトと raw 出力を置き、ステップ 5 の grounding が `$FINDINGS_TABLE` と `pr.diff` を読む場所であり、
途中で消すと後続の参照が壊れる。
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

`$POST_INLINE` が `false` の場合は「インラインコメント: N件投稿」の代わりに、
`$BLOCK_LAYER` に応じて以下を表示する。
**失敗したことを黙って成功として報告しない。**

`$BLOCK_LAYER` が `audit` の場合:

```
インラインコメント: 投稿なし（⚠ Codex 監査が実行できなかったため）
  理由: $AUDIT_NOTE
  未監査の指摘 N 件はサマリコメント本文に一覧表示済み
```

`$BLOCK_LAYER` が `structure` の場合:

```
インラインコメント: 投稿なし（⚠ 指摘の構造化に失敗したため）
  Codex 監査・grounding も未実行
  未整形の指摘はサマリコメント本文に一覧表示済み
```

`$GROUNDING_NOTE` が空でない場合は、上記に加えて以下を表示する
（`$POST_INLINE` が `true` でも表示する。無言でスキップしない）。

```
grounding: 失敗（⚠ $GROUNDING_NOTE）
  全 N 件を通常 PR コメントとして投稿した（インラインは 0 件）
```
