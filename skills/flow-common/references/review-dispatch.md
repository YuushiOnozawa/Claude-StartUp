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
| post_state | posted / post_failed / not_applicable | fast は常に not_applicable。`posted` は投稿完了だけでなく、mutation 後の部分投稿・投稿状況不明を含む保守的な値 |
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

dispatch の実行順序は次のとおり。各手順の詳細は該当節・表を正とし、ここでは繰り返さない。

1. backend を選ぶ（「入力と backend 選択」）。
2. `DISPATCH_TMPDIR=$(mktemp -d)` で返却用の tmpdir を作る。
3. 選んだ engine skill（/magi-fast /magi-hard /codex-fast /codex-hard）を実行する。起動すらできない
   場合は「backend 利用不可時」の envelope にする。
4. hard は engine の完了報告から `dispatch handoff:` 行を取得して検証する（「dispatch handoff 行」）。
   codex hard はこのあと dispatch が /review-post を実行する。
5. hard は ref を事前検証する（「hard の ref 事前検証」）。
6. native の生結果を「fast 正規化」または「hard 正規化と GitHub 投稿」の写像表に通して envelope を組む。
7. envelope を `$DISPATCH_TMPDIR/review-dispatch-result.json` へ書き、validator を実行する（下記）。
8. `$REVIEW_DISPATCH_RESULT` を設定して呼び出し元へ返す。

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

validator が落ちた場合も、下記「dispatch 失敗時の canonical envelope」を返して LGTM を出さない。

### dispatch 失敗時の canonical envelope

engine は最後まで走ったが dispatch 側の検証（`dispatch handoff:` 行、hard の ref 事前検証、validator
自身など）が失敗した場合、dispatch は次の envelope を組んで返す。3 フィールドだけ設定して残りを既定値の
ままにすると、`manual_review_required` の不変条件や `failure_reason` 必須で validator 自身が拒否する
ため、必ず全フィールドをこの値にする。

| フィールド | 値 |
|---|---|
| dispatch_status | `failed` |
| gate_decision | `indeterminate` |
| lgtm_eligible | `false` |
| blocking_count | `null` |
| manual_review_required | `true`（「評価不能時の不変条件」で validator が強制） |
| manual_review | `null`（詳細を構成できないため） |
| artifact_ref / adjudication_ref | `null` |
| post_state | **codex backend**: dispatch の /review-post は未実行で、GitHub へ1件も書き込まれていないと保証できる → `post_failed`（/review-hard 再実行は安全）。**magi backend**: /magi-hard 内部の /review-post が既に走っており投稿状況を dispatch が確認できない → `posted`（保守的。pr-review は再実行を促さず手動確認へ）。fast は `not_applicable`。`dispatch_status=failed` が LGTM を止めるのは両者共通 |
| failure_reason | 非空。どの検証が失敗したか（例: `dispatch handoff 行の result_path 不一致`） |
| native_result | `{}` 可 |

例外は「投稿は成功（/review-post 終了コード 0・result 読取可）したが、その後の正規化で失敗した」場合
だけで、これは「hard の post_state」に従い `post_state=posted` を保持する（`failed` + `posted` は許容）。
より一般に、`post_state=posted` かつ `dispatch_status=failed` の envelope は「GitHub へは投稿された
（可能性が高い）が dispatch が正規化・検証を完了できなかった」を意味する。`pr-review` はこの組合せで
/review-hard の再実行を促さず、既存コメントの手動確認を促す。

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
- 必須 ref が null / run 外 / 読取不能なら「dispatch 失敗時の canonical envelope」を返す。ただし投稿後
  （/review-post 終了コード 0・result 読取可）にこの検査が失敗した場合は、その例外規定に従い
  `post_state=posted` を保持する。

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
dispatch が解決した forge host を `forge_host` に引き継ぎ、未指定時は `github.com` とする。
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
- 行の欠落、不正 JSON、非絶対パス、`request` の読取不能は dispatch 失敗として扱い、「dispatch 失敗時の
  canonical envelope」を返す。
- dispatch は取得した `request` / `result` パス自体も検証する（「hard の ref 事前検証」が対象にする
  request `.inputs` の成果物 ref とは別物）。
  - 両パスを絶対パスへ正規化し、当該 run の engine tmpdir または dispatch handoff 配下に含まれる
    ことを確認する。外部から与えられた任意の絶対パスは受け入れない。
  - `result` が `request` の `.result_path` と一致することを確認する（不一致は別 run の result を
    取り込んでいる兆候）。
  - `request` の `.pr.owner` / `.pr.repo` / `.pr.number` / `.pr.head_sha` が、dispatch がこの engine
    skill を起動したときの PR と head SHA（dispatch 自身が起動しているため常に既知）と一致することを
    確認する（stale run の取り込み防止）。
  - いずれかが不一致・確認不能なら、上と同じく「dispatch 失敗時の canonical envelope」を返す。

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
| manual_review_required | adjudication result の `results[]` と `validity_global_failure` | `results[].verdict=="needs_human"` が1件以上、`results[].importance_status=="failed"` が1件以上、または `validity_global_failure==true` なら true。それ以外 false。`importance_status` の値域と `failed` 判定の正本は `scripts/review-adjudicate-findings.sh`（`importance` 値が null のとき `failed`） |
| manual_review | 上記の要人手確認内容 | true のとき `needs_human` の finding id 一覧と `importance_status=="failed"` の finding id 一覧を載せ、`validity_global_failure==true` は別記する。それ以外 null |
| artifact_ref | request .inputs.findings_artifact | structure 経路では null |
| adjudication_ref | request `.inputs.adjudication_result` | structure 経路では null（正当）。通常経路（`gate_decision ∈ {lgtm,block}`）で null または読めない場合は `dispatch_status=failed`。同じ規則を `artifact_ref` にも適用する（上記「hard の ref 事前検証」） |
| native_result | result の .counts / .items / .grounding_status / `github_writes` など | 呼び出し元は分岐に使わない。`pr-review` の再実行ガードは `post_state` と `dispatch_status`（共通キー）だけで判断し、`github_writes` は人間がコメント状況を確認するための情報にとどめる |

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
  ただし `block_layer=importance` は投稿経路としては通常でも重要度判定が失敗している。未評価 finding は
  `final_gate=defer` に落ちて `.counts.block` に現れないため `.counts.block` だけでは検知できない。
  adjudication result の `importance_status=="failed"` を `manual_review_required` へ写像して LGTM を
  防ぐ（上表 `manual_review_required` 行）。この写像は adjudication result 経由なので magi / codex の
  両 backend に等しく効く。

