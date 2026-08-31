---
name: magi-hard
description: MAGI 6体（melchior→balthasar→casper→metatron→sandalphon→leliel）でPRレビューを行う。指摘をGitHubにコメント投稿する。Trigger: "/magi-hard", "magi-hard", "ハードレビュー", "PRをMAGIにレビューさせて"
---

# MAGI-HARD スキル

MAGI の6体を順次実行し、PR の全差分を深くレビューする。
各体は担当ドメインに専念し、ドメイン分離によって重複を防ぐ。
`final_gate:"block"` の指摘を GitHub PR へ投稿し、サマリも別途投稿する。

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

`$MAGI_RUN_DIR/pr.diff` は**ステップ 5 で生成する review-post request の diff 入力**になる。
ここで書き出さないと review-post が grounding を実行できず、
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
    if ! jq -e --arg p "$persona" 'index($p) != null' <<<"$FAILED_PERSONAS_JSON" >/dev/null 2>&1; then
      FAILED_PERSONAS_JSON=$(jq --arg p "$persona" '. + [$p]' <<<"$FAILED_PERSONAS_JSON")
      printf '%s\n' "$FAILED_PERSONAS_JSON" > "$MAGI_RUN_DIR/failed-personas.json"
    fi
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
`skills/flow-common/references/casper-engine.md` の共通契約を Read し、
`engine=magi`、`diff_source=$DIFF`、raw 出力先、Normalizer 一時ディレクトリ、失敗記録の受け口、
および `persona,headline,path,line,evidence,body`（MAGI downstream で写像する場合は
`persona,headline,original_path,original_line,evidence,body`）の dedup キーを渡して実行する。
入力の実体と failure sink は次のように確保する。

```bash
CASPER_RAW_FILE="$MAGI_RUN_DIR/raw/casper.txt"
CASPER_NORMALIZER_TMPDIR="$MAGI_RUN_DIR/casper-normalizer"
CASPER_FAILURE_SINK="$MAGI_RUN_DIR/casper-failure.json"
mkdir -p "$CASPER_NORMALIZER_TMPDIR"
printf '%s\n' '{"failed_personas":[],"failure_stage":null}' > "$CASPER_FAILURE_SINK"
```

契約の `raw_output_path="$CASPER_RAW_FILE"` の内容（CASPER のチャンクヘッダー付き raw stdout）を
`$CASPER_RESULT` に渡す。raw ファイルが生成されない場合に限り、`$CASPER_ENGINE_FINDINGS` の JSON
文字列表現（未設定なら `[]`）を `$CASPER_RESULT` として使い、LGTM 表示・失敗時の診断本文を空にしない。
契約の `status` を `$CASPER_ENGINE_STATUS`、`failure_stage` を `$CASPER_ENGINE_FAILURE_STAGE`、
正規化済み dedup 後の配列を `$CASPER_ENGINE_FINDINGS` として保持する。
契約は `/casper` を `MAGI_ORCHESTRATED=true` で呼び出し、Haiku/no-confirmation、チャンク直列化、
Normalizer、`source_persona=CASPER` 固定、失敗段階の記録までを担当する。
成功・失敗を問わず次を実行してからステップ 3.4 に進む。

