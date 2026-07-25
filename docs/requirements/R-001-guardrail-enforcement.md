---
id: R-001
title: 破壊的操作・秘密読取の機械的遮断
tier: S
status: ratified
ratified_by: 大澤将平
paths:
  - ".claude/scripts/guard-dangerous.sh"
  - ".claude/settings.json"
  - "profiles/_base/.claude/scripts/guard-dangerous.sh"
  - "profiles/_base/.claude/settings.json"
negative_space:
  - "再帰強制削除・履歴/ブランチ破壊・force push などの破壊的コマンドが、表記ゆれ（結合フラグ・順序違い・パス先行・チェイン実行）を用いても実行できてはならない"
  - "秘密情報ファイルが bash 経由（読取コマンドとの共起・パイプ跨ぎ）で読み取れてはならない"
---

## 受け入れ基準

- `guard-dangerous.sh` は、次を **deny**（`permissionDecision: deny`）する:
  - 再帰強制削除（`rm -rf` / `rm -fr` / `rm dir -rf` 等の表記ゆれ）
  - 履歴・ブランチ破壊（`git reset --hard` / `git clean -f*` / `git branch -D`）
  - force push（`git push --force` / `-f` / `--force-with-lease`）
  - 秘密ファイルの bash 経由読取（`cat .env` 等、読取コマンドと秘密パスの共起）
  - 上記が `&&` などで連結されていても同様に deny する
- 一方、正当な操作（`ls -la` / `cat .env.example` 等のサニタイズ対象）と、Bash 以外のツールは
  **素通し**（deny しない）する。

## 検証

`tests/guard-dangerous.bats`（`make test` から bats で実行）。破壊的コマンドの表記ゆれ・チェイン実行・
秘密読取を試みる adversarial ケースを含む。

> 2026-07-24 批准レス化（ADR-008）: 旧 `tests_ratified_by` / `tests_ratified_sha` / `test_assets` は
> スキーマごと廃止したため本要件からも除去した。要件内容（受け入れ基準・negative_space）は不変。
