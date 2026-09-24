# FX-M2-002 — 同一 target の同時実行

- Source: Issue #411 / MC-002
- Invariant: INV-002
- Test ID: M2-FX-002

## Scenario

同一 target に対して、2つの run が同時に開始される。

## Observable expected result

- 実行権を持つ run は高々1本である。
- もう一方の run は無期限に待たず、`already_running` 相当として終端する。
- 同じ target から重複した外部副作用が発生しない。

## Out of scope

- 実行コマンド
- JSON schema
- lock 名、post key 名、関数名
