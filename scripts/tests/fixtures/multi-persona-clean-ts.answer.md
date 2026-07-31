# Multi-Persona Clean Code Fixture Answer Key（precision/decoy 用）

## 目的

既存の `*-flaws-ts` 系 fixture は recall（欠陥をどれだけ検出できるか）を測るためのものだが、
「壊れていないコードを誤検知しないか」（precision / decoy 耐性）を測る fixture が無かった
（[[project_magi_dedup_issue366_pr368]] 作業中に発見、`docs/magi-model-selection-procedure.md`
2番で「既知の欠落」として記録済み）。

この fixture は、MELCHIOR/BALTHASAR/METATRON/SANDALPHON/LELIEL 5persona の観点をそれぞれ
1〜3個ずつ、**正しく実装されたコード**として盛り込んだ単一の TypeScript diff である。
`createPasswordResetToken` 機能を `accountService.ts` に追加する体裁で、各 persona が
「疑わしく見えるが実際には問題ない」パターン（decoy）に対して false positive を出さないかを見る。

**期待される正解は「0件」。** raw_recall を測る他 fixture と異なり、この fixture の合格条件は
「decoy を欠陥として誤検知しないこと」だけである。

## 使い方

`skills/magi-common/references/execution-steps.md` のステップ2と同じ組み立てで、
対象 persona の `system.txt` / `prompt.txt` を作る（`output-format-v2.md` を使う。
`output-format.md` は使わない）。

LELIEL のみ `<IMPACT_CONTEXT>` として `multi-persona-clean-ts.impact-context.txt` を
`prompt.txt` の `<TASK>` 直前に追加する（`leliel-caller-break-ts` fixture と同じ手順）。

## Decoy 一覧

| ID | Persona | 該当行 | 一見疑わしく見える理由 | 実際に問題ない理由 |
| --- | --- | --- | --- | --- |
| DC-M1 | MELCHIOR | `src/services/accountService.ts:35-37` | 配列の `length === 0` 分岐は見落とされがちな edge case | 空配列を明示的にガードして早期return しており、未処理のedge caseではない |
| DC-M2 | MELCHIOR | `src/services/accountService.ts:25-29`, `:67-69` | `finally` 内の条件分岐がリソースリークに見えることがある | `existingClient` が渡された場合は呼び出し元が解放責任を持つため、二重解放を避けて `!existingClient` の時だけ release している。`createPasswordResetToken` 側は常に自前取得のため無条件 release で正しい |
| DC-B1 | BALTHASAR | `src/services/accountService.ts:16`, `:47` | 既存関数のシグネチャ変更はbackward-compat breakとして疑われやすい | いずれも**追加された optional 引数**（`existingClient?`、`options?`）で、省略時は旧来と同じ挙動になる。既存呼び出し元は無変更で動作する |
| DC-B2 | BALTHASAR | `src/services/accountService.ts:41-43` | 1行の薄いラッパー関数は不要な間接化に見えることがある | `hashToken` はpepper付与とhash化という実際の振る舞いを持ち、`createPasswordResetToken` 内での重複コードを避けている。中身を持たない空ラッパーではない |
| DC-T1 | METATRON | `src/services/accountService.ts:20-23`, `:61-64` | 文字列で組み立てたSQLに見えることがある | `$1`/`$2`/`$3` のプレースホルダによるパラメータ化クエリであり、値は配列で別送されている。injectionの余地はない |
| DC-T2 | METATRON | `src/services/accountService.ts:56` | トークン生成に弱い乱数を使っていないか疑われやすい箇所 | `crypto.randomBytes(32)`（Node.js CSPRNG）を使用しており、`Math.random()` 等の予測可能な乱数ではない |
| DC-T3 | METATRON | `src/services/accountService.ts:41-43` | `sha256` はパスワードハッシュとしては弱いアルゴリズムとして知られる | ハッシュ対象はユーザーが選ぶ低エントロピーな password ではなく、`crypto.randomBytes(32)` が生成した256bitの高エントロピーな乱数トークン（+pepper）。総当たりが現実的に不可能なため、bcrypt/argon2のような低速化ハッシュは不要 |
| DC-S1 | SANDALPHON | `src/services/accountService.ts:6-12` | 必須環境変数のデフォルト欠如は典型的な指摘対象 | `getTokenPepper()` は `hashToken` 経由で `createPasswordResetToken` が実際に呼ばれた時にだけ評価される遅延検証であり、`accountService.ts` を import しただけの既存経路（`findUserByEmail` を使う `authRoutes.ts`/`weeklyDigest.ts`）は `TOKEN_PEPPER` 未設定でも一切影響を受けない。**module top-levelでの即時throwにはしていない**——それだと新規追加した必須env varが既存の無関係な呼び出し元までimport時点で巻き込んで起動失敗させる、実際にSANDALPHONが拾うべき本物の欠陥になる（Codexレビューで最初の設計案から修正済み） |
| DC-L1 | LELIEL | `src/services/accountService.ts:14-17`（`findUserByEmail`のシグネチャ変更） | 既存exported関数のシグネチャ変更はcaller breakageの典型的な疑いどころ | `multi-persona-clean-ts.impact-context.txt` の `authRoutes.ts:handleLogin`・`weeklyDigest.ts:sendDigestTo` はいずれも`findUserByEmail(email)`と1引数で呼んでおり、追加された第2引数はoptionalなので型・実行時挙動とも無変更のまま動作する |

## 採点基準

- **期待される true finding は0件。** DC-* のいずれかを欠陥として報告した場合、それは誤検知（false positive）としてカウントする。
- DC-* に該当しない箇所（diffに存在しない事実の捏造等）を報告した場合も誤検知としてカウントする。
- `"No findings."` 等の契約に沿った「指摘なし」出力は正しい挙動であり、減点対象ではない。

## 合格条件

- 誤検知が **0件**であることが望ましい。
- 誤検知が1件までは許容し、2件以上の誤検知が出たモデルはこの fixture で不合格とする。
- 誤検知が出た場合は、DC-*のどれに該当する誤認かを個別ログに記録し、
  `docs/magi-model-selection-procedure.md` 5番「採点方法」の decoy 誤検知欄に転記する。

関連: [[project_magi_dedup_issue366_pr368]] [[project_magi_recall_first_direction]]
