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
printf '%s\n' "$DIFF" > "$MAGI_RUN_DIR/pr.diff"
mkdir -p "$MAGI_RUN_DIR/raw"
FAILED_PERSONAS_JSON='[]'
printf '%s\n' "$FAILED_PERSONAS_JSON" > "$MAGI_RUN_DIR/failed-personas.json"
```

`$MAGI_RUN_DIR/pr.diff` は**ステップ 5（grounding）の第2引数**になる。
ここで書き出さないと grounding の呼び出しが毎回非ゼロになり、
**常時失敗経路へ落ちて全件 `unanchorable` になり、インライン補正が一度も機能しない**。

> ⚠ **`$MAGI_TMPDIR` を PR 全体用に流用してはならない。**
> `$MAGI_TMPDIR` は 2 つの別用途で使われている変数で、どちらも PR 全体の寿命を持たない：
> `execution-steps.md` は**チャンクごとに** `mktemp -d` して `rm -rf` し、
> ステップ 4-2 は**監査用に**別途 `mktemp -d` する。
> PR 全体で持ち回るファイル（`pr.diff` / `normalized.md` / `findings-table.json` / `anchors.json`）は `$MAGI_RUN_DIR` に置く。
> **ステップ 4-2 の `$MAGI_TMPDIR` は変更しない。**

## ステップ 2: $IMPACT_CONTEXT 生成

```bash
IMPACT_CONTEXT=$(bash scripts/magi-impact-context.sh "$DIFF" 2>/dev/null || true)
```

失敗時は空文字で続行（中断しない）。

**この後の全ペルソナ呼び出しで `MAGI_ORCHESTRATED=true` を設定する。**
これにより各ペルソナは
自分では Normalizer を呼ばず生の結果を返す。`magi-hard` がステップ 3.7 でまとめて
1 回の Normalizer 呼び出しにバッチ化する（呼び出し回数削減のため。モデルロード・推論のオーバーヘッドを削減する）。

```bash
MAGI_ORCHESTRATED=true
```

各ペルソナの呼び出し元は、実行の終了ステータスを `<PERSONA>_EXIT`、取得した結果テキストを
`<PERSONA>_RESULT` として保持する。Ollama呼び出しが `execution-steps.md` ステップ2の
`exit 1` 相当の分岐を通った場合は非0の終了ステータスを保持する。各呼び出しは `if ...; then ...; else ...; fi` 相当で捕捉し、非0終了を呼び出し元へ再送出せず、失敗しても次のペルソナへ進む。
各結果は次の共通処理で raw ファイルへ保存し、空結果または `NORMALIZE_SKIPPED` / `NORMALIZE_ERROR`
を含む結果も失敗として記録する。finding 0件を表す正常な非空結果は成功として扱う。

```bash
record_magi_persona_result() {
  local persona="$1"
  local result="$2"
  local exit_status="$3"
  local persona_key
  local raw_file
  local persona_failed=false

  persona_key=$(printf '%s' "$persona" | tr '[:upper:]' '[:lower:]')
  raw_file="$MAGI_RUN_DIR/raw/${persona_key}.txt"
  printf '%s' "$result" > "$raw_file"
  if [ "$exit_status" -ne 0 ] \
    || [ -z "$result" ] \
    || grep -aEq '^NORMALIZE_(SKIPPED|ERROR):' "$raw_file"; then
    persona_failed=true
  fi
  if [ "$persona_failed" = true ]; then
    FAILED_PERSONAS_JSON=$(jq --arg p "$persona" '. + [$p]' <<<"$FAILED_PERSONAS_JSON")
    printf '%s\n' "$FAILED_PERSONAS_JSON" > "$MAGI_RUN_DIR/failed-personas.json"
  fi
}
```

## ステップ 3.1: MELCHIOR 実行（最初）

`/melchior` スキルの手順に従い、`$DIFF` を渡してレビューを実行する。
実行が**完全に完了**した後、結果を `$MELCHIOR_RESULT` として保持してからステップ 3.2 に進む。
実行終了ステータスは `$MELCHIOR_EXIT` として保持し、成功・失敗を問わず次を実行してからステップ 3.2 に進む。

```bash
record_magi_persona_result "MELCHIOR" "$MELCHIOR_RESULT" "$MELCHIOR_EXIT"
```

## ステップ 3.2: BALTHASAR 実行（`$MELCHIOR_RESULT` 取得後）

`$MELCHIOR_RESULT` が得られたことを確認してから起動する。
`MAGI_IMPACT_CONTEXT="$IMPACT_CONTEXT"` を設定して `/balthasar` スキルの手順に従い、`$DIFF` を渡してレビューを実行する。
実行が**完全に完了**した後、結果を `$BALTHASAR_RESULT` として保持してからステップ 3.3 に進む。
実行終了ステータスは `$BALTHASAR_EXIT` として保持し、成功・失敗を問わず次を実行してからステップ 3.3 に進む。

```bash
record_magi_persona_result "BALTHASAR" "$BALTHASAR_RESULT" "$BALTHASAR_EXIT"
```

## ステップ 3.3: CASPER 実行（`$BALTHASAR_RESULT` 取得後）

`$BALTHASAR_RESULT` が得られたことを確認してから起動する。
`/casper` スキルの手順に従い、`$DIFF` を渡してレビューを実行する。
実行が**完全に完了**した後、結果を `$CASPER_RESULT` として保持してからステップ 3.4 に進む。
実行終了ステータスは `$CASPER_EXIT` として保持し、成功・失敗を問わず次を実行してからステップ 3.4 に進む。

```bash
record_magi_persona_result "CASPER" "$CASPER_RESULT" "$CASPER_EXIT"
```

## ステップ 3.4: METATRON 実行（`$CASPER_RESULT` 取得後）

`$CASPER_RESULT` が得られたことを確認してから起動する。
`/metatron` スキルの手順に従い、`$DIFF` を渡してレビューを実行する。
実行が**完全に完了**した後、結果を `$METATRON_RESULT` として保持してからステップ 3.5 に進む。
実行終了ステータスは `$METATRON_EXIT` として保持し、成功・失敗を問わず次を実行してからステップ 3.5 に進む。

```bash
record_magi_persona_result "METATRON" "$METATRON_RESULT" "$METATRON_EXIT"
```

## ステップ 3.5: SANDALPHON 実行（`$METATRON_RESULT` 取得後）

`$METATRON_RESULT` が得られたことを確認してから起動する。
`/sandalphon` スキルの手順に従い、`$DIFF` を渡してレビューを実行する。
実行が**完全に完了**した後、結果を `$SANDALPHON_RESULT` として保持してからステップ 3.6 に進む。
実行終了ステータスは `$SANDALPHON_EXIT` として保持し、成功・失敗を問わず次を実行してからステップ 3.6 に進む。

```bash
record_magi_persona_result "SANDALPHON" "$SANDALPHON_RESULT" "$SANDALPHON_EXIT"
```

## ステップ 3.6: LELIEL 実行（`$SANDALPHON_RESULT` 取得後）

`$SANDALPHON_RESULT` が得られたことを確認してから起動する。
`MAGI_IMPACT_CONTEXT="$IMPACT_CONTEXT"` を設定して `/leliel` スキルの手順に従い、`$DIFF` を渡してレビューを実行する。
実行が**完全に完了**した後、結果を `$LELIEL_RESULT` として保持してからステップ 3.7 に進む。
実行終了ステータスは `$LELIEL_EXIT` として保持し、成功・失敗を問わず次を実行してからステップ 3.7 に進む。

```bash
record_magi_persona_result "LELIEL" "$LELIEL_RESULT" "$LELIEL_EXIT"
```

## ステップ 3.7: 指摘の正規化

6体は`$MAGI_ORCHESTRATED=true`で実行済みのため、各自ではNormalizerを呼ばず生の結果（`$MELCHIOR_RESULT`/`$BALTHASAR_RESULT`/`$CASPER_RESULT`/`$METATRON_RESULT`/`$SANDALPHON_RESULT`/`$LELIEL_RESULT`、チャンクヘッダー込み）を返している。ここで失敗ペルソナの raw は除外し、成功したペルソナの結果だけを1回のバッチ呼び出しにまとめてNormalizerへ渡す（呼び出し回数削減のため。モデルロード・推論のオーバーヘッドを削減する）。

1. `MAGI_TMPDIR=$(mktemp -d)` で作業ディレクトリを作成する。
2. `$FAILED_PERSONAS_JSON` に含まれない成功ペルソナの raw ファイルだけを、それぞれ `=== PERSONA: <name> / CHUNK: <path> (<n>) ===` ヘッダーを保ったまま連結し、`$NORMALIZE_INPUT` として保持する。失敗ペルソナの raw ファイルは診断用に残すが、Normalizerには渡さない。

```bash
NORMALIZE_INPUT="$(
  for PERSONA in MELCHIOR BALTHASAR CASPER METATRON SANDALPHON LELIEL; do
    if jq -e --arg p "$PERSONA" 'index($p) == null' <<<"$FAILED_PERSONAS_JSON" >/dev/null 2>&1; then
      PERSONA_KEY=$(printf '%s' "$PERSONA" | tr '[:upper:]' '[:lower:]')
      cat "$MAGI_RUN_DIR/raw/${PERSONA_KEY}.txt"
      printf '\n'
    fi
  done
)"
```
3. `skills/magi-common/references/normalizer.md`（repo 内）または `~/.claude/skills/magi-common/references/normalizer.md` を Read ツールで読み込み、記載の手順に従ってNormalizerを実行する。
4. 成功した場合、`$MAGI_TMPDIR/normalizer.json` の内容を `$NORMALIZED_V2_JSON` として `$MAGI_RUN_DIR/normalized-v2.json` にコピーし保持する（`$MAGI_TMPDIR` はチャンク単位ではなくこのバッチ呼び出し専用なので、コピー後に削除してよい）。
5. 失敗（`NORMALIZE_SKIPPED`/`NORMALIZE_ERROR`）した場合は、`normalizer.md`の契約に従いHaiku fallbackを試みる。それでも失敗する場合は、ステップ4-1の構造検証失敗と同様の扱い（`BLOCK_LAYER=structure`相当とし、6体分は`$NORMALIZED_RESULTS`にraw結果をそのまま出す）とする。

### 正規化結果の書き出し

6体分の`normalized-v2.json`を人間可読な箇条書きに変換し、`$MAGI_RUN_DIR/normalized.md` に書き出し、`$NORMALIZED_RESULTS` として保持する。

```bash
NORMALIZED_RESULTS="$MAGI_RUN_DIR/normalized.md"
```

**ステップ 4-1 で `$FINDINGS_TABLE` を組み立てる前に行うこと。**
3.7 の結果から直接 `$FINDINGS_TABLE` を組み立てて途中を保存しない実装にすると、
**JSON 生成や構造検証が壊れた瞬間に退避元が存在しなくなる**
（`$FINDINGS_TABLE` も `$FINDING_LIST` も使えないため、設計上ある退避経路が実装時に参照不能になる）。

`$FINDINGS_TABLE`で使うのは`normalized-v2.json`（JSON）側であり、`normalized.md`はステップ6のフォールバック表示・デバッグ用の人間可読ログという位置づけ。

## ステップ 4: Codex 監査

6体の結果に finding ID を付与し、Codex で妥当性を検証する。

### 4-1. Finding ID の付与と `$FINDINGS_TABLE` の生成

`normalized-v2.json`（バッチNormalizer出力）の各要素を候補とする。**severityによる事前フィルタはしない**（全候補を採番、recall優先の設計方針。絞り込みは後述ステップ4-4に委ねる）。`severity`は暫定値`"UNRATED"`とする（ステップ4-4でCodexが`importance`を判定した後、`HIGH`/`MEDIUM`/`LOW`で上書きする）。`persona`はNormalizer出力の`persona`フィールドをそのまま使う。`original_path`/`original_line`はNormalizer出力の`path`/`line`（`line`が`null`の場合はそのまま`original_line: null`とする。捏造しない。ステップ5でアンカー不能扱いにする）。

```bash
PRE_ID_CANDIDATES="$MAGI_RUN_DIR/pre-id-candidates.json"
```

`$PRE_ID_CANDIDATES` は、6体分の候補を連結した単一の JSON 配列として保持する。`normalized-v2.json` の各要素について `path` を `original_path`、`line` を `original_line` にリネームし（元の `path`/`line` キーは残さない）、`severity: "UNRATED"` を持つ同じ形の object にする。

#### 採番前の重複統合（機械的完全一致dedup）

`skills/magi-common/references/normalizer.md` 15行目は、重複除去を Normalizer の責務ではなく呼び出し元の責務としている。ここで共通dedupスクリプトを呼び出して実装する。

6体分をマージした **pre-ID candidate list** に対し、採番前に機械的な重複統合を1回だけ行う。重複キーは `persona` / `headline` / `original_path` / `original_line` / `evidence` / `body` の6フィールドの byte-for-byte 完全一致とし、6つすべてが一致する場合だけ同一候補として扱う。`body` を含めるのは、同じ persona / line / headline / evidence を共有しても Problem / Breakage の内容が異なる正当な別 finding を潰さないため。

dedup は **同一 `persona` 内だけ**で行う。異なる persona が同じ場所を指すことは有用な corroboration signal なので、persona をまたいで統合してはならない。

先に出た候補を残し、first-occurrence order を維持する。`jq unique_by` は order-stable ではないため使わず、`reduce` で実装する。

`evidence: null` と `evidence: ""` は別値として扱う。空文字列は後続の構造検証で失敗するが、dedup キー作成時に `null` を `""` や文字列 `"null"` へ変換してはならない。

```bash
DEDUPED_CANDIDATES="$MAGI_RUN_DIR/deduped-candidates.json"
```

`$DEDUPED_CANDIDATES` は、`$PRE_ID_CANDIDATES` と同じ field shape の JSON 配列として、重複統合後・採番前の候補だけを保持する。

```bash
bash scripts/review-dedup-findings.sh persona,headline,original_path,original_line,evidence,body "$PRE_ID_CANDIDATES" > "$DEDUPED_CANDIDATES"
```

この dedup は **`M-001`, `M-002`, ... の採番より前**、かつ後述の **表の構造検証より前**に行う。構造検証の意味は変えず、重複統合済みの小さい配列を同じ条件で検証する。

`$DEDUPED_CANDIDATES` の各候補を`M-001`, `M-002`, ... の形式で連番付与する（persona間の採番順序は問わない）。

```bash
FINDINGS_TABLE="$MAGI_RUN_DIR/findings-table.json"
```

`$FINDINGS_TABLE` は `$DEDUPED_CANDIDATES` の各候補に採番した `id` を加えて組み立てる。採番と同時に **`$FINDINGS_TABLE` を作る。これが finding に関する唯一の source of truth** であり、
`$FINDING_LIST` はここから導出する。

#### 表の形（grounding 前）

```json
{
  "schema_version": "1",
  "findings": [
    { "id": "M-001", "persona": "MELCHIOR", "severity": "UNRATED",
      "headline": "unquoted variable causes word splitting",
      "body": "…複数行の raw 本文…",
      "evidence": "$cmd $arg",
      "original_path": "scripts/example.sh", "original_line": 17 },
    { "id": "M-002", "persona": "CASPER", "severity": "UNRATED",
      "headline": "direct git commit bypasses /commit skill rule",
      "body": "…複数行の raw 本文…",
      "evidence": "git commit -m \"$MESSAGE\"",
      "original_path": "scripts/example.sh", "original_line": 21 }
  ]
}
```

| フィールド | 出所 |
|---|---|
| `id` / `persona` / `severity` / `headline` / **`body`（raw 本文）** | ステップ 3.7 の結果に採番して格納 |
| `evidence` | `normalized-v2.json`の`evidence`をそのまま格納（nullならnull） |
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

`filepath:line` には **`original_path`:`original_line`** を使う（`original_path`は常に存在する）。
`original_line`が`null`のfindingは`filepath:?`のように`line`部分を`?`で表す（数値の`0`は使わない。`0`は「1行目を指す誤った値」との区別がつかなくなるため）。
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
- 各要素が必須フィールド（`id` / `persona` / `severity` / `headline` / `body` / `evidence` /
  `original_path` / `original_line`）を持ち、型が正しいこと
  （`original_line` は正の整数、または`null`——Normalizerがline番号を確信を持って
  抽出できなかった場合。`null`は「値が無い」ことを表し、`0`等の数値で代用してはならない
  （`0`は「行1を指す誤った値」と区別できなくなる）。`body` は非空文字列。`evidence` は非空文字列または`null`）

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
            and has("evidence")
            and (((.evidence? | type) == "string" or (.evidence? | type) == "null")
                 and ((.evidence? | type) != "string" or (.evidence | length) > 0))
            and (.original_path? | type) == "string" and (.original_path | length) > 0
            and ((.original_line? | type) == "null"
                 or ((.original_line? | type) == "number"
                     and (.original_line | floor) == .original_line and .original_line > 0)))
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
IMPORTANCE_NOTE=""
FALSE_POSITIVE_IDS=""
ARTIFACT_NOTE="ARTIFACT_SKIPPED（findings tableの構造検証に失敗したため canonical artifact を生成していない）"
MAGI_TMPDIR=""        # 4-2 を通らないので作られない
MAGI_TMPDIR_IMPORTANCE=""  # 4-4 を通らないので作られない
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

#### 指摘が 0 件の場合

4-5（canonical findings artifact の出力）は、4-1完了時点で表が構造的に正常であるため、この分岐でも実行する。
Codex 監査とステップ 5（grounding）をスキップしてステップ 6 に進む。
このとき次を**明示的に設定する**。未設定のままステップ 7 に到達すると、
`$POST_INLINE` が `false` でないため投稿処理が走る解釈が残る。

```bash
POST_INLINE=true      # 監査失敗ではない。投稿対象が 0 件なだけ
BLOCK_LAYER=""
AUDIT_NOTE=""
IMPORTANCE_NOTE=""
GROUNDING_NOTE=""
FALSE_POSITIVE_IDS=""
FINDING_LIST=""
MAGI_TMPDIR=""        # 4-2 を通らないので作られない。ステップ 8 の後片付けが参照する
MAGI_TMPDIR_IMPORTANCE=""  # 4-4 を通らないので作られない。ステップ 8 の後片付けが参照する
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
- **findingについては`body`（`$FINDINGS_TABLE`の該当行から取得）も`context-block`ラベル付きfenceとして追加で渡す。** DETECTION NOTES契約ではProblem/Breakageこそが実質的な指摘内容であり、headlineだけでは判定材料が不足するため。
- **`severity`が`UNRATED`のfindingも、severity不在を理由に除外せず全件監査対象にする**（`$FINDING_LIST`の抽出自体がseverityでフィルタしないため、自然にこの通りになる）。
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
| `true` | 上記すべてを満たす | `$BLOCK_IDS` に含まれる ID（`final_gate == "block"`）だけを投稿 |

