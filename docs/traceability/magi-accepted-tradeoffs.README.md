# magi-accepted-tradeoffs registry

`magi-accepted-tradeoffs.json` は、BALTHASAR 等が意図的な設計トレードオフを繰り返し指摘する問題への対策として、承認済みトレードオフを構造化して記録するための registry。

本ドキュメント作成時点では、reviewer prompt にも magi-fast / magi-hard の gate 判定にも組み込まれていない。今回のスコープはデータ定義のみであり、prompt 注入や gate 連携は別 Issue で CHANGE_SUMMARY の効果測定後に実装する。

## 将来の prompt 注入原則

- 「この tradeoff は承認済みなので自動的に無視せよ」という指示にはしない。
- 既知リスクとして扱い、同じ論点を再掲する場合は新しい証拠・範囲逸脱・validation 失敗を示す形にする。
- `expires_at` 切れ、`scope` 不一致、`validation` 未実施の場合は waiver（免除）として扱わない。

## エントリ追加ガイド

- `decision_ref`: 承認判断を追跡できる PR、Issue、会話、議事録などの参照。
- `status`: 現時点の扱い。承認済みは `accepted` とする。
- `scope.description`: 対象範囲を 1-2 文で説明する。
- `scope.files`: tradeoff が適用されるファイルパス。
- `scope.patterns`: 対象箇所を絞る正規表現、glob、識別子など。不要なら空配列にする。
- `scope.issue_refs`: 関連 Issue の参照。
- `rationale`: なぜその tradeoff を受け入れたか。
- `known_risks`: 承認時点で受け入れたリスク。
- `validation`: 検証方法。未検証なら未検証であることを明記する。
- `owner`: 承認者または見直し責任者。
- `applies_to_personas`: 既知リスクとして扱う reviewer persona。
- `created_at`: エントリ作成日時。UTC RFC3339 で記録する。
- `review_after`: 次回見直し推奨時期。UTC RFC3339 で記録する。
- `expires_at`: 期限。期限なしは `null` とする。
- `evidence_refs`: 承認・検証・議論の証拠参照。
