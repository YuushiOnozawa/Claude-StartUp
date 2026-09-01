# /review-fast /review-hard 共通 dispatch 契約

/review-fast と /review-hard は、review engine の backend を選択し、engine の生結果を
呼び出し元が扱える共通 envelope へ正規化する薄い dispatch 層である。fast と hard は backend 選択 UI、
状態変数、利用不可時の fail-closed 規則を共有する。

## 入力と backend 選択

入口は呼び出し元から review_kind=fast または review_kind=hard を受け取る。backend は magi または
codex の一方だけを実行する。「両方実行」は選択肢に設けない。

該当する状態変数が未設定・不正のときだけ AskUserQuestion を 1 回出す。fast と hard は別の質問にし、
fast の選択結果は $REVIEW_FAST_BACKEND、hard の選択結果は $REVIEW_HARD_BACKEND に保持する。
呼び出し時に値が消失していた場合は既定値を推測せず、その review 種別だけ再問い合わせする。

- fast の質問: 「Fast レビューの backend を選択してください。修正ループ中は同じ backend を使い続けます。」
  - magi — /magi-fast を実行（Ollama が必要）
  - codex — /codex-fast を実行（Codex companion が必要）
- hard の質問: 「PR の hard レビューの backend を選択してください。結果は GitHub へ投稿されます。」
  - magi — /magi-hard を実行（Ollama が必要）
  - codex — /codex-hard → /review-post を実行（Codex companion が必要。Codex 最大 8 回・各 600 秒 timeout・最悪約 80 分、加えて CASPER の Haiku 呼び出し）

既定値と一時 override は別の変数として扱う。override は当該 Feature/PR の呼び出しだけに適用し、完了
後に破棄する。fast は /review-post に接続せず、hard は投稿を止めるトグルを設けない。

## 実行前提

dispatch と `scripts/review-dispatch-envelope.sh` は `jq` を必要とする。`jq` が PATH にない環境では
validator が契約検証を実行できず、`exit 2` で停止する。setup / runner への `jq` 導入は本層の変更対象
ではなく、必要なら別 Issue で扱う。

## 共通 envelope

dispatch は次の全フィールドを持つ単一 JSON 値を返す。余分な実装固有情報は native_result に残し、
呼び出し元は共通キーだけで分岐する。

```json
{
  "schema_version": "1",
  "artifact_type": "review-dispatch-result",
  "review_kind": "fast",
  "backend": "magi",
  "dispatch_status": "complete",
  "gate_decision": "lgtm",
  "lgtm_eligible": true,
  "blocking_count": 0,
  "manual_review_required": false,
  "manual_review": null,
  "artifact_ref": null,
  "adjudication_ref": null,
  "post_state": "not_applicable",
  "failure_reason": null,
  "native_result": {}
}
```

| フィールド | 値 | 規約 |
|---|---|---|
| schema_version | "1" | envelope のスキーマバージョン |
| artifact_type | "review-dispatch-result" | envelope の種別 |
| review_kind | fast / hard | 実行した review 種別 |
| backend | magi / codex | 実行した engine backend |
| dispatch_status | complete / incomplete / failed / unavailable | engine が最後まで走ったか |
| gate_decision | lgtm / block / manual / indeterminate | dispatch 層で正規化したゲート |
| lgtm_eligible | boolean | 下記の固定述語をすべて満たす場合だけ true |
| blocking_count | 非負整数 / null | 集計不能なら null。degraded 経路、`.counts.block` の欠落・非整数は null とし、null を 0 に丸めない |
| manual_review_required | boolean | 未監査・要人手確認が残るか |
| manual_review | object / array / null | 未監査・要人手確認の内容 |
| artifact_ref | パス / null | fast は常に null。hard は engine の run tmpdir（または dispatch handoff）内のパス。validator が検証するのは「null または非空文字列」という JSON 形状だけで、実在・run tmpdir 所属・当該 review との対応は dispatch が envelope 生成前に検証する（下記「返却、検証、寿命」） |
| adjudication_ref | パス / null | fast は常に null。hard は engine の run tmpdir（または dispatch handoff）内のパス。実在確認などの責務は artifact_ref と同じ |
| post_state | posted / post_failed / not_applicable | fast は常に not_applicable |
| failure_reason | 文字列 / null | dispatch_status が complete 以外のとき、非空文字列が必須 |
| native_result | object | backend 固有の生結果。persona 別集計などを保持し、分岐には使わない |

