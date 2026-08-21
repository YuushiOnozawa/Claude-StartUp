# Canonical findings artifact

両 engine の検出結果を F2 以降の共通後段へ渡すための、canonical findings artifact の正本である。
schema_version は `1` とする。

これは「検出結果の契約」であり、監査・gate・重要度・grounding は含まない。監査 verdict、
canonical persona、グルーピング、重要度、grounding の結果はすべて下流の Feature が付与する。

## スキーマ例

```json
{
  "schema_version": "1",
  "engine": "magi",
  "detection_status": "complete",
  "failed_personas": [],
  "findings": [
    {
      "id": "M-001",
      "source_persona": "MELCHIOR",
      "path": "scripts/example.sh",
      "line": 17,
      "headline": "unquoted variable causes word splitting",
      "body": "…複数行の raw 本文…",
      "evidence": "$cmd $arg",
      "reported_gate": null,
      "gate_provenance": null
    }
  ]
}
```

## フィールド契約

| フィールド | 型・値 | 必須 | 規約 |
|---|---|---|---|
| `schema_version` | 文字列 `1` | 必須 | |
| `engine` | `magi` / `codex` | 必須 | `id` と組で finding の join キーになる（`id` は engine 内でのみ一意） |
| `detection_status` | `complete` / `incomplete` / `unknown` | 必須 | 検出層だけの状態。監査・merge・grounding・投稿の状態は含まない。`unknown` はその engine がペルソナ単位の失敗追跡を持たないことを表す |
| `failed_personas` | 文字列配列 / `null` | 必須（`null` 可） | `unknown` のときだけ `null`。`[]` にしてはならない |
| `findings` | 配列 | 必須 | 空配列可。(engine, id) が一意 |
| `id` | 非空文字列 | 必須 | engine 側の ID をそのまま使い、再採番しない |
| `source_persona` | 非空文字列 | 必須 | `MELCHIOR` / `BALTHASAR` / `CASPER` / `METATRON` / `SANDALPHON` / `LELIEL` |
| `path` | 非空文字列 | 必須 | |
| `line` | 正の整数 / `null` | 必須（`null` 可） | `null` は捏造しなかった証。0 や 1 で埋めない |
| `headline` | 非空文字列 | 必須 | |
| `body` | 非空文字列 | 必須 | raw 本文を保持する。改行、`|`、コードフェンス、引用符を含みうる |
| `evidence` | 非空文字列 / `null` | 必須（`null` 可） | `null` はその検出経路が引用を出さないことを表す。`""` は契約違反。Codex の5ペルソナは構造的に常に `null` |
| `reported_gate` | `block` / `defer` / `manual` / `null` | 必須（`null` 可） | ペルソナの自己申告であり、最終 gate ではない。最終 gate は F2 の独立判定層が決める |
| `gate_provenance` | `model_reported` / `deterministic` / `null` | 必須（`null` 可） | CASPER の `block` は決定論的導出、Codex の5ペルソナは model reported |

## 組合せ規則

`null` 同値だけでは誤変換を検出できないため、次の規則を validator とテストで固定する。

| 規則 | 内容 |
|---|---|
| status ⇔ failed_personas | `complete` ⟺ `[]` / `incomplete` ⟺ 非空配列 / `unknown` ⟺ `null`。他の組合せは契約違反 |
| failed_personas の中身 | 許可ペルソナ名（6種）のみ、重複禁止 |
| gate 軸の同値 | `reported_gate == null` ⟺ `gate_provenance == null` |
| engine=magi | 全 finding が `reported_gate == null` かつ `gate_provenance == null` |
| engine=codex / CASPER | `reported_gate == "block"` かつ `gate_provenance == "deterministic"` |
| engine=codex / 他5ペルソナ | `reported_gate` は `block` / `defer` / `manual` のいずれか、かつ `gate_provenance == "model_reported"` |

## v1 に入れないもの

| 除外するもの | 理由 / 担当 |
|---|---|
| `severity` / `importance` | 重要度は artifact の下流（F2）。MAGI の `severity` は監査後に付くため、検出時点の artifact には置かない |
| 監査 verdict（`valid` / `false_positive` / `needs_human`） | 両 engine とも table 外に持っている。共通化は F2 |
| `canonical_persona` / グルーピング | F2 |
| `anchored_path` / `anchored_line` / `side` / `anchor_status` | F4。未検証の位置を下流が読む余地を作るため、artifact に初期投入してはならない |

## 保存先・寿命・失敗時の扱い

- MAGI は `$MAGI_RUN_DIR/findings-artifact.json`、Codex は `$REVIEW_TMPDIR/findings-artifact.json` に保存する。
- 既存 findings table と同じディレクトリ・同じ run 寿命の一時成果物であり、run をまたいで保持しない。
- 変換前に `$ARTIFACT_NOTE=""` を初期化し、変換スクリプトの非0終了、出力ファイル不在、不正 JSON、自己検証落ちをすべて次へ集約する。

  `ARTIFACT_NOTE="ARTIFACT_FAILED（canonical artifact の生成に失敗した）"`

- 変換失敗でも既存のレビュー本体（監査・merge・grounding・投稿）は止めない。artifact を消費する経路は F1 時点では存在せず、F2 で artifact が消費側になった時点でこの失敗を gate へ昇格させる。
- artifact ファイルの不在は「検出層より前で停止した」ことを意味する。F2 は artifact 不在を必ず失敗として扱い、findings 0件や `complete` と解釈してはならない。

## F1 時点では既存経路と並存する

artifact は F1 ではどの production 経路からも消費されない。既存の監査・importance・merge・grounding・投稿は変更せず、そのまま動かす。
どの旧処理を artifact 後段へ置換・停止するかは F2 の決定事項であり、F1 では判断しない。
この並存は意図的な暫定状態である。
