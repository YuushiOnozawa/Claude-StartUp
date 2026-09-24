# FX-M2-017 — publish=none の副作用境界

- Source: MC-020 / mining@c819dba / mining@6088cc3
- Invariant: INV-017
- Test ID: M2-FX-017

## Scenario

同じ入力について、解析だけを要求する `publish=none` の run と、外部投稿を要求する run を比較する。

## Observable expected result

- `publish=none` の run では外部書き込みが0件である。
- `publish=none` の run の結果が、ローカルで観測可能な状態として残る。
- 外部書き込みは投稿を要求した run にだけ発生する。

## Out of scope

- 実行コマンド
- JSON schema
- lock 名、post key 名、関数名
