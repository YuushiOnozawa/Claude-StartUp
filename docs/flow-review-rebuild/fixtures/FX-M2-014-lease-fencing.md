# FX-M2-014 — lease 期限切れ後の fencing

- Source: Issue #411 / MC-017 / mining@fdf3b70 / mining@070aec4
- Invariant: INV-014
- Test ID: M2-FX-014

## Scenario

owner A の lease が期限切れになった後、owner B が同じ target を取得し、owner A が遅れて renew、release、または publish を試みる。

## Observable expected result

- owner B の処理だけが有効として観測される。
- owner A の遅い操作は拒否される。
- owner A が owner B の状態、外部書き込み、lease を巻き戻さない。

## Out of scope

- 実行コマンド
- JSON schema
- lock 名、post key 名、関数名