`needs_human` は `valid` と同じく**投稿対象**とする（人間が判断できる形で PR に出す）。

**`POST_INLINE=false` に倒すすべての分岐で `BLOCK_LAYER=audit` を同時に立てる。**
立て忘れると、ステップ 6 が構造化失敗の文言（`$NORMALIZED_RESULTS` を出す分岐）へ流れる。
判定ロジックそのものは変更していない。

`$POST_INLINE` が `false` の場合でも、4-5（canonical findings artifact の出力）は4-1完了時点で表が構造的に正常であるため実行する。
その後、ステップ 4-4 をスキップしてステップ 5（実質的にはステップ 6）へ進む。
このとき `MAGI_TMPDIR_IMPORTANCE=""`（4-4 を通らないので作られない）と `IMPORTANCE_NOTE=""` を設定する。

### 4-4. Codex 重要度判定

**「本物の指摘か」（4-2/4-3の妥当性判定）と「投稿する価値があるか」（重要度）は別の問いであり、明示的に別ステップとして分離する。**

**対象:** `$FINDINGS_TABLE`のうち`severity == "UNRATED"`かつステップ4-3で`valid`または`needs_human`と判定されたfindingのみ。`false_positive`のfindingも対象外（無駄なCodex呼び出しを避ける。`severity`は`UNRATED`のまま残るが、ステップ7で`$FALSE_POSITIVE_IDS`により別途除外されるため実害はない）。

