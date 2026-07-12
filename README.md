# AI Dev Foundation

チーム共通のAI駆動開発基盤リポジトリです。

> **フェーズ: MVP** — main への直接 push を例外的に許可中（判定・切替条件: `docs/rules/git.md`「開発フェーズと main 直接 push」）

## このリポジトリの役割

- 全サービス共通の開発ルール（`CLAUDE.md`・`docs/rules/`）の正本管理
- Claude Code ガードレール（権限・フック・skills・サブエージェント）の配布（ADR-004）
- devcontainer雛形の管理（Windows/Mac差異を吸収）
- 品質ゲートの配布（Makefileターゲット契約・pre-push/commit-msgフック・CI多段ゲート・カバレッジラチェット）
- 新サービス立ち上げスクリプトの提供
- 改善の双方向ループ：逆輸入（サービス→共通）と順輸入（共通→サービス）の標準プロセス（`docs/rules/backport.md`）

## メンバー向けセットアップ

```bash
# 1. クローン
git clone <this-repo-url>
cd ai-dev-foundation

# 2. VS Codeで開く（WSL内から実行）
code .

# 3. 「Reopen in Container」をクリック

# 4. Claude Codeを起動
claude
```

## 新サービスを立ち上げる

```bash
./scripts/new-service.sh <サービス名>
```

## 主要コマンド

```bash
make test          # スクリプトの構文チェック
make lint          # shellcheck ゼロ警告ゲート（fail-closed）
make audit-all     # 整合性監査一式（リンク切れ・配布漏れ・退化検出）
make install-hooks # pre-push / commit-msg フックの導入
```

## 構成

| パス | 内容 |
|---|---|
| `CLAUDE.md` | AI開発共通ルール（全サービスへ配布される正本） |
| `COMMAND.md` | Claude Code コマンドリファレンス（共通正本） |
| `docs/rules/` | 共通ルール詳細（品質ゲート・git運用・逆輸入/順輸入 等） |
| `docs/decisions/` | ADR（基盤の意思決定記録） |
| `templates/` | 新サービス用雛形（`.claude/`・devcontainer・CI・Makefile 等） |
| `scripts/` | new-service / 監査 / 還流・取込 / git フック |
| `.claude/` | この基盤リポ自身のガードレール（settings・フック・skills） |
| `.github/workflows/` | 基盤リポ自身の CI 多段ゲート |

