# AI Dev Foundation

チーム共通のAI駆動開発基盤リポジトリです。

> **フェーズ: MVP** — main への直接 push を例外的に許可中（判定・切替条件: `docs/rules/git.md`「開発フェーズと main 直接 push」）

## このリポジトリの役割

- 全サービス共通の開発ルール（`CLAUDE.md`・`docs/rules/`）の正本管理
- Claude Code ガードレール（権限・フック・skills・サブエージェント）の配布（ADR-004）
- devcontainer雛形の管理（Windows/Mac差異を吸収）
- 品質ゲートの配布（Makefileターゲット契約・pre-push/commit-msgフック・CI多段ゲート・カバレッジラチェット）
- 新サービス立ち上げスクリプトの提供
- 共通基盤の一方通行配布：改善は基盤リポで直接行い、各サービスが順輸入で取り込む（逆輸入は廃止・ADR-009。`docs/rules/backport.md`）

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
./scripts/new-service.sh <サービス名> --profile <product-static|product-web>
```

`--profile` は必須（未指定はエラー＋一覧表示）。プロファイルは `profiles/_base/`（共通骨格）の上に
`profiles/<name>/profile.manifest` の add/replace を重ねて配布する（詳細: `docs/rules/repo-layout.md`）。

## 主要コマンド

```bash
make test          # スクリプトの構文チェック + bats 回帰テスト（fail-closed）
make lint          # shellcheck ゼロ警告ゲート（fail-closed）
make audit-all     # 整合性監査一式（リンク切れ・配布漏れ・退化検出）
make req-coverage  # 要件↔テストのカバレッジ検証（未カバー・dangling検出）
make tier-tripwire # 基盤ではスキップ（配布物。サービス側で機微パターンを設定して実行）
make install-hooks # pre-push / commit-msg フックの導入
```

## 構成

| パス | 内容 |
|---|---|
| `CLAUDE.md` | AI開発共通ルール（全サービスへ配布される正本） |
| `docs/rules/` | 共通ルール詳細（品質ゲート・git運用・配布/順輸入 等） |
| `docs/requirements/` | 要件の正本（永続資産。批准レス運用: ADR-008） |
| `docs/decisions/` | ADR（基盤の意思決定記録） |
| `profiles/` | 新サービス用雛形（`_base/`=共通骨格＋`product-static/`・`product-web/`=プロファイル断片） |
| `scripts/` | new-service / 監査 / 順輸入 / git フック |
| `tests/` | 配布シェル資産の bats 回帰テスト（`@req` マーカーで要件に紐づけ） |
| `.claude/` | この基盤リポ自身のガードレール（settings・フック・skills） |
| `.github/` | 基盤リポ自身の CI 多段ゲート |

### ディレクトリ構成

```
ai-dev-foundation/
├── .devcontainer/                      # Ubuntu 24.04 + Claude Code + jq/shellcheck（Windows/Mac差異を吸収）
├── .github/
│   └── workflows/ci.yml                # CI多段ゲート（audit / lint / test / req-coverage / secret-scan）
├── .claude/                            # 基盤リポ自身のガードレール（選択的に追跡）
│   ├── settings.json                   # 権限(allow/ask/deny)・フック・通知
│   ├── scripts/
│   │   ├── guard-dangerous.sh          # 破壊的操作・秘密読取の遮断（PreToolUse）
│   │   └── session-start-rules.sh      # ルール注入＋要件資産の状態表示（SessionStart）
│   ├── skills/                         # audit-ai-rules / extract-requirements / verify-request
│   └── agents/                         # consistency-auditor / security-reviewer
├── docs/
│   ├── requirements/                   # 要件の正本（永続資産。批准レス運用: ADR-008）
│   │   └── R-001-guardrail-enforcement.md
│   ├── rules/                          # 共通ルール詳細
│   │   ├── code-style.md / testing.md / security.md / git.md
│   │   ├── quality-gates.md / consistency.md / token-efficiency.md
│   │   ├── tiers.md                    # Tier分類（S/A/B/C）と検証厳格度・トリップワイヤ
│   │   ├── requirements.md             # 要件の永続資産化とトレーサビリティ
│   │   ├── backport.md                 # 配布と順輸入の手順（一方通行）
│   │   └── repo-layout.md              # サービス必須構成の正
│   └── decisions/                      # ADR（001〜009）
├── profiles/                           # 新サービス用雛形（プロファイル合成方式。ADR-006）
│   ├── _base/                          #   共通骨格（旧 templates/。.claude・devcontainer・CI・Makefile・要件テンプレ・監査）
│   ├── product-static/                 #   自社・静的サイト向け断片（profile.manifest + files/）
│   └── product-web/                    #   自社・動的Webアプリ向け断片（profile.manifest + files/）
├── scripts/
│   ├── new-service.sh                  # 新サービス雛形生成
│   ├── audit-consistency.sh            # 整合性監査（配布漏れ・リンク切れ・退化検出）
│   ├── check-coverage.sh               # カバレッジ・フロア判定（一方向ラチェット）
│   ├── check-requirements-coverage.sh  # 要件↔テストのカバレッジ検証（未カバー・dangling検出）
│   ├── check-tier-tripwire.sh          # Tierデスカレーションのコード実態裏取り
│   ├── pre-push / commit-msg           # gitフック（push前ゲート・コミット規約）
│   └── sync-from-common.sh             # 順輸入（共通→サービス。一方通行配布）
├── tests/                              # 配布シェル資産の bats 回帰テスト（guard / req-coverage / tier-tripwire / new-service / audit）
├── .backport-manifest                  # 共通所有ファイルの名簿（順輸入=配布の範囲。名称は互換維持）
├── .req-coverage-baseline              # 未カバー要件のベースライン免除（Tier B/C のみ可）
├── Makefile                            # 品質ゲートのターゲット契約
├── CLAUDE.md                           # AI開発共通ルール（共通正本）
└── README.md
```

