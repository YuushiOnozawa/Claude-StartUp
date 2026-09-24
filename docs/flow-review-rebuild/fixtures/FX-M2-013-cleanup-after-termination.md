# FX-M2-013 — 終了後の残留資源回収

- Source: MC-016 / mining@b8721a5 / mining@83a6557 / mining@070aec4
- Invariant: INV-013
- Test ID: M2-FX-013

## Scenario

親の実行が crash、SIGINT、SIGTERM、または timeout で終了する間に、子の処理、排他資源、一時資源が存在する。

## Observable expected result

- 回復後に active な子の処理、排他資源、一時資源が残らない。
- 次の run が残留資源によって無期限に塞がれない。
- 回収不能な残留がある場合も、stale として有界に観測され、終端する。

## Out of scope

- 実行コマンド
- JSON schema
- lock 名、post key 名、関数名