```bash
if [ -r "$CASPER_FAILURE_SINK" ]; then
  CASPER_FAILED_PERSONAS=$(jq -c '.failed_personas // []' "$CASPER_FAILURE_SINK" 2>/dev/null || printf '%s\n' '[]')
  FAILED_PERSONAS_JSON=$(jq -cn \
    --argjson existing "$FAILED_PERSONAS_JSON" \
    --argjson additions "$CASPER_FAILED_PERSONAS" \
    'reduce ($additions[]) as $p ($existing; if index($p) == null then . + [$p] else . end)')
  printf '%s\n' "$FAILED_PERSONAS_JSON" > "$MAGI_RUN_DIR/failed-personas.json"
fi
CASPER_ENGINE_FAILURE_STAGE=$(jq -r '.failure_stage // "null"' "$CASPER_FAILURE_SINK" 2>/dev/null || printf '%s\n' 'null')
if [ -r "$CASPER_RAW_FILE" ]; then
  CASPER_RESULT=$(cat "$CASPER_RAW_FILE")
else
  CASPER_RESULT=$(printf '%s\n' "${CASPER_ENGINE_FINDINGS:-[]}")
fi
if [ "$CASPER_ENGINE_STATUS" = "complete" ]; then
  CASPER_EXIT=0
else
  CASPER_EXIT=1
fi
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

MELCHIOR/BALTHASAR/METATRON/SANDALPHON/LELIELは`$MAGI_ORCHESTRATED=true`で実行済みのため、
各自ではNormalizerを呼ばず生の結果（チャンクヘッダー込み）を返している。CASPER はステップ3.3の
共通契約で正規化済みのため、CASPER raw をこのバッチへ重ねて渡さない。失敗ペルソナの raw は除外し、
残り5体の結果だけを1回のバッチ呼び出しにまとめてNormalizerへ渡す。

1. `MAGI_TMPDIR=$(mktemp -d)` で作業ディレクトリを作成する。
2. `$FAILED_PERSONAS_JSON` に含まれない成功ペルソナの raw ファイルだけを、それぞれ `=== PERSONA: <name> / CHUNK: <path> (<n>) ===` ヘッダーを保ったまま連結し、`$NORMALIZE_INPUT` として保持する。失敗ペルソナの raw ファイルは診断用に残すが、Normalizerには渡さない。

```bash
NORMALIZE_INPUT="$(
  for PERSONA in MELCHIOR BALTHASAR METATRON SANDALPHON LELIEL; do
    if jq -e --arg p "$PERSONA" 'index($p) == null' <<<"$FAILED_PERSONAS_JSON" >/dev/null 2>&1; then
      PERSONA_KEY=$(printf '%s' "$PERSONA" | tr '[:upper:]' '[:lower:]')
      cat "$MAGI_RUN_DIR/raw/${PERSONA_KEY}.txt"
      printf '\n'
    fi
  done
)"
```
3. `skills/magi-common/references/normalizer.md`（repo 内）または `~/.claude/skills/magi-common/references/normalizer.md` を Read ツールで読み込み、記載の手順に従ってNormalizerを実行する。
4. 成功した場合、`$MAGI_TMPDIR/normalizer.json` に CASPER engine の
`$CASPER_ENGINE_FINDINGS` を追加した内容を `$NORMALIZED_V2_JSON` として
`$MAGI_RUN_DIR/normalized-v2.json` にコピーし保持する（`$MAGI_TMPDIR` はチャンク単位ではなくこの
バッチ呼び出し専用なので、コピー後に削除してよい）。CASPER の `persona`/`source_persona` は
共通契約が固定した値をそのまま使い、ここで再度 Normalizer や dedup を呼び出さない。

```bash
if [ "$CASPER_ENGINE_STATUS" = "complete" ]; then
  jq -s '.[0] + .[1]' "$MAGI_TMPDIR/normalizer.json" \
    <(printf '%s\n' "$CASPER_ENGINE_FINDINGS") > "$MAGI_RUN_DIR/normalized-v2.json"
else
  cp "$MAGI_TMPDIR/normalizer.json" "$MAGI_RUN_DIR/normalized-v2.json"
