#!/bin/bash
set -e
SERVICE_NAME=$1
if [ -z "$SERVICE_NAME" ]; then
  echo "使い方: ./scripts/new-service.sh <サービス名>"
  exit 1
fi
TARGET="$HOME/projects/${SERVICE_NAME}"
if [ -d "$TARGET" ]; then
  echo "エラー: ${TARGET} は既に存在します"
  exit 1
fi
echo "=== ${SERVICE_NAME} の雛形を作成します ==="

# ディレクトリ作成
mkdir -p "${TARGET}"/{.devcontainer,.claude,docs/rules,src}

# devcontainer設定をコピー
cp /workspace/templates/.devcontainer/Dockerfile "${TARGET}/.devcontainer/"
cp /workspace/templates/.devcontainer/postCreate.sh "${TARGET}/.devcontainer/"
sed "s/SERVICE_NAME/${SERVICE_NAME}/g" \
  /workspace/templates/.devcontainer/devcontainer.json > "${TARGET}/.devcontainer/devcontainer.json"

# Claude設定をコピー
cp /workspace/templates/.claude/settings.json "${TARGET}/.claude/settings.json"

# 共通ルールをそのままコピー
cp /workspace/CLAUDE.md "${TARGET}/CLAUDE.md"
cp /workspace/docs/rules/code-style.md "${TARGET}/docs/rules/"
cp /workspace/docs/rules/testing.md "${TARGET}/docs/rules/"
cp /workspace/docs/rules/security.md "${TARGET}/docs/rules/"
cp /workspace/docs/rules/git.md "${TARGET}/docs/rules/"

# SERVICE.mdをテンプレートからコピー
cp /workspace/templates/SERVICE.md.template "${TARGET}/SERVICE.md"
sed -i "s/\[サービス名\]/${SERVICE_NAME}/g" "${TARGET}/SERVICE.md"

# .gitignore
cat > "${TARGET}/.gitignore" << 'GITIGNORE'
.claude/
.env
node_modules/
dist/
.DS_Store
*.log
CLAUDE.local.md
GITIGNORE

# .env.example
cat > "${TARGET}/.env.example" << 'ENVEXAMPLE'
ANTHROPIC_API_KEY=
DATABASE_URL=
ENVEXAMPLE

# README
cat > "${TARGET}/README.md" << README
# ${SERVICE_NAME}

## セットアップ
\`\`\`bash
git clone <repo-url> ~/projects/${SERVICE_NAME}
cd ~/projects/${SERVICE_NAME}
code .
# 「Reopen in Container」をクリック
cp .env.example .env
claude
\`\`\`

## 共通ルール更新時
ai-dev-foundation の CLAUDE.md・docs/rules/ が更新された場合は、
このリポジトリの該当ファイルも手動で同期してください。
README

echo "✅ ~/projects/${SERVICE_NAME} を作成しました"
echo ""
echo "作成されたファイル:"
find "${TARGET}" -not -path '*/.claude/*' | sort
echo ""

# VS Codeで新規ウィンドウとして開く
code "${TARGET}"
