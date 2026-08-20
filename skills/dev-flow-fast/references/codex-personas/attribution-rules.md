このファイルは `/codex-hard` / `/codex-fast` 専用であり、既存MAGIローカルLLMパイプラインには使われない。

# ペルソナ帰属ルール

この文書は、複数の観点に見えるコード finding から `canonical_persona`（帰属先ペルソナ）を1つ決めるための責務表である。ここで扱うのはコード finding の意味的な帰属であり、gate の機械的な集計そのものではない。

## 優先順位

根本原因が複数領域にまたがるときは、次の優先順位で canonical_persona を決める。上位の観点が成立する場合、下位の観点へ重複帰属しない。

`security exploitability（METATRON） > deployment/release consequence（SANDALPHON） > existing-source impact（LELIEL） > general code quality（MELCHIOR/BALTHASAR）`

「security exploitability」は攻撃可能性・秘密情報漏洩を意味し、「deployment/release consequence」は本番投入・設定・運用・復旧の結果を意味する。「existing-source impact」は diff 内で実際に確認できる既存コードへの破壊的影響を意味する。最後の一般品質領域では、実装上の具体的な不具合は MELCHIOR、設計・アーキテクチャ上の懸念は BALTHASAR とする。

## 責務表

| 根本原因・具体例 | `canonical_persona` | 帰属の判定 |
| --- | --- | --- |
| 秘密情報漏洩（ハードコードされた鍵・token（トークン）、秘密情報を含むログなど） | `METATRON` | 常に METATRON 固定。設定やデプロイに現れる場合でも、秘密情報が漏れることが根本原因なら上位の security を採用する。 |
| デプロイ時の設定・運用露出（環境変数、CI/CD、rollback 可否、migration、runtime 整合性など） | `SANDALPHON` | 攻撃可能性や秘密情報漏洩ではなく、投入・運用・復旧の失敗が根本原因なら SANDALPHON。 |
| 入力由来の攻撃可能性（injection、認証 bypass、path traversal、RCE など） | `METATRON` | 入力が攻撃経路として成立するなら、単なる入力処理バグやデプロイ影響より METATRON を優先する。 |
| 既存呼び出し元への実際の破壊的影響（同じ diff 内の旧署名参照、削除シンボル参照など） | `LELIEL` | diff 内で caller と変更の不整合を確認できる場合に限る。diff 外の callgraph は証拠として扱わない。 |
| 単なるログ品質、実装ミス、edge case、resource leak、可読性 | `MELCHIOR` | 攻撃可能性、デプロイ影響、既存 caller 影響が根本原因でない一般的な実装品質なら MELCHIOR。 |
| 設計・アーキテクチャ上の懸念（責務分離、依存方向、抽象化、拡張性、設計段階の互換性） | `BALTHASAR` | 具体的な実装バグや diff 内の caller 破壊が根本原因でない設計問題なら BALTHASAR。 |

同じ事象に複数の説明が可能でも、finding の本文は採用した根本原因とその証拠に絞る。たとえば、秘密情報を環境変数に置く方法が不適切である場合は「設定が足りない」ではなく、秘密情報の露出経路として METATRON に帰属させる。

## gate 競合時の優先順位

gate が同一グループ内で複数 finding に分かれた場合は、次の強さを採用する。

`block > manual > defer`

`block` は `manual` と `defer` より優先し、`manual` は `defer` より優先する。同一グループ内の最も高い gate をグループの判定とする。実際の gate の計算・集計はシェル側スクリプトが行うため、この節は判定基準としてのみ使用し、ここで計算結果を手作業で作らない。

## finding の分離とマージ

同じ `path`/`line` でも、根本原因が異なる finding はマージしない。たとえば同じ行に「攻撃者が shell injection を成立させる」問題と「同じ diff 内の caller が変更された戻り値を処理できない」問題がある場合、意味的内容が異なるため METATRON と LELIEL の別 group のまま残す。

同一 finding とみなせるのは、根本原因、影響、証拠が同じで、単に複数ペルソナの表現が重複している場合に限る。帰属を1つにすることは、異なる根本原因を一つの finding に押し込むことを意味しない。

## CASPER finding の扱い

このファイルの責務表は、コード finding（MELCHIOR / BALTHASAR / METATRON / SANDALPHON / LELIEL 間）の帰属だけを対象とする。CASPER finding は、リポジトリまたはエージェントのルール違反に対する別のルール違反 gate として独立に扱う。

CASPER finding は、この責務表によるコード finding との意味的マージ対象にしない。同じ `path`/`line` に CASPER のルール違反とコード finding があっても、根本原因と gate の判定契約が異なるため別 finding・別 group として残す。CASPER 自体は今回作成する5つのペルソナ基準ファイルには含めないが、将来 `/codex-fast` から参照される境界としてこの扱いを固定する。