`manual_review_required` の扱いは degraded 種別で分かれる。`incomplete + structure` は `false` を許容、
`incomplete + audit` は `true`、`dispatch_status ∈ {failed, unavailable}` は
`scripts/review-dispatch-envelope.sh` が `true` を強制する（「評価不能時の不変条件」）。

review-adjudicate-findings.sh は per-finding final_gate の正本であり、hard の集計キーではない。
`final_gate` に `manual` が無い事実は変わらないが、`needs_human` → `manual_review_required=true` の写像は
dispatch が担う。`validity_global_failure:true` は block_layer=audit として扱う。

### hard の post_state

/review-post の終了コードと result の存在を次で写像する。

`post_state=post_failed` は「dispatch が GitHub へ1件も書き込まれていないと保証できる場合」
（`/review-post` 未実行、または `/review-post` 終了コード 2 = API 呼び出し前の契約違反）に限る。
それ以外の失敗は `post_state=posted`（write 状況不明を保守的に投稿済み扱い）とし、`pr-review` は
盲目的な /review-hard 再実行をしない。分岐は共通キー（`post_state` / `dispatch_status`）だけで行い、
`github_writes` の中身は使わない。

- 終了コード 0 かつ review-post-result.json を読める場合は post_state=posted。status は posted、
  no_findings、report_only のいずれでもよい。ただし report_only は degraded として
  dispatch_status=incomplete、gate_decision=indeterminate にする。
- **投稿は成功（終了コード 0・result 読める）したが、その後 dispatch が adjudication_ref を
  読めない等で正規化に失敗した場合は、`post_state=posted` を保持しつつ
  `dispatch_status=failed` / `gate_decision=indeterminate` / `blocking_count=null` とする。**
  投稿は実際に起きているので `post_state` は正直に `posted` にする（`failed`+`posted` は許容）。
  false LGTM は `dispatch_status != complete ⟹ lgtm_eligible=false` が防ぐ。
- 終了コード 1（`review-post.md` の定義上、サマリを含むいずれかの GitHub API 呼び出しの失敗）は
  post_state=posted、dispatch_status=failed、gate_decision=indeterminate、blocking_count=null、
  `failure_reason` 非空とする。`github_writes` が空でも未投稿の証明にはならない（サーバ受理後の
  タイムアウトや応答解析失敗でも空になり得る）ため、`github_writes` の中身で post_failed と posted を
  分けない。hard の LGTM は `dispatch_status != complete` の述語で止まる。
- 終了コード 2（`review-post.md` の契約上、request / 入力 artifact の契約違反、または managed lease admission
  failure であり、この検証より前に GitHub mutation を呼び出してはならない ＝ 未投稿を保証できる）は
  `dispatch_status=failed`、`post_state=post_failed`、`gate_decision=indeterminate`、`blocking_count=null`、
  `manual_review_required=true` とする。verify の lease_id 不一致、released / force-released、owner token 消失、
  post lock 内の再確認失敗、投稿直前 renew の `not_owner` / I/O 失敗を含む。`/review-hard` の再実行は安全である。
- `/review-post` を起動した後の異常終了、result ファイルなし、または result の parse 不能（終了コード 2
  以外で write 状況が不明）は dispatch_status=failed、post_state=posted（保守的）、
  gate_decision=indeterminate、blocking_count=null、`failure_reason` 非空とする。
- status、block_layer、counts.block のいずれかが whitelist 外・欠落・非整数の場合、`post_state` は
  この節の終了コード / result 写像を優先する（終了コード 0 かつ result を読取・parse できるなら
  `posted`、終了コード 2 なら `post_failed`、終了コード 1 と「起動後の異常終了・result 不在・parse
  不能」は `posted`）。whitelist 違反
  そのものは `dispatch_status=failed`、`gate_decision=indeterminate`、`blocking_count=null` にだけ
  反映する。「評価不能時の不変条件」により `dispatch_status=failed` では `manual_review_required=true`
  となる（`manual_review` は詳細を構成できなければ null を許容）。status/counts の不正だけで
  `post_state` を `post_failed` にすると、実際には投稿済みでも呼び出し元が再投稿し二重投稿し得るため。
  例: 投稿成功後に whitelist 違反を検出した場合の最終状態は `dispatch_status=failed` /
  `gate_decision=indeterminate` / `blocking_count=null` / `manual_review_required=true` /
  `post_state=posted` / `lgtm_eligible=false`。

投稿しない hard レビューが必要な場合は、従来どおり /codex-hard を直接使う。

## 単一飛行制御（single-flight, hard 専用）

この節は `review_kind==hard` のゲート下にのみ適用する。`/review-fast` は一切変更せず、lease、post lock、
`review-post` の managed request を持たない。#411 の helper が扱う lease scope は `per_pr` のみであり、
broker 層の lease は追加しない（PR-2 の `codex-broker-run.sh` が、実際の Codex task 呼び出し境界を担当する）。

`/review-hard` は次の順に実行する。

1. **A1 PR 識別解決**: `forge_host`、owner、repo、number、`head_sha` を解決し、owner/repo を小文字化した
   canonical key `"{forge_host}\n{owner}/{repo}\n{pr_number}"` を作る。`head_sha` は key に含めず metadata に保存する。
2. **A2 backend 選択**: `magi` または `codex` を決定する。lease の metadata と unavailable envelope の
   `backend` は、この選択後の値を使う。
3. **A3 入力検証**: PR、backend、diff、依存コマンド、request 契約を検証する。ここまでは lease を取得しない。
4. **A4 state bootstrap**: `DISPATCH_TMPDIR=$(mktemp -d)` を作り、`umask 077` 下で UUID の
   `sf-owner-token` と atomic rename の `dispatch-state.json` を作る。owner token、lease_id、cleanup 状態は
   このファイル正本で引き渡し、独立 Bash 呼び出し間の env / shell variable 継承に依存しない。
