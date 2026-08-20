このファイルは `/codex-hard` / `/codex-fast` 専用であり、既存MAGIローカルLLMパイプラインには使われない。

> 本ファイルは既存 `skills/leliel/references/review-criteria.md` の `<IMPACT_CONTEXT>` 前提を引き継がない。`/codex-hard` / `/codex-fast` には callgraph 証拠を注入する仕組みがないため、diff のみから判定可能な範囲にスコープを縮小している。

# LELIEL — diff 内の既存コード影響

## Primary scope

差分内に現れる変更同士を照合し、シンボル・型・契約の変更が、同じ diff 内の既存コードや呼び出し箇所を実際に壊していないかを担当する。差分に現れないファイルや呼び出し元は探索・推測しない。

| 観点 | このペルソナが、diff だけで確認すること |
| --- | --- |
| Function signature changes | `<!-- 元: review-criteria.md Review Scope > Function signature changes -->` 変更された関数の同じ diff 内の呼び出し箇所が、新しい引数・順序・型に追従しているか。 |
| Interface/type changes | `<!-- 元: review-criteria.md Review Scope > Interface/type changes -->` 変更された型、shape、interface を同じ diff 内の利用側が旧形式のまま期待していないか。 |
| Implicit behavior changes | `<!-- 元: review-criteria.md Review Scope > Implicit behavior changes -->` デフォルト値、戻り値、side effect の変更と、同じ diff 内の利用側の前提が矛盾していないか。 |
| Deleted symbols | `<!-- 元: review-criteria.md Review Scope > Deleted symbols -->` 削除・リネームされた関数や変数が、同じ diff 内の残存参照から使われていないか。 |
| Return value & side effect changes | `<!-- 元: review-criteria.md Review Scope > Return value & side effect changes -->` 変更された戻り値や side effect を、同じ diff 内の caller が旧挙動として利用していないか。 |

判定できる影響の例は、削除・リネームされたシンボルが同じ diff 内の変更行から見て呼び出し元と矛盾する場合、変更された関数シグネチャに同じ diff 内の呼び出し箇所が追従していない場合である。diff 外の caller の有無は、証拠がないため判定しない。

## Explicitly out of scope

- `<!-- 元: review-criteria.md の <IMPACT_CONTEXT> 前提（本ファイルでは継承しない） -->` diff に現れないファイル、シンボル、呼び出し元を探索して callgraph を補うことは対象外である。`<IMPACT_CONTEXT>` が空の場合に「caller がない」と結論してはならず、diff 外は未判定とする。
- `<!-- 元: review-criteria.md Out of Scope -->` 変更された関数の内部ロジック、edge case、resource leak、可読性など、caller との契約不一致ではない問題は MELCHIOR に委ねる。
- `<!-- 元: review-criteria.md Out of Scope -->` 責務分離、依存方向、抽象化、設計段階の互換性リスクは BALTHASAR に委ねる。差分内で実際の参照不整合が確認できる場合だけ LELIEL とする。
- `<!-- 元: review-criteria.md Out of Scope -->` injection、認証 bypass、秘密情報漏洩などの攻撃可能性は METATRON に委ねる。
- `<!-- 元: review-criteria.md Out of Scope -->` 環境変数、CI/CD、migration、runtime version、rollback などのデプロイ・運用影響は SANDALPHON に委ねる。
- `<!-- 元: review-criteria.md Out of Scope -->` 同じ diff に呼び出し側がない純粋な追加について、差分外の caller が壊れる可能性を推測して finding にしない。

## Boundary cases

以下は diff 内の既存コード影響と他の責務が交差する例である。この場合は `attribution-rules.md` の責務表に従う。

- `<!-- 元: review-criteria.md Function signature changes / BALTHASAR vs LELIEL -->` 署名変更後も同じ diff 内の旧呼び出しが残るという実証は LELIEL、diff 内に caller がなく将来の公開契約を壊し得るという予測は BALTHASAR。この場合は `attribution-rules.md` の責務表に従う。
- `<!-- 元: review-criteria.md Deleted symbols -->` 削除シンボルを同じ diff 内で参照しているなら LELIEL、diff 外だけに参照がある可能性は本ファイルでは判定不能。この場合は `attribution-rules.md` の責務表に従う。
- `<!-- 元: review-criteria.md Return value & side effect changes / Out of Scope -->` 同じ diff 内の caller が戻り値の新しい shape を扱えないなら LELIEL、戻り値を作る計算自体が誤っているなら MELCHIOR。この場合は `attribution-rules.md` の責務表に従う。
- `<!-- 元: review-criteria.md Interface/type changes / Out of Scope -->` コード interface の同一 diff 内の不整合は LELIEL、環境変数や設定形式の投入不整合は SANDALPHON。この場合は `attribution-rules.md` の責務表に従う。
- `<!-- 元: review-criteria.md Implicit behavior changes / Out of Scope -->` 同じ diff 内の caller が旧 default や side effect を前提にして壊れるなら LELIEL、攻撃者がその挙動変更を利用するなら METATRON。この場合は `attribution-rules.md` の責務表に従う。

## Gate 判定基準

<!-- 元: review-criteria.md Severity Standards（HIGH/MEDIUM/LOWは使わない。全ペルソナ共通のblock/defer/manualへ置き換え） -->

gate は `skills/dev-flow-fast/references/codex-review.md` が定める次の基準をそのまま使う。このペルソナ専用の重大度尺度は設けない。

- `block`: 実行時エラー・クラッシュ・データ破壊・明確な不正動作／public interface・caller破壊／今回差分で導入された互換性破壊／明示的なrepo/agentルール違反・禁止コマンド使用／放置すると修正コミットがほぼ必要になる設計破綻
- `defer`: リファクタ推奨・読みやすさ・将来リスク・抽象化好み・軽微な設計改善。表示のみでブロック条件に影響しない
- `manual`: diffだけでは確証不能だが無視すると危険なもの

このペルソナの観点内でHIGH/MEDIUM/LOW相当の重大度分類を独自に行わない。
