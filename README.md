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
make test          # スクリプトの構文チェック + bats 回帰テスト（fail-closed）
make lint          # shellcheck ゼロ警告ゲート（fail-closed）
make audit-all     # 整合性監査一式（リンク切れ・配布漏れ・退化検出）
make req-coverage  # 要件↔テストのカバレッジ・妥当性・批准後改変検知
make tier-tripwire # Tierデスカレーションのコード実態裏取り（基盤は機微面なし宣言でスキップ）
make install-hooks # pre-push / commit-msg フックの導入
```

## 構成

| パス | 内容 |
|---|---|
| `CLAUDE.md` | AI開発共通ルール（全サービスへ配布される正本） |
| `COMMAND.md` | Claude Code コマンドリファレンス（共通正本） |
| `docs/rules/` | 共通ルール詳細（品質ゲート・git運用・逆輸入/順輸入 等） |
| `docs/requirements/` | 要件の正本（人間批准の永続資産。LLMは書き込み禁止） |
| `docs/decisions/` | ADR（基盤の意思決定記録） |
| `templates/` | 新サービス用雛形（`.claude/`・devcontainer・CI・Makefile 等） |
| `scripts/` | new-service / 監査 / 還流・取込 / git フック |
| `tests/` | 配布シェル資産の bats 回帰テスト（`@req` マーカーで要件に紐づけ） |
| `.claude/` | この基盤リポ自身のガードレール（settings・フック・skills） |
| `.github/` | CODEOWNERS（要件レビュー必須化）と基盤リポ自身の CI 多段ゲート |

### ディレクトリ構成

```
ai-dev-foundation/
├── .devcontainer/                      # Ubuntu 24.04 + Claude Code + jq/shellcheck（Windows/Mac差異を吸収）
├── .github/
│   ├── CODEOWNERS                      # docs/requirements/ への変更に人間レビューを必須化
│   └── workflows/ci.yml                # CI多段ゲート（audit / lint / test / req-coverage / tier-tripwire / secret-scan）
├── .claude/                            # 基盤リポ自身のガードレール（選択的に追跡）
│   ├── settings.json                   # 権限(allow/ask/deny)・フック・通知
│   ├── scripts/
│   │   ├── guard-dangerous.sh          # 破壊的操作・秘密読取・要件書き込みの遮断（PreToolUse）
│   │   └── session-start-rules.sh      # ルール注入＋要件資産の状態表示（SessionStart）
│   ├── skills/                         # audit-ai-rules / extract-requirements / verify-request
│   └── agents/                         # consistency-auditor / security-reviewer
├── docs/
│   ├── requirements/                   # 要件の正本（人間批准・LLM書き込み禁止）
│   │   └── R-001-guardrail-enforcement.md
│   ├── rules/                          # 共通ルール詳細
│   │   ├── code-style.md / testing.md / security.md / git.md
│   │   ├── quality-gates.md / consistency.md / token-efficiency.md
│   │   ├── tiers.md                    # Tier分類（S/A/B/C）と検証厳格度・トリップワイヤ
│   │   ├── requirements.md             # 要件の永続資産化とトレーサビリティ
│   │   ├── backport.md                 # 逆輸入・順輸入の手順
│   │   └── repo-layout.md              # サービス必須構成の正
│   └── decisions/                      # ADR（001〜005）
├── templates/                          # 新サービス用雛形（.claude・devcontainer・CI・Makefile・要件テンプレ・監査）
├── scripts/
│   ├── new-service.sh                  # 新サービス雛形生成
│   ├── audit-consistency.sh            # 整合性監査（配布漏れ・リンク切れ・退化検出）
│   ├── check-coverage.sh               # カバレッジ・フロア判定（一方向ラチェット）
│   ├── check-requirements-coverage.sh  # 要件↔テストのカバレッジ・妥当性・批准後改変検知
│   ├── check-tier-tripwire.sh          # Tierデスカレーションのコード実態裏取り
│   ├── pre-push / commit-msg           # gitフック（push前ゲート・コミット規約）
│   ├── backport-to-common.sh           # 逆輸入（サービス→共通）
│   └── sync-from-common.sh             # 順輸入（共通→サービス）
├── tests/                              # guard-dangerous / req-coverage / tier-tripwire の bats 回帰テスト
├── .backport-manifest                  # 共通所有ファイルの名簿（機械同期の対象）
├── .req-coverage-baseline              # 未カバー要件のベースライン免除（Tier B/C のみ可）
├── .tier-tripwire-allow                # トリップワイヤの明示免除リスト
├── Makefile                            # 品質ゲートのターゲット契約
├── CLAUDE.md / COMMAND.md              # AI開発共通ルール・コマンドリファレンス（共通正本）
└── README.md
```