5. **H1 startup sweep**: `review-singleflight.sh sweep --scope per_pr` を実行する。`stale_suspected` は列挙
   するだけで削除しない。
6. **H2 admission**: run 開始時に実際の chunk 数・persona/task 数から `planned_overdue_at` を導出し、
   backend 選択後に次の完全な helper 契約で実行する。`SF_ENGINE=review-hard` とし、
   `SF_PLANNED_OVERDUE` は `execution-budget.sh max-allowance <backend>` を上限に実 chunk/persona 数から算出し、
   acquire 時点で実 chunk/persona 数が未確定または算出不能なら max-allowance をそのまま使う。

   ```bash
   SF_ENGINE=review-hard
   SF_PLANNED_OVERDUE="$(bash "$BUDGET_HELPER" max-allowance "$BACKEND" 2>/dev/null || true)"
   bash "$SF_HELPER" acquire --scope per_pr --key "$SF_CANONICAL_KEY" \
     --owner-token-file "$DISPATCH_TMPDIR/sf-owner-token" \
     --engine "$SF_ENGINE" --head-sha "$HEAD_SHA" \
     --overdue-seconds "$SF_PLANNED_OVERDUE" \
     --owner-session-id "$SF_SESSION_ID" --owner-run-id "$SF_RUN_ID" --host "$SF_HOST" \
     --artifact-path "$DISPATCH_TMPDIR/engine-artifact.json" --log-path "$DISPATCH_TMPDIR/engine.log" \
     > "$DISPATCH_TMPDIR/acquire.json"
   SF_ACQUIRE_JSON="$(jq -c '.' "$DISPATCH_TMPDIR/acquire.json")"
   ```

acquire が `held` または `stale_suspected`（その他の fail-closed を含む）なら、待機・自動 takeover・backend
再選択をせず、次の canonical hard envelope を作って exit 2 で停止する。stderr には holder の `lease_id`、
`token_fp`、owner session/run、開始時刻、engine、残り時間、`status` の確認手順、そのまま貼れる
`--force-release --expected-lease-id <id> --reason "<text>"` 手順を出す。`owner_token` は stdout、stderr、
status、envelope、ログのいずれにも出さない。「TTL 失効済みでも旧 owner が生存していれば force-release は
二重投稿を招き得る」警告も表示し、backend 再選択 UI は表示しない。

fail-fast envelope は builder 自身がキー集合を canonical 15 個と完全一致することを検証してから
`$DISPATCH_TMPDIR/review-dispatch-result.json` に書く（validator が余分なキーを弾かないため）。値は次のとおり。

```text
schema_version:          "1"
artifact_type:           "review-dispatch-result"
review_kind:             "hard"
backend:                 <A2 の選択値>
dispatch_status:         "unavailable"
gate_decision:           "indeterminate"
lgtm_eligible:           false
blocking_count:          null
manual_review_required:  true
manual_review:           null
artifact_ref:             null
adjudication_ref:         null
post_state:               "not_applicable"
failure_reason:           <非空の lock admission 理由>
native_result:            {}
```

builder 自己検証後に `bash scripts/review-dispatch-envelope.sh validate "$REVIEW_DISPATCH_RESULT"` を通し、
`$REVIEW_DISPATCH_RESULT` には絶対パスだけを返す。builder または validator が失敗した場合も同じ
canonical failed envelope を再生成し、再生成不能なら `$REVIEW_DISPATCH_RESULT` を未設定のまま明示的に
fail-closed とする。

acquire 成功後は `dispatch-state.json` の `per_pr.acquired=true` と `lease_id` を永続化し、
`DISPATCH_TMPDIR`、`DISPATCH_STATE`、`SF_CANONICAL_KEY`、取得した `SF_LEASE_ID`、および
`singleflight.json` のパスを handoff として返して終了する。各 phase 開始前は
`bash scripts/review-singleflight.sh verify --scope per_pr --key "$CANONICAL_KEY"`
（`owner_token_file` と `lease_id` を明示）で owner token / lease_id を再確認し、不一致・失効・token 消失時は
後続 phase と GitHub 副作用へ進まない。engine（`/magi-hard` または `/codex-hard`）へは
`singleflight` object を request JSON に渡し、engine が `/review-post` request へそのまま引き継ぐ。

以下の Bash ブロックは A4/H1/H2、managed object の生成、acquire、fail-fast envelope の生成・検証、handoff の
返却までを実装する。engine、review-post、CLEANUP はこの関数の呼び出し元である対話的 Claude セッションの責務である。

