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
mkdir -p "${TARGET}"/{.devcontainer,.claude,docs/rules,docs/service-rules,scripts}

# devcontainer設定をコピー
cp /workspace/templates/.devcontainer/Dockerfile "${TARGET}/.devcontainer/"
cp /workspace/templates/.devcontainer/postCreate.sh "${TARGET}/.devcontainer/"
sed "s/SERVICE_NAME/${SERVICE_NAME}/g" \
  /workspace/templates/.devcontainer/devcontainer.json > "${TARGET}/.devcontainer/devcontainer.json"

# Claude設定をコピー
cp /workspace/templates/.claude/settings.json "${TARGET}/.claude/settings.json"
# Claude skills・SessionStartルール注入スクリプト・危険操作ガードフックを配布
mkdir -p "${TARGET}/.claude/scripts" "${TARGET}/.claude/skills"
cp /workspace/templates/.claude/scripts/session-start-rules.sh "${TARGET}/.claude/scripts/"
cp /workspace/templates/.claude/scripts/guard-dangerous.sh "${TARGET}/.claude/scripts/"
cp -a /workspace/templates/.claude/skills/. "${TARGET}/.claude/skills/"
chmod +x "${TARGET}/.claude/scripts/session-start-rules.sh" "${TARGET}/.claude/scripts/guard-dangerous.sh"

# 共通ルールをそのままコピー
# docs/rules 配下はディレクトリ単位でコピーする（個別指定だと新規ルールの配布漏れが起きるため）
cp /workspace/CLAUDE.md "${TARGET}/CLAUDE.md"
cp /workspace/docs/rules/*.md "${TARGET}/docs/rules/"

# サービス固有ルールの雛形を配布（CLAUDE.md が docs/service-rules/consistency.md を参照するため、
# 雛形が無いと全サービスでリンク切れになる。中身はサービスが自スタックで肉付けする＝逆輸入対象外）
cp /workspace/templates/docs/service-rules/*.md "${TARGET}/docs/service-rules/"

# 品質ゲート一式（Makefile ターゲット契約・pre-push フック・監査スクリプト雛形）を配布
cp /workspace/templates/Makefile "${TARGET}/Makefile"
cp /workspace/templates/scripts/audit-consistency.sh "${TARGET}/scripts/"
cp /workspace/scripts/pre-push "${TARGET}/scripts/"
chmod +x "${TARGET}/scripts/audit-consistency.sh" "${TARGET}/scripts/pre-push"

# 逆輸入プロセス一式を新規サービスへ配布
cp /workspace/scripts/backport-to-common.sh "${TARGET}/scripts/"
cp /workspace/.backport-manifest "${TARGET}/.backport-manifest"
chmod +x "${TARGET}/scripts/backport-to-common.sh"

# SERVICE.mdをテンプレートからコピー
cp /workspace/templates/SERVICE.md.template "${TARGET}/SERVICE.md"
sed -i "s/\[サービス名\]/${SERVICE_NAME}/g" "${TARGET}/SERVICE.md"

# .gitignore
# .claude/ 配下は認証情報・セッションログ等を含むため丸ごとは追跡しないが、
# settings.json・scripts/・skills/ はチーム共有すべき安全な設定なので選択的に追跡対象へ戻す
# （このリポジトリ自身の .gitignore と同じ手法。理由: .claude/ を丸ごとgit管理外にすると
#   guard-dangerous.sh 等の安全設定が新規clone・2人目以降のメンバーに配布されないため）
cat > "${TARGET}/.gitignore" << 'GITIGNORE'
.claude/*
!.claude/settings.json
!.claude/scripts/
!.claude/scripts/**
!.claude/skills/
!.claude/skills/**
.env
node_modules/
dist/
.DS_Store
*.log
CLAUDE.local.md
.backport-backup-*/
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
