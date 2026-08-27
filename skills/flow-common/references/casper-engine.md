# CASPER engine 共通契約

MAGI と Codex の両オーケストレーターから CASPER を呼び出すための、backend 非依存の正本である。
この契約は CASPER の検出結果を正規化済み findings 配列へ変換するまでを扱い、
レビューの重要度、gate、監査、grounding、投稿は扱わない。

## 責務と非責務

CASPER engine は、次の処理を同じ順序で実行する。

1. `/casper` を `MAGI_ORCHESTRATED=true` で呼び出す。
2. 大きい diff を hunk チャンクへ分割し、CASPER の raw 出力を連結する。
3. `skills/magi-common/references/normalizer.md` に従って、CASPER の raw 出力を1回のバッチ処理で正規化する。
4. 正規化結果の構造を検証する。
5. `source_persona` を必ず `CASPER` に固定する。
6. 呼び出し元から明示されたキーで `scripts/review-dedup-findings.sh` を実行する。

`reported_gate` / `gate_provenance` / `final_gate` / `importance` はこの契約に含めない。
MAGI は通常どおり importance 判定へ渡し、artifact 上の `reported_gate` / `gate_provenance` は
`null` のままにする。Codex は後段で importance をスキップし、`gate: "block"` と
`gate_provenance: "deterministic"` を付与する。この engine 別の接続は各呼び出し元の責務である。

`engine=magi|codex` は出力の接続先を記録するためだけに受け取る。検出基準、プロンプト、モデル、
Normalizer の選択を `engine` によって変えてはならない。

## CASPER の呼び出し

CASPER は常に次の override で実行する。

- `MAGI_ORCHESTRATED=true` を `/casper` 呼び出し元から明示的に渡す。
- 標準モデルは Claude Haiku とし、Ollama は使わない。
- Ollama 不可時の通常ペルソナ向け `AskUserQuestion` フォールバック確認は行わない。

これは `skills/casper/SKILL.md` の Haiku/no-confirmation 方針を、MAGI/Codex の両方で同じく適用する
ための override である。`MAGI_ORCHESTRATED` は CASPER の呼び出し境界でだけ設定し、内部の別処理へ
暗黙に引き継がない。

## diff チャンクと raw 出力

入力 diff は `scripts/magi-split-hunk.sh 400` で hunk 単位に分割する。チャンクは必ず直列に処理し、
前のチャンクの呼び出しが完全に終了してから次を開始する。各チャンクの stdout は、取得した内容を
捨てずに次のヘッダーを付けて raw 出力先へ追記する。

```text
=== PERSONA: CASPER / CHUNK: <path> (<n>) ===
<そのチャンクの CASPER raw stdout>
```

チャンク呼び出しの終了コードと stdout はそれぞれ保持する。1チャンクでも呼び出しに失敗した場合は
engine 全体を失敗とし、部分的な raw を finding 0件として成功扱いにしてはならない。

## Normalizer と構造検証

raw 出力が呼び出し成功として得られた場合だけ、連結済み raw を `$NORMALIZE_INPUT` として
`skills/magi-common/references/normalizer.md` の手順へ渡す。Normalizer は1回のバッチ呼び出しとし、
候補の判断、削除、統合、重要度判定は行わせない。

Normalizer 呼び出しの**直前**に `CASPER_NORMALIZE_ATTEMPTED=true` を設定する。このフラグは
Normalizer を試行したかどうかを表し、呼び出し失敗時に CASPER の失敗を検出層で二重計上しないために
使う。Normalizer 一時ディレクトリと正規化済み出力ファイルは呼び出し元が用意し、失敗時も診断用
raw を保持する。

Normalizer の出力は JSON array でなければならない。空配列 `[]` は「正常終了・0件」であり、失敗に
してはならない。配列の各要素は次をすべて満たすことを検証する。

| フィールド | 必須の型・値 |
|---|---|
| `persona` | 非空文字列（値は信用せず、後で固定する） |
| `path` | 非空文字列 |
| `line` | 正の整数または `null` |
| `headline` | 非空文字列 |
| `body` | 非空文字列 |
| `evidence` | 非空文字列または `null` |

構造検証は、`[]` を有効な成功として許容しつつ、配列内の1件でも不適合なら全体を失敗にする。

```bash
jq -e '
  type == "array"
  and all(.[];
    type == "object"
    and ((.persona? | type) == "string" and (.persona | length) > 0)
    and ((.path? | type) == "string" and (.path | length) > 0)
    and has("line")
    and ((.line == null)
         or ((.line | type) == "number" and (.line | floor) == .line and .line > 0))
    and ((.headline? | type) == "string" and (.headline | length) > 0)
    and ((.body? | type) == "string" and (.body | length) > 0)
    and (((.evidence? // null) | type) == "null"
         or (((.evidence? // null) | type) == "string"
             and ((.evidence? // null) | length) > 0))
  )
' "$NORMALIZED_FILE" >/dev/null 2>&1
```

