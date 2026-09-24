# FX-M2-018 — target 同一性・所有権入力の fail-closed

- Source: MC-021 / mining@83a6557 / mining@fdf3b70
- Invariant: INV-018
- Test ID: M2-FX-018

## Scenario

target の同一性・所有権を示す入力が欠落・不一致・破損している。加えて、所有権記録の時刻が未来、状態の保存先が想定外の種類（リンク等）へ差し替え、または排他機構が利用不能・非対応の環境である。

## Observable expected result

- 外部への書き込み前に、明示的な失敗または評価不能で終端する。
- 成功や投稿へ進まない。
- 未来の所有権記録、想定外の状態保存先、排他機構の利用不能・非対応は、暗黙の fallback をせず、外部への書き込み前に明示的な失敗または評価不能で終端する。

## Out of scope

- 実行コマンド
- JSON schema
- lock 名、post key 名、関数名
