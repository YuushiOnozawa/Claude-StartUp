# FX-M2-018 — target 同一性・所有権入力の fail-closed

- Source: MC-021 / mining@83a6557 / mining@fdf3b70
- Invariant: INV-018
- Test ID: M2-FX-018

## Scenario

target の同一性・所有権を示す入力が欠落・不一致・破損している。

## Observable expected result

- 外部への書き込み前に、明示的な失敗または評価不能で終端する。
- 成功や投稿へ進まない。

## Out of scope

- 実行コマンド
- JSON schema
- lock 名、post key 名、関数名