```bash
review_hard_dispatch() {
  local SAVED_RC=0 ACQUIRE_RC=0 STATE_TMP
  local ACQUIRE_JSON DISPATCH_HANDOFF
  WORKTREE_ROOT="${WORKTREE_ROOT:-$(git rev-parse --show-toplevel 2>/dev/null || pwd)}"
  BACKEND="${REVIEW_HARD_BACKEND:-${BACKEND:-}}"
  [[ "$BACKEND" == magi || "$BACKEND" == codex ]] || return 2
  FORGE_HOST="${FORGE_HOST:-github.com}"
  SF_CANONICAL_KEY="${CANONICAL_KEY:-$(printf '%s\n%s/%s\n%s' "$FORGE_HOST" "${OWNER,,}" "${REPO,,}" "$PR_NUM")}"
  HEAD_SHA="${HEAD_SHA:?HEAD_SHA is required}"
  SF_ENGINE=review-hard
  SF_SESSION_ID="${SF_SESSION_ID:-${CLAUDE_SESSION_ID:-unknown-session}}"
  SF_RUN_ID="${SF_RUN_ID:-${RUN_ID:-unknown-run}}"
  SF_HOST="${SF_HOST:-$(hostname 2>/dev/null || printf '%s' unknown)}"
  SF_HELPER="${SF_HELPER:-$WORKTREE_ROOT/scripts/review-singleflight.sh}"
  [[ -r "$SF_HELPER" ]] || SF_HELPER="${HOME:-}/.claude/scripts/review-singleflight.sh"
  ENVELOPE_HELPER="${ENVELOPE_HELPER:-$WORKTREE_ROOT/scripts/review-dispatch-envelope.sh}"
  [[ -r "$ENVELOPE_HELPER" ]] || ENVELOPE_HELPER="${HOME:-}/.claude/scripts/review-dispatch-envelope.sh"
  STATE_HELPER="${STATE_HELPER:-$WORKTREE_ROOT/scripts/review-dispatch-state.sh}"
  [[ -r "$STATE_HELPER" ]] || STATE_HELPER="${HOME:-}/.claude/scripts/review-dispatch-state.sh"
  BUDGET_HELPER="$WORKTREE_ROOT/skills/flow-common/execution-budget.sh"
  [[ -r "$BUDGET_HELPER" ]] || BUDGET_HELPER="${HOME:-}/.claude/skills/flow-common/execution-budget.sh"
  [[ -r "$SF_HELPER" && -r "$ENVELOPE_HELPER" && -r "$STATE_HELPER" ]] || return 2
  SF_HELPER="$(realpath -m -- "$SF_HELPER")"
  ENVELOPE_HELPER="$(realpath -m -- "$ENVELOPE_HELPER")"
  STATE_HELPER="$(realpath -m -- "$STATE_HELPER")"

  DISPATCH_TMPDIR="$(mktemp -d)" || return 2
  chmod 700 "$DISPATCH_TMPDIR" || return 2
  DISPATCH_STATE="$DISPATCH_TMPDIR/dispatch-state.json"
  SF_TOKEN_FILE="$DISPATCH_TMPDIR/sf-owner-token"
  ( umask 077 && jq -n \
      --arg tmpdir "$DISPATCH_TMPDIR" --arg dispatch_state "$DISPATCH_STATE" --arg backend "$BACKEND" \
      --arg state_helper "$STATE_HELPER" --arg sf_helper "$SF_HELPER" --arg envelope_helper "$ENVELOPE_HELPER" \
      --arg canonical_key "$SF_CANONICAL_KEY" --arg owner_token_file "$SF_TOKEN_FILE" \
      '{schema_version:"1",phase:"init",tmpdir:$tmpdir,dispatch_state:$dispatch_state,backend:$backend,state_helper:$state_helper,sf_helper:$sf_helper,envelope_helper:$envelope_helper,canonical_key:$canonical_key,owner_token_file:$owner_token_file,singleflight_file:($tmpdir + "/singleflight.json"),lease_id:null,per_pr:{acquired:false},saved_rc:0,post_state:"not_started"}' \
      > "$DISPATCH_STATE.tmp" && mv -f "$DISPATCH_STATE.tmp" "$DISPATCH_STATE" ) || return 2
  ( umask 077 && python3 -c 'import uuid;print(uuid.uuid4())' > "$SF_TOKEN_FILE" ) || return 2
  sf_state_set() {
    local filter="$1"; shift
    bash "$STATE_HELPER" set --dispatch-state "$DISPATCH_STATE" --filter "$filter" "$@"
  }
  sf_state_set '.owner_token_file=$token_file' --arg token_file "$SF_TOKEN_FILE" || return 5

  sf_release_after_acquire() {
    local release_rc=0
    timeout 10 bash "$SF_HELPER" release --scope per_pr --key "$SF_CANONICAL_KEY" \
      --owner-token-file "$SF_TOKEN_FILE" --lease-id "$SF_LEASE_ID" \
      >"$DISPATCH_TMPDIR/release-after-acquire.json" 2>"$DISPATCH_TMPDIR/release-after-acquire.err" || release_rc=$?
    if [[ "$release_rc" -ne 0 ]]; then
      echo "review-dispatch: acquire 後の初期化失敗時に lease release も失敗しました（stale_suspected）" >&2
    fi
    return "$release_rc"
  }

  abort_after_acquire() {
    local release_rc=0
    local state_rc=0 fallback_rc=0
    sf_release_after_acquire || release_rc=$?
    SAVED_RC=5
    if [[ "$release_rc" -eq 0 ]]; then
      sf_state_set '.per_pr.acquired=false | .saved_rc=$rc | .phase="aborted"' --argjson rc "$SAVED_RC" || state_rc=$?
      if [[ "$state_rc" -ne 0 ]]; then
        echo "review-dispatch: abort 後の dispatch-state.json 更新に失敗しました（release_rc=$release_rc）。正本が実態と乖離している可能性があります。stale_suspected として扱ってください" >&2
        sf_state_set '.saved_rc=$rc | .phase="cleanup_failed"' --argjson rc "$SAVED_RC" || fallback_rc=$?
        if [[ "$fallback_rc" -ne 0 ]]; then
          echo "review-dispatch: abort 後の dispatch-state.json フォールバック更新にも失敗しました（release_rc=$release_rc）。正本が実態と乖離している可能性があります。stale_suspected として扱ってください" >&2
        fi
      fi
    else
      sf_state_set '.saved_rc=$rc | .phase="cleanup_failed"' --argjson rc "$SAVED_RC" || state_rc=$?
      if [[ "$state_rc" -ne 0 ]]; then
        echo "review-dispatch: abort 後の dispatch-state.json 更新に失敗しました（release_rc=$release_rc）。正本が実態と乖離している可能性があります。stale_suspected として扱ってください" >&2
      fi
      echo "review-dispatch: lease を自動解放できないため fail-closed で終了します" >&2
    fi
  }

  SF_MAX_ALLOWANCE="$(bash "$BUDGET_HELPER" max-allowance "$BACKEND" 2>/dev/null || true)"
  SF_CHUNK_COUNT="${SF_CHUNK_COUNT:-${DIFF_CHUNK_COUNT:-}}"; SF_PERSONA_COUNT="${SF_PERSONA_COUNT:-}"
  SF_PER_CHUNK="$(bash "$BUDGET_HELPER" generation-factor per_chunk_seconds "$BACKEND" 2>/dev/null || true)"
  SF_POST_BUDGET="$(bash "$BUDGET_HELPER" get review_post "$BACKEND" 2>/dev/null || true)"
  if [[ "$SF_MAX_ALLOWANCE" =~ ^[1-9][0-9]*$ && "$SF_CHUNK_COUNT" =~ ^[1-9][0-9]*$ && "$SF_PERSONA_COUNT" =~ ^[1-9][0-9]*$ && "$SF_PER_CHUNK" =~ ^[1-9][0-9]*$ ]]; then
    [[ "$SF_POST_BUDGET" =~ ^[1-9][0-9]*$ ]] || SF_POST_BUDGET=3120
    SF_PLANNED_OVERDUE=$((SF_CHUNK_COUNT * SF_PERSONA_COUNT * SF_PER_CHUNK + SF_POST_BUDGET))
    (( SF_PLANNED_OVERDUE > SF_MAX_ALLOWANCE )) && SF_PLANNED_OVERDUE="$SF_MAX_ALLOWANCE"
  else
    SF_PLANNED_OVERDUE="${SF_MAX_ALLOWANCE:-3120}"
  fi
  [[ "$SF_PLANNED_OVERDUE" =~ ^[1-9][0-9]*$ ]] || SF_PLANNED_OVERDUE=3120

  sf_write_envelope() {
    local status="$1" post_state="$2" reason="$3"
    bash "$STATE_HELPER" write-envelope --dispatch-state "$DISPATCH_STATE" --dispatch-tmpdir "$DISPATCH_TMPDIR" \
      --sf-helper "$SF_HELPER" --envelope-helper "$ENVELOPE_HELPER" --canonical-key "$SF_CANONICAL_KEY" \
      --backend "$BACKEND" --status "$status" --post-state "$post_state" --reason "$reason" || return $?
    REVIEW_DISPATCH_RESULT="$(realpath -m -- "$DISPATCH_TMPDIR/review-dispatch-result.json")"; export REVIEW_DISPATCH_RESULT
  }
  while :; do
    if ! bash "$SF_HELPER" sweep --scope per_pr >"$DISPATCH_TMPDIR/sweep.json" 2>"$DISPATCH_TMPDIR/sweep.err"; then SAVED_RC=2; sf_state_set '.saved_rc=$rc | .phase="sweep_failed"' --argjson rc "$SAVED_RC" || true; sf_write_envelope unavailable not_applicable "singleflight sweep failed" || true; break; fi
    ACQUIRE_RC=0; ACQUIRE_JSON="$DISPATCH_TMPDIR/acquire.json"
    bash "$SF_HELPER" acquire --scope per_pr --key "$SF_CANONICAL_KEY" --owner-token-file "$DISPATCH_TMPDIR/sf-owner-token" \
      --engine "$SF_ENGINE" --head-sha "$HEAD_SHA" --overdue-seconds "$SF_PLANNED_OVERDUE" \
      --owner-session-id "$SF_SESSION_ID" --owner-run-id "$SF_RUN_ID" --host "$SF_HOST" \
      --artifact-path "$DISPATCH_TMPDIR/engine-artifact.json" --log-path "$DISPATCH_TMPDIR/engine.log" \
      >"$ACQUIRE_JSON" 2>"$DISPATCH_TMPDIR/acquire.err" || ACQUIRE_RC=$?
    if [[ "$ACQUIRE_RC" -ne 0 ]] || ! jq -e '.state == "acquired" and (.lease_id|type)=="string" and (.token_fp|type)=="string" and (.planned_overdue_at|type)=="number"' "$ACQUIRE_JSON" >/dev/null 2>&1; then SAVED_RC=2; sf_state_set '.saved_rc=$rc | .phase="admission_failed"' --argjson rc "$SAVED_RC" || true; sf_write_envelope unavailable not_applicable "per_pr admission failed" || true; break; fi
    SF_ACQUIRE_JSON="$(jq -c '.' "$ACQUIRE_JSON")"
    SF_LEASE_ID="$(jq -r '.lease_id' <<<"$SF_ACQUIRE_JSON")"
    if ! sf_state_set '.per_pr.acquired=true | .per_pr.lease_id=$lease_id | .lease_id=$lease_id | .owner_token_file=$owner_token_file | .phase="acquired" | .post_state="not_started"' \
      --arg lease_id "$SF_LEASE_ID" --arg owner_token_file "$SF_TOKEN_FILE"; then
      abort_after_acquire
      break
    fi
    if ! SF_OBJECT="$(jq -cn --arg tmpdir "$DISPATCH_TMPDIR" --arg owner_token_file "$SF_TOKEN_FILE" --arg canonical_key "$SF_CANONICAL_KEY" --arg lease_id "$SF_LEASE_ID" --arg forge_host "$FORGE_HOST" --arg helper "$SF_HELPER" --arg lease_file_ref "$DISPATCH_STATE" \
      '{managed_by:"review-hard",tmpdir:$tmpdir,owner_token_file:$owner_token_file,lease_file_ref:$lease_file_ref,canonical_key:$canonical_key,lease_id:$lease_id,forge_host:$forge_host,scope:"per_pr",helper:$helper}')"; then
      abort_after_acquire
      break
    fi
    if ! printf '%s' "$SF_OBJECT" > "$DISPATCH_TMPDIR/singleflight.json" \
      || ! chmod 600 "$DISPATCH_TMPDIR/singleflight.json"; then
      abort_after_acquire
      break
    fi
    export DISPATCH_TMPDIR DISPATCH_STATE SF_CANONICAL_KEY SF_TOKEN_FILE SF_LEASE_ID \
      REVIEW_HARD_SINGLEFLIGHT_JSON="$DISPATCH_TMPDIR/singleflight.json"
    if ! sf_state_set '.phase="engine_running" | .post_state="in_progress"'; then
      abort_after_acquire
      break
    fi
    if ! DISPATCH_HANDOFF="$(jq -cn --arg backend "$BACKEND" --arg tmpdir "$DISPATCH_TMPDIR" --arg dispatch_state "$DISPATCH_STATE" \
      --arg canonical_key "$SF_CANONICAL_KEY" --arg lease_id "$SF_LEASE_ID" --arg singleflight "$DISPATCH_TMPDIR/singleflight.json" \
      '{backend:$backend,tmpdir:$tmpdir,dispatch_state:$dispatch_state,canonical_key:$canonical_key,lease_id:$lease_id,singleflight:$singleflight}')"; then
      abort_after_acquire
      break
    fi
    printf 'review-dispatch handoff: %s\n' "$DISPATCH_HANDOFF"
    SAVED_RC=0
    break
  done
  return "$SAVED_RC"
}
review_hard_dispatch

```json
{
  "managed_by": "review-hard",
  "tmpdir": "<DISPATCH_TMPDIR>",
  "owner_token_file": "<DISPATCH_TMPDIR>/sf-owner-token",
  "lease_file_ref": "<DISPATCH_TMPDIR>/dispatch-state.json",
  "scope": "per_pr",
  "canonical_key": "<forge_host>\n<owner>/<repo>\n<number>",
  "lease_id": "<current per_pr lease_id>",
  "forge_host": "<resolved forge_host>"
}
```

`dispatch-state.json` は handoff 後の独立 Bash 呼び出しが自己完結できる正本でもある。次の値を保存し、
呼び出し元は handoff の `dispatch_state` だけを次の各ブロックの先頭へ明示的に再代入する。
`tmpdir`、`backend`、`state_helper`、`sf_helper`、`envelope_helper`、`canonical_key`、
`owner_token_file`、`lease_id`、`singleflight_file` は state から `jq -er` で再導出する。
この方式を選ぶ理由は、engine 実行をまたぐ呼び出し元の記憶・環境変数継承に依存せず、handoff の JSON だけを
再入力すれば後続ブロックを再現できるためである。

## engine 実行と cleanup（呼び出し元の責務）

`review_hard_dispatch()` が成功して handoff を返した後は、この Bash 関数を実行した対話的 Claude セッション自身が、
返された `backend` に応じて `skills/magi-hard/SKILL.md` または `skills/codex-hard/SKILL.md` を Read し、その手順に従って
engine skill を実行する。Markdown の Bash ブロックを `/magi-hard` や `/codex-hard` の外部スクリプトとして起動してはならない。
`DISPATCH_TMPDIR`、`DISPATCH_STATE`（`dispatch-state.json` の絶対パス）、`SF_CANONICAL_KEY`、`SF_LEASE_ID`、
`singleflight.json` のパス、および singleflight object は handoff の値をそのまま request に引き継ぐ。

以下の結果処理ブロックと cleanup ブロックは、engine skill を実行した Bash 呼び出しとは別のプロセスで実行してよい。
前の呼び出しで定義した関数・shell variable・export は引き継がれないため、各ブロックの先頭で handoff の
`dispatch_state` 絶対パスを `DISPATCH_STATE="<handoff JSON の .dispatch_state>"` として再代入し、そこから必要な値を
`jq -er` で再導出する。以下のブロック中の `<...>` は、直前に保存した handoff JSON の実値へ置換する。

engine skill は `dispatch handoff: {"request":"<絶対パス>","result":"<絶対パス>"}` 行を返し、呼び出し元は
その request/result を検証する。各 phase 開始前には次を実行し、owner token と lease_id を再確認する。

```bash
bash scripts/review-singleflight.sh verify --scope per_pr --key "$SF_CANONICAL_KEY" \
  --owner-token-file "$SF_TOKEN_FILE" --lease-id "$SF_LEASE_ID"
