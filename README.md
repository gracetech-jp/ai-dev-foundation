# AI Dev Foundation

チーム共通のAI駆動開発基盤リポジトリです。

## このリポジトリの役割

- 全サービス共通の開発ルール（CLAUDE.md）の管理
- devcontainer雛形の管理（Windows/Mac差異を吸収）
- 新サービス立ち上げスクリプトの提供

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

## 構成

| パス | 内容 |
|---|---|
| `CLAUDE.md` | AI開発共通ルール |
| `docs/` | 開発規約・設計方針 |
| `templates/` | 新サービス用雛形 |
| `scripts/` | セットアップスクリプト |

