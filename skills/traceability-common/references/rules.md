# Traceability 共通ルール

全 `traceability-*` スキルが従う共通規約。各スキルは実行前にこのファイルを Read する。

## 対象の特定

- 引数で `core-XX` が指定されたらそれを対象とする
- 無指定なら `docs/traceability/README.md`（全体ボード）を読み、進行中・次候補の核問題を提示して
  AskUserQuestion で選ばせる

## フォルダ構造とファイル役割

```
docs/planning/                     Step 1 の分類結果
docs/traceability/
  README.md                        全体ボード（核問題 × ドキュメント × ステータス）
  core-XX-<name>/
    README.md                      核問題の入口。概要・関連項目・分類・confidence・ステータス表
    requirements.md                Step 3: 問題・要求候補・受け入れ条件候補・対象外・人間確認事項
    specification.md               Step 4: 仕様候補・境界条件・fail/warn/info 基準・未確定事項
    implementation-plan.md         Step 5: 変更候補ファイル・作業単位・PR分割・依存関係
    test-plan.md                   Step 8: 自動テスト・verify・CI・手動確認・異常系
    design-review.md               Step 7 で作成（それまで todo）
    traceability-map.md            問題→要求→仕様→実装→テストの対応表。各 Step で更新
    traceability-audit.md          Step 9 で作成（それまで todo）
```

## ステータス値

`todo` 未着手 / `draft` AI作成の未確定たたき台 / `reviewing` 人間確認中 /
`approved` 確認済み・次工程可 / `blocked` 判断・依存待ち / `implemented` 実装済み /
`verified` テスト・監査完了 / `later` 後回し

## ID 規約（traceability-map 用）

```
PROB-XX-NN   問題（核問題 XX 内の通し番号）
REQ-XX-NN    要求
SPEC-XX-NN   仕様
IMPL-XX-NN   実装項目
TEST-XX-NN   テスト観点
```

- 対応は `traceability-map.md` に表で記録する: `| REQ-01-01 | SPEC-01-01, SPEC-01-02 | 備考 |`
- **根拠のない対応関係を作らない**。対応不明は「未対応（理由）」と書く

## 各スキル完了時の必須更新（3点セット）

1. 対象 `core-XX/README.md` のステータス表
2. `docs/traceability/README.md` の全体ボード
3. 対象 `core-XX/traceability-map.md`（当該 Step の対応追加）

## 人間確認の扱い

- 生成・更新したドキュメントは `draft` とし、スキル末尾で人間確認ポイントを提示して
  AskUserQuestion（「approved にする / draft のまま / 修正指示」）を呼ぶ
- `approved` にできるのは人間の回答のみ。AI が自律的に approved へ変更しない

## 外部変更の記録ルール（Step 1 完了後に入力が動いたとき）

分類完了後に新しいスコープ・先行変更（別経路で入る実装、外部ツール導入など）が発生した場合:

1. **分類ドキュメント（docs/planning/）は書き換えない** — Step 1 成果物は「あの時点の入力から
   何を切り出したか」の記録として不変に保つ
2. **既存核問題の問題クラスに収まる場合** → 該当 `core-XX/README.md` に記録する:
   - 「人間確認が必要な点」に取り込み判断の項目を追加
   - 「外部先行変更（日付）」セクションを追加し、変更の内容・出典・関連文書への相互参照を書く
   - この記録が**派生元宣言**になる: Step 3 はこれを前提に要求範囲を切り、Step 9 は当該実装を
     orphan implementation として誤検知しない（「なぜ存在するか」にこの記録が答える）
3. **どの核問題にも収まらない場合** → `/traceability-classify` を差分再実行する
   （既存 core 番号は変えず、新 core を追加する）

## 禁止事項

- いきなり実装しない。仕様未確定のまま実装を進めない
- 問題・要求・仕様・実装項目・テストを混同しない
- 推測を事実扱いしない（推測は「推測:」と明記）
- ドキュメントより実装・git 履歴を現状の正とする
- コード変更を伴う Step では、変更理由と対応仕様 ID を必ず記録する
