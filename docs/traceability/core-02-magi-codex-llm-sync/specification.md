# Specification Draft: Core 02

## 仕様候補

- agents参照撤去または復元の方針
- モデル割当の単一情報源または突合CI
- 補助スクリプトの絶対/環境変数ベース解決規約
- codex-companion のバージョン固定パス排除
- 実装変更時のドキュメント同時更新ルール

## 境界条件

- この仕様候補は、分類成果物の「仕様化の観点」から起こした論点であり、まだ確定仕様ではない。
- 関連Fable項目 01, 02, 03, 06, 08 のうち、他の核問題にも現れる項目は重複として扱う。
- 実装確認メモに基づく現状は次の通り。

- agents/ には MAGI 系では leliel.md のみ存在する
- 各personaの SKILL.md に agents/<persona>.md 参照が残る
- 実スキル側モデルと setup/800 のpull対象が一致しない
- magi-fast / magi-hard に bash scripts/... の相対参照が残る
- codegen はCodex委譲だが setup/850 はCodex CLI確認のみ

## fail / warn / info の判定が必要なもの

- 目的達成に必須で、欠けると主要機能が動かないものは fail 候補。
- 手動認証、環境差、任意機能、段階導入対象は warn / info 候補。
- 具体的な判定境界は requirements.md の人間確認事項を解消してから決める。

## 未確定事項

- #203 の方針を完遂して references に一本化するか agents を復元するか
- METATRON の devstral を継続するか
- Codex CLI / plugin の確認済みバージョンをどこまで固定するか