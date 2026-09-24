# FX-M2-016 — unavailable の fail-closed

- Source: MC-019 / mining@83a6557
- Invariant: INV-016
- Test ID: M2-FX-016

## Scenario

選択された executor が利用不能、未認証、または未認定の状態で run を開始する。

## Observable expected result

- 自動 fallback が発生しない。
- `unavailable` 相当の状態が明示されて終端する。
- 利用不能を成功として扱わず、外部投稿へ進まない。

## Out of scope

- 実行コマンド
- JSON schema
- lock 名、post key 名、関数名
