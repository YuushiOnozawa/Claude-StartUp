# FX-M2-009 — required job の無音 skip

- Source: 構造的欠陥7 / MC-012
- Invariant: INV-009
- Test ID: M2-FX-009

## Scenario

recipe に含まれる persona または job の実体が欠落した状態で run を開始する。

## Observable expected result

- 宣言された全 job に、成功、失敗、`timed_out`、`unavailable` のいずれかの終端結果が残る。
- 未実行の job が無音で結果から消えない。
- 一部 job の欠落を理由に、run が成功扱いにならない。

## Out of scope

- 実行コマンド
- JSON schema
- lock 名、post key 名、関数名
