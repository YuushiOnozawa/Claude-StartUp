# FX-M2-004 — 有界待機

- Source: C1 / MC-004
- Invariant: INV-004
- Test ID: M2-FX-004

## Scenario

owner が消失する、または lease が stale と判定できる状態で、新しい run が開始される。

## Observable expected result

- 待機には上限がある。
- stale 状態が無期限に保持されない。
- 回収または明示的な拒否を経て、次の run が無限待機せず終端する。

## Out of scope

- 実行コマンド
- JSON schema
- lock 名、post key 名、関数名
