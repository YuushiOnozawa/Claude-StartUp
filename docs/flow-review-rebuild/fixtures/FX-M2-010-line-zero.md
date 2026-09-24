# FX-M2-010 — location の line:0

- Source: MC-013 / mining@f11852d
- Invariant: INV-010
- Test ID: M2-FX-010

## Scenario

finding の location が `line:0` になる入力を与える。

## Observable expected result

- `line:0` だけを理由に構造検証が失敗しない。
- finding が保持され、後続で観測可能な結果として終端する。

## Out of scope

- 実行コマンド
- JSON schema
- lock 名、post key 名、関数名