lgtm_eligible を true にできるのは、次のすべてが成立するときだけである。

```text
dispatch_status == "complete"
gate_decision == "lgtm"
blocking_count == 0
manual_review_required == false
```

さらに review_kind == hard の場合は post_state == posted も必須である。blocking_count == 0 単独を
LGTM の根拠にしてはならない。

### 評価不能時の不変条件

`dispatch_status ∈ {failed, unavailable}` のときは `manual_review_required == true` を必須とする。
全面失敗と backend 利用不可は自動判定不能であり、「人手確認不要」と表現できない。この 2 状態は envelope
単独で確実に判定できるため、`scripts/review-dispatch-envelope.sh` が契約として強制する（違反は `exit 2`）。
validator 自身が契約違反を検出したときの fail-closed 結果でも `manual_review_required=true` とする。

`dispatch_status == "incomplete"` はこの強制の対象外である。incomplete には structure-degraded
（`manual_review_required=false` を許容）と audit-degraded（`manual_review_required=true`）の両方があり、
envelope 単独では区別できないためである。

## 返却、検証、寿命

dispatch は engine の cleanup より前に必要な生結果を読み、envelope を run 専用 tmpdir の固定名へ書く。
呼び出し元へ渡す返却変数は、$DISPATCH_TMPDIR/review-dispatch-result.json の絶対パスである。
$REVIEW_POST_RESULT と同じ体裁で、次のように $REVIEW_DISPATCH_RESULT を設定して渡す。

```bash
REVIEW_DISPATCH_RESULT="$(realpath -m -- "$DISPATCH_TMPDIR/review-dispatch-result.json")"
# envelope を $REVIEW_DISPATCH_RESULT へ書き出す。
export REVIEW_DISPATCH_RESULT
```

呼び出し元は $REVIEW_DISPATCH_RESULT のファイルだけを読み、envelope のキーで分岐する。envelope を書き
出したら必ず次を実行する。

```bash
bash scripts/review-dispatch-envelope.sh validate "$REVIEW_DISPATCH_RESULT"
```

validator が落ちた場合は dispatch 契約違反として dispatch_status=failed、gate_decision=indeterminate、
lgtm_eligible=false、failure_reason 非 null の fail-closed 結果として扱い、LGTM を出さない。

envelope、artifact_ref、adjudication_ref、hard の $REVIEW_POST_RESULT は同一 run 内だけ有効である。
ref は engine の run tmpdir（または dispatch handoff）内の一時成果物であり、呼び出し元はパスを永続化せず、
次 run で再読み込みしない。次 run で必要になった場合は該当 review 種別を再実行する。

### hard の ref 事前検証（dispatch runtime の責務）

envelope validator は文字列形状しか見ないため、hard envelope を組む前に dispatch が次を実施する。

- ref は request の `.inputs`（`findings_artifact` / `adjudication_result`）から取得し、任意の外部入力で
  差し替えない。
- 非 null ref は絶対パスへ正規化し、現在の engine run tmpdir または dispatch handoff 配下に含まれる
  ことを確認する。
- 非 null ref ごとに `[ -r "$path" ]` で読取可能を確認する。
- `gate_decision ∈ {lgtm, block}` では `artifact_ref` と `adjudication_ref` の両方を必須とする。
- structure-degraded 経路の両 ref = null は正当として扱う。
- 必須 ref が null / run 外 / 読取不能なら `dispatch_status=failed` / `gate_decision=indeterminate` /
  `blocking_count=null` / `lgtm_eligible=false` とする。投稿後にこの検査が失敗した場合は
  「hard の post_state」に従い `post_state=posted` を保持する。

## fast 正規化

### MAGI