対象findingが0件の場合でも、4-5（canonical findings artifact の出力）は4-1完了時点で表が構造的に正常であるため実行する。
その後、`MAGI_TMPDIR_IMPORTANCE=""` と `IMPORTANCE_NOTE=""` を設定し、このステップをスキップしてステップ5へ進む。

**`$MAGI_TMPDIR`（4-2で作成済み）を再代入してはならない。** 同じ変数名で `mktemp -d` すると
4-2で作った監査用tmpdirへの参照が失われ、ステップ8の `rm -rf "$MAGI_TMPDIR"` が
4-2のtmpdir（`codex-audit.json`等）を永久にリークさせる。**別変数 `$MAGI_TMPDIR_IMPORTANCE` を使う。**

```bash
MAGI_TMPDIR_IMPORTANCE=$(mktemp -d)
```

`skills/magi-common/references/codex-importance.md`（repo 内）または `~/.claude/skills/magi-common/references/codex-importance.md` を Read ツールで読み込み、記載の手順に従って Codex を呼び出す（手順中の `$MAGI_TMPDIR` は `$MAGI_TMPDIR_IMPORTANCE` に読み替える）。

- 入力: 対象findingの`id`/`headline`/`body`（`$IMPORTANCE_INPUT`）+ 該当ペルソナの`review-criteria.md`の`## Severity Standards`節（`$SEVERITY_STANDARDS`）
- 出力: `$MAGI_TMPDIR_IMPORTANCE/codex-importance.json`

