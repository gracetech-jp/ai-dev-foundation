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
  - "秘密情報ファイルのパスが平文でコマンド文字列に現れる読み取りが、bash 経由（外部コマンド・インタプリタのインラインコードとの共起、パイプ跨ぎ、ヒアドキュメント）で成立してはならない"
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
- **対象外（この要件が要求しないこと）**: 難読化によるパス生成（`'.e'+'nv'` / `chr()` /
  base64 デコード）、ファイル実行（`python script.py`）、間接実行（`npm run` / `npx` / `uv run`）、
  ライブラリ経由の暗黙読み込み（`require('dotenv').config()`）。正規表現による静的検査では
  原理的に到達できない（根拠: `docs/rules/security.md` §静的検査の防御ライン）。
  これらが通過することは `tests/guard-dangerous.bats`「既知の限界」節で固定している。

## 検証

`tests/guard-dangerous.bats`（`make test` から bats で実行）。破壊的コマンドの表記ゆれ・チェイン実行・
秘密読取を試みる adversarial ケースを含む。

> 2026-07-24 批准レス化（ADR-008）: 旧 `tests_ratified_by` / `tests_ratified_sha` / `test_assets` は
> スキーマごと廃止したため本要件からも除去した。要件内容（受け入れ基準・negative_space）は不変。

> **2026-07-25 negative_space の緩和（ユーザー了解のうえ実施）**: 旧文言
> 「秘密情報ファイルが bash 経由（読取コマンドとの共起・パイプ跨ぎ）で読み取れてはならない」は、
> 達成不能な絶対要求だった。`guard-dangerous.sh` は正規表現による静的検査であり、難読化・
> ファイル実行・間接実行には原理的に到達できない。旧文言のままでは「要件を満たしている」と
> 誤認したまま穴が放置されるため、実際に守れる範囲（パスが平文で現れる読み取り）へ限定した。
> **これは要件の緩和であり、防御範囲は狭まっている**。悪意ある実行者を想定する場合は
> フックの拡張では解決せず、ファイル権限・秘密の非ファイル化・ネットワーク遮断で対処する。