/magi-fast の MELCHIOR/BALTHASAR/CASPER ゲート結果を次のように写像する。通常の blocking_count は
3 体のゲート集計を正本とし、manual/needs_human の有無は native の要確認情報を反映する。

| native の状態 | dispatch_status | blocking_count | manual_review_required | gate_decision | lgtm_eligible |
|---|---|---|---|---|---|
| ゲート成功・blocking 0・未解決 manual/needs_human なし | complete | 0 | false | lgtm | true |
| ゲート成功・blocking finding あり | complete | native 値 | native を反映 | block | false |
| ゲート成功・未解決 manual/needs_human あり | complete | native 値 | true | manual | false |
| CASPER 単体失敗（$CASPER_ENGINE_STATUS != complete、MELCHIOR/BALTHASAR は正常） | incomplete | null | true | indeterminate | false |
| ゲート判定失敗（全面ブラックアウト、3 体すべて未判定） | failed | null | true | indeterminate | false |

CASPER 単体失敗では MELCHIOR/BALTHASAR の block/manual 件数を native_result に残すが、CASPER 分が欠ける
ため blocking_count は null とする。これは全面ブラックアウトの failed とは別の incomplete である。

### Codex

/codex-fast の pipeline_status、findings、manual_review を正規化する。blocking_count は persona 別では
なく、merge 後の canonical_persona 別集計を正本とする。persona 別集計は native_result に残す。

| native の状態 | dispatch_status | blocking_count | manual_review_required | gate_decision | lgtm_eligible |
|---|---|---|---|---|---|
| pipeline_status=complete・canonical block 合計 0・manual_review 空 | complete | 0 | false | lgtm | true |
| pipeline_status=complete・block あり | complete | canonical 集計 | manual_review を反映 | block | false |
| pipeline_status=complete・block なし・manual_review あり | complete | 0 | true | manual | false |
| pipeline_status=incomplete | incomplete | 集計可なら保持・不能なら null | manual_review を反映 | indeterminate | false |
| merge / gate 集計そのものが失敗 | failed | null | true | indeterminate | false |

pipeline_status=incomplete は finding 0 件へ丸めず、incomplete として保持する。blocking_count == 0 でも
dispatch_status が complete でなければ LGTM にしない。

fast は canonical artifact を持たないため、すべての経路で artifact_ref=null、adjudication_ref=null、
post_state=not_applicable とする。

## hard 正規化と GitHub 投稿

両 backend とも schema_version:"1"、artifact_type:"review-post-request" の同形 request を生成する。
差は投稿を誰が行うかだけである。

### dispatch handoff 行

hard engine skill（/magi-hard、/codex-hard）は、完了報告の末尾に次の 1 行を安定書式で出力する。
dispatch はこの行から成果物パスを取得し、engine の cleanup がこれらを消さないことを前提にできる。

```text
dispatch handoff: {"request":"<review-post-request.json の絶対パス>","result":"<review-post-result.json の絶対パス>"}
```

- `request` / `result` は必須キーで、いずれも絶対パスとする。
- codex の `result` は完了報告の時点で未生成でよい。request の `.result_path` が示す絶対パスをそのまま
  返し、dispatch が /review-post 実行後に読む。
- 行の欠落、不正 JSON、非絶対パス、`request` の読取不能は dispatch 失敗として扱い、
  `dispatch_status=failed` / `gate_decision=indeterminate` / `blocking_count=null` とする。

| backend | dispatch の動作 | 投稿主体 |
|---|---|---|
| magi | /magi-hard を実行し、完了報告の `dispatch handoff:` 行から request / result のパスを取得して読む（result は /magi-hard 内部の投稿後に存在する） | /magi-hard 内部の /review-post |
| codex | /codex-hard を実行し、`dispatch handoff:` 行の request を /review-post へ渡して投稿まで完了させ、同行の result（= request の `.result_path`）を読む | dispatch が呼ぶ /review-post |

### hard envelope フィールドの正本