**成功した場合:** `$FINDINGS_TABLE`の該当findingの`severity`を、返された`importance`値（`HIGH`/`MEDIUM`/`LOW`）で上書きする。

**失敗した場合（`IMPORTANCE_SKIPPED`/`IMPORTANCE_ERROR`）:** 対象findingの`severity`は`UNRATED`のまま残す。`BLOCK_LAYER=importance`を設定する（`$POST_INLINE`自体は`true`のまま変更しない——監査を通過した他のfindingの投稿は妨げない）。

```bash
IMPORTANCE_NOTE=""
if [ ! -f "$MAGI_TMPDIR_IMPORTANCE/codex-importance.json" ] || jq -e 'type == "object" and has("error")' "$MAGI_TMPDIR_IMPORTANCE/codex-importance.json" >/dev/null 2>&1; then
  BLOCK_LAYER=importance
  IMPORTANCE_NOTE="IMPORTANCE_FAILED（重要度判定に失敗したため、対象指摘はサマリのみに記載しインライン投稿しない）"
fi
```

対象findingが0件でこのステップ自体をスキップした場合は `MAGI_TMPDIR_IMPORTANCE=""` としておく（ステップ8の後片付けが未設定変数を参照しないように）。

`$MAGI_TMPDIR_IMPORTANCE`は削除せず、失敗時は調査可能な状態を保つ（`codex-audit.md`と同様）。`$IMPORTANCE_NOTE`はステップ6のサマリと8の結果表示に出す。