fi
```
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

`$PRE_ID_CANDIDATES` は、5体分の通常 Normalizer 結果と CASPER engine の正規化済み結果を連結した
単一の JSON 配列として保持する。`normalized-v2.json` の各要素について `path` を `original_path`、
`line` を `original_line` にリネームし（元の `path`/`line` キーは残さない）、`severity: "UNRATED"` を
持つ同じ形の object にする。

#### 採番前の重複統合（機械的完全一致dedup）

`skills/magi-common/references/normalizer.md` 15行目は、重複除去を Normalizer の責務ではなく呼び出し元の責務としている。ここで共通dedupスクリプトを呼び出して実装する。

通常5体分をマージした **pre-ID candidate list** に対し、採番前に機械的な重複統合を1回だけ行う。
CASPER 候補は共通契約ですでに同じ処理を終えているため、この downstream dedup へ再投入しない。
重複キーは `persona` / `headline` / `original_path` / `original_line` / `evidence` / `body` の6フィールドの
byte-for-byte 完全一致とし、6つすべてが一致する場合だけ同一候補として扱う。`body` を含めるのは、同じ
persona / line / headline / evidence を共有しても Problem / Breakage の内容が異なる正当な別 finding を
潰さないため。

dedup は **同一 `persona` 内だけ**で行う。異なる persona が同じ場所を指すことは有用な corroboration signal なので、persona をまたいで統合してはならない。

先に出た候補を残し、first-occurrence order を維持する。`jq unique_by` は order-stable ではないため使わず、`reduce` で実装する。

`evidence: null` と `evidence: ""` は別値として扱う。空文字列は後続の構造検証で失敗するが、dedup キー作成時に `null` を `""` や文字列 `"null"` へ変換してはならない。

```bash
DEDUPED_CANDIDATES="$MAGI_RUN_DIR/deduped-candidates.json"
```

`$DEDUPED_CANDIDATES` は通常5体分の重複統合後・採番前の候補を保持する。CASPER engine の配列は
first-occurrence order を維持したまま、dedup 済み候補としてここへ追加する。

```bash
PRE_ID_NON_CASPER="$MAGI_RUN_DIR/pre-id-non-casper.json"
jq 'map(select(.persona != "CASPER"))' "$PRE_ID_CANDIDATES" > "$PRE_ID_NON_CASPER"
bash scripts/review-dedup-findings.sh persona,headline,original_path,original_line,evidence,body \
  "$PRE_ID_NON_CASPER" > "$MAGI_RUN_DIR/deduped-non-casper.json"
jq 'map(select(.persona == "CASPER"))' "$PRE_ID_CANDIDATES" > "$MAGI_RUN_DIR/deduped-casper.json"
jq -s '.[0] + .[1]' "$MAGI_RUN_DIR/deduped-non-casper.json" \
  "$MAGI_RUN_DIR/deduped-casper.json" > "$DEDUPED_CANDIDATES"
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

grounding と GitHub 投稿は、共通後段の `/review-post` に委譲する。このステップでは、4-1 完了時点の
`$FINDINGS_TABLE`、4-5/4-6 の成果物、PR diff、層別状態を request JSON にまとめる。
`POST_INLINE` はステップ7相当の投稿可否だけを表し、サマリ投稿の可否には使わない。

```bash
REVIEW_POST_REQUEST="$MAGI_RUN_DIR/review-post-request.json"
REVIEW_POST_RESULT="$MAGI_RUN_DIR/review-post-result.json"
REVIEW_POST_DIFF="$MAGI_RUN_DIR/pr.diff"
REVIEW_POST_NORMALIZED="$MAGI_RUN_DIR/normalized-results.txt"
REVIEW_POST_FINDING_LIST="$MAGI_RUN_DIR/finding-list.txt"

# jq の --rawfile に任せて、structure/audit 経路の退避本文も改行・引用符を保つ。
if [ -n "${NORMALIZED_RESULTS:-}" ] && [ -r "$NORMALIZED_RESULTS" ]; then
  cat -- "$NORMALIZED_RESULTS" > "$REVIEW_POST_NORMALIZED"
else
  printf '%s' "" > "$REVIEW_POST_NORMALIZED"
fi
printf '%s' "${FINDING_LIST:-}" > "$REVIEW_POST_FINDING_LIST"

POST_INLINE_JSON="${POST_INLINE:-true}"
BLOCK_LAYER_VALUE="${BLOCK_LAYER:-}"
ARTIFACT_PATH_VALUE="${ARTIFACT_FILE:-}"
ADJUDICATION_PATH_VALUE="${ADJUDICATION_RESULT:-}"
if [ "$BLOCK_LAYER_VALUE" = "structure" ]; then
  ARTIFACT_PATH_VALUE=""
  ADJUDICATION_PATH_VALUE=""
fi

jq -n \
  --arg engine "magi" \
  --arg owner "$OWNER" \
  --arg repo "$REPO" \
  --argjson number "$PR_NUM" \
  --arg head_sha "$HEAD_SHA" \
  --arg artifact "$ARTIFACT_PATH_VALUE" \
  --arg adjudication "$ADJUDICATION_PATH_VALUE" \
  --arg diff "$REVIEW_POST_DIFF" \
  --argjson post_inline "$POST_INLINE_JSON" \
  --arg block_layer "$BLOCK_LAYER_VALUE" \
  --arg audit_note "${AUDIT_NOTE:-}" \
  --arg importance_note "${IMPORTANCE_NOTE:-}" \
  --arg artifact_note "${ARTIFACT_NOTE:-}" \
  --rawfile normalized_results "$REVIEW_POST_NORMALIZED" \
  --rawfile finding_list "$REVIEW_POST_FINDING_LIST" \
  --arg result_path "$REVIEW_POST_RESULT" \
  '{
    schema_version:"1", artifact_type:"review-post-request", engine:$engine,
    pr:{owner:$owner, repo:$repo, number:$number, head_sha:$head_sha},
    inputs:{
      findings_artifact:(if $artifact == "" then null else $artifact end),
      adjudication_result:(if $adjudication == "" then null else $adjudication end),
      diff:$diff
    },
    engine_state:{
      post_inline:$post_inline,
      block_layer:(if $block_layer == "" then null else $block_layer end),
      audit_note:(if $audit_note == "" then null else $audit_note end),
      importance_note:(if $importance_note == "" then null else $importance_note end),
      artifact_note:(if $artifact_note == "" then null else $artifact_note end),
      normalized_results:(if $normalized_results == "" then null else $normalized_results end),
      finding_list:(if $finding_list == "" then null else $finding_list end)
    },
    result_path:$result_path
  }' > "$REVIEW_POST_REQUEST" || return 1
```