```

verify が不一致・失効・token 消失で失敗した場合は、後続 phase と GitHub 副作用へ進まない。engine skill の実行が完了せず
所定の handoff/result を返さなかった場合（handoff 行が出力されない、エラー終了、または skill 自体を Read できない場合を含む）は、
旧 `ENGINE_RC=127` の分岐と同じ「backend 利用不可」判定として扱い、`dispatch_status=unavailable`、
`post_state=not_applicable`、`gate_decision=indeterminate`、`blocking_count=null`、
`manual_review_required=true`、非空の `failure_reason` を持つ envelope を返す。実行後の検証失敗や投稿状況不明は、
既存の hard の `failed` / `posted` 写像に従う。

engine skill の完了後は `skills/review-post/SKILL.md` を Read して手順に従い、engine が生成した
`REVIEW_POST_REQUEST` を `/review-post "$REVIEW_POST_REQUEST"` として実行する。実行後は `$REVIEW_POST_RESULT` を読み、
投稿完了、または終了コード 1/2 の理由を確認する。magi backend では `/magi-hard` のステップ6、codex backend では handoff の
request を `/review-post` へ渡す段階がこの責務に当たる。

engine skill の出力から handoff 行の JSON 部分を `$DISPATCH_TMPDIR/handoff.json` に保存し、実際の skill の終了コードを
`ENGINE_RC` に設定してから、次の結果処理を行う。ここで行う envelope の写像、result 検証、canonical envelope の検証は、
従来の dispatch runtime と同じである。

```bash
DISPATCH_STATE="<handoff JSON の .dispatch_state の絶対パス>"
[[ "$DISPATCH_STATE" == /* && -r "$DISPATCH_STATE" ]] || { echo "review-dispatch: dispatch state がありません" >&2; exit 1; }
DISPATCH_TMPDIR="$(jq -er '.tmpdir' "$DISPATCH_STATE")"
BACKEND="$(jq -er '.backend' "$DISPATCH_STATE")"
STATE_HELPER="$(jq -er '.state_helper' "$DISPATCH_STATE")"
SF_HELPER="$(jq -er '.sf_helper' "$DISPATCH_STATE")"
ENVELOPE_HELPER="$(jq -er '.envelope_helper' "$DISPATCH_STATE")"
SF_CANONICAL_KEY="$(jq -er '.canonical_key' "$DISPATCH_STATE")"
SF_TOKEN_FILE="$(jq -er '.owner_token_file' "$DISPATCH_STATE")"
SF_LEASE_ID="$(jq -er '.lease_id' "$DISPATCH_STATE")"
SINGLEFLIGHT_FILE="$(jq -er '.singleflight_file' "$DISPATCH_STATE")"
[[ "$DISPATCH_TMPDIR" == /* && "$STATE_HELPER" == /* && "$SF_HELPER" == /* && "$ENVELOPE_HELPER" == /* \
  && "$SF_TOKEN_FILE" == /* && "$SF_LEASE_ID" != "null" && "$SINGLEFLIGHT_FILE" == /* ]] \
  || { echo "review-dispatch: dispatch state の値が不正です" >&2; exit 1; }
[[ -r "$STATE_HELPER" && -r "$SF_HELPER" && -r "$ENVELOPE_HELPER" ]] || { echo "review-dispatch: helper がありません" >&2; exit 1; }
STATE_SET=(bash "$STATE_HELPER" set --dispatch-state "$DISPATCH_STATE")
WRITE_ENVELOPE=(bash "$STATE_HELPER" write-envelope --dispatch-state "$DISPATCH_STATE" --dispatch-tmpdir "$DISPATCH_TMPDIR" \
  --sf-helper "$SF_HELPER" --envelope-helper "$ENVELOPE_HELPER" --canonical-key "$SF_CANONICAL_KEY" --backend "$BACKEND")

ENGINE_CONTINUE=true
if [[ ! "${ENGINE_RC:-}" =~ ^(0|[1-9][0-9]*)$ ]]; then
  ENGINE_RC=1
  ENGINE_FAILURE_REASON="engine skill の終了コードが未設定または不正"
else
  ENGINE_FAILURE_REASON="engine skill の実行が完了せず所定の handoff/result を返さなかった"
fi
if [[ "$ENGINE_RC" -ne 0 ]]; then
  ENGINE_POST_STATE="$(jq -r '.post_state // empty' "$DISPATCH_STATE" 2>/dev/null || true)"
  if [[ "$BACKEND" == magi && "$ENGINE_POST_STATE" == posted ]]; then
    SAVED_RC=1
    "${WRITE_ENVELOPE[@]}" --status failed --post-state posted --reason "MAGI review-post の投稿後に終了したため投稿状況を確認できません" || true
  elif [[ "$BACKEND" == magi && "$ENGINE_RC" -eq 2 && "$ENGINE_POST_STATE" == post_failed ]]; then
    SAVED_RC=2
    "${WRITE_ENVELOPE[@]}" --status failed --post-state post_failed --reason "review-post managed guard failure; GitHub mutation 未実行" || true
  else
    SAVED_RC=1
    "${WRITE_ENVELOPE[@]}" --status unavailable --post-state not_applicable --reason "$ENGINE_FAILURE_REASON" || true
  fi
  "${STATE_SET[@]}" --filter '.saved_rc=$rc | .phase="engine_failed"' --argjson rc "$SAVED_RC" || true
  ENGINE_CONTINUE=false
fi

HANDOFF_JSON="$DISPATCH_TMPDIR/handoff.json"
if [[ "$ENGINE_CONTINUE" == true ]] \
  && { ! jq -e 'type=="object" and (.request|type)=="string" and (.result|type)=="string"' "$HANDOFF_JSON" >/dev/null 2>&1; }; then
  SAVED_RC=1
  "${STATE_SET[@]}" --filter '.saved_rc=$rc | .phase="handoff_failed"' --argjson rc "$SAVED_RC" || true
  "${WRITE_ENVELOPE[@]}" --status unavailable --post-state not_applicable --reason "engine skill の実行が完了せず所定の handoff/result を返さなかった" || true
  ENGINE_CONTINUE=false
fi

if [[ "$ENGINE_CONTINUE" == true ]]; then
  REQUEST_FILE="$(jq -r '.request' "$HANDOFF_JSON")"
  RESULT_FILE="$(jq -r '.result' "$HANDOFF_JSON")"
  if [[ "$REQUEST_FILE" != /* || "$RESULT_FILE" != /* || ! -r "$REQUEST_FILE" ]]; then
    SAVED_RC=1
    "${STATE_SET[@]}" --filter '.saved_rc=$rc | .phase="handoff_ref_failed"' --argjson rc "$SAVED_RC" || true
    "${WRITE_ENVELOPE[@]}" --status failed --post-state posted --reason "handoff ref が不正" || true
    ENGINE_CONTINUE=false
  fi
fi

if [[ "$ENGINE_CONTINUE" == true && "$BACKEND" == codex ]]; then
  # この直前に Claude 自身が Read 済みの review-post skill に従って /review-post を実行し、
  # その終了コードを POST_RC に設定しておく。
  if [[ ! "${POST_RC:-}" =~ ^(0|[1-9][0-9]*)$ ]]; then
    POST_RC=1
    POST_FAILURE_REASON="review-post の終了コードが未設定または不正"
  else
    POST_FAILURE_REASON="review-post の終了コードが非0"
  fi
  if [[ "$POST_RC" -eq 2 && ! -s "$RESULT_FILE" ]]; then
    SAVED_RC=2
    "${STATE_SET[@]}" --filter '.saved_rc=$rc | .phase="post_failed" | .post_state="post_failed"' --argjson rc "$SAVED_RC" || true
    "${WRITE_ENVELOPE[@]}" --status failed --post-state post_failed --reason "review-post managed guard failure; GitHub mutation 未実行" || true
    ENGINE_CONTINUE=false
  elif [[ "$POST_RC" -eq 3 ]]; then
    SAVED_RC=1
    "${STATE_SET[@]}" --filter '.saved_rc=$rc | .phase="post_partial" | .post_state="posted"' --argjson rc "$SAVED_RC" || true
    "${WRITE_ENVELOPE[@]}" --status failed --post-state posted --reason "review-post fencing failure after GitHub mutation; 投稿済みまたは投稿状況不明" || true
    ENGINE_CONTINUE=false
  elif [[ "$POST_RC" -ne 0 ]]; then
    SAVED_RC=1
    "${STATE_SET[@]}" --filter '.saved_rc=$rc | .phase="post_unknown" | .post_state="unknown"' --argjson rc "$SAVED_RC" || true
    "${WRITE_ENVELOPE[@]}" --status failed --post-state posted --reason "$POST_FAILURE_REASON" || true
    ENGINE_CONTINUE=false
  fi
fi

if [[ "$ENGINE_CONTINUE" == true ]]; then
  if [[ ! -s "$RESULT_FILE" ]] || ! jq -e 'type=="object" and (.status|IN("posted","no_findings")) and (.counts.block|type)=="number" and (.counts.block|floor)==.counts.block and .counts.block >= 0' "$RESULT_FILE" >/dev/null 2>&1; then
    SAVED_RC=1
    "${STATE_SET[@]}" --filter '.saved_rc=$rc | .phase="result_failed"' --argjson rc "$SAVED_RC" || true
    "${WRITE_ENVELOPE[@]}" --status failed --post-state posted --reason "review-post-result.json が欠落または不正" || true
    ENGINE_CONTINUE=false
  fi
fi

if [[ "$ENGINE_CONTINUE" == true ]]; then
  BLOCK_COUNT="$(jq -r '.counts.block' "$RESULT_FILE")"
  lgtm=true
  GATE=lgtm
  [[ "$BLOCK_COUNT" -gt 0 ]] && { lgtm=false; GATE=block; }
  REQUEST_ARTIFACT="$(jq -r '.inputs.findings_artifact // empty' "$REQUEST_FILE")"
  REQUEST_ADJUDICATION="$(jq -r '.inputs.adjudication_result // empty' "$REQUEST_FILE")"
  jq -n --arg backend "$BACKEND" --arg gate "$GATE" --argjson lgtm "$lgtm" --argjson count "$BLOCK_COUNT" \
    --arg artifact "$REQUEST_ARTIFACT" --arg adjudication "$REQUEST_ADJUDICATION" --arg native "$RESULT_FILE" \
    '{schema_version:"1",artifact_type:"review-dispatch-result",review_kind:"hard",backend:$backend,dispatch_status:"complete",gate_decision:$gate,lgtm_eligible:$lgtm,blocking_count:$count,manual_review_required:false,manual_review:null,artifact_ref:(if $artifact=="" then null else $artifact end),adjudication_ref:(if $adjudication=="" then null else $adjudication end),post_state:"posted",failure_reason:null,native_result:{review_post_result:$native}}' > "$DISPATCH_TMPDIR/review-dispatch-result.json"
  if ! bash "$ENVELOPE_HELPER" validate "$DISPATCH_TMPDIR/review-dispatch-result.json" >/dev/null; then
    SAVED_RC=2
    "${STATE_SET[@]}" --filter '.saved_rc=$rc | .phase="envelope_failed"' --argjson rc "$SAVED_RC" || true
    "${WRITE_ENVELOPE[@]}" --status failed --post-state posted --reason "dispatch envelope validator failed" || true
  else
    REVIEW_DISPATCH_RESULT="$(realpath -m -- "$DISPATCH_TMPDIR/review-dispatch-result.json")"
    export REVIEW_DISPATCH_RESULT
    printf 'review-dispatch result: %s\n' "$REVIEW_DISPATCH_RESULT"
    SAVED_RC=0
    "${STATE_SET[@]}" --filter '.saved_rc=$rc | .phase="complete" | .post_state="posted"' --argjson rc 0 || true
  fi
fi
```

engine と review-post の後、`dispatch-state.json` の `saved_rc` を正本にする状態機械を更新し、全エラー経路を CLEANUP に収束させる。
lease release は次のように execution-budget の cleanup（10秒以内）で行い、失敗時は lease を `stale_suspected` として残したことを報告する。

```bash
timeout 10 bash "$SF_HELPER" release --scope per_pr --key "$SF_CANONICAL_KEY" \
  --owner-token-file "$SF_TOKEN_FILE" --lease-id "$SF_LEASE_ID"
```

cleanup の順序は per_pr lease の release だけであり、broker lease をこの helper に持たせない。`saved_rc`、lease release、
post 状態の更新が終わるまで `DISPATCH_TMPDIR` を削除しない。

cleanup の状態機械は次のように handoff 後の呼び出し元側で定義し、engine と review-post の結果を処理した後に呼び出す。

```bash
DISPATCH_STATE="<handoff JSON の .dispatch_state の絶対パス>"
[[ "$DISPATCH_STATE" == /* && -r "$DISPATCH_STATE" ]] || { echo "review-dispatch: dispatch state がありません" >&2; exit 1; }
DISPATCH_TMPDIR="$(jq -er '.tmpdir' "$DISPATCH_STATE")"
STATE_HELPER="$(jq -er '.state_helper' "$DISPATCH_STATE")"
SF_HELPER="$(jq -er '.sf_helper' "$DISPATCH_STATE")"
SF_CANONICAL_KEY="$(jq -er '.canonical_key' "$DISPATCH_STATE")"
SF_TOKEN_FILE="$(jq -er '.owner_token_file' "$DISPATCH_STATE")"
SF_LEASE_ID="$(jq -er '.lease_id' "$DISPATCH_STATE")"
SINGLEFLIGHT_FILE="$(jq -er '.singleflight_file' "$DISPATCH_STATE")"
[[ "$DISPATCH_TMPDIR" == /* && "$STATE_HELPER" == /* && "$SF_HELPER" == /* && "$SF_TOKEN_FILE" == /* \
  && "$SF_LEASE_ID" != "null" && "$SINGLEFLIGHT_FILE" == /* ]] \
  || { echo "review-dispatch: cleanup 用 dispatch state の値が不正です" >&2; exit 1; }
[[ -r "$STATE_HELPER" && -r "$SF_HELPER" ]] || { echo "review-dispatch: cleanup helper がありません" >&2; exit 1; }

# 旧 sf_cleanup() の処理は独立プロセスの cleanup サブコマンドへ移した。
# このサブコマンドが timeout 10 bash "$SF_HELPER" release を実行し、state を更新する。
# engine/post の結果処理と dispatch envelope の出力が終わった後に実行する。
bash "$STATE_HELPER" cleanup --dispatch-state "$DISPATCH_STATE" --dispatch-tmpdir "$DISPATCH_TMPDIR" \
  --sf-helper "$SF_HELPER" --canonical-key "$SF_CANONICAL_KEY" \
  --owner-token-file "$SF_TOKEN_FILE" --lease-id "$SF_LEASE_ID"
```

### Issue #415 との関係

#411 は `/review-hard` 呼び出し前の per-PR admission control と managed `/review-post` fencing、#415 は開始済み
child の追跡・回収・orphan lifecycle 対策である。層が違うため代替関係になく、#411 の `sweep` は #411 自身が
作った lease の `stale_suspected` 列挙に限られる。

## backend 利用不可時

「backend 利用不可」は engine skill（/magi-fast、/magi-hard、/codex-fast、/codex-hard）の実行が完了せず、
所定の handoff/result を返さない場合を指す。skill を Read できない、Codex companion 不在、Ollama へ到達できず
/magi-* が起動段階で失敗した場合などが該当する。

この場合は次の envelope にする。hard では engine skill の完了報告がなく投稿自体が発生しないため
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