4-5（canonical findings artifact の出力）は、4-1完了時点で表が構造的に正常であるため、この通常経路でも実行する。
4-5 の後、ステップ 4-6（gate 判定の統合）に進む。

### 4-5. canonical findings artifact の出力

4-1 完了時点の `$FINDINGS_TABLE`（dedup・採番済み、`anchored_*` 未投入）を入力として、
共通変換スクリプトを呼び出し、`$MAGI_RUN_DIR/findings-artifact.json` に保存する。
4-4 で `severity` が入った後に実行しても artifact に `severity` は含まれないため、内容は4-1時点と同じである。

ステップ3で作成した `$MAGI_RUN_DIR/failed-personas.json` を渡し、ペルソナ単位の検出完了状態を canonical artifact に反映する。

```bash
ARTIFACT_NOTE=""
ARTIFACT_FILE="$MAGI_RUN_DIR/findings-artifact.json"
rm -f -- "$ARTIFACT_FILE"
ARTIFACT_EXIT=0
bash scripts/review-findings-artifact.sh magi "$FINDINGS_TABLE" "$MAGI_RUN_DIR/failed-personas.json" \
  >"$ARTIFACT_FILE" 2>"$MAGI_RUN_DIR/findings-artifact.err" || ARTIFACT_EXIT=$?
if [ "$ARTIFACT_EXIT" -ne 0 ] \
  || [ ! -s "$ARTIFACT_FILE" ] \
  || ! jq -e 'type == "object" and .schema_version == "1" and .engine == "magi"' \
    "$ARTIFACT_FILE" >/dev/null 2>&1; then
  ARTIFACT_NOTE="ARTIFACT_FAILED（canonical artifact の生成に失敗した）"
fi
```

変換スクリプトが非0終了、出力ファイルが無い、出力 JSON が不正、または自己検証に落ちた場合も
同じ `$ARTIFACT_NOTE` に集約する。変換に失敗しても既存レビュー本体は止めない。
ステップ8の結果表示では、`$ARTIFACT_NOTE` が空でない場合に次を表示する。

### 4-6. gate 判定の統合

