# リポジトリ構成の必須要素（共通）

全サービスリポジトリが備えるべきファイル/ディレクトリを定義する。これらは `scripts/new-service.sh` が
生成時に配布し、欠落は `scripts/audit-consistency.sh` の「配布漏れ検査」等で検出する。
人手のレビューに頼らず、**構成の欠落を機械的に検出**するのが目的。

## 必須ファイル / ディレクトリ

| パス | 役割 | 由来 |
|---|---|---|
| `CLAUDE.md` | AI駆動開発の共通ルール（基盤から配布・逆輸入対象） | 共通正本 |
| `SERVICE.md` | サービス固有ルール（スタック表・構成・環境変数） | 雛形から生成 |
| `COMMAND.md` | Claude Code コマンドリファレンス | 共通正本 |
| `docs/rules/` | 共通ルール群（本ファイル含む） | 共通正本 |
| `docs/requirements/` | 要件の永続資産（人間批准・一意ID・negative space。詳細: `docs/rules/requirements.md`） | 骨格配布 |
| `docs/service-rules/` | サービス固有ルール（整合性の具体手順等） | 雛形 |
| `docs/decisions/` | ADR（意思決定記録。運用ガイド＋テンプレ） | 雛形 |
| `.claude/settings.json` | 権限（allow/ask/deny）・フック設定 | 骨格配布 |
| `.claude/scripts/guard-dangerous.sh` | 破壊的操作・秘密読み取りの遮断フック | 骨格配布 |
| `.claude/scripts/session-start-rules.sh` | ルール注入フック | 骨格配布 |
| `.claude/skills/` `.claude/agents/` | skills・サブエージェント | 骨格配布 |
| `.devcontainer/` | 統一開発環境（詳細: `docs/decisions/`） | 骨格配布 |
| `.github/workflows/ci.yml` | CI 多段ゲート（詳細: `docs/rules/quality-gates.md` §4） | 骨格配布 |
| `.editorconfig` | エディタ非依存のスタイル強制（詳細: `docs/rules/code-style.md`） | 骨格配布 |
| `Makefile` | 品質ゲートのターゲット契約（詳細: `docs/rules/quality-gates.md` §1） | 骨格配布 |
| `scripts/pre-push` | push前ゲート（`make audit-all`＋`make test`） | 共通正本 |
| `scripts/commit-msg` | Conventional Commits の機械強制（詳細: `docs/rules/git.md`） | 共通正本 |
| `scripts/check-coverage.sh` | カバレッジのフロア判定（詳細: `docs/rules/quality-gates.md` §5） | 共通正本 |
| `scripts/audit-consistency.sh` | 整合性監査（詳細: `docs/rules/consistency.md`） | 雛形 |
| `scripts/backport-to-common.sh` `.backport-manifest` | 逆輸入プロセス（詳細: `docs/rules/backport.md`） | 共通正本＋ローカル |
| `.coverage-floor` | カバレッジのフロア値（サービスがラチェット） | 雛形初期値 |
| `.gitignore` `.env.example` `README.md` | 追跡除外・環境変数雛形・入口 | 雛形から生成 |

## 運用

- 新規サービスは `scripts/new-service.sh <名前>` で上記一式を生成する。
- 「由来: 骨格配布」は共通リポの `templates/` から配布され、サービス側とパスが 1:1 対応しないため
  逆輸入は手動同期（詳細: `docs/rules/backport.md`）。
- 必須要素を増減したら、`new-service.sh`・`audit-consistency.sh`・本ファイルを同時に更新する
  （一箇所だけ直すとドリフトする）。
