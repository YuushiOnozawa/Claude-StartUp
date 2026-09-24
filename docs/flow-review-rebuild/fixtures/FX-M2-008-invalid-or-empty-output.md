# FX-M2-008 — 構造化出力の不正・空出力

- Source: 構造的欠陥6 / MC-011 / mining@f11852d
- Invariant: INV-008
- Test ID: M2-FX-008

## Scenario

複数の executor 経路から、空、壊れた、または一貫しない構造化出力が返される。

## Observable expected result

- どの経路でも同じ構造契約に基づいて拒否される。
- 結果は評価不能または失敗として終端し、成功や外部投稿に進まない。
- 出力を解釈できない job が、未処理のまま成功扱いにならない。

## Out of scope

- 実行コマンド
- JSON schema
- lock 名、post key 名、関数名
