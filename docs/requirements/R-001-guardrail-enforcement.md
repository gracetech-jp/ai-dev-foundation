---
id: R-001
title: 破壊的操作・秘密読取の機械的遮断
tier: S
status: ratified
ratified_by: 大澤将平
tests_ratified_by: 大澤将平
tests_ratified_sha: 76da7651cffd87598de1e1d666235d32f30f008d5558890e15c3e64c2fa35d50
paths:
  - ".claude/scripts/guard-dangerous.sh"
  - ".claude/settings.json"
  - "templates/.claude/scripts/guard-dangerous.sh"
  - "templates/.claude/settings.json"
test_assets:
  - "tests/guard-dangerous.bats"
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

> status は draft。人間が内容を確認し `status: ratified`・`ratified_by`・`tests_ratified_by`・
> 実 `tests_ratified_sha` を commit した時点で批准成立（実ハッシュは手順3で照合スクリプト導入時に確定）。
