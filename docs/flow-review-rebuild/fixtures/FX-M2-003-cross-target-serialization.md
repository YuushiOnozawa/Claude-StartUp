# FX-M2-003 — 別 target の共有 executor 直列化

- Source: Issue #411 / MC-003 / mining@b8721a5
- Invariant: INV-003
- Test ID: M2-FX-003

## Scenario

異なる target に属する2つの外部 executor job が同時に開始される。

## Observable expected result

- 外部 Codex 実行は同時に高々1本である。
- target が異なっても外部 executor の重ね打ちが発生しない。
- 各 run の終端結果が失われず、別 target の実行が無期限に待たない。

## Out of scope

- 実行コマンド
- JSON schema
- lock 名、post key 名、関数名
