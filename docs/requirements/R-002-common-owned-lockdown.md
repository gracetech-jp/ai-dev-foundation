---
id: R-002
title: 共通所有ファイルのサービス側編集封鎖（一方通行配布）
tier: S
status: ratified
ratified_by: LLM（ADR-009 の決定に基づき起票。draft を経ておらず、内容のユーザー確認は未実施）
paths:
  - ".claude/scripts/guard-dangerous.sh"
  - "profiles/_base/.claude/scripts/guard-dangerous.sh"
  - "profiles/_base/.claude/settings.json"
  - "profiles/*/files/.claude/settings.json"
negative_space:
  - "サービスリポで、共通所有ファイル（CLAUDE.md・docs/rules/・共通スクリプト・ガードレール骨格・配布skills/agents）が bash 経由（リダイレクト・tee・cp/mv・sed -i 等）で書き換えられてはならない"
  - "基盤リポ ai-dev-foundation 自身で共通所有ファイルの編集がブロックされてはならない（編集元のため）"
  - "順輸入（sync-from-common.sh の実行）が封鎖に巻き込まれて止まってはならない（唯一の正規更新経路）"
---

## 受け入れ基準

- `guard-dangerous.sh` は、プロジェクトルートに `profiles/_base/` が**無い**（＝サービスリポ）とき、
  共通所有ファイル（ADR-009 の封鎖対象一覧）への bash 経由の書き込みを **deny** する:
  - リダイレクト（`>` / `>>`）の書き込み先が共通所有ファイル
  - 変更系コマンド（tee / cp / mv / dd / install / truncate / patch / rsync / `sed -i`）と共通所有パスの共起
- プロジェクトルートに `profiles/_base/` が**有る**（＝基盤リポ）ときは、同じコマンドでも**素通し**する。
- サービスリポでも、`sync-from-common.sh` の起動コマンド・読取コマンド（`cat` 等）は**素通し**する。
- 配布する `settings.json`（`profiles/_base`・各プロファイル）は封鎖対象の `Write(...)` / `Edit(...)` deny を持つ
  （存在の退化は `audit-consistency.sh` が検出する）。

## 検証

`tests/guard-dangerous.bats`（`make test` から bats で実行）。サービス想定（`CLAUDE_PROJECT_DIR` を
`profiles/_base` の無い一時ディレクトリに向ける）での書込遮断と、基盤想定での素通し・順輸入素通しの
回帰を含む。