scripts/review-adjudicate-findings.sh の出力は per-finding の final_gate だけで、値域は block、defer、null
である。final_gate は manual を取らない。したがって hard に manual ゲートは構造的に存在せず、
needs_human verdict は既存どおり defer に収束する。ただし未解決の要人手確認を LGTM に埋もれさせないため、
dispatch は adjudication result（`adjudication_ref`）の `results[]` も読む。

hard の集計正本は、両 backend が通る /review-post の review-post-result.json である。
review-post-result.json の .counts.block と .status を使い、persona 別内訳などは native_result に残す。

| envelope フィールド | 算出元 | 規則 |
|---|---|---|
| blocking_count | review-post-result.json の `.counts.block` | degraded 経路、欠落、非整数では null。通常経路の整数値だけを使う |
| gate_decision | **明示 whitelist** による導出 | `block_layer=structure/audit` または `.status=report_only` の degraded → `indeterminate`。それ以外で `.status ∈ {posted, no_findings}`、`block_layer ∈ {importance, null}`、整数 `.counts.block > 0` → `block`、同じ status/layer で整数 `.counts.block == 0` → `lgtm`。未知・欠落・非整数・whitelist 外は `dispatch_status=failed` / `gate_decision=indeterminate` / `blocking_count=null`。`post_state` は status/counts ではなく「hard の post_state」の終了コード / result 写像から決める |
| manual_review_required | adjudication result の `results[]` と `validity_global_failure` | `results[].verdict=="needs_human"` が1件以上、または `validity_global_failure==true` なら true。それ以外 false |
| manual_review | 上記の要人手確認内容 | true のとき `needs_human` の finding id 一覧を載せ、`validity_global_failure==true` は別記する。それ以外 null |
| artifact_ref | request .inputs.findings_artifact | structure 経路では null |
| adjudication_ref | request `.inputs.adjudication_result` | structure 経路では null（正当）。通常経路（`gate_decision ∈ {lgtm,block}`）で null または読めない場合は `dispatch_status=failed`。同じ規則を `artifact_ref` にも適用する（上記「hard の ref 事前検証」） |
| native_result | result の .counts / .items / .grounding_status など | 呼び出し元は分岐に使わない |

degraded 経路は review-post-result.json の status だけでなく request の engine_state.block_layer で識別する。
status=report_only だけでは audit 経路が no_findings に見えるためである。`status=report_only` も既存どおり
degraded として扱い、`dispatch_status=incomplete` / `gate_decision=indeterminate` にする。

- block_layer=structure: 構造化失敗。dispatch_status=incomplete、gate_decision=indeterminate、
  blocking_count=null、artifact_ref=null、adjudication_ref=null。post result の status は report_only。
  **adjudication を読めないため `needs_human` 判定は不能。`manual_review_required` は false のまま、
  `manual_review` は null。`dispatch_status=incomplete` が LGTM を防ぐ。**
- block_layer=audit: 妥当性 global failure。dispatch_status=incomplete、gate_decision=indeterminate、
  blocking_count=null、manual_review_required=true。`validity_global_failure==true` は manual_review に別記する。
- block_layer=importance または null かつ status が posted/no_findings: 通常経路として .counts.block と .status を使う。

`manual_review_required` の扱いは degraded 種別で分かれる。`incomplete + structure` は `false` を許容、
`incomplete + audit` は `true`、`dispatch_status ∈ {failed, unavailable}` は
`scripts/review-dispatch-envelope.sh` が `true` を強制する（「評価不能時の不変条件」）。

review-adjudicate-findings.sh は per-finding final_gate の正本であり、hard の集計キーではない。
`final_gate` に `manual` が無い事実は変わらないが、`needs_human` → `manual_review_required=true` の写像は
dispatch が担う。`validity_global_failure:true` は block_layer=audit として扱う。

### hard の post_state

/review-post の終了コードと result の存在を次で写像する。

- 終了コード 0 かつ review-post-result.json を読める場合は post_state=posted。status は posted、
  no_findings、report_only のいずれでもよい。ただし report_only は degraded として
  dispatch_status=incomplete、gate_decision=indeterminate にする。