次はすべて失敗として記録する。

- `/casper` の非0終了、チャンク失敗、または呼び出し stdout が空。
- Normalizer の非0終了、空 stdout、Normalizer 出力の不正 JSON。
- JSON が配列でない、必須フィールドの欠落、型違い、空文字列、または不正な `line`。

検証を通った要素だけを正規化済み findings とし、Normalizer が返した `persona` は信用しない。
各要素の `persona` と `source_persona` を機械的に `"CASPER"` へ強制上書きする。
`persona` は MAGI/Codex の既存 downstream へ渡す互換フィールド、`source_persona` は canonical
接続用フィールドとして同じ固定値を持つ。

## dedup

dedup キーは engine が推測せず、呼び出し元が `dedup_keys` パラメータとして明示的に渡す。
指定されたキー名が入力要素に存在することも検証し、キー欠落時は失敗とする。実処理は既存の
`scripts/review-dedup-findings.sh "$dedup_keys" <input.json>` を使い、first-occurrence order と
各フィールドを保持する。

- Codex 呼び出し元は `persona,headline,path,line,evidence,body` を渡す。
- MAGI 呼び出し元は、MAGI の「dedup は同一 persona 内だけ」契約を保つキーを渡す。
  通常の normalized shape では `persona,headline,path,line,evidence,body`、MAGI の downstream で
  `original_path` / `original_line` へ写像済みの場合は `persona,headline,original_path,original_line,evidence,body`
  とする。いずれも `persona` をキーから外してはならない。

`source_persona=CASPER` の固定は dedup より前に行う。これにより Normalizer が別の persona 名を返しても
CASPER finding として同一キーで扱われ、異なる persona の finding を混ぜることもない。

## 失敗状態と失敗記録

呼び出し元は次の4状態を区別して受け取る。

| 状態 | 意味 |
|---|---|
| `invoke_failed` | `/casper` またはチャンク処理の失敗、非0終了、空 stdout |
| `normalize_failed` | Normalizer の非0終了、空 stdout、不正 JSON、または `NORMALIZE_ERROR` / `NORMALIZE_SKIPPED` |
| `structure_failed` | Normalizer JSON は読めたが、必須フィールドの型・非空条件に不適合 |
| `complete` | 構造検証と dedup を通過した正規化済み配列（`[]` を含む） |

失敗時は `failed_personas` に `CASPER` を一度だけ記録し、`failure_stage` に上表の段階を記録する。
Normalizer を試行した場合は `CASPER_NORMALIZE_ATTEMPTED=true` を維持し、試行していない場合は未設定または
`false` とする。Normalizer の失敗を finding 0件の正常終了へ丸めてはならない。

## 入出力契約

呼び出し元は少なくとも次を入力として渡す。

| 入力 | 内容 |
|---|---|
| `engine` | `magi` または `codex`。下流接続用のみ |
| `diff_source` | CASPER が見る filtered diff、またはそのファイル |
| `raw_output_path` | ヘッダー付き CASPER raw 連結先 |
| `normalizer_tmpdir` | Normalizer の一時ディレクトリ |
| `failure_sink` | `failed_personas` と `failure_stage` の受け口 |
| `dedup_keys` | 呼び出し元が明示する CSV キー列 |

`failure_sink` をファイルで渡す場合は、engine が次の JSON object を書き込む。
成功時は `{"failed_personas":[],"failure_stage":null}`（正規化済み finding が `[]` の場合も同じ）とし、
失敗時は `failed_personas` に `CASPER` を一度だけ含め、`failure_stage` に
`invoke_failed` / `normalize_failed` / `structure_failed` のいずれかを設定する。呼び出し元はこの
ファイルを読み、既存の失敗ペルソナ配列へ重複なく反映する。

成功時は次を返す。

| 出力 | 内容 |
|---|---|
| `normalized_findings` | `persona`, `source_persona`, `path`, `line`, `headline`, `body`, `evidence` を持つ配列。空配列可 |
| `status` | `complete` または上記3種の失敗状態 |
| `failure_stage` | 成功時は `null`、失敗時は失敗段階 |
| `normalizer_attempted` | Normalizer 試行有無。`CASPER_NORMALIZE_ATTEMPTED` と一致 |

`normalized_findings` を MAGI の findings table、または Codex の downstream 接続へ渡す際に、各呼び出し元は
自身の `reported_gate` / `gate_provenance` / `final_gate` / `importance` 契約だけを追加する。
