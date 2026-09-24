# FX-M2-019 — runtime reachability と drift 検出

- Source: 構造的欠陥1 / 構造的欠陥9 / MC-022
- Invariant: INV-019
- Test ID: M2-FX-019

## Scenario

source 側と runtime 側の実行 closure に、欠落、内容不一致、または旧入口の残留がある。

## Observable expected result

- drift 検査が不一致を列挙し、非成功で終端する。
- 不一致がある状態を、実フロー検証の成功として扱わない。
- 完全一致した場合だけ、runtime の全入口が到達可能であることを観測できる。

## Out of scope

- 実行コマンド
- JSON schema
- lock 名、post key 名、関数名