この request を次のステップで `/review-post` へ渡す。structure 経路では artifact と adjudication を null にし、
`$NORMALIZED_RESULTS` を raw のまま渡す。それ以外では canonical artifact と adjudication result のパスを必ず渡す。
grounding は投稿対象を絞る前の canonical findings 全件を対象にし、null-line の分離、アンカー検証、422 フォールバックは
review-post 契約に従う。

## ステップ 6: サマリコメント投稿

`skills/review-post/SKILL.md` を Read して手順に従い、`/review-post "$REVIEW_POST_REQUEST"` を実行する。
実行後は `$REVIEW_POST_RESULT` を読み、サマリ投稿が完了したこと、または終了コード1/2の理由を確認する。
サマリは `post_inline` の値に関係なく review-post が常に投稿する。終了コード2は入力契約違反として停止し、
終了コード1は GitHub API の失敗として後続へ成功扱いで渡さない。

## ステップ 7: GitHub インラインコメント投稿

GitHub への実投稿はステップ6で review-post が完了しているため、このステップでは投稿を行わない。
`$REVIEW_POST_RESULT` の `items[]`、`counts`、`github_writes`、および review-post の終了コードを検査するだけにする。
`post_inline:false` の場合は summary-only/audit/structure の結果であり、ステップ7相当のインライン投稿・通常 PR コメント退避は
実行されず、指摘一覧はステップ6のサマリ本文に埋め込まれている。grounding fallback の場合は
`anchor_status:"unanchorable"` と `delivery:"pr_comment"` を確認する。

検査後、ステップ8が結果を表示できるよう、サマリ URL、投稿件数、`grounding_note` を `$REVIEW_POST_RESULT` の
`github_writes` / `counts` / `grounding_note` から設定する。review-post の終了コード1/2は成功として扱わず、終了理由と
成功済みの `github_writes` を保持したまま報告する。

```bash
SUMMARY_URL=$(jq -r 'first(.github_writes[] | select(.kind == "summary") | .url) // ""' "$REVIEW_POST_RESULT")
INLINE_COUNT=$(jq -r '.counts.inline_posted' "$REVIEW_POST_RESULT")
FALLBACK_COUNT=$(jq -r '.counts.fallback_posted' "$REVIEW_POST_RESULT")
GROUNDING_NOTE=$(jq -r '.grounding_note // ""' "$REVIEW_POST_RESULT")
```


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
