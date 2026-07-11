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
mkdir -p "${TARGET}"/{.devcontainer,.claude,.github/workflows,docs/rules,docs/service-rules,docs/decisions,scripts}

# devcontainer設定をコピー
cp /workspace/templates/.devcontainer/Dockerfile "${TARGET}/.devcontainer/"
cp /workspace/templates/.devcontainer/postCreate.sh "${TARGET}/.devcontainer/"
sed "s/SERVICE_NAME/${SERVICE_NAME}/g" \
  /workspace/templates/.devcontainer/devcontainer.json > "${TARGET}/.devcontainer/devcontainer.json"

# Claude設定をコピー
cp /workspace/templates/.claude/settings.json "${TARGET}/.claude/settings.json"
# Claude skills・サブエージェント・SessionStartルール注入スクリプト・危険操作ガードフックを配布
mkdir -p "${TARGET}/.claude/scripts" "${TARGET}/.claude/skills" "${TARGET}/.claude/agents"
cp /workspace/templates/.claude/scripts/session-start-rules.sh "${TARGET}/.claude/scripts/"
cp /workspace/templates/.claude/scripts/guard-dangerous.sh "${TARGET}/.claude/scripts/"
cp -a /workspace/templates/.claude/skills/. "${TARGET}/.claude/skills/"
cp -a /workspace/templates/.claude/agents/. "${TARGET}/.claude/agents/"
chmod +x "${TARGET}/.claude/scripts/session-start-rules.sh" "${TARGET}/.claude/scripts/guard-dangerous.sh"

# 共通ルールをそのままコピー
# docs/rules 配下はディレクトリ単位でコピーする（個別指定だと新規ルールの配布漏れが起きるため）
cp /workspace/CLAUDE.md "${TARGET}/CLAUDE.md"
# COMMAND.md（Claude Code コマンドリファレンス）はスタック非依存の共通正本。root からコピーし還流対象に含める
cp /workspace/COMMAND.md "${TARGET}/COMMAND.md"
cp /workspace/docs/rules/*.md "${TARGET}/docs/rules/"

# サービス固有ルールの雛形を配布（CLAUDE.md が docs/service-rules/consistency.md を参照するため、
# 雛形が無いと全サービスでリンク切れになる。中身はサービスが自スタックで肉付けする＝逆輸入対象外）
cp /workspace/templates/docs/service-rules/*.md "${TARGET}/docs/service-rules/"
# ADR（意思決定記録）の運用の型を配布（テンプレート＋運用ガイド。基盤固有のADR本体は配らない）
cp /workspace/templates/docs/decisions/*.md "${TARGET}/docs/decisions/"

# 品質ゲート一式（Makefile契約・フック・監査雛形・カバレッジ機構・CIワークフロー）を配布
cp /workspace/templates/Makefile "${TARGET}/Makefile"
cp /workspace/templates/scripts/audit-consistency.sh "${TARGET}/scripts/"
cp /workspace/scripts/pre-push "${TARGET}/scripts/"
cp /workspace/scripts/commit-msg "${TARGET}/scripts/"           # Conventional Commits 検証(中立)
cp /workspace/scripts/check-coverage.sh "${TARGET}/scripts/"    # カバレッジ・ラチェット判定(中立)
cp /workspace/templates/.coverage-floor "${TARGET}/.coverage-floor"  # フロア初期値(サービスがラチェット)
chmod +x "${TARGET}/scripts/audit-consistency.sh" "${TARGET}/scripts/pre-push" \
         "${TARGET}/scripts/commit-msg" "${TARGET}/scripts/check-coverage.sh"
# CIワークフロー（スタック非依存の多段ゲート。詳細: docs/rules/quality-gates.md §4）
cp /workspace/templates/.github/workflows/ci.yml "${TARGET}/.github/workflows/ci.yml"

# 逆輸入プロセス一式を新規サービスへ配布
cp /workspace/scripts/backport-to-common.sh "${TARGET}/scripts/"
cp /workspace/.backport-manifest "${TARGET}/.backport-manifest"
chmod +x "${TARGET}/scripts/backport-to-common.sh"

# SERVICE.mdをテンプレートからコピー
cp /workspace/templates/SERVICE.md.template "${TARGET}/SERVICE.md"
sed -i "s/\[サービス名\]/${SERVICE_NAME}/g" "${TARGET}/SERVICE.md"

# .gitignore / .env.example / README をテンプレートから配布
# （.claude/ 配下は認証情報・セッションログ等を含むため丸ごとは追跡しないが、
#   settings.json・scripts/・skills/ はチーム共有すべき安全な設定なので gitignore テンプレ側で
#   選択的に追跡対象へ戻している。理由: .claude/ を丸ごとgit管理外にすると guard-dangerous.sh 等の
#   安全設定が新規clone・2人目以降のメンバーに配布されないため）
cp /workspace/templates/gitignore.template "${TARGET}/.gitignore"
cp /workspace/templates/.editorconfig "${TARGET}/.editorconfig"
cp /workspace/templates/.env.example "${TARGET}/.env.example"
sed "s/SERVICE_NAME/${SERVICE_NAME}/g" \
  /workspace/templates/README.md.template > "${TARGET}/README.md"

echo "✅ ~/projects/${SERVICE_NAME} を作成しました"
echo ""
echo "作成されたファイル:"
find "${TARGET}" -not -path '*/.claude/*' | sort
echo ""

# VS Codeで新規ウィンドウとして開く
code "${TARGET}"