- **投稿は成功（終了コード 0・result 読める）したが、その後 dispatch が adjudication_ref を
  読めない等で正規化に失敗した場合は、`post_state=posted` を保持しつつ
  `dispatch_status=failed` / `gate_decision=indeterminate` / `blocking_count=null` とする。**
  投稿は実際に起きているので `post_state` は正直に `posted` にする（`failed`+`posted` は許容）。
  false LGTM は `dispatch_status != complete ⟹ lgtm_eligible=false` が防ぐ。
- 終了コード 1（GitHub API 失敗、result は書き込み済み）は post_state=post_failed とし、
  dispatch_status は通常経路のままにする。counts と gate 判定は利用できるが、hard の LGTM は post_state
  の述語によって禁止される。**`post_state=post_failed` のときは `failure_reason` に投稿失敗の理由を
  必ず入れる（`dispatch_status` が `complete` でも）。**
- 終了コード 2、result ファイルなし、または result の parse 不能は dispatch_status=failed、
  post_state=post_failed、gate_decision=indeterminate、blocking_count=null とする。
- status、block_layer、counts.block のいずれかが whitelist 外・欠落・非整数の場合、`post_state` は
  この節の終了コード / result 写像を優先する（終了コード 0 かつ result を読取・parse できるなら
  `posted`、終了コード 1、終了コード 2、result 不在・parse 不能なら `post_failed`）。whitelist 違反
  そのものは `dispatch_status=failed`、`gate_decision=indeterminate`、`blocking_count=null` にだけ
  反映する。「評価不能時の不変条件」により `dispatch_status=failed` では `manual_review_required=true`
  となる（`manual_review` は詳細を構成できなければ null を許容）。status/counts の不正だけで
  `post_state` を `post_failed` にすると、実際には投稿済みでも呼び出し元が再投稿し二重投稿し得るため。
  例: 投稿成功後に whitelist 違反を検出した場合の最終状態は `dispatch_status=failed` /
  `gate_decision=indeterminate` / `blocking_count=null` / `manual_review_required=true` /
  `post_state=posted` / `lgtm_eligible=false`。

投稿しない hard レビューが必要な場合は、従来どおり /codex-hard を直接使う。

## backend 利用不可時

「backend 利用不可」は engine skill（/magi-fast、/magi-hard、/codex-fast、/codex-hard）を起動すら
できない場合を指す。Codex companion 不在、Ollama へ到達できず /magi-* が起動段階で失敗した場合などが
該当する。

この場合は次の envelope にする。hard では engine skill を起動できず投稿自体が発生しないため
`post_state=not_applicable` とする（fast は元々 `not_applicable`）。

```text
dispatch_status:        unavailable
gate_decision:          indeterminate
lgtm_eligible:          false
blocking_count:         null
manual_review_required: true
post_state:             not_applicable
failure_reason:         <理由>
```

その後、該当する review 種別だけ再選択 UI を出す（magi へ切替、codex へ切替、または中止して手動
レビュー）。自動で別 backend へフォールバックせず、切り替えた場合も一方だけを実行する。中止した場合は
unavailable envelope をそのまま返し、呼び出し元は fail-closed に処理する。

/magi-fast 内部の Ollama→Haiku fallback（feedback_magi_haiku_confirmation.md に従う要ユーザー確認）は
engine skill 内で完結するため、backend 利用不可には当たらず、F5 では変更しない。

## 依存元

- scripts/codex-review-merge.sh: fast は pipeline_status、findings、manual_review、failed_personas を出力し、
  hard は加えて artifact_type、grouping_global_failure、validity_global_failure、findings の
  canonical_persona / final_gate を出力する。
- skills/magi-common/references/codex-fast-gate.md: gate の値域は block / defer / manual、verdict の値域は
  valid / false_positive / needs_human。Codex companion の失敗や不正結果は 3 体すべて未判定として LGTM を禁止する。
- skills/flow-common/references/review-post.md: hard の review-post-result.json は .counts.block と .status を持つ。
  review-adjudicate-findings.sh の per-finding final_gate は manual 集計の正本ではない。