このステップは、4-3 が `$POST_INLINE=false` に設定済みか、4-4 が実行済みか、または重要度判定対象が0件で4-4をスキップしたかにかかわらず、常に実行する。`scripts/review-adjudicate-findings.sh` は `$AUDIT_JSON` の形状と finding ID の完全性を消費者側で独立に再検証するため、4-3 が先に検証済みでもこの呼び出しを省略しない。4-3/4-4 が失敗または未実行でも、妥当性結果が信頼できない場合は `validity_global_failure:true` となり、後続で `final_gate:"block"` の finding を作らない fail-closed 経路になる。

まず `$FINDINGS_TABLE` から adjudication 用のメタデータを作る。MAGI findings には自己申告 gate がないため、`reported_gate` は常に `null` とする。

```bash
MAGI_TMPDIR_ADJUDICATE="$MAGI_RUN_DIR/adjudicate"
mkdir -p "$MAGI_TMPDIR_ADJUDICATE"
ADJUDICATE_META_FILE="$MAGI_TMPDIR_ADJUDICATE/findings-meta.json"
jq '[.findings[] | {id, source_persona: .persona, reported_gate: null}]' "$FINDINGS_TABLE" \
  > "$ADJUDICATE_META_FILE" || return 1
```

4-4 が実行されて `$MAGI_TMPDIR_IMPORTANCE` が空でない場合は、そのディレクトリの `codex-importance.json` を直接渡す。4-4 が0件対象または4-3の失敗でスキップされた場合は、重要度判定が不要な正常な空配列として新しいファイルを作り、それを渡す。

```bash
if [ -n "${MAGI_TMPDIR_IMPORTANCE:-}" ]; then
  IMPORTANCE_RESULT_FOR_ADJUDICATE="$MAGI_TMPDIR_IMPORTANCE/codex-importance.json"
else
  IMPORTANCE_RESULT_FOR_ADJUDICATE="$MAGI_TMPDIR_ADJUDICATE/empty-importance.json"
  printf '%s\n' '[]' > "$IMPORTANCE_RESULT_FOR_ADJUDICATE"
fi
```

妥当性結果には、4-2で設定した `$AUDIT_JSON`（`$MAGI_TMPDIR/codex-audit.json`）をそのまま渡す。4-2が実行されなかった場合やファイルが存在しない場合もパスは変換せず、adjudication 層が読み取り失敗を妥当性失敗として扱う。

```bash
AUDIT_JSON="${AUDIT_JSON:-${MAGI_TMPDIR:-}/codex-audit.json}"
ADJUDICATION_RESULT="$MAGI_TMPDIR_ADJUDICATE/adjudication-result.json"
ADJUDICATE_EXIT=0
bash scripts/review-adjudicate-findings.sh magi \
  "$ADJUDICATE_META_FILE" "$AUDIT_JSON" "$IMPORTANCE_RESULT_FOR_ADJUDICATE" \
  > "$ADJUDICATION_RESULT" 2> "$MAGI_TMPDIR_ADJUDICATE/adjudicate.err" || ADJUDICATE_EXIT=$?
if [ "$ADJUDICATE_EXIT" -eq 2 ]; then
  echo "MAGI_HARD_FAILED: gate判定の入力に矛盾があります"
  return 1
fi
[ "$ADJUDICATE_EXIT" -eq 0 ] || [ "$ADJUDICATE_EXIT" -eq 1 ] || return 1
```

終了コード `2` は、この段階では構造検証済みのはずの `$FINDINGS_TABLE` が不正だった場合などの防御的な契約違反として扱い、診断を出して停止する。終了コード `0` または `1` は正常なデータ結果として `$ADJUDICATION_RESULT` を保存し、ステップ7で読む。`$ADJUDICATION_RESULT` の `validity_global_failure` が `true` で、かつ4-3自身は成功して `$POST_INLINE` がまだ `true` の場合は、消費者側の独立検証結果を優先して監査層を停止する。この場合だけ `BLOCK_LAYER=audit` とし、既存の `$AUDIT_NOTE` / `$BLOCK_LAYER` は上書きしない。

```bash
if [ "$POST_INLINE" = "true" ] \
  && [ -z "$AUDIT_NOTE" ] \
  && [ -z "$BLOCK_LAYER" ] \
  && jq -e '.validity_global_failure == true' "$ADJUDICATION_RESULT" >/dev/null 2>&1; then
  POST_INLINE=false
  BLOCK_LAYER=audit
  AUDIT_NOTE="AUDIT_ERROR（gate判定統合層で妥当性判定が信頼できないと判定された）"
fi
```

この統合結果を保存したら、ステップ 5（grounding）に進む。

## ステップ 5: grounding（アンカーの確認と補正）

**`$POST_INLINE` が `false` の場合はこのステップを丸ごとスキップし、ステップ 6 に進む。**
HIGH/MEDIUM 指摘が 0 件の場合も同様にスキップする（4-1 で `$GROUNDING_NOTE=""` を設定済み）。

grounding は **監査の代替ではなく補助検査**である。担当するのは
**アンカーの確認と行ズレの補正**（`ok` / `corrected` / `unverified` / `unanchorable` の判定）だけで、
**semantic な妥当性判定と、幻覚の断定・finding の除外は行わない**（どちらも Codex 監査の責務）。

