# FX-M2-012 — 投稿開始後の成否不明

- Source: MC-015 / mining@fdf3b70
- Invariant: INV-012
- Test ID: M2-FX-012

## Scenario

外部 API の相手がリクエストを受理した後、caller timeout または応答解析失敗が起き、成否を確認できない。

## Observable expected result

- 終端結果は `posted_unknown` 相当として観測できる。
- 自動的な再投稿が発生しない。
- 再判定は同じ stable marker の検索だけで行われ、marker が見つからない場合も盲目的な再投稿に進まない。
- リクエストを送る前に失敗した場合は未投稿が確定し再試行してよいが、このケース（受理後の成否不明）では再試行しない。

## Out of scope

- 実行コマンド
- JSON schema
- lock 名、post key 名、関数名
