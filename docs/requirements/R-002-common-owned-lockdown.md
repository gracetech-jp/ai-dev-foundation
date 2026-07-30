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
  - "service-templates/claude/scripts/guard-dangerous.sh"
  - "service-templates/claude/settings.json"
negative_space:
  - "サービスリポで、共通所有ファイル（CLAUDE.md・docs/rules/・共通スクリプト・ガードレール骨格・配布skills/agents）が bash 経由（リダイレクト・tee・cp/mv・sed -i 等）で書き換えられてはならない"
  - "基盤リポ ai-dev-foundation 自身で共通所有ファイルの編集がブロックされてはならない（編集元のため）"
  - "参照方式で正当な操作（共通リポ側にある実体の読取・実行）が封鎖に巻き込まれて止まってはならない"
---

## 受け入れ基準

- `guard-dangerous.sh` は、プロジェクトルートに `profiles/_base/` が**無い**（＝サービスリポ）とき、
  共通所有ファイル（ADR-009 の封鎖対象一覧）への bash 経由の書き込みを **deny** する:
  - リダイレクト（`>` / `>>`）の書き込み先が共通所有ファイル
  - 変更系コマンド（tee / cp / mv / dd / install / truncate / patch / rsync / `sed -i`）と共通所有パスの共起
- プロジェクトルートに `profiles/_base/` が**有る**（＝基盤リポ）ときは、同じコマンドでも**素通し**する。
- サービスリポでも、共通リポ側にある実体の読取（`cat` 等）・実行（`bash <共通側パス>`）は**素通し**する。
- 配布する `settings.json`（`profiles/_base`・各プロファイル）は封鎖対象の `Write(...)` / `Edit(...)` deny を持つ
  （存在の退化は `audit-consistency.sh` が検出する）。

## 検証

`tests/guard-dangerous.bats`（`make test` から bats で実行）。サービス想定（`CLAUDE_PROJECT_DIR` を
`profiles/_base` の無い一時ディレクトリに向ける）での書込遮断と、基盤想定での素通し・共通側実体の参照素通しの
回帰を含む。

> **2026-07-26 paths の拡大（保護範囲の拡大・ユーザー承認済み）**: 参照方式への移行フェーズ0で、
> 共通所有ファイルの配布元が `service-templates/` に移った。移行後にロックの本体となる
> `service-templates/claude/scripts/guard-dangerous.sh` と `service-templates/claude/settings.json` を
> paths に追加し、Makefile の `TIER_TRIPWIRE_PATHS` にも同じ2件を加えて実効化した。
> **これは保護範囲の拡大であり緩和ではない**（受け入れ基準・negative_space は不変）。
> 追加しなければ、移行後は「配布元を無要件で書き換えられるのに緑」という状態になっていた。

> **2026-07-30 negative_space の意味変更（順輸入の廃止・ADR-010。ユーザー了解のうえ実施）**:
> 「順輸入が止まってはならない」という条項は、共通所有ファイルの**複製がサービス側に存在し、
> それを更新する経路が必要**という前提に立っていた。参照方式の完成により複製そのものを持たなく
> なったため、この前提が消滅した（`sync-from-common.sh` と `.backport-manifest` は削除）。
> 条項は「参照方式で正当な操作が封鎖に巻き込まれない」へ置き換えた。
> **封鎖の対象範囲（paths・遮断する操作）は不変で、緩和ではない**。ロックの意味だけが
> 「配られた複製を編集させない」から「複製をプロジェクト側に発生させない」へ変わっている。