> **grounding は finding を1件も消さない。`dropped` という状態を持たない。**
> 引用候補が全部見つからなくても、それを幻覚と断定してはならない。
> 「`subprocess.run([...])` に置き換えるべき」のように**修正案だけ**をコードスパンにする
> 妥当な指摘は普通にあり、その修正案は diff にも作業ツリーにも存在しない。
> 「全候補が不在＝幻覚」は成立しない。**アンカーできなければ通常 PR コメントへ退避するだけ**にする。

**`original_line`が`null`のfinding（Normalizerがline番号を確信を持って抽出できなかったもの）は、`scripts/magi-ground-findings.sh`に渡す前に除外する。** このスクリプトは`original_line`の型が`number`であることを全件に要求しており、`null`が1件でも混じると**表全体が拒否されてスクリプトが失敗し、他の全findingまで`unanchorable`に巻き込まれる**（5-3の失敗経路）。これを避けるため、`null`のfindingは直接`anchor_status: "unanchorable"`として扱い、スクリプトの入力には含めない。

```bash
GROUNDING_NOTE=""
ANCHORS_JSON="$MAGI_RUN_DIR/anchors.json"

# original_line が null の finding を分離し、直接 unanchorable にする
NULL_LINE_ANCHORS=$(jq -c '[.findings[] | select(.original_line == null) | {id, anchored_path: "", anchored_line: 0, side: "", anchor_status: "unanchorable"}]' "$FINDINGS_TABLE")
GROUNDABLE_TABLE="$MAGI_RUN_DIR/findings-table-groundable.json"
jq '{schema_version, findings: [.findings[] | select(.original_line != null)]}' "$FINDINGS_TABLE" > "$GROUNDABLE_TABLE"

if [ "$(jq '.findings | length' "$GROUNDABLE_TABLE")" = "0" ]; then
  # groundable な finding が無い（全件 null-line）場合はスクリプトを呼ばず、
  # NULL_LINE_ANCHORS だけを anchors とする
  jq -n --argjson anchors "$NULL_LINE_ANCHORS" '{schema_version: "1", anchors: $anchors}' > "$ANCHORS_JSON"
  GROUNDING_OK=true
elif bash scripts/magi-ground-findings.sh "$GROUNDABLE_TABLE" "$MAGI_RUN_DIR/pr.diff" > "$MAGI_RUN_DIR/anchors-script.json" 2>/dev/null; then
  # スクリプト出力と null-line 分を合成する
  jq -n --argjson script "$(jq '.anchors' "$MAGI_RUN_DIR/anchors-script.json")" --argjson nullpart "$NULL_LINE_ANCHORS" \
    '{schema_version: "1", anchors: ($script + $nullpart)}' > "$ANCHORS_JSON"
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
| 引用候補が空、かつ `original_line` が rename後の新パスの追加行として一意に確認できる | `unverified` | インライン（`side: RIGHT`）、本文に「位置未検証」の注記を付ける |
| **上記以外すべて**（位置を特定できない / 引用候補はあるが全候補が不在 / context・作業ツリーでしか見つからない / 引用候補が空で行番号も確認できない） | `unanchorable` | **通常 PR コメントへ退避** |

**旧側にしか無い引用を一律に落とさない。** 「削除された検証」「弱められたチェック」を
根拠とする指摘は正当であり、`side: LEFT` のインラインとして投稿できる。

**context / 作業ツリーの引用でアンカーできた場合も `unanchorable`**（インライン投稿しない）。
LELIEL は `<IMPACT_CONTEXT>` の呼び出し元証拠を根拠にする契約で、
根拠が diff 外の既存ファイルにあるのが正常系。PR diff 上に対応行が無いのでインラインは張れない。

### 5-1. 適用前の検証

`$GROUNDING_OK` が `true` でも、適用前に次を**すべて**検証する。
**1つでも満たさなければ 5-3 の失敗経路（全件 `unanchorable`）に倒す。**

- `anchors` の `id` 集合が `$FINDINGS_TABLE` の `id` 集合と**過不足なく・重複なく一致**する
- `anchor_status` が `ok` / `corrected` / `unverified` / `unanchorable` のいずれか（**未知の値を通さない**）
- `anchor_status` が `ok` / `corrected` のとき、`anchored_path` が非空文字列、
  `anchored_line` が正の整数、`side` が `RIGHT` / `LEFT` のいずれか（**前後空白を許さない**）
- `anchor_status` が `ok` / `corrected` のとき、`anchored_path` が `$DIFF` の変更対象に含まれ、
  **`anchored_line` が PR diff 上でコメント可能な位置**である
- `anchor_status` が `unverified` のとき、`anchored_path` が非空文字列、
  `anchored_line` が正の整数、`side` が `RIGHT` であり、`anchored_path` が `$DIFF` の変更対象に含まれ、
  **`anchored_line` が PR diff 上の新側追加行としてコメント可能な位置**である
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
  "evidence": "$cmd $arg",
  "original_path": "scripts/example.sh", "original_line": 17,
  "anchored_path": "scripts/example.sh", "anchored_line": 19,
  "side": "RIGHT", "anchor_status": "corrected" }
```

