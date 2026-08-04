# AI Dev Foundation

チーム共通のAI駆動開発基盤リポジトリです。

> **フェーズ: MVP** — main への直接 push を例外的に許可中（判定・切替条件: `docs/rules/git.md`「開発フェーズと main 直接 push」）

## このリポジトリの役割

- 全サービス共通の開発ルール（`CLAUDE.md`・`docs/rules/`）の正本管理
- Claude Code ガードレール（権限・フック・skills・サブエージェント）の配布（ADR-004）
- devcontainer雛形の管理（Windows/Mac差異を吸収）
- 品質ゲートの配布（Makefileターゲット契約・pre-push/commit-msgフック・CI多段ゲート・カバレッジラチェット）
- 新サービス立ち上げスクリプトの提供
- 共通資産は参照方式：実体は基盤リポに1つだけ置き、各プロジェクトは実行時に参照する（配布・順輸入は廃止・ADR-009/010。`docs/rules/common-assets.md`）

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

```bash
bash scripts/verify-isolation.sh   # 隔離境界（ADR-013 第1層）の実測。Rebuild のたびに1回流す
```

設定が正しいことは `make audit-all` の検査(13)が見るが、**その設定で実際に遮断されるか**は
コンテナを動かさないと分からない。こちらは実測（適用スタンプ + 実通信）を担う。

## ディレクトリ構成

各ディレクトリの詳細は**直下の README** を参照する（ここは直下の一覧のみ。所在の管理方法は
`docs/rules/repo-layout.md`「所在の管理は各階層の README が正本」）。

```
ai-dev-foundation/
├── common/                     # 共通資産の実体。各プロジェクトが参照する（複製しない）
├── docs/                       # 共通ルール・要件・ADR・監査記録
├── profiles/                   # 新規プロジェクト生成の雛形（プロファイル合成方式・ADR-006）
├── projects/                   # 各プロジェクト（ここに置くと共通資産を解決できる。git 管理外）
├── scripts/                    # この基盤リポ自身の運用スクリプト
├── service-templates/          # 参照方式版の配布雛形（移行期。profiles/_base と対で維持）
├── tests/                      # 配布シェル資産の bats 回帰テスト
├── .claude/                    # 基盤リポ自身のガードレール（権限・フック・skills・agents）
├── .devcontainer/              # 統一開発環境（Ubuntu 24.04 + Claude Code + jq/shellcheck）
├── .github/                    # 基盤の CI と、各プロジェクトが uses: で参照する composite action
├── .vscode/                    # エディタ設定（ファイルネスト等）
├── .ai-dev-foundation-root     # 参照解決の起点マーカー（消すと Make も フックも解決不能になる）
├── .editorconfig               # TAB / UTF-8 / LF の強制
├── .gitignore                  # 追跡除外（projects/ を含む）
├── .req-coverage-baseline      # 未カバー要件の免除リスト（Tier B/C のみ・空が既定）
├── .tier-tripwire-allow        # トリップワイヤ例外の allowlist（空が既定）
├── CLAUDE.md                   # AI駆動開発の共通ルール（全プロジェクトが上位探索で読む正本）
├── LICENSE                     # MIT
├── Makefile                    # 品質ゲートのターゲット契約（make all / test / audit-all …）
├── README.md                   # このファイル
└── SECURITY.md                 # 脆弱性報告の窓口
```

