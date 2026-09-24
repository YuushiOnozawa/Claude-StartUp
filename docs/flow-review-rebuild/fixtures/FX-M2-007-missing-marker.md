# FX-M2-007 — completion marker 欠落

- Source: ERR-20260713-002 / ERR-20260717-001 / MC-010
- Invariant: INV-007
- Test ID: M2-FX-007

## Scenario

completion marker が存在せず、終了結果と構造化出力だけが残る。

## Observable expected result

- marker の有無だけで成功または失敗を決めない。
- 終了結果と構造化出力から判定できるときは、その判定が観測できる。
- 情報が不足しているときは非完了として終端し、成功や外部投稿に進まない。

## Out of scope

- 実行コマンド
- JSON schema
- lock 名、post key 名、関数名