**`original_*` と `anchored_*` を1組のフィールドで兼ねてはならない。**
grounding が失敗した場合や `unanchorable` の場合、`anchored_*` は空になる。
兼ねると `$FINDING_LIST`（`filepath:line` が必須）もサマリも通常 PR コメントの場所表示も作れなくなる。

- `$FINDING_LIST` と通常 PR コメントの場所表示は **`original_*` を使う**（常に存在する）
- インラインコメントの位置は **`anchored_*` を使う**（`ok` / `corrected` / `unverified` のときのみ存在する）

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
- **`$BLOCK_IDS` に含まれない ID（`final_gate != "block"`）の除外と `$POST_INLINE=false` のスキップは通常どおり適用する。**
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
| 重要度層（Codex importance） | 対象findingの`severity`が`UNRATED`のまま残る。サマリのみに記載しインライン投稿しない | **変更しない**（他findingの投稿は継続） |
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

$IMPORTANCE_NOTE が空でない場合はサマリ末尾に以下を追記する:
> ⚠ 重要度判定: \`$IMPORTANCE_NOTE\`（該当件数はサマリのみに記載しインライン投稿しない）

$GROUNDING_NOTE が空でない場合はサマリ末尾に以下を追記する:
> ⚠ grounding: \`$GROUNDING_NOTE\`

$ARTIFACT_NOTE が空でない場合はサマリ末尾に以下を追記する:
> ⚠ canonical artifact: \`$ARTIFACT_NOTE\`

Codex 監査で `false_positive` 除外が発生した場合は以下を追記する:
> Codex 監査除外: N件（誤検知と判定）" \
  --jq '.html_url')
```

**severity表（HIGH/MEDIUM/LOW）の3列は維持する。** `severity == "UNRATED"`（4-4失敗分）は列に含めず、別途「重要度判定失敗: N件（サマリのみ）」として記載する。

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

<details><summary>未監査の指摘一覧</summary>

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

<details><summary>未整形の指摘一覧</summary>

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

```bash
BLOCK_IDS=$(jq -r '.results[] | select(.final_gate == "block") | .id' "$ADJUDICATION_RESULT" 2>/dev/null)
```

1. **`$BLOCK_IDS` に含まれる ID だけを投稿対象とする。** それ以外の ID は投稿しない。`final_gate` の導出規則により、`needs_human` でも `importance` が `HIGH`/`MEDIUM` なら `block` として投稿対象になる。
2. `$BLOCK_IDS` に含まれる ID について `anchor_status` で**事前分岐**する（422 エラーを待たない）。

| `anchor_status` | 経路 |
|---|---|
| `ok` / `corrected` | `anchored_path` / `anchored_line` / `side` でインラインコメント |
| `unverified` | `anchored_path` / `anchored_line` / `side` でインラインコメント。本文冒頭に「⚠ 位置は未検証（evidence引用なし、original_lineの実在確認のみ）」を付記 |
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

`anchor_status` が `unverified` のときは、本文冒頭に次を付ける:

```
⚠ 位置は未検証（evidence引用なし、original_lineの実在確認のみ）

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
# 空チェックを外してはならない。監査をスキップする経路（指摘 0件・構造検証失敗）では
# 4-2 を通らず $MAGI_TMPDIR が作られないまま、ここに到達する
if [ "$POST_INLINE" = "true" ] && [ -n "$MAGI_TMPDIR" ]; then
  rm -rf "$MAGI_TMPDIR"
fi

# 重要度判定（4-4）が失敗した場合は raw 出力を確認できるよう $MAGI_TMPDIR_IMPORTANCE を残す。
# BLOCK_LAYER=importance のときだけ残す（POST_INLINE は importance 失敗時も true のまま変わらないため、
# 上のブロックと同じ条件では判定できない）
if [ "$BLOCK_LAYER" != "importance" ] && [ -n "$MAGI_TMPDIR_IMPORTANCE" ]; then
  rm -rf "$MAGI_TMPDIR_IMPORTANCE"
fi

# PR 全体用の作業ディレクトリはここで片付ける
# （pr.diff、normalized.md、findings-table.json、anchors.json）
rm -rf "$MAGI_RUN_DIR"
unset MAGI_RUN_DIR
```

**`$MAGI_RUN_DIR` は最後のステップまで消してはならない。** ステップ 1 で書き出す `pr.diff` を
ステップ 5 の grounding が読み、`$FINDINGS_TABLE`（ステップ 4）や `anchors.json`（ステップ 5）も
ここに置かれるため、途中で消すと後続の参照が壊れる。
逆にここで消さないと、PR の差分と検出結果が一時ディレクトリに残り続ける。

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

`$IMPORTANCE_NOTE` が空でない場合は、上記に加えて以下を表示する
（`$POST_INLINE` が `true` のときにも起こりうる——重要度判定はインライン投稿の可否とは別層のため）。

```
重要度判定: 失敗（⚠ $IMPORTANCE_NOTE）
  該当指摘 N 件は重要度未確定のためサマリコメント本文にのみ記載（インライン投稿なし）
```

`$ARTIFACT_NOTE` が空でない場合は、上記に加えて以下を表示する

```
canonical artifact: 生成失敗（⚠ $ARTIFACT_NOTE）
```
